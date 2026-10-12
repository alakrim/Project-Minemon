-- Gen 2 rules for stats, damage, catching, experience and wild levels.
-- Pure: no Luanti API, so busted can test it. Port of the archived Godot core (godot-prototype branch).
-- All integer divisions use math.floor on non-negative values, which matches GDScript integer division.

local M = {}

M.STAT_KEYS = { "hp", "atk", "def", "spa", "spd", "spe" }

local CRIT_CHANCE = 1 / 16
local HIGH_CRIT_CHANCE = 1 / 4
local CRIT_MULT = 2
local STAB_MULT = 1.5
local RANDOM_MIN = 85
local RANDOM_MAX = 100

local function clamp(n, lo, hi)
	if n < lo then
		return lo
	end
	if n > hi then
		return hi
	end
	return n
end

local function stage_of(view, key)
	local stages = view.stages or {}
	return math.floor(tonumber(stages[key]) or 0)
end

-- Stage multiplier: stage s gives (2 + max(s, 0)) / (2 + max(-s, 0)), with s clamped to -6..6.
function M.stage_mult(stage)
	local s = clamp(math.floor(tonumber(stage) or 0), -6, 6)
	return (2 + math.max(s, 0)) / (2 + math.max(-s, 0))
end

-- base: species base_stats. ivs: 0..15 per stat. bond: 0..255, adds floor(bond/25) percent to every stat.
-- HP = floor((2b+iv)L/100) + L + 10; others = floor((2b+iv)L/100) + 5; then x (100 + floor(bond/25)) / 100, floored.
function M.calc_stats(base, level, ivs, bond)
	base = base or {}
	ivs = ivs or {}
	local bonus_percent = 100 + math.floor(clamp(tonumber(bond) or 0, 0, 255) / 25)
	local out = {}
	for _, key in ipairs(M.STAT_KEYS) do
		local core_value = math.floor((2 * (base[key] or 0) + (ivs[key] or 0)) * level / 100)
		local value
		if key == "hp" then
			value = core_value + level + 10
		else
			value = core_value + 5
		end
		out[key] = math.floor(value * bonus_percent / 100)
	end
	return out
end

local function fixed_amount(fixed, atk)
	if type(fixed) == "string" then
		return atk.level
	end
	return math.floor(tonumber(fixed) or 0)
end

-- atk, def: views {level, stats, types, status, stages}. move: move data. type_mult_fn(atk_type, def_types).
-- rng: object with :float() and :int(a, b). Roll order is fixed (accuracy, crit, spread) so seeded runs repeat.
-- Returns {amount, crit, effectiveness, missed}.
function M.damage(atk, def, move, type_mult_fn, rng)
	local effect = move.effect or {}
	local result = { amount = 0, crit = false, effectiveness = 1.0, missed = false }
	result.effectiveness = type_mult_fn(move.type, def.types or {})

	if move.accuracy ~= nil then
		local hit_chance = move.accuracy * M.stage_mult(stage_of(atk, "acc")) / M.stage_mult(stage_of(def, "eva"))
		if rng:float() * 100 >= hit_chance then
			result.missed = true
			return result
		end
	end

	if move.category == "status" then
		return result
	end

	if effect.fixed_damage ~= nil then
		if result.effectiveness > 0 then
			result.amount = fixed_amount(effect.fixed_damage, atk)
		end
		return result
	end

	if move.power == nil then
		return result
	end

	local physical = move.category == "physical"
	local atk_key = physical and "atk" or "spa"
	local def_key = physical and "def" or "spd"
	local attack = math.floor((atk.stats[atk_key] or 1) * M.stage_mult(stage_of(atk, atk_key)))
	local defence = math.floor((def.stats[def_key] or 1) * M.stage_mult(stage_of(def, def_key)))
	defence = math.max(defence, 1)

	-- Base damage: floor(floor(floor(2L/5 + 2) * power * A / D) / 50) + 2.
	local level_term = math.floor(2 * atk.level / 5) + 2
	local base = math.floor(math.floor(level_term * move.power * attack / defence) / 50) + 2

	local crit_chance = effect.high_crit and HIGH_CRIT_CHANCE or CRIT_CHANCE
	result.crit = rng:float() < crit_chance
	local roll = rng:int(RANDOM_MIN, RANDOM_MAX) / 100

	if result.effectiveness <= 0 then
		return result
	end

	local stab = 1.0
	for _, t in ipairs(atk.types or {}) do
		if t == move.type then
			stab = STAB_MULT
			break
		end
	end
	local crit_mult = result.crit and CRIT_MULT or 1
	local raw = base * stab * result.effectiveness * crit_mult * roll
	result.amount = math.max(1, math.floor(raw))
	return result
