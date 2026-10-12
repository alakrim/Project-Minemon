-- Pure move rules for minemon_combat (no Luanti API, so busted can test them).
-- Archetypes, stage limits, the player damage rule and move validation (T-23 brief).

local M = {}

M.ARCHETYPES = {
	projectile = true,
	beam = true,
	melee_arc = true,
	area_burst = true,
	aura = true,
	status_cloud = true,
}

M.CATEGORIES = { physical = true, special = true, status = true }
M.STAT_KEYS = { atk = true, def = true, spa = true, spd = true, spe = true, acc = true, eva = true }
M.TARGETS = { user = true, target = true }

-- The statuses named in moves.json that the status pass models (T-31; effects_logic.DATA_STATUS maps them). Others
-- (disable, perish-song, no-type-immunity) are reported by effects_logic.gaps.
M.STATUSES = {
	burn = true, poison = true, paralysis = true, sleep = true, freeze = true,
	confusion = true, trap = true, ["leech-seed"] = true, protect = true,
}

M.STAGE_MIN = -6
M.STAGE_MAX = 6
M.MELEE_MAX_RANGE = 3.5
-- Body size slack on range checks: centres are compared, and a creature's body is half a node or so wide.
M.RANGE_SLACK = 0.5
M.PLAYER_DAMAGE_DIVISOR = 4
M.PLAYER_DAMAGE_MIN = 1
M.PLAYER_DAMAGE_MAX = 8

local function clamp(v, lo, hi)
	if v < lo then
		return lo
	end
	if v > hi then
		return hi
	end
	return v
end

-- Archetypes that need a target (aura moves act on the user).
function M.needs_target(archetype)
	return archetype ~= "aura"
end

function M.needs_range(archetype)
	return archetype == "projectile" or archetype == "beam" or archetype == "melee_arc"
		or archetype == "area_burst" or archetype == "status_cloud"
end

function M.clamp_stage(value)
	return clamp(math.floor(value), M.STAGE_MIN, M.STAGE_MAX)
end

-- Players are not Gen 2 combatants: the damage is divided by 4 and kept in 1..8 (T-23 brief).
function M.player_damage(amount)
	return clamp(math.floor(amount / M.PLAYER_DAMAGE_DIVISOR), M.PLAYER_DAMAGE_MIN, M.PLAYER_DAMAGE_MAX)
end

-- Returns nil when the move can work, otherwise the reason it cannot.
function M.validate(move)
	if type(move) ~= "table" then
		return "move is not a table"
	end
	if not M.ARCHETYPES[move.archetype] then
		return "unknown archetype " .. tostring(move.archetype)
	end
	if not M.CATEGORIES[move.category] then
		return "unknown category " .. tostring(move.category)
	end
	if type(move.type) ~= "string" then
		return "type is missing"
	end
	if type(move.cast_s) ~= "number" or move.cast_s < 0 then
		return "cast_s must be a number >= 0"
	end
	if type(move.cooldown_s) ~= "number" or move.cooldown_s <= 0 then
		return "cooldown_s must be a number > 0"
	end
	if type(move.range_m) ~= "number" or move.range_m < 0 then
		return "range_m must be a number >= 0"
	end
	if type(move.pp) ~= "number" or move.pp < 1 then
		return "pp must be a number >= 1"
	end
	if move.power ~= nil and type(move.power) ~= "number" then
		return "power must be a number or null"
	end
	if move.accuracy ~= nil and (type(move.accuracy) ~= "number" or move.accuracy < 0 or move.accuracy > 100) then
		return "accuracy must be 0..100 or null"
	end
	if type(move.effect) ~= "table" then
		return "effect must be a table"
	end
	if M.needs_range(move.archetype) and move.range_m <= 0 then
		return "range_m must be > 0 for archetype " .. move.archetype
	end
	if move.archetype == "melee_arc" and move.range_m > M.MELEE_MAX_RANGE then
		return "melee range_m is over " .. M.MELEE_MAX_RANGE
	end
	local effect = move.effect
	if effect.status ~= nil and type(effect.status) ~= "string" then
		return "effect.status must be a string"
	end
	for _, change in ipairs(effect.stat_changes or {}) do
		if not M.STAT_KEYS[change.stat] then
			return "unknown stat " .. tostring(change.stat)
		end
		if type(change.stages) ~= "number" or change.stages == 0 then
			return "stat change needs non-zero stages"
		end
		if not M.TARGETS[change.target] then
			return "stat change target must be user or target"
		end
	end
	return nil
end

-- Valid moves that will not work as their name suggests. Returns a list of strings (may be empty).
function M.warnings(move)
	local out = {}
	local effect = move.effect or {}
	if move.category ~= "status" and move.power == nil then
		out[#out + 1] = "no power: deals no damage"
	end
	if effect.status ~= nil and not M.STATUSES[effect.status] then
		out[#out + 1] = "status " .. effect.status .. " is outside the minimal set: ignored"
	end
	if move.category == "status" and effect.status == nil and effect.stat_changes == nil then
		out[#out + 1] = "status move with no effect in its data (see effects_logic.gaps)"
	end
	return out
end

return M
