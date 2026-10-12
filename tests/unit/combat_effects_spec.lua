-- Unit tests for mods/minemon/minemon_combat/effects_logic.lua and the rules it uses from status_logic.lua (T-31).
-- Pure logic, no Luanti. Every random rule runs on a seeded RNG, with seeds spread out (the first draw of a small
-- Park-Miller seed is near 0; see combat_choose_spec).
-- luacheck: globals describe it assert

local here = debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$") or "."
local EFX = dofile(here .. "/../../mods/minemon/minemon_combat/effects_logic.lua")
local SL = dofile(here .. "/../../mods/minemon/minemon_combat/status_logic.lua")
local LOGIC = dofile(here .. "/../../mods/minemon/minemon_combat/moves_logic.lua")
local FORMULAS = dofile(here .. "/../../mods/minemon/minemon_core/formulas.lua")
local RNG = dofile(here .. "/../../mods/minemon/minemon_core/rng.lua")

local function spread(seed)
	return RNG.new(seed * 1000003)
end

-- A neutral type chart: every hit is 1.0.
local function neutral()
	return 1.0
end

local function view(level, hp, atk, def)
	return {
		level = level,
		hp = hp,
		stats = { hp = hp, atk = atk or 50, def = def or 50, spa = atk or 50, spd = def or 50, spe = 50 },
		types = { "normal" },
		stages = {},
	}
end

describe("combat effects: stat stages", function()
	it("clamps a stage to -6..6", function()
		assert.equals(6, LOGIC.clamp_stage(9))
		assert.equals(-6, LOGIC.clamp_stage(-9))
		assert.equals(2, LOGIC.clamp_stage(2))
	end)

	it("decays a stage 1 towards 0 every 20 s, and stops at 0", function()
		local stages, timer = EFX.decay_stages({ atk = 3, spe = -2 }, 0, 0)
		assert.equals(3, stages.atk)
		assert.equals(-2, stages.spe)
		stages, timer = EFX.decay_stages(stages, timer, 19.5)
		assert.equals(3, stages.atk)
		stages, timer = EFX.decay_stages(stages, timer, 0.5)
		assert.equals(2, stages.atk)
		assert.equals(-1, stages.spe)
		stages, timer = EFX.decay_stages(stages, timer, 40)
		assert.is_nil(stages.atk)
		assert.is_nil(stages.spe)
		assert.equals(0, timer)
	end)

	it("decays in 0.5 s steps as the glue calls it", function()
		local stages, timer = { def = 1 }, 0
		local steps = 0
		while next(stages) ~= nil and steps < 200 do
			stages, timer = EFX.decay_stages(stages, timer, 0.5)
			steps = steps + 1
		end
		assert.equals(40, steps) -- one stage: 20 s = 40 steps
	end)

	it("keeps a stage that has not decayed, and drops zero entries", function()
		local stages = EFX.decay_stages({ atk = 0, eva = 4 }, 0, 0)
		assert.is_nil(stages.atk)
		assert.equals(4, stages.eva)
	end)

	it("a mist holder refuses a stat drop, not a rise", function()
		assert.is_true(EFX.blocks_drop(-1, true))
		assert.is_false(EFX.blocks_drop(1, true))
		assert.is_false(EFX.blocks_drop(-1, false))
	end)
end)

