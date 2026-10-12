-- Unit tests for mods/minemon/minemon_combat/status_logic.lua (pure logic, no Luanti).
-- luacheck: globals describe it assert

local here = debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$") or "."
local S = dofile(here .. "/../../mods/minemon/minemon_combat/status_logic.lua")
local RNG = dofile(here .. "/../../mods/minemon/minemon_core/rng.lua")

describe("combat status_logic maths", function()
	it("burn and poison deal 1/16 of max HP, at least 1", function()
		assert.equals(10, S.burn_damage(160))
		assert.equals(1, S.burn_damage(5))
		assert.equals(1, S.burn_damage(0))
	end)

	it("a burn record ticks every 2 s with 0.5 s steps, and ends after 12 s", function()
		local rec = S.new_record("burn", RNG.new(1))
		local rng = RNG.new(1)
		local total, ticks = 0, 0
		for step = 1, 24 do
			local out = S.advance(rec, 0.5, rng, 160)
			total = total + out.damage
			if out.damage > 0 then
				ticks = ticks + 1
				assert.equals(0, step % 4, "tick must land on every 4th step (2 s at 0.5 s steps)")
			end
			if step < 24 then
				assert.is_false(out.cured)
			else
				assert.is_true(out.cured)
			end
		end
		assert.equals(6, ticks)
		assert.equals(60, total)
	end)

	it("poison ticks the same way as burn", function()
		local rec = S.new_record("poison", RNG.new(1))
		local total = 0
		for _ = 1, 4 do
			local out
			out = S.advance(rec, 0.5, RNG.new(1), 320)
			total = total + out.damage
		end
		assert.equals(20, total)
	end)

	it("thaw chance is 10% per second, so 5.13% per 0.5 s step", function()
		assert.is_true(math.abs(S.thaw_chance(1) - 0.10) < 1e-12)
		assert.is_true(math.abs(S.thaw_chance(0.5) - (1 - 0.9 ^ 0.5)) < 1e-12)
		assert.is_true(math.abs(S.thaw_chance(0.5) - 0.0513) < 1e-3)
	end)

	it("sleep lasts 3 to 7 s (T-31), and both ends are reached", function()
		local lo, hi = math.huge, -math.huge
		for seed = 1, 2000 do
			-- Spread seeds: the first draw of a small seed is near 0 (see combat_choose_spec).
			local t = S.sleep_duration(RNG.new(seed * 1000003))
			assert.is_true(t >= 3 and t <= 7, "sleep " .. t)
			lo, hi = math.min(lo, t), math.max(hi, t)
		end
		assert.is_true(lo < 3.1 and hi > 6.9, "range " .. lo .. " .. " .. hi)
	end)

	it("a rest sleep takes the duration given (T-31: 5 s)", function()
		local rec = S.new_record("sleep", RNG.new(1), 5)
		assert.equals(5, rec.left)
	end)

	it("sleep and freeze block moves, paralysis halves speed", function()
		assert.is_true(S.blocks_moves("sleep"))
		assert.is_true(S.blocks_moves("freeze"))
		assert.is_false(S.blocks_moves("paralysis"))
		assert.is_false(S.blocks_moves("burn"))
		assert.equals(0.5, S.speed_mult("paralysis"))
		assert.equals(0, S.speed_mult("sleep"))
		assert.equals(1, S.speed_mult("none"))
	end)

	it("only the minimal set is recognised", function()
		assert.is_true(S.is_minimal("burn"))
		assert.is_true(S.is_minimal("freeze"))
		assert.is_false(S.is_minimal("confusion"))
		assert.is_false(S.is_minimal("trap"))
	end)

	it("a restored sleep or freeze lasts 3 s, a restored burn, poison or paralysis 12 s (T-23b)", function()
		assert.equals(3, S.restore_record("sleep").left)
		assert.equals(3, S.restore_record("freeze").left)
		assert.equals(12, S.restore_record("burn").left)
		assert.equals(12, S.restore_record("poison").left)
		assert.equals(12, S.restore_record("paralysis").left)
		assert.equals("freeze", S.restore_record("freeze").kind)
		assert.equals(0, S.restore_record("freeze").tick)
	end)

	it("a restored status ends after its duration (T-23b)", function()
		local rng = RNG.new(3)
		local rec = S.restore_record("sleep")
		local out = S.advance(rec, 2.5, rng, 100)
		assert.is_false(out.cured)
		out = S.advance(rec, 0.5, rng, 100)
		assert.is_true(out.cured)
	end)
end)

describe("combat status_logic paralysis and freeze (seeded rng)", function()
	it("paralysis fails about 25% of the time", function()
		local rng = RNG.new(7)
		local fails = 0
		local n = 10000
		for _ = 1, n do
			if S.paralysis_fails(rng) then
				fails = fails + 1
			end
		end
		local rate = fails / n
		assert.is_true(math.abs(rate - 0.25) < 0.02, "fail rate " .. rate)
	end)

	it("the same seed gives the same paralysis rolls", function()
		local a, b = RNG.new(99), RNG.new(99)
		for _ = 1, 50 do
			assert.equals(S.paralysis_fails(a), S.paralysis_fails(b))
		end
	end)

	it("a frozen creature thaws within 200 steps on this seed", function()
		local rng = RNG.new(3)
		local rec = S.new_record("freeze", rng)
		local cured_at = nil
		for step = 1, 200 do
			if S.advance(rec, 0.5, rng, 100).cured then
				cured_at = step
				break
			end
		end
		assert.is_not_nil(cured_at)
	end)
end)

describe("combat status_logic registry", function()
	it("enforces its capacity but still updates existing keys", function()
		local reg = S.new_registry(2)
		assert.is_true(reg.put("a", 1))
		assert.is_true(reg.put("b", 2))
		assert.is_false(reg.put("c", 3))
		assert.is_true(reg.put("a", 10))
		assert.equals(10, reg.get("a"))
		assert.equals(2, reg.size())
	end)

	it("removes entries and frees a slot", function()
		local reg = S.new_registry(1)
		reg.put("a", 1)
		reg.remove("a")
		assert.equals(0, reg.size())
		assert.is_true(reg.put("b", 2))
	end)

	it("prunes entries that fail the keep test", function()
		local reg = S.new_registry(10)
		for i = 1, 5 do
			reg.put("k" .. i, { alive = i % 2 == 1 })
		end
		reg.prune(function(v) return v.alive end)
		assert.equals(3, reg.size())
		assert.is_nil(reg.get("k2"))
		assert.is_not_nil(reg.get("k3"))
	end)

	it("walks entries in key order", function()
		local reg = S.new_registry(10)
		reg.put("c", 3)
		reg.put("a", 1)
		reg.put("b", 2)
		local seen = {}
		reg.each(function(k) seen[#seen + 1] = k end)
		assert.are.same({ "a", "b", "c" }, seen)
	end)
end)
