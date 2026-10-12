-- minemon_creatures: wild creature decisions and danger tuning (T-21b, D-009, D-026). Pure: no core access, so
-- busted can test it (docs/CONVENTIONS.md). wild_brain.lua reads the world, calls decide(ctx) and acts on the result.
--
-- decide(ctx) returns one of {action="hunt_player", target}, {action="fight_creature", target}, {action="flee"},
-- {action="idle"}. The targets are opaque values from ctx (objects in the game, anything in the tests).
--
-- ctx fields:
--   temperament        "aggressive" | "territorial" | "skittish" | "peaceful" (a Dread creature is "aggressive")
--   dread              true for a Dread creature: it hunts within DREAD_HUNT_RANGE (T-30)
--   types              species types (list of strings)
--   hp_frac            instance HP / max HP, 0..1
--   is_night           boolean
--   player             nearest player (opaque) or nil; player_distance its distance in nodes
--   creature           the nearest player's active creature (opaque) or nil; creature_distance from us
--   hurt_by            "creature" | "player" | "other" | nil, the last hit (see angry_until)
--   attacker           the creature that hit us (opaque) or nil; attacker_distance from us
--   angry_until        time in seconds until which the creature is angry (set by being hurt)
--   now                current time in seconds (same clock as angry_until)
--   view_range         the creature's view range in nodes

local M = {}

M.THINK_S = 0.5 -- seconds between two decisions of one creature
M.NIGHT_VIEW_MULT = 1.5 -- view range multiplier at night (aggressive)
M.CREATURE_RANGE = 16 -- a player's creature (or an attacker) this close is fought
M.TERRITORIAL_CLOSE = 5 -- territorial attacks a player this close without being hit
M.SKITTISH_RANGE = 8 -- skittish flees a player this close
M.FLEE_PLAYER_RANGE = 12 -- the flee direction uses the nearest player within this range
M.LOW_HP = 0.2 -- below this HP fraction every temperament flees, except aggressive at night
M.HUNT_SPEED_MULT = 1.2 -- run speed multiplier while hunting a player
M.ANGER = { aggressive = 30, territorial = 30, skittish = 30, peaceful = 10 } -- seconds angry after a hit
M.NIGHT_TERRITORIAL_TYPES = { ghost = true, dark = true, poison = true } -- behave as aggressive at night
M.DREAD_HUNT_RANGE = 20 -- a Dread creature (ctx.dread) hunts the nearest player within this range, at any hour (D-031)

-- Danger tuning (T-21b brief): melee damage and the bite period, from the instance stats.
M.DAMAGE_MIN = 2
M.PERIOD_BASE = 1.2 -- seconds between bites at spe 0
M.PERIOD_MIN = 0.5 -- seconds, the fastest bite period

-- Night as in spawning.lua: 0.2 to 0.8 of the day is daylight.
function M.is_night(timeofday)
	return timeofday < 0.2 or timeofday > 0.8
end

-- Seconds a wild creature stays angry after a hit. Unknown temperaments use the peaceful value.
function M.anger_seconds(temperament)
	return M.ANGER[temperament] or M.ANGER.peaceful
end

-- Melee damage per bite: max(2, floor(1.5 + level*0.15 + atk/20 + 0.5)). atk is the instance's atk stat.
function M.melee_damage(level, atk)
	return math.max(M.DAMAGE_MIN, math.floor(1.5 + level * 0.15 + atk / 20 + 0.5))
end

-- Seconds between bites: 1.2 - spe/200, at least 0.5. spe is the instance's spe stat.
function M.attack_period(spe)
	return math.max(M.PERIOD_MIN, M.PERIOD_BASE - spe / 200)
end

-- Run speed for the state: +20% while hunting a player.
function M.run_speed(base, hunting)
	if hunting then
		return base * M.HUNT_SPEED_MULT
	end
	return base
end

-- The danger numbers for a creature against an unarmoured player with player_hp HP. seconds is the time from the
-- first bite to the kill, counted as bites * period (the first bite comes after one period).
function M.danger(level, atk, spe, player_hp)
	local damage = M.melee_damage(level, atk)
	local period = M.attack_period(spe)
	local bites = math.ceil(player_hp / damage)
	return {
		damage = damage,
		period = period,
		bites_per_s = 1 / period,
		bites = bites,
		seconds = bites * period,
	}
end

local function has_any(list, set)
	for _, value in ipairs(list or {}) do
		if set[value] then
			return true
		end
	end
	return false
end

local function idle()
	return { action = "idle" }
end

local function flee()
	return { action = "flee" }
end

-- Aggressive engagement: a player in view (x1.5 at night). Their creature within CREATURE_RANGE is fought; otherwise
-- the player is hunted. Returns nil when no player is in view.
local function engage_player(ctx)
	local range = (ctx.view_range or 0) * (ctx.is_night and M.NIGHT_VIEW_MULT or 1)
	if ctx.dread == true then
		range = M.DREAD_HUNT_RANGE
	end
	if ctx.player == nil or ctx.player_distance == nil or ctx.player_distance > range then
		return nil
	end
	if ctx.creature ~= nil and ctx.creature_distance ~= nil and ctx.creature_distance <= M.CREATURE_RANGE then
		return { action = "fight_creature", target = ctx.creature }
	end
	return { action = "hunt_player", target = ctx.player }
end

-- The decision for one creature. Pure: the same ctx always gives the same result.
function M.decide(ctx)
	local now = ctx.now or 0
	local hurt = (ctx.angry_until or 0) > now
	local night = ctx.is_night == true
	local temperament = ctx.temperament
	local hp = ctx.hp_frac or 1

	-- Any temperament flees at low HP, except an aggressive creature at night, which fights to the end.
	if hp < M.LOW_HP and not (temperament == "aggressive" and night) then
		return flee()
	end

	if temperament == "aggressive" then
		return engage_player(ctx) or idle()
	end

	if temperament == "territorial" then
		if night and has_any(ctx.types, M.NIGHT_TERRITORIAL_TYPES) then
			return engage_player(ctx) or idle()
		end
		local close = ctx.player_distance ~= nil and ctx.player_distance <= M.TERRITORIAL_CLOSE
		if close or hurt then
			return engage_player(ctx) or idle()
		end
		return idle()
	end

	if temperament == "skittish" then
		if hurt then
			return flee()
		end
		if ctx.player_distance ~= nil and ctx.player_distance <= M.SKITTISH_RANGE then
			return flee()
		end
		return idle()
	end

	if temperament == "peaceful" then
		if not hurt then
			return idle()
		end
		local attacker_near = ctx.attacker_distance ~= nil and ctx.attacker_distance <= M.CREATURE_RANGE
		if ctx.hurt_by == "creature" and ctx.attacker ~= nil and attacker_near then
			return { action = "fight_creature", target = ctx.attacker }
		end
		return flee()
	end

	return idle()
end

return M
