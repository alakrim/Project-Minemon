-- Pure rules for minemon_capture (T-26, D-030): ball ids, catch multipliers, the shake check, the odds bands and the
-- messages. Must not touch `core` (see docs/CONVENTIONS.md), so busted can test it without Luanti. init.lua is the
-- glue that throws balls, runs the capture sequence and draws the odds HUD.

local M = {}

M.SHAKE_CHECKS = 4 -- Gen 3+ shake checks: each passes with probability p^(1/4), so all four pass with probability p
M.SHAKE_SECONDS = 0.9 -- one visible shake
M.CAUGHT_BOND = 70 -- bond of a freshly caught creature
M.THROW_SPEED = 22 -- metres per second
M.THROW_GRAVITY = 4 -- a slight pull, so a throw has an arc
M.THROW_MAX_AGE = 4 -- seconds before a ball in flight lands where it is
M.ODDS_RANGE = 24 -- nodes the odds ray reaches
M.ODDS_INTERVAL = 0.25 -- seconds between odds updates
M.ODDS_GREEN_MIN = 60
M.ODDS_YELLOW_MIN = 25
M.KIT_BALLS = 5 -- Poké Balls in the starter kit
M.PARTY_MAX = 6 -- mirrors minemon_party's party_logic.MAX
M.PAUSED_TIMER = 1000000 -- the exhausted timer while a capture runs (stays a finite number, so it serializes)

-- Ball ids, in order of strength. Item names are "minemon:<id>" (registered with a leading colon, D-030).
-- The Umbral Ball (T-30, D-031) is made from Dread Shards and is strong only against Dread creatures.
M.BALLS = { "poke_ball", "great_ball", "ultra_ball", "master_ball", "umbral_ball" }
M.UMBRAL_DREAD_MULT = 3.0 -- Umbral Ball catch multiplier against a Dread creature (its base is 0.5 otherwise)
M.DREAD_OTHER_FACTOR = 0.75 -- every other ball is weaker against a Dread creature (x0.75)
M.DREAD_CAUGHT_BOND = 20 -- bond of a caught Dread creature (a normal catch starts at CAUGHT_BOND)
local BALL_SET = {}
for _, id in ipairs(M.BALLS) do
	BALL_SET[id] = true
end

-- "minemon:great_ball" -> "great_ball"; anything else (or an unknown id) -> nil.
function M.ball_id(item_name)
	if type(item_name) ~= "string" then
		return nil
	end
	local id = item_name:match("^minemon:(.+)$")
	if id ~= nil and BALL_SET[id] then
		return id
	end
	return nil
end

function M.item_name(ball_id)
	return "minemon:" .. ball_id
end

-- Catch multiplier of an items.json record (the minemon.data.get_item result), or nil when it is not a ball.
function M.catch_mult(item)
	if type(item) ~= "table" or item.kind ~= "ball" then
		return nil
	end
	return tonumber(item.catch_mult)
end

-- The catch multiplier of a ball against one creature (T-30). base is the items.json catch_mult of the ball. A Dread
-- creature (inst.dread) takes the Umbral Ball at UMBRAL_DREAD_MULT and the other balls at base x DREAD_OTHER_FACTOR.
-- Any other creature gets base.
function M.ball_mult(ball_id, inst, base)
	if inst == nil or inst.dread ~= true then
		return base
	end
	if ball_id == "umbral_ball" then
		return M.UMBRAL_DREAD_MULT
	end
	return base * M.DREAD_OTHER_FACTOR
end

-- The bond a caught creature starts with: DREAD_CAUGHT_BOND for a Dread creature, else CAUGHT_BOND.
function M.caught_bond(inst)
	if inst ~= nil and inst.dread == true then
		return M.DREAD_CAUGHT_BOND
	end
	return M.CAUGHT_BOND
end

-- The Master Ball always catches; any other ball uses the catch chance as it is.
function M.effective_p(ball_id, p)
	if ball_id == "master_ball" then
		return 1
	end
	return p
end

-- Shake check (Gen 3+). Returns n (visible shakes, 0..3) and caught. The creature is caught when all four checks pass,
-- so the catch probability is p. A failed check ends the sequence after the shakes before it.
function M.shakes(p, rng)
	if p >= 1 then
		return M.SHAKE_CHECKS - 1, true
	end
	if p <= 0 then
		return 0, false
	end
	local q = p ^ (1 / M.SHAKE_CHECKS)
	for i = 1, M.SHAKE_CHECKS do
		if rng:float() >= q then
			return i - 1, false
		end
	end
	return M.SHAKE_CHECKS - 1, true
end

-- Catch odds in whole percent, 0..100.
function M.odds_percent(p)
	local clamped = math.max(0, math.min(1, tonumber(p) or 0))
	return math.floor(clamped * 100 + 0.5)
end

function M.odds_band(pct)
	if pct >= M.ODDS_GREEN_MIN then
		return "green"
	end
	if pct >= M.ODDS_YELLOW_MIN then
		return "yellow"
	end
	return "red"
end

-- Band colours as 0xRRGGBB numbers (HUD text colour).
M.ODDS_RGB = { green = 0x55FF55, yellow = 0xFFFF55, red = 0xFF5555 }

function M.odds_text(pct)
	return "Catch ~" .. tostring(pct) .. "%"
end

-- "Catch rate ×1", "×1.5", "×255": %g keeps the decimals of the data and drops the .0.
function M.tooltip_line(mult)
	return string.format("Catch rate ×%g", mult)
end

-- "mr_mime" -> "Mr Mime", "cyndaquil" -> "Cyndaquil". A nickname wins over the species name.
function M.display_name(species_name, nickname)
	if type(nickname) == "string" and nickname ~= "" then
		return nickname
	end
	local parts = {}
	for word in tostring(species_name or ""):gmatch("[^_]+") do
		parts[#parts + 1] = word:sub(1, 1):upper() .. word:sub(2)
	end
	return table.concat(parts, " ")
end

-- The starter kit is given once: a player with creatures and no flag yet.
function M.kit_due(party_size, flag_set)
	return (party_size or 0) > 0 and not flag_set
end

function M.caught_line(name)
	return "Gotcha! " .. name .. " was caught!"
end

function M.broke_free_line(name)
	return "Oh no! " .. name .. " broke free!"
end

function M.too_strong_line()
	return "It's too strong — weaken it first!"
end

function M.sent_to_pc_line(name)
	return name .. " was sent to the PC."
end

-- What a thrown ball does when it hits an object: "drop" (not a wild creature: a player, an owned creature, or any
-- other object), "bounce" (a wild creature that is not exhausted) or "capture" (an exhausted wild creature).
function M.hit_outcome(is_wild, is_exhausted)
	if not is_wild then
		return "drop"
	end
	if is_exhausted then
		return "capture"
	end
	return "bounce"
end

return M
