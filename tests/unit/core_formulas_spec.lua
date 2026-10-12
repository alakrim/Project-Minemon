-- Unit tests for mods/minemon/minemon_core/formulas.lua (pure logic, no Luanti).
-- luacheck: globals describe it assert

local here = debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$") or "."
local F = dofile(here .. "/../../mods/minemon/minemon_core/formulas.lua")
local R = dofile(here .. "/../../mods/minemon/minemon_core/rng.lua")

-- Cyndaquil (species 155) base stats, from data/species.json.
local CYNDAQUIL = { hp = 39, atk = 52, def = 43, spa = 60, spd = 50, spe = 65 }
local ZERO_IVS = { hp = 0, atk = 0, def = 0, spa = 0, spd = 0, spe = 0 }
local MAX_IVS = { hp = 15, atk = 15, def = 15, spa = 15, spd = 15, spe = 15 }

-- rng stand-in: float() and int() return scripted values in order.
local function scripted(floats, ints)
	local fi, ii = 0, 0
	return {
		float = function()
			fi = fi + 1
			assert(floats[fi] ~= nil, "scripted rng ran out of floats")
			return floats[fi]
		end,
		int = function(_, _, _)
			ii = ii + 1
			assert(ints[ii] ~= nil, "scripted rng ran out of ints")
			return ints[ii]
		end,
	}
end

local function near(expected, actual, tol)
	assert.is_true(math.abs(expected - actual) <= (tol or 1e-12), "expected " .. expected .. " got " .. actual)
end

-- Type multiplier stand-in: always the same value.
local function fixed_mult(value)
	return function()
		return value
	end
end

local function view(level, stats, types, stages)
	return { level = level, stats = stats, types = types or {}, stages = stages or {} }
end

describe("formulas.calc_stats", function()
	it("gives Cyndaquil L5 with zero IVs and no bond the values 18/10/9/11/10/11", function()
		-- HP: floor(78*5/100) + 5 + 10 = 3 + 15 = 18. Others: floor(2b*5/100) + 5, e.g. atk floor(104*5/100) + 5 = 10.
		local s = F.calc_stats(CYNDAQUIL, 5, ZERO_IVS, 0)
		assert.are.same({ hp = 18, atk = 10, def = 9, spa = 11, spd = 10, spe = 11 }, s)
	end)

	it("gives Cyndaquil L50 with zero IVs and no bond the values 99/57/48/65/55/70", function()
		-- HP: floor(78*50/100) + 60 = 39 + 60 = 99. atk: floor(104*50/100) + 5 = 52 + 5 = 57.
		local s = F.calc_stats(CYNDAQUIL, 50, ZERO_IVS, 0)
		assert.are.same({ hp = 99, atk = 57, def = 48, spa = 65, spd = 55, spe = 70 }, s)
	end)

	it("adds the IVs: Cyndaquil L50 with 15 IVs gives 106/64/55/72/62/77", function()
		local s = F.calc_stats(CYNDAQUIL, 50, MAX_IVS, 0)
		assert.are.same({ hp = 106, atk = 64, def = 55, spa = 72, spd = 62, spe = 77 }, s)
	end)

	it("applies the bond bonus: bond 255 is +10 percent, floored per stat", function()
		-- 99*110/100 = 108.9 -> 108; 57*110/100 = 62.7 -> 62; 65*110/100 = 71.5 -> 71.
		local s = F.calc_stats(CYNDAQUIL, 50, ZERO_IVS, 255)
		assert.are.same({ hp = 108, atk = 62, def = 52, spa = 71, spd = 60, spe = 77 }, s)
	end)

	it("gives no bonus below bond 25", function()
		assert.are.same(F.calc_stats(CYNDAQUIL, 50, ZERO_IVS, 0), F.calc_stats(CYNDAQUIL, 50, ZERO_IVS, 24))
	end)
end)

