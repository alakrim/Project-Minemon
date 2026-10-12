-- Integration test (T-21b): the wild brain in the assembled game.
-- A flat stone platform is built at the origin. The players and their active creatures come from the brain's
-- injectable sources (minemon.creatures.wild.sources), because a headless server has no players and T-22 may not be
-- loaded. Checks:
--   A  an aggressive wild Rattata with a player in view and the player's Cyndaquil within 16 nodes attacks the
--      Cyndaquil (the attack target is the Cyndaquil within 3 s), and its melee damage and bite period are the
--      tuned values for its instance stats;
--   B  a skittish Pidgey hit by a creature goes into the runaway state within 2.5 s;
--   C  20 mixed wild creatures run for 10 s: the brain thinks, makes no errors, and none is lost.
-- Writes PASS n or FAIL <reason> to test_result.txt, then shuts down.
-- luacheck: read_globals core minemon vector

local PLATFORM_Y = 5 -- stone top at y = 5; creatures stand at y = 6
local HALF = 8 -- platform spans -8..8 in x and z
local TOP_Y = 9 -- air above the platform up to this y
local STONE = "mcl_core:stone"
local RATTATA, PIDGEY, CYNDAQUIL = 19, 16, 155
local TOTAL_SECONDS = 10 -- the mixed run
local MIXED_IDS = { 19, 20, 21, 16, 92, 95, 155, 4, 1, 143, 25, 133, 122, 152, 7, 66, 98, 56, 43, 209 }

local finished = false
local checks = 0

local function finish(line)
	if finished then
		return
	end
	finished = true
	core.safe_file_write(core.get_worldpath() .. "/test_result.txt", line .. "\n")
	core.request_shutdown()
end

local function check(cond, msg)
	checks = checks + 1
	if not cond then
		error(msg, 0)
	end
end

local function guarded(fn)
	return function(...)
		local ok, err = pcall(fn, ...)
		if not ok then
			finish("FAIL " .. tostring(err))
		end
	end
end

local function close(a, b)
	return math.abs(a - b) < 1e-6
end

-- The tuning the brain must apply (T-21b brief): damage max(2, floor(1.5 + level*0.15 + atk/20 + 0.5)) and the bite
-- period 1.2 - spe/200, at least 0.5.
local function expected_damage(level, atk)
	return math.max(2, math.floor(1.5 + level * 0.15 + atk / 20 + 0.5))
end

local function expected_period(spe)
	return math.max(0.5, 1.2 - spe / 200)
end

-- Polls cond every 0.25 s for up to timeout seconds. Calls next() when it holds, else fails with msg.
local function wait_for(cond, timeout, msg, next_fn)
	local waited = 0
	local function poll()
		if cond() then
			next_fn()
			return
		end
		waited = waited + 0.25
		if waited >= timeout then
			finish("FAIL " .. msg)
			return
		end
		core.after(0.25, guarded(poll))
	end
	poll()
end

-- A stand-in for a player: only get_pos is used by the brain (a player is never a hunt target in this test).
local FAKE_POS = vector.new(0, PLATFORM_Y + 1, 0)
local fake_player = {
	get_pos = function()
		return FAKE_POS
	end,
	get_player_name = function()
		return "fake_player"
	end,
	is_player = function()
		return true
	end,
	is_valid = function()
		return true
	end,
	get_guid = function()
		return "fake_player"
	end,
}

local wild = minemon.creatures.wild
check(wild ~= nil, "minemon.creatures.wild is missing (the brain is not exported)")

local function set_players(list)
	wild.set_sources(function()
		return list
	end, nil)
end

-- Stone platform with air above it, forceloaded, so the creatures stay active.
local function build_platform()
	for x = -HALF, HALF do
		for z = -HALF, HALF do
			core.set_node(vector.new(x, PLATFORM_Y, z), { name = STONE })
			for y = PLATFORM_Y + 1, TOP_Y do
				core.set_node(vector.new(x, y, z), { name = "air" })
			end
		end
	end
	for _, p in ipairs({ { -HALF, -HALF }, { HALF, -HALF }, { -HALF, HALF }, { HALF, HALF } }) do
		check(core.forceload_block(vector.new(p[1], PLATFORM_Y, p[2]), true, 256), "forceload failed")
	end
end

local rattata, rattata_le, cyndaquil, pidgey, pidgey_le
local mixed = {}
local step_b, step_c -- forward declarations: the steps call each other in order

