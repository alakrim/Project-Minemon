-- Integration test (T-24): the creature runtime hooks in the assembled game.
-- A flat stone platform is built at the origin, so the test does not depend on the world's terrain.
-- Checks: the single damage path keeps the entity HP and the instance HP equal; a punch from a dummy entity goes
-- through do_punch (the attacker is reported, and the HP drops by exactly the punch damage); a wild creature at 0 HP
-- becomes exhausted and still exists after 2 s; exhausted creatures ignore damage; the exhaustion ends after 20 s
-- with 25% HP and a flee state; a brain runs; an owned creature at 0 HP fires creature_fainted and is removed when
-- no handler does it. Writes PASS n or FAIL <reason> to test_result.txt, then shuts down.
-- luacheck: read_globals core minemon vector

local PLATFORM_Y = 5 -- stone top at y = 5; creatures stand at y = 6
local HALF = 6 -- platform spans -6..6 in x and z
local TOP_Y = 9 -- air above the platform up to this y
local STONE = "mcl_core:stone"
local RATTATA = 19
local DUMMY = "creatures_runtime_test:dummy"
local EXHAUST_WAIT = 21 -- seconds after exhaustion starts (20 s exhaustion plus margin)

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

local function fail_on_error(fn)
	return function(...)
		local ok, err = pcall(fn, ...)
		if not ok then
			finish("FAIL " .. tostring(err))
		end
	end
end

-- Dummy punching entity: no visuals, never moves.
core.register_entity(DUMMY, {
	initial_properties = {
		physical = false,
		pointable = false,
		visual = "sprite",
		textures = { "blank.png" },
		collisionbox = { -0.1, -0.1, -0.1, 0.1, 0.1, 0.1 },
	},
})

-- Brain: counts the calls made for the creature named in brain_target (set by the test).
local brain_target = nil
local brain_calls = 0
minemon.creatures.register_brain("creatures_runtime_test", function(self, _dtime)
	if brain_target and self.object:get_guid() == brain_target then
		brain_calls = brain_calls + 1
	end
	return nil
end)

