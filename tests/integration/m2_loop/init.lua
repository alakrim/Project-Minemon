-- Integration test (W1): the whole M2 loop across minemon_party, minemon_creatures, minemon_capture, minemon_growth and
-- minemon_sanctuary, in the assembled game, with no real players. A stone platform at the origin is forceloaded and an
-- altar stands on it. A fake player (meta, inventory and the methods the code uses) drives the flow, in this order:
--  (1) a starter Bulbasaur is the party and is sent out;
--  (2) a wild Rattata is damaged to 0 by the active creature: it is exhausted, creature_defeated fires once, the lead
--      gains exactly the formula's exp (once), coins lie on the ground once, and a second hit does nothing;
--  (3) a forced catch puts it in the party (owner, ball, bond 70, hp >= 1, entity gone);
--  (4) four more forced catches fill the party to 6; a seventh goes to the PC (minemon.pc.list grows, party stays 6);
--  (5) the Keeper's counter sells a Poke Ball (the purchase runs through the shop's receive-fields handler, since the
--      purchase function itself is local to shop.lua; it is not exposed);
--  (6) the lead gains exp to level 16 through minemon.growth.grant_exp, the evolution cinematic starts, and
--      _evolve_now turns it into Ivysaur with the same uid, sent out again;
--  (7) the altar heals the party: every HP max, the lead's PP refilled, the active creature recalled;
--  (8) a failed forced capture of a wild Bulbasaur breaks it free: visible, not exhausted, enraged (_mm_enraged_t > 0),
--      not passive, and the party and the PC are unchanged.
-- Writes PASS n or FAIL <reason> to test_result.txt, then shuts down.
-- luacheck: read_globals core minemon vector ItemStack

local PLATFORM_Y = 5 -- stone top at y = 5.5; the fake player stands there
local HALF = 6
local TOP_Y = 9
local STONE = "mcl_core:stone"
local ALTAR_NODE = "minemon_sanctuary:altar"
local ALTAR = vector.new(0, PLATFORM_Y + 1, HALF)
local SHOP_FORM = "minemon_sanctuary:shop"
local COIN = "minemon:coin"
local BALL = "minemon:poke_ball"
local NAME = "m2_loop_player"
local BULBASAUR = 1
local IVYSAUR = 2
local RATTATA = 19
local PARTY_MAX = 6
local COIN_RADIUS = 1.0

local finished = false
local checks = 0
local defeated = 0
local captured = 0
local evolved = 0

