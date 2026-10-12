-- Pure rules for minemon_growth (T-27, D-030). No `core` access, so busted can test them (docs/CONVENTIONS.md).
-- init.lua is the Luanti glue: chat, formspecs, the evolution cinematic, the items and the party writes.
--
-- Numbers: bond 0..255. Levels and exp follow minemon.formulas, which is passed in as F wherever it is needed, so this
-- file never reads the global table. Evolution conditions are the keys of data/species.json (every key must hold).
-- Functions never mutate their inputs; they return new tables.

local M = {}

M.MAX_LEVEL = 100
M.MAX_BOND = 255
M.MAX_MOVES = 4
M.BOND_PERIOD_S = 120 -- +1 bond per this many seconds as the active creature
M.BOND_LEVEL_LOW = 3 -- +3 per level-up while bond is below BOND_LEVEL_SPLIT
M.BOND_LEVEL_HIGH = 2 -- +2 per level-up from BOND_LEVEL_SPLIT on
M.BOND_LEVEL_SPLIT = 100
M.BOND_FAINT = -5
M.DAY_FROM = 0.25 -- VoxeLibre day: time of day 0.25 .. 0.75
M.DAY_TO = 0.75
M.CINEMATIC_S = 6 -- the evolution cinematic lasts this long unless "Stop it!" is pressed

local function clamp(n, lo, hi)
	if n < lo then
		return lo
	end
	if n > hi then
		return hi
	end
	return n
end

-- Bond ----------------------------------------------------------------------------------------------------------------

function M.clamp_bond(bond)
	return clamp(math.floor(tonumber(bond) or 0), 0, M.MAX_BOND)
end

-- Adds n bond points (n may be negative), clamped to 0..255.
function M.add_bond(bond, n)
	return M.clamp_bond(M.clamp_bond(bond) + (tonumber(n) or 0))
end

-- A level-up adds bond: +3 below 100, +2 from 100 on.
function M.bond_after_level(bond)
	local b = M.clamp_bond(bond)
	local gain = M.BOND_LEVEL_HIGH
	if b < M.BOND_LEVEL_SPLIT then
		gain = M.BOND_LEVEL_LOW
	end
	return M.add_bond(b, gain)
end

-- Accumulates seconds spent as the active creature. Returns the new accumulator and the bond points earned.
function M.bond_tick(acc, dt)
	local total = (acc or 0) + math.max(tonumber(dt) or 0, 0)
	local points = math.floor(total / M.BOND_PERIOD_S)
	return total - points * M.BOND_PERIOD_S, points
end

-- Hearts shown in the party formspec: bond / 51, rounded (0..5).
function M.hearts(bond)
	return math.floor(M.clamp_bond(bond) / 51 + 0.5)
end

-- Levels and HP -------------------------------------------------------------------------------------------------------

-- The level for a total exp: the highest level the curve allows, never below the current level, capped at 100.
function M.level_after(F, exp, growth, level)
	local lv = F.level_for_exp(math.max(0, math.floor(tonumber(exp) or 0)), growth)
	return clamp(math.max(lv, math.floor(tonumber(level) or 1)), 1, M.MAX_LEVEL)
end

-- Keeps the HP fraction across a max HP change: new_hp = ceil(hp * new_max / old_max), integer arithmetic.
-- A fainted creature stays at 0. An unknown old max keeps the HP, clamped to the new max.
function M.rescale_hp(hp, old_max, new_max)
	local h = math.max(0, math.floor(tonumber(hp) or 0))
	local new = math.max(1, math.floor(tonumber(new_max) or 1))
	if h <= 0 then
		return 0
	end
	local old = math.floor(tonumber(old_max) or 0)
	if old <= 0 then
		return math.min(h, new)
	end
	return clamp(math.ceil(h * new / old), 1, new)
end

-- Learning ------------------------------------------------------------------------------------------------------------

