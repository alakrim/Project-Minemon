-- Unit tests for mods/minemon/minemon_party/party_logic.lua (pure logic, no Luanti).
-- Covers: list ops (max 6, duplicates, write-back by uid), lead selection (fainted skipped), make lead, the regen
-- ticks, the faint revive timer, the owned brain's distances and target rule, HUD colours and text, and the serialize
-- safety of load/save (bad input never breaks the party).
-- luacheck: globals describe it assert

local here = debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$") or "."
local P = dofile(here .. "/../../mods/minemon/minemon_party/party_logic.lua")

local function member(uid, hp, level)
	return { uid = uid, species_id = 155, level = level or 5, hp = hp or 20, nickname = "", faint_s = 0 }
end

local function uids(list)
	local out = {}
	for i, m in ipairs(list) do
		out[i] = m.uid
	end
	return table.concat(out, ",")
end

describe("party_logic constants", function()
	it("matches the T-22 numbers", function()
		assert.equals(6, P.MAX)
		assert.equals(5, P.STARTER_LEVEL)
		assert.are.same({ 1, 4, 7, 152, 155, 158 }, P.STARTERS)
		assert.equals(8, P.REGEN_S)
		assert.equals(600, P.REVIVE_S)
		assert.equals(24, P.TELEPORT_DIST)
		assert.equals(32, P.TARGET_RANGE)
		assert.equals(10, P.ASSIST_RANGE)
		assert.equals(0.25, P.BRAIN_S)
	end)
end)

describe("party_logic list ops", function()
	it("add appends and returns a new list", function()
		local a = { member("a") }
		local b = P.add(a, member("b"))
		assert.equals("a,b", uids(b))
		assert.equals("a", uids(a))
	end)

	it("refuses a seventh member and a duplicate uid", function()
		local list = {}
		for i = 1, 6 do
			list = P.add(list, member("m" .. i))
		end
		local out, why = P.add(list, member("m7"))
		assert.is_nil(out)
		assert.equals("full", why)
		local out2, why2 = P.add({ member("x") }, member("x"))
		assert.is_nil(out2)
		assert.equals("duplicate", why2)
	end)

	it("replace writes back by uid and keeps the order", function()
		local list = { member("a", 20), member("b", 20) }
		local changed = member("b", 3)
		local out, found = P.replace(list, changed)
		assert.is_true(found)
		assert.equals(3, out[2].hp)
		assert.equals(20, list[2].hp)
		assert.equals("a,b", uids(out))
	end)

	it("replace reports a missing uid and returns the list unchanged", function()
		local list = { member("a") }
		local out, found = P.replace(list, member("zz"))
		assert.is_false(found)
		assert.equals(list, out)
	end)

	it("index_of finds a uid or returns nil", function()
		local list = { member("a"), member("b") }
		assert.equals(2, P.index_of(list, "b"))
		assert.is_nil(P.index_of(list, "q"))
	end)
end)

describe("party_logic lead selection", function()
	it("the lead is the first member above 0 HP", function()
		assert.equals(1, P.lead_index({ member("a", 10), member("b", 10) }))
	end)

	it("skips fainted members", function()
		assert.equals(2, P.lead_index({ member("a", 0), member("b", 7) }))
	end)

	it("is nil when everyone has fainted or the party is empty", function()
		assert.is_nil(P.lead_index({ member("a", 0), member("b", 0) }))
		assert.is_nil(P.lead_index({}))
	end)

	it("make_lead moves the member to the front and keeps the rest in order", function()
		local out = P.make_lead({ member("a"), member("b"), member("c") }, 3)
		assert.equals("c,a,b", uids(out))
	end)

	it("make_lead refuses a fainted member and a bad index", function()
		local out, why = P.make_lead({ member("a"), member("b", 0) }, 2)
		assert.is_nil(out)
		assert.equals("fainted", why)
		local out2, why2 = P.make_lead({ member("a") }, 4)
		assert.is_nil(out2)
		assert.equals("no such member", why2)
	end)

	it("make_lead on the lead returns the same order", function()
		assert.equals("a,b", uids(P.make_lead({ member("a"), member("b") }, 1)))
	end)
end)

