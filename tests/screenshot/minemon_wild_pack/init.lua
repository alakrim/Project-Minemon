-- Visual check for T-25c: real wild creatures from minemon.creatures.spawn, with their Cobblemon pack models
-- when the pack is present (stand-ins otherwise). Test-only: loaded only by scripts/screenshot.sh
-- (MINEMON_SHOT_EXTRA_MODS), never shipped.
--
-- Builds a flat stone platform above the spawn ground (the same height rule as minemon_pack_lineup, so the
-- shot positions in tests/screenshot/wild_pack.json are the same), then spawns six wild creatures in a row at
-- z = 0: Rattata, Pidgey, Pikachu, Gastly, Onix and Geodude. They are real creatures: they wander, fight and
-- animate with the brain and the default states. The shot helper teleports the player but cannot make them fly,
-- so gravity is off and the height is snapped here.

-- luacheck: globals VoxelArea
local SPECIES = { 19, 16, 25, 92, 95, 74 }
local STARTER = 155
local LEVEL = 10
local ROW_X0 = -8
local ROW_DX = 4
local ROW_Z = 0
local PLATFORM_X = { -16, 16 }
local PLATFORM_Z = { -12, 6 }
local FLOOR_ABOVE_GROUND = 30
local FLOOR_MIN_Y = 80
local CLEAR_ABOVE = 6
local POLL_S = 0.25

local feet_y = nil
local built = false
local poll_acc = 0
-- Test-only leash: the wild creatures wander, so each one is returned to its spawn point when it strays more
-- than LEASH_R metres away. They keep walking and standing in the shots, and stay in the camera's frame.
local LEASH_R = 2.0
local LEASH_S = 0.5
local leashed = {} -- { obj, home }
local leash_acc = 0

local function log(msg)
	core.log("action", "[minemon_wild_pack] " .. msg)
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

local function spawn_row()
	local n = 0
	for i, dex in ipairs(SPECIES) do
		local pos = { x = ROW_X0 + (i - 1) * ROW_DX, y = feet_y, z = ROW_Z }
		local obj = minemon.creatures.spawn(pos, dex, LEVEL, nil)
		if obj then
			n = n + 1
			leashed[#leashed + 1] = { obj = obj, home = pos }
		else
			log("spawn failed for species " .. dex)
		end
	end
	log("spawned " .. n .. " wild creatures at feet y=" .. feet_y)
end

local function in_platform(p)
	return p.x >= PLATFORM_X[1] and p.x <= PLATFORM_X[2] and p.z >= PLATFORM_Z[1] and p.z <= PLATFORM_Z[2]
end

local function leash_step(dtime)
	leash_acc = leash_acc + dtime
	if leash_acc < LEASH_S then
		return
	end
	leash_acc = 0
	for _, item in ipairs(leashed) do
		if item.obj:is_valid() then
			local p = item.obj:get_pos()
			local dx, dz = p.x - item.home.x, p.z - item.home.z
			if math.sqrt(dx * dx + dz * dz) > LEASH_R then
				item.obj:set_pos(item.home)
				item.obj:set_velocity({ x = 0, y = 0, z = 0 })
			end
		end
	end
end

core.register_globalstep(function(dtime)
	if not feet_y then
		return
	end
	leash_step(dtime)
	poll_acc = poll_acc + dtime
	if poll_acc < POLL_S then
		return
	end
	poll_acc = 0
	for _, player in ipairs(core.get_connected_players()) do
		local p = player:get_pos()
		if in_platform(p) and math.abs(p.y - feet_y) > 0.05 then
			player:set_pos({ x = p.x, y = feet_y, z = p.z })
		end
	end
end)

core.register_on_joinplayer(function(player)
	player:set_physics_override({ gravity = 0 })
	-- The starter chooser opens 1 s after a join with an empty party and would cover the shots, so the starter is
	-- chosen at once (as in minemon_party_shots). Cyndaquil, 155.
	local ok = minemon.party.choose_starter(player, STARTER)
	log("starter chosen: " .. tostring(ok))
	if built then
		return
	end
	built = true
	core.after(0.5, function()
		local ground = core.get_spawn_level(0, 0) or 40
		local floor_y = math.max(math.floor(ground) + FLOOR_ABOVE_GROUND, FLOOR_MIN_Y)
		feet_y = floor_y + 0.5
		build_platform(floor_y)
		spawn_row()
		log("platform at y=" .. floor_y .. " (spawn ground " .. tostring(ground) .. ")")
	end)
end)
