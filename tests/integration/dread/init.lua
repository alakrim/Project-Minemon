-- Integration test (T-30, D-031): the Dread variants in the assembled game, with no real players.
-- A stone platform at the origin is forceloaded. Checks, in stages:
--   (1) the Dread Shard and the Umbral Ball are registered, and the Umbral recipe (Ultra Ball + 4 shards) crafts;
--   (2) a forced Dread creature (minemon.creatures.make_dread) has the dread flag, the "Dread " nametag, full HP, the
--       Dread stat multiplier (x1.25 atk), and is not passive; a normal creature of the same species is not;
--   (3) the look is on (the glow of dread_fx, the Dread texture modifier, the dark nametag colour);
--   (4) aggression: a fake player 15 nodes away makes the Dread creature hunt (run speed x1.2) while the normal
--       peaceful creature does not;
--   (5) defeat: the Dread creature drops 1 or 2 Dread Shards, and its coins are x3 of the normal range (the normal
--       creature's coins stay in the normal range);
--   (6) an Umbral Ball forced capture keeps dread = true and gives bond 20;
--   (7) at day a wild Dread creature dissolves (removed), within a few seconds.
-- Writes PASS n or FAIL <reason> to test_result.txt, then shuts down.
-- luacheck: read_globals core minemon vector ItemStack

local PLATFORM_Y = 5 -- stone top at y = 5.5
local HALF = 6
local TOP_Y = 9
local STONE = "mcl_core:stone"
local NAME = "dread_test_player"
local DROWZEE = 96 -- peaceful: a normal one stays idle, a Dread one hunts
local CYNDAQUIL = 155
local NORMAL_LEVEL = 5

local SANCTUARY_LOGIC = dofile(core.get_modpath("minemon_sanctuary") .. "/sanctuary_logic.lua")

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

-- Runs fn after delay seconds; a failure ends the test with FAIL.
local function stage(delay, fn)
	core.after(delay, function()
		local ok, err = pcall(fn)
		if not ok then
			finish("FAIL " .. tostring(err))
		end
	end)
end

-- The fake player (as in tests/integration/capture): methods take self. No inventory.
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
		return "dread-test-fake-player"
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

-- An rng whose float() is always v. 0 passes every shake check.
local function fixed_rng(v)
	return { float = function() return v end }
end

local function spawn_drowzee(x, z)
	local obj = minemon.creatures.spawn(vector.new(x, PLATFORM_Y + 1, z), DROWZEE, NORMAL_LEVEL, nil)
	check(obj ~= nil, "wild spawn failed at " .. x .. "," .. z)
	local le = obj:get_luaentity()
	le.walk_velocity = 0 -- keep it on its spot for the checks
	return obj
end

-- Counts the items of one name ("minemon:coin", "minemon:dread_shard") lying near pos.
local function count_items(pos, name, radius)
	local total = 0
	for _, obj in ipairs(core.get_objects_inside_radius(pos, radius)) do
		local le = (not obj:is_player()) and obj:get_luaentity() or nil
		if le and type(le.itemstring) == "string" then
			local item, count = le.itemstring:match("^(%S+)%s*(%d*)$")
			if item == name then
				total = total + (tonumber(count) or 1)
			end
		end
	end
	return total
end

-- The coin range of a victim of level lvl at the current time (sanctuary_logic.coin_amount, without the draw). The
-- night here is the sanctuary's (0.2..0.8), as in minemon_sanctuary/init.lua.
local function coin_range(lvl)
	local t = core.get_timeofday()
	local night = t < 0.2 or t > 0.8
	local mult = night and SANCTUARY_LOGIC.COIN_NIGHT_MULT or 1
	local base = math.ceil(math.max(1, lvl) / SANCTUARY_LOGIC.COIN_BASE_DIV)
	local lo = base * mult
	local hi = (base + SANCTUARY_LOGIC.COIN_BONUS_MAX) * mult
	return lo, hi
end

local S = {} -- the objects the stages share

local function stage_registration()
	check(core.registered_craftitems["minemon:dread_shard"] ~= nil, "minemon:dread_shard is not registered")
	check(core.registered_craftitems["minemon:umbral_ball"] ~= nil, "minemon:umbral_ball is not registered")
	check(minemon.data.get_item("umbral_ball") ~= nil and minemon.data.get_item("umbral_ball").kind == "ball",
		"umbral_ball is not a ball in items.json")
	local out = core.get_craft_result({ method = "normal", width = 3, items = {
		"minemon:ultra_ball", "minemon:dread_shard", "minemon:dread_shard", "minemon:dread_shard",
		"minemon:dread_shard", "", "", "", "" } })
	check(out and out.item and out.item:get_name() == "minemon:umbral_ball",
		"the Umbral Ball recipe does not craft from an Ultra Ball and 4 shards")

	build_platform()
	core.set_timeofday(0.9) -- night for the whole test until the dawn stage (a Dread creature dissolves by day)
	S.dread = spawn_drowzee(-2.5, -3)
	S.normal = spawn_drowzee(2.5, -3)
	check(minemon.creatures.make_dread(S.dread) == true, "make_dread failed")
	S.dle = S.dread:get_luaentity()
	S.nle = S.normal:get_luaentity()
	check(minemon.creatures.get_instance(S.dread).dread == true, "the instance is not Dread")
	check(minemon.creatures.get_instance(S.normal).dread ~= true, "the normal instance is Dread")
	check(string.find(S.dle.nametag, "^Dread Drowzee Lv %d+$") ~= nil,
		"the Dread nametag is wrong: " .. tostring(S.dle.nametag))
	check(S.nle.nametag == "Drowzee Lv " .. NORMAL_LEVEL, "the normal nametag is wrong: " .. tostring(S.nle.nametag))

	-- The Dread stat multiplier: atk and hp are x1.25 of the plain stats at the same level and IVs.
	local inst = minemon.creatures.get_instance(S.dread)
	local species = minemon.data.get_species(DROWZEE)
	local plain = minemon.instance.stats({ level = inst.level, ivs = inst.ivs, bond = inst.bond, dread = false },
		species)
	local st = minemon.instance.stats(inst, species)
	check(st.atk == math.floor(plain.atk * 1.25), "the Dread atk is not x1.25: " .. st.atk .. " vs " .. plain.atk)
	check(st.hp == math.floor(plain.hp * 1.25), "the Dread hp is not x1.25")
	check(inst.hp == st.hp, "the Dread creature does not start at full HP: " .. inst.hp .. " vs " .. st.hp)
	check(inst.level >= NORMAL_LEVEL + 5 and inst.level <= NORMAL_LEVEL + 12, "the Dread level bump is out of range")
	check(S.dle.passive == false, "a wild Dread creature is passive")
	check(S.nle.passive == true, "a normal peaceful creature is not passive")
	S.dread_level = inst.level
end

local function stage_look()
	check(S.dle._mm_dread_on == true, "the Dread look is not on")
	local props = S.dread:get_properties()
	local fx = dofile(core.get_modpath("minemon_creatures") .. "/dread_fx.lua")
	check(props.glow == fx.GLOW, "the Dread glow is not " .. fx.GLOW .. ": " .. tostring(props.glow))
	local tex = props.textures[1]
	check(type(tex) == "string" and string.find(tex, "^[multiply", 1, true) ~= nil,
		"the Dread texture has no multiply modifier: " .. tostring(tex))
	local c = props.nametag_color -- a colour comes back as a table {r, g, b, a}
	check(type(c) == "table" and c.r == 0xB0 and c.g == 0x10 and c.b == 0x2A,
		"the Dread nametag colour is not #B0102A: " .. tostring(type(c) == "table" and c.r or c))
	check(S.normal:get_properties().glow ~= 6, "the normal creature glows")
end

local function stage_aggression()
	local fake = make_fake()
	fake.get_pos = function()
		return vector.new(-2.5, PLATFORM_Y + 1, 12) -- 15 nodes from the Dread creature, 17 from the normal one
	end
	minemon.creatures.wild.set_sources(function() return { fake } end, function() return nil end)
	stage(0.9, function()
		local base_d = S.dle._mm_run_base
		local base_n = S.nle._mm_run_base
		check(type(base_d) == "number" and base_d > 0, "the Dread creature has no run base yet")
		check(math.abs(S.dle.run_velocity - base_d * 1.2) < 1e-6,
			"the Dread creature does not hunt at x1.2: " .. tostring(S.dle.run_velocity) .. " base " .. base_d)
		check(math.abs(S.nle.run_velocity - base_n) < 1e-6, "the normal peaceful creature hunts")
		-- The fake player cannot be fought: stop the hunt before the engine runs the attack state.
		minemon.creatures.wild.set_sources(function() return {} end, nil)
		S.dle.attack = nil
		S.dle.state = "stand"
		S.dle.run_velocity = base_d
		S.dle.walk_velocity = 0
		core.after(0.1, function()
			S.dle.state = "stand"
			S.dle.attack = nil
		end)
	end)
end

local function stage_defeat()
	stage(0.5, function()
		local pos_d = S.dread:get_pos()
		local pos_n = S.normal:get_pos()
		minemon.creatures.damage(S.dread, 9999, nil, nil)
		minemon.creatures.damage(S.normal, 9999, nil, nil)
		check(minemon.creatures.is_exhausted(S.dread), "the Dread creature is not exhausted at 0 HP")
		check(minemon.creatures.is_exhausted(S.normal), "the normal creature is not exhausted at 0 HP")
		S.dread_pos, S.normal_pos = pos_d, pos_n
	end)
	stage(1.0, function()
		local shards = count_items(S.dread_pos, "minemon:dread_shard", 2.5)
		check(shards >= 1 and shards <= 2, "the Dread creature dropped " .. shards .. " shards, not 1..2")
		check(count_items(S.normal_pos, "minemon:dread_shard", 2.5) == 0, "the normal creature dropped a shard")

		local lo_d, hi_d = coin_range(S.dle._mm.level)
		local coins_d = count_items(S.dread_pos, "minemon:coin", 2.5)
		check(coins_d % 3 == 0, "the Dread coins are not a multiple of 3: " .. coins_d)
		check(coins_d >= 3 * lo_d and coins_d <= 3 * hi_d,
			string.format("the Dread coins %d are not x3 of the range %d..%d", coins_d, lo_d, hi_d))
		local lo_n, hi_n = coin_range(S.nle._mm.level)
		local coins_n = count_items(S.normal_pos, "minemon:coin", 2.5)
		check(coins_n >= lo_n and coins_n <= hi_n, string.format("the normal coins %d are not in %d..%d",
			coins_n, lo_n, hi_n))
	end)
end

local function stage_umbral()
	stage(0.3, function()
		local fake = make_fake()
		local ok, starter = minemon.party.choose_starter(fake, CYNDAQUIL)
		check(ok, "choose_starter failed: " .. tostring(starter))
		local c = spawn_drowzee(-0.5, 3)
		check(minemon.creatures.make_dread(c) == true, "make_dread failed for the capture")
		minemon.creatures.damage(c, 9999, nil, nil)
		check(minemon.creatures.is_exhausted(c), "the capture target is not exhausted")
		local n, caught = minemon.capture._resolve(fake, c, "umbral_ball", fixed_rng(0))
		check(caught == true, "the forced Umbral capture did not catch (shakes " .. tostring(n) .. ")")
		local party = minemon.party.get(fake)
		local joined = party[#party]
		check(joined ~= nil and joined.dread == true, "the captured creature is not Dread in the party")
		check(joined.bond == 20, "the captured Dread creature's bond is " .. tostring(joined and joined.bond))
		check(joined.owner == NAME, "the captured creature's owner is " .. tostring(joined.owner))
		check(joined.ball == "umbral_ball", "the captured creature's ball is " .. tostring(joined.ball))
	end)
end

local function stage_dawn()
	stage(0.3, function()
		local d = spawn_drowzee(3.5, -5)
		check(minemon.creatures.make_dread(d) == true, "make_dread failed for the dawn check")
		check(d:is_valid(), "the dawn creature vanished before the day")
		S.dawn = d
		core.set_timeofday(0.5)
	end)
	stage(2.5, function()
		local gone = not S.dawn:is_valid() or S.dawn:get_luaentity()._removed == true
		check(gone, "the Dread creature did not dissolve at day")
		check(S.normal:is_valid(), "a normal creature was removed at day")
		finish(string.format("PASS %d checks", checks))
	end)
end

core.after(1, function()
	local ok, err = pcall(function()
		stage_registration()
	end)
	if not ok then
		finish("FAIL " .. tostring(err))
		return
	end
	stage(1.5, function()
		stage_look()
		stage_aggression()
	end)
	stage(3.5, function()
		stage_defeat()
	end)
	stage(6.0, function()
		stage_umbral()
	end)
	stage(8.0, function()
		stage_dawn()
	end)
end)
