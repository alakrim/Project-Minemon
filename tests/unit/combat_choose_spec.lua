-- Unit tests for mods/minemon/minemon_combat/choose_logic.lua (pure logic, no Luanti).
-- luacheck: globals describe it assert

local here = debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$") or "."
local C = dofile(here .. "/../../mods/minemon/minemon_combat/choose_logic.lua")
local RNG = dofile(here .. "/../../mods/minemon/minemon_core/rng.lua")

-- A small stand-in chart: grass hits fire for 2x, fire hits grass for 0.5x, everything else is neutral.
local function mult(atk_type, def_types)
	local m = 1.0
	for _, d in ipairs(def_types) do
		if atk_type == "grass" and d == "fire" then
			m = m * 2.0
		elseif atk_type == "fire" and d == "grass" then
			m = m * 0.5
		elseif atk_type == "normal" and d == "ghost" then
			m = m * 0.0
		end
	end
	return m
end

local MOVES = {
	tackle = { type = "normal", category = "physical", power = 35, accuracy = 95, archetype = "melee_arc" },
	vine_whip = { type = "grass", category = "special", power = 35, accuracy = 100, archetype = "projectile" },
	ember = { type = "fire", category = "special", power = 40, accuracy = 100, archetype = "projectile" },
	growl = { type = "normal", category = "status", power = nil, accuracy = 100, archetype = "status_cloud",
		effect = { stat_changes = { { stat = "atk", stages = -1, target = "target" } } } },
	seismic = { type = "normal", category = "physical", power = nil, accuracy = 100, archetype = "melee_arc" },
}

local function cand(id, opts)
	opts = opts or {}
	return {
		id = id,
		pp = opts.pp,
		move = MOVES[id],
		on_cooldown = opts.on_cooldown or false,
	}
end

local function ctx(target_status)
	return {
		user_types = { "grass", "poison" },
		target_types = { "fire" },
		target_status = target_status or "none",
		type_mult = mult,
	}
end

describe("combat choose_logic.score", function()
	it("scores a super-effective STAB move above a neutral one", function()
		local se = C.score(MOVES.vine_whip, ctx())
		local neutral = C.score(MOVES.tackle, ctx())
		-- vine_whip: 35 x 1.0 x 1.5 STAB x 2.0 = 105; tackle: 35 x 0.95 x 1.0 x 1.0 = 33.25
		assert.is_true(math.abs(se - 105) < 1e-9)
		assert.is_true(math.abs(neutral - 33.25) < 1e-9)
	end)

	it("scores a status move 30 when the target has no status and 0 otherwise", function()
		assert.equals(30, C.score(MOVES.growl, ctx("none")))
		assert.equals(30, C.score(MOVES.growl, { target_status = nil, user_types = {}, target_types = {},
			type_mult = mult }))
		assert.equals(0, C.score(MOVES.growl, ctx("burn")))
		assert.equals(0, C.score(MOVES.growl, ctx("paralysis")))
	end)

	it("scores a move with no power as 0", function()
		assert.equals(0, C.score(MOVES.seismic, ctx()))
	end)

	it("scores a type-immune move as 0", function()
		local immune = { type = "normal", category = "physical", power = 90, accuracy = 100 }
		local c = { user_types = {}, target_types = { "ghost" }, target_status = "none", type_mult = mult }
		assert.equals(0, C.score(immune, c))
	end)
end)

describe("combat choose_logic.choose_best", function()
	it("prefers the super-effective move", function()
		local id = C.choose_best({ cand("tackle"), cand("vine_whip") }, ctx())
		assert.equals("vine_whip", id)
	end)

	it("skips moves on cooldown and moves with 0 PP", function()
		local list = { cand("vine_whip", { on_cooldown = true }), cand("ember", { pp = 0 }), cand("tackle", { pp = 5 }) }
		assert.equals("tackle", C.choose_best(list, ctx()))
	end)

	it("returns nil when nothing is eligible", function()
		local list = { cand("vine_whip", { on_cooldown = true }), cand("tackle", { pp = 0 }) }
		assert.is_nil(C.choose_best(list, ctx()))
		assert.is_nil(C.choose({}, ctx(), RNG.new(1)))
	end)

	it("picks a status move when the target has no status and the damage is weak", function()
		local weak = { type = "normal", category = "physical", power = 10, accuracy = 100, archetype = "melee_arc" }
		local list = { { id = "weak", pp = nil, move = weak, on_cooldown = false }, cand("growl") }
		assert.equals("growl", C.choose_best(list, ctx("none")))
		assert.equals("weak", C.choose_best(list, ctx("burn")))
	end)

	it("keeps the earlier move on a tie", function()
		local a = { id = "a", pp = nil, move = MOVES.tackle, on_cooldown = false }
		local b = { id = "b", pp = nil, move = MOVES.tackle, on_cooldown = false }
		assert.equals("a", C.choose_best({ a, b }, ctx()))
	end)
end)

describe("combat choose_logic.choose (15% randomness, seeded)", function()
	it("returns the super-effective move on most seeds and always a valid id", function()
		local list = { cand("tackle"), cand("vine_whip"), cand("ember") }
		local valid = { tackle = true, vine_whip = true, ember = true }
		local best = 0
		-- Seeds are spread out: the first draw of a small Park-Miller seed is near 0, which would always take the
		-- random branch.
		for seed = 1, 400 do
			local id = C.choose(list, ctx(), RNG.new(seed * 1000003))
			assert.is_true(valid[id] == true)
			if id == "vine_whip" then
				best = best + 1
			end
		end
		-- Best 85% of the time, plus 1/3 of the 15% random picks: about 90%.
		assert.is_true(best >= 320, "vine_whip chosen " .. best .. " of 400")
	end)

	it("is deterministic for a given seed", function()
		local list = { cand("tackle"), cand("vine_whip") }
		local a = C.choose(list, ctx(), RNG.new(42))
		local b = C.choose(list, ctx(), RNG.new(42))
		assert.equals(a, b)
	end)

	it("never picks a move on cooldown, even at random", function()
		local list = { cand("vine_whip", { on_cooldown = true }), cand("tackle") }
		for seed = 1, 200 do
			assert.equals("tackle", C.choose(list, ctx(), RNG.new(seed)))
		end
	end)
end)
