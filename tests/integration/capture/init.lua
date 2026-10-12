-- Integration test (T-26): minemon_capture in the assembled game, with no real players.
-- A stone platform at the origin is forceloaded, so the creatures stay active. A fake player (a table with the methods
-- the party and capture code use) drives the flow. Checks: a wild Rattata damaged to 0 becomes exhausted and fires
-- creature_defeated; a forced catch (every shake passes) puts it in the party with owner, ball and bond set, fires
-- creature_captured and removes the entity; a forced failure (the first shake fails) leaves an exhausted Bulbasaur in
-- place, no longer exhausted, with the enraged state for 30 s and not passive; a hit on a wild creature that is not
-- exhausted bounces and does not capture it; the four balls are registered and the Great Ball and Poke Ball recipes
-- craft. Writes PASS n or FAIL <reason> to test_result.txt, then shuts down.
--
-- Not covered here (no real player): the throw entity's flight, the timed shake sequence (capture_logic_spec covers the
-- shake rule), the odds HUD and the starter kit (they need a real inventory and HUD). The Rattata is not used for a
-- failure: its catch rate is 255, so at 0 HP its catch chance is 1 and every shake passes (see the report).
-- luacheck: read_globals core minemon vector

local PLATFORM_Y = 5 -- stone top at y = 5.5; the fake player stands there
local HALF = 6
local TOP_Y = 9
local STONE = "mcl_core:stone"
local NAME = "capture_test_player"
local RATTATA = 19
local BULBASAUR = 1
local CYNDAQUIL = 155

local finished = false
local checks = 0
local defeated = {}
local captured = {}

