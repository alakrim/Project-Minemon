-- Pure rules for minemon_party (T-22, M1 contract). No `core` access, so busted can test them (docs/CONVENTIONS.md).
-- init.lua, brain.lua and ui.lua are the Luanti glue.
--
-- A member is a minemon.instance table (uid, species_id, level, hp, moves, ...) plus `faint_s`: the seconds of play
-- time it has spent fainted. A party is a plain array of members, at most M.MAX long. Functions never mutate their
-- inputs; they return new tables.

local M = {}

M.MAX = 6
M.STARTER_LEVEL = 5
M.STARTERS = { 1, 4, 7, 152, 155, 158 } -- Bulbasaur, Charmander, Squirtle, Chikorita, Cyndaquil, Totodile
M.REGEN_S = 8 -- seconds per 1 HP for a recalled, hurt creature
M.REVIVE_S = 600 -- a fainted creature revives to 1 HP after this much play time
M.SEND_DIST = 2 -- a creature is sent out this far in front of the player
M.TELEPORT_DIST = 24 -- an owned creature farther than this from its owner teleports behind the owner
M.TELEPORT_BEHIND = 2
M.FOLLOW_START = 4 -- walk toward the owner beyond this distance
M.FOLLOW_STOP = 3 -- stand still within this distance (between the two, keep the current action)
M.FAST_FOLLOW_DIST = 8 -- run toward the owner beyond this distance
M.TARGET_RANGE = 32 -- an ordered target farther than this is dropped
M.ASSIST_RANGE = 10 -- a wild creature this close that attacks us or the owner is joined
M.BRAIN_S = 0.25 -- the owned brain works every this many seconds
M.COLOUR = { white = 0xFFFFFF, yellow = 0xFFD700, red = 0xFF3030, grey = 0x9A9A9A }

-- One colour per type, the same palette as minemon_combat/vfx.lua (TYPE_COLOUR).
M.TYPE_COLOUR = {
	normal = "#d8d4b8",
	fire = "#ff7a2e",
	water = "#4f9bff",
	electric = "#ffe14a",
	grass = "#5fd35f",
	ice = "#8fe8ff",
	fighting = "#e0503a",
	poison = "#c35ae0",
	ground = "#e8c070",
	flying = "#6aa6ff",
	psychic = "#ff5fa8",
	bug = "#c8e040",
	rock = "#c8b060",
	ghost = "#8a6fc8",
	dragon = "#7a5cff",
	dark = "#6a5a6e",
	steel = "#d0dcf0",
}

local function copy(list)
	local out = {}
	for i, m in ipairs(list) do
		out[i] = m
	end
	return out
end

local function clamp(n, lo, hi)
	if n < lo then
		return lo
	end
	if n > hi then
		return hi
	end
	return n
end

-- Members ----------------------------------------------------------------------------------------------------------

function M.is_alive(member)
	return member ~= nil and (member.hp or 0) > 0
end

-- Sets the field the party rules read, when a member does not have it yet.
function M.ensure(member)
	member.faint_s = member.faint_s or 0
	return member
end

