-- Status and move effects for minemon_combat (T-31). Pure: no Luanti API, so busted can test it.
-- Holds: the volatile statuses and their durations, stat stage decay, the mechanics of moves that the moves.json
-- effect fields cannot say (MECH), the damage and heal rules, and the texts, colours and nametag tags.
-- moves.json is never edited here: extend() copies a move and adds the mechanics on top of it.

local M = {}

-- Stat stages: each stage moves 1 towards 0 every STAGE_DECAY_S seconds.
M.STAGE_DECAY_S = 20

-- Volatile statuses: several can sit on one creature, next to one primary status (sleep, burn, ...). They are short and
-- are not saved: a reload clears them.
M.VOLATILE = {
	confusion = true, trap = true, leech = true, flinch = true, protect = true, endure = true,
	mist = true, light_screen = true, reflect = true, focus = true, safeguard = true,
}
M.VOLATILE_S = {
	flinch = 1, protect = 1.5, endure = 1.5, trap = 6, leech = 15,
	mist = 10, light_screen = 10, reflect = 10, focus = 10, safeguard = 10,
}
M.CONFUSION_MIN_S = 4
M.CONFUSION_MAX_S = 8
M.CONFUSION_SELF_HIT = 1 / 3
M.SELF_HIT_POWER = 40
M.TRAP_TICK_S = 1
M.TRAP_DIVISOR = 16
M.LEECH_TICK_S = 2
M.LEECH_DIVISOR = 8
M.PROTECT_STREAK_RESET_S = 6
M.REST_SLEEP_S = 5
M.HAZE_RADIUS_M = 6
M.BELLY_DRUM_ATK = 6

-- Statuses of the moves.json effect field, mapped to our kinds. Anything not listed (disable, perish-song,
-- no-type-immunity) is not modelled yet and is reported by M.gaps.
M.DATA_STATUS = {
	burn = "burn", poison = "poison", paralysis = "paralysis", sleep = "sleep", freeze = "freeze",
	confusion = "confusion", trap = "trap", ["leech-seed"] = "leech", protect = "protect",
}

M.PRIMARY = { sleep = true, paralysis = true, burn = true, poison = true, freeze = true }

-- Text shown near the victim (floating text, see vfx.lua). A nil text shows nothing.
M.STATUS_TEXT = {
	sleep = "fell asleep!", paralysis = "is paralyzed!", burn = "was burned!", poison = "was poisoned!",
	freeze = "was frozen solid!", confusion = "is confused!", trap = "was trapped!", leech = "was seeded!",
}
M.SELF_TEXT = {
	mist = "is shrouded in mist!", light_screen = "put up a Light Screen!", reflect = "put up a Reflect!",
	focus = "is focusing its energy!", endure = "is bracing to endure!", safeguard = "is protected by Safeguard!",
}
M.TEXT = {
	blocked = "Blocked!", protected = "protected itself!", failed = "But it failed!", flinched = "flinched!",
	paralysed = "is paralyzed! It can't move!", self_hit = "hurt itself in its confusion!",
	healed = "regained health!", rested = "fell asleep and feels healthy!", bell = "A soothing bell rang!",
	mist_blocks = "Mist protects against stat drops!", haze = "All stat changes were eliminated!",
	pain_split = "The pain was shared!", drum = "drummed its belly!",
}

-- Status tags on the nametag, e.g. "Rattata Lv 4 [SLP]". A primary status wins over a volatile one.
M.STATUS_TAG = {
	sleep = "SLP", paralysis = "PAR", burn = "BRN", poison = "PSN", freeze = "FRZ",
	confusion = "CNF", trap = "TRP", leech = "SEED",
}
M.TAG_ORDER = { "confusion", "trap", "leech" }
M.SUFFIX = " (exhausted)"

-- The type whose tint the status burst uses (vfx.TYPE_COLOUR).
M.KIND_TYPE = {
	sleep = "psychic", paralysis = "electric", burn = "fire", poison = "poison", freeze = "ice",
	confusion = "psychic", trap = "rock", leech = "grass", flinch = "normal", protect = "steel",
	endure = "normal", mist = "ice", light_screen = "psychic", reflect = "steel", focus = "fighting",
	safeguard = "normal",
}

