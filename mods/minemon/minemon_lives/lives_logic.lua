-- Pure lives rules for minemon_lives. Must not touch `core` (see docs/CONVENTIONS.md),
-- so busted can test it without Luanti.
--
-- State: { lives = int 0..max, deaths = int >= 0, dead = bool }
-- Rules: lives start at max. Each death while alive costs one life; the death that
-- takes lives to 0 reports "last_life"; a death at 0 lives is permadeath (dead = true).
-- Functions never mutate their input; they return new tables.

local M = {}

M.MAX = 3

local function clamp(n, lo, hi)
	if n < lo then
		return lo
	end
	if n > hi then
		return hi
	end
	return n
end

-- Returns a valid copy of any state-shaped table. A dead state always has 0 lives.
local function normalize(state, max)
	max = max or M.MAX
	state = state or {}
	local dead = state.dead == true
	local lives = clamp(math.floor(tonumber(state.lives) or max), 0, max)
	local deaths = math.max(0, math.floor(tonumber(state.deaths) or 0))
	if dead then
		lives = 0
	end
	return { lives = lives, deaths = deaths, dead = dead }
end

function M.new_state(max)
	max = max or M.MAX
	return { lives = max, deaths = 0, dead = false }
end

-- Returns new_state, event. Event is "lost_life", "last_life" or "permadeath".
-- A death while already dead changes nothing and reports "permadeath".
function M.on_death(state, max)
	max = max or M.MAX
	local s = normalize(state, max)
	if s.dead then
		return s, "permadeath"
	end
	if s.lives > 0 then
		local lives = s.lives - 1
		local event = "lost_life"
		if lives == 0 then
			event = "last_life"
		end
		return { lives = lives, deaths = s.deaths + 1, dead = false }, event
	end
	return { lives = 0, deaths = s.deaths + 1, dead = true }, "permadeath"
end

-- Adds one life, capped at max. A dead state is unchanged: only revive undoes permadeath.
function M.give_life(state, max)
	max = max or M.MAX
	local s = normalize(state, max)
	if s.dead then
		return s
	end
	s.lives = math.min(s.lives + 1, max)
	return s
end

-- Full reset: back to max lives, zero deaths, alive.
function M.revive(_state, max)
	return M.new_state(max)
end

-- Compact text for player meta, e.g. "3:0:0" (lives:deaths:dead as 0 or 1).
function M.serialize(state, max)
	local s = normalize(state, max)
	return string.format("%.0f:%.0f:%d", s.lives, s.deaths, s.dead and 1 or 0)
end

-- Parses serialize() output. Any garbage, empty string or nil gives new_state(max).
function M.deserialize(text, max)
	max = max or M.MAX
	if type(text) ~= "string" or #text == 0 or #text > 64 then
		return M.new_state(max)
	end
	local lives_text, deaths_text, dead_text = text:match("^(%d+):(%d+):([01])$")
	if not lives_text then
		return M.new_state(max)
	end
	return normalize({
		lives = tonumber(lives_text),
		deaths = tonumber(deaths_text),
		dead = dead_text == "1",
	}, max)
end

return M