end

-- Chance (0..1) that a ball with ball_mult catches a creature with catch_rate at hp_frac (0..1).
-- a = (3 - 2 hp_frac) * catch_rate * ball_mult / 3 * status_mult; chance = clamp(a / 255, 0, 1).
local function status_mult(status)
	if status == "sleep" or status == "freeze" then
		return 2
	end
	if status == "paralysis" or status == "burn" or status == "poison" then
		return 1.5
	end
	return 1
end

function M.catch_chance(catch_rate, hp_frac, ball_mult, status)
	local frac = clamp(tonumber(hp_frac) or 0, 0, 1)
	local a = (3 - 2 * frac) * catch_rate * ball_mult / 3 * status_mult(status)
	return clamp(a / 255, 0, 1)
end

-- Experience. Curves are the Gen 1-2 formulas for the six growth rates.
-- The data files name the "medium_fast" curve "medium"; both names are accepted.
local CURVES = {}

local function n_cube(n)
	return n * n * n
end

CURVES.fast = function(n)
	return math.floor(4 * n_cube(n) / 5)
end

CURVES.medium_fast = function(n)
	return n_cube(n)
end

CURVES.medium_slow = function(n)
	return math.floor(6 * n_cube(n) / 5) - 15 * n * n + 100 * n - 140
end

CURVES.slow = function(n)
	return math.floor(5 * n_cube(n) / 4)
end

CURVES.erratic = function(n)
	local n3 = n_cube(n)
	if n <= 50 then
		return math.floor(n3 * (100 - n) / 50)
	end
	if n <= 68 then
		return math.floor(n3 * (150 - n) / 100)
	end
	if n <= 98 then
		return math.floor(n3 * math.floor((1911 - 10 * n) / 3) / 500)
	end
	return math.floor(n3 * (160 - n) / 100)
end

CURVES.fluctuating = function(n)
	local n3 = n_cube(n)
	if n <= 15 then
		return math.floor(n3 * (math.floor((n + 1) / 3) + 24) / 50)
	end
	if n <= 35 then
		return math.floor(n3 * (n + 14) / 50)
	end
	return math.floor(n3 * (math.floor(n / 2) + 32) / 50)
end

local ALIASES = { medium = "medium_fast" }

local function curve_for(growth)
	local name = ALIASES[growth] or growth
	local curve = CURVES[name]
	assert(curve, "minemon: unknown growth rate " .. tostring(growth))
	return curve
end

-- Total experience needed to reach `level` (1..100). Level 1 is always 0.
function M.exp_for_level(level, growth)
	local n = clamp(math.floor(level), 1, 100)
	if n <= 1 then
		return 0
	end
	return math.max(curve_for(growth)(n), 0)
end

-- Highest level (1..100) whose total experience is <= total_exp.
function M.level_for_exp(total_exp, growth)
	curve_for(growth) -- fails early on an unknown growth rate
	local best = 1
	for lv = 2, 100 do
		if M.exp_for_level(lv, growth) <= total_exp then
			best = lv
		else
			break
		end
	end
	return best
end

-- Experience gained from defeating a species: floor(base_exp * L / 7 * (1 + bond / 510)).
function M.exp_gain(base_exp, defeated_level, bond)
	local bond_mult = 1 + clamp(tonumber(bond) or 0, 0, 255) / 510
	return math.floor(base_exp * defeated_level / 7 * bond_mult)
end

-- Wild level for a spawn distance from the world origin. Base 2 + floor(d / 80), jitter -2..+2 from rng,
-- night x 1.2 (floored), clamped to 2..70.
function M.wild_level(distance_from_origin, is_night, rng)
	local d = math.max(tonumber(distance_from_origin) or 0, 0)
	local level = 2 + math.floor(d / 80) + rng:int(-2, 2)
	if is_night then
		level = math.floor(level * 1.2)
	end
	return clamp(level, 2, 70)
end

return M
