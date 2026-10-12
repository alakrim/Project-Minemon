-- minemon_sanctuary: the PC box (T-28, D-030). The rules are in pc_logic.lua; this file is the glue.
-- Storage: player meta "minemon:pc:list" (JSON of serialized instances, cap 240). The party is minemon.party.
-- API (used by minemon.pc.* from other mods, T-26 included):
--   deposit(player, inst) -> bool, reason   inst in the party: it goes to the box (not when it is the last healthy
--                                           member). inst not in the party (a capture with a full party): it is boxed.
--   withdraw(player, index) -> bool, reason takes a box entry into the party (not when the party is full)
--   list(player) -> array of instances in the box
-- luacheck: read_globals core minemon

local MODPATH = core.get_modpath("minemon_sanctuary")
local PCL = dofile(MODPATH .. "/pc_logic.lua")

local KEY = "minemon:pc:list"
local FORM = "minemon_sanctuary:pc"

local M = {}
local ui = {} -- player name -> { page, side, index, note }; per session, not saved

local function state(name)
	local st = ui[name]
	if st == nil then
		st = { page = 1 }
		ui[name] = st
	end
	return st
end

-- Storage -------------------------------------------------------------------------------------------------------------

function M.list(player)
	local raw = player:get_meta():get_string(KEY)
	local parsed = nil
	if raw ~= "" then
		local ok, value = pcall(core.parse_json, raw)
		if ok then
			parsed = value
		end
	end
	return PCL.load(parsed, minemon.instance.deserialize)
end

local function write(player, box)
	player:get_meta():set_string(KEY, core.write_json(PCL.save(box, minemon.instance.serialize)))
end

-- The API ------------------------------------------------------------------------------------------------------------

function M.deposit(player, inst)
	if player == nil or inst == nil then
		return false, PCL.REFUSE_NONE
	end
	local party = minemon.party.get(player)
	local idx = PCL.index_of_uid(party, inst.uid)
	if idx == nil then
		-- Not in the party: a capture that found the party full. It goes straight to the box.
		local box, why = PCL.box_add(M.list(player), inst)
		if box == nil then
			return false, why
		end
		write(player, box)
		return true
	end
	local ok, why = PCL.can_deposit(party, idx)
	if not ok then
		return false, why
	end
	local box, full = PCL.box_add(M.list(player), party[idx])
	if box == nil then
		return false, full
	end
	-- The box is written first: if the server stops here, the creature is in the box and maybe in the party, not lost.
	write(player, box)
	minemon.party.set(player, PCL.party_without(party, idx))
	return true
end

function M.withdraw(player, index)
	if player == nil then
		return false, PCL.REFUSE_NONE
	end
	local box = M.list(player)
	local party = minemon.party.get(player)
	local ok, why = PCL.can_withdraw(party, box, index)
	if not ok then
		return false, why
	end
	local rest, member = PCL.box_remove(box, index)
	member.faint_s = 0
	write(player, rest)
	minemon.party.set(player, PCL.party_with(party, member))
	return true
end

-- The formspec -------------------------------------------------------------------------------------------------------

local function esc(text)
	return core.formspec_escape(text)
end

-- The label used in notes: nickname or species name.
local function label_of(entry)
	if entry.nickname and entry.nickname ~= "" then
		return entry.nickname
	end
	local sp = minemon.data.get_species(entry.species_id)
	return sp and sp.name or "Your creature"
end

local function short_name(entry)
	if entry.nickname and entry.nickname ~= "" then
		return entry.nickname:sub(1, 9)
	end
	local sp = minemon.data.get_species(entry.species_id)
	local name = sp and sp.name or "?"
	return name:sub(1, 1):upper() .. name:sub(2, 9)
end

local function cell_text(entry, selected)
	local mark = selected and "> " or ""
	return string.format("%s%s L%d", mark, short_name(entry), entry.level)
end