describe("formulas.stage_mult", function()
	it("maps stages to multipliers and clamps to -6..6", function()
		assert.equals(1, F.stage_mult(0))
		assert.equals(1.5, F.stage_mult(1))
		assert.equals(2 / 3, F.stage_mult(-1))
		assert.equals(4, F.stage_mult(6))
		assert.equals(4, F.stage_mult(7))
		assert.equals(0.25, F.stage_mult(-6))
		assert.equals(0.25, F.stage_mult(-9))
	end)
end)

describe("formulas.damage", function()
	local ember = { type = "fire", category = "special", power = 40, accuracy = 100, effect = {} }

	it("hand-computed case: Ember L10 special vs grass, STAB, 2x, roll 85", function()
		-- Attacker: L10, spa 50, types {fire}. Defender: spd 40, types {grass}. Both stages 0.
		-- hit 100*1/1 = 100 >= roll 50 -> hit (scripted float 0.5).
		-- Crit roll 0.5 >= 1/16 -> no crit.
		-- A = 50, D = 40. Level term = floor(2*10/5) + 2 = 6.
		-- base = floor(floor(6*40*50/40)/50) + 2 = floor(300/50) + 2 = 8.
		-- raw = 8 * 1.5 (STAB) * 2.0 (fire -> grass) * 1 * 0.85 (roll) = 20.4 -> 20.
		local atk = view(10, { spa = 50 }, { "fire" })
		local def = view(10, { spd = 40 }, { "grass" })
		local r = F.damage(atk, def, ember, fixed_mult(2.0), scripted({ 0.5, 0.5 }, { 85 }))
		assert.are.same({ amount = 20, crit = false, effectiveness = 2.0, missed = false }, r)
	end)

	it("crit doubles the damage: same case with roll 1.0 and a crit roll of 0.01", function()
		-- base 8 * 1.5 * 2.0 * 2 (crit) * 1.0 = 48.
		local atk = view(10, { spa = 50 }, { "fire" })
		local def = view(10, { spd = 40 }, { "grass" })
		local r = F.damage(atk, def, ember, fixed_mult(2.0), scripted({ 0.5, 0.01 }, { 100 }))
		assert.is_true(r.crit)
		assert.equals(48, r.amount)
	end)

	it("the crit threshold is 1/16 by default and 1/4 with effect.high_crit", function()
		local atk = view(10, { spa = 50 }, { "normal" })
		local def = view(10, { spd = 40 }, { "normal" })
		local plain = { type = "normal", category = "special", power = 40, accuracy = 100, effect = {} }
		local high = { type = "normal", category = "special", power = 40, accuracy = 100, effect = { high_crit = true } }
		assert.is_false(F.damage(atk, def, plain, fixed_mult(1), scripted({ 0.5, 0.2 }, { 100 })).crit)
		assert.is_true(F.damage(atk, def, high, fixed_mult(1), scripted({ 0.5, 0.2 }, { 100 })).crit)
		assert.is_true(F.damage(atk, def, plain, fixed_mult(1), scripted({ 0.5, 0.06 }, { 100 })).crit)
	end)

	it("misses when the roll is at or above the hit chance", function()
		local move = { type = "normal", category = "physical", power = 40, accuracy = 50, effect = {} }
		local atk = view(10, { atk = 50 }, {})
		local def = view(10, { def = 40 }, {})
		local r = F.damage(atk, def, move, fixed_mult(1), scripted({ 0.9 }, {}))
		assert.is_true(r.missed)
		assert.equals(0, r.amount)
	end)

	it("the accuracy stage raises the hit chance: +1 turns 50 into 75", function()
		local move = { type = "normal", category = "physical", power = 40, accuracy = 50, effect = {} }
		local atk = view(10, { atk = 50 }, {}, { acc = 1 })
		local def = view(10, { def = 40 }, {})
		local r = F.damage(atk, def, move, fixed_mult(1), scripted({ 0.7, 0.5 }, { 100 }))
		assert.is_false(r.missed)
	end)

	it("immunity gives 0 damage with effectiveness 0", function()
		local atk = view(10, { atk = 50 }, { "electric" })
		local def = view(10, { def = 40 }, { "ground" })
		local move = { type = "electric", category = "physical", power = 90, accuracy = 100, effect = {} }
		local r = F.damage(atk, def, move, fixed_mult(0), scripted({ 0.5, 0.01 }, { 100 }))
		assert.equals(0, r.amount)
		assert.equals(0, r.effectiveness)
		assert.is_false(r.missed)
	end)

	it("a status move deals no damage", function()
		local move = { type = "normal", category = "status", power = nil, accuracy = 100, effect = {} }
		local r = F.damage(view(5, {}, {}), view(5, {}, {}), move, fixed_mult(1), scripted({ 0.1 }, {}))
		assert.equals(0, r.amount)
		assert.is_false(r.missed)
	end)

	it("fixed_damage 'level' gives the attacker level; a number gives that number", function()
		local by_level = { type = "normal", category = "special", accuracy = nil, effect = { fixed_damage = "level" } }
		local by_number = { type = "normal", category = "special", accuracy = nil, effect = { fixed_damage = 40 } }
		local atk = view(17, { spa = 1 }, {})
		local def = view(17, { spd = 1 }, {})
		assert.equals(17, F.damage(atk, def, by_level, fixed_mult(1), scripted({}, {})).amount)
		assert.equals(40, F.damage(atk, def, by_number, fixed_mult(1), scripted({}, {})).amount)
		assert.equals(0, F.damage(atk, def, by_number, fixed_mult(0), scripted({}, {})).amount)
	end)

	it("no STAB without a matching attacker type", function()
		-- base 8 * 1 * 1 * 1 * 1.0 = 8
		local atk = view(10, { spa = 50 }, { "water" })
		local def = view(10, { spd = 40 }, {})
		local r = F.damage(atk, def, ember, fixed_mult(1), scripted({ 0.5, 0.5 }, { 100 }))
		assert.equals(8, r.amount)
	end)

	it("the result is at least 1 when the hit is not immune", function()
		local atk = view(2, { atk = 1 }, {})
		local def = view(2, { def = 999 }, {})
		local move = { type = "normal", category = "physical", power = 1, accuracy = nil, effect = {} }
		assert.equals(1, F.damage(atk, def, move, fixed_mult(0.25), scripted({ 0.5, 0.5 }, { 85 })).amount)
	end)
end)

