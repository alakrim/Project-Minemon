-- Unit tests for mods/minemon/minemon_core/rng.lua and events.lua (pure logic, no Luanti).
-- luacheck: globals describe it assert

local here = debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$") or "."
local R = dofile(here .. "/../../mods/minemon/minemon_core/rng.lua")
local E = dofile(here .. "/../../mods/minemon/minemon_core/events.lua")

describe("rng", function()
	it("gives the same sequence for the same seed", function()
		local a, b = R.new(42), R.new(42)
		for _ = 1, 200 do
			assert.equals(a:float(), b:float())
		end
	end)

	it("gives different sequences for different seeds", function()
		local a, b = R.new(42), R.new(43)
		local same = 0
		for _ = 1, 50 do
			if a:float() == b:float() then
				same = same + 1
			end
		end
		assert.is_true(same < 5)
	end)

	it("float() stays strictly inside (0, 1), also for seeds 0 and 1", function()
		for _, seed in ipairs({ 0, 1, 2147483646, 123456789 }) do
			local r = R.new(seed)
			for _ = 1, 500 do
				local f = r:float()
				assert.is_true(f > 0 and f < 1, "seed " .. seed .. " gave " .. f)
			end
		end
	end)

	it("int(a, b) covers a..b inclusive and nothing else", function()
		local r = R.new(7)
		local seen = {}
		for _ = 1, 2000 do
			local v = r:int(3, 7)
			assert.is_true(v >= 3 and v <= 7)
			assert.equals(math.floor(v), v)
			seen[v] = true
		end
		for v = 3, 7 do
			assert.is_true(seen[v] == true, "value " .. v .. " never appeared")
		end
	end)

	it("int(a, a) always gives a, and negative ranges work", function()
		local r = R.new(5)
		assert.equals(9, r:int(9, 9))
		for _ = 1, 100 do
			local v = r:int(-2, 2)
			assert.is_true(v >= -2 and v <= 2)
		end
	end)

	it("int(a, b) with a > b is an error", function()
		assert.has_error(function()
			R.new(1):int(5, 4)
		end)
	end)
end)

describe("events", function()
	it("calls handlers in registration order with the fired arguments", function()
		local ev = E.create(function() end)
		local calls = {}
		ev.register("thing", function(a, b)
			calls[#calls + 1] = "first " .. a .. b
		end)
		ev.register("thing", function(a, b)
			calls[#calls + 1] = "second " .. a .. b
		end)
		ev.fire("thing", "x", "y")
		assert.are.same({ "first xy", "second xy" }, calls)
	end)

	it("an error in one handler is logged and the others still run", function()
		local logged = {}
		local ev = E.create(function(message)
			logged[#logged + 1] = message
		end)
		local ran_after = false
		ev.register("creature_defeated", function()
			error("boom")
		end)
		ev.register("creature_defeated", function()
			ran_after = true
		end)
		ev.fire("creature_defeated", {}, {})
		assert.is_true(ran_after)
		assert.equals(1, #logged)
		assert.is_truthy(logged[1]:find("creature_defeated", 1, true))
		assert.is_truthy(logged[1]:find("boom", 1, true))
	end)

	it("firing a name with no handlers does nothing", function()
		local ev = E.create(function()
			error("should not log")
		end)
		assert.has_no.errors(function()
			ev.fire("nobody_listens", 1, 2, 3)
		end)
	end)

	it("handlers registered during a fire run from the next fire", function()
		local ev = E.create(function() end)
		local count = 0
		ev.register("tick", function()
			count = count + 1
			if count == 1 then
				ev.register("tick", function()
					count = count + 100
				end)
			end
		end)
		ev.fire("tick")
		assert.equals(1, count)
		ev.fire("tick")
		assert.equals(102, count)
	end)

	it("rejects a non-function handler", function()
		local ev = E.create(function() end)
		assert.has_error(function()
			ev.register("tick", "not a function")
		end)
	end)

	it("keeps the registries of separate create() calls apart", function()
		local one = E.create(function() end)
		local two = E.create(function() end)
		local hit = false
		one.register("x", function()
			hit = true
		end)
		two.fire("x")
		assert.is_false(hit)
	end)
end)