describe("party_logic regeneration", function()
	it("adds 1 HP after 8 s, not before", function()
		local acc, hp = P.regen_step(0, 10, 20, 7.9)
		assert.equals(10, hp)
		acc, hp = P.regen_step(acc, hp, 20, 0.1)
		assert.equals(11, hp)
		assert.equals(0, acc)
	end)

	it("keeps the remainder between calls", function()
		local acc, hp = P.regen_step(0, 5, 20, 5)
		assert.equals(5, hp)
		acc, hp = P.regen_step(acc, hp, 20, 5)
		assert.equals(6, hp)
		assert.equals(2, acc)
	end)

	it("never goes above max and resets the accumulator at max", function()
		local acc, hp = P.regen_step(0, 19, 20, 100)
		assert.equals(20, hp)
		assert.equals(0, acc)
	end)

	it("does nothing for a fainted or full creature", function()
		local acc, hp = P.regen_step(5, 0, 20, 100)
		assert.equals(0, hp)
		assert.equals(0, acc)
		acc, hp = P.regen_step(5, 20, 20, 100)
		assert.equals(20, hp)
		assert.equals(0, acc)
	end)
end)

describe("party_logic faint revive timer", function()
	it("does not revive before 10 minutes of play time", function()
		local s, revived = P.revive_step(0, 599.9)
		assert.is_false(revived)
		assert.is_true(s > 599)
	end)

	it("revives at 600 s and resets the timer", function()
		local s, revived = P.revive_step(599.5, 0.5)
		assert.is_true(revived)
		assert.equals(0, s)
	end)

	it("accumulates across calls", function()
		local s, revived = P.revive_step(0, 300)
		assert.is_false(revived)
		local _, again = P.revive_step(s, 300)
		assert.is_true(again)
	end)
end)

describe("party_logic owned brain rules", function()
	it("follows: walk beyond 4, stand within 3, keep the action between", function()
		assert.equals("walk", P.follow_action(4.5, false))
		assert.equals("stand", P.follow_action(2.9, true))
		assert.equals("walk", P.follow_action(3.5, true))
		assert.equals("stand", P.follow_action(3.5, false))
	end)

	it("teleports only beyond 24 nodes", function()
		assert.is_false(P.needs_teleport(24))
		assert.is_true(P.needs_teleport(24.1))
	end)

	it("keeps an ordered target only while it exists, is not exhausted and is within 32", function()
		assert.is_true(P.target_valid(true, false, 32))
		assert.is_false(P.target_valid(true, false, 32.5))
		assert.is_false(P.target_valid(true, true, 3))
		assert.is_false(P.target_valid(false, false, 3))
	end)

	it("puts the teleport target 2 m behind the owner, half a node up (not in the ground)", function()
		local p = P.behind({ x = 10, y = 5, z = 10 }, { x = 0, y = 0.3, z = 1 })
		assert.is_true(math.abs(p.x - 10) < 1e-9)
		assert.is_true(math.abs(p.z - 8) < 1e-9)
		assert.equals(5.5, p.y)
		local q = P.behind({ x = 10, y = 5, z = 10 }, { x = 1, y = 0, z = 0 })
		assert.is_true(math.abs(q.x - 8) < 1e-9)
		assert.is_true(math.abs(q.z - 10) < 1e-9)
	end)

	it("falls back to +z when the look direction is vertical", function()
		local p = P.behind({ x = 0, y = 0, z = 0 }, { x = 0, y = 1, z = 0 })
		assert.is_true(math.abs(p.z + 2) < 1e-9)
	end)

	it("sends a creature 2 m in front of the player", function()
		local p = P.in_front({ x = 0, y = 4, z = 0 }, { x = 0, y = -0.5, z = 1 })
		assert.is_true(math.abs(p.z - 2) < 1e-9)
		assert.equals(4.5, p.y)
	end)
end)

