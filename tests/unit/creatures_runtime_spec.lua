-- Unit tests for mods/minemon/minemon_creatures/runtime_logic.lua (pure logic, no Luanti).
-- Covers: HP clamp and sync, the punch damage formula, exhausted timing and recovery, the nametag suffix,
-- the brain chain (order, stop and skip semantics, error isolation) and the log throttle.
-- luacheck: globals describe it assert

local here = debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$") or "."
local R = dofile(here .. "/../../mods/minemon/minemon_creatures/runtime_logic.lua")

describe("runtime_logic constants", function()
	it("matches the D-027 numbers", function()
		assert.equals(20, R.EXHAUST_SECONDS)
		assert.equals(0.25, R.RECOVER_FRACTION)
		assert.equals(60, R.LOG_INTERVAL)
	end)
end)

describe("runtime_logic.apply_damage", function()
	it("lowers HP by the amount", function()
		assert.equals(27, R.apply_damage(30, 30, 3))
	end)

	it("clamps at 0", function()
		assert.equals(0, R.apply_damage(5, 30, 9999))
	end)

	it("clamps at max when the HP is already above max", function()
		assert.equals(30, R.apply_damage(40, 30, 0))
	end)

	it("ignores a zero or negative amount", function()
		assert.equals(12, R.apply_damage(12, 30, 0))
		assert.equals(12, R.apply_damage(12, 30, -4))
	end)
end)

describe("runtime_logic.hit_amount", function()
	it("is 0 below the threshold", function()
		assert.equals(0, R.hit_amount(0))
		assert.equals(0, R.hit_amount(0.09))
	end)

	it("is at least 1 for a hit", function()
		assert.equals(1, R.hit_amount(0.1))
		assert.equals(1, R.hit_amount(0.9))
	end)

	it("rounds down above 1", function()
		assert.equals(3, R.hit_amount(3.7))
		assert.equals(2, R.hit_amount(2))
	end)
end)

describe("runtime_logic.punch_damage", function()
	it("gives the group damage at full punch and full armor", function()
		assert.equals(2, R.punch_damage({ fleshy = 2 }, { fleshy = 100 }, 1.0, 1.0))
	end)

	it("scales with the armor percentage", function()
		assert.equals(1, R.punch_damage({ fleshy = 2 }, { fleshy = 50 }, 1.0, 1.0))
	end)

	it("counts an absent armor group as 0", function()
		assert.equals(0, R.punch_damage({ fleshy = 2 }, { immortal = 1 }, 1.0, 1.0))
	end)

	it("sums the damage groups", function()
		assert.equals(5, R.punch_damage({ fleshy = 2, crush = 3 }, { fleshy = 100, crush = 100 }, 1.0, 1.0))
	end)

	it("scales by the time since the last punch, capped at 1", function()
		assert.equals(1, R.punch_damage({ fleshy = 2 }, { fleshy = 100 }, 0.5, 1.0))
		assert.equals(2, R.punch_damage({ fleshy = 2 }, { fleshy = 100 }, 9, 1.0))
	end)

	it("treats a zero time as 0.2 (mcl_mobs quirk, combat.lua:572-574)", function()
		assert.is_near(0.4, R.punch_damage({ fleshy = 2 }, { fleshy = 100 }, 0, 1.0), 1e-9)
	end)

	it("uses 1.4 as the default full punch interval", function()
		assert.is_near(1, R.punch_damage({ fleshy = 2 }, { fleshy = 100 }, 0.7, nil), 1e-9)
	end)

	it("returns 0 with no damage groups", function()
		assert.equals(0, R.punch_damage(nil, { fleshy = 100 }, 1.0, 1.0))
	end)
end)

describe("runtime_logic.reconcile", function()
	it("reports none when the entity and the instance agree", function()
		local kind, amount = R.reconcile(12, 12, 30)
		assert.equals("none", kind)
		assert.equals(0, amount)
	end)

	it("reports the damage when the entity is lower (mcl subtracted)", function()
		local kind, amount = R.reconcile(9, 12, 30)
		assert.equals("damage", kind)
		assert.equals(3, amount)
	end)

	it("counts a negative entity HP as 0", function()
		local kind, amount = R.reconcile(-4, 12, 30)
		assert.equals("damage", kind)
		assert.equals(12, amount)
	end)

	it("reports the heal when the entity is higher, capped at max", function()
		local kind, amount = R.reconcile(40, 12, 30)
		assert.equals("heal", kind)
		assert.equals(18, amount)
	end)
end)