minemon.events.register("creature_defeated", function()
	defeated = defeated + 1
end)
minemon.events.register("creature_captured", function()
	captured = captured + 1
end)
minemon.events.register("creature_evolved", function()
	evolved = evolved + 1
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

-- An inventory with counts per item name. Methods take self, like the engine's InvRef.
local function make_inventory()
	local counts = {}
	local inv = {}
	function inv.get_list(_, _list)
		local out = {}
		for name, n in pairs(counts) do
			if n > 0 then
				out[#out + 1] = ItemStack(name .. " " .. n)
			end
		end
		return out
	end
	function inv.add_item(_, _list, stack)
		local st = ItemStack(stack)
		counts[st:get_name()] = (counts[st:get_name()] or 0) + st:get_count()
		return ItemStack("")
	end
	function inv.remove_item(_, _list, stack)
		local st = ItemStack(stack)
		local have = counts[st:get_name()] or 0
		local take = math.min(have, st:get_count())
		counts[st:get_name()] = have - take
		return ItemStack(st:get_name() .. " " .. take)
	end
	function inv.room_for_item()
		return true
	end
	function inv.count(_, name)
		return counts[name] or 0
	end
	return inv
end

-- The fake player: meta is a table of strings; the inventory is make_inventory().
local function make_fake(inv)
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
		return "m2-loop-test-fake-player"
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
	core.set_node(ALTAR, { name = ALTAR_NODE })
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

local function species(id)
	return minemon.data.get_species(id)
end

local function max_hp(m)
	return minemon.instance.stats(m, species(m.species_id)).hp
end

-- The coins lying on the ground near pos (item entities whose item is minemon:coin).
local function coins_near(pos)
	local n = 0
	for _, o in ipairs(core.get_objects_inside_radius(pos, COIN_RADIUS)) do
		local le = o:get_luaentity()
		if le and le.name == "__builtin:item" and type(le.itemstring) == "string"
			and string.find(le.itemstring, "^minemon:coin") then
			n = n + ItemStack(le.itemstring):get_count()
		end
	end
	return n
end

-- Runs the shop's registered receive-fields handlers, as the engine does for a button press.
local function receive(player, form, fields)
	for _, cb in ipairs(core.registered_on_player_receive_fields) do
		if cb(player, form, fields) then
			return true
		end
	end
	return false
end

local function run()
	local inv = make_inventory()
	local fake = make_fake(inv)

	-- (1) the starter is the party, and it is sent out
	local ok, why = minemon.party.choose_starter(fake, BULBASAUR)
	check(ok, "choose_starter failed: " .. tostring(why))
	check(#minemon.party.get(fake) == 1, "the party does not have one starter")
	local sent, why_sent = minemon.party.send_out(fake, 1)
	check(sent, "send_out failed: " .. tostring(why_sent))
	local active = minemon.party.get_active(fake)
	check(active ~= nil, "the starter is not out")
	local lead_uid = minemon.party.get(fake)[1].uid

	-- (2) the active creature defeats a wild Rattata: exhausted, exp once, coins once
	local wild = wild_at(RATTATA, -5, -5)
	local pos = wild:get_pos()
	-- party.get returns the cached list, so the exp and bond are copied as numbers before the defeat
	local exp_before = minemon.party.get(fake)[1].exp
	local bond_before = minemon.party.get(fake)[1].bond
	local expected_gain = minemon.formulas.exp_gain(species(RATTATA).base_exp, 5, bond_before)
	check(expected_gain > 0, "the expected exp gain is not positive")
	local defeated_before = defeated
	minemon.creatures.damage(wild, 9999, active, nil)
	check(minemon.creatures.is_exhausted(wild), "the Rattata is not exhausted at 0 HP")
	check(defeated == defeated_before + 1, "creature_defeated did not fire once: " .. (defeated - defeated_before))
	local exp_after = minemon.party.get(fake)[1].exp
	check(exp_after - exp_before == expected_gain,
		"exp gain is " .. (exp_after - exp_before) .. ", expected " .. expected_gain)
	local coins = coins_near(pos)
	check(coins > 0, "the defeated Rattata dropped no coins")
	minemon.creatures.damage(wild, 50, active, nil) -- exhausted: ignored
	check(defeated == defeated_before + 1, "a second hit fired creature_defeated again")
	check(minemon.party.get(fake)[1].exp == exp_after, "a second hit gave exp again")
	check(coins_near(pos) == coins, "a second hit dropped coins again")

	-- (3) a forced catch joins the party with owner, ball, bond 70 and hp >= 1
	local n, caught = minemon.capture._resolve(fake, wild, "poke_ball", fixed_rng(0))
	check(caught == true, "the forced catch did not catch")
	check(n == 3, "a forced catch did not show 3 shakes: " .. tostring(n))
	local party = minemon.party.get(fake)
	check(#party == 2, "the party did not grow to 2: " .. #party)
	local joined = party[2]
	check(joined.owner == NAME, "the caught creature's owner is " .. tostring(joined.owner))
	check(joined.ball == "poke_ball", "the caught creature's ball is " .. tostring(joined.ball))
	check(joined.bond == 70, "the caught creature's bond is " .. tostring(joined.bond))
	check(joined.hp >= 1, "the caught creature has no HP")
	check(captured == 1, "creature_captured did not fire once: " .. captured)
	local wle = wild:get_luaentity()
	check((wle and wle._removed) or not wild:is_valid(), "the caught creature's entity is still there")

	-- (4) four more catches fill the party to 6
	for _, x in ipairs({ -3, -1, 1, 3 }) do
		local w = wild_at(RATTATA, x, -5)
		minemon.creatures.damage(w, 9999, nil, nil)
		local _, c = minemon.capture._resolve(fake, w, "poke_ball", fixed_rng(0))
		check(c == true, "a forced catch at x=" .. x .. " did not catch")
	end
	party = minemon.party.get(fake)
	check(#party == PARTY_MAX, "the party is " .. #party .. ", expected " .. PARTY_MAX)
	check(captured == 5, "creature_captured fired " .. captured .. " times, expected 5")

	-- (5) a seventh catch goes to the PC; the party stays at 6
	local pc_before = #minemon.pc.list(fake)
	local w7 = wild_at(RATTATA, 5, -5)
	minemon.creatures.damage(w7, 9999, nil, nil)
	local _, c7 = minemon.capture._resolve(fake, w7, "poke_ball", fixed_rng(0))
	check(c7 == true, "the seventh forced catch did not catch")
	check(#minemon.party.get(fake) == PARTY_MAX, "the seventh catch changed the party size")
	check(#minemon.pc.list(fake) == pc_before + 1, "the PC did not grow by one: " .. #minemon.pc.list(fake))
	check(captured == 6, "creature_captured fired " .. captured .. " times, expected 6")

	-- (6) the Keeper's counter sells a Poke Ball: items.json price 200, so 2 coins (sanctuary_logic COIN_PER_PRICE)
	inv:add_item("main", ItemStack(COIN .. " 10"))
	check(receive(fake, SHOP_FORM, { buy_poke_ball_1 = "x1" }), "the shop did not handle the purchase")
	check(inv:count(BALL) == 1, "the Poke Ball was not bought: " .. inv:count(BALL))
	check(inv:count(COIN) == 8, "the purchase did not take 2 coins: " .. inv:count(COIN) .. " left of 10")

	-- (7) the lead levels to 16 through the growth API: the evolution cinematic starts; _evolve_now evolves it
	local lead = minemon.party.get(fake)[1]
	check(lead.uid == lead_uid, "the lead is not the starter any more")
	local to16 = minemon.formulas.exp_for_level(16, species(BULBASAUR).growth_rate) - lead.exp
	check(to16 > 0, "the starter already has the exp for level 16")
	minemon.growth.grant_exp(fake, lead_uid, to16)
	lead = minemon.party.get(fake)[1]
	check(lead.level == 16, "the lead is at level " .. lead.level .. ", expected 16")
	check(minemon.growth._cinematic(NAME) ~= nil, "no evolution cinematic at level 16")
	check(minemon.growth._evolve_now(fake, lead_uid, IVYSAUR), "_evolve_now to Ivysaur failed")
	lead = minemon.party.get(fake)[1]
	check(lead.species_id == IVYSAUR, "the lead is species " .. lead.species_id .. ", expected Ivysaur")
	check(lead.uid == lead_uid, "the uid changed in the evolution")
	check(evolved == 1, "creature_evolved fired " .. evolved .. " times")
	active = minemon.party.get_active(fake)
	check(active ~= nil, "the evolved lead was not sent out again")
	check(minemon.creatures.get_instance(active).species_id == IVYSAUR, "the active entity is not Ivysaur")
	check(#minemon.party.get(fake) == PARTY_MAX, "the evolution changed the party size")

	-- (8) the altar heals the party: HP max for every member, the lead's PP refilled, the active one recalled
	minemon.creatures.damage(active, 6, nil, nil)
	minemon.party.update_member(fake, lead_uid, function(m)
		m.moves[1].pp = 0
	end)
	local hurt = minemon.party.get(fake)[1]
	check(hurt.hp < max_hp(hurt), "the lead was not hurt before the altar")
	core.registered_nodes[ALTAR_NODE].on_rightclick(ALTAR, core.get_node(ALTAR), fake)
	check(minemon.party.get_active(fake) == nil, "the altar did not recall the active creature")
	party = minemon.party.get(fake)
	for i, m in ipairs(party) do
		check(m.hp == max_hp(m), "party member " .. i .. " is at " .. m.hp .. " HP after the altar, max " .. max_hp(m))
	end
	local lead_pp = party[1].moves[1].pp
	local move = minemon.data.get_move(party[1].moves[1].id)
	check(move ~= nil and lead_pp == move.pp, "the lead's PP was not refilled: " .. tostring(lead_pp))

	-- (9) a failed capture of a wild Bulbasaur: enraged, not exhausted, nothing else changes
	local pc_now = #minemon.pc.list(fake)
	local bw = wild_at(BULBASAUR, -5, 3)
	minemon.creatures.damage(bw, 9999, nil, nil)
	check(minemon.creatures.is_exhausted(bw), "the wild Bulbasaur is not exhausted at 0 HP")
	local _, cb = minemon.capture._resolve(fake, bw, "poke_ball", fixed_rng(0.9999))
	check(cb == false, "the forced failure caught")
	check(bw:is_valid(), "the broken-free creature is gone")
	local ble = bw:get_luaentity()
	check(type(ble._mm_enraged_t) == "number" and ble._mm_enraged_t > 0,
		"the broken-free creature is not enraged: " .. tostring(ble._mm_enraged_t))
	check(not minemon.creatures.is_exhausted(bw), "the broken-free creature is still exhausted")
	check(ble.passive == false, "the broken-free creature is still passive")
	check(captured == 6, "a failed capture fired creature_captured")
	check(#minemon.party.get(fake) == PARTY_MAX, "a failed capture changed the party")
	check(#minemon.pc.list(fake) == pc_now, "a failed capture changed the PC")

	-- (10) every item in items.json is registered as minemon:<id>, so the shop can find it (D-030)
	local f = io.open(core.get_modpath("minemon_core") .. "/data/items.json", "rb")
	check(f ~= nil, "items.json is not readable")
	local parsed = core.parse_json(f:read("*a"), nil, true)
	f:close()
	local ids = 0
	for id in pairs(parsed) do
		ids = ids + 1
		check(core.registered_items["minemon:" .. id] ~= nil, "minemon:" .. id .. " is not registered")
	end
	check(ids >= 17, "items.json has only " .. ids .. " items")

	bw:remove()
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