local function party_cell(member, selected)
	if member == nil then
		return "-"
	end
	local sp = minemon.data.get_species(member.species_id)
	local max = sp and minemon.instance.stats(member, sp).hp or member.hp
	local mark = selected and "> " or ""
	return string.format("%s%s L%d %d/%d", mark, short_name(member), member.level, math.max(0, member.hp), max)
end

local function formspec(player)
	local name = player:get_player_name()
	local st = state(name)
	local party = minemon.party.get(player)
	local box = M.list(player)
	local first, _ = PCL.page_bounds(st.page)
	local fs = {
		"size[10.6,9.6]",
		"label[0.3,0.35;Your party]",
	}
	for i = 1, PCL.PARTY_MAX do
		local selected = st.side == "party" and st.index == i
		fs[#fs + 1] = string.format("button[%.2f,0.8;1.6,0.8;pc_party_%d;%s]", 0.3 + (i - 1) * 1.7, i,
			esc(party_cell(party[i], selected)))
	end
	fs[#fs + 1] = string.format("label[0.3,2.0;PC box, page %d of %d]", st.page, PCL.PAGES)
	fs[#fs + 1] = "button[6.0,1.85;1.0,0.6;pc_prev;<]"
	fs[#fs + 1] = "button[7.1,1.85;1.0,0.6;pc_next;>]"
	for r = 0, 4 do
		for c = 0, 5 do
			local index = first + r * 6 + c
			local entry = box[index]
			local selected = st.side == "box" and st.index == index
			local text = entry and cell_text(entry, selected) or "-"
			fs[#fs + 1] = string.format("button[%.2f,%.2f;1.6,0.8;pc_box_%d;%s]", 0.3 + c * 1.7, 2.7 + r * 0.9,
				index, esc(text))
		end
	end
	fs[#fs + 1] = "button[0.3,7.8;2.6,0.8;pc_dep;Deposit]"
	fs[#fs + 1] = "button[3.1,7.8;2.6,0.8;pc_wd;Withdraw]"
	fs[#fs + 1] = "button_exit[5.9,7.8;2.6,0.8;close;Close]"
	fs[#fs + 1] = string.format("label[0.3,8.9;%s]", esc(st.note or ""))
	return table.concat(fs)
end

function M.show(player)
	core.show_formspec(player:get_player_name(), FORM, formspec(player))
end

-- Opens the PC for a player (the PC node's right click).
function M.open(player)
	local st = state(player:get_player_name())
	st.note = ""
	M.show(player)
end

-- Handles the PC formspec's fields. Returns true when handled.
function M.on_fields(player, fields)
	if fields.quit or fields.close then
		return true -- the player closed the PC: do not show it again
	end
	local name = player:get_player_name()
	local st = state(name)
	local party = minemon.party.get(player)
	for i = 1, PCL.PARTY_MAX do
		if fields["pc_party_" .. i] then
			st.side, st.index = "party", i
			M.show(player)
			return true
		end
	end
	for field in pairs(fields) do
		local index = field:match("^pc_box_(%d+)$")
		if index ~= nil then
			st.side, st.index = "box", tonumber(index)
			M.show(player)
			return true
		end
	end
	if fields.pc_prev then
		st.page = math.max(1, st.page - 1)
	elseif fields.pc_next then
		st.page = math.min(PCL.PAGES, st.page + 1)
	elseif fields.pc_dep and st.side == "party" and party[st.index] ~= nil then
		local member = party[st.index]
		local ok, why = M.deposit(player, member)
		st.note = ok and (label_of(member) .. " is now in the PC.") or why
		st.side, st.index = nil, nil
	elseif fields.pc_wd and st.side == "box" then
		local box = M.list(player)
		local entry = box[st.index]
		if entry == nil then
			st.note = PCL.REFUSE_NONE
		else
			local ok, why = M.withdraw(player, st.index)
			st.note = ok and (label_of(entry) .. " joined your party.") or why
		end
		st.side, st.index = nil, nil
	end
	M.show(player)
	return true
end

function M.forget(name)
	ui[name] = nil
end

M.FORM = FORM

return M