-- Mechanics per move id. A move that is not here works from its moves.json fields alone.
--   fixed        effect.fixed_damage for formulas.damage: a number, or "level"
--   ohko         one-hit KO, accuracy from the data; fails against a higher level
--   half_hp      deals half the target's current HP (super fang)
--   psywave      level x random 50..150 percent
--   power        power chosen when the move is cast: "hp" (flail, reversal), "magnitude", "present"
--   status       effect.status for a move whose data has none (mean look)
--   protect      the 1.5 s shield, with the halving streak
--   self_volatile  a volatile on the user, for 10 s (or the listed time) with a refresh
--   haze, rest, heal (half, sun, moon), heal_bell, pain_split, belly_drum: see effects.lua
M.MECH = {
	dragon_rage = { fixed = 40 },
	sonic_boom = { fixed = 20 },
	night_shade = { fixed = "level" },
	seismic_toss = { fixed = "level" },
	super_fang = { half_hp = true },
	psywave = { psywave = true },
	fissure = { ohko = true },
	guillotine = { ohko = true },
	horn_drill = { ohko = true },
	flail = { power = "hp" },
	reversal = { power = "hp" },
	magnitude = { power = "magnitude" },
	present = { power = "present" },
	mean_look = { status = "trap" },
	protect = { protect = true },
	detect = { protect = true },
	endure = { self_volatile = "endure" },
	mist = { self_volatile = "mist" },
	light_screen = { self_volatile = "light_screen" },
	reflect = { self_volatile = "reflect" },
	focus_energy = { self_volatile = "focus" },
	safeguard = { self_volatile = "safeguard" },
	haze = { haze = true },
	rest = { rest = true },
	recover = { heal = "half" },
	soft_boiled = { heal = "half" },
	milk_drink = { heal = "half" },
	morning_sun = { heal = "sun" },
	synthesis = { heal = "sun" },
	moonlight = { heal = "moon" },
	heal_bell = { heal_bell = true },
	pain_split = { pain_split = true },
	belly_drum = { belly_drum = true },
}

local function clamp(v, lo, hi)
	if v < lo then
		return lo
	end
	if v > hi then
		return hi
	end
	return v
end

function M.is_volatile(kind)
	return M.VOLATILE[kind] == true
end

function M.kind_type(kind)
	return M.KIND_TYPE[kind] or "normal"
end

-- Stat stages --------------------------------------------------------------------------------------------------------

-- Moves every non-zero stage 1 towards 0 for each full STAGE_DECAY_S in timer + dt. Returns a fresh stages table
-- without zero entries, and the timer that is left. A table with no stage left has timer 0.
function M.decay_stages(stages, timer, dt)
	local out = {}
	local any = false
	for k, v in pairs(stages or {}) do
		if v ~= 0 then
			out[k] = v
			any = true
		end
	end
	if not any then
		return {}, 0
	end
	local t = (timer or 0) + (dt or 0)
	while t >= M.STAGE_DECAY_S do
		t = t - M.STAGE_DECAY_S
		for k, v in pairs(out) do
			if v > 0 then
				out[k] = v - 1
			elseif v < 0 then
				out[k] = v + 1
			end
		end
	end
	local res = {}
	local left = false
	for k, v in pairs(out) do
		if v ~= 0 then
			res[k] = v
			left = true
		end
	end
	if not left then
		return {}, 0
	end
	return res, t
end

-- Mist stops stat drops (negative stages) on its holder.
function M.blocks_drop(stages, mist)
	return mist == true and stages < 0
end

-- Volatile records ---------------------------------------------------------------------------------------------------

-- A new record for a volatile status: { kind, left, tick, hurts, seeder }. Confusion rolls its duration (4 to 8 s).
-- hurts: a trap from a move with power also deals damage. seeder: the leech seed's user.
function M.volatile_record(kind, rng, opts)
	opts = opts or {}
	local left = M.VOLATILE_S[kind] or 1
	if kind == "confusion" then
		left = M.CONFUSION_MIN_S + (M.CONFUSION_MAX_S - M.CONFUSION_MIN_S) * rng:float()
	end
	return { kind = kind, left = left, tick = 0, hurts = opts.hurts == true, seeder = opts.seeder }
end

function M.trap_damage(max_hp)
	return math.max(1, math.floor((tonumber(max_hp) or 0) / M.TRAP_DIVISOR))
end

function M.leech_amount(max_hp)
	return math.max(1, math.floor((tonumber(max_hp) or 0) / M.LEECH_DIVISOR))
end

-- Advances a volatile record by dt seconds. Returns {damage, drain, expired}. A hurting trap deals 1/16 max HP every
-- second. A leech seed drains 1/8 max HP every 2 s, to its seeder. The record's clock runs in both cases.
function M.advance_volatile(rec, dt, max_hp)
	local out = { damage = 0, drain = 0, expired = false }
	rec.tick = (rec.tick or 0) + dt
	if rec.kind == "trap" and rec.hurts then
		while rec.tick >= M.TRAP_TICK_S do
			rec.tick = rec.tick - M.TRAP_TICK_S
			out.damage = out.damage + M.trap_damage(max_hp)
		end
	elseif rec.kind == "leech" then
		while rec.tick >= M.LEECH_TICK_S do
			rec.tick = rec.tick - M.LEECH_TICK_S
			out.drain = out.drain + M.leech_amount(max_hp)
		end
	end
	rec.left = (rec.left or 0) - dt
	if rec.left <= 0 then
		out.expired = true
	end
	return out
