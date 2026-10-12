-- Unit tests for mods/minemon/minemon_sanctuary/sanctuary_logic.lua (pure logic, no Luanti).
-- Covers: ward geometry (16 horizontal, 8 vertical), the spawn block (24 nodes, 3D), centre storage, coin amount
-- bands (day and night), shop price conversion and rows, the potion target and heal, the starter kit rule and the
-- spawn ring.
-- luacheck: globals describe it assert

local here = debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$") or "."
local S = dofile(here .. "/../../mods/minemon/minemon_sanctuary/sanctuary_logic.lua")

local C = { x = 100, y = 20, z = -50 }

-- A fake minemon.rng: int(a, b) returns a fixed value clamped to the range, so the bands are exact.
local function fixed_rng(value)
	return {
		int = function(_, a, b)
			assert(a <= b, "rng:int needs a <= b")
			return math.max(a, math.min(b, value))
		end,
	}
end

local function at(dx, dy, dz)
	return { x = C.x + dx, y = C.y + dy, z = C.z + dz }
end

describe("sanctuary_logic constants", function()
	it("matches the D-030 numbers", function()
		assert.equals(16, S.WARD_H)
		assert.equals(8, S.WARD_V)
		assert.equals(24, S.SPAWN_BLOCK)
		assert.equals(3, S.KIT_POTIONS)
		assert.equals(10, S.KIT_COINS)
		assert.equals(100, S.COIN_PER_PRICE)
	end)
end)

describe("sanctuary_logic ward geometry", function()
	it("is safe at the centre and inside 16 nodes horizontally", function()
		assert.is_true(S.in_ward(C, at(0, 0, 0)))
		assert.is_true(S.in_ward(C, at(16, 0, 0)))
		assert.is_true(S.in_ward(C, at(10, 0, 12))) -- 10^2 + 12^2 = 244 < 256
	end)

	it("is not safe just outside 16 nodes horizontally", function()
		assert.is_false(S.in_ward(C, at(17, 0, 0)))
		assert.is_false(S.in_ward(C, at(12, 0, 13))) -- 144 + 169 = 313 > 256
	end)

	it("allows 8 nodes vertically and refuses 9", function()
		assert.is_true(S.in_ward(C, at(0, 8, 0)))
		assert.is_true(S.in_ward(C, at(0, -8, 0)))
		assert.is_false(S.in_ward(C, at(0, 9, 0)))
		assert.is_false(S.in_ward(C, at(0, -9, 0)))
	end)

	it("returns the first centre whose ward holds the position", function()
		local far = { x = 500, y = 20, z = 500 }
		local centres = { far, C }
		assert.equals(C, S.warded_by(centres, at(3, 0, 3)))
		assert.is_nil(S.warded_by(centres, at(40, 0, 0)))
		assert.is_nil(S.warded_by({}, at(0, 0, 0)))
		assert.is_nil(S.warded_by(nil, at(0, 0, 0)))
	end)
end)

describe("sanctuary_logic spawn block", function()
	it("refuses a wild spawn within 24 nodes in 3D", function()
		assert.is_true(S.blocks_spawn(C, at(24, 0, 0)))
		assert.is_true(S.blocks_spawn(C, at(0, 10, 20))) -- 100 + 400 = 500 <= 576
		assert.is_true(S.blocks_spawn(C, at(15, 0, 18))) -- 225 + 324 = 549 <= 576
	end)

	it("allows a spawn just beyond 24 nodes", function()
		assert.is_false(S.blocks_spawn(C, at(25, 0, 0)))
		assert.is_false(S.blocks_spawn(C, at(17, 0, 18))) -- 289 + 324 = 613 > 576
		assert.is_false(S.blocks_spawn(C, at(0, 0, 25)))
	end)

	it("uses the full 3D distance, so height counts", function()
		assert.is_true(S.blocks_spawn(C, at(0, 20, 0)))
		assert.is_false(S.blocks_spawn(C, at(0, 25, 0)))
	end)

	it("is refused when any centre blocks the spawn", function()
		local far = { x = 900, y = 20, z = 900 }
		assert.is_true(S.spawn_refused({ far, C }, at(5, 0, 5)))
		assert.is_false(S.spawn_refused({ far }, at(5, 0, 5)))
		assert.is_false(S.spawn_refused({}, at(0, 0, 0)))
	end)
end)

