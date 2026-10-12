-- minemon_sanctuary: coins, potions, the keeper's counter and the coin drops (T-28, D-030). Glue: the rules are in
-- sanctuary_logic.lua. The item names are "minemon:<id>" (registered with a leading colon, as D-030 requires).
-- luacheck: read_globals core minemon ItemStack

local MODPATH = core.get_modpath("minemon_sanctuary")
local LOGIC = dofile(MODPATH .. "/sanctuary_logic.lua")

local COIN = "minemon:coin"
local SHOP = "minemon_sanctuary:shop"
local MAX_ROWS = 16 -- two columns of eight: the shop shows at most this many items
local COLUMN_X = { 0.3, 5.5 } -- each entry: a label (2.9 wide) and two buttons (0.95 wide each)
local ROW_Y0 = 1.2
local ROW_H = 0.9

local M = {}

-- The items.json map (the same file minemon_core reads). The shop needs every entry, so it reads the file itself.
local function read_items()
	local f = io.open(core.get_modpath("minemon_core") .. "/data/items.json", "rb")
	if not f then
		return {}
	end
	local text = f:read("*a")
	f:close()
	local parsed = core.parse_json(text, nil, true)
	return type(parsed) == "table" and parsed or {}
end

local ITEMS = read_items()

local function say(name, text)
	core.chat_send_player(name, text)
end

