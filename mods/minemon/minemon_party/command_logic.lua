-- Pure rules for the move command bar (T-29, D-031). No `core` access, so busted can test them (docs/CONVENTIONS.md).
-- command.lua is the Luanti glue: the HUD bar, the Z key, the Party Ball clicks. brain.lua reads the queue.
--
-- A moveset is an array of up to SLOTS entries { id, pp } (minemon.instance moves). A pp list is SLOTS long: a number
-- for a move, nil for an empty slot. A queue is { move = id, expires = game time }: a move the player ordered, which
-- the owned brain casts on the ordered target when it is in reach and off cooldown.

local M = {}

M.SLOTS = 4
M.QUEUE_S = 6 -- a queued move expires this many seconds after the order
M.NAME_CHARS = 12 -- the bar shows at most this many characters of a move name

-- The pp of each of the SLOTS moves of a moveset: a number for a move, nil for an empty slot.
function M.slot_pps(moveset)
	local out = {}
	for i = 1, M.SLOTS do
		local s = moveset and moveset[i]
		if type(s) == "table" and s.id ~= nil then
			out[i] = math.max(0, math.floor(tonumber(s.pp) or 0))
		end
	end
	return out
end

-- True when slot i holds a move with PP above 0.
local function usable(pps, i)
	local pp = pps[i]
	return type(pp) == "number" and pp > 0
end

-- The next slot after current (wrapping round) whose move has PP above 0. current may be nil or 0 to start from
-- slot 1. Returns the slot index, or nil when no slot has PP left. Empty slots and 0-PP moves are skipped.
function M.next_selectable(pps, current)
	local cur = current or 0
	for i = 1, M.SLOTS do
		local idx = ((cur - 1 + i) % M.SLOTS) + 1
		if usable(pps, idx) then
			return idx
		end
	end
	return nil
end

-- The selection after the moves changed: current when it still has PP, else the next usable slot (or nil).
function M.keep_selection(pps, current)
	if current ~= nil and usable(pps, current) then
		return current
	end
	return M.next_selectable(pps, current)
end

-- A queued order that expires at now + QUEUE_S.
function M.new_queue(move_id, now)
	return { move = move_id, expires = now + M.QUEUE_S }
end

-- A queue is live while the game time is before its expiry.
function M.queue_live(queue, now)
	return queue ~= nil and now < queue.expires
end

-- A self-target move acts on its user, so it needs no target: an aura move, or a move whose stat changes all
-- target the user. Returns true or false.
function M.is_self_target(move)
	if type(move) ~= "table" then
		return false
	end
	if move.archetype == "aura" then
		return true
	end
	local changes = move.effect and move.effect.stat_changes or {}
	if #changes == 0 then
		return false
	end
	for _, c in ipairs(changes) do
		if c.target ~= "user" then
			return false
		end
	end
	return true
end

-- A move name cut to max_chars characters; a cut name ends with a dot.
function M.short_name(name, max_chars)
	local n = max_chars or M.NAME_CHARS
	local s = tostring(name or "")
	if #s <= n then
		return s
	end
	return s:sub(1, n - 1) .. "."
end

-- "PP 12/20" for the bar.
function M.pp_text(pp, max)
	return string.format("PP %d/%d", math.max(0, math.floor(tonumber(pp) or 0)), math.floor(tonumber(max) or 0))
end

return M
