-- Visual check for the T-25a Cobblemon pack. Test-only: loaded only by scripts/screenshot.sh
-- (MINEMON_SHOT_EXTRA_MODS), never shipped.
--
-- Builds a flat platform above the spawn ground, then two lineups of static display entities (not mobs):
--   row A (z = 0, from x = -7.5): the six test species 19, 25, 92, 95, 130, 155, then the shiny forms of 19 and 25;
--   grid B (x from 16, z = -2, 1, 4): 24 species drawn with a fixed seed from the converted pack, so every run
--   shows the same 24. Every display faces -z, towards the cameras in tests/screenshot/pack_lineup.json.
-- The shot helper teleports the player but cannot make them fly, so gravity is off and the height is snapped here.
--
-- Depends on minemon_pack_cobblemon (the generated pack): the pack's init.lua defines minemon_pack.models[dex].
-- T-25b: every display is frozen at SHOT_FRAME (set_animation with speed 0), so a shot shows one pose of the
-- baked clip: 5 is the stand clip (0-20), 30 the walk clip (21-41). Edit the constant for the walk shots.

-- luacheck: globals VoxelArea
local DISPLAY = "minemon_pack_lineup:display"
local TEST_SPECIES = { 19, 25, 92, 95, 130, 155 }
local SHINY_SPECIES = { 19, 25 }
local RANDOM_SEED = 25
local RANDOM_COUNT = 24
local ROW_A_X0 = -7.5
local ROW_A_Z = 0
-- Six blocks apart, so that each model can be shot on its own without its neighbours in the frame.
local ROW_DX = 6
local GRID_B_X0 = 40
local GRID_B_COLS = 8
local GRID_B_ROWS_Z = { -2, 1, 4 }
local GRID_B_DX = 1.9
-- The platform covers both lineups. The floor sits above the canopy and the cloud layer, as in the T-18 lineup.
local PLATFORM_X = { -12, 60 }
local PLATFORM_Z = { -16, 8 }
local FLOOR_ABOVE_GROUND = 30
local FLOOR_MIN_Y = 80
local CLEAR_ABOVE = 6
local POLL_S = 0.25
-- The frame every display is frozen at (T-25b): stand 0-20, walk 21-41.
local SHOT_FRAME = 5

local displays = {}
local built = false
local feet_y = nil
local poll_acc = 0

local function log(msg)
	core.log("action", "[minemon_pack_lineup] " .. msg)
end

local function pack_models()
	local pack = rawget(_G, "minemon_pack")
	return pack and pack.models or {}
end

-- VoxelManip writes the platform, because core.set_node does nothing in blocks that are not loaded yet.
local function build_platform(floor_y)
	local vm = VoxelManip()
	local emin, emax = vm:read_from_map({ x = PLATFORM_X[1], y = floor_y, z = PLATFORM_Z[1] },
		{ x = PLATFORM_X[2], y = floor_y + CLEAR_ABOVE, z = PLATFORM_Z[2] })
	local area = VoxelArea:new({ MinEdge = emin, MaxEdge = emax })
	local data = vm:get_data()
	local c_air = core.get_content_id("air")
	local c_stone = core.get_content_id("mcl_core:stone")
	for z = PLATFORM_Z[1], PLATFORM_Z[2] do
		for y = floor_y, floor_y + CLEAR_ABOVE do
			for x = PLATFORM_X[1], PLATFORM_X[2] do
				data[area:index(x, y, z)] = (y == floor_y) and c_stone or c_air
			end
		end
	end
	vm:set_data(data)
	vm:write_to_map(true)
end

local function spawn_display(x, z, dex, shiny)
	local model = pack_models()[dex]
	if not model then
		log("no pack model for dex " .. dex)
		return
	end
	local obj = core.add_entity({ x = x, y = feet_y, z = z }, DISPLAY)
	if obj then
		obj:set_properties({
			visual = "mesh",
			mesh = model.mesh,
			textures = { shiny and model.texture_shiny or model.texture },
			visual_size = { x = 1, y = 1, z = 1 },
		})
		obj:set_animation({ x = SHOT_FRAME, y = SHOT_FRAME }, 0, 0, false)
		obj:set_yaw(0)
		table.insert(displays, obj)
	end
end

-- The 24 species: every converted dex number, shuffled with a fixed seed, first 24.
local function random_species()
	local all = {}
	for dex in pairs(pack_models()) do
		table.insert(all, dex)
	end
	table.sort(all)
	local rng = PcgRandom(RANDOM_SEED)
	for i = #all, 2, -1 do
		local j = rng:next(1, i)
		all[i], all[j] = all[j], all[i]
	end
	local picked = {}
	for i = 1, math.min(RANDOM_COUNT, #all) do
		table.insert(picked, all[i])
	end
	return picked
end

local function spawn_lineups()
	for i, dex in ipairs(TEST_SPECIES) do
		spawn_display(ROW_A_X0 + (i - 1) * ROW_DX, ROW_A_Z, dex, false)
	end
	for i, dex in ipairs(SHINY_SPECIES) do
		spawn_display(ROW_A_X0 + (#TEST_SPECIES + i - 1) * ROW_DX, ROW_A_Z, dex, true)
	end
	local picked = random_species()
	for i, dex in ipairs(picked) do
		local col = (i - 1) % GRID_B_COLS
		local row = math.floor((i - 1) / GRID_B_COLS) + 1
		spawn_display(GRID_B_X0 + col * GRID_B_DX, GRID_B_ROWS_Z[row], dex, false)
	end
	log("spawned " .. #displays .. " displays at feet y=" .. feet_y .. "; grid B: " .. table.concat(picked, ","))
end

local function in_lineup_area(p)
	return p.x >= PLATFORM_X[1] and p.x <= PLATFORM_X[2] and p.z >= PLATFORM_Z[1] and p.z <= PLATFORM_Z[2]
end

core.register_entity(DISPLAY, {
	initial_properties = {
		physical = false,
		collide_with_objects = false,
		pointable = false,
		static_save = false,
		visual = "mesh",
		mesh = "mmp_0019.glb",
		textures = { "mmp_0019.png" },
		visual_size = { x = 1, y = 1, z = 1 },
	},
})

core.register_globalstep(function(dtime)
	if not feet_y then
		return
	end
	poll_acc = poll_acc + dtime
	if poll_acc < POLL_S then
		return
	end
	poll_acc = 0
	for _, player in ipairs(core.get_connected_players()) do
		local p = player:get_pos()
		if in_lineup_area(p) and math.abs(p.y - feet_y) > 0.05 then
			player:set_pos({ x = p.x, y = feet_y, z = p.z })
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
		spawn_lineups()
		log("platform at y=" .. floor_y .. " (spawn ground " .. tostring(ground) .. ")")
	end)
end)