describe("formulas.catch_chance", function()
	it("full HP, Poke Ball, no status: 15/255 for catch rate 45", function()
		near(15 / 255, F.catch_chance(45, 1, 1, "none"))
	end)

	it("lower HP means a higher chance", function()
		assert.is_true(F.catch_chance(45, 0, 1, "none") > F.catch_chance(45, 0.5, 1, "none"))
		assert.is_true(F.catch_chance(45, 0.5, 1, "none") > F.catch_chance(45, 1, 1, "none"))
		near(45 / 255, F.catch_chance(45, 0, 1, "none"))
	end)

	it("ball ordering: Poke < Great < Ultra < Master", function()
		local poke = F.catch_chance(45, 0.5, 1.0, "none")
		local great = F.catch_chance(45, 0.5, 1.5, "none")
		local ultra = F.catch_chance(45, 0.5, 2.0, "none")
		local master = F.catch_chance(45, 0.5, 255.0, "none")
		assert.is_true(poke < great)
		assert.is_true(great < ultra)
		assert.is_true(ultra < master)
		assert.equals(1, master)
	end)

	it("status multipliers: sleep doubles, burn gives 1.5", function()
		near(2 * 15 / 255, F.catch_chance(45, 1, 1, "sleep"))
		near(1.5 * 15 / 255, F.catch_chance(45, 1, 1, "burn"))
	end)

	it("always stays within 0..1", function()
		assert.equals(1, F.catch_chance(255, 0, 255, "sleep"))
		assert.equals(0, F.catch_chance(0, 1, 1, "none"))
		assert.equals(F.catch_chance(45, 0, 1, "none"), F.catch_chance(45, -1, 1, "none"))
	end)
end)

