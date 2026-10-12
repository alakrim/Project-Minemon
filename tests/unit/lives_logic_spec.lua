-- Unit tests for mods/minemon/minemon_lives/lives_logic.lua (pure logic, no Luanti).
-- luacheck: globals describe it

local here = debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$") or "."
local L = dofile(here .. "/../../mods/minemon/minemon_lives/lives_logic.lua")

describe("lives_logic.new_state", function()
	it("starts with 3 lives, 0 deaths, alive", function()
		assert.are.same({ lives = 3, deaths = 0, dead = false }, L.new_state(3))
		assert.equals(3, L.MAX)
	end)

	it("defaults to MAX when no max is given", function()
		assert.are.same({ lives = 3, deaths = 0, dead = false }, L.new_state())
	end)
end)

describe("lives_logic.on_death", function()
	it("gives lost_life, lost_life, last_life for the first three deaths", function()
		local s = L.new_state(3)
		local event
		s, event = L.on_death(s, 3)
		assert.equals("lost_life", event)
		assert.equals(2, s.lives)
		s, event = L.on_death(s, 3)
		assert.equals("lost_life", event)
		assert.equals(1, s.lives)
		s, event = L.on_death(s, 3)
		assert.equals("last_life", event)
		assert.equals(0, s.lives)
		assert.is_false(s.dead)
	end)

	it("gives permadeath on the 4th death and sets dead", function()
		local s = { lives = 0, deaths = 3, dead = false }
		local event
		s, event = L.on_death(s, 3)
		assert.equals("permadeath", event)
		assert.is_true(s.dead)
		assert.equals(0, s.lives)
		assert.equals(4, s.deaths)
	end)

	it("changes nothing once dead", function()
		local dead = { lives = 0, deaths = 4, dead = true }
		local s, event = L.on_death(dead, 3)
		assert.are.same({ lives = 0, deaths = 4, dead = true }, s)
		assert.equals("permadeath", event)
	end)

	it("does not mutate its input", function()
		local before = { lives = 3, deaths = 0, dead = false }
		L.on_death(before, 3)
		assert.are.same({ lives = 3, deaths = 0, dead = false }, before)
	end)

	it("counts from max when max is 5", function()
		local s, event = L.on_death(L.new_state(5), 5)
		assert.equals("lost_life", event)
		assert.equals(4, s.lives)
	end)
end)

describe("lives_logic.give_life", function()
	it("adds one life", function()
		assert.equals(2, L.give_life({ lives = 1, deaths = 2, dead = false }, 3).lives)
	end)

	it("is capped at max", function()
		assert.equals(3, L.give_life({ lives = 3, deaths = 0, dead = false }, 3).lives)
	end)

	it("does nothing while dead", function()
		assert.are.same({ lives = 0, deaths = 4, dead = true }, L.give_life({ lives = 0, deaths = 4, dead = true }, 3))
	end)
end)

describe("lives_logic.revive", function()
	it("fully resets a dead state", function()
		assert.are.same({ lives = 3, deaths = 0, dead = false }, L.revive({ lives = 0, deaths = 4, dead = true }, 3))
	end)

	it("fully resets a partly used state", function()
		assert.are.same({ lives = 3, deaths = 0, dead = false }, L.revive({ lives = 1, deaths = 2, dead = false }, 3))
	end)
end)

describe("lives_logic serialize / deserialize", function()
	it("round-trips every reachable state", function()
		local states = {
			L.new_state(3),
			{ lives = 2, deaths = 1, dead = false },
			{ lives = 0, deaths = 3, dead = false },
			{ lives = 0, deaths = 4, dead = true },
		}
		for _, s in ipairs(states) do
			assert.are.same(s, L.deserialize(L.serialize(s, 3), 3))
		end
	end)

	it("writes a compact string", function()
		assert.equals("3:0:0", L.serialize(L.new_state(3), 3))
		assert.equals("0:4:1", L.serialize({ lives = 0, deaths = 4, dead = true }, 3))
	end)

	it("falls back to new_state for garbage, empty and nil input", function()
		local fresh = { lives = 3, deaths = 0, dead = false }
		assert.are.same(fresh, L.deserialize("abc", 3))
		assert.are.same(fresh, L.deserialize("", 3))
		assert.are.same(fresh, L.deserialize(nil, 3))
		assert.are.same(fresh, L.deserialize("3:0", 3))
		assert.are.same(fresh, L.deserialize("x:y:z", 3))
		assert.are.same(fresh, L.deserialize("-1:0:0", 3))
		assert.are.same(fresh, L.deserialize(42, 3))
		assert.are.same(fresh, L.deserialize({}, 3))
	end)

	it("clamps lives above max and forces lives to 0 when dead", function()
		assert.are.same({ lives = 3, deaths = 0, dead = false }, L.deserialize("9:0:0", 3))
		assert.are.same({ lives = 0, deaths = 2, dead = true }, L.deserialize("2:2:1", 3))
	end)
end)