-- "mr_mime" -> "Mr Mime" (the same rule as minemon_party's display names).
local function pretty(raw)
	local parts = {}
	for word in tostring(raw or ""):gmatch("[^_]+") do
		parts[#parts + 1] = word:sub(1, 1):upper() .. word:sub(2)
	end
	return table.concat(parts, " ")
end

-- The name the player knows a member by: nickname or species name.
local function label_of(m)
	if m.nickname and m.nickname ~= "" then
		return m.nickname
	end
	local sp = minemon.data.get_species(m.species_id)
	return pretty(sp and sp.name or "creature")
end

-- Max HP of a member, from its species and level (its current HP when the species is unknown).
local function max_of(m)
	local sp = minemon.data.get_species(m.species_id)
	if sp == nil then
		return m.hp
	end
	return minemon.instance.stats(m, sp).hp
end

-- Coins -------------------------------------------------------------------------------------------------------------

-- The number of coins in the player's main inventory.
function M.coin_count(player)
	local n = 0
	for _, st in ipairs(player:get_inventory():get_list("main")) do
		if st:get_name() == COIN then
			n = n + st:get_count()
		end
	end
	return n
end

-- Drops the coins of one defeated wild creature at pos. rng is a minemon.rng object. Returns the amount.
function M.drop_coins(pos, level, night, rng)
	local amount = LOGIC.coin_amount(level, night, rng)
	core.add_item(pos, COIN .. " " .. amount)
	return amount
end

-- Potions -----------------------------------------------------------------------------------------------------------

-- The party uid of the active creature, or nil.
local function active_uid_of(user)
	local obj = minemon.party.get_active(user)
	local le = obj and obj:get_luaentity()
	return le and le._mm and le._mm.uid or nil
end

-- Heals the active creature, or else the first hurt member that is not fainted, then uses one potion.
local function use_potion(stack, user, id)
	if user == nil or not user:is_player() then
		return nil
	end
	local name = user:get_player_name()
	local item = minemon.data.get_item(id)
	local amount = item and item.heal or 0
	local party = minemon.party.get(user)
	local active_uid = active_uid_of(user)
	local idx = LOGIC.heal_target(party, active_uid, max_of)
	if idx == nil then
		say(name, "Nothing to heal.")
		return nil
	end
	local m = party[idx]
	local added
	if m.uid == active_uid then
		added = minemon.creatures.heal(minemon.party.get_active(user), amount)
	else
		m.hp, added = LOGIC.heal_step(m.hp, max_of(m), amount)
		minemon.party.set(user, party)
	end
	say(name, string.format("%s recovered %d HP.", label_of(m), added))
	stack:take_item(1)
	return stack
end

local POTIONS = {
	{ id = "potion", texture = "minemon_sanctuary_potion.png", desc = "Potion" },
	{ id = "super_potion", texture = "minemon_sanctuary_super_potion.png", desc = "Super Potion" },
}

for _, p in ipairs(POTIONS) do
	core.register_craftitem(":minemon:" .. p.id, {
		description = p.desc,
		_doc_items_longdesc = "Heals one creature of yours. Right click to use.",
		inventory_image = p.texture,
		stack_max = 99,
		groups = { craftitem = 1 },
		on_place = function(stack, user)
			return use_potion(stack, user, p.id)
		end,
		on_secondary_use = function(stack, user)
			return use_potion(stack, user, p.id)
		end,
	})
end

core.register_craftitem(":minemon:coin", {
	description = "₽ Coin",
	_doc_items_longdesc = "Dropped by wild creatures. Spend them at a Sanctuary counter.",
	inventory_image = "minemon_sanctuary_coin.png",
	stack_max = 999,
	groups = { craftitem = 1 },
})

-- Shop --------------------------------------------------------------------------------------------------------------

local function is_registered(id)
	return core.registered_items["minemon:" .. id] ~= nil
end

local function esc(text)
	return core.formspec_escape(text)
end

-- The rows on sale right now (only priced and registered items).
function M.rows()
	return LOGIC.shop_rows(ITEMS, is_registered)
end

local function shop_formspec(player)
	local rows = M.rows()
	local fs = {
		"size[10.6,10]",
		"label[0.4,0.4;The Keeper's Counter]",
		string.format("label[6.0,0.4;%s]", esc("₽ Coins: " .. M.coin_count(player))),
	}
	for i, row in ipairs(rows) do
		if i > MAX_ROWS then
			break
		end
		local col = math.floor((i - 1) / 8) + 1
		local r = (i - 1) % 8
		local x = COLUMN_X[col]
		local y = ROW_Y0 + r * ROW_H
		local coins = row.price == 1 and "coin" or "coins"
		fs[#fs + 1] = string.format("label[%.2f,%.2f;%s]", x, y + 0.25,
			esc(string.format("%s - %d %s", row.name, row.price, coins)))
		fs[#fs + 1] = string.format("button[%.2f,%.2f;0.95,0.65;buy_%s_1;x1]", x + 2.9, y, row.id)
		fs[#fs + 1] = string.format("button[%.2f,%.2f;0.95,0.65;buy_%s_5;x5]", x + 3.9, y, row.id)
	end
	if #rows == 0 then
		fs[#fs + 1] = "label[0.4,1.4;Nothing for sale yet.]"
	end
	return table.concat(fs)
end

function M.open_shop(player)
	core.show_formspec(player:get_player_name(), SHOP, shop_formspec(player))
end

-- Buys qty of the item with this id. Coins are taken from the inventory; the item must fit.
local function buy(player, id, qty)
	local name = player:get_player_name()
	local row = nil
	for _, r in ipairs(M.rows()) do
		if r.id == id then
			row = r
		end
	end
	if row == nil then
		say(name, "The keeper does not sell that.")
		return false
	end
	local total = LOGIC.total_price(row.price, qty)
	local coins = M.coin_count(player)
	if coins < total then
		say(name, string.format("You need %d coins for %s x%d. You have %d.", total, row.name, qty, coins))
		return false
	end
	local inv = player:get_inventory()
	local stack = ItemStack("minemon:" .. id .. " " .. qty)
	if not inv:room_for_item("main", stack) then
		say(name, "Your bag is full.")
		return false
	end
	inv:remove_item("main", ItemStack(COIN .. " " .. total))
	inv:add_item("main", stack)
	say(name, string.format("Bought %s x%d for %d coins.", row.name, qty, total))
	return true
end

-- Handles the shop formspec's fields. Returns true when the formspec was handled.
function M.on_fields(player, formname, fields)
	if formname ~= SHOP then
		return false
	end
	for field in pairs(fields) do
		local id, qty = field:match("^buy_(.*)_(%d+)$")
		if id ~= nil then
			buy(player, id, tonumber(qty))
			M.open_shop(player)
			return true
		end
	end
	return true
end

M.FORM = SHOP

return M
