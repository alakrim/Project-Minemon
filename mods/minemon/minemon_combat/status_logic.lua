-- Status effects and the bounded registry (T-23). Pure: no Luanti API, so busted can test it.
-- A record is {kind, left, tick}: left is seconds of status left (nil for freeze), tick is the burn/poison timer.

local M = {}

M.KINDS = { burn = true, poison = true, paralysis = true, sleep = true, freeze = true }
-- The brief sets no end for burn, poison and paralysis. This keeps them bounded (a design choice, see report).
M.DURATION_S = 12
M.TICK_S = 2 -- burn and poison damage interval
M.TICK_DIVISOR = 16 -- 1/16 of max HP per tick
M.PARALYSIS_FAIL = 0.25
M.PARALYSIS_SPEED = 0.5
M.THAW_PER_SECOND = 0.10
M.SLEEP_MIN_S = 3 -- T-31: sleep lasts 3 to 7 s
M.SLEEP_MAX_S = 7
M.REGISTRY_CAP = 256

function M.is_minimal(kind)
	return M.KINDS[kind] == true
end

-- Sleep and freeze stop moves.
function M.blocks_moves(kind)
	return kind == "sleep" or kind == "freeze"
end

-- Walk and run multiplier for creatures: paralysis halves them, sleep and freeze stop them.
function M.speed_mult(kind)
	if kind == "paralysis" then
		return M.PARALYSIS_SPEED
	end
	if kind == "sleep" or kind == "freeze" then
		return 0
	end
	return 1
end

function M.burn_damage(max_hp)
	return math.max(1, math.floor((tonumber(max_hp) or 0) / M.TICK_DIVISOR))
end

-- Chance that a freeze thaws within dt seconds, at 10% per second.
function M.thaw_chance(dt)
	return 1 - (1 - M.THAW_PER_SECOND) ^ dt
end

function M.paralysis_fails(rng)
	return rng:float() < M.PARALYSIS_FAIL
end

function M.sleep_duration(rng)
	return M.SLEEP_MIN_S + (M.SLEEP_MAX_S - M.SLEEP_MIN_S) * rng:float()
end

-- A new record. A sleep takes the duration given (rest: 5 s) or a random one from 3 to 7 s.
function M.new_record(kind, rng, duration)
	local left = nil
	if kind == "sleep" then
		left = duration or M.sleep_duration(rng)
	elseif kind == "burn" or kind == "poison" or kind == "paralysis" then
		left = M.DURATION_S
	end
	return { kind = kind, left = left, tick = 0 }
end

-- Fresh durations for a status restored after an unload or reload (T-23b): sleep and freeze 3 s, the rest 12 s.
M.RESTORE_SHORT_S = 3
function M.restore_record(kind)
	local left = nil
	if kind == "sleep" or kind == "freeze" then
		left = M.RESTORE_SHORT_S
	elseif kind == "burn" or kind == "poison" or kind == "paralysis" then
		left = M.DURATION_S
	end
	return { kind = kind, left = left, tick = 0 }
end

-- Advances a record by dt seconds. Returns {damage = n, cured = bool}. Burn and poison deal 1/16 max HP every
-- TICK_S seconds. rng is used only by freeze (the thaw roll).
function M.advance(record, dt, rng, max_hp)
	local out = { damage = 0, cured = false }
	local kind = record.kind
	if kind == "burn" or kind == "poison" then
		record.tick = (record.tick or 0) + dt
		while record.tick >= M.TICK_S do
			record.tick = record.tick - M.TICK_S
			out.damage = out.damage + M.burn_damage(max_hp)
		end
	elseif kind == "freeze" then
		if rng:float() < M.thaw_chance(dt) then
			out.cured = true
		end
	end
	if record.left ~= nil then
		record.left = record.left - dt
		if record.left <= 0 then
			out.cured = true
		end
	end
	return out
end

-- A map with a fixed capacity. put returns false when the map is full and the key is new.
function M.new_registry(cap)
	local items = {}
	local count = 0
	local reg = {}

	function reg.put(key, value)
		if items[key] == nil then
			if count >= cap then
				return false
			end
			count = count + 1
		end
		items[key] = value
		return true
	end

	function reg.get(key)
		return items[key]
	end

	function reg.remove(key)
		if items[key] ~= nil then
			items[key] = nil
			count = count - 1
		end
	end

	function reg.size()
		return count
	end

	-- Calls fn(key, value) for every entry in key order. Entries removed during the walk are skipped.
	function reg.each(fn)
		local keys = {}
		for k in pairs(items) do
			keys[#keys + 1] = k
		end
		table.sort(keys)
		for _, k in ipairs(keys) do
			if items[k] ~= nil then
				fn(k, items[k])
			end
		end
	end

	-- Removes every entry for which keep(value) is false.
	function reg.prune(keep)
		reg.each(function(k, v)
			if not keep(v) then
				reg.remove(k)
			end
		end)
	end

	return reg
end

return M
