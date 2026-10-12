-- minemon_party UI (T-22): the party HUD (top right), the starter chooser, the party formspec, the Party Ball item
-- and the chat commands (/party, /starter, /heal_party). Loaded as dofile(...)(S); S is the party state of init.lua.
-- Returns the UI table: refresh_hud, show_chooser, show_party, forget.
-- luacheck: read_globals core minemon vector

local MODPATH = core.get_modpath("minemon_party")
local LOGIC = dofile(MODPATH .. "/party_logic.lua")

local HUD_TYPE = core.features.hud_def_type_field and "type" or "hud_elem_type"
local CHOOSER = "minemon_party:starter"
local PARTY = "minemon_party:party"
local REOPEN_S = 3 -- a closed chooser reopens after this many seconds
local MAX_REOPENS = 5

return function(S)
	local M = {}
	local hud_ids = {} -- owner name -> { [slot] = hud id }

	local function esc(text)
		return core.formspec_escape(text)
	end

	local function hex(colour)
		return string.format("#%06X", colour)
	end

	local function species_and_max(m)
		local sp = minemon.data.get_species(m.species_id)
		if sp == nil then
			return nil, nil
		end
		return sp, minemon.instance.stats(m, sp).hp
	end

	-- The party HUD: one line per member, top right. Called from the globalstep only when S.hud_dirty is set.
	function M.refresh_hud(player)
		local name = player:get_player_name()
		local list = S.list(player)
		local rec = S.active_rec(name)
		local active_uid = rec and rec.uid or nil
		local ids = hud_ids[name] or {}
		hud_ids[name] = ids
		for i = 1, LOGIC.MAX do
			local m = list[i]
			local sp, max = nil, nil
			if m ~= nil then
				sp, max = species_and_max(m)
			end
			if sp ~= nil then
				local text = LOGIC.hud_line(m, sp.name, max, m.uid == active_uid)
				if m.dread == true then
					text = text .. " ☠" -- a Dread creature (T-30, D-031)
				end
				local colour = LOGIC.hp_colour(m.hp, max)
				if ids[i] == nil then
					ids[i] = player:hud_add({
						[HUD_TYPE] = "text",
						position = { x = 1, y = 0 },
						alignment = { x = -1, y = 1 },
						offset = { x = -10, y = 10 + (i - 1) * 18 },
						text = text,
						number = colour,
						size = { x = 1, y = 0 },
						style = 1,
						z_index = 100,
					})
				else
					player:hud_change(ids[i], "text", text)
					player:hud_change(ids[i], "number", colour)
				end
			elseif ids[i] ~= nil then
				player:hud_remove(ids[i])
				ids[i] = nil
			end
		end
	end

	function M.forget(name)
		hud_ids[name] = nil
	end

	-- The starter chooser: six buttons, each with a box in the colour of its first type.
	local function chooser_formspec()
		local fs = { "size[8,8]", "label[0.5,0.4;Choose your partner]" }
		for i, id in ipairs(LOGIC.STARTERS) do
			local sp = minemon.data.get_species(id)
			if sp ~= nil then
				local col = (i - 1) % 2
				local row = math.floor((i - 1) / 2)
				local x = 0.5 + col * 3.8
				local y = 1.0 + row * 2.2
				fs[#fs + 1] = string.format("box[%.2f,%.2f;0.35,1.5;%s]", x, y, LOGIC.type_colour(sp.types[1]))
				local label = LOGIC.display_name(sp.name) .. " - " .. LOGIC.types_text(sp.types)
				fs[#fs + 1] = string.format("button[%.2f,%.2f;3.3,1.5;pick_%d;%s]", x + 0.5, y, id, esc(label))
			end
		end
		return table.concat(fs)
	end

	function M.show_chooser(player)
		core.show_formspec(player:get_player_name(), CHOOSER, chooser_formspec())
	end

	-- The party formspec (sneak + right click with the Party Ball): name, HP bar and "Make lead" per row.
	local function party_formspec(player)
		local list = S.list(player)
		local rec = S.active_rec(player:get_player_name())
		local active_uid = rec and rec.uid or nil
		local fs = { "size[10,8.4]", "label[0.4,0.4;Your party]" }
		if #list == 0 then
			fs[#fs + 1] = "label[0.4,1.2;No creatures yet. Use /starter.]"
		end
		for i, m in ipairs(list) do
			local sp, max = species_and_max(m)
			if sp ~= nil then
				local y = 1.0 + (i - 1) * 1.1
				local frac = max > 0 and math.max(0, math.min(1, m.hp / max)) or 0
				local mark = m.uid == active_uid and "▶ " or ""
				local title = string.format("%s%s Lv%d (%s)", mark, LOGIC.member_name(m, sp.name), m.level,
					LOGIC.status_text(m.status))
				if m.dread == true then
					title = title .. " ☠" -- a Dread creature (T-30, D-031)
				end
				-- Bond hook (T-27): minemon_growth sets minemon.party.bond_text to a short string, e.g. hearts.
				local hook = minemon.party and minemon.party.bond_text
				local bond = hook and hook(m) or ""
				if bond ~= "" then
					title = title .. "  " .. bond
				end
				fs[#fs + 1] = string.format("label[0.4,%.2f;%s]", y + 0.25, esc(title))
				fs[#fs + 1] = string.format("box[3.4,%.2f;2.6,0.45;#333333]", y)
				if frac > 0 then
					fs[#fs + 1] = string.format("box[3.4,%.2f;%.2f,0.45;%s]", y, 2.6 * frac,
						hex(LOGIC.hp_colour(m.hp, max)))
				end
				fs[#fs + 1] = string.format("label[6.2,%.2f;HP %d/%d]", y + 0.25, math.max(0, m.hp), max)
				fs[#fs + 1] = string.format("button[7.8,%.2f;1.9,0.5;lead_%d;Make lead]", y - 0.02, i)
			end
		end
		return table.concat(fs)
	end

	function M.show_party(player)
		core.show_formspec(player:get_player_name(), PARTY, party_formspec(player))
	end

	-- A chooser closed without a choice reopens after REOPEN_S seconds, up to MAX_REOPENS times.
	local function reopen_later(player)
		local name = player:get_player_name()
		local st = S.starter[name] or { reopens = 0 }
		S.starter[name] = st
		if st.reopens >= MAX_REOPENS then
			return
		end
		st.reopens = st.reopens + 1
		core.after(REOPEN_S, function()
			local p = core.get_player_by_name(name)
			if p ~= nil and #S.list(p) == 0 and not S.is_dead(p) then
				M.show_chooser(p)
			end
		end)
	end

	core.register_on_player_receive_fields(function(player, formname, fields)
		if formname == CHOOSER then
			for _, id in ipairs(LOGIC.STARTERS) do
				if fields["pick_" .. id] then
					S.choose_starter(player, id)
					return true
				end
			end
			if fields.quit then
				reopen_later(player)
			end
			return true
		end
		if formname == PARTY then
			local name = player:get_player_name()
			for i = 1, LOGIC.MAX do
				if fields["lead_" .. i] then
					local list = S.list(player)
					local out, why = LOGIC.make_lead(list, i)
					if out ~= nil then
						S.cache[name] = out
						S.save(player)
						S.mark(name)
						S.say(name, S.member_display(out[1]) .. " is now your lead.")
					elseif why == "fainted" then
						S.say(name, S.member_display(list[i]) .. " has fainted and cannot lead.")
					end
					M.show_party(player)
					return true
				end
			end
			return true
		end
		return nil
	end)

	-- The Party Ball. Right click: send out the lead, or recall the active creature. Sneak + right click: the party.
	-- Left click on a creature that is not ours: order the active creature to attack it. It never damages anything
	-- itself: with on_use defined, the client sends the click to the server instead of punching (Luanti docs).
	local function ball_action(user)
		if user == nil or not user:is_player() then
			return nil
		end
		local ctrl = user:get_player_control()
		if ctrl ~= nil and ctrl.sneak then
			M.show_party(user)
		elseif S.active_rec(user:get_player_name()) ~= nil then
			S.recall(user:get_player_name(), false)
		elseif #S.list(user) == 0 then
			S.say(user:get_player_name(), "You have no creatures yet. Use /starter.")
		else
			S.send_out(user, nil)
		end
		return nil
	end

	core.register_craftitem(S.BALL, {
		description = "Party Ball",
		_doc_items_longdesc = "Sends out your lead creature, recalls it, or orders it to attack.",
		_doc_items_usagehelp = "Right click: send out or recall. Sneak and right click: your party. "
			.. "Left click a wild creature: attack.",
		inventory_image = "minemon_party_ball.png",
		stack_max = 1,
		groups = { craftitem = 1 },
		on_place = function(_itemstack, placer, _pointed)
			ball_action(placer)
			return nil
		end,
		on_secondary_use = function(_itemstack, user, _pointed)
			ball_action(user)
			return nil
		end,
		on_use = function(_itemstack, user, pointed)
			if user == nil or pointed == nil or pointed.type ~= "object" then
				return nil
			end
			S.order(user, pointed.ref)
			return nil
		end,
	})

	-- Chat commands ----------------------------------------------------------------------------------------------

	core.register_chatcommand("party", {
		description = "List your party in chat",
		func = function(name)
			local p = core.get_player_by_name(name)
			if p == nil then
				return false, "You are not online."
			end
			local list = S.list(p)
			if #list == 0 then
				return true, "Your party is empty. Use /starter."
			end
			local rec = S.active_rec(name)
			local lines = {}
			for i, m in ipairs(list) do
				local sp, max = species_and_max(m)
				local mark = (rec ~= nil and rec.uid == m.uid) and "▶ " or ""
				local display = sp and LOGIC.member_name(m, sp.name) or "?"
				local fainted = m.hp <= 0 and " (fainted)" or ""
				lines[#lines + 1] = string.format("%d. %s%s Lv%d %d/%s%s", i, mark, display, m.level, m.hp,
					tostring(max or 0), fainted)
			end
			return true, table.concat(lines, "\n")
		end,
	})

	core.register_chatcommand("starter", {
		description = "Choose your starter when your party is empty",
		func = function(name)
			local p = core.get_player_by_name(name)
			if p == nil then
				return false, "You are not online."
			end
			if #S.list(p) > 0 then
				return false, "You already have a partner."
			end
			M.show_chooser(p)
			return true, "Choose your partner."
		end,
	})

	core.register_chatcommand("heal_party", {
		description = "Heal every creature in your party (admin)",
		privs = { server = true },
		func = function(name)
			local p = core.get_player_by_name(name)
			if p == nil then
				return false, "You are not online."
			end
			S.heal_all(p)
			return true, "Your party is healed."
		end,
	})

	return M
end
