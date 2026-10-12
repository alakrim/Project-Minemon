-- Unit tests for mods/minemon/minemon_growth/growth_logic.lua (pure logic, no Luanti).
-- Covers: the multi-level exp gain, the HP fraction, the learn plan (auto-learn under 4 moves, prompts at 4, no
-- duplicates), every evolution condition kind on real species ids, the bond clamps and clock, and the cinematic spiral.
-- The species below copy the growth and evolution fields of data/species.json for the ids named in T-27.
-- luacheck: globals describe it assert

local here = debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$") or "."
local G = dofile(here .. "/../../mods/minemon/minemon_growth/growth_logic.lua")
local F = dofile(here .. "/../../mods/minemon/minemon_core/formulas.lua")

local function species(id, name, growth, evolutions)
	return { id = id, name = name, growth_rate = growth, evolutions = evolutions or {}, learnset = {} }
end

-- Real ids and evolutions (data/species.json).
local BULBASAUR = species(1, "bulbasaur", "medium_slow", { { conditions = { min_level = 16 }, to = 2 } })
local PIKACHU = species(25, "pikachu", "medium", { { conditions = { item = "thunder_stone" }, to = 26 } })
local GOLBAT = species(42, "golbat", "medium", { { conditions = { min_bond = 220 }, to = 169 } })
local POLIWHIRL = species(61, "poliwhirl", "medium_slow", {
	{ conditions = { item = "water_stone" }, to = 62 },
	{ conditions = { held_item = "king_s_rock", trade = true }, to = 186 },
})
local KADABRA = species(64, "kadabra", "medium_slow", { { conditions = { trade = true }, to = 65 } })
local EEVEE = species(133, "eevee", "medium", {
	{ conditions = { min_bond = 220, time_of_day = "day" }, to = 196 },
	{ conditions = { min_bond = 220, time_of_day = "night" }, to = 197 },
})
local TYROGUE = species(236, "tyrogue", "medium", {
	{ conditions = { min_level = 20, stat_relation = "attack_gt_defense" }, to = 106 },
	{ conditions = { min_level = 20, stat_relation = "attack_lt_defense" }, to = 107 },
	{ conditions = { min_level = 20, stat_relation = "attack_eq_defense" }, to = 237 },
})

local function mon(level, bond)
	return { level = level, bond = bond or 0 }
end

-- A context with nothing held and no item used, overridden by fields in over.
local function ctx(over)
	local c = {
		is_night = false,
		used_item = nil,
		link_cable = false,
		inventory_has = function()
			return false
		end,
		stats = nil,
	}
	for k, v in pairs(over or {}) do
		c[k] = v
	end
	return c
end

local function holds(id)
	return function(item)
		return item == id
	end
end

local function pp_of(id)
	return ({ tackle = 35, growl = 40, leech_seed = 10, vine_whip = 25, poison_powder = 35 })[id] or 10
end

describe("growth constants", function()
	it("matches the T-27 numbers", function()
		assert.equals(100, G.MAX_LEVEL)
		assert.equals(255, G.MAX_BOND)
		assert.equals(4, G.MAX_MOVES)
		assert.equals(120, G.BOND_PERIOD_S)
		assert.equals(-5, G.BOND_FAINT)
		assert.equals(6, G.CINEMATIC_S)
	end)
end)

describe("exp and levels", function()
	it("a multi-level exp gain lands on the right level", function()
		local start = F.exp_for_level(15, "medium_slow")
		local to18 = F.exp_for_level(18, "medium_slow")
		assert.equals(18, G.level_after(F, to18, "medium_slow", 15))
		assert.equals(17, G.level_after(F, to18 - 1, "medium_slow", 15))
		assert.equals(15, G.level_after(F, start, "medium_slow", 15))
	end)

	it("one exp short of the next level keeps the level", function()
		local just_below = F.exp_for_level(16, "medium_slow") - 1
		assert.equals(15, G.level_after(F, just_below, "medium_slow", 15))
		assert.equals(16, G.level_after(F, just_below + 1, "medium_slow", 15))
	end)

	it("never goes below the current level and caps at 100", function()
		assert.equals(15, G.level_after(F, 0, "medium_slow", 15))
		assert.equals(100, G.level_after(F, 10 ^ 9, "medium", 1))
	end)
end)