-- Event log: creature_hurt and creature_fainted handlers record what they see.
local hurt = {}
local fainted = {}
minemon.events.register("creature_hurt", function(obj, amount, attacker, _info)
	hurt[#hurt + 1] = { guid = obj:get_guid(), amount = amount, attacker = attacker and attacker:get_guid() or nil }
end)
minemon.events.register("creature_fainted", function(obj, owner)
	fainted[#fainted + 1] = { guid = obj:get_guid(), owner = owner }
end)

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

local wild, wild_inst, wild_max
local punched, punched_inst, punched_max
local owned

local function instance_max(inst)
	local sp = minemon.data.get_species(inst.species_id)
	return minemon.instance.stats(inst, sp).hp
end

-- Step 1: the single damage path keeps the entity and the instance in step.
local function step_damage()
	wild = minemon.creatures.spawn(vector.new(0, PLATFORM_Y + 1, 0), RATTATA, 7, nil)
	check(wild, "wild spawn failed")
	wild_inst = minemon.creatures.get_instance(wild)
	check(wild_inst, "no instance on the wild creature")
	local le = wild:get_luaentity()
	wild_max = instance_max(wild_inst)
	check(wild_inst.hp == wild_max, "fresh creature is not at full HP")
	check(le.health == wild_inst.hp, "entity health differs from instance HP at spawn")

	local dealt = minemon.creatures.damage(wild, 3, nil, {})
	check(dealt == 3, "damage 3 dealt " .. tostring(dealt))
	check(wild_inst.hp == wild_max - 3, "instance HP is " .. wild_inst.hp .. ", want " .. (wild_max - 3))
	check(le.health == wild_inst.hp, "entity health " .. tostring(le.health) .. " ~= instance HP " .. wild_inst.hp)
	check(wild:get_hp() == wild_inst.hp, "engine HP " .. wild:get_hp() .. " ~= instance HP " .. wild_inst.hp)
	check(#hurt >= 1 and hurt[#hurt].amount == 3, "creature_hurt not fired with amount 3")

	-- mcl_mobs subtracts self.health directly on a fall, then calls check_for_death. The guard must sync it.
	le.health = le.health - 2
	le:check_for_death("fall", { type = "fall" })
	check(wild_inst.hp == wild_max - 5, "direct mcl subtraction not synced: instance HP " .. wild_inst.hp)
	check(le.health == wild_inst.hp, "after sync entity health " .. tostring(le.health) .. " ~= " .. wild_inst.hp)
end

-- Step 2: a punch from the dummy goes through do_punch, not mcl's own subtraction.
local function step_punch()
	punched = minemon.creatures.spawn(vector.new(2, PLATFORM_Y + 1, 0), RATTATA, 7, nil)
	check(punched, "punch target spawn failed")
	punched_inst = minemon.creatures.get_instance(punched)
	punched_max = instance_max(punched_inst)
	brain_target = punched:get_guid()
	local dummy = core.add_entity(vector.new(0, PLATFORM_Y + 1, 2), DUMMY)
	check(dummy, "dummy spawn failed")
	local hurt_before = #hurt
	punched:punch(dummy, 1.0, { full_punch_interval = 1.0, damage_groups = { fleshy = 2 } }, nil)
	check(punched_inst.hp == punched_max - 2, "punch: instance HP " .. punched_inst.hp .. ", want " .. (punched_max - 2))
	check(punched:get_luaentity().health == punched_inst.hp, "punch: entity health differs from instance HP")
	check(#hurt == hurt_before + 1, "punch: creature_hurt not fired once")
	check(hurt[#hurt].attacker == dummy:get_guid(), "punch: attacker is not the dummy")
	check(hurt[#hurt].amount == 2, "punch: creature_hurt amount " .. tostring(hurt[#hurt].amount))
	dummy:remove()
end

-- Step 3: zero HP makes a wild creature exhausted; damage is ignored while exhausted.
local function step_exhaust()
	local le = wild:get_luaentity()
	minemon.creatures.damage(wild, 9999, nil, {})
	check(wild_inst.hp == 0, "exhausted: instance HP " .. wild_inst.hp .. ", want 0")
	check(minemon.creatures.is_exhausted(wild), "wild creature at 0 HP is not exhausted")
	check(le.health == 0, "exhausted: entity health " .. tostring(le.health))
	check(wild:get_hp() == 1, "exhausted: engine HP should stay at 1, got " .. wild:get_hp())
	check(string.sub(le.nametag, -#" (exhausted)") == " (exhausted)", "exhausted: no nametag suffix")
	check(le.passive == true, "exhausted: passive is not true")
	check(le.attack == nil, "exhausted: attack is not nil")
	check(le.state == "stand", "exhausted: state is " .. tostring(le.state))
	check(minemon.creatures.damage(wild, 5, nil, {}) == 0, "exhausted creature took damage")
	check(wild_inst.hp == 0, "exhausted creature HP changed")
	check(minemon.creatures.is_owned(wild) == false, "wild creature reported as owned")
end

-- Step 4: after 2 s the exhausted creature still exists and is still exhausted.
local function step_still_there()
	check(wild:get_pos() ~= nil, "exhausted creature removed within 2 s")
	check(wild:get_luaentity()._removed ~= true, "exhausted creature marked removed")
	check(minemon.creatures.is_exhausted(wild), "exhausted flag lost after 2 s")
	check(wild_inst.hp == 0, "exhausted HP changed after 2 s")
	check(brain_calls > 0, "the brain was never called for the punch target")
end

-- Step 5: an owned creature at 0 HP fires creature_fainted; with no handler removing it, it is removed after 0.5 s.
local function step_faint()
	owned = minemon.creatures.spawn(vector.new(4, PLATFORM_Y + 1, -4), RATTATA, 12, "tester")
	check(owned, "owned spawn failed")
	check(minemon.creatures.is_owned(owned), "owned creature not reported as owned")
	check(minemon.creatures.owner_name(owned) == "tester", "owner_name is wrong")
	local fainted_before = #fainted
	minemon.creatures.damage(owned, 9999, nil, {})
	check(#fainted == fainted_before + 1, "creature_fainted not fired")
	check(fainted[#fainted].guid == owned:get_guid(), "creature_fainted for the wrong object")
	check(fainted[#fainted].owner == "tester", "creature_fainted owner is " .. tostring(fainted[#fainted].owner))
	check(not minemon.creatures.is_exhausted(owned), "owned creature became exhausted")
	check(owned:get_pos() ~= nil, "owned creature removed before the 0.5 s grace")
end

local function step_faint_removed()
	check(owned:get_pos() == nil and not owned:is_valid(), "fainted owned creature still present after 0.5 s")
end

-- Step 6: after the exhaustion time, the creature recovers: 25% HP, passive from the temperament, flees.
local function step_recover()
	local le = wild:get_luaentity()
	check(not minemon.creatures.is_exhausted(wild), "still exhausted after the exhaustion time")
	check(wild_inst.hp == math.floor(wild_max * 0.25), "recovered HP is " .. wild_inst.hp
		.. ", want " .. math.floor(wild_max * 0.25))
	check(le.health == wild_inst.hp, "recovered entity health differs from instance HP")
	check(le.state == "runaway", "recovered state is " .. tostring(le.state))
	local sp = minemon.data.get_species(RATTATA)
	local hostile = sp.temperament == "aggressive" or sp.temperament == "territorial"
	check(le.passive == (not hostile), "recovered passive is wrong for " .. sp.temperament)
	check(string.sub(le.nametag, -#" (exhausted)") ~= " (exhausted)", "recovered nametag keeps the suffix")
	check(le.health > 0 and wild:get_pos() ~= nil, "recovered creature is gone")
end

local function passed()
	finish(string.format("PASS %d checks; hurt events=%d; brain calls=%d", checks, #hurt, brain_calls))
end

-- Times are seconds after the previous step. Exhaustion starts in the first step (T1); the creature must still be
-- exhausted at T1 + 19 and recovered at T1 + 21 (the exhaustion lasts 20 s).
local steps = {
	{ 0.5, function()
		build_platform()
		step_damage()
		step_punch()
		step_exhaust()
	end },
	{ 2, function()
		step_still_there()
		step_faint()
	end },
	{ 1, function()
		step_faint_removed()
	end },
	{ 16, function()
		check(minemon.creatures.is_exhausted(wild), "exhaustion ended before 20 s")
	end },
	{ EXHAUST_WAIT - 19, function()
		step_recover()
		passed()
	end },
}

local function run_steps(i)
	local step = steps[i]
	if not step then
		return
	end
	core.after(step[1], fail_on_error(function()
		if finished then
			return
		end
		step[2]()
		run_steps(i + 1)
	end))
end

-- Emerge the platform area first, then run the steps. Runs once.
core.after(1, function()
	core.emerge_area(vector.new(-HALF - 2, PLATFORM_Y - 2, -HALF - 2), vector.new(HALF + 2, TOP_Y + 2, HALF + 2),
		function(_, _, calls_remaining)
			if calls_remaining ~= 0 then
				return
			end
			local ok, err = pcall(function()
				check(core.registered_nodes[STONE], "stone node " .. STONE .. " is not registered")
				run_steps(1)
			end)
			if not ok then
				finish("FAIL " .. tostring(err))
			end
		end)
end)