minemon.events.register("creature_defeated", function(le, _attacker)
	defeated[#defeated + 1] = le
end)
minemon.events.register("creature_captured", function(player, inst)
	captured[#captured + 1] = { player = player, inst = inst }
end)

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

-- The fake player. Methods take self, like the engine's ObjectRef methods. It has no inventory (no get_inventory),
-- so the code that gives items skips it.
local function make_fake()
	local store = {}
	local meta = {
		get_string = function(_, key)
			return store[key] or ""
		end,
		set_string = function(_, key, value)
			store[key] = value
		end,
	}
	local fake = {}
	fake.get_meta = function()
		return meta
	end
	fake.get_player_name = function()
		return NAME
	end
	fake.get_pos = function()
		return vector.new(0, PLATFORM_Y + 0.5, 0)
	end
	fake.get_look_dir = function()
		return vector.new(0, 0, 1)
	end
	fake.is_valid = function()
		return true
	end
	fake.is_player = function()
		return true
	end
	fake.get_guid = function()
		return "capture-test-fake-player"
	end
	return fake
end

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

-- An rng whose float() is always v. 0 passes every shake check; 0.9999 fails the first one.
local function fixed_rng(v)
	return { float = function() return v end }
end

local function wild_at(species_id, x, z)
	local obj = minemon.creatures.spawn(vector.new(x, PLATFORM_Y + 1, z), species_id, 5, nil)
	check(obj ~= nil, "wild spawn failed for species " .. species_id)
	return obj
end

local function run()
	local fake = make_fake()

	-- (1) the balls are registered, with the leading-colon names and the catch rate line
	local poke = core.registered_craftitems["minemon:poke_ball"]
	check(poke ~= nil, "minemon:poke_ball is not registered")
	check(string.find(poke.description, "Catch rate ×1", 1, true) ~= nil,
		"poke ball description has no catch rate line: " .. tostring(poke.description))
	for _, id in ipairs({ "great_ball", "ultra_ball", "master_ball" }) do
		check(core.registered_craftitems["minemon:" .. id] ~= nil, "minemon:" .. id .. " is not registered")
	end
	check(string.find(core.registered_craftitems["minemon:master_ball"].description, "Catch rate ×255", 1, true) ~= nil,
		"master ball description has no ×255 line")

	-- (2) the recipes: a Poké Ball is gold nugget, redstone, gold nugget (gives 2); a Great Ball is a Poké Ball + lapis
	local out = core.get_craft_result({ method = "normal", width = 1,
		items = { "mcl_core:gold_nugget", "mesecons:redstone", "mcl_core:gold_nugget" } })
	check(out and out.item and out.item:get_name() == "minemon:poke_ball", "the Poké Ball recipe does not craft")
	check(out.item:get_count() == 2, "the Poké Ball recipe does not give 2")
	out = core.get_craft_result({ method = "normal", width = 2,
		items = { "minemon:poke_ball", "mcl_dye:blue", "", "" } })
	check(out and out.item and out.item:get_name() == "minemon:great_ball", "the Great Ball recipe does not craft")

	-- (3) the starter: a party with one member, so the party has room for a catch
	local ok, starter = minemon.party.choose_starter(fake, CYNDAQUIL)
	check(ok, "choose_starter failed: " .. tostring(starter))
	check(#minemon.party.get(fake) == 1, "the party does not have the starter")

	-- (4) a wild Rattata damaged to 0 becomes exhausted and fires creature_defeated
	local rattata = wild_at(RATTATA, 0.5, -3)
	local before_defeated = #defeated
	minemon.creatures.damage(rattata, 9999, nil, nil)
	check(minemon.creatures.is_exhausted(rattata), "the Rattata is not exhausted at 0 HP")
	check(#defeated == before_defeated + 1, "creature_defeated did not fire once")
	check(defeated[#defeated].object:get_guid() == rattata:get_guid(), "creature_defeated carries the wrong creature")

	-- (5) a forced catch: every shake passes, so the Rattata joins the party
	local n, caught = minemon.capture._resolve(fake, rattata, "poke_ball", fixed_rng(0))
	check(caught == true, "the forced catch did not catch")
	check(n == 3, "a forced catch did not show 3 shakes: " .. tostring(n))
	local party = minemon.party.get(fake)
	check(#party == 2, "the party did not grow to 2: " .. #party)
	local joined = party[2]
	check(joined.owner == NAME, "the caught creature's owner is " .. tostring(joined.owner))
	check(joined.ball == "poke_ball", "the caught creature's ball is " .. tostring(joined.ball))
	check(joined.bond == 70, "the caught creature's bond is " .. tostring(joined.bond))
	check(joined.hp >= 1, "the caught creature has no HP")
	check(#captured == 1, "creature_captured did not fire once: " .. #captured)
	check(captured[1].inst == joined, "creature_captured carries the wrong instance")
	local le = rattata:get_luaentity()
	check((le and le._removed) or not rattata:is_valid(), "the caught creature's entity is still there")

	-- (6) a forced failure: the first shake fails, so the Bulbasaur breaks free and turns on the thrower
	local bulba = wild_at(BULBASAUR, 2.5, -3)
	minemon.creatures.damage(bulba, 9999, nil, nil)
	check(minemon.creatures.is_exhausted(bulba), "the Bulbasaur is not exhausted at 0 HP")
	local n2, caught2 = minemon.capture._resolve(fake, bulba, "poke_ball", fixed_rng(0.9999))
	check(caught2 == false, "the forced failure caught")
	check(n2 == 0, "a forced failure showed shakes: " .. tostring(n2))
	check(bulba:is_valid(), "the broken-free creature is gone")
	local ble = bulba:get_luaentity()
	check(ble._mm_capturing == nil, "the capturing flag is still set after a failure")
	check(not minemon.creatures.is_exhausted(bulba), "the broken-free creature is still exhausted")
	check(type(ble._mm_enraged_t) == "number" and ble._mm_enraged_t > 0,
		"the broken-free creature is not enraged: " .. tostring(ble._mm_enraged_t))
	check(ble.passive == false, "the broken-free creature is still passive")
	check(#captured == 1, "a failed capture fired creature_captured")
	check(#minemon.party.get(fake) == 2, "a failed capture changed the party")
	check(minemon.creatures.is_owned(bulba) == false, "a broken-free creature became owned")

	-- (7) a hit on a wild creature that is not exhausted bounces: no capture, no change to the party
	local wild = wild_at(RATTATA, -2.5, -3)
	local at = wild:get_pos()
	check(minemon.capture._hit_object(fake, wild, "poke_ball", at) == "bounce",
		"a hit on a healthy wild creature did not bounce")
	check(wild:is_valid() and not minemon.creatures.is_exhausted(wild), "the bounced creature changed state")
	check(#captured == 1, "a bounce fired creature_captured")
	check(#minemon.party.get(fake) == 2, "a bounce changed the party")

	-- (8) a hit on nothing (no object) drops the ball
	check(minemon.capture._hit_object(fake, nil, "poke_ball", at) == "drop", "a hit on nothing did not drop")

	for _, obj in ipairs({ wild, bulba }) do
		if obj:is_valid() then
			obj:remove()
		end
	end
	finish(string.format("PASS %d checks", checks))
end

core.after(1, function()
	local ok, err = pcall(function()
		build_platform()
		run()
	end)
	if not ok then
		finish("FAIL " .. tostring(err))
	end
end)
