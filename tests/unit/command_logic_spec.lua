-- Unit tests for mods/minemon/minemon_party/command_logic.lua (pure logic, no Luanti), T-29.
-- Covers: the slot pp list, cycling (skips 0-PP and empty slots, wraps, nil when no PP), keeping the selection,
-- the queue expiry (6 s), self-target detection (aura, user-only stat changes), and the bar text.
-- luacheck: globals describe it assert

local here = debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$") or "."
local C = dofile(here .. "/../../mods/minemon/minemon_party/command_logic.lua")

describe("command_logic constants", function()
	it("has 4 slots, a 6 s queue and a 12-character name", function()
		assert.equals(4, C.SLOTS)
		assert.equals(6, C.QUEUE_S)
		assert.equals(12, C.NAME_CHARS)
	end)
end)

describe("slot_pps", function()
	it("gives the pp of each move and nil for empty slots", function()
		local pps = C.slot_pps({ { id = "ember", pp = 25 }, { id = "tackle", pp = 0 } })
		assert.equals(25, pps[1])
		assert.equals(0, pps[2])
		assert.is_nil(pps[3])
		assert.is_nil(pps[4])
	end)

	it("reads a missing or negative pp as 0", function()
		local pps = C.slot_pps({ { id = "ember" }, { id = "absorb", pp = -3 } })
		assert.equals(0, pps[1])
		assert.equals(0, pps[2])
	end)

	it("accepts no moveset", function()
		local pps = C.slot_pps(nil)
		assert.is_nil(pps[1])
	end)
end)

describe("next_selectable", function()
	it("moves to the next slot with PP", function()
		assert.equals(2, C.next_selectable({ 5, 5, 5, 5 }, 1))
		assert.equals(4, C.next_selectable({ 5, 5, 5, 5 }, 3))
	end)

	it("skips moves with 0 PP", function()
		assert.equals(3, C.next_selectable({ 5, 0, 5, 5 }, 1))
		assert.equals(4, C.next_selectable({ 5, 0, 0, 5 }, 1))
	end)

	it("skips empty slots", function()
		assert.equals(1, C.next_selectable({ 5, nil, nil, nil }, 1))
		assert.equals(4, C.next_selectable({ 5, nil, nil, 2 }, 1))
	end)

	it("wraps round from the last slot", function()
		assert.equals(1, C.next_selectable({ 5, 0, 0, 5 }, 4))
		assert.equals(1, C.next_selectable({ 5, 5, 5, 5 }, 4))
	end)

	it("returns the same slot when it is the only one with PP", function()
		assert.equals(2, C.next_selectable({ 0, 5, 0, 0 }, 2))
	end)

	it("returns nil when every move is at 0 PP or the slots are empty", function()
		assert.is_nil(C.next_selectable({ 0, 0, 0, 0 }, 1))
		assert.is_nil(C.next_selectable({ nil, nil, nil, nil }, 1))
	end)

	it("starts at slot 1 when there is no current selection", function()
		assert.equals(1, C.next_selectable({ 5, 5, 5, 5 }, nil))
		assert.equals(2, C.next_selectable({ 0, 5, 5, 5 }, nil))
	end)
end)

describe("keep_selection", function()
	it("keeps the current slot while it has PP", function()
		assert.equals(3, C.keep_selection({ 5, 5, 5, 5 }, 3))
	end)

	it("moves on when the current move is out of PP", function()
		assert.equals(4, C.keep_selection({ 0, 0, 0, 5 }, 2))
	end)

	it("returns nil when no move has PP", function()
		assert.is_nil(C.keep_selection({ 0, 0, 0, 0 }, 1))
	end)
end)

describe("queue", function()
	it("expires 6 s after the order", function()
		local q = C.new_queue("ember", 100)
		assert.equals("ember", q.move)
		assert.equals(106, q.expires)
		assert.is_true(C.queue_live(q, 100))
		assert.is_true(C.queue_live(q, 105.9))
		assert.is_false(C.queue_live(q, 106))
		assert.is_false(C.queue_live(q, 120))
	end)

	it("is not live when there is no queue", function()
		assert.is_false(C.queue_live(nil, 100))
	end)
end)

describe("is_self_target", function()
	it("is true for an aura move", function()
		assert.is_true(C.is_self_target({ archetype = "aura", effect = {} }))
	end)

	it("is true when every stat change targets the user", function()
		local move = {
			archetype = "melee_arc",
			effect = { stat_changes = { { stat = "def", stages = 1, target = "user" } } },
		}
		assert.is_true(C.is_self_target(move))
	end)

	it("is false for an attack that changes the target", function()
		local move = {
			archetype = "projectile",
			effect = { stat_changes = { { stat = "atk", stages = -1, target = "target" } } },
		}
		assert.is_false(C.is_self_target(move))
	end)

	it("is false when the stat changes mix user and target", function()
		local move = {
			archetype = "beam",
			effect = { stat_changes = {
				{ stat = "atk", stages = 1, target = "user" },
				{ stat = "def", stages = -1, target = "target" },
			} },
		}
		assert.is_false(C.is_self_target(move))
	end)

	it("is false for a damaging move with no effects", function()
		assert.is_false(C.is_self_target({ archetype = "projectile", effect = {} }))
		assert.is_false(C.is_self_target({ archetype = "melee_arc" }))
	end)

	it("is false for a missing move", function()
		assert.is_false(C.is_self_target(nil))
	end)
end)

describe("bar text", function()
	it("keeps short names and cuts long ones with a dot", function()
		assert.equals("Ember", C.short_name("Ember"))
		assert.equals("Thunder Sho.", C.short_name("Thunder Shock!!"))
		assert.equals(12, #C.short_name("Thunder Shock!!"))
	end)

	it("formats PP as n/max and never below 0", function()
		assert.equals("PP 12/25", C.pp_text(12, 25))
		assert.equals("PP 0/35", C.pp_text(-2, 35))
	end)
end)