-- The move ids a learnset gives for levels in (old_level, new_level], in level order, each move once.
function M.learn_candidates(learnset, old_level, new_level)
	local found = {}
	for i, entry in ipairs(learnset or {}) do
		if entry.level > old_level and entry.level <= new_level then
			found[#found + 1] = { move = entry.move, level = entry.level, index = i }
		end
	end
	table.sort(found, function(a, b)
		if a.level ~= b.level then
			return a.level < b.level
		end
		return a.index < b.index
	end)
	local out, seen = {}, {}
	for _, f in ipairs(found) do
		if not seen[f.move] then
			seen[f.move] = true
			out[#out + 1] = f.move
		end
	end
	return out
end

local function has_move(moves, id)
	for _, mv in ipairs(moves) do
		if mv.id == id then
			return true
		end
	end
	return false
end

-- Plans what a member learns from candidates (move ids in order). moves: {id, pp} list. pending: move ids that
-- already have a prompt queued for this member. pp_of(id) gives the full PP of a move.
-- A move already known or already queued is skipped (no duplicates). While fewer than MAX_MOVES are known, a move is
-- learned at once; after that it becomes a prompt.
-- Returns { moves = new list, learned = {ids}, prompts = {ids} }.
function M.plan_learns(moves, candidates, pending, pp_of)
	local out = {}
	for i, mv in ipairs(moves or {}) do
		out[i] = { id = mv.id, pp = mv.pp }
	end
	local queued = {}
	for _, id in ipairs(pending or {}) do
		queued[id] = true
	end
	local learned, prompts = {}, {}
	for _, id in ipairs(candidates or {}) do
		if not has_move(out, id) and not queued[id] then
			if #out < M.MAX_MOVES then
				out[#out + 1] = { id = id, pp = math.floor(tonumber(pp_of(id)) or 0) }
				learned[#learned + 1] = id
			else
				queued[id] = true
				prompts[#prompts + 1] = id
			end
		end
	end
	return { moves = out, learned = learned, prompts = prompts }
end

-- The moves with slot index replaced by move id at full pp. Returns a new list, or nil when index is not a slot.
function M.replace_move(moves, index, id, pp)
	if index < 1 or index > #(moves or {}) then
		return nil
	end
	local out = {}
	for i, mv in ipairs(moves) do
		out[i] = { id = mv.id, pp = mv.pp }
	end
	out[index] = { id = id, pp = math.floor(tonumber(pp) or 0) }
	return out
end

-- Evolution -----------------------------------------------------------------------------------------------------------

local function stat_relation_holds(relation, stats)
	if stats == nil then
		return false
	end
	if relation == "attack_gt_defense" then
		return stats.atk > stats.def
	end
	if relation == "attack_lt_defense" then
		return stats.atk < stats.def
	end
	if relation == "attack_eq_defense" then
		return stats.atk == stats.def
	end
	return false
end

-- Does one condition hold? ctx = { is_night, used_item (item id or nil), link_cable (bool), inventory_has(id) -> bool,
-- stats = { atk, def } (current stats) }. An unknown key never holds.
function M.condition_holds(key, value, inst, ctx)
	if key == "min_level" then
		return (inst.level or 0) >= value
	end
	if key == "item" then
		return ctx.used_item ~= nil and ctx.used_item == value
	end
	if key == "min_bond" then
		return (inst.bond or 0) >= value
	end
	if key == "time_of_day" then
		if value == "day" then
			return not ctx.is_night
		end
		if value == "night" then
			return ctx.is_night == true
		end
		return false
	end
	if key == "stat_relation" then
		return stat_relation_holds(value, ctx.stats)
	end
	if key == "trade" then
		if value == true then
			return ctx.link_cable == true
		end
		return ctx.link_cable ~= true
	end
	if key == "held_item" then
		return ctx.inventory_has ~= nil and ctx.inventory_has(value) == true
	end
	return false
end

-- The first evolution of species whose every condition holds: { to = species id, conditions = the set }, or nil.
-- A conditions set with no keys never matches.
function M.matching_evolution(inst, species, ctx)
	for _, evo in ipairs((species and species.evolutions) or {}) do
		local conds = evo.conditions or {}
		local count = 0
		local ok = true
		for key, value in pairs(conds) do
			count = count + 1
			if not M.condition_holds(key, value, inst, ctx) then
				ok = false
			end
		end
		if ok and count > 0 then
			return { to = evo.to, conditions = conds }
		end
	end
	return nil
end

-- True when some evolution of species has every condition hold in ctx.
function M.can_evolve(inst, species, ctx)
	return M.matching_evolution(inst, species, ctx) ~= nil
end

-- Day is time of day 0.25..0.75 (inclusive). Returns is_night for a time of day.
function M.is_night(timeofday)
	local t = tonumber(timeofday) or 0
	return not (t >= M.DAY_FROM and t <= M.DAY_TO)
end

-- Cinematic --------------------------------------------------------------------------------------------------------

-- The spiral of the evolution cinematic at elapsed time t (seconds): the angle (radians), the radius (metres) and
-- the height (metres above the creature's feet). The spiral tightens and rises toward the end.
function M.spiral(t)
	local frac = clamp((tonumber(t) or 0) / M.CINEMATIC_S, 0, 1)
	return {
		angle = (tonumber(t) or 0) * 6,
		radius = 1.6 * (1 - frac) + 0.15,
		height = 0.2 + 1.8 * frac,
	}
end

return M
