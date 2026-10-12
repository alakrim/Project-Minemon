-- minemon_creatures: the look of a Dread creature (T-30, D-031). Glue only (the Luanti API). The rules are in
-- dread_logic.lua. The look is baked into the entity's textures (a colorize and a multiply), its glow and attached
-- particle spawners: thin dark smoke that drifts up, and red sparks about the head (the eyes).
--
-- The look is kept by sync(), which runs from the do_custom hook (runtime.lua) on every step. It is cheap: it only
-- acts when the Dread flag and the look differ. That covers a creature that becomes Dread, or is caught and sent out
-- by minemon_party, after its entity was activated: the party replaces the instance after the spawn.
-- luacheck: read_globals core vector

local M = {}

-- Dark violet-black tint (texture modifiers, applied after the base texture). colorize at full ratio takes the
-- luminance of the texture and the hue of the colour; the multiply lifts it a little so the silhouette still shows
-- at night. Tuned with tests/screenshot/dread.json (T-30).
M.TINT = "^[colorize:#1c0a2a:255^[multiply:#b09ad0"
M.GLOW = 10 -- light level of the entity's own texture (it does not light the world)
M.SMOKE_TEXTURE = "mcl_campfires_particle_1.png^[colorize:#33204a:255" -- VoxeLibre campfire wisp, darkened
M.SMOKE_TEXTURE_OWNED = "mcl_campfires_particle_1.png^[colorize:#4a3a5c:255" -- lighter once it is owned (a trophy)
M.GLINT_TEXTURE = "mcl_particles_smoke.png^[colorize:#ff2040:255" -- the red sparks (the eyes)

local function owned(le)
	return (le.owner ~= nil and le.owner ~= "") or le.tamed == true
end

-- The texture of a creature: the base texture, plus the Dread tint when dread is true.
function M.texture_for(base, dread)
	if dread == true and type(base) == "string" then
		return base .. M.TINT
	end
	return base
end

-- Attached particle spawners on the creature. The offsets follow the collision box height, so a large creature gets
-- its smoke and sparks higher. Returns a list of spawner ids.
local function spawn_fx(le)
	local obj = le.object
	local props = obj:get_properties()
	local box = props and props.collisionbox or { -0.3, 0, -0.3, 0.3, 1, 0.3 }
	local h = math.max(0.5, box[5] or 1)
	local hw = math.max(0.3, math.abs(box[4] or 0.3))
	local smoke = owned(le) and M.SMOKE_TEXTURE_OWNED or M.SMOKE_TEXTURE
	return {
		core.add_particlespawner({
			amount = 2.0, -- per second: sparse, thin wisps
			time = 0,
			minpos = { x = -hw, y = h * 0.3, z = -hw },
			maxpos = { x = hw, y = h * 0.9, z = hw },
			minvel = { x = -0.04, y = 0.12, z = -0.04 },
			maxvel = { x = 0.04, y = 0.30, z = 0.04 },
			minacc = { x = 0, y = 0.02, z = 0 },
			maxacc = { x = 0, y = 0.06, z = 0 },
			minexptime = 1.6,
			maxexptime = 3.2,
			minsize = 1.2,
			maxsize = 3.0,
			collisiondetection = false,
			attached = obj,
			texture = { name = smoke, alpha = 0.55, alpha_tween = { 1, 0 } },
			glow = 0,
		}),
		-- Red eyes: a cluster of steady sparks about the head. It does not depend on the way the creature faces, so
		-- they show from any side.
		core.add_particlespawner({
			amount = 5.0,
			time = 0,
			minpos = { x = -hw * 0.5, y = h * 0.7, z = -hw * 0.5 },
			maxpos = { x = hw * 0.5, y = h * 0.8, z = hw * 0.5 },
			minvel = { x = 0, y = 0, z = 0 },
			maxvel = { x = 0, y = 0, z = 0 },
			minexptime = 0.3,
			maxexptime = 0.6,
			minsize = 1.0,
			maxsize = 1.6,
			collisiondetection = false,
			attached = obj,
			texture = { name = M.GLINT_TEXTURE, alpha = 1.0, alpha_tween = { 1, 0.4 } },
			glow = 14,
		}),
	}
end

local function turn_on(le)
	local obj = le.object
	if not obj or not obj:is_valid() then
		return
	end
	local base = le._mm_base_texture
	if type(base) == "string" then
		obj:set_properties({ textures = { M.texture_for(base, true) }, glow = M.GLOW })
	end
	le._mm_dread_spawners = spawn_fx(le)
	le._mm_dread_on = true
end

local function turn_off(le)
	local obj = le.object
	for _, id in ipairs(le._mm_dread_spawners or {}) do
		core.delete_particlespawner(id)
	end
	le._mm_dread_spawners = nil
	le._mm_dread_on = nil
	if obj and obj:is_valid() and type(le._mm_base_texture) == "string" then
		obj:set_properties({ textures = { le._mm_base_texture }, glow = 0 })
	end
end

-- Keeps the look in step with the instance's Dread flag. Called every step from do_custom.
function M.sync(le)
	local inst = le._mm
	local want = inst ~= nil and inst.dread == true
	if want == (le._mm_dread_on == true) then
		return
	end
	if want then
		turn_on(le)
	else
		turn_off(le)
	end
end

-- True when the look is on (for tests).
function M.is_on(le)
	return le ~= nil and le._mm_dread_on == true
end

return M
