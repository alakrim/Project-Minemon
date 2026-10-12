-- Integration test (T-27): minemon_growth in the assembled game, with no real players.
-- A stone platform at the origin is forceloaded, so the creatures stay active. A fake player (as in
-- tests/integration/party, plus an inventory) drives the flow. Checks:
--  (1) exp from creature_defeated (the active creature as attacker): a Bulbasaur at Lv 15 with exp one below Lv 16
--      reaches 16, bond 3, a larger max HP, the HP fraction kept, and the evolution cinematic starts;
--  (2) "Stop it!" ends the cinematic and keeps Bulbasaur;
--  (3) _evolve_now to Ivysaur (2): same uid, species 2 in the party list, sent out again, creature_evolved fired, and
--      no learn prompt (the new species' moves at Lv 16 are all known);
--  (4) a Thunder Stone on the lead Pikachu gives Raichu and takes the stone;
--  (5) a Link Cable on Kadabra gives Alakazam and takes the cable;
--  (6) Poliwhirl: a Link Cable without the King's Rock does nothing and keeps the cable; with the rock it gives
--      Politoed and takes both;
--  (7) learn prompts: a free slot learns at once; at 4 moves two prompts queue; a replace takes the slot; closing the
--      second counts as "Don't learn";
--  (8) bond -5 on faint (the real faint path);
--  (9) every evolution item is registered as minemon:<id>, the Link Cable costs 2100, and the bond hearts hook works.
-- Writes PASS n or FAIL <reason> to test_result.txt, then shuts down.
-- luacheck: read_globals core minemon vector

local PLATFORM_Y = 5 -- stone top at y = 5.5; the fake player stands there
local HALF = 6
local TOP_Y = 9
local STONE = "mcl_core:stone"
local NAME = "growth_test_player"
local BULBASAUR = 1
local IVYSAUR = 2
local RATTATA = 19
local PIKACHU = 25
local RAICHU = 26
local KADABRA = 64
local ALAKAZAM = 65
local POLIWHIRL = 61
local POLITOED = 186

local EVO_ITEMS = {
	"fire_stone", "leaf_stone", "moon_stone", "sun_stone", "thunder_stone", "water_stone",
	"dragon_scale", "king_s_rock", "metal_coat", "up_grade", "link_cable",
}

local finished = false
local checks = 0
local evolved_events = {}

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

-- The fake player: the party test's methods, plus an inventory with contains_item, add_item and remove_item.
local items = {} -- "minemon:<id>" -> count
local function count(id)
	return items["minemon:" .. id] or 0
end
local function give(id)
	items["minemon:" .. id] = count(id) + 1
end

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
	local inv = {}
	inv.contains_item = function(_, _list, item)
		return (items[item] or 0) > 0
	end
	inv.add_item = function(_, _list, item)
		items[item] = (items[item] or 0) + 1
	end
	inv.remove_item = function(_, _list, item)
		if (items[item] or 0) > 0 then
			items[item] = items[item] - 1
		end
	end
	local fake = {}
	fake.get_meta = function()
		return meta
	end
	fake.get_inventory = function()
		return inv
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
		return "growth-test-fake-player"
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

local function species(id)
	return minemon.data.get_species(id)
end

local function new_member(id, level, rng, bond)
	local m = minemon.instance.new(species(id), level, rng)
	m.owner = NAME
	m.bond = bond or 0
	return m
end

local function lead(fake)
	return minemon.party.get(fake)[1]
end

local function run()
	local fake = make_fake()
	local rng = minemon.rng.new(4242)

	minemon.events.register("creature_evolved", function(player, inst, old_id)
		evolved_events[#evolved_events + 1] = { player = player, uid = inst.uid, old = old_id, now = inst.species_id }
	end)

	-- (1) exp from creature_defeated, with the active creature as the attacker
	local bulb = new_member(BULBASAUR, 15, rng)
	bulb.exp = minemon.formulas.exp_for_level(16, species(BULBASAUR).growth_rate) - 1
	minemon.party.set(fake, { bulb })
	local sent, why = minemon.party.send_out(fake, 1)
	check(sent, "send_out failed: " .. tostring(why))
	local obj = minemon.party.get_active(fake)
	check(obj ~= nil, "Bulbasaur is not out")
	minemon.creatures.damage(obj, 3, nil, nil)
	local hp_before = lead(fake).hp
	local old_max = minemon.instance.stats(lead(fake), species(BULBASAUR)).hp

	local victim = minemon.instance.new(species(RATTATA), 10, rng)
	minemon.events.fire("creature_defeated", { _mm = victim, name = "minemon_creatures:rattata" }, obj)

	local m = lead(fake)
	check(m.level == 16, "level after the defeat is " .. tostring(m.level) .. ", expected 16")
	check(m.bond == 3, "bond after the level-up is " .. tostring(m.bond) .. ", expected 3")
	check(m.exp >= minemon.formulas.exp_for_level(16, species(BULBASAUR).growth_rate), "exp was not added")
	local new_max = minemon.instance.stats(m, species(BULBASAUR)).hp
	check(new_max > old_max, "max HP did not grow: " .. old_max .. " -> " .. new_max)
	local expected_hp = math.ceil(hp_before * new_max / old_max)
	check(m.hp == expected_hp, "HP fraction not kept: " .. m.hp .. ", expected " .. expected_hp)
	check(minemon.growth._cinematic(NAME) ~= nil, "no evolution cinematic at level 16 (min_level 16 holds)")

	-- (2) Stop it! ends the cinematic and keeps Bulbasaur
	minemon.growth._answer_evolve(fake, { stop = "Stop it!" })
	check(minemon.growth._cinematic(NAME) == nil, "Stop it! did not end the cinematic")
	check(lead(fake).species_id == BULBASAUR, "stopping the cinematic changed the species")

	-- (3) the evolution to Ivysaur keeps the uid, sends out again, fires the event, and offers no move prompt
	local uid = lead(fake).uid
	check(minemon.growth._evolve_now(fake, uid, IVYSAUR), "_evolve_now to Ivysaur failed")
	check(lead(fake).species_id == IVYSAUR, "the party list does not show Ivysaur")
	check(lead(fake).uid == uid, "the uid changed in the evolution")
	local active = minemon.party.get_active(fake)
	check(active ~= nil, "the evolved creature was not sent out again")
	check(minemon.creatures.get_instance(active).species_id == IVYSAUR, "the entity is not Ivysaur")
	minemon.party.recall(fake)
	check(#evolved_events == 1, "creature_evolved fired " .. #evolved_events .. " times")
	check(evolved_events[1].old == BULBASAUR and evolved_events[1].now == IVYSAUR, "creature_evolved has wrong ids")
	check(minemon.growth._pending(NAME) == 0, "Ivysaur at Lv 16 queued learn prompts")

	-- (4) a Thunder Stone on the lead Pikachu gives Raichu and takes the stone
	local pika = new_member(PIKACHU, 20, rng)
	minemon.party.set(fake, { pika })
	give("thunder_stone")
	check(minemon.growth._use_item_now(fake, "thunder_stone"), "a Thunder Stone had no effect on Pikachu")
	check(lead(fake).species_id == RAICHU, "Pikachu did not become Raichu")
	check(lead(fake).uid == pika.uid, "the uid changed with the stone")
	check(count("thunder_stone") == 0, "the Thunder Stone was not taken")

	-- (5) a Link Cable on Kadabra gives Alakazam and takes the cable
	minemon.party.set(fake, { new_member(KADABRA, 36, rng) })
	give("link_cable")
	check(minemon.growth._use_item_now(fake, "link_cable"), "a Link Cable had no effect on Kadabra")
	check(lead(fake).species_id == ALAKAZAM, "Kadabra did not become Alakazam")
	check(count("link_cable") == 0, "the Link Cable was not taken")

	-- (6) Poliwhirl: the cable alone does nothing; with the King's Rock it gives Politoed and takes both
	minemon.party.set(fake, { new_member(POLIWHIRL, 30, rng) })
	give("link_cable")
	check(minemon.growth._use_item_now(fake, "link_cable") == false, "a Link Cable evolved Poliwhirl without the rock")
	check(lead(fake).species_id == POLIWHIRL, "Poliwhirl changed without the rock")
	check(count("link_cable") == 1, "the cable was taken without an evolution")
	give("king_s_rock")
	check(minemon.growth._use_item_now(fake, "link_cable"), "Poliwhirl did not evolve with the rock")
	check(lead(fake).species_id == POLITOED, "Poliwhirl did not become Politoed")
	check(count("link_cable") == 0 and count("king_s_rock") == 0, "the cable or the rock was not taken")

	-- (7) learn prompts: Bulbasaur at 14 with four moves; reaching 15 offers Poison Powder and Sleep Powder
	local bulb14 = new_member(BULBASAUR, 14, rng)
	bulb14.moves = {
		{ id = "tackle", pp = 35 }, { id = "growl", pp = 40 },
		{ id = "leech_seed", pp = 10 }, { id = "vine_whip", pp = 25 },
	}
	minemon.party.set(fake, { bulb14 })
	local gain = minemon.formulas.exp_for_level(15, species(BULBASAUR).growth_rate)
		- minemon.formulas.exp_for_level(14, species(BULBASAUR).growth_rate)
	minemon.growth.grant_exp(fake, bulb14.uid, gain)
	check(lead(fake).level == 15, "Bulbasaur is at " .. lead(fake).level .. ", expected 15")
	check(minemon.growth._pending(NAME) == 2, "expected 2 learn prompts, got " .. minemon.growth._pending(NAME))
	minemon.growth._answer_learn(fake, { replace_2 = "Replace" })
	check(lead(fake).moves[2].id == "poison_powder", "the replace did not take the slot")
	check(minemon.growth._pending(NAME) == 1, "one prompt should remain after a replace")
	minemon.growth._answer_learn(fake, { quit = "true" })
	check(minemon.growth._pending(NAME) == 0, "closing the prompt did not clear it")
	for _, mv in ipairs(lead(fake).moves) do
		check(mv.id ~= "sleep_powder", "a closed prompt still taught Sleep Powder")
	end

	-- (8) bond -5 on faint, through the real faint path
	local bulb_b = new_member(BULBASAUR, 5, rng, 10)
	minemon.party.set(fake, { bulb_b })
	check(minemon.party.send_out(fake, 1), "send_out before the faint failed")
	local o = minemon.party.get_active(fake)
	minemon.creatures.damage(o, 9999, nil, nil)
	check(lead(fake).hp == 0, "the creature did not faint")
	check(lead(fake).bond == 5, "bond after a faint is " .. lead(fake).bond .. ", expected 5")

	-- (9) the items, the price, the commands and the bond hook
	for _, id in ipairs(EVO_ITEMS) do
		check(core.registered_items["minemon:" .. id] ~= nil, "item minemon:" .. id .. " is not registered")
	end
	check(minemon.data.get_item("link_cable").price == 2100, "the Link Cable price is not 2100")
	check(core.registered_chatcommands["exp"] ~= nil, "/exp is not registered")
	check(core.registered_chatcommands["givexp"] ~= nil, "/givexp is not registered")
	check(minemon.party.bond_text ~= nil, "the bond hook is not set")
	check(minemon.party.bond_text({ bond = 255 }) == string.rep("♥", 5), "255 bond is not five hearts")

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