end

-- Grass types cannot be seeded.
function M.seed_immune(def_types)
	for _, t in ipairs(def_types or {}) do
		if t == "grass" then
			return true
		end
	end
	return false
end

-- Confusion: true when this cast turns on the user (a 33% roll).
function M.confusion_self_hit(rng)
	return rng:float() < M.CONFUSION_SELF_HIT
end

-- Protect ------------------------------------------------------------------------------------------------------------

-- The streak in force now: it restarts after PROTECT_STREAK_RESET_S with no protect use.
function M.protect_streak(prev_streak, prev_time, now)
	if prev_time == nil or now - prev_time > M.PROTECT_STREAK_RESET_S then
		return 0
	end
	return prev_streak or 0
end

-- Success chance after `streak` uses in a row: 1, 1/2, 1/4, ...
function M.protect_chance(streak)
	return 1 / (2 ^ math.max(0, streak or 0))
end

-- Damage rules -------------------------------------------------------------------------------------------------------

-- One-hit KO: it hits when the user is at least as high level as the target.
function M.ohko_hits(atk_level, def_level)
	return (tonumber(atk_level) or 0) >= (tonumber(def_level) or 0)
end

function M.half_hp_damage(def_hp)
	return math.max(1, math.floor((tonumber(def_hp) or 0) / 2))
end

-- roll_percent: 50..150 (see psywave_roll).
function M.psywave_damage(level, roll_percent)
	return math.max(1, math.floor((tonumber(level) or 0) * roll_percent / 100))
end

function M.psywave_roll(rng)
	return 50 + rng:int(0, 100)
end

-- Flail and reversal: stronger the lower the user's HP, as in the games (48 steps of max HP).
function M.flail_power(hp, max)
	if (tonumber(max) or 0) <= 0 then
		return 20
	end
	local n = math.floor(48 * clamp(tonumber(hp) or 0, 0, max) / max)
	if n <= 1 then
		return 200
	elseif n <= 4 then
		return 150
	elseif n <= 9 then
		return 100
	elseif n <= 16 then
		return 80
	elseif n <= 32 then
		return 40
	end
	return 20
end

-- Magnitude: roll 1..100 to the power 10..150, with the games' odds.
function M.magnitude_power(roll)
	if roll <= 5 then
		return 10
	elseif roll <= 15 then
		return 30
	elseif roll <= 35 then
		return 50
	elseif roll <= 65 then
		return 70
	elseif roll <= 85 then
		return 90
	elseif roll <= 95 then
		return 110
	end
	return 150
end

-- Present: roll 1..4 gives power 40, 80, 120, or 0 for a heal of the target.
function M.present_power(roll)
	if roll == 1 then
		return 40
	elseif roll == 2 then
		return 80
	elseif roll == 3 then
		return 120
	end
	return 0
end

-- Screens halve the damage of their kind: light screen against special, reflect against physical.
function M.screened(amount, category, light_screen, reflect)
	if (category == "special" and light_screen) or (category == "physical" and reflect) then
		return math.max(1, math.floor(amount / 2))
	end
	return amount
end

-- Endure: a hit that would take the holder to 0 leaves it at 1 HP (0 damage when it is at 1 HP already).
function M.endured(amount, hp)
	if amount < hp then
		return amount
	end
	return math.max(0, hp - 1)
end

-- Heals --------------------------------------------------------------------------------------------------------------

-- Night as in wild_logic.is_night: 0.2 to 0.8 of the day is daylight.
function M.is_night(timeofday)
	return timeofday < 0.2 or timeofday > 0.8
end

-- The share of max HP a healing move gives. half: 1/2. sun (morning sun, synthesis): 2/3 by day, 1/4 at night.
-- moon (moonlight): the reverse.
function M.heal_fraction(heal_kind, is_night)
	if heal_kind == "sun" then
		return is_night and 0.25 or 2 / 3
	elseif heal_kind == "moon" then
		return is_night and 2 / 3 or 0.25
	end
	return 0.5
end

function M.heal_amount(max_hp, fraction)
	return math.max(1, math.floor((tonumber(max_hp) or 0) * fraction))
end

-- Pain split: both sides go to the average HP.
function M.pain_split_hp(a, b)
	return math.floor((a + b) / 2)
end

-- Belly drum: costs half of max HP, and only works when the user has more than that.
function M.belly_drum_cost(max_hp)
	return math.floor((tonumber(max_hp) or 0) / 2)
end

