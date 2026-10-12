-- Integration test (T-28): minemon_sanctuary in the assembled game, with no real players.
-- A stone platform at the origin is forceloaded. A sanctuary is placed on it. A fake player (a table with the
-- methods the code uses: get_meta, get_player_name, get_pos, get_look_dir, get_inventory, is_valid, is_player)
-- drives the flow. Checks:
--   the shrine nodes exist (altar, PC, counter, lanterns, pillars, respawn air above the altar);
--   the ward: is_safe inside 16 nodes horizontal and 8 vertical, not outside; blocks_spawn at 24 nodes;
--   the spawn gate of a Rattata refuses a spawn inside the ward (through the same gate mcl_mobs runs);
--   the altar: the active creature is recalled, the party is healed (HP, status, PP, fainted members too),
--   set_player_spawn_pos is called once (spied) and the respawn point is the air above the altar, with
--   enable_bed_respawn on and off;
--   the PC: deposit and withdraw round trip through player meta, the last healthy member is refused, a full party
--   refuses a withdraw, a capture with a full party is boxed;
--   creature_defeated (fired here) drops coins at the creature's position, in the band for its level;
--   the Keeper's counter: a purchase takes coins and gives the item, a short purse is refused;
--   a potion heals the first hurt member and is used up;
--   spawn_attempt drives the spawn search on the real nodes and places the spawn sanctuary once;
--   the search radii widen per attempt (8..16, then 24, 32, 48), and foundation() lays a stone pillar down to
--   solid ground, a 3 x 3 platform when no ground is in reach, and builds nothing on unloaded nodes.
-- Writes PASS n or FAIL <reason> to test_result.txt, then shuts down.
-- luacheck: read_globals core minemon vector ItemStack
-- luacheck: globals mcl_spawn

local PLATFORM_Y = 4 -- stone top at y = 4; the sanctuary floor is this node
local HALF = 14
local TOP_Y = 16
local STONE = "mcl_core:stone"
local NAME = "sanctuary_test_player"
local RATTATA = 19
local BULBASAUR = 1
local FLOOR = vector.new(0, PLATFORM_Y, 0)
local ALTAR = vector.new(0, PLATFORM_Y + 1, 0)
local SHOP_FORM = "minemon_sanctuary:shop"

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

local function node_name(pos)
	local node = core.get_node_or_nil(pos)
	return node and node.name or "nil"
end

-- A minimal inventory over real ItemStacks: 32 slots, add, remove by name and count, room.
local function make_inventory()
	local slots = {}
	for i = 1, 32 do
		slots[i] = ItemStack("")
	end
	local inv = {}
	function inv.get_list(_, _list)
		return slots
	end
	function inv.add_item(_, _list, stack)
		local left = ItemStack(stack)
		for i = 1, #slots do
			left = slots[i]:add_item(left)
			if left:is_empty() then
				return left
			end
		end
		return left
	end
	function inv.room_for_item(_, _list, stack)
		local left = ItemStack(stack)
		for i = 1, #slots do
			left = ItemStack(slots[i]):add_item(left)
			if left:is_empty() then
				return true
			end
		end
		return left:is_empty()
	end
	function inv.remove_item(_, _list, stack)
		local need = stack:get_count()
		local name = stack:get_name()
		local removed = 0
		for i = 1, #slots do
			if slots[i]:get_name() == name and need > removed then
				local take = math.min(slots[i]:get_count(), need - removed)
				slots[i]:take_item(take)
				removed = removed + take
			end
		end
		return ItemStack(name .. " " .. removed)
	end
	function inv.count(_, name)
		local n = 0
		for _, s in ipairs(slots) do
			if s:get_name() == name then
				n = n + s:get_count()
			end
		end
		return n
	end
	return inv
end

