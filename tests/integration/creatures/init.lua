-- Integration test (T-21a, T-21b, T-25c): minemon_creatures registers all 251 species; spawn() gives the requested
-- level, health, nametag and, when the pack is loaded, the pack's model and texture (T-25c); owned spawns are tamed
-- and never despawn; a wild creature survives 5 s; and the server step interval is measured with no creatures,
-- then with 40 creatures on a flat stone platform in a forceloaded 64x64 area.
-- Natural spawns need players, so the creatures are spawned directly. T-21b: the platform is built with set_node at
-- a fixed height, so the test no longer depends on the world seed (the old centre search failed 1 run in 4).
-- Writes PASS n or FAIL <reason> to test_result.txt, then shuts down.
-- luacheck: read_globals core minemon vector

local BASE_WINDOW_S = 8 -- step interval with no creatures
local LOAD_WINDOW_S = 75 -- step interval with PERF_COUNT creatures (the run stays under the 120 s timeout)
local SKIP_STEPS = 20 -- samples right after a phase change are skipped
local PERF_COUNT = 40
local HALF = 32 -- the perf area is 64x64 around the centre
local PLATFORM_Y = 5 -- stone top at y = 5; creatures stand at y = 6
local TOP, BOTTOM = 12, -4 -- vertical extent of the platform, the emerge box and the forceload range

local finished = false
local function finish(line)
	if finished then
		return
	end
	finished = true
	core.safe_file_write(core.get_worldpath() .. "/test_result.txt", line .. "\n")
	core.request_shutdown()
end

local function check(cond, msg)
	if not cond then
		error(msg, 0)
	end
end

