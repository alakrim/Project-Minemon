-- Pure rules for the Sanctuary PC (T-28, D-030). No `core` access, so busted can test them.
-- The box is a plain array of serialized instances (minemon.instance.serialize). pc.lua is the Luanti glue.
-- A party member is a minemon.instance table with hp (and faint_s, which the party keeps and the box drops).
-- Functions never mutate their inputs; they return new tables.

local M = {}

M.CAP = 240 -- stored creatures in one PC
M.PAGE_SIZE = 30 -- creatures per box page
M.PAGES = 8 -- 8 pages of 30 make the 240 cap
M.PARTY_MAX = 6 -- the party size (minemon_party MAX)
M.REFUSE_LAST = "You can't go out there alone."
M.REFUSE_FULL_BOX = "Your PC box is full."
M.REFUSE_PARTY_FULL = "Your party is full."
M.REFUSE_NONE = "No such creature."

-- First and last box index shown on a page (1-based, inclusive). Pages outside 1..PAGES are clamped.
function M.page_bounds(page)
	local p = math.max(1, math.min(M.PAGES, math.floor(page or 1)))
	local first = (p - 1) * M.PAGE_SIZE + 1
	return first, first + M.PAGE_SIZE - 1
end

-- The page that holds a box index.
function M.page_of(index)
	return math.floor((index - 1) / M.PAGE_SIZE) + 1
end

-- Depositing: the member at index can leave the party when another member is alive, or when it has fainted.
-- Returns true, or false and the reason.
function M.can_deposit(party, index)
	local m = party[index]
	if m == nil then
		return false, M.REFUSE_NONE
	end
	if m.hp > 0 then
		for i, other in ipairs(party) do
			if i ~= index and other.hp > 0 then
				return true
			end
		end
		return false, M.REFUSE_LAST
	end
	return true
end

-- Withdrawing: the box index must exist and the party must have room. Returns true, or false and the reason.
function M.can_withdraw(party, box, index)
	if box[index] == nil then
		return false, M.REFUSE_NONE
	end
	if #party >= M.PARTY_MAX then
		return false, M.REFUSE_PARTY_FULL
	end
	return true
end

-- Adds a serialized creature to the end of the box. Returns the new box, or nil and the reason when it is full.
function M.box_add(box, entry)
	if #box >= M.CAP then
		return nil, M.REFUSE_FULL_BOX
	end
	local out = {}
	for i, e in ipairs(box) do
		out[i] = e
	end
	out[#out + 1] = entry
	return out
end

-- Removes the entry at index. Returns the new box and the removed entry (nil when index is out of range).
function M.box_remove(box, index)
	if box[index] == nil then
		return box, nil
	end
	local out = {}
	for i, e in ipairs(box) do
		if i ~= index then
			out[#out + 1] = e
		end
	end
	return out, box[index]
end

-- The party without the member at index (a new array).
function M.party_without(party, index)
	local out = {}
	for i, m in ipairs(party) do
		if i ~= index then
			out[#out + 1] = m
		end
	end
	return out
end

-- The party with one more member at the end (a new array).
function M.party_with(party, member)
	local out = {}
	for i, m in ipairs(party) do
		out[i] = m
	end
	out[#out + 1] = member
	return out
end

-- Index of a uid in a list of members or entries, or nil.
function M.index_of_uid(list, uid)
	for i, m in ipairs(list) do
		if m.uid == uid then
			return i
		end
	end
	return nil
end

-- Builds the box from its JSON-decoded value. Invalid entries and duplicate uids are dropped; the cap holds.
-- deserialize is minemon.instance.deserialize (a failing entry is dropped). Returns the array of instances.
function M.load(parsed, deserialize)
	local out = {}
	if type(parsed) ~= "table" then
		return out
	end
	for _, t in ipairs(parsed) do
		if #out >= M.CAP then
			break
		end
		if type(t) == "table" then
			local ok, m = pcall(deserialize, t)
			if ok and type(m) == "table" and type(m.uid) == "string" and m.uid ~= "" and m.species_id >= 1
				and M.index_of_uid(out, m.uid) == nil then
				out[#out + 1] = m
			end
		end
	end
	return out
end

-- The JSON-safe array for the box. serialize is minemon.instance.serialize.
function M.save(box, serialize)
	local out = {}
	for i, m in ipairs(box) do
		out[i] = serialize(m)
	end
	return out
end

return M