-- "mr_mime" -> "Mr Mime", "cyndaquil" -> "Cyndaquil" (the same rule as minemon_creatures/defs.lua display_name).
function M.display_name(raw)
	local parts = {}
	for word in tostring(raw or ""):gmatch("[^_]+") do
		parts[#parts + 1] = word:sub(1, 1):upper() .. word:sub(2)
	end
	return table.concat(parts, " ")
end

-- The nickname when there is one, else the species name.
function M.member_name(member, species_name)
	if member.nickname and member.nickname ~= "" then
		return member.nickname
	end
	return M.display_name(species_name)
end

-- "none" and nil read as "OK"; other statuses are capitalised.
function M.status_text(status)
	if status == nil or status == "" or status == "none" then
		return "OK"
	end
	return M.display_name(status)
end

-- The HUD colour of a member's HP: grey when fainted, red below 20%, yellow below 50%, else white.
function M.hp_colour(hp, max)
	if hp <= 0 then
		return M.COLOUR.grey
	end
	local frac = max > 0 and hp / max or 0
	if frac < 0.2 then
		return M.COLOUR.red
	end
	if frac < 0.5 then
		return M.COLOUR.yellow
	end
	return M.COLOUR.white
end

-- One HUD line, e.g. "▶ ● Cyndaquil Lv5 18/20". The active member is marked with ▶.
function M.hud_line(member, species_name, max, is_active)
	local mark = is_active and "▶ " or "  "
	return string.format("%s● %s Lv%d %d/%d", mark, M.member_name(member, species_name), member.level,
		math.max(0, member.hp), max)
end

-- The type colour of a type name, as "#rrggbb" (white when unknown).
function M.type_colour(type_name)
	return M.TYPE_COLOUR[type_name] or "#ffffff"
end

-- "Grass/Poison" for ["grass", "poison"].
function M.types_text(types)
	local parts = {}
	for i, t in ipairs(types or {}) do
		parts[i] = M.display_name(t)
	end
	return table.concat(parts, "/")
end

-- The party list ---------------------------------------------------------------------------------------------------

function M.index_of(list, uid)
	for i, m in ipairs(list) do
		if m.uid == uid then
			return i
		end
	end
	return nil
end

-- Appends a member. Returns the new list, or nil and a reason when the party is full or the uid is already there.
function M.add(list, member)
	if #list >= M.MAX then
		return nil, "full"
	end
	if M.index_of(list, member.uid) then
		return nil, "duplicate"
	end
	local out = copy(list)
	out[#out + 1] = member
	return out
end

-- Replaces the member with the same uid (write-back). Returns the new list and whether a member was found.
function M.replace(list, member)
	local i = M.index_of(list, member.uid)
	if not i then
		return list, false
	end
	local out = copy(list)
	out[i] = member
	return out, true
end

-- The index of the lead: the first member with HP above 0, or nil when everyone has fainted.
function M.lead_index(list)
	for i, m in ipairs(list) do
		if M.is_alive(m) then
			return i
		end
	end
	return nil
end

-- Moves the member at index to the front. A fainted member cannot lead. Returns the new list, or nil and a reason.
function M.make_lead(list, index)
	local m = list[index]
	if not m then
		return nil, "no such member"
	end
	if not M.is_alive(m) then
		return nil, "fainted"
	end
	local out = { m }
	for i, x in ipairs(list) do
		if i ~= index then
			out[#out + 1] = x
		end
	end
	return out
end

-- Timers -----------------------------------------------------------------------------------------------------------

-- Regeneration for a recalled creature that is hurt and alive: 1 HP per REGEN_S seconds, never above max. Returns
-- the new accumulator (seconds) and the new HP.
function M.regen_step(acc, hp, max, dt)
	if hp <= 0 or hp >= max then
		return 0, hp
	end
	acc = (acc or 0) + dt
	local steps = math.min(math.floor(acc / M.REGEN_S), max - hp)
	if steps < 0 then
		steps = 0
	end
	hp = hp + steps
	acc = acc - steps * M.REGEN_S
	if hp >= max then
		acc = 0
	end
	return acc, hp
end

-- Fainted time: adds dt. Returns the new fainted time and whether the creature revives now (the caller sets HP 1).
function M.revive_step(faint_s, dt)
	local s = (faint_s or 0) + dt
	if s >= M.REVIVE_S then
		return 0, true
	end
	return s, false
end

-- Owned brain -----------------------------------------------------------------------------------------------------

-- "walk" or "stand" for a follow decision at distance dist. Between the two thresholds the current action holds.
function M.follow_action(dist, walking)
	if dist > M.FOLLOW_START then
		return "walk"
	end
	if dist <= M.FOLLOW_STOP then
		return "stand"
	end
	return walking and "walk" or "stand"
end

function M.needs_teleport(dist)
	return dist > M.TELEPORT_DIST
end

-- An ordered target is kept while it exists, is not exhausted and is within TARGET_RANGE.
function M.target_valid(exists, exhausted, dist)
	return exists == true and exhausted ~= true and dist <= M.TARGET_RANGE
end

-- The point TELEPORT_BEHIND metres behind the owner, on the horizontal plane. look is the owner's look direction.
function M.behind(owner_pos, look)
	local lx, lz = look.x or 0, look.z or 0
	local len = math.sqrt(lx * lx + lz * lz)
	if len < 1e-6 then
		lx, lz, len = 0, 1, 1
	end
	return {
		x = owner_pos.x - lx / len * M.TELEPORT_BEHIND,
		y = owner_pos.y + 0.5, -- half a node up, as in_front: a creature placed at ground level sinks into it
		z = owner_pos.z - lz / len * M.TELEPORT_BEHIND,
	}
end

-- The point M.SEND_DIST metres in front of the player, on the horizontal plane (feet level plus 0.5).
function M.in_front(player_pos, look)
	local lx, lz = look.x or 0, look.z or 0
	local len = math.sqrt(lx * lx + lz * lz)
	if len < 1e-6 then
		lx, lz, len = 0, 1, 1
	end
	return {
		x = player_pos.x + lx / len * M.SEND_DIST,
		y = player_pos.y + 0.5,
		z = player_pos.z + lz / len * M.SEND_DIST,
	}
end

-- Storage ----------------------------------------------------------------------------------------------------------

-- Builds a party from a JSON-decoded value. Anything that is not a valid member is dropped, duplicates too, and the
-- list is cut to MAX. deserialize is minemon.instance.deserialize; it may fail, and then the entry is dropped.
function M.load(parsed, deserialize)
	local out = {}
	if type(parsed) ~= "table" then
		return out
	end
	for i = 1, #parsed do
		if #out >= M.MAX then
			break
		end
		local t = parsed[i]
		if type(t) == "table" then
			local ok, m = pcall(deserialize, t)
			if ok and type(m) == "table" and type(m.uid) == "string" and m.uid ~= "" and m.species_id >= 1 then
				m.level = math.max(1, m.level)
				m.hp = math.max(0, m.hp)
				m.faint_s = clamp(tonumber(t.faint_s) or 0, 0, M.REVIVE_S)
				if M.index_of(out, m.uid) == nil then
					out[#out + 1] = m
				end
			end
		end
	end
	return out
end

-- The JSON-safe array for the party list. serialize is minemon.instance.serialize.
function M.save(list, serialize)
	local out = {}
	for i, m in ipairs(list) do
		local t = serialize(m)
		t.faint_s = m.faint_s or 0
		out[i] = t
	end
	return out
end

return M
