-- Unit tests for mods/minemon/minemon_sanctuary/pc_logic.lua (pure logic, no Luanti).
-- Covers: the cap (240), pages (8 x 30), deposit and withdraw rules (the last healthy member is refused, a full party
-- refuses a withdraw), box add and remove, and the load and save safety of the box.
-- luacheck: globals describe it assert

local here = debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$") or "."
local P = dofile(here .. "/../../mods/minemon/minemon_sanctuary/pc_logic.lua")

local function member(uid, hp)
	return { uid = uid, species_id = 155, level = 5, hp = hp or 20, faint_s = 0 }
end

local function entry(uid)
	return { uid = uid, species_id = 25, level = 3, hp = 10, nickname = "", moves = {}, ivs = {} }
end

local function party_of(n, hp)
	local out = {}
	for i = 1, n do
		out[i] = member("p" .. i, hp)
	end
	return out
end

local function box_of(n)
	local out = {}
	for i = 1, n do
		out[i] = entry("b" .. i)
	end
	return out
end

describe("pc_logic constants", function()
	it("matches the D-030 numbers", function()
		assert.equals(240, P.CAP)
		assert.equals(30, P.PAGE_SIZE)
		assert.equals(8, P.PAGES)
		assert.equals(6, P.PARTY_MAX)
		assert.equals(P.CAP, P.PAGE_SIZE * P.PAGES)
	end)
end)

describe("pc_logic pages", function()
	it("gives the bounds of each page", function()
		assert.are.same({ 1, 30 }, { P.page_bounds(1) })
		assert.are.same({ 31, 60 }, { P.page_bounds(2) })
		assert.are.same({ 211, 240 }, { P.page_bounds(8) })
	end)

	it("clamps pages outside 1..8", function()
		assert.are.same({ 1, 30 }, { P.page_bounds(0) })
		assert.are.same({ 211, 240 }, { P.page_bounds(99) })
	end)

	it("finds the page of a box index", function()
		assert.equals(1, P.page_of(1))
		assert.equals(1, P.page_of(30))
		assert.equals(2, P.page_of(31))
		assert.equals(8, P.page_of(240))
	end)
end)

describe("pc_logic deposit rule", function()
	it("allows a deposit when another member is alive", function()
		assert.is_true((P.can_deposit(party_of(3), 2)))
	end)

	it("refuses the last healthy member", function()
		local ok, why = P.can_deposit(party_of(1), 1)
		assert.is_false(ok)
		assert.equals("You can't go out there alone.", why)
	end)

	it("refuses when the others have all fainted", function()
		local party = { member("a", 20), member("b", 0), member("c", 0) }
		local ok, why = P.can_deposit(party, 1)
		assert.is_false(ok)
		assert.equals(P.REFUSE_LAST, why)
	end)

	it("allows the last member when it has fainted", function()
		assert.is_true((P.can_deposit({ member("a", 0) }, 1)))
	end)

	it("refuses an index that is not in the party", function()
		local ok, why = P.can_deposit(party_of(2), 5)
		assert.is_false(ok)
		assert.equals(P.REFUSE_NONE, why)
	end)
end)

describe("pc_logic withdraw rule", function()
	it("allows a withdraw when the party has room", function()
		assert.is_true((P.can_withdraw(party_of(5), box_of(3), 2)))
	end)

	it("refuses a withdraw when the party is full", function()
		local ok, why = P.can_withdraw(party_of(6), box_of(3), 1)
		assert.is_false(ok)
		assert.equals("Your party is full.", why)
	end)

	it("refuses an empty box slot", function()
		local ok, why = P.can_withdraw(party_of(1), box_of(3), 4)
		assert.is_false(ok)
		assert.equals(P.REFUSE_NONE, why)
	end)
end)

describe("pc_logic box", function()
	it("adds to the end and keeps the input", function()
		local box = box_of(2)
		local out = P.box_add(box, entry("new"))
		assert.equals(2, #box)
		assert.equals(3, #out)
		assert.equals("new", out[3].uid)
	end)

	it("refuses to add past the cap of 240", function()
		local out, why = P.box_add(box_of(P.CAP), entry("extra"))
		assert.is_nil(out)
		assert.equals("Your PC box is full.", why)
	end)

	it("accepts the 240th entry", function()
		local out = P.box_add(box_of(P.CAP - 1), entry("last"))
		assert.equals(P.CAP, #out)
	end)

	it("removes an entry by index and returns it", function()
		local box = box_of(3)
		local out, removed = P.box_remove(box, 2)
		assert.equals("b2", removed.uid)
		assert.equals(2, #out)
		assert.equals("b1", out[1].uid)
		assert.equals("b3", out[2].uid)
		assert.equals(3, #box)
	end)

	it("returns nothing for an index out of range", function()
		local box = box_of(2)
		local out, removed = P.box_remove(box, 9)
		assert.is_nil(removed)
		assert.equals(2, #out)
	end)
end)

describe("pc_logic party helpers", function()
	it("removes one member without touching the input", function()
		local party = party_of(3)
		local out = P.party_without(party, 2)
		assert.equals(3, #party)
		assert.equals(2, #out)
		assert.equals("p1", out[1].uid)
		assert.equals("p3", out[2].uid)
	end)

	it("appends one member without touching the input", function()
		local party = party_of(2)
		local out = P.party_with(party, member("x"))
		assert.equals(2, #party)
		assert.equals(3, #out)
		assert.equals("x", out[3].uid)
	end)
end)

describe("pc_logic load and save", function()
	local function deser(t)
		if t.bad then
			error("bad entry")
		end
		return { uid = t.uid, species_id = t.species_id or 1, hp = t.hp or 1, level = t.level or 1 }
	end

	local function ser(m)
		return { uid = m.uid, species_id = m.species_id, hp = m.hp, level = m.level }
	end

	it("drops invalid entries and duplicate uids", function()
		local parsed = {
			{ uid = "a", species_id = 1 },
			{ uid = "a", species_id = 2 },
			{ bad = true, uid = "z" },
			"junk",
			{ uid = "", species_id = 3 },
			{ uid = "b", species_id = 0 },
			{ uid = "c", species_id = 4 },
		}
		local box = P.load(parsed, deser)
		assert.equals(2, #box)
		assert.equals("a", box[1].uid)
		assert.equals("c", box[2].uid)
	end)

	it("returns an empty box for bad input", function()
		assert.equals(0, #P.load(nil, deser))
		assert.equals(0, #P.load("text", deser))
	end)

	it("caps the loaded box at 240", function()
		local parsed = {}
		for i = 1, P.CAP + 10 do
			parsed[i] = { uid = "u" .. i, species_id = 1 }
		end
		assert.equals(P.CAP, #P.load(parsed, deser))
	end)

	it("saves JSON-safe entries and keeps the order", function()
		local out = P.save({ { uid = "a", species_id = 1, hp = 4, level = 2 }, { uid = "b", species_id = 2, hp = 5,
			level = 3 } }, ser)
		assert.equals(2, #out)
		assert.equals("b", out[2].uid)
		assert.equals(3, out[2].level)
	end)
end)
