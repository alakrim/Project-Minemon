-- Visual effects for minemon_combat (T-23): particle spawners, the orb trail and the effectiveness text.
-- Glue: it touches core. Every spawner call is capped at MAX_PER_CALL particles.
-- luacheck: read_globals core vector

local SAFE = dofile(core.get_modpath("minemon_combat") .. "/safe.lua")

local M = {}

M.MAX_PER_CALL = 8
M.FEEDBACK_GAP_S = 0.5
M.FEEDBACK_SHOW_S = 1.2
M.FEEDBACK_RANGE_M = 24
M.FEEDBACK_OFFSET_Y = -56

M.TEX = {
	orb = "minemon_combat_orb.png",
	spark = "minemon_combat_spark.png",
	puff = "minemon_combat_puff.png",
}

-- One tint per move type (white textures are multiplied by these).
M.TYPE_COLOUR = {
	normal = "#d8d4b8",
	fire = "#ff7a2e",
	water = "#4f9bff",
	electric = "#ffe14a",
	grass = "#5fd35f",
	ice = "#8fe8ff",
	fighting = "#e0503a",
	poison = "#c35ae0",
	ground = "#e8c070",
	flying = "#6aa6ff",
	psychic = "#ff5fa8",
	bug = "#c8e040",
	rock = "#c8b060",
	ghost = "#8a6fc8",
	dragon = "#7a5cff",
	dark = "#6a5a6e",
	steel = "#d0dcf0",
}

local HUD_TYPE = core.features.hud_def_type_field and "type" or "hud_elem_type"

M.FEEDBACK = {
	super = { text = "Super effective!", colour = 0x33DD55 },
	weak = { text = "Not very effective...", colour = 0xA0A0A0 },
	none = { text = "No effect", colour = 0x303030 },
	crit = { text = "Critical!", colour = 0xFFD700 },
}

function M.colour(type_name)
	return M.TYPE_COLOUR[type_name] or "#ffffff"
end

-- Texture for one particle kind ("orb", "spark" or "puff") tinted for a move type.
function M.texture(kind, type_name)
	return M.TEX[kind] .. "^[multiply:" .. M.colour(type_name)
end

-- Adds one particle spawner, with the per-call cap applied.
function M.spawn(def)
	def.amount = math.min(def.amount or 1, M.MAX_PER_CALL)
	core.add_particlespawner(def)
end

local ZERO = { x = 0, y = 0, z = 0 }

-- Transient effects last about a second and a quarter: the screenshot capture and the server's own timing can lag by
-- up to a second, and an effect that is gone by then is not visible in a capture.
M.BURST_S = 1.2

-- A radial puff at pos.
function M.burst(pos, type_name, kind, speed, time)
	local s = speed or 1
	M.spawn({
		amount = M.MAX_PER_CALL,
		time = time or 0.3,
		minpos = pos,
		maxpos = pos,
		minvel = { x = -s, y = -s, z = -s },
		maxvel = { x = s, y = s, z = s },
		minacc = ZERO,
		maxacc = ZERO,
		minexptime = 0.5,
		maxexptime = M.BURST_S,
		minsize = 5,
		maxsize = 8,
		texture = M.texture(kind, type_name),
		glow = 12,
		collisiondetection = false,
	})
end

-- The beam: eight spawners of sparks spread along the line from a to b.
function M.line(a, b, type_name)
	for i = 1, 8 do
		local t = (i - 0.5) / 8
		local p = vector.add(a, vector.multiply(vector.subtract(b, a), t))
		M.spawn({
			amount = M.MAX_PER_CALL,
			time = M.BURST_S,
			minpos = p,
			maxpos = p,
			minvel = { x = -0.2, y = -0.2, z = -0.2 },
			maxvel = { x = 0.2, y = 0.2, z = 0.2 },
			minacc = ZERO,
			maxacc = ZERO,
			minexptime = 0.6,
			maxexptime = M.BURST_S,
			minsize = 7,
			maxsize = 9,
			texture = M.texture("spark", type_name),
			glow = 14,
			collisiondetection = false,
		})
	end
end

-- The area burst: a shockwave ring on the ground around the centre, expanding out to the given radius, then a
-- puff shell on the centre. Eight spawners for the ring, one for the centre.
function M.sphere(centre, radius, type_name)
	local n = 8
	local speed = radius / M.BURST_S
	for i = 0, n - 1 do
		local a = (i / n) * 2 * math.pi
		local dir = { x = math.cos(a), y = 0.15, z = math.sin(a) }
		local p = vector.add(centre, vector.new(dir.x * 0.8, 0, dir.z * 0.8))
		M.spawn({
			amount = M.MAX_PER_CALL,
			time = M.BURST_S,
			minpos = p,
			maxpos = p,
			minvel = { x = dir.x * speed, y = dir.y, z = dir.z * speed },
			maxvel = { x = dir.x * speed * 1.1, y = dir.y * 1.5, z = dir.z * speed * 1.1 },
			minacc = ZERO,
			maxacc = ZERO,
			minexptime = 0.6,
			maxexptime = M.BURST_S,
			minsize = 6,
			maxsize = 9,
			texture = M.texture("puff", type_name),
			glow = 12,
			collisiondetection = false,
		})
	end
	M.burst(centre, type_name, "puff", 0.5, M.BURST_S)
