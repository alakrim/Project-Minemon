-- minemon_party command bar (T-29, D-031): the 4-move HUD bar while a creature is out, the Z key and sneak + left
-- click on air that cycle the selected move, and the Party Ball order that queues the selected move for the owned
-- brain. Loaded as dofile(...)(S) from init.lua, after ui.lua. The Party Ball's on_use is replaced here
-- (core.override_item) so ui.lua stays untouched: a creature click orders as S.order does, plus the queue; air clicks
-- cycle or self-cast.
-- The pure rules are in command_logic.lua. Returns the command table: draw, cycle, self_cast, order, selected, queued.
-- luacheck: read_globals core minemon vector

local MODPATH = core.get_modpath("minemon_party")
local LOGIC = dofile(MODPATH .. "/party_logic.lua")
local CMD = dofile(MODPATH .. "/command_logic.lua")

local HUD_TYPE = core.features.hud_def_type_field and "type" or "hud_elem_type"
local UPDATE_S = 0.25 -- the bar is redrawn at most this often; a change of the selection redraws at once
local FLASH_S = 1.2 -- the cycle flash (the move name above the bar) stays this long

-- Layout, in pixels. The bar sits bottom centre, above the VoxeLibre health and hunger bars. Each element's
-- bottom edge is BOTTOM (plus its own offset) above the bottom of the screen.
local BOTTOM = 130
local SLOT_W, SLOT_H, GAP = 104, 34, 4
local EDGE = 2 -- the selection frame is this wide
local CHIP_W = 5 -- the type colour chip on the left of a slot
local BAR_W = CMD.SLOTS * SLOT_W + (CMD.SLOTS - 1) * GAP

local WHITE = 0xFFFFFF
local GREY = 0xA8A8A8
local EMPTY_PP = 0xFF5050
local FILL_OFF = "[fill:1x1:#00000000"
local FILL_ON = "[fill:1x1:#FFFFFFFF"
local FILL_DIM = "[fill:1x1:#000000A0"
local FILL_BG = "[fill:1x1:#2A3440E6" -- a light slate: a cooling slot is darkened over it (FILL_DIM)

local function fill(hex)
	return "[fill:1x1:" .. hex .. "FF"
end

-- Left edge of slot i, in pixels from the centre of the screen.
local function slot_left(i)
	return -BAR_W / 2 + (i - 1) * (SLOT_W + GAP)
end