describe("runtime_logic.recovery_hp", function()
	it("is 25% of max, rounded down", function()
		assert.equals(10, R.recovery_hp(40))
		assert.equals(7, R.recovery_hp(30))
	end)

	it("is at least 1", function()
		assert.equals(1, R.recovery_hp(3))
		assert.equals(1, R.recovery_hp(1))
	end)
end)

describe("runtime_logic.tick_exhausted", function()
	it("counts down and is not over while time remains", function()
		local left, done = R.tick_exhausted(20, 5)
		assert.equals(15, left)
		assert.is_false(done)
	end)

	it("is over at exactly 0", function()
		local left, done = R.tick_exhausted(0.5, 0.5)
		assert.equals(0, left)
		assert.is_true(done)
	end)

	it("is over when the step overshoots", function()
		local _, done = R.tick_exhausted(1, 2)
		assert.is_true(done)
	end)

	it("a full exhaustion lasts EXHAUST_SECONDS in steps", function()
		local left, done = R.EXHAUST_SECONDS, false
		local steps = 0
		while not done do
			left, done = R.tick_exhausted(left, 0.5)
			steps = steps + 1
		end
		assert.equals(40, steps)
	end)
end)

describe("runtime_logic nametag suffix", function()
	it("adds the suffix once", function()
		assert.equals("Rattata Lv 4 (exhausted)", R.with_suffix("Rattata Lv 4"))
		assert.equals("Rattata Lv 4 (exhausted)", R.with_suffix("Rattata Lv 4 (exhausted)"))
	end)

	it("removes the suffix and leaves other text alone", function()
		assert.equals("Rattata Lv 4", R.without_suffix("Rattata Lv 4 (exhausted)"))
		assert.equals("Rattata Lv 4", R.without_suffix("Rattata Lv 4"))
	end)

	it("handles a missing nametag", function()
		assert.equals(" (exhausted)", R.with_suffix(nil))
		assert.equals("", R.without_suffix(nil))
	end)
end)

describe("runtime_logic.should_log", function()
	it("logs the first time", function()
		assert.is_true(R.should_log(nil, 100, 60))
	end)

	it("stays quiet inside the interval", function()
		assert.is_false(R.should_log(100, 130, 60))
	end)

	it("logs again once the interval has passed", function()
		assert.is_true(R.should_log(100, 160, 60))
	end)
end)