describe("formulas experience curves", function()
	local GROWTHS = { "fast", "medium_fast", "medium_slow", "slow", "erratic", "fluctuating" }

	it("matches the known values at L10 and L100 for all six growth rates", function()
		local expected = {
			fast = { 800, 800000 },
			medium_fast = { 1000, 1000000 },
			medium_slow = { 560, 1059860 },
			slow = { 1250, 1250000 },
			erratic = { 1800, 600000 },
			fluctuating = { 540, 1640000 },
		}
		for _, g in ipairs(GROWTHS) do
			assert.equals(expected[g][1], F.exp_for_level(10, g), g .. " L10")
			assert.equals(expected[g][2], F.exp_for_level(100, g), g .. " L100")
		end
	end)

	it("level 1 needs 0 experience and the data name 'medium' is the medium_fast curve", function()
		assert.equals(0, F.exp_for_level(1, "medium_slow"))
		assert.equals(F.exp_for_level(20, "medium_fast"), F.exp_for_level(20, "medium"))
	end)

	it("level_for_exp inverts exp_for_level for every level and growth rate", function()
		for _, g in ipairs(GROWTHS) do
			for lv = 1, 100 do
				assert.equals(lv, F.level_for_exp(F.exp_for_level(lv, g), g), g .. " level " .. lv)
			end
		end
	end)

	it("level_for_exp rounds down and caps at 100", function()
		assert.equals(9, F.level_for_exp(999, "medium_fast"))
		assert.equals(10, F.level_for_exp(1000, "medium_fast"))
		assert.equals(100, F.level_for_exp(10 ^ 9, "medium_fast"))
	end)

	it("an unknown growth rate is an error, not a silent 0", function()
		assert.has_error(function()
			F.exp_for_level(10, "bogus")
		end)
	end)

	it("exp_gain: Bulbasaur-like base 64 at L5 gives 45, and 68 with full bond", function()
		assert.equals(45, F.exp_gain(64, 5, 0))
		assert.equals(68, F.exp_gain(64, 5, 255))
	end)
end)

describe("formulas.wild_level", function()
	it("stays in 2..4 at the origin, with the real rng", function()
		local rng = R.new(11)
		for _ = 1, 500 do
			local lv = F.wild_level(0, false, rng)
			assert.is_true(lv >= 2 and lv <= 4)
		end
	end)

	it("uses base 2 + floor(d/80) plus the jitter: d 800 with jitter 0 gives 12", function()
		assert.equals(12, F.wild_level(800, false, scripted({}, { 0 })))
	end)

	it("night multiplies by 1.2 (floored): 12 becomes 14", function()
		assert.equals(14, F.wild_level(800, true, scripted({}, { 0 })))
	end)

	it("clamps to 2..70 far from the origin, and at night", function()
		assert.equals(70, F.wild_level(100000, false, scripted({}, { 2 })))
		assert.equals(70, F.wild_level(100000, true, scripted({}, { 2 })))
		assert.equals(2, F.wild_level(0, false, scripted({}, { -2 })))
	end)
end)

describe("formulas.calc_stats and damage are deterministic with a seeded rng", function()
	it("two seeded runs of 200 hits give the same results", function()
		local move = { type = "fire", category = "special", power = 40, accuracy = 90, effect = {} }
		local atk = view(12, { spa = 60 }, { "fire" })
		local def = view(12, { spd = 50 }, { "grass" })
		local function run(seed)
			local rng = R.new(seed)
			local out = {}
			for i = 1, 200 do
				out[i] = F.damage(atk, def, move, fixed_mult(2), rng).amount
			end
			return out
		end
		assert.are.same(run(99), run(99))
	end)
end)
