-- Screenshot scene for the Dread variants (T-30, D-031): a stone platform, a normal Gengar and a Dread Gengar about 6 m
-- in front of the player. Both are frozen (they would hunt the player; enable_damage is off in the shot run), so the
-- pictures compare their looks only. Test only: loaded by scripts/screenshot.sh through MINEMON_SHOT_EXTRA_MODS,
-- never shipped. Keep PLAYER_POS in sync with tests/screenshot/dread.json.
--
-- The starter is chosen at join, so the party chooser never covers the shots (as in minemon_capture_shots).
--
-- luacheck: read_globals core minemon vector VoxelManip VoxelArea

local FLOOR_Y = 180 -- the stone top is at y = 180.5
local ABOVE = 6
local PLATFORM = { x0 = -12, x1 = 12, z0 = -12, z1 = 12 }
local PLAYER_POS = vector.new(0, FLOOR_Y + 0.5, -5.5)
local NORMAL_POS = vector.new(1.6, FLOOR_Y + 1, 0.5)
local DREAD_POS = vector.new(-1.6, FLOOR_Y + 1, 0.5)
local CYNDAQUIL = 155
local GENGAR = 94
local LEVEL = 30
local CLEAR_R = 30
local SETUP_S = 0.5

local started = false
local setup_done = false
local frozen = {}

local function log(msg)
	core.log("action", "[minemon_dread_shots] " .. msg)
end

local function build_platform()
	-- VoxelManip loads the blocks first, so the nodes stick (as in minemon_capture_shots).
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

local function freeze(obj)
	local le = obj:get_luaentity()
	if le then
		le.walk_velocity = 0
		le.run_velocity = 0
		frozen[#frozen + 1] = obj
	end
end

local function setup()
	if setup_done then
		return
	end
	setup_done = true
	-- Night before the spawn: a Dread creature dissolves at day (minemon_dread). The shots set their own times later.
	core.set_timeofday(0.9)
	build_platform()
	clear_mobs(PLAYER_POS)
	local normal = minemon.creatures.spawn(NORMAL_POS, GENGAR, LEVEL, nil)
	local dread = minemon.creatures.spawn(DREAD_POS, GENGAR, LEVEL, nil)
	if not normal or not dread then
		log("spawn failed")
		return
	end
	local ok = minemon.creatures.make_dread(dread)
	log("normal and Dread Gengar placed; make_dread " .. tostring(ok))
	freeze(normal)
	freeze(dread)
	-- The brains set the run speed on each think; this keeps both on their spots for the shots.
	core.register_globalstep(function()
		for _, obj in ipairs(frozen) do
			if obj:is_valid() then
				local le = obj:get_luaentity()
				if le then
					le.run_velocity = 0
					le.walk_velocity = 0
				end
			end
		end
	end)
end

core.register_on_joinplayer(function(player)
	if started then
		return
	end
	started = true
	local ok, res = minemon.party.choose_starter(player, CYNDAQUIL)
	log("starter: " .. tostring(ok) .. " " .. tostring(res and res.species_id or res))
	player:set_pos(PLAYER_POS)
	core.after(SETUP_S, setup)
end)