describe("combat effects: paralysis and confusion (seeded rolls)", function()
	it("paralysis fails 25% of casts, within 3% over 10000 rolls", function()
		local rng = spread(11)
		local fails = 0
		for _ = 1, 10000 do
			if SL.paralysis_fails(rng) then
				fails = fails + 1
			end
		end
		local rate = fails / 10000
		assert.is_true(math.abs(rate - 0.25) <= 0.03, "paralysis fail rate " .. rate)
	end)

	it("confusion hits the user 33% of casts, within 3% over 10000 rolls", function()
		local rng = spread(12)
		local hits = 0
		for _ = 1, 10000 do
			if EFX.confusion_self_hit(rng) then
				hits = hits + 1
			end
		end
		local rate = hits / 10000
		assert.is_true(math.abs(rate - 1 / 3) <= 0.03, "confusion self-hit rate " .. rate)
	end)

	it("confusion lasts 4 to 8 s", function()
		local lo, hi = math.huge, -math.huge
		for seed = 1, 2000 do
			local rec = EFX.volatile_record("confusion", spread(seed), {})
			assert.is_true(rec.left >= 4 and rec.left <= 8, "confusion " .. rec.left)
			lo, hi = math.min(lo, rec.left), math.max(hi, rec.left)
		end
		assert.is_true(lo < 4.1 and hi > 7.9, "range " .. lo .. " .. " .. hi)
	end)

	it("sleep records from the primary status rules (3 to 7 s) keep their kind", function()
		assert.equals("sleep", SL.new_record("sleep", spread(3)).kind)
	end)
end)

describe("combat effects: protect", function()
	it("succeeds 1, 1/2, 1/4 ... with each use in a row", function()
		assert.equals(1, EFX.protect_chance(0))
		assert.equals(0.5, EFX.protect_chance(1))
		assert.equals(0.25, EFX.protect_chance(2))
	end)

	it("halves the chance on each consecutive use, measured over seeded rolls", function()
		local rng = spread(21)
		local streak0, streak1 = 0, 1
		local ok0, ok1 = 0, 0
		for _ = 1, 10000 do
			if rng:float() < EFX.protect_chance(streak0) then
				ok0 = ok0 + 1
			end
			if rng:float() < EFX.protect_chance(streak1) then
				ok1 = ok1 + 1
			end
		end
		assert.is_true(math.abs(ok0 / 10000 - 1) < 1e-9)
		assert.is_true(math.abs(ok1 / 10000 - 0.5) <= 0.03, "second protect " .. ok1 / 10000)
	end)

	it("the streak restarts after 6 s with no protect", function()
		assert.equals(2, EFX.protect_streak(2, 100, 105))
		assert.equals(0, EFX.protect_streak(2, 100, 107))
		assert.equals(0, EFX.protect_streak(5, nil, 100))
	end)

	it("protect lasts 1.5 s", function()
		assert.equals(1.5, EFX.VOLATILE_S.protect)
	end)
end)

describe("combat effects: volatile statuses", function()
	it("a trap that hurts takes 1/16 max HP every second for its 6 s", function()
		local rec = EFX.volatile_record("trap", spread(1), { hurts = true })
		local total, expired = 0, false
		for _ = 1, 12 do
			local out = EFX.advance_volatile(rec, 0.5, 160)
			total = total + out.damage
			if out.expired then
				expired = true
			end
		end
		assert.equals(6 * 10, total) -- 160 / 16 = 10 per tick, 6 ticks
		assert.is_true(expired)
	end)

	it("a trap from a move with no power (mean look) deals no damage", function()
		local rec = EFX.volatile_record("trap", spread(1), { hurts = false })
		local total = 0
		for _ = 1, 12 do
			total = total + EFX.advance_volatile(rec, 0.5, 160).damage
		end
		assert.equals(0, total)
	end)

	it("a leech seed drains 1/8 max HP every 2 s for 15 s: 7 drains", function()
		local rec = EFX.volatile_record("leech", spread(1), { seeder = "x" })
		local drains, total = 0, 0
		for _ = 1, 40 do
			local out = EFX.advance_volatile(rec, 0.5, 160)
			if out.drain > 0 then
				drains = drains + 1
				total = total + out.drain
			end
			if out.expired then
				break
			end
		end
		assert.equals(7, drains)
		assert.equals(7 * 20, total)
	end)

	it("grass types cannot be seeded", function()
		assert.is_true(EFX.seed_immune({ "grass", "poison" }))
		assert.is_false(EFX.seed_immune({ "fire" }))
		assert.is_false(EFX.seed_immune(nil))
	end)

	it("flinch, endure and the side buffs have their durations", function()
		assert.equals(1, EFX.VOLATILE_S.flinch)
		assert.equals(1.5, EFX.VOLATILE_S.endure)
		assert.equals(10, EFX.VOLATILE_S.mist)
		assert.equals(10, EFX.VOLATILE_S.light_screen)
		assert.equals(10, EFX.VOLATILE_S.reflect)
	end)

	it("endure leaves 1 HP, or 0 damage at 1 HP", function()
		assert.equals(19, EFX.endured(50, 20))
		assert.equals(7, EFX.endured(7, 20))
		assert.equals(0, EFX.endured(5, 1))
	end)

	it("light screen halves special and reflect halves physical damage, never below 1", function()
		assert.equals(10, EFX.screened(20, "special", true, false))
		assert.equals(20, EFX.screened(20, "physical", true, false))
		assert.equals(10, EFX.screened(20, "physical", false, true))
		assert.equals(1, EFX.screened(1, "special", true, false))
	end)

	it("the status tag shows the primary status first, then the volatile one", function()
		assert.equals("SLP", EFX.tag_for("sleep", { trap = true }))
		assert.equals("CNF", EFX.tag_for("none", { trap = true, confusion = true }))
		assert.equals("CNF", EFX.tag_for("none", { confusion = true }))
		assert.is_nil(EFX.tag_for("none", {}))
	end)
end)