-- The fake player: meta is a plain table of strings; the inventory is make_inventory().
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
	local inv = make_inventory()
	local fake = {}
	fake.get_meta = function()
		return meta
	end
	fake.get_player_name = function()
		return NAME
	end
	fake.get_pos = function()
		return vector.new(0, PLATFORM_Y + 1.5, -4)
	end
	fake.get_look_dir = function()
		return vector.new(0, 0, 1)
	end
	fake.get_inventory = function()
		return inv
	end
	fake.is_valid = function()
		return true
	end
	fake.is_player = function()
		return true
	end
	fake.get_guid = function()
		return "sanctuary-test-fake-player"
	end
	return fake
end

-- The corners are forceloaded first. Their mapblocks load asynchronously, so the checks start only once the platform
-- reads back as loaded (see start below): nodes are set only in loaded blocks.
local function forceload_corners()
	for _, p in ipairs({ { -HALF, -HALF }, { HALF, -HALF }, { -HALF, HALF }, { HALF, HALF } }) do
		check(core.forceload_block(vector.new(p[1], PLATFORM_Y, p[2]), true, 256), "forceload failed")
	end
end

local function loaded()
	for _, p in ipairs({ FLOOR, vector.new(-HALF, PLATFORM_Y, -HALF), vector.new(HALF, PLATFORM_Y, HALF) }) do
		if core.get_node_or_nil(p) == nil then
			return false
		end
	end
	return true
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
end

local function max_hp(m)
	return minemon.instance.stats(m, minemon.data.get_species(m.species_id)).hp
end

local function member(species_id, level, rng)
	local m = minemon.instance.new(minemon.data.get_species(species_id), level, rng)
	m.owner = NAME
	return m
end

local function coin_count_on_ground(pos, radius)
	local total = 0
	for _, obj in ipairs(core.get_objects_inside_radius(pos, radius)) do
		local le = (not obj:is_player()) and obj:get_luaentity() or nil
		if le and le.name == "__builtin:item" and type(le.itemstring) == "string" then
			local n = le.itemstring:match("^minemon:coin (%d+)$")
			if n then
				total = total + tonumber(n)
			end
		end
	end
	return total
end