end

-- The status cloud: four spawners of slow puffs around the centre, alive for time seconds.
function M.cloud(centre, radius, type_name, time)
	local offsets = {
		{ 0.6, 0.2, 0.4 }, { -0.5, 0.4, -0.5 }, { 0.2, 0.6, -0.6 }, { -0.6, 0.1, 0.3 },
	}
	for _, o in ipairs(offsets) do
		local p = vector.add(centre, vector.new(o[1] * radius * 0.5, o[2], o[3] * radius * 0.5))
		M.spawn({
			amount = M.MAX_PER_CALL,
			time = time,
			minpos = vector.subtract(p, vector.new(0.5, 0.2, 0.5)),
			maxpos = vector.add(p, vector.new(0.5, 0.2, 0.5)),
			minvel = { x = -0.1, y = 0.2, z = -0.1 },
			maxvel = { x = 0.1, y = 0.4, z = 0.1 },
			minacc = ZERO,
			maxacc = ZERO,
			minexptime = 1.2,
			maxexptime = 2.4,
			minsize = 5,
			maxsize = 8,
			texture = M.texture("puff", type_name),
			glow = 0,
			collisiondetection = false,
		})
	end
end

-- The melee swoosh: five spark spawners in a vertical arc in front of the user, sweeping forward. The arc lies in the
-- plane of fwd and up, so it reads from the side as well as from the front.
function M.swoosh(centre, fwd, type_name)
	for i = -2, 2 do
		local bulge = 0.4 - 0.1 * math.abs(i)
		local p = vector.add(centre, vector.new(fwd.x * bulge, i * 0.35, fwd.z * bulge))
		M.spawn({
			amount = M.MAX_PER_CALL,
			time = M.BURST_S,
			minpos = p,
			maxpos = p,
			minvel = vector.multiply(fwd, 2),
			maxvel = vector.multiply(fwd, 3),
			minacc = ZERO,
			maxacc = ZERO,
			minexptime = 0.5,
			maxexptime = M.BURST_S,
			minsize = 11,
			maxsize = 13,
			texture = M.texture("spark", type_name),
			glow = 14,
			collisiondetection = false,
		})
	end
end

-- The aura: a ring of sparks around the body centre that rises and fades, for the stat-raising moves.
function M.aura(centre, type_name)
	local n = 8
	for i = 0, n - 1 do
		local a = (i / n) * 2 * math.pi
		local p = vector.add(centre, vector.new(math.cos(a) * 0.9, 0, math.sin(a) * 0.9))
		M.spawn({
			amount = M.MAX_PER_CALL,
			time = M.BURST_S,
			minpos = p,
			maxpos = p,
			minvel = { x = 0, y = 0.6, z = 0 },
			maxvel = { x = 0, y = 1.2, z = 0 },
			minacc = ZERO,
			maxacc = ZERO,
			minexptime = 0.5,
			maxexptime = M.BURST_S,
			minsize = 7,
			maxsize = 9,
			texture = M.texture("spark", type_name),
			glow = 14,
			collisiondetection = false,
		})
	end
end

-- The wind-up on the user while the move is cast.
function M.windup(pos, type_name, time)
	M.spawn({
		amount = M.MAX_PER_CALL,
		time = math.max(0.1, time or 0.3),
		minpos = vector.subtract(pos, vector.new(0.4, 0.2, 0.4)),
		maxpos = vector.add(pos, vector.new(0.4, 0.2, 0.4)),
		minvel = { x = 0, y = 0.5, z = 0 },
		maxvel = { x = 0, y = 1, z = 0 },
		minacc = ZERO,
		maxacc = ZERO,
		minexptime = 0.4,
		maxexptime = 0.7,
		minsize = 3,
		maxsize = 5,
		texture = M.texture("spark", type_name),
		glow = 12,
		collisiondetection = false,
	})
end

-- The trail behind a flying orb.
function M.orb_trail(pos, type_name)
	M.spawn({
		amount = 2,
		time = 0.1,
		minpos = pos,
		maxpos = pos,
		minvel = ZERO,
		maxvel = ZERO,
		minacc = ZERO,
		maxacc = ZERO,
		minexptime = 0.4,
		maxexptime = 0.7,
		minsize = 4,
		maxsize = 6,
		texture = M.texture("puff", type_name),
		glow = 12,
		collisiondetection = false,
	})
end

-- Short HUD text near the crosshair. One message per player per FEEDBACK_GAP_S, shown for FEEDBACK_SHOW_S.
local last_shown = {}

function M.feedback(player, text, colour)
	local name = player:get_player_name()
	local t = core.get_gametime()
	if last_shown[name] and t - last_shown[name] < M.FEEDBACK_GAP_S then
		return false
	end
	last_shown[name] = t
	local id = player:hud_add({
		[HUD_TYPE] = "text",
		position = { x = 0.5, y = 0.5 },
		offset = { x = 0, y = M.FEEDBACK_OFFSET_Y },
		text = text,
		number = colour,
		alignment = { x = 0, y = 0 },
		size = { x = 2 },
		z_index = 100,
	})
	core.after(M.FEEDBACK_SHOW_S, function()
		SAFE.call("feedback hud removal", function()
			if player:get_pos() then
				player:hud_remove(id)
			end
		end)
	end)
	return true
end

return M
