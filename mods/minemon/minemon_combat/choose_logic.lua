-- Move choice (T-23, status scoring T-31). Pure: no Luanti API, so busted can test it.
-- A candidate is {id, pp, move, on_cooldown}; pp nil means unlimited (wild creatures). move may carry mech (the
-- effects_logic mechanics).
-- ctx = {user_types, target_types, target_status, type_mult(atk_type, def_types), user_hp_frac, user_stages,
-- target_stages}. The stage tables and user_hp_frac are optional (0 stages, full HP when absent).

local M = {}

M.RANDOM_CHANCE = 0.15
M.STATUS_SCORE = 30 -- a stat drop on a target with no status
M.PRIMARY_SCORE = 40 -- sleep, paralysis, burn, poison, freeze on a target with no status
M.VOLATILE_SCORE = 25 -- confusion, trap, leech seed on a target with no status
M.STAT_UP_SCORE = 25 -- a stat rise on the user, while its stage is below STAT_UP_LIMIT
M.STAT_UP_LIMIT = 2
M.STAT_DROP_LIMIT = -2 -- a stat drop is wanted while the target's stage is above this
M.HEAL_SCORE = 60 -- healing below HEAL_BELOW of max HP
M.HEAL_BELOW = 0.4
M.PROTECT_SCORE = 30 -- protect when the user is low
M.PROTECT_BELOW = 0.35
M.BUFF_SCORE = 15 -- a side buff on the user (mist, screens, focus)
M.BELLY_DRUM_SCORE = 35 -- belly drum at high HP and a low attack stage
M.BELLY_DRUM_ABOVE = 0.8
M.STAB = 1.5

local PRIMARY = { sleep = true, paralysis = true, burn = true, poison = true, freeze = true }

local function has(list, value)
	for _, v in ipairs(list or {}) do
		if v == value then
			return true
		end
	end
	return false
end

local function stage_of(stages, stat)
	return (stages and stages[stat]) or 0
end

local function any_stage(stages)
	for _, v in pairs(stages or {}) do
		if v ~= 0 then
			return true
		end
	end
	return false
end

-- Status moves (T-31). Each one scores by what it does now, and 0 when it cannot help:
--   heal and rest below HEAL_BELOW; protect when low; belly drum at high HP;
--   a stat rise on the user while its stage is low;
--   everything that affects the target (a status, a stat drop) only when the target has no primary status, so there is
--   no second sleep on a sleeping target.
local function status_score(move, ctx)
	local effect = move.effect or {}
	local mech = move.mech or {}
	local hp = ctx.user_hp_frac or 1
	if mech.heal or mech.rest then
		return hp < M.HEAL_BELOW and M.HEAL_SCORE or 0
	end
	if mech.protect then
		return hp < M.PROTECT_BELOW and M.PROTECT_SCORE or 0
	end
	if mech.belly_drum then
		return (hp >= M.BELLY_DRUM_ABOVE and stage_of(ctx.user_stages, "atk") < M.STAT_UP_LIMIT)
			and M.BELLY_DRUM_SCORE or 0
	end
	if mech.haze then
		return (any_stage(ctx.user_stages) or any_stage(ctx.target_stages)) and M.BUFF_SCORE or 0
	end
	if mech.self_volatile then
		return M.BUFF_SCORE
	end
	local up = false
	for _, c in ipairs(effect.stat_changes or {}) do
		if c.target == "user" and c.stages > 0 and stage_of(ctx.user_stages, c.stat) < M.STAT_UP_LIMIT then
			up = true
		end
	end
	if up then
		return M.STAT_UP_SCORE
	end
	if ctx.target_status ~= nil and ctx.target_status ~= "none" then
		return 0
	end
	local best = 0
	if effect.status ~= nil then
		best = PRIMARY[effect.status] and M.PRIMARY_SCORE or M.VOLATILE_SCORE
	end
	for _, c in ipairs(effect.stat_changes or {}) do
		if c.target == "target" and c.stages < 0 and stage_of(ctx.target_stages, c.stat) > M.STAT_DROP_LIMIT then
			best = math.max(best, M.STATUS_SCORE)
		end
	end
	return best
end

-- Expected damage = power x accuracy x STAB x type multiplier. Status moves: see status_score.
function M.score(move, ctx)
	if move.category == "status" then
		return status_score(move, ctx)
	end
	local power = tonumber(move.power) or 0
	if power <= 0 then
		return 0
	end
	local accuracy = (move.accuracy or 100) / 100
	local stab = has(ctx.user_types, move.type) and M.STAB or 1
	local mult = ctx.type_mult(move.type, ctx.target_types or {})
	return power * accuracy * stab * mult
end

-- Drops moves on cooldown and moves with no PP left.
function M.eligible(candidates)
	local out = {}
	for _, c in ipairs(candidates) do
		if not c.on_cooldown and (c.pp == nil or c.pp > 0) then
			out[#out + 1] = c
		end
	end
	return out
end

-- The best eligible move by score. Ties keep the earlier move in the list. Returns id, score or nil.
function M.choose_best(candidates, ctx)
	local best, best_score = nil, nil
	for _, c in ipairs(M.eligible(candidates)) do
		local s = M.score(c.move, ctx)
		if best_score == nil or s > best_score then
			best, best_score = c, s
		end
	end
	if best == nil then
		return nil, nil
	end
	return best.id, best_score
end

-- The best move, except that with RANDOM_CHANCE (from rng:float()) a random eligible move is picked.
function M.choose(candidates, ctx, rng)
	local list = M.eligible(candidates)
	if #list == 0 then
		return nil
	end
	if rng:float() < M.RANDOM_CHANCE then
		return list[rng:int(1, #list)].id
	end
	return (M.choose_best(candidates, ctx))
end

return M