local function registration_check()
	local ids = minemon.data.all_species_ids()
	check(#ids == 251, "expected 251 species, got " .. #ids)
	local seen = {}
	for _, id in ipairs(ids) do
		local sp = minemon.data.get_species(id)
		check(sp, "species " .. id .. " missing")
		local name = minemon.creatures.entity_name(sp)
		check(core.registered_entities[name], "not registered: " .. name)
		check(not seen[name], "duplicate entity name: " .. name)
		seen[name] = true
	end
	check(minemon.creatures.key_for("Mr. Mime") == "mr_mime", "key_for(Mr. Mime) is wrong")
	return #ids
end

-- Wild and owned spawns at pos. Returns the number of checks made.
local function spawn_checks(pos)
	local obj = minemon.creatures.spawn(pos, 19, 7, nil)
	check(obj, "spawn(Rattata, 7) returned nil")
	local inst = minemon.creatures.get_instance(obj)
	check(inst, "no instance on the spawned object")
	check(inst.level == 7, "level is " .. tostring(inst.level) .. ", want 7")
	local le = obj:get_luaentity()
	check(le.health == inst.hp, "luaentity health " .. tostring(le.health) .. " ~= instance hp " .. inst.hp)
	check(obj:get_hp() == inst.hp, "object hp " .. obj:get_hp() .. " ~= instance hp " .. inst.hp)
	check(le.can_despawn == true, "wild creature must be able to despawn")
	check(not le.tamed, "wild creature must not be tamed")
	check(string.find(le.nametag or "", "Lv 7", 1, true), "nametag has no 'Lv 7': " .. tostring(le.nametag))
	check(string.find(le.nametag or "", "Rattata", 1, true), "nametag has no species name")
	local c = obj:get_properties().nametag_color
	if type(c) == "table" then
		check(c.r == 255 and c.g == 48 and c.b == 48, "Rattata nametag colour should be #FF3030")
	else
		check(string.upper(tostring(c)):find("FF3030", 1, true), "Rattata nametag colour should be #FF3030")
	end
	-- T-25c: with the Cobblemon pack the model, texture and collision box are the pack's; without it, the stand-in's.
	local props = obj:get_properties()
	local pack = rawget(_G, "minemon_pack")
	local entry = pack and pack.models and pack.models[19]
	local want_h = 0.25
	core.log("action", "[creatures_test] T-25c visuals: pack entry for Rattata " .. (entry and "present" or "absent"))
	if entry then
		want_h = math.min(4, math.max(0.3, entry.height))
		check(props.mesh == entry.mesh, "Rattata mesh should be " .. entry.mesh .. ", got " .. tostring(props.mesh))
		local want_tex = inst.shiny and entry.texture_shiny or entry.texture
		check(props.textures[1] == want_tex,
			"Rattata texture should be " .. want_tex .. ", got " .. tostring(props.textures[1]))
		check(props.visual_size.x == 1 and props.visual_size.y == 1, "pack models have visual_size 1")
	else
		check(props.mesh == "mm_quadruped.glb", "stand-in Rattata mesh should be mm_quadruped.glb")
	end
	check(type(inst.shiny) == "boolean", "a wild spawn must carry a shiny flag")
	local box = props.collisionbox
	check(box and math.abs(box[5] - want_h) < 1e-3, "Rattata collision box height should be " .. want_h)
	check(minemon.creatures.is_exhausted(obj) == false, "is_exhausted must be false in T-21a")
	check(minemon.creatures.spawn(pos, 99999, 5, nil) == nil, "unknown species should return nil")

	local owned = minemon.creatures.spawn(pos, 25, 12, "tester")
	check(owned, "owned spawn returned nil")
	local ole = owned:get_luaentity()
	check(ole.can_despawn == false, "owned creature must not despawn")
	check(ole.persistent == true, "owned creature must be persistent")
	check(ole.tamed == true, "owned creature must be tamed")
	check(ole.owner == "tester", "owner is " .. tostring(ole.owner))
	check(minemon.creatures.get_instance(owned).level == 12, "owned level is wrong")
	return 16
end

-- Step interval measurement. Registered at load time (globalsteps cannot be added later).
local perf = nil

local function phase_summary(p)
	if p.count == 0 then
		return -1, 0
	end
	return p.sum / p.count, p.max
end

local function spawn_perf(positions)
	local creatures = {}
	local ids = { 19, 16, 25, 133, 122, 95, 4, 1, 143, 152 } -- land species only: fish die out of water
	for i = 1, PERF_COUNT do
		local pos = positions[(i - 1) % #positions + 1]
		local id = ids[(i - 1) % #ids + 1]
		local obj = minemon.creatures.spawn(pos, id, 5 + (i % 10), nil)
		check(obj, "perf spawn " .. i .. " failed")
		creatures[#creatures + 1] = { obj = obj, id = id }
	end
	return creatures
end

local function perf_step()
	if not perf or perf.report then
		return
	end
	local now = core.get_us_time()
	if perf.last then
		perf.steps = perf.steps + 1
		if perf.steps > SKIP_STEPS then
			local ms = (now - perf.last) / 1000
			local p = perf[perf.phase]
			p.sum = p.sum + ms
			p.count = p.count + 1
			if ms > p.max then
				p.max = ms
			end
		end
	end
	perf.last = now
	local elapsed = (now - perf.phase_started) / 1e6
	if perf.phase == "base" and elapsed >= BASE_WINDOW_S then
		local ok, res = pcall(spawn_perf, perf.positions)
		if not ok then
			perf.report = true
			finish("FAIL " .. tostring(res))
			return
		end
		perf.creatures = res
		perf.phase = "load"
		perf.phase_started = now
		perf.steps = 0
	elseif perf.phase == "load" and elapsed >= LOAD_WINDOW_S then
		perf.report = true
		local alive = 0
		for _, c in ipairs(perf.creatures) do
			if c.obj:get_pos() then
				alive = alive + 1
			end
		end
		local base_avg, base_max = phase_summary(perf.base)
		local load_avg, load_max = phase_summary(perf.load)
		finish(string.format("PASS %d checks; step_interval_ms base_avg=%.2f base_max=%.2f "
			.. "load_avg=%.2f load_max=%.2f steps=%d creatures=%d alive=%d",
			perf.checks, base_avg, base_max, load_avg, load_max, perf.load.count, #perf.creatures, alive))
	end
end
core.register_globalstep(perf_step)

-- Forceloads every mapblock that covers the 64x64 area between BOTTOM and TOP, so the creatures stay active.
-- Returns the number of blocks forceloaded.
local function forceload_area(cx, cz)
	local blocks = 0
	local lo = math.floor((PLATFORM_Y + BOTTOM) / 16) * 16
	local hi = math.floor((PLATFORM_Y + TOP) / 16) * 16
	for y = lo, hi, 16 do
		for x = cx - HALF, cx + HALF - 1, 16 do
			for z = cz - HALF, cz + HALF - 1, 16 do
				if core.forceload_block(vector.new(x, y, z), true, 256) then
					blocks = blocks + 1
				end
			end
		end
	end
	return blocks
end

-- Builds the platform over the 64x64 area: stone at PLATFORM_Y, air above it up to TOP, so the creatures always
-- stand on flat ground whatever the world seed. Returns the standing positions on a 4-node grid.
local function build_platform(cx, cz)
	local positions = {}
	for x = cx - HALF, cx + HALF - 1 do
		for z = cz - HALF, cz + HALF - 1 do
			core.set_node(vector.new(x, PLATFORM_Y, z), { name = "mcl_core:stone" })
			for y = PLATFORM_Y + 1, TOP do
				core.set_node(vector.new(x, y, z), { name = "air" })
			end
			if (x - cx) % 4 == 0 and (z - cz) % 4 == 0 then
				positions[#positions + 1] = vector.new(x, PLATFORM_Y + 1, z)
			end
		end
	end
	return positions
end

local function run(positions, checks)
	-- The probe stands near the platform centre, away from the perf creatures and the platform edge.
	local probe_pos = vector.new(8, PLATFORM_Y + 1, 8)
	local probe = minemon.creatures.spawn(probe_pos, 19, 3, nil)
	if not probe then
		finish("FAIL probe spawn failed")
		return
	end
	local probe_le = probe:get_luaentity()
	core.after(5, function()
		if not probe:get_pos() then
			finish(string.format("FAIL probe creature gone after 5 s (last health %s, spawned at %s)",
				tostring(probe_le.health), core.pos_to_string(probe_pos, 1)))
			return
		end
		perf = {
			phase = "base", phase_started = core.get_us_time(), last = nil, steps = 0, creatures = {},
			positions = positions, checks = checks + 1,
			base = { sum = 0, count = 0, max = 0 }, load = { sum = 0, count = 0, max = 0 },
		}
	end)
end

-- Emerges the box, builds the platform, forceloads it, and runs the checks at the platform centre.
local function setup_and_run()
	core.emerge_area(vector.new(-HALF, BOTTOM, -HALF), vector.new(HALF, TOP, HALF),
		function(_, _, calls_remaining)
			if calls_remaining ~= 0 then
				return
			end
			local ok, err = pcall(function()
				local positions = build_platform(0, 0)
				check(#positions >= PERF_COUNT, "platform has " .. #positions .. " positions")
				check(forceload_area(0, 0) >= 16, "forceload failed")
				local n = registration_check()
				local centre = vector.new(0, PLATFORM_Y + 1, 0)
				n = n + spawn_checks(centre)
				run(positions, n)
			end)
			if not ok then
				finish("FAIL " .. tostring(err))
			end
		end)
end

core.after(1, setup_and_run)
