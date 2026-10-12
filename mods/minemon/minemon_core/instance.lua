-- One owned creature. Pure: stats and move data come in through the arguments.
-- M.create(formulas, data) returns the instance API; init.lua exposes it as minemon.instance.
--   formulas: the minemon.formulas module.  data: the minemon.data registry (needs get_move).

local M = {}

M.MAX_MOVES = 4
M.DEFAULT_BALL = "poke_ball"
M.DEFAULT_STATUS = "none"
M.IV_KEYS = { "hp", "atk", "def", "spa", "spd", "spe" }

-- Dread variants (T-30, D-031): a corrupted creature has x1.25 on hp, atk, spa and spe while wild, and x1.10 once
-- owned. Defence and special defence are not changed.
M.DREAD_KEYS = { "hp", "atk", "spa", "spe" }
M.DREAD_MULT_WILD = 1.25
M.DREAD_MULT_OWNED = 1.10

-- Scalar fields copied by serialize and deserialize.
local SCALARS = { "uid", "species_id", "nickname", "level", "exp", "bond", "hp", "status", "ball", "shiny", "dread" }

function M.create(formulas, data)
	local I = {}

	-- The last MAX_MOVES distinct moves learned at or below `level`. A move's place is set by its most recent
	-- learn entry, so re-learning a move moves it to the end of the list.
	local function starting_moves(species, level)
		local order = {}
		for _, entry in ipairs(species.learnset or {}) do
			if entry.level <= level then
				for i = #order, 1, -1 do
					if order[i] == entry.move then
						table.remove(order, i)
					end
				end
				order[#order + 1] = entry.move
			end
		end
		local out = {}
		for i = math.max(1, #order - M.MAX_MOVES + 1), #order do
			local id = order[i]
			local move = data.get_move(id)
			out[#out + 1] = { id = id, pp = move and move.pp or 0 }
		end
		return out
	end

	-- Random draws: uid first, then the six IVs in IV_KEYS order.
	function I.new(species, level, rng)
		level = math.max(1, math.floor(level))
		local uid = string.format("%d-%d", species.id, rng:int(1, 1000000000))
		local ivs = {}
		for _, key in ipairs(M.IV_KEYS) do
			ivs[key] = rng:int(0, 15)
		end
		local stats = formulas.calc_stats(species.base_stats, level, ivs, 0)
		return {
			uid = uid,
			species_id = species.id,
			nickname = "",
			level = level,
			exp = formulas.exp_for_level(level, species.growth_rate),
			ivs = ivs,
			bond = 0,
			hp = stats.hp,
			status = M.DEFAULT_STATUS,
			moves = starting_moves(species, level),
			ball = M.DEFAULT_BALL,
			shiny = false,
			dread = false,
			owner = nil,
		}
	end

	-- The stats of an instance. A Dread creature gets the Dread multiplier on four stats (see DREAD_KEYS).
	function I.stats(instance, species)
		local st = formulas.calc_stats(species.base_stats, instance.level, instance.ivs, instance.bond)
		if instance.dread == true then
			local owned = instance.owner ~= nil and instance.owner ~= ""
			local mult = owned and M.DREAD_MULT_OWNED or M.DREAD_MULT_WILD
			for _, key in ipairs(M.DREAD_KEYS) do
				st[key] = math.floor(st[key] * mult)
			end
		end
		return st
	end

	-- A JSON-safe copy: plain strings, numbers, booleans and tables with string keys or array parts.
	function I.serialize(instance)
		local out = {}
		for _, key in ipairs(SCALARS) do
			out[key] = instance[key]
		end
		out.ivs = {}
		for _, key in ipairs(M.IV_KEYS) do
			out.ivs[key] = instance.ivs[key]
		end
		out.moves = {}
		for i, mv in ipairs(instance.moves or {}) do
			out.moves[i] = { id = mv.id, pp = mv.pp }
		end
		out.owner = instance.owner
		return out
	end

	-- Rebuilds an instance from serialize output, filling defaults for missing fields.
	function I.deserialize(t)
		local ivs = {}
		for _, key in ipairs(M.IV_KEYS) do
			ivs[key] = math.floor(tonumber((t.ivs or {})[key]) or 0)
		end
		local moves = {}
		for i, mv in ipairs(t.moves or {}) do
			moves[i] = { id = mv.id, pp = math.floor(tonumber(mv.pp) or 0) }
		end
		return {
			uid = t.uid or "",
			species_id = math.floor(tonumber(t.species_id) or 0),
			nickname = t.nickname or "",
			level = math.floor(tonumber(t.level) or 1),
			exp = math.floor(tonumber(t.exp) or 0),
			ivs = ivs,
			bond = math.floor(tonumber(t.bond) or 0),
			hp = math.floor(tonumber(t.hp) or 0),
			status = t.status or M.DEFAULT_STATUS,
			moves = moves,
			ball = t.ball or M.DEFAULT_BALL,
			shiny = t.shiny == true,
			dread = t.dread == true,
			owner = t.owner,
		}
	end

	return I
end

return M
