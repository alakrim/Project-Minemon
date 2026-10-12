-- Visual check for the T-23 combat effects: one scene per archetype. Test-only: loaded only by scripts/screenshot.sh
-- (MINEMON_SHOT_EXTRA_MODS), never shipped. Keep SCENES in sync with tests/screenshot/combat_fx.json.
--
-- The shot helper (tests/screenshot/minemon_shots) teleports the player to each shot's position, waits wait_s
-- seconds, clears the HUD, waits 1 s more and then the capture happens. This helper watches the player: when the
-- player stands on a scene's camera position it spawns the scene's creatures and calls minemon.combat.use_move at a
-- time chosen so that the effect is still in flight at the capture (show_s seconds after the effect starts).
--
-- luacheck: read_globals core minemon vector VoxelManip VoxelArea

local WAIT_S = 2 -- wait_s in combat_fx.json
local CAPTURE_S = WAIT_S + 1 -- minemon_shots waits wait_s, clears the HUD, waits 1 s, then captures
local MATCH_R = 0.3
local POLL_S = 0.1
local LEVEL = 20
local FLOOR_Y = 180 -- above the terrain of the screenshot seed (seed 1337)
local ABOVE = 6
local PLATFORM = { x0 = -52, x1 = 52, z0 = -12, z1 = 12 }
local SCENE_Z = 0
local CLEAR_R = 30 -- natural spawns within this radius of a scene are removed, so the scene reads clearly

-- cx: scene centre x. user and target stand d metres apart on x (user on the -x side). cam_z: the camera z for the
-- scene (the camera looks along +z), far enough back that both creatures fit the frame. show_s: how long after the
-- effect starts the capture should see it. The capture lags the timer by up to about half a second (the shell polls
-- for the marker), so the transient effects last about a second (vfx.BURST_S) and the orb launches at the capture.
local SCENES = {
	{ name = "fx_projectile", cx = -40, cam_z = -9, user = 155, target = 1, move = "ember", d = 11, show_s = 0.1 },
	{ name = "fx_beam", cx = -24, cam_z = -6, user = 7, target = 1, move = "aeroblast", d = 6, show_s = 0.3 },
	{ name = "fx_melee", cx = -8, cam_z = -4.5, user = 1, target = 4, move = "wing_attack", d = 1.6, show_s = 0.3 },
	{ name = "fx_area", cx = 8, cam_z = -4.5, user = 1, target = 7, move = "razor_leaf", d = 4, show_s = 0.3 },
	{ name = "fx_aura", cx = 24, cam_z = -4.5, user = 25, target = 4, move = "agility", d = 4, show_s = 0.3 },
	{ name = "fx_cloud", cx = 40, cam_z = -4.5, user = 1, target = 155, move = "spore", d = 4, show_s = 1.0 },
}

local feet_y = nil
local active = {}
local armed = nil
local poll_acc = 0

local function log(msg)
	core.log("action", "[minemon_combat_fx] " .. msg)
end

local function build_platform(floor_y)
	local vm = VoxelManip()
	local emin, emax = vm:read_from_map(vector.new(PLATFORM.x0, floor_y, PLATFORM.z0),
		vector.new(PLATFORM.x1, floor_y + ABOVE, PLATFORM.z1))
	local area = VoxelArea:new({ MinEdge = emin, MaxEdge = emax })
	local data = vm:get_data()
	local c_air = core.get_content_id("air")
	local c_stone = core.get_content_id("mcl_core:stone")
	for z = PLATFORM.z0, PLATFORM.z1 do
		for x = PLATFORM.x0, PLATFORM.x1 do
			for y = floor_y, floor_y + ABOVE do
				data[area:index(x, y, z)] = (y == floor_y) and c_stone or c_air
			end
		end
	end
	vm:set_data(data)
	vm:write_to_map(true)
end

local function clear_active()
	for _, a in ipairs(active) do
		if a.obj:get_pos() then
			a.obj:remove()
		end
	end
	active = {}