-- Step A: the Rattata attacks the player's Cyndaquil, and the tuning is applied.
local function step_a()
	cyndaquil = minemon.creatures.spawn(vector.new(-2, PLATFORM_Y + 1, 3), CYNDAQUIL, 10, "tester")
	check(cyndaquil, "owned Cyndaquil spawn failed")
	check(minemon.creatures.is_owned(cyndaquil), "Cyndaquil is not owned")
	rattata = minemon.creatures.spawn(vector.new(3, PLATFORM_Y + 1, 0), RATTATA, 7, nil)
	check(rattata, "wild Rattata spawn failed")
	rattata_le = rattata:get_luaentity()
	local cyn = cyndaquil
	wild.set_sources(function()
		return { fake_player }
	end, function(p)
		if p == fake_player then
			return cyn
		end
		return nil
	end)
	wait_for(function()
		local target = rattata_le.attack
		return target ~= nil and target:is_valid() and target:get_guid() == cyn:get_guid()
	end, 3, "the wild Rattata did not attack the player's Cyndaquil within 3 s", function()
		check(rattata_le.state == "attack", "Rattata state is " .. tostring(rattata_le.state))
		local inst = minemon.creatures.get_instance(rattata)
		local sp = minemon.data.get_species(RATTATA)
		local st = minemon.instance.stats(inst, sp)
		check(rattata_le.damage == expected_damage(inst.level, st.atk), "Rattata damage " .. tostring(rattata_le.damage)
			.. ", want " .. expected_damage(inst.level, st.atk))
		check(close(rattata_le.attack_frequency, expected_period(st.spe)), "Rattata bite period "
			.. tostring(rattata_le.attack_frequency) .. ", want " .. expected_period(st.spe))
		core.after(0, guarded(step_b))
	end)
end

-- Step B: a skittish Pidgey hit by a creature runs away. No players are listed, so only the hit makes it flee.
step_b = function()
	set_players({})
	pidgey = minemon.creatures.spawn(vector.new(-4, PLATFORM_Y + 1, -4), PIDGEY, 5, nil)
	check(pidgey, "wild Pidgey spawn failed")
	pidgey_le = pidgey:get_luaentity()
	local dealt = minemon.creatures.damage(pidgey, 2, cyndaquil, {})
	check(dealt == 2, "Pidgey took " .. tostring(dealt) .. " damage, want 2")
	wait_for(function()
		return pidgey_le.state == "runaway"
	end, 2.5, "the hurt skittish Pidgey did not enter the runaway state within 2.5 s", function()
		check(pidgey:get_pos() ~= nil, "Pidgey disappeared")
		core.after(0, guarded(step_c))
	end)
end

-- Step C: 20 mixed wild creatures for 10 s. No player is listed, so the brain thinks but does not hunt.
step_c = function()
	local before = wild.stats()
	local grid = { -6, -3, 0, 3, 6 }
	local i = 0
	for _, x in ipairs(grid) do
		for _, z in ipairs(grid) do
			if i < 20 then
				i = i + 1
				local id = MIXED_IDS[i]
				local obj = minemon.creatures.spawn(vector.new(x, PLATFORM_Y + 1, z), id, 3 + (i * 3) % 18, nil)
				check(obj, "mixed spawn " .. i .. " (species " .. id .. ") failed")
				mixed[#mixed + 1] = obj
			end
		end
	end
	check(#mixed == 20, "spawned " .. #mixed .. " mixed creatures, want 20")
	core.after(TOTAL_SECONDS, guarded(function()
		local after = wild.stats()
		local alive = 0
		for _, obj in ipairs(mixed) do
			if obj:get_pos() ~= nil then
				alive = alive + 1
			end
		end
		local thinks = after.thinks - before.thinks
		check(after.errors == 0, "the wild brain raised " .. after.errors .. " errors")
		check(thinks >= 100, "only " .. thinks .. " brain thinks in " .. TOTAL_SECONDS .. " s (want >= 100)")
		check(alive == 20, "only " .. alive .. " of 20 mixed creatures are still there after " .. TOTAL_SECONDS .. " s")
		finish(string.format("PASS %d checks; brain thinks=%d errors=%d; mixed alive=%d/20",
			checks, thinks, after.errors, alive))
	end))
end

core.after(1, function()
	core.emerge_area(vector.new(-HALF - 2, PLATFORM_Y - 2, -HALF - 2), vector.new(HALF + 2, TOP_Y + 2, HALF + 2),
		function(_, _, calls_remaining)
			if calls_remaining ~= 0 then
				return
			end
			local ok, err = pcall(function()
				check(core.registered_nodes[STONE], "stone node " .. STONE .. " is not registered")
				build_platform()
				step_a()
			end)
			if not ok then
				finish("FAIL " .. tostring(err))
			end
		end)
end)