return function(S)
	local M = {}
	local selected = {} -- owner name -> selected slot (1..SLOTS); resets to 1 on send-out
	local bars = {} -- owner name -> { ids = { [slot] = { key = hud id } }, last = { [slot] = { key = value } } }
	local flash = {} -- owner name -> hud id of the cycle flash
	local prev_zoom = {} -- owner name -> the Z key state of the last globalstep

	local function forget(name)
		bars[name] = nil
		selected[name] = nil
		flash[name] = nil
		prev_zoom[name] = nil
	end

	-- A 1x1 image element placed on the bar. The element extends right and up from its anchor.
	local function add_image(player, x, bottom, w, h, tex, z)
		return player:hud_add({
			[HUD_TYPE] = "image",
			position = { x = 0.5, y = 1 },
			alignment = { x = 1, y = -1 },
			offset = { x = x, y = -bottom },
			text = tex,
			scale = { x = w, y = h },
			z_index = z,
		})
	end

	local function add_text(player, x, bottom, str, colour, size, z)
		return player:hud_add({
			[HUD_TYPE] = "text",
			position = { x = 0.5, y = 1 },
			alignment = { x = 1, y = -1 },
			offset = { x = x, y = -bottom },
			text = str,
			number = colour,
			size = { x = size, y = 0 }, -- y is unused for text; the engine wants a full vector (ui.lua does the same)
			style = 1,
			z_index = z,
		})
	end

	-- The HUD elements of one slot. Their content is set by apply(), which changes only what differs.
	local function create_slot(player, i)
		local lx = slot_left(i)
		return {
			frame = add_image(player, lx, BOTTOM, SLOT_W, SLOT_H, FILL_OFF, 100),
			bg = add_image(player, lx + EDGE, BOTTOM + EDGE, SLOT_W - 2 * EDGE, SLOT_H - 2 * EDGE, FILL_BG, 101),
			chip = add_image(player, lx + EDGE, BOTTOM + EDGE, CHIP_W, SLOT_H - 2 * EDGE, FILL_OFF, 102),
			dim = add_image(player, lx + EDGE, BOTTOM + EDGE, SLOT_W - 2 * EDGE, SLOT_H - 2 * EDGE, FILL_OFF, 103),
			name = add_text(player, lx + EDGE + CHIP_W + 6, BOTTOM + SLOT_H / 2, "", WHITE, 0.8, 104),
			pp = add_text(player, lx + EDGE + CHIP_W + 6, BOTTOM + 4, "", GREY, 0.7, 104),
		}
	end

	-- Which HUD element and which property each state key drives.
	local OPS = {
		frame = { "frame", "text" },
		dim = { "dim", "text" },
		chip = { "chip", "text" },
		name = { "name", "text" },
		namecol = { "name", "number" },
		pp = { "pp", "text" },
		ppcol = { "pp", "number" },
	}

	local function apply(player, bar, i, want)
		local ids = bar.ids[i]
		local last = bar.last[i] or {}
		bar.last[i] = last
		for key, value in pairs(want) do
			if last[key] ~= value then
				local op = OPS[key]
				player:hud_change(ids[op[1]], op[2], value)
				last[key] = value
			end
		end
	end

	-- The state of each slot for the moveset m of the active creature, and the selected slot.
	local function wanted(rec, m, sel)
		local pps = CMD.slot_pps(m.moves)
		local out = {}
		for i = 1, CMD.SLOTS do
			local s = m.moves and m.moves[i]
			local move = s and s.id and minemon.data.get_move(s.id)
			if move == nil then
				out[i] = { frame = FILL_OFF, dim = FILL_OFF, chip = FILL_OFF, name = "", namecol = WHITE, pp = "",
					ppcol = GREY }
			else
				local pp = pps[i] or 0
				local cooling = minemon.combat.on_cooldown(rec.obj, s.id)
				out[i] = {
					frame = (i == sel) and FILL_ON or FILL_OFF,
					dim = cooling and FILL_DIM or FILL_OFF,
					chip = fill(LOGIC.type_colour(move.type)),
					name = CMD.short_name(move.name),
					namecol = (pp > 0 and not cooling) and WHITE or GREY,
					pp = CMD.pp_text(pp, move.pp),
					ppcol = pp > 0 and WHITE or EMPTY_PP,
				}
			end
		end
		return out
	end

	-- The active creature of a player: its record and its member, or nil.
	local function active(name)
		local rec = S.active_rec(name)
		if rec == nil then
			return nil, nil
		end
		local m = rec.obj:get_luaentity()._mm
		if m == nil then
			return nil, nil
		end
		return rec, m
	end

	-- The selected slot, kept on a move with PP when it can be. Returns the slot or nil (no move has PP).
	local function selection(name, m)
		local pps = CMD.slot_pps(m.moves)
		local sel = CMD.keep_selection(pps, selected[name] or 1)
		if sel ~= nil then
			selected[name] = sel
		end
		return sel
	end

	local function hide(player, name)
		local bar = bars[name]
		if bar == nil then
			return
		end
		for i = 1, CMD.SLOTS do
			local ids = bar.ids[i]
			if ids then
				for _, id in pairs(ids) do
					player:hud_remove(id)
				end
			end
		end
		bars[name] = nil
	end

	-- Draws the bar of a player: shown while a creature is out, removed otherwise.
	local function draw(player)
		local name = player:get_player_name()
		local rec, m = active(name)
		if rec == nil then
			hide(player, name)
			return
		end
		local bar = bars[name]
		if bar == nil then
			bar = { ids = {}, last = {} }
			for i = 1, CMD.SLOTS do
				bar.ids[i] = create_slot(player, i)
			end
			bars[name] = bar
		end
		local sel = selection(name, m)
		local states = wanted(rec, m, sel or 0)
		for i = 1, CMD.SLOTS do
			apply(player, bar, i, states[i])
		end
	end

	-- The short line above the bar, removed after FLASH_S.
	local function show_flash(player, text)
		local name = player:get_player_name()
		if flash[name] ~= nil then
			player:hud_remove(flash[name])
		end
		local id = player:hud_add({
			[HUD_TYPE] = "text",
			position = { x = 0.5, y = 1 },
			alignment = { x = 0, y = -1 },
			offset = { x = 0, y = -(BOTTOM + SLOT_H + 14) },
			text = text,
			number = WHITE,
			size = { x = 1.1, y = 0 },
			style = 1,
			z_index = 120,
		})
		flash[name] = id
		core.after(FLASH_S, function()
			local p = core.get_player_by_name(name)
			if p ~= nil and flash[name] == id then
				p:hud_remove(id)
				flash[name] = nil
			end
		end)
	end

	-- Selects the next move with PP above 0 (Z, or sneak + left click on air). Returns true when a move was selected.
	function M.cycle(player)
		local name = player:get_player_name()
		local rec, m = active(name)
		if rec == nil then
			return false
		end
		local pps = CMD.slot_pps(m.moves)
		local nxt = CMD.next_selectable(pps, selected[name] or 1)
		if nxt == nil then
			show_flash(player, "No PP left")
			return false
		end
		selected[name] = nxt
		local move = minemon.data.get_move(m.moves[nxt].id)
		show_flash(player, move and move.name or "")
		draw(player)
		return true
	end

	-- The selected move's slot and move data, or nil and a reason when there is nothing to use.
	local function chosen(name, m)
		local sel = selection(name, m)
		local slot = m.moves and m.moves[sel or selected[name] or 1]
		local move = slot and slot.id and minemon.data.get_move(slot.id)
		return slot, move
	end

	-- Left click on a creature with the Party Ball: orders the target (S.order) and queues the selected move for the
	-- owned brain. With no PP left on that move, the target is still ordered and nothing is queued.
	function M.order(player, target)
		local name = player:get_player_name()
		local rec, m = active(name)
		if rec == nil then
			return false
		end
		rec.queue = nil
		local slot, move = chosen(name, m)
		if slot == nil or move == nil then
			return S.order(player, target)
		end
		if (slot.pp or 0) <= 0 then
			local ok = S.order(player, target)
			S.say(name, "No PP left for " .. move.name .. "!")
			return ok
		end
		local ok = S.order(player, target, move.name)
		if ok then
			rec.queue = CMD.new_queue(slot.id, core.get_gametime())
			draw(player)
		end
		return ok
	end

	-- Left click on air with the Party Ball (no sneak): a self-target move is cast at once, without a target.
	function M.self_cast(player)
		local name = player:get_player_name()
		local rec, m = active(name)
		if rec == nil then
			return false
		end
		local slot, move = chosen(name, m)
		if slot == nil or move == nil then
			return false
		end
		if not CMD.is_self_target(move) then
			S.say(name, move.name .. " needs a target. Left click a creature.")
			return false
		end
		if (slot.pp or 0) <= 0 then
			S.say(name, "No PP left for " .. move.name .. "!")
			return false
		end
		local ok, why = minemon.combat.use_move(rec.obj, nil, slot.id)
		if not ok then
			S.say(name, move.name .. " cannot be used now (" .. tostring(why) .. ").")
			return false
		end
		draw(player)
		return true
	end

	-- The selected slot of a player (1..SLOTS), or nil when the player has no active creature.
	function M.selected(player)
		local name = player:get_player_name()
		local rec, m = active(name)
		if rec == nil then
			return nil
		end
		return selection(name, m) or selected[name] or 1
	end

	-- The queued order of a player's active creature (command_logic queue: { move, expires }), or nil.
	function M.queued(player)
		local rec = S.active_rec(player:get_player_name())
		return rec and rec.queue or nil
	end

	M.draw = draw

	-- The Party Ball's left click. Replaces the ui.lua on_use (the same object click, as S.order does, plus the queue).
	core.override_item(S.BALL, {
		on_use = function(_itemstack, user, pointed)
			if user == nil or pointed == nil or not user:is_player() then
				return nil
			end
			if pointed.type == "object" then
				M.order(user, pointed.ref)
			elseif pointed.type == "nothing" then
				local ctrl = user:get_player_control()
				if ctrl and ctrl.sneak then
					M.cycle(user)
				else
					M.self_cast(user)
				end
			end
			return nil
		end,
	})

	minemon.events.register("creature_sent_out", function(player)
		selected[player:get_player_name()] = 1
	end)
	minemon.events.register("creature_recalled", function(player)
		if player ~= nil and player:is_valid() then
			draw(player)
		end
	end)

	local acc = 0
	core.register_globalstep(function(dtime)
		acc = acc + dtime
		local due = acc >= UPDATE_S
		if due then
			acc = 0
		end
		for _, player in ipairs(core.get_connected_players()) do
			local name = player:get_player_name()
			local ctrl = player:get_player_control()
			local zoom = ctrl ~= nil and ctrl.zoom == true
			if zoom and not prev_zoom[name] then
				M.cycle(player)
			end
			prev_zoom[name] = zoom
			if due then
				draw(player)
			end
		end
	end)

	core.register_on_leaveplayer(function(player)
		forget(player:get_player_name())
	end)

	return M
end