-- Move data ----------------------------------------------------------------------------------------------------------

-- A copy of the move with the mechanics added. The effect table is copied too, so the data is not changed.
-- The status name is mapped to our kinds (DATA_STATUS); a status we do not model is dropped.
function M.extend(move_id, raw)
	local out = {}
	for k, v in pairs(raw) do
		out[k] = v
	end
	local effect = {}
	for k, v in pairs(raw.effect or {}) do
		effect[k] = v
	end
	if effect.status ~= nil then
		effect.status = M.DATA_STATUS[effect.status]
	end
	local mech = M.MECH[move_id]
	if mech then
		if mech.fixed ~= nil then
			effect.fixed_damage = mech.fixed
		end
		if mech.status ~= nil then
			effect.status = mech.status
		end
	end
	out.effect = effect
	out.mech = mech
	out.id = move_id
	return out
end

-- The move with a higher critical hit chance (focus energy): the copy's effect has high_crit.
function M.with_high_crit(move)
	local out = {}
	for k, v in pairs(move) do
		out[k] = v
	end
	local effect = {}
	for k, v in pairs(move.effect or {}) do
		effect[k] = v
	end
	effect.high_crit = true
	out.effect = effect
	return out
end

-- The move to run for this user and target, with the power set when the move's power depends on the moment.
-- Returns move, heal: heal is true for a present that heals the target instead.
function M.prepare(move, mech, atk, rng)
	if mech == nil or mech.power == nil then
		return move, false
	end
	local power
	if mech.power == "hp" then
		power = M.flail_power(atk.hp, atk.stats and atk.stats.hp)
	elseif mech.power == "magnitude" then
		power = M.magnitude_power(rng:int(1, 100))
	elseif mech.power == "present" then
		power = M.present_power(rng:int(1, 4))
		if power == 0 then
			return move, true
		end
	end
	local out = {}
	for k, v in pairs(move) do
		out[k] = v
	end
	out.power = power
	return out, false
end

-- Applies the mechanics that come after the formula's damage: one-hit KO, half HP, psywave. res is the formulas
-- result {amount, crit, effectiveness, missed}; atk and def are views (level, hp, stats).
function M.post_damage(mech, res, atk, def, rng)
	if mech == nil or res.missed then
		return res
	end
	if mech.ohko then
		if res.effectiveness > 0 then
			if M.ohko_hits(atk.level, def.level) then
				res.amount = math.max(1, tonumber(def.hp) or 1)
			else
				res.missed = true
			end
		end
	elseif mech.half_hp then
		if res.effectiveness > 0 then
			res.amount = M.half_hp_damage(def.hp)
		end
	elseif mech.psywave then
		if res.effectiveness > 0 then
			res.amount = M.psywave_damage(atk.level, M.psywave_roll(rng))
		end
	end
	return res
end

-- Gaps ---------------------------------------------------------------------------------------------------------------

-- The reasons a move does not work fully. An empty list means it is handled.
function M.gaps(move_id, raw)
	local out = {}
	local ext = M.extend(move_id, raw)
	local raw_status = (raw.effect or {}).status
	if raw_status ~= nil and ext.effect.status == nil then
		out[#out + 1] = "status " .. raw_status .. " not modelled"
	end
	local changes = ext.effect.stat_changes or {}
	local has_effect = ext.effect.status ~= nil or #changes > 0 or ext.mech ~= nil
	if raw.category == "status" and not has_effect then
		out[#out + 1] = "no effect yet"
	end
	if raw.category ~= "status" and raw.power == nil and ext.mech == nil and ext.effect.fixed_damage == nil then
		out[#out + 1] = "no damage yet"
	end
	return out
end

-- Nametags -----------------------------------------------------------------------------------------------------------

-- Sets the status tag on a nametag: any old tag is removed first. The tag goes before the exhausted suffix, so the
-- runtime can still strip that suffix. tag nil removes the tag.
function M.with_status_tag(text, tag)
	local base = (text or ""):gsub(" %[%u+%]", "")
	if tag == nil then
		return base
	end
	local tagged = " [" .. tag .. "]"
	if base:sub(-#M.SUFFIX) == M.SUFFIX then
		return base:sub(1, #base - #M.SUFFIX) .. tagged .. M.SUFFIX
	end
	return base .. tagged
end

-- The tag to show: the primary status, else the first volatile one in TAG_ORDER. volatile is a set of kinds.
function M.tag_for(primary, volatile)
	if primary ~= nil and M.STATUS_TAG[primary] ~= nil then
		return M.STATUS_TAG[primary]
	end
	for _, kind in ipairs(M.TAG_ORDER) do
		if volatile and volatile[kind] then
			return M.STATUS_TAG[kind]
		end
	end
	return nil
end

return M
