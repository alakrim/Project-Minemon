-- Pure rules for minemon_sanctuary (T-28, D-030). No `core` access, so busted can test them (docs/CONVENTIONS.md).
-- init.lua, structure.lua, shop.lua and pc.lua are the Luanti glue. pc_logic.lua holds the PC rules.
--
-- A sanctuary is a lantern shrine. Its centre is the altar position. Inside its ward no wild creature spawns (within
-- SPAWN_BLOCK nodes) and no wild creature attacks: a target inside a ward is dropped (wild_brain.lua guards).

local M = {}

M.WARD_H = 16 -- ward radius, horizontal nodes
M.WARD_V = 8 -- ward radius, vertical nodes
M.SPAWN_BLOCK = 24 -- no wild spawn within this distance (3D) of a sanctuary centre
M.SPAWN_OFFSET = 8 -- the spawn sanctuary stands this far from the world spawn point
M.KIT_POTIONS = 3 -- the starter supplies
M.KIT_COINS = 10
M.COIN_BASE_DIV = 3 -- coins: ceil(level / 3) + rng(0..2), doubled at night
M.COIN_BONUS_MAX = 2
M.COIN_NIGHT_MULT = 2
M.COIN_PER_PRICE = 100 -- shop: coin price = items.json price / 100, rounded up, at least 1
M.MAX_CENTRES = 64 -- sanctuary centres kept in mod storage

M.HINT = "Follow the lanterns. Sanctuaries keep the night away."
M.RESTORED = "Your party is restored. The lanterns will remember you."

local function sq(n)
	return n * n
end

-- The horizontal distance and the vertical distance between a centre and a position (ward geometry).
function M.ward_offsets(centre, pos)
	local dx = pos.x - centre.x
	local dz = pos.z - centre.z
	return math.sqrt(dx * dx + dz * dz), math.abs(pos.y - centre.y)
end

-- True when pos is inside the ward of one centre: 16 nodes horizontal, 8 vertical.
function M.in_ward(centre, pos)
	local h, v = M.ward_offsets(centre, pos)
	return h <= M.WARD_H and v <= M.WARD_V
end

-- True when a wild spawn at pos is refused by one centre: within 24 nodes in 3D.
function M.blocks_spawn(centre, pos)
	local dx = pos.x - centre.x
	local dy = pos.y - centre.y
	local dz = pos.z - centre.z
	return sq(dx) + sq(dy) + sq(dz) <= sq(M.SPAWN_BLOCK)
end

-- The first centre whose ward holds pos, or nil. centres is an array of { x, y, z }.
function M.warded_by(centres, pos)
	for _, c in ipairs(centres or {}) do
		if M.in_ward(c, pos) then
			return c
		end
	end
	return nil
end

-- True when any centre refuses a wild spawn at pos.
function M.spawn_refused(centres, pos)
	for _, c in ipairs(centres or {}) do
		if M.blocks_spawn(c, pos) then
			return true
		end
	end
	return false
end

-- Centres: a list stored in mod storage. A position within 1 node of an existing centre is not added again.
-- Returns the new list and whether a centre was added.
function M.add_centre(list, pos)
	local out = {}
	for i, c in ipairs(list or {}) do
		out[i] = { x = c.x, y = c.y, z = c.z }
	end
	for _, c in ipairs(out) do
		if math.abs(c.x - pos.x) <= 1 and math.abs(c.y - pos.y) <= 1 and math.abs(c.z - pos.z) <= 1 then
			return out, false
		end
	end
	if #out >= M.MAX_CENTRES then
		return out, false
	end
	out[#out + 1] = { x = pos.x, y = pos.y, z = pos.z }
	return out, true
end

-- Rebuilds the centre list from its stored (JSON) form, dropping anything that is not a position.
function M.load_centres(parsed)
	local out = {}
	if type(parsed) ~= "table" then
		return out
	end
	for _, c in ipairs(parsed) do
		if type(c) == "table" and type(c.x) == "number" and type(c.y) == "number" and type(c.z) == "number" then
			out[#out + 1] = { x = c.x, y = c.y, z = c.z }
		end
	end
	return out
end

-- Coins dropped by one defeated wild creature: ceil(level / 3) plus rng(0..2), doubled at night.
-- rng is a minemon.rng object (:int(a, b) is inclusive).
function M.coin_amount(level, night, rng)
	local base = math.ceil(math.max(1, level) / M.COIN_BASE_DIV) + rng:int(0, M.COIN_BONUS_MAX)
	if night then
		return base * M.COIN_NIGHT_MULT
	end
	return base
end

-- Shop price in coins for an items.json price. Free items (price 0) have no shop price: nil.
function M.coin_price(item_price)
	if type(item_price) ~= "number" or item_price <= 0 then
		return nil
	end
	return math.max(1, math.ceil(item_price / M.COIN_PER_PRICE))
end

-- The shop rows: every items.json entry with a price above 0 that is registered (is_registered(id) is true).
-- Sorted by coin price, then id, so the list is the same on every open. items is the items.json map.
function M.shop_rows(items, is_registered)
	local rows = {}
	for id, item in pairs(items or {}) do
		local price = M.coin_price(item.price)
		if price ~= nil and is_registered(id) then
			rows[#rows + 1] = { id = id, name = item.name or id, price = price }
		end
	end
	table.sort(rows, function(a, b)
		if a.price ~= b.price then
			return a.price < b.price
		end
		return a.id < b.id
	end)
	return rows
end

-- The party member a potion heals: the active creature when it is hurt, else the first hurt member that is not
-- fainted. Returns its index or nil. max_of(member) gives its max HP.
function M.heal_target(list, active_uid, max_of)
	local function hurt(m)
		return m.hp > 0 and m.hp < max_of(m)
	end
	if active_uid ~= nil then
		for i, m in ipairs(list) do
			if m.uid == active_uid and hurt(m) then
				return i
			end
		end
	end
	for i, m in ipairs(list) do
		if hurt(m) then
			return i
		end
	end
	return nil
end

-- HP after a potion, and the HP actually restored. A fainted creature is not healed by a potion (HP 0 stays 0).
function M.heal_step(hp, max, amount)
	if hp <= 0 or amount <= 0 then
		return hp, 0
	end
	local new_hp = math.min(max, hp + amount)
	return new_hp, new_hp - hp
end

-- Coins for buying qty of one item at its unit price.
function M.total_price(unit, qty)
	return unit * qty
end

-- The starter kit is given once, when the party is not empty.
function M.kit_due(kit_given, party_size)
	return kit_given ~= true and party_size > 0
end

-- Points on a ring of the given radius around (cx, cz): count points at equal angles, starting at angle 0.
function M.ring_points(cx, cz, radius, count)
	local out = {}
	for i = 0, count - 1 do
		local a = (2 * math.pi * i) / count
		out[#out + 1] = {
			x = cx + math.floor(radius * math.cos(a) + 0.5),
			z = cz + math.floor(radius * math.sin(a) + 0.5),
		}
	end
	return out
end

return M
