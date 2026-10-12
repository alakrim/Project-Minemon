-- Screenshot scene for minemon_growth (T-27): a stone platform, a Bulbasaur at Lv 15 sent out 2 m in front of the
-- player, and a level-up to 16 through minemon.growth.grant_exp. The level-up line and the evolution cinematic (the
-- "What? ... is evolving!" formspec, the frozen glow and the dark spiral) start at once. Test-only: loaded by
-- scripts/screenshot.sh through MINEMON_SHOT_EXTRA_MODS, never shipped. Keep PLAYER_POS in sync with
-- tests/screenshot/evolve.json.
--
-- Timeline after the join: the Bulbasaur is in the party at once (so the starter chooser, which opens 1 s after a
-- join with an empty party, never covers the shots). At SETUP_S the scene is built and the level-up runs. The
-- cinematic lasts 6 s; the shot list captures it within that window.
--
-- luacheck: read_globals core minemon vector VoxelManip VoxelArea

local FLOOR_Y = 180 -- the stone top is at y = 180.5 (the floor the minemon_party_shots scene uses)
local ABOVE = 6
local PLATFORM = { x0 = -12, x1 = 12, z0 = -12, z1 = 12 }
local PLAYER_POS = vector.new(0, FLOOR_Y + 0.5, -4.5)
local BULBASAUR = 1
local LEVEL_BEFORE = 15
local LEVEL_AFTER = 16
local SETUP_S = 2
local CLEAR_R = 30 -- natural mobs within this radius of the scene are removed

local started = false

local function log(msg)
	core.log("action", "[minemon_growth_shots] " .. msg)
end

local function build_platform()
	local vm = VoxelManip()
	local emin, emax = vm:read_from_map(vector.new(PLATFORM.x0, FLOOR_Y, PLATFORM.z0),
		vector.new(PLATFORM.x1, FLOOR_Y + ABOVE, PLATFORM.z1))
	local area = VoxelArea:new({ MinEdge = emin, MaxEdge = emax })
	local data = vm:get_data()
	local c_air = core.get_content_id("air")
	local c_stone = core.get_content_id("mcl_core:stone")
	for z = PLATFORM.z0, PLATFORM.z1 do
		for x = PLATFORM.x0, PLATFORM.x1 do
			for y = FLOOR_Y, FLOOR_Y + ABOVE do
				data[area:index(x, y, z)] = (y == FLOOR_Y) and c_stone or c_air
			end
		end
	end
	vm:set_data(data)
	vm:write_to_map(true)
end

local function clear_mobs(centre)
	for _, obj in ipairs(core.get_objects_inside_radius(centre, CLEAR_R)) do
		local le = (not obj:is_player()) and obj:get_luaentity() or nil
		if le and le.is_mob then
			obj:remove()
		end
	end
end

local function setup(player, uid)
	build_platform()
	clear_mobs(PLAYER_POS)
	player:set_pos(PLAYER_POS)
	local sent, why = minemon.party.send_out(player, 1)
	if not sent then
		log("send_out failed: " .. tostring(why))
		return
	end
	local species = minemon.data.get_species(BULBASAUR)
	local gain = minemon.formulas.exp_for_level(LEVEL_AFTER, species.growth_rate)
		- minemon.formulas.exp_for_level(LEVEL_BEFORE, species.growth_rate)
	minemon.growth.grant_exp(player, uid, gain)
	local running = minemon.growth._cinematic(player:get_player_name()) ~= nil
	log("scene ready: level-up to " .. LEVEL_AFTER .. ", cinematic running = " .. tostring(running))
end

core.register_on_joinplayer(function(player)
	if started then
		return
	end
	started = true
	local rng = minemon.rng.new(2026)
	local bulb = minemon.instance.new(minemon.data.get_species(BULBASAUR), LEVEL_BEFORE, rng)
	bulb.owner = player:get_player_name()
	minemon.party.set(player, { bulb })
	local uid = bulb.uid
	core.after(SETUP_S, function()
		setup(player, uid)
	end)
end)