describe("combat effects: fixed damage and special damage rules", function()
	it("dragon rage always does 40 and sonic boom 20, at neutral type", function()
		local atk, def = view(30, 90), view(10, 90)
		local dragon = EFX.extend("dragon_rage", { type = "dragon", category = "special", power = nil, accuracy = nil,
			effect = {}, archetype = "projectile" })
		local res = FORMULAS.damage(atk, def, dragon, neutral, spread(1))
		assert.equals(40, res.amount)
		local sonic = EFX.extend("sonic_boom", { type = "normal", category = "physical", power = nil, accuracy = nil,
			effect = {}, archetype = "beam" })
		assert.equals(20, FORMULAS.damage(atk, def, sonic, neutral, spread(1)).amount)
	end)

	it("night shade and seismic toss do damage equal to the user's level", function()
		local night = EFX.extend("night_shade", { type = "ghost", category = "physical", power = nil, accuracy = nil,
			effect = {}, archetype = "beam" })
		assert.equals(37, FORMULAS.damage(view(37, 90), view(5, 90), night, neutral, spread(1)).amount)
		local seismic = EFX.extend("seismic_toss", { type = "fighting", category = "physical", power = nil,
			accuracy = nil, effect = {}, archetype = "melee_arc" })
		assert.equals(12, FORMULAS.damage(view(12, 90), view(5, 90), seismic, neutral, spread(1)).amount)
	end)

	it("a fixed damage move does nothing against a type it does not affect", function()
		local night = EFX.extend("night_shade", { type = "ghost", category = "physical", power = nil, accuracy = nil,
			effect = {}, archetype = "beam" })
		local zero = function()
			return 0.0
		end
		assert.equals(0, FORMULAS.damage(view(37, 90), view(5, 90), night, zero, spread(1)).amount)
	end)

	it("super fang deals half the target's current HP", function()
		local res = { amount = 0, crit = false, effectiveness = 1.0, missed = false }
		local out = EFX.post_damage({ half_hp = true }, res, view(20, 90), view(20, 61))
		assert.equals(30, out.amount)
		assert.equals(1, EFX.half_hp_damage(1))
	end)

	it("psywave is level x 50..150 percent", function()
		assert.equals(10, EFX.psywave_damage(20, 50))
		assert.equals(30, EFX.psywave_damage(20, 150))
		local rng = spread(5)
		for _ = 1, 500 do
			local roll = EFX.psywave_roll(rng)
			assert.is_true(roll >= 50 and roll <= 150)
		end
	end)

	it("flail power grows as HP falls", function()
		assert.equals(200, EFX.flail_power(1, 100))
		assert.equals(150, EFX.flail_power(10, 100))
		assert.equals(20, EFX.flail_power(100, 100))
	end)

	it("magnitude maps 1..100 onto the games' powers", function()
		assert.equals(10, EFX.magnitude_power(1))
		assert.equals(70, EFX.magnitude_power(40))
		assert.equals(150, EFX.magnitude_power(100))
	end)

	it("present rolls 40, 80, 120, or 0 (a heal)", function()
		assert.equals(40, EFX.present_power(1))
		assert.equals(120, EFX.present_power(3))
		assert.equals(0, EFX.present_power(4))
	end)
end)