describe("party_logic HUD", function()
	it("colours HP white above 50%, yellow below 50%, red below 20%, grey when fainted", function()
		assert.equals(P.COLOUR.white, P.hp_colour(11, 20))
		assert.equals(P.COLOUR.white, P.hp_colour(10, 20))
		assert.equals(P.COLOUR.yellow, P.hp_colour(9, 20))
		assert.equals(P.COLOUR.yellow, P.hp_colour(4, 20))
		assert.equals(P.COLOUR.red, P.hp_colour(3, 20))
		assert.equals(P.COLOUR.grey, P.hp_colour(0, 20))
	end)

	it("marks the active member with an arrow and shows name, level and HP", function()
		local text = P.hud_line(member("a", 18, 5), "cyndaquil", 20, true)
		assert.equals("▶ ● Cyndaquil Lv5 18/20", text)
		assert.equals("  ● Cyndaquil Lv5 0/20", P.hud_line(member("a", 0, 5), "cyndaquil", 20, false))
	end)

	it("uses the nickname when there is one", function()
		local m = member("a", 9, 7)
		m.nickname = "Flame"
		assert.equals("  ● Flame Lv7 9/20", P.hud_line(m, "cyndaquil", 20, false))
	end)

	it("title-cases names and types and reads an empty status as OK", function()
		assert.equals("Mr Mime", P.display_name("mr_mime"))
		assert.equals("Grass/Poison", P.types_text({ "grass", "poison" }))
		assert.equals("OK", P.status_text("none"))
		assert.equals("Burn", P.status_text("burn"))
		assert.equals("#ff7a2e", P.type_colour("fire"))
		assert.equals("#ffffff", P.type_colour("nonsense"))
	end)
end)

-- Stand-ins for minemon.instance.deserialize / serialize: the party rules never look at other fields.
local function de(t)
	if t.boom then
		error("corrupt")
	end
	return { uid = t.uid, species_id = t.species_id, level = t.level, hp = t.hp, nickname = "", ivs = {},
		moves = {}, bond = 0 }
end
local function se(m)
	return { uid = m.uid, species_id = m.species_id, level = m.level, hp = m.hp }
end

describe("party_logic serialize safety", function()
	it("loads nothing from a non-table", function()
		assert.equals(0, #P.load(nil, de))
		assert.equals(0, #P.load("garbage", de))
		assert.equals(0, #P.load(42, de))
	end)

	it("drops entries that are not valid members", function()
		local parsed = {
			"text",
			{ uid = "", species_id = 1, level = 5, hp = 5 },
			{ uid = "ok", species_id = 0, level = 5, hp = 5 },
			{ uid = "boom", boom = true },
			{ uid = "good", species_id = 155, level = 5, hp = 9 },
		}
		local list = P.load(parsed, de)
		assert.equals("good", uids(list))
	end)

	it("cuts the party to MAX and drops duplicate uids", function()
		local parsed = {}
		for i = 1, 9 do
			parsed[#parsed + 1] = { uid = "u" .. (i % 7), species_id = 1, level = 5, hp = 5 }
		end
		local list = P.load(parsed, de)
		assert.is_true(#list <= P.MAX)
		local seen = {}
		for _, m in ipairs(list) do
			assert.is_nil(seen[m.uid])
			seen[m.uid] = true
		end
	end)

	it("clamps level, HP and fainted time", function()
		local list = P.load({ { uid = "a", species_id = 1, level = 0, hp = -4, faint_s = 99999 } }, de)
		assert.equals(1, list[1].level)
		assert.equals(0, list[1].hp)
		assert.equals(P.REVIVE_S, list[1].faint_s)
	end)

	it("save writes JSON-safe tables with faint_s and load reads them back", function()
		local m = member("a", 0, 5)
		m.faint_s = 120
		local saved = P.save({ m }, se)
		assert.equals("table", type(saved[1]))
		assert.equals(120, saved[1].faint_s)
		local back = P.load(saved, de)
		assert.equals(0, back[1].hp)
		assert.equals(120, back[1].faint_s)
	end)

	it("handles a missing faint_s when saving and loading", function()
		local saved = P.save({ { uid = "a", species_id = 1, level = 5, hp = 5 } }, se)
		assert.equals(0, saved[1].faint_s)
	end)
end)
