-- Screenshot scene for minemon_sanctuary (T-28): a stone platform with one Sanctuary at its centre, lit at night. Test
-- only: loaded by scripts/screenshot.sh through MINEMON_SHOT_EXTRA_MODS, never shipped. The camera position is in
-- tests/screenshot/sanctuary.json (12 m south of the altar, looking north).
--
-- Timeline after the join: the scene is built SETUP_S seconds after the join; the shot helper teleports the player
-- for each shot. Natural mobs within CLEAR_R are removed, so only the shrine is in the frame.
--
-- luacheck: read_globals core minemon vector VoxelManip VoxelArea

local FLOOR_Y = 180 -- the stone top is at node y = 180 (the floor the other screenshot scenes use for seed 1337)
local ABOVE = 10 -- the air above the platform is cleared this high, enough for the shrine (floor + 8)
local PLATFORM = { x0 = -20, x1 = 20, z0 = -20, z1 = 20 }
local SANCTUARY_FLOOR = vector.new(0, FLOOR_Y, 0)
local SETUP_S = 2
local CLEAR_R = 40 -- natural mobs within this radius of the scene are removed

local started = false

local function log(msg)
	core.log("action", "[minemon_sanctuary_shots] " .. msg)
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

local function setup()
	build_platform()
	local altar = minemon.sanctuary.place(SANCTUARY_FLOOR)
	clear_mobs(vector.new(0, FLOOR_Y, 0))
	log("scene ready: sanctuary altar at " .. (altar and core.pos_to_string(altar) or "nil"))
end

core.register_on_joinplayer(function(player)
	if started then
		return
	end
	started = true
	-- The starter is chosen at once, so the chooser (which opens 1 s after a join with an empty party) never covers
	-- the shots. Cyndaquil is the same choice the party scene makes.
	local ok = minemon.party.choose_starter(player, 155)
	core.log("action", "[minemon_sanctuary_shots] starter chosen: " .. tostring(ok))
	core.after(SETUP_S, setup)
end)