local function run()
	local rng = minemon.rng.new(31337)
	build_platform()

	-- (1) the shrine: place it and check the nodes
	local altar = minemon.sanctuary.place(FLOOR)
	check(altar ~= nil, "place returned nil")
	check(altar.x == ALTAR.x and altar.y == ALTAR.y and altar.z == ALTAR.z, "altar is not above the floor centre")
	check(node_name(ALTAR) == "minemon_sanctuary:altar", "altar node is " .. node_name(ALTAR))
	check(node_name(vector.new(-2, ALTAR.y, 0)) == "minemon_sanctuary:pc", "PC is missing on the west side")
	check(node_name(vector.new(2, ALTAR.y, 0)) == "minemon_sanctuary:counter", "counter is missing on the east side")
	for _, sx in ipairs({ -3, 3 }) do
		for _, sz in ipairs({ -3, 3 }) do
			check(node_name(vector.new(sx, PLATFORM_Y + 5, sz)) == "minemon_sanctuary:lantern",
				"lantern missing at a corner")
			check(node_name(vector.new(sx, PLATFORM_Y + 2, sz)) == "mcl_core:stonebrick", "pillar missing")
		end
	end
	check(node_name(vector.new(0, PLATFORM_Y + 4, 3)) == "mcl_core:stonebrick", "frame beam missing")
	check(node_name(vector.new(0, ALTAR.y + 1, 0)) == "air", "the respawn air above the altar is blocked")
	local centres = minemon.sanctuary.list()
	check(#centres >= 1, "the centre was not registered")

	-- (2) the ward: 16 horizontal, 8 vertical
	check(minemon.sanctuary.is_safe(vector.new(ALTAR.x + 16, ALTAR.y, ALTAR.z)), "16 nodes out is not safe")
	check(not minemon.sanctuary.is_safe(vector.new(ALTAR.x + 17, ALTAR.y, ALTAR.z)), "17 nodes out is safe")
	check(minemon.sanctuary.is_safe(vector.new(ALTAR.x, ALTAR.y + 8, ALTAR.z)), "8 nodes up is not safe")
	check(not minemon.sanctuary.is_safe(vector.new(ALTAR.x, ALTAR.y + 9, ALTAR.z)), "9 nodes up is safe")
	check(not minemon.sanctuary.is_safe(vector.new(40, ALTAR.y, 40)), "far away is safe")

	-- (3) the spawn gate refuses a Rattata spawn inside the ward, and the spawn block is 24 nodes in 3D
	local rattata_name = minemon.creatures.entity_name(minemon.data.get_species(RATTATA))
	check(not minemon.creatures.gate_passes(rattata_name, vector.new(3, PLATFORM_Y + 1, 3)),
		"a wild spawn inside the ward was allowed")
	check(minemon.sanctuary.blocks_spawn(vector.new(ALTAR.x + 24, ALTAR.y, ALTAR.z)), "24 nodes out is not blocked")
	check(not minemon.sanctuary.blocks_spawn(vector.new(ALTAR.x + 25, ALTAR.y, ALTAR.z)), "25 nodes out is blocked")

	-- (4) the altar: heal, recall, respawn (spied and checked through get_player_spawn_pos)
	local fake = make_fake()
	local m1 = member(BULBASAUR, 5, rng)
	m1.hp = 1
	m1.status = "burn"
	local m2 = member(BULBASAUR, 6, rng)
	m2.hp = 0
	m2.faint_s = 100
	minemon.party.set(fake, { m1, m2 })
	local sent, why = minemon.party.send_out(fake, 1)
	check(sent, "send_out failed: " .. tostring(why))
	check(minemon.party.get_active(fake) ~= nil, "no creature is out before the altar")

	local spy_calls = 0
	local original_set = mcl_spawn.set_player_spawn_pos
	mcl_spawn.set_player_spawn_pos = function(...)
		spy_calls = spy_calls + 1
		return original_set(...)
	end
	local altar_def = core.registered_nodes["minemon_sanctuary:altar"]
	altar_def.on_rightclick(ALTAR, core.get_node(ALTAR), fake)
	mcl_spawn.set_player_spawn_pos = original_set

	check(minemon.party.get_active(fake) == nil, "the altar did not recall the active creature")
	check(m1.hp == max_hp(m1), "the lead was not healed: " .. m1.hp .. " of " .. max_hp(m1))
	check(m1.status == "none", "the status was not cleared: " .. tostring(m1.status))
	for _, mv in ipairs(m1.moves) do
		local move = minemon.data.get_move(mv.id)
		check(mv.pp == move.pp, "PP of " .. mv.id .. " was not refilled")
	end
	check(m2.hp == max_hp(m2) and m2.faint_s == 0, "the fainted member was not revived by the altar")
	check(spy_calls == 1, "set_player_spawn_pos was called " .. spy_calls .. " times")

	local spawn_pos = mcl_spawn.get_player_spawnpoint(fake)
	check(spawn_pos ~= nil and spawn_pos.x == ALTAR.x and spawn_pos.y == ALTAR.y + 1 and spawn_pos.z == ALTAR.z,
		"the respawn point is not the air above the altar")
	local bed_on = core.settings:get_bool("enable_bed_respawn") ~= false
	core.settings:set_bool("enable_bed_respawn", false)
	local rp_off = mcl_spawn.get_player_spawn_pos(fake)
	check(rp_off ~= nil and rp_off.y == ALTAR.y + 1, "respawn is lost with enable_bed_respawn off")
	core.settings:set_bool("enable_bed_respawn", true)
	local rp_on = mcl_spawn.get_player_spawn_pos(fake)
	check(rp_on ~= nil and rp_on.y == ALTAR.y + 1, "respawn is lost with enable_bed_respawn on")
	core.settings:set_bool("enable_bed_respawn", bed_on)

	-- (5) the PC: deposit and withdraw through meta. With the second member fainted, the lead is the last healthy one.
	m2.hp = 0
	minemon.party.set(fake, { m1, m2 })
	local refused, reason = minemon.pc.deposit(fake, m1)
	check(refused == false and reason == "You can't go out there alone.",
		"the last healthy member was allowed to leave the party")
	check(minemon.pc.deposit(fake, m2) == true, "a fainted second member could not be deposited")
	check(#minemon.party.get(fake) == 1, "the party does not have one member after the deposit")
	check(#minemon.pc.list(fake) == 1, "the PC box does not have the deposited member")
	local raw = fake:get_meta():get_string("minemon:pc:list")
	check(raw ~= "" and #core.parse_json(raw) == 1, "the PC box is not in player meta")
	check(minemon.pc.withdraw(fake, 1) == true, "withdraw failed with room in the party")
	check(#minemon.party.get(fake) == 2 and #minemon.pc.list(fake) == 0, "withdraw did not move the member back")
	local ok_missing, why_missing = minemon.pc.withdraw(fake, 1)
	check(ok_missing == false and why_missing == "No such creature.", "withdraw from an empty box was allowed")

	-- a full party refuses a withdraw; a capture with a full party goes into the box
	local full = {}
	for i = 1, 6 do
		full[i] = member(BULBASAUR, 4 + i, rng)
	end
	minemon.party.set(fake, full)
	local extra = member(RATTATA, 3, rng)
	check(minemon.pc.deposit(fake, extra) == true, "a capture with a full party was not boxed")
	check(#minemon.party.get(fake) == 6, "the party changed when a capture was boxed")
	check(#minemon.pc.list(fake) == 1, "the boxed capture is not in the box")
	local ok_full, why_full = minemon.pc.withdraw(fake, 1)
	check(ok_full == false and why_full == "Your party is full.", "withdraw into a full party was allowed")
	minemon.party.set(fake, { m1, m2 })
	check(minemon.pc.withdraw(fake, 1) == true, "withdraw of the boxed capture failed")
	check(#minemon.party.get(fake) == 3 and #minemon.pc.list(fake) == 0, "the boxed capture did not come back")
	m2.hp = max_hp(m2)

	-- (6) coins: creature_defeated drops coins at the creature's position
	local at = vector.new(8, PLATFORM_Y + 1, -8)
	local obj = minemon.creatures.spawn(at, RATTATA, 5, nil)
	check(obj ~= nil, "the test Rattata did not spawn")
	local le = obj:get_luaentity()
	minemon.events.fire("creature_defeated", le, nil)
	local t = core.get_timeofday()
	local night = t < 0.2 or t > 0.8
	local low, high = 2, 4
	if night then
		low, high = 4, 8
	end
	local dropped = coin_count_on_ground(at, 2)
	check(dropped >= low and dropped <= high, "coins dropped: " .. dropped .. " not in " .. low .. ".." .. high)
	obj:remove()

	-- (7) the Keeper's counter: a purchase takes coins and gives the item; a short purse is refused
	local inv = fake:get_inventory()
	inv:add_item("main", ItemStack("minemon:coin 20"))
	local function receive(form, fields)
		for _, cb in ipairs(core.registered_on_player_receive_fields) do
			if cb(fake, form, fields) then
				return true
			end
		end
		return false
	end
	check(receive(SHOP_FORM, { buy_potion_1 = "x1" }), "the shop did not handle a purchase")
	check(inv:count("minemon:coin") == 18, "the purchase did not take 2 coins: " .. inv:count("minemon:coin"))
	check(inv:count("minemon:potion") == 1, "the purchased potion is missing")
	receive(SHOP_FORM, { buy_super_potion_1 = "x1" })
	check(inv:count("minemon:coin") == 11, "the purchase took coins it should not have")
	check(inv:count("minemon:super_potion") == 1, "the super potion was not bought with 11 coins")
	inv:remove_item("main", ItemStack("minemon:coin 11"))
	receive(SHOP_FORM, { buy_super_potion_5 = "x5" })
	check(inv:count("minemon:super_potion") == 1, "a purchase with no coins gave an item")

	-- (8) a potion heals the first hurt member and is used up
	m1.hp = 3
	local stack = ItemStack("minemon:potion 2")
	local def = core.registered_items["minemon:potion"]
	check(def ~= nil and def.on_place ~= nil, "minemon:potion is not registered")
	stack = def.on_place(stack, fake)
	check(stack ~= nil and stack:get_count() == 1, "the potion was not used up")
	check(m1.hp > 3, "the potion did not heal the hurt member")

	-- (9) the last resort: a stone foundation under a floor (a pillar down to the platform, a 3 x 3 platform when the
	-- ground is out of reach, nothing where the nodes are not loaded)
	check(minemon.sanctuary.foundation(vector.new(-10, 10, 10), 48) == "pillar", "no pillar down to the platform")
	check(node_name(vector.new(-10, 9, 10)) == "mcl_core:stone" and node_name(vector.new(-10, 5, 10)) == "mcl_core:stone",
		"the foundation pillar is missing")
	check(node_name(vector.new(-11, 6, 9)) == "mcl_core:stone", "the foundation pillar is not 3 x 3")
	check(node_name(vector.new(-10, 4, 10)) == "mcl_core:stone", "the foundation disturbed the ground")
	check(minemon.sanctuary.foundation(vector.new(10, 10, -10), 2) == "platform",
		"no 3 x 3 platform when the ground is out of reach")
	check(node_name(vector.new(9, 9, -11)) == "mcl_core:stone" and node_name(vector.new(11, 9, -9)) == "mcl_core:stone",
		"the foundation platform is not 3 x 3")
	check(node_name(vector.new(10, 8, -10)) == "air", "the foundation platform went below its depth")
	check(minemon.sanctuary.foundation(vector.new(-12, 5, -12), 48) == "ground", "a supported floor was not seen as such")
	check(minemon.sanctuary.foundation(vector.new(200, 10, 200), 48) == nil, "a floor on unloaded nodes was built")

	-- (10) the spawn sanctuary: the attempts drive the search on the real nodes. The first usable floor is taken (the
	-- platform, or the mapgen ground of this random world, both pass the 9 x 9 check). The placement is kept once.
	check(#minemon.sanctuary.spawn_radii(0) == 3 and minemon.sanctuary.spawn_radii(0)[3] == 16,
		"attempt 0 does not search the rings 8 to 16")
	check(minemon.sanctuary.spawn_radii(1)[4] == 24, "attempt 1 does not widen to 24")
	local widest = minemon.sanctuary.spawn_radii(99)
	check(#widest == 6 and widest[6] == 48, "the widest search is not 48")
	local placed, spawn_altar = false, nil
	for attempt = 0, 3 do
		placed, spawn_altar = minemon.sanctuary.spawn_attempt(attempt)
		if placed then
			break
		end
	end
	check(placed == true and spawn_altar ~= nil, "spawn_attempt did not place the spawn sanctuary")
	check(node_name(spawn_altar) == "minemon_sanctuary:altar", "the spawn centre is not an altar")
	check(node_name(vector.new(spawn_altar.x, spawn_altar.y - 1, spawn_altar.z)) == "mcl_core:stonebrick",
		"the spawn sanctuary has no floor under its altar")
	check(minemon.sanctuary.spawn_attempt(0) == false, "spawn_attempt placed a second spawn sanctuary")
	return checks
end

-- Waits (at most 30 s) for the platform to load, then runs the checks once.
local function start(waited)
	if not loaded() then
		if waited >= 150 then
			finish("FAIL the test platform did not load")
			return
		end
		core.after(0.2, function()
			start(waited + 1)
		end)
		return
	end
	local ok, res = pcall(run)
	if ok then
		finish("PASS " .. tostring(res))
	else
		finish("FAIL " .. tostring(res))
	end
end

core.after(1, function()
	forceload_corners()
	start(0)
end)