describe("HP fraction", function()
	it("keeps the fraction when the max grows", function()
		assert.equals(15, G.rescale_hp(10, 20, 30))
		assert.equals(30, G.rescale_hp(20, 20, 30))
	end)

	it("rounds up, so a living creature never drops to 0", function()
		assert.equals(10, G.rescale_hp(7, 10, 13)) -- 9.1 -> 10
		assert.equals(2, G.rescale_hp(1, 50, 60)) -- 1.2 -> 2
		assert.equals(1, G.rescale_hp(1, 100, 1))
	end)

	it("keeps a fainted creature at 0 and clamps to the new max", function()
		assert.equals(0, G.rescale_hp(0, 20, 30))
		assert.equals(30, G.rescale_hp(40, 40, 30))
	end)

	it("keeps the HP when the old max is unknown", function()
		assert.equals(12, G.rescale_hp(12, 0, 30))
	end)
end)

describe("learn plan", function()
	it("learns at once while fewer than 4 moves are known", function()
		local plan = G.plan_learns({ { id = "tackle", pp = 35 } }, { "growl", "leech_seed" }, {}, pp_of)
		assert.are.same({ "growl", "leech_seed" }, plan.learned)
		assert.are.same({}, plan.prompts)
		assert.equals(3, #plan.moves)
		assert.equals(40, plan.moves[2].pp)
	end)

	it("makes a prompt list at 4 moves and leaves the moves alone", function()
		local four = {
			{ id = "tackle", pp = 35 }, { id = "growl", pp = 40 },
			{ id = "leech_seed", pp = 10 }, { id = "poison_powder", pp = 35 },
		}
		local plan = G.plan_learns(four, { "vine_whip", "tackle" }, {}, pp_of)
		assert.are.same({}, plan.learned)
		assert.are.same({ "vine_whip" }, plan.prompts)
		assert.equals(4, #plan.moves)
		assert.equals("poison_powder", plan.moves[4].id)
	end)

	it("never duplicates a move: known, queued or repeated in the candidates", function()
		local plan = G.plan_learns({ { id = "tackle", pp = 35 } }, { "tackle", "growl", "growl" }, {}, pp_of)
		assert.are.same({ "growl" }, plan.learned)
		local full = {
			{ id = "tackle", pp = 35 }, { id = "growl", pp = 40 },
			{ id = "leech_seed", pp = 10 }, { id = "poison_powder", pp = 35 },
		}
		local repeated = G.plan_learns(full, { "vine_whip", "vine_whip" }, {}, pp_of)
		assert.are.same({ "vine_whip" }, repeated.prompts)
		local queued = G.plan_learns(full, { "vine_whip" }, { "vine_whip" }, pp_of)
		assert.are.same({}, queued.prompts)
	end)

	it("orders candidates by level and keeps each move once", function()
		local learnset = {
			{ level = 1, move = "tackle" }, { level = 4, move = "growl" },
			{ level = 1, move = "growl" }, { level = 7, move = "leech_seed" },
		}
		assert.are.same({ "tackle", "growl" }, G.learn_candidates(learnset, 0, 4))
		assert.are.same({ "leech_seed" }, G.learn_candidates(learnset, 4, 7))
		assert.are.same({}, G.learn_candidates(learnset, 7, 9))
	end)

	it("replaces a slot at full PP, and refuses a slot that is not there", function()
		local moves = { { id = "tackle", pp = 1 }, { id = "growl", pp = 2 } }
		local out = G.replace_move(moves, 2, "vine_whip", 25)
		assert.equals("vine_whip", out[2].id)
		assert.equals(25, out[2].pp)
		assert.equals("growl", moves[2].id)
		assert.is_nil(G.replace_move(moves, 3, "vine_whip", 25))
	end)
end)

describe("evolution conditions", function()
	it("min_level: Bulbasaur evolves at 16, not at 15", function()
		assert.is_true(G.can_evolve(mon(16), BULBASAUR, ctx()))
		assert.is_false(G.can_evolve(mon(15), BULBASAUR, ctx()))
		assert.equals(2, G.matching_evolution(mon(16), BULBASAUR, ctx()).to)
	end)

	it("item: Pikachu with a Thunder Stone gives Raichu, and no other stone does", function()
		assert.equals(26, G.matching_evolution(mon(30), PIKACHU, ctx({ used_item = "thunder_stone" })).to)
		assert.is_false(G.can_evolve(mon(30), PIKACHU, ctx({ used_item = "water_stone" })))
		assert.is_false(G.can_evolve(mon(30), PIKACHU, ctx()))
	end)

	it("min_bond: Golbat at bond 220, not at 219", function()
		assert.is_true(G.can_evolve(mon(30, 220), GOLBAT, ctx()))
		assert.is_false(G.can_evolve(mon(30, 219), GOLBAT, ctx()))
	end)

	it("trade with held_item: Poliwhirl needs the Link Cable and the King's Rock in the bag", function()
		local with_rock = ctx({ link_cable = true, inventory_has = holds("king_s_rock") })
		assert.equals(186, G.matching_evolution(mon(30), POLIWHIRL, with_rock).to)
		assert.is_false(G.can_evolve(mon(30), POLIWHIRL, ctx({ link_cable = true })))
		assert.is_false(G.can_evolve(mon(30), POLIWHIRL, ctx({ inventory_has = holds("king_s_rock") })))
	end)

	it("trade: Kadabra needs the Link Cable", function()
		assert.equals(65, G.matching_evolution(mon(36), KADABRA, ctx({ link_cable = true })).to)
		assert.is_false(G.can_evolve(mon(36), KADABRA, ctx()))
	end)

	it("time_of_day: Eevee at bond 220 gives Espeon by day and Umbreon by night", function()
		assert.equals(196, G.matching_evolution(mon(20, 220), EEVEE, ctx({ is_night = false })).to)
		assert.equals(197, G.matching_evolution(mon(20, 220), EEVEE, ctx({ is_night = true })).to)
		assert.is_false(G.can_evolve(mon(20, 200), EEVEE, ctx({ is_night = false })))
	end)

	it("stat_relation: Tyrogue at 20 picks the form from attack against defence", function()
		local function stats(atk, def)
			return { atk = atk, def = def }
		end
		assert.equals(106, G.matching_evolution(mon(20), TYROGUE, ctx({ stats = stats(30, 20) })).to)
		assert.equals(107, G.matching_evolution(mon(20), TYROGUE, ctx({ stats = stats(20, 30) })).to)
		assert.equals(237, G.matching_evolution(mon(20), TYROGUE, ctx({ stats = stats(25, 25) })).to)
		assert.is_false(G.can_evolve(mon(19), TYROGUE, ctx({ stats = stats(30, 20) })))
		assert.is_false(G.can_evolve(mon(20), TYROGUE, ctx()))
	end)

	it("an empty conditions set and an unknown key never hold", function()
		local odd = species(999, "odd", "medium", { { conditions = {}, to = 1 }, { conditions = { moon = true }, to = 2 } })
		assert.is_false(G.can_evolve(mon(50), odd, ctx()))
		assert.is_false(G.condition_holds("moon", true, mon(50), ctx()))
	end)

	it("day runs from 0.25 to 0.75 inclusive", function()
		assert.is_false(G.is_night(0.5))
		assert.is_false(G.is_night(0.25))
		assert.is_false(G.is_night(0.75))
		assert.is_true(G.is_night(0.1))
		assert.is_true(G.is_night(0.8))
	end)
end)

describe("bond", function()
	it("clamps to 0..255", function()
		assert.equals(255, G.add_bond(250, 10))
		assert.equals(0, G.add_bond(3, -5))
		assert.equals(0, G.clamp_bond(-4))
		assert.equals(255, G.clamp_bond(999))
	end)

	it("a level-up adds 3 below 100 and 2 from 100 on", function()
		assert.equals(102, G.bond_after_level(99))
		assert.equals(102, G.bond_after_level(100))
		assert.equals(255, G.bond_after_level(254))
	end)

	it("the active clock gives 1 point per 120 s", function()
		assert.are.same({ 0, 1 }, { G.bond_tick(0, 120) })
		assert.are.same({ 10, 1 }, { G.bond_tick(100, 30) })
		assert.are.same({ 119, 1 }, { G.bond_tick(0, 239) })
		assert.are.same({ 60, 0 }, { G.bond_tick(0, 60) })
	end)

	it("hearts are bond / 51, rounded", function()
		assert.equals(0, G.hearts(0))
		assert.equals(0, G.hearts(25))
		assert.equals(1, G.hearts(70))
		assert.equals(4, G.hearts(220))
		assert.equals(5, G.hearts(255))
	end)
end)

describe("cinematic spiral", function()
	it("tightens and rises over the 6 s", function()
		local start, finish = G.spiral(0), G.spiral(G.CINEMATIC_S)
		assert.is_true(start.radius > finish.radius)
		assert.is_true(start.height < finish.height)
		assert.is_true(math.abs(finish.radius - 0.15) < 1e-9)
		assert.is_true(math.abs(finish.height - 2.0) < 1e-9)
	end)
end)