describe("combat effects: one-hit KO level rule", function()
	it("hits when the user is at least as high level as the target", function()
		assert.is_true(EFX.ohko_hits(20, 20))
		assert.is_true(EFX.ohko_hits(25, 20))
		assert.is_false(EFX.ohko_hits(19, 20))
	end)

	it("post_damage: a hit takes the target's current HP, a level fail misses", function()
		local hit = EFX.post_damage({ ohko = true }, { amount = 0, effectiveness = 1.0, missed = false },
			view(30, 90), view(20, 45))
		assert.equals(45, hit.amount)
		assert.is_false(hit.missed)
		local fail = EFX.post_damage({ ohko = true }, { amount = 0, effectiveness = 1.0, missed = false },
			view(10, 90), view(20, 45))
		assert.is_true(fail.missed)
	end)

	it("an immune target takes no one-hit KO", function()
		local res = EFX.post_damage({ ohko = true }, { amount = 0, effectiveness = 0, missed = false },
			view(30, 90), view(20, 45))
		assert.equals(0, res.amount)
		assert.is_false(res.missed)
	end)
end)

describe("combat effects: heal fractions by time of day", function()
	it("recover, soft boiled and milk drink heal 1/2 at any time", function()
		assert.equals(0.5, EFX.heal_fraction("half", false))
		assert.equals(0.5, EFX.heal_fraction("half", true))
		assert.equals(50, EFX.heal_amount(100, EFX.heal_fraction("half", false)))
	end)

	it("sun moves heal 2/3 by day and 1/4 at night", function()
		assert.is_true(math.abs(EFX.heal_fraction("sun", false) - 2 / 3) < 1e-12)
		assert.equals(0.25, EFX.heal_fraction("sun", true))
		assert.equals(40, EFX.heal_amount(60, EFX.heal_fraction("sun", false)))
		assert.equals(15, EFX.heal_amount(60, EFX.heal_fraction("sun", true)))
	end)

	it("moonlight is the reverse: 2/3 at night, 1/4 by day", function()
		assert.equals(2 / 3, EFX.heal_fraction("moon", true))
		assert.equals(0.25, EFX.heal_fraction("moon", false))
	end)

	it("day and night follow the wild rule: 0.2 to 0.8 of the day is daylight", function()
		assert.is_false(EFX.is_night(0.5))
		assert.is_false(EFX.is_night(0.2))
		assert.is_true(EFX.is_night(0.0))
		assert.is_true(EFX.is_night(0.9))
	end)

	it("a heal is at least 1 HP", function()
		assert.equals(1, EFX.heal_amount(1, 0.25))
	end)

	it("pain split takes the average, rounded down", function()
		assert.equals(15, EFX.pain_split_hp(10, 21))
	end)

	it("belly drum costs half of max HP", function()
		assert.equals(30, EFX.belly_drum_cost(61))
	end)
end)

