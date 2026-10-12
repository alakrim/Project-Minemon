-- Pure runtime rules for minemon_creatures (T-24, D-027). Must not touch `core` (see docs/CONVENTIONS.md),
-- so busted can test it without Luanti. runtime.lua is the Luanti glue that calls these functions.
--
-- HP is an integer in 0..max. Every change goes through these rules, so the entity and the saved instance agree.
-- Functions never mutate their input; they return new values.

local M = {}

M.EXHAUST_SECONDS = 20 -- wild creatures stay exhausted this long (PLAN D-027)
M.ENRAGE_SECONDS = 30 -- a creature that breaks free of a ball turns on the thrower this long (D-030)
M.RECOVER_FRACTION = 0.25 -- HP after exhaustion ends, as a fraction of max HP
M.HIT_THRESHOLD = 0.1 -- raw damage below this is no hit (mirrors mcl_mobs on_punch, combat.lua:617-618)
M.LOG_INTERVAL = 60 -- seconds between two log lines from the same brain

local function clamp(n, lo, hi)
	if n < lo then
		return lo
	end
	if n > hi then
		return hi
	end
	return n
end
M.clamp = clamp

-- HP after `amount` damage: never below 0, never above max. A non-positive amount changes nothing.
function M.apply_damage(hp, max, amount)
	if amount <= 0 then
		return clamp(hp, 0, max)
	end
	return clamp(hp - amount, 0, max)
end

-- Whole HP for a raw hit. Below the threshold there is no hit; a hit always does at least 1 HP.
function M.hit_amount(raw)
	if raw < M.HIT_THRESHOLD then
		return 0
	end
	return math.max(1, math.floor(raw))
end

-- Raw punch damage, as mcl_mobs computes it (combat.lua:567-580): each damage group times the time factor
-- times armor/100. `tflp` is the time since the last punch; 0 is treated as 0.2 (combat.lua:572-574).
-- `groups` and `armor` may be nil.
function M.punch_damage(groups, armor, tflp, full_punch_interval)
	local interval = full_punch_interval or 1.4
	if interval == 0 then
		interval = 0.001
	end
	local t = tflp or interval
	if t == 0 then
		t = 0.2
	end
	local frac = clamp(t / interval, 0, 1)
	local total = 0
	for group, value in pairs(groups or {}) do
		local armor_factor = ((armor and armor[group]) or 0) / 100.0
		total = total + value * frac * armor_factor
	end
	return total
end

-- One damage step on the instance HP. Returns new_hp, dealt (HP removed), reached_zero (true when this hit took
-- HP from above 0 to 0). An exhausted creature ignores damage: nothing changes.
function M.damage_step(hp, max, raw, exhausted)
	if exhausted then
		return hp, 0, false
	end
	local dmg = M.hit_amount(raw or 0)
	if dmg <= 0 then
		return hp, 0, false
	end
	local new_hp = M.apply_damage(hp, max, dmg)
	local dealt = hp - new_hp
	return new_hp, dealt, hp > 0 and new_hp == 0
end

-- One heal step. Returns new_hp and the HP added. Exhausted creatures do not heal; they recover by the timer.
function M.heal_step(hp, max, amount, exhausted)
	if exhausted or (amount or 0) < 1 then
		return hp, 0
	end
	local new_hp = M.clamp(hp + math.floor(amount), 0, max)
	return new_hp, new_hp - hp
end

-- What happens when HP reaches 0: an owned creature faints (T-22 recalls it), a wild one is exhausted.
function M.zero_outcome(owned)
	if owned then
		return "faint"
	end
	return "exhaust"
end

-- The change that brings the entity's HP (what mcl_mobs left in self.health) back in line with the instance.
-- Returns "none", "damage" (amount to apply) or "heal" (amount to apply). Negative entity HP counts as 0.
function M.reconcile(entity_hp, inst_hp, max)
	local e = clamp(entity_hp, 0, max)
	if e == inst_hp then
		return "none", 0
	end
	if e < inst_hp then
		return "damage", inst_hp - e
	end
	return "heal", e - inst_hp
end

-- HP after exhaustion ends: 25% of max, at least 1.
function M.recovery_hp(max)
	return math.max(1, math.floor(max * M.RECOVER_FRACTION))
end

-- Seconds left in exhaustion after dtime. Returns the new value and whether exhaustion is over.
function M.tick_exhausted(remaining, dtime)
	local left = remaining - dtime
	return left, left <= 0
end

-- Seconds left in the enraged state after dtime. Returns the new value and whether the rage is over.
function M.tick_enraged(remaining, dtime)
	local left = remaining - dtime
	return left, left <= 0
end

local SUFFIX = " (exhausted)"
M.SUFFIX = SUFFIX

-- Nametag with the exhausted suffix. Idempotent.
function M.with_suffix(text)
	text = text or ""
	if text:sub(-#SUFFIX) == SUFFIX then
		return text
	end
	return text .. SUFFIX
end

function M.without_suffix(text)
	text = text or ""
	if text:sub(-#SUFFIX) == SUFFIX then
		return text:sub(1, #text - #SUFFIX)
	end
	return text
end

-- Log throttle: true when a line may be written now (never logged, or the interval has passed).
function M.should_log(last, now, interval)
	return last == nil or now - last >= (interval or M.LOG_INTERVAL)
end

-- Runs brains in order. brains: list of { name = string, fn = function(self, dtime) -> result }.
-- Result rules: true stops the chain and returns nil (mcl default states still run);
-- "skip_states" stops the chain and returns false (mcl do_states is skipped); anything else continues.
-- A brain that raises an error is reported through on_error(name, message) and does not stop the chain.
-- Returns the value for mcl's do_custom: false or nil.
function M.run_chain(brains, self, dtime, on_error)
	for _, brain in ipairs(brains) do
		local ok, res = pcall(brain.fn, self, dtime)
		if not ok then
			if on_error then
				on_error(brain.name, tostring(res))
			end
		elseif res == "skip_states" then
			return false
		elseif res == true then
			return nil
		end
	end
	return nil
end

return M
