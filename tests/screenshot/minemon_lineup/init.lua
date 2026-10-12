-- Visual check for the T-18 stand-in creatures. Test-only: loaded only by scripts/screenshot.sh
-- (MINEMON_SHOT_EXTRA_MODS), never shipped.
--
-- Builds a flat stone platform just above the spawn ground and a lineup of static display entities (not mobs):
-- one column per body plan, one row per type. The animation follows the player's x/z position, so each shot in
-- tests/screenshot/creature_lineup.json shows its own clip (stand, walk, die). Keep SHOT_MODES in sync with that file.
-- The shot helper teleports the player but cannot make them fly, so gravity is off and the height is snapped here.

-- luacheck: globals VoxelArea
local DISPLAY = "minemon_lineup:display"
local PLANS = { "biped", "quadruped", "serpent", "avian", "blob", "insect", "fish", "other" }
local TYPES = { "fire", "water", "grass", "ghost" }
-- The platform sits above the canopy (trees reach about 20 nodes over the ground) and above the cloud layer,
-- which VoxeLibre draws at about y = 65 (mcl_weather: layer 127).
local FLOOR_ABOVE_GROUND = 30
local FLOOR_MIN_Y = 80
local CLEAR_ABOVE = 6 -- air is cleared this high above the platform
local COL_DX = 2.6
local ROW_DZ = 2.4
local HALF_X = 16
local MIN_Z, MAX_Z = -14, 10
local MODE_POLL_S = 0.25
local MATCH_RADIUS = 0.15

local CLIPS = {
	stand = { range = { x = 0, y = 20 }, speed = 4, loop = true },
	walk = { range = { x = 21, y = 41 }, speed = 20, loop = true },
	run = { range = { x = 42, y = 52 }, speed = 30, loop = true },
	punch = { range = { x = 53, y = 63 }, speed = 14, loop = false },
	die = { range = { x = 64, y = 74 }, speed = 10, loop = false },
	sit = { range = { x = 75, y = 85 }, speed = 6, loop = false },
}

-- Shot feet positions (x, z) -> clip. Must match tests/screenshot/creature_lineup.json.
local SHOT_MODES = {
	{ x = 0, z = -10, mode = "stand" },
	{ x = 0, z = -10.6, mode = "walk" },
	{ x = 0, z = -11.2, mode = "die" },
	{ x = -2.6, z = -8.5, mode = "stand" },
	{ x = 2.6, z = -8.5, mode = "walk" },
	{ x = -6, z = -6, mode = "stand" },
	{ x = 6, z = -6, mode = "stand" },
}

local displays = {}
local built = false
local feet_y = nil
local poll_acc = 0

local function log(msg)
	core.log("action", "[minemon_lineup] " .. msg)
end

local function column_x(i)
	return (i - 4.5) * COL_DX
end

local function row_z(j)
	return (j - 2.5) * ROW_DZ
end

-- core.set_node does nothing in blocks that are not loaded yet, so the platform is written with VoxelManip,
-- which generates and loads its blocks first. The box is cleared to air, then the floor layer is stone.
local function build_platform(floor_y)
	local vm = VoxelManip()
	local emin, emax = vm:read_from_map({ x = -HALF_X, y = floor_y, z = MIN_Z },
		{ x = HALF_X, y = floor_y + CLEAR_ABOVE, z = MAX_Z })
	local area = VoxelArea:new({ MinEdge = emin, MaxEdge = emax })
	local data = vm:get_data()
	local c_air = core.get_content_id("air")
	local c_stone = core.get_content_id("mcl_core:stone")
	for z = MIN_Z, MAX_Z do
		for y = floor_y, floor_y + CLEAR_ABOVE do
			for x = -HALF_X, HALF_X do
				data[area:index(x, y, z)] = (y == floor_y) and c_stone or c_air
			end
		end
	end
	vm:set_data(data)
	vm:write_to_map(true)
end

local function spawn_lineup()
	for i, plan in ipairs(PLANS) do
		for j, type_name in ipairs(TYPES) do
			local pos = { x = column_x(i), y = feet_y, z = row_z(j) }
			local obj = core.add_entity(pos, DISPLAY)
			if obj then
				obj:set_properties({
					visual = "mesh",
					mesh = "mm_" .. plan .. ".glb",
					textures = { "mm_type_" .. type_name .. ".png" },
					visual_size = { x = 1, y = 1, z = 1 },
				})
				table.insert(displays, obj)
			end
		end
	end
	log("spawned " .. #displays .. " display entities at feet y=" .. feet_y)
end

local function set_clip(obj, mode)
	local le = obj:get_luaentity()
	if not le or le.mode == mode then
		return
	end
	le.mode = mode
	local clip = CLIPS[mode]
	obj:set_animation(clip.range, clip.speed, 0, clip.loop)
end

-- Returns the clip for a player on a shot position, or nil. Snaps the player onto the platform height.
local function shot_for_player(player)
	local p = player:get_pos()
	for _, s in ipairs(SHOT_MODES) do
		if math.abs(p.x - s.x) < MATCH_RADIUS and math.abs(p.z - s.z) < MATCH_RADIUS then
			if math.abs(p.y - feet_y) > 0.05 then
				player:set_pos({ x = p.x, y = feet_y, z = p.z })
			end
			return s.mode
		end
	end
	return nil
end

core.register_entity(DISPLAY, {
	initial_properties = {
		physical = false,
		collide_with_objects = false,
		pointable = false,
		static_save = false,
		visual = "mesh",
		mesh = "mm_biped.glb",
		textures = { "mm_type_fire.png" },
		visual_size = { x = 1, y = 1, z = 1 },
	},
	mode = nil,
})

core.register_globalstep(function(dtime)
	if not feet_y then
		return
	end
	poll_acc = poll_acc + dtime
	if poll_acc < MODE_POLL_S then
		return
	end
	poll_acc = 0
	local mode = nil
	for _, player in ipairs(core.get_connected_players()) do
		mode = shot_for_player(player) or mode
	end
	mode = mode or "stand"
	for _, obj in ipairs(displays) do
		if obj:get_pos() then
			set_clip(obj, mode)
		end
	end
end)

core.register_on_joinplayer(function(player)
	player:set_physics_override({ gravity = 0 })
	if built then
		return
	end
	built = true
	core.after(0.5, function()
		local ground = core.get_spawn_level(0, 0) or 40
		local floor_y = math.max(math.floor(ground) + FLOOR_ABOVE_GROUND, FLOOR_MIN_Y)
		feet_y = floor_y + 0.5
		build_platform(floor_y)
		spawn_lineup()
		log("platform at y=" .. floor_y .. " (spawn ground " .. tostring(ground) .. ")")
	end)
end)
