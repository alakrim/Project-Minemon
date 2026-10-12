-- One-shot move effects and stat stage decay (T-31). Runs when a cast finishes, after the archetype has fired, for
-- the mechanics in effects_logic.MECH that are not an archetype: protect, rest, healing, haze, mist and the other side
-- buffs, pain split and belly drum. Also the 0.5 s decay of stat stages.
-- Glue: the context G (built in init.lua) carries the status module (G.status), so its registries are the same ones.
-- luacheck: read_globals core

local EFX = dofile(core.get_modpath("minemon_combat") .. "/effects_logic.lua")

local M = {}

local WHITE = 0xFFFFFF
local GREEN = 0x33DD55
local GREY = 0xA0A0A0
local BELL_RADIUS_M = 6

-- Creatures that have a stat stage. Weak keys: an entity that is gone drops out by itself.
local stage_holders = setmetatable({}, { __mode = "k" })

-- Called whenever a stage is set above 0 (G.apply_stage), so the decay tick knows the entity.
function M.note_stages(le)
	stage_holders[le] = true
end

-- Stat stages move 1 towards 0 every EFX.STAGE_DECAY_S seconds. Runs from the 0.5 s step. The speed follows the spe
-- stage, so it is refreshed here too.
function M.decay_tick(G, dt)
	for le in pairs(stage_holders) do
		local obj = le.object
		if le._removed or not obj or not obj:get_pos() then
			stage_holders[le] = nil
		else
			local stages, timer = EFX.decay_stages(le._mm_stages, le._mm_stage_timer, dt)
			le._mm_stages = stages
			le._mm_stage_timer = timer
			if next(stages) == nil then
				stage_holders[le] = nil
			end
			G.status.refresh_speed(obj)
		end
	end
end

-- Confusion: the cast turns on the user. The user takes a typeless hit of power 40 from its own stats (no type
-- chart, no STAB). The cast is spent.
local SELF_HIT = { type = "typeless", category = "physical", power = EFX.SELF_HIT_POWER, effect = {} }

local function typeless(_, _)
	return 1.0
end

function M.self_hit(G, user)
	local v = G.view_of(user)
	if not v then
		return
	end
	local res = G.formulas.damage(v, v, SELF_HIT, typeless, G.rng)
	if res.amount > 0 then
		G.apply_damage(user, res.amount, nil, { move_id = "confusion" })
	end
	G.feedback_near(user:get_pos(), EFX.TEXT.self_hit, GREY)
end

local function self_volatile(G, user, kind)
	if G.status.apply_volatile(user, kind, G.rng, { refresh = true }) then
		G.feedback_near(user:get_pos(), EFX.SELF_TEXT[kind], WHITE)
	end
end

-- Protect: succeeds with 1 / 2^streak, where the streak counts the uses in a row (EFX.protect_streak).
local function protect(G, user)
	local le = user:get_luaentity()
	if not le then
		return
	end
	local now = core.get_us_time() / 1e6
	local streak = EFX.protect_streak(le._mm_protect_streak, le._mm_protect_t, now)
	local ok = G.rng:float() < EFX.protect_chance(streak)
	le._mm_protect_streak = streak + 1
	le._mm_protect_t = now
	if ok then
		G.status.apply_volatile(user, "protect", G.rng, { refresh = true })
		G.feedback_near(user:get_pos(), EFX.TEXT.protected, WHITE)
	else
		G.feedback_near(user:get_pos(), EFX.TEXT.failed, GREY)
	end
end

-- Haze: every stat stage within HAZE_RADIUS_M goes back to 0.
local function haze(G, user)
	local centre = user:get_pos()
	for _, obj in ipairs(core.get_objects_inside_radius(centre, EFX.HAZE_RADIUS_M)) do
		local le = obj:get_luaentity()
		if le and G.is_combatant(obj) then
			le._mm_stages = {}
			le._mm_stage_timer = 0
			stage_holders[le] = nil
			G.status.refresh_speed(obj)
		end
	end
	G.feedback_near(centre, EFX.TEXT.haze, WHITE)
end

-- Rest: full HP, the primary status cleared, then 5 s of sleep.
local function rest(G, user)
	local v = G.view_of(user)
	if not v then
		return
	end
	G.status.clear(user)
	G.heal_obj(user, v.stats.hp)
	G.status.apply(user, "sleep", G.rng, EFX.REST_SLEEP_S)
	G.feedback_near(user:get_pos(), EFX.TEXT.rested, GREEN)
end

-- A healing move: a fraction of max HP by the time of day (EFX.heal_fraction). At full HP it fails.
local function heal_self(G, user, heal_kind)
	local v = G.view_of(user)
	if not v then
		return
	end
	local frac = EFX.heal_fraction(heal_kind, EFX.is_night(core.get_timeofday()))
	local added = G.heal_obj(user, EFX.heal_amount(v.stats.hp, frac))
	if added > 0 then
		G.feedback_near(user:get_pos(), EFX.TEXT.healed, GREEN)
	else
		G.feedback_near(user:get_pos(), EFX.TEXT.failed, GREY)
	end
end

-- Heal Bell: clears the primary status of every creature of the user's side within the radius.
local function heal_bell(G, user)
	local centre = user:get_pos()
	for _, obj in ipairs(core.get_objects_inside_radius(centre, BELL_RADIUS_M)) do
		if not obj:is_player() and G.is_combatant(obj) and G.is_friend(user, obj) then
			G.status.clear(obj)
		end
	end
	G.feedback_near(centre, EFX.TEXT.bell, WHITE)
end

-- Pain split: both creatures go to the average of their HP.
local function pain_split(G, user, target)
	if not target or not target:get_pos() or target:is_player() or not G.is_combatant(target) then
		return
	end
	local a, b = G.hp_of(user), G.hp_of(target)
	local avg = EFX.pain_split_hp(a, b)
	if b > avg then
		G.apply_damage(target, b - avg, nil, { move_id = "pain-split" })
	end
	if a < avg then
		G.heal_obj(user, avg - a)
	end
	G.feedback_near(user:get_pos(), EFX.TEXT.pain_split, WHITE)
end

-- Belly drum: half of max HP is spent for +6 attack. It fails when the user has no more than that.
local function belly_drum(G, user)
	local v = G.view_of(user)
	if not v then
		return
	end
	local cost = EFX.belly_drum_cost(v.stats.hp)
	if G.hp_of(user) <= cost then
		G.feedback_near(user:get_pos(), EFX.TEXT.failed, GREY)
		return
	end
	G.apply_damage(user, cost, nil, { move_id = "belly-drum" })
	G.apply_stage(user, "atk", EFX.BELLY_DRUM_ATK)
	G.feedback_near(user:get_pos(), EFX.TEXT.drum, WHITE)
end

-- Runs the one-shot mechanic of move (move.mech), if it has one.
function M.on_cast(G, user, target, move)
	local mech = move.mech
	if mech == nil then
		return
	end
	if mech.self_volatile then
		self_volatile(G, user, mech.self_volatile)
	elseif mech.protect then
		protect(G, user)
	elseif mech.haze then
		haze(G, user)
	elseif mech.rest then
		rest(G, user)
	elseif mech.heal then
		heal_self(G, user, mech.heal)
	elseif mech.heal_bell then
		heal_bell(G, user)
	elseif mech.pain_split then
		pain_split(G, user, target)
	elseif mech.belly_drum then
		belly_drum(G, user)
	end
end

return M