describe("combat effects: move data", function()
	local MOVES_DATA = {
		ember = { type = "fire", category = "special", power = 40, accuracy = 100, archetype = "projectile",
			effect = { status = "burn", status_chance = 10 } },
		disable = { type = "normal", category = "status", archetype = "status_cloud", accuracy = 55,
			effect = { status = "disable" } },
		mean_look = { type = "normal", category = "status", archetype = "status_cloud", effect = {} },
		splash = { type = "normal", category = "status", archetype = "aura", effect = {} },
		counter = { type = "fighting", category = "physical", archetype = "melee_arc", accuracy = 100, effect = {} },
		leech_seed = { type = "grass", category = "status", archetype = "status_cloud", accuracy = 90,
			effect = { status = "leech-seed" } },
	}

	it("maps data statuses to our kinds, and drops the ones not modelled", function()
		assert.equals("burn", EFX.extend("ember", MOVES_DATA.ember).effect.status)
		assert.equals("leech", EFX.extend("leech_seed", MOVES_DATA.leech_seed).effect.status)
		assert.is_nil(EFX.extend("disable", MOVES_DATA.disable).effect.status)
	end)

	it("does not change the raw move it copies", function()
		local raw = MOVES_DATA.ember
		EFX.extend("ember", raw)
		assert.equals("burn", raw.effect.status)
	end)

	it("mean look gets the trap status from the mechanics table", function()
		assert.equals("trap", EFX.extend("mean_look", MOVES_DATA.mean_look).effect.status)
	end)

	it("gaps: a handled move has none, a no-op and a missing status are reported", function()
		assert.equals(0, #EFX.gaps("ember", MOVES_DATA.ember))
		assert.equals(1, #EFX.gaps("splash", MOVES_DATA.splash))
		assert.equals("no effect yet", EFX.gaps("splash", MOVES_DATA.splash)[1])
		assert.equals("status disable not modelled", EFX.gaps("disable", MOVES_DATA.disable)[1])
		assert.equals("no damage yet", EFX.gaps("counter", MOVES_DATA.counter)[1])
	end)

	it("with_high_crit copies the move and sets high_crit only on the copy", function()
		local raw = { type = "normal", effect = {} }
		local high = EFX.with_high_crit(raw)
		assert.is_true(high.effect.high_crit)
		assert.is_nil(raw.effect.high_crit)
	end)

	it("prepare sets the power by moment, and reports a present heal", function()
		local raw = { type = "normal", category = "physical", power = nil, effect = {} }
		local flail = EFX.extend("flail", raw)
		local low = view(20, 100)
		low.hp = 1
		local out = EFX.prepare(flail, flail.mech, low, spread(1))
		assert.equals(200, out.power)
		assert.is_nil(raw.power)
		local rng = spread(9)
		local heals = 0
		for _ = 1, 400 do
			local _, heal = EFX.prepare(EFX.extend("present", raw), EFX.MECH.present, view(20, 100), rng)
			if heal then
				heals = heals + 1
			end
		end
		assert.is_true(heals > 60 and heals < 140, "present heals " .. heals .. " of 400")
	end)
end)

describe("combat effects: nametags", function()
	it("adds a status tag to the nametag", function()
		assert.equals("Rattata Lv 4 [SLP]", EFX.with_status_tag("Rattata Lv 4", "SLP"))
	end)

	it("replaces an old tag, and removes it when the tag is nil", function()
		assert.equals("Rattata Lv 4 [PAR]", EFX.with_status_tag("Rattata Lv 4 [SLP]", "PAR"))
		assert.equals("Rattata Lv 4", EFX.with_status_tag("Rattata Lv 4 [SLP]", nil))
	end)

	it("keeps the exhausted suffix at the end, so the runtime can strip it", function()
		local text = EFX.with_status_tag("Rattata Lv 4 (exhausted)", "CNF")
		assert.equals("Rattata Lv 4 [CNF] (exhausted)", text)
		assert.equals("Rattata Lv 4 (exhausted)", EFX.with_status_tag(text, nil))
	end)

	it("is idempotent", function()
		local once = EFX.with_status_tag("Pikachu Lv 9", "PAR")
		assert.equals(once, EFX.with_status_tag(once, "PAR"))
	end)
end)

describe("combat effects: stage decay holder", function()
	it("blocks drops with mist only", function()
		assert.is_true(EFX.blocks_drop(-2, true))
		assert.is_false(EFX.blocks_drop(-2, false))
	end)
end)