describe("sanctuary_logic centre storage", function()
	it("adds a centre once and reports it", function()
		local list, added = S.add_centre({}, C)
		assert.is_true(added)
		assert.equals(1, #list)
		local again, added2 = S.add_centre(list, { x = C.x + 1, y = C.y, z = C.z })
		assert.is_false(added2)
		assert.equals(1, #again)
	end)

	it("keeps the list copy separate from the input", function()
		local src = { { x = 1, y = 2, z = 3 } }
		local out = S.add_centre(src, at(50, 0, 50))
		assert.equals(1, #src)
		assert.equals(2, #out)
	end)

	it("caps the list at MAX_CENTRES", function()
		local list = {}
		for i = 1, S.MAX_CENTRES do
			list[i] = { x = i * 100, y = 0, z = 0 }
		end
		local out, added = S.add_centre(list, at(0, 0, 0))
		assert.is_false(added)
		assert.equals(S.MAX_CENTRES, #out)
	end)

	it("loads only valid positions from stored JSON", function()
		local out = S.load_centres({ { x = 1, y = 2, z = 3 }, { x = "a", y = 0, z = 0 }, "junk", { x = 4, y = 5, z = 6 } })
		assert.equals(2, #out)
		assert.equals(4, out[2].x)
		assert.are.same({}, S.load_centres(nil))
	end)
end)

describe("sanctuary_logic coin amount", function()
	it("is ceil(level / 3) plus 0..2 by day", function()
		assert.equals(1, S.coin_amount(1, false, fixed_rng(0)))
		assert.equals(1 + 2, S.coin_amount(1, false, fixed_rng(2)))
		assert.equals(2 + 1, S.coin_amount(4, false, fixed_rng(1))) -- ceil(4/3) = 2
		assert.equals(7 + 0, S.coin_amount(20, false, fixed_rng(0))) -- ceil(20/3) = 7
	end)

	it("doubles at night", function()
		assert.equals(2 * (1 + 2), S.coin_amount(1, true, fixed_rng(2)))
		assert.equals(2 * 7, S.coin_amount(20, true, fixed_rng(0)))
	end)

	it("stays inside the bands for every level and draw", function()
		for level = 1, 70 do
			local low = S.coin_amount(level, false, fixed_rng(0))
			local high = S.coin_amount(level, false, fixed_rng(2))
			assert.is_true(low >= math.ceil(level / 3))
			assert.is_true(high <= math.ceil(level / 3) + 2)
			assert.equals(2 * low, S.coin_amount(level, true, fixed_rng(0)))
		end
	end)
end)

describe("sanctuary_logic shop prices", function()
	it("converts items.json prices to coins, rounded up, at least 1", function()
		assert.equals(2, S.coin_price(200))
		assert.equals(7, S.coin_price(700))
		assert.equals(6, S.coin_price(600))
		assert.equals(30, S.coin_price(3000))
		assert.equals(1, S.coin_price(50))
		assert.equals(2, S.coin_price(101))
	end)

	it("has no price for free or invalid items", function()
		assert.is_nil(S.coin_price(0))
		assert.is_nil(S.coin_price(nil))
		assert.is_nil(S.coin_price(-5))
	end)

	it("lists only priced and registered items, sorted by price then id", function()
		local items = {
			potion = { name = "Potion", price = 200 },
			master_ball = { name = "Master Ball", price = 0 },
			super_potion = { name = "Super Potion", price = 700 },
			poke_ball = { name = "Poké Ball", price = 200 },
			unknown = { name = "Unknown", price = 900 },
		}
		local registered = { potion = true, super_potion = true, poke_ball = true, master_ball = true }
		local rows = S.shop_rows(items, function(id) return registered[id] == true end)
		assert.equals(3, #rows)
		assert.equals("poke_ball", rows[1].id)
		assert.equals("potion", rows[2].id)
		assert.equals("super_potion", rows[3].id)
		assert.equals(7, rows[3].price)
		assert.equals("Poké Ball", rows[1].name)
	end)
end)

describe("sanctuary_logic potions", function()
	local function max_of(m)
		return m.max
	end

	it("targets the active creature when it is hurt", function()
		local list = { { uid = "a", hp = 5, max = 20 }, { uid = "b", hp = 3, max = 9 } }
		assert.equals(2, S.heal_target(list, "b", max_of))
	end)

	it("falls back to the first hurt member that is not fainted", function()
		local list = { { uid = "a", hp = 0, max = 20 }, { uid = "b", hp = 20, max = 20 }, { uid = "c", hp = 4, max = 9 } }
		assert.equals(3, S.heal_target(list, nil, max_of))
		assert.equals(3, S.heal_target(list, "b", max_of))
	end)

	it("has no target when nobody is hurt and alive", function()
		local list = { { uid = "a", hp = 0, max = 20 }, { uid = "b", hp = 20, max = 20 } }
		assert.is_nil(S.heal_target(list, nil, max_of))
		assert.is_nil(S.heal_target({}, nil, max_of))
	end)

	it("heals up to max and reports the amount added", function()
		local hp, added = S.heal_step(5, 20, 20)
		assert.equals(20, hp)
		assert.equals(15, added)
		hp, added = S.heal_step(18, 20, 50)
		assert.equals(20, hp)
		assert.equals(2, added)
	end)

	it("never heals a fainted creature", function()
		local hp, added = S.heal_step(0, 20, 20)
		assert.equals(0, hp)
		assert.equals(0, added)
	end)
end)

describe("sanctuary_logic total price", function()
	it("multiplies the unit price by the quantity", function()
		assert.equals(2, S.total_price(2, 1))
		assert.equals(35, S.total_price(7, 5))
	end)
end)

describe("sanctuary_logic starter kit and spawn ring", function()
	it("is due once, when the party is not empty", function()
		assert.is_true(S.kit_due(nil, 1))
		assert.is_false(S.kit_due(nil, 0))
		assert.is_false(S.kit_due(true, 3))
	end)

	it("puts count points on a ring of the radius", function()
		local pts = S.ring_points(0, 0, 8, 4)
		assert.equals(4, #pts)
		assert.are.same({ x = 8, z = 0 }, pts[1])
		assert.are.same({ x = 0, z = 8 }, pts[2])
		assert.are.same({ x = -8, z = 0 }, pts[3])
	end)
end)