end

-- A wild creature standing still at pos, facing yaw, with one move.
local function spawn_fixed(pos, species_id, yaw, move_id)
	local obj = minemon.creatures.spawn(pos, species_id, LEVEL, nil)
	if not obj then
		log("spawn failed for species " .. species_id)
		return nil
	end
	local inst = minemon.creatures.get_instance(obj)
	local m = minemon.data.get_move(move_id)
	inst.moves = { { id = move_id, pp = m and m.pp or 0 } }
	local le = obj:get_luaentity()
	le.walk_velocity = 0
	le.run_velocity = 0
	obj:set_yaw(yaw)
	active[#active + 1] = { obj = obj, pos = pos, yaw = yaw }
	return obj
end

-- Removes natural spawns and other mobs near the scene. Our own creatures are removed by clear_active first.
local function clear_mobs(centre)
	for _, obj in ipairs(core.get_objects_inside_radius(centre, CLEAR_R)) do
		local le = (not obj:is_player()) and obj:get_luaentity() or nil
		if le and le.is_mob then
			obj:remove()
		end
	end
end

local function arm(scene)
	clear_active()
	clear_mobs(vector.new(scene.cx, feet_y, SCENE_Z))
	local cx = scene.cx
	local user_pos = vector.new(cx - scene.d / 2, feet_y + 0.5, SCENE_Z)
	local target_pos = vector.new(cx + scene.d / 2, feet_y + 0.5, SCENE_Z)
	local user = spawn_fixed(user_pos, scene.user, -math.pi / 2, scene.move)
	local target = spawn_fixed(target_pos, scene.target, math.pi / 2, "tackle")
	if not user or not target then
		return
	end
	local m = minemon.data.get_move(scene.move)
	local delay = CAPTURE_S - m.cast_s - scene.show_s
	log(string.format("arming %s: %s -> %s, %s in %.2f s", scene.name, user:get_luaentity().nametag or "?",
		target:get_luaentity().nametag or "?", scene.move, delay))
	core.after(delay, function()
		if user:get_pos() and target:get_pos() then
			local ok, why = minemon.combat.use_move(user, target, scene.move)
			log(string.format("%s use_move: %s %s", scene.name, tostring(ok), tostring(why)))
		end
	end)
end

local function scene_at(p)
	for _, s in ipairs(SCENES) do
		if math.abs(p.x - s.cx) < MATCH_R and math.abs(p.z - s.cam_z) < MATCH_R then
			return s
		end
	end
	return nil
end

-- Holds the creatures on their marks and arms the scene under the player.
core.register_globalstep(function(dtime)
	if not feet_y then
		return
	end
	poll_acc = poll_acc + dtime
	if poll_acc < POLL_S then
		return
	end
	poll_acc = 0
	for _, a in ipairs(active) do
		local p = a.obj:get_pos()
		if p and vector.distance(p, a.pos) > 0.05 then
			a.obj:set_pos(a.pos)
			a.obj:set_yaw(a.yaw)
		end
	end
	for _, player in ipairs(core.get_connected_players()) do
		local p = player:get_pos()
		if p and math.abs(p.y - feet_y) > 0.05 and scene_at(p) then
			player:set_pos({ x = p.x, y = feet_y, z = p.z })
		end
		local s = p and scene_at(p)
		if s and s.name ~= armed then
			armed = s.name
			arm(s)
		end
	end
end)

-- The platform floats above the terrain, so the scenes read against sky. It is built once the mod has loaded, before
-- the client joins, so the first capture is not taken while the blocks are still arriving.
local function ensure_platform()
	if feet_y then
		return
	end
	feet_y = FLOOR_Y + 0.5
	build_platform(FLOOR_Y)
	log("platform at y=" .. FLOOR_Y)
end

core.after(0.5, ensure_platform)

core.register_on_joinplayer(function(player)
	player:set_physics_override({ gravity = 0 })
	core.after(0.5, ensure_platform)
end)