describe("runtime_logic.run_chain", function()
	local function brain(name, result, log)
		return {
			name = name,
			fn = function(_, _)
				log[#log + 1] = name
				return result
			end,
		}
	end

	it("runs every brain in registration order when none stops", function()
		local log = {}
		local out = R.run_chain({ brain("a", nil, log), brain("b", false, log), brain("c", nil, log) }, {}, 0.1)
		assert.are.same({ "a", "b", "c" }, log)
		assert.is_nil(out)
	end)

	it("true stops the chain and returns nil, so mcl's default states still run", function()
		local log = {}
		local out = R.run_chain({ brain("a", true, log), brain("b", nil, log) }, {}, 0.1)
		assert.are.same({ "a" }, log)
		assert.is_nil(out)
	end)

	it("skip_states stops the chain and returns false, so do_states is skipped", function()
		local log = {}
		local out = R.run_chain({ brain("a", "skip_states", log), brain("b", nil, log) }, {}, 0.1)
		assert.are.same({ "a" }, log)
		assert.is_false(out)
	end)

	it("passes self and dtime to every brain", function()
		local seen = {}
		local me = { id = 1 }
		R.run_chain({ { name = "a", fn = function(self, dtime)
			seen[#seen + 1] = self
			seen[#seen + 1] = dtime
		end } }, me, 0.25)
		assert.equals(me, seen[1])
		assert.equals(0.25, seen[2])
	end)

	it("isolates an error: the failing brain is reported and the chain goes on", function()
		local log, errors = {}, {}
		local chain = {
			{ name = "bad", fn = function() error("boom") end },
			brain("after", nil, log),
		}
		local out = R.run_chain(chain, {}, 0.1, function(name, msg)
			errors[#errors + 1] = name .. ":" .. msg
		end)
		assert.are.same({ "after" }, log)
		assert.equals(1, #errors)
		assert.is_truthy(errors[1]:find("^bad:"))
		assert.is_nil(out)
	end)

	it("an error does not count as a stop", function()
		local log = {}
		local chain = {
			{ name = "bad", fn = function() error("x") end },
			brain("b", "skip_states", log),
		}
		assert.is_false(R.run_chain(chain, {}, 0.1, function() end))
		assert.are.same({ "b" }, log)
	end)

	it("runs with an empty chain and returns nil", function()
		assert.is_nil(R.run_chain({}, {}, 0.1))
	end)
end)

describe("runtime_logic.damage_step (the single damage path, instance side)", function()
	it("lowers HP and reports the amount dealt", function()
		local hp, dealt, zero = R.damage_step(20, 20, 3, false)
		assert.equals(17, hp)
		assert.equals(3, dealt)
		assert.is_false(zero)
	end)

	it("clamps at 0 and reports the zero crossing once", function()
		local hp, dealt, zero = R.damage_step(5, 20, 9999, false)
		assert.equals(0, hp)
		assert.equals(5, dealt)
		assert.is_true(zero)
	end)

	it("does not report a zero crossing when HP is already 0", function()
		local hp, dealt, zero = R.damage_step(0, 20, 4, false)
		assert.equals(0, hp)
		assert.equals(0, dealt)
		assert.is_false(zero)
	end)

	it("ignores damage while exhausted", function()
		local hp, dealt, zero = R.damage_step(0, 20, 4, true)
		assert.equals(0, hp)
		assert.equals(0, dealt)
		assert.is_false(zero)
	end)

	it("ignores a sub-threshold hit", function()
		local hp, dealt = R.damage_step(20, 20, 0.05, false)
		assert.equals(20, hp)
		assert.equals(0, dealt)
	end)

	it("keeps HP between 0 and max for any hit", function()
		for _, raw in ipairs({ 0, 0.4, 1, 7.9, 30, 1000 }) do
			local hp = R.damage_step(12, 20, raw, false)
			assert.is_true(hp >= 0 and hp <= 20)
		end
	end)
end)

describe("runtime_logic.heal_step", function()
	it("adds HP up to max", function()
		local hp, added = R.heal_step(10, 20, 4, false)
		assert.equals(14, hp)
		assert.equals(4, added)
	end)

	it("caps at max", function()
		local hp, added = R.heal_step(18, 20, 50, false)
		assert.equals(20, hp)
		assert.equals(2, added)
	end)

	it("does nothing for an exhausted creature", function()
		local hp, added = R.heal_step(0, 20, 10, true)
		assert.equals(0, hp)
		assert.equals(0, added)
	end)

	it("ignores amounts below 1", function()
		local hp, added = R.heal_step(10, 20, 0.5, false)
		assert.equals(10, hp)
		assert.equals(0, added)
	end)
end)

describe("runtime_logic.zero_outcome", function()
	it("exhausts a wild creature", function()
		assert.equals("exhaust", R.zero_outcome(false))
	end)

	it("faints an owned creature", function()
		assert.equals("faint", R.zero_outcome(true))
	end)
end)

describe("runtime_logic exhaustion timeline (pure)", function()
	-- Drives the same steps as runtime.lua's exhausted_step, with a 0.5 s frame, from the zero HP event.
	local function run_until_recovered(max)
		local left = R.EXHAUST_SECONDS
		local frames = 0
		local done = false
		while not done do
			frames = frames + 1
			left, done = R.tick_exhausted(left, 0.5)
			if frames > 1000 then
				error("exhaustion never ended")
			end
		end
		return R.recovery_hp(max), frames
	end

	it("recovers after 20 s, which is 40 frames of 0.5 s", function()
		local _, frames = run_until_recovered(40)
		assert.equals(40, frames)
	end)

	it("recovers to 25% of max HP", function()
		local hp = run_until_recovered(40)
		assert.equals(10, hp)
		hp = run_until_recovered(31)
		assert.equals(7, hp)
	end)

	it("a heal during exhaustion does not shorten it", function()
		-- Heal is refused while exhausted, so the timer alone decides when the creature recovers.
		local hp = R.heal_step(0, 40, 40, true)
		assert.equals(0, hp)
		local _, frames = run_until_recovered(40)
		assert.equals(40, frames)
	end)
end)

describe("runtime_logic enraged state (D-030, T-26)", function()
	it("lasts 30 seconds", function()
		assert.equals(30, R.ENRAGE_SECONDS)
	end)

	it("counts down and reports when the rage is over", function()
		local left, done = R.tick_enraged(30, 10)
		assert.equals(20, left)
		assert.is_false(done)
		left, done = R.tick_enraged(0.5, 0.5)
		assert.equals(0, left)
		assert.is_true(done)
	end)

	it("runs out in whole steps, the same way as exhaustion", function()
		local rem = R.ENRAGE_SECONDS
		local frames = 0
		local done = false
		while not done do
			rem, done = R.tick_enraged(rem, 0.5)
			frames = frames + 1
		end
		assert.equals(60, frames)
	end)
end)
