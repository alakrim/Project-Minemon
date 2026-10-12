-- Integration test (T-22): minemon_party in the assembled game, with no real players.
-- A stone platform at the origin is forceloaded, so the creatures stay active. A fake player (a table with the
-- methods the party code uses: get_meta, get_player_name, get_pos, get_look_dir, is_valid, is_player, get_guid)
-- drives the flow. Checks: the starter choice (level 5, saved in player meta, one starter only); send_out spawns an
-- owned creature near the player, and the entity carries the party member (same uid); an own creature cannot be
-- ordered, a wild one can; a hit lowers the member's HP through the damage path; recall writes that HP back and
-- get_active is nil; a fainted creature keeps HP 0 in the list and in meta, get_active is nil and the lead moves on;
-- send_out with no index sends the lead; the owned brain is registered (a second "owned" is refused); heal_all
-- restores every member. Writes PASS n or FAIL <reason> to test_result.txt, then shuts down.
-- Not covered here (no real player): the HUD, formspecs, the Party Ball clicks, regeneration timing (party_logic_spec
-- covers the rules), the 5 s save cadence, and the owner-offline recall (the brain checks is_valid on the owner).
-- luacheck: read_globals core minemon vector

local PLATFORM_Y = 5 -- stone top at y = 5.5; the fake player stands there
local HALF = 6
local TOP_Y = 9
local STONE = "mcl_core:stone"
local NAME = "party_test_player"
local RATTATA = 19
local BULBASAUR = 1
local CYNDAQUIL = 155

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

-- The fake player. Methods take self, like the engine's ObjectRef methods.
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
		return "party-test-fake-player"
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

local function max_hp(inst)
	local sp = minemon.data.get_species(inst.species_id)
	return minemon.instance.stats(inst, sp).hp
end

local function meta_members(fake)
	local raw = fake:get_meta():get_string("minemon:party:list")
	check(raw ~= "", "party list is not in player meta")
	local parsed = core.parse_json(raw)
	check(type(parsed) == "table", "party list in meta is not JSON")
	return parsed
end

local function run()
	local fake = make_fake()
	local rng = minemon.rng.new(777)

	-- (1) the starter choice
	local ok, first = minemon.party.choose_starter(fake, CYNDAQUIL)
	check(ok, "choose_starter failed: " .. tostring(first))
	check(first.level == 5, "starter level is " .. tostring(first.level))
	check(first.species_id == CYNDAQUIL, "starter species is " .. tostring(first.species_id))
	check(first.owner == NAME, "starter owner is " .. tostring(first.owner))
	check(#minemon.party.get(fake) == 1, "party has " .. #minemon.party.get(fake) .. " members after the starter")
	check(minemon.party.choose_starter(fake, BULBASAUR) == false, "a second starter must be refused")
	check(meta_members(fake)[1].uid == first.uid, "the starter is not saved in meta")

	-- (2) a second member, so that the party has two
	local second = minemon.instance.new(minemon.data.get_species(BULBASAUR), 5, rng)
	second.owner = NAME
	minemon.party.set(fake, { first, second })
	check(#minemon.party.get(fake) == 2, "set did not keep two members")
	check(minemon.party.lead_index(fake) == 1, "the lead is not the first member")

	-- (3) send_out spawns the lead next to the player, owned, and the entity carries the member
	local sent, why = minemon.party.send_out(fake, 1)
	check(sent, "send_out failed: " .. tostring(why))
	local obj = minemon.party.get_active(fake)
	check(obj ~= nil, "get_active is nil after send_out")
	check(minemon.creatures.is_owned(obj), "the sent creature is not owned")
	check(minemon.creatures.owner_name(obj) == NAME, "owner_name is " .. tostring(minemon.creatures.owner_name(obj)))
	local inst = minemon.creatures.get_instance(obj)
	check(inst and inst.uid == first.uid, "the entity does not carry the party member")
	check(vector.distance(obj:get_pos(), fake:get_pos()) <= 3.5, "the creature was not sent out near the player")
	check(minemon.party.send_out(fake, 1) == false, "a second send_out must be refused")

	-- (4) order rules: an own creature cannot be ordered; a wild one can
	check(minemon.party.order(fake, obj) == false, "an own creature was ordered")
	local wild = minemon.creatures.spawn(vector.new(0.5, PLATFORM_Y + 1, -3), RATTATA, 5, nil)
	check(wild ~= nil, "wild spawn failed")
	check(minemon.party.order(fake, wild) == true, "a wild creature could not be ordered")

	-- (5) a hit lowers the member's HP through the damage path
	local before = inst.hp
	minemon.creatures.damage(obj, 3, nil, nil)
	check(inst.hp == before - 3, "damage did not lower the member's HP: " .. inst.hp .. " from " .. before)

	-- (6) recall writes the HP back and clears the active creature
	check(minemon.party.recall(fake) == true, "recall returned false")
	check(minemon.party.get_active(fake) == nil, "get_active is not nil after recall")
	check(minemon.party.get(fake)[1].hp == before - 3, "recall did not keep the HP")
	check(meta_members(fake)[1].hp == before - 3, "the recalled HP is not in meta")

	-- (7) a fainted creature: HP 0 in the list and in meta, no active creature, the lead moves on
	local ok3, why3 = minemon.party.send_out(fake, 2)
	check(ok3, "send_out of the second member failed: " .. tostring(why3))
	local obj2 = minemon.party.get_active(fake)
	check(obj2 ~= nil, "second member not active")
	minemon.creatures.damage(obj2, 9999, nil, nil)
	check(minemon.party.get_active(fake) == nil, "get_active is not nil after a faint")
	check(minemon.party.get(fake)[2].hp == 0, "fainted member does not have HP 0")
	check(meta_members(fake)[2].hp == 0, "fainted HP is not in meta")
	check(minemon.party.lead_index(fake) == 1, "the lead did not stay on the living member")

	-- (8) send_out without an index sends the lead (the first living member)
	local ok4, why4 = minemon.party.send_out(fake, nil)
	check(ok4, "send_out with the lead failed: " .. tostring(why4))
	local lead = minemon.party.get_active(fake)
	check(lead ~= nil and minemon.creatures.get_instance(lead).uid == first.uid, "the lead was not sent out")
	check(minemon.party.recall(fake) == true, "recall of the lead failed")

	-- (9) the owned brain is registered: a second "owned" is refused
	local reg_ok, reg_err = pcall(minemon.creatures.register_brain, "owned", function() end)
	check(reg_ok == false and tostring(reg_err):find("already registered", 1, true) ~= nil,
		"the owned brain is not registered: " .. tostring(reg_err))

	-- (10) heal_all restores every member
	minemon.party.heal_all(fake)
	local healed = minemon.party.get(fake)
	check(healed[2].hp == max_hp(healed[2]), "heal_all did not heal the fainted member")
	check(healed[1].hp == max_hp(healed[1]), "heal_all did not heal the first member")
	check(meta_members(fake)[2].hp == max_hp(healed[2]), "healed HP is not in meta")

	if wild and wild:get_pos() then
		wild:remove()
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
