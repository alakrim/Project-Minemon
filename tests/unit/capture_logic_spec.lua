-- Unit tests for mods/minemon/minemon_capture/capture_logic.lua (pure logic, no Luanti).
-- Covers: the shake check (catch rate within 2% of p over 20000 seeded trials), the Master Ball, the ball
-- multiplier lookup from items.json, the odds colour bands and text, the tooltip, the starter kit, the messages and
-- the hit outcome.
-- luacheck: globals describe it assert

local here = debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$") or "."
local L = dofile(here .. "/../../mods/minemon/minemon_capture/capture_logic.lua")
local R = dofile(here .. "/../../mods/minemon/minemon_core/rng.lua")
local ITEMS_PATH = here .. "/../../mods/minemon/minemon_core/data/items.json"

-- busted has no core.parse_json. items.json is flat: each ball entry is a block with a catch_mult line.
local function items_from_json()
	local f = assert(io.open(ITEMS_PATH, "rb"))
	local text = f:read("*a")
	f:close()
	local out = {}
	for _, id in ipairs({ "poke_ball", "great_ball", "ultra_ball", "master_ball", "potion" }) do
		local block = text:match('"' .. id .. '"%s*:%s*(%b{})')
		assert(block, "items.json has no entry " .. id)
		local kind = block:match('"kind"%s*:%s*"([^"]+)"')
		local mult = tonumber(block:match('"catch_mult"%s*:%s*([%d%.]+)'))
		out[id] = { kind = kind, catch_mult = mult }
	end
	return out
end

local function shake_rate(p, trials, seed)
	local rng = R.new(seed)
	local caught = 0
	for _ = 1, trials do
		local _, ok = L.shakes(p, rng)
		if ok then
			caught = caught + 1
		end
	end
	return caught / trials
end

describe("capture_logic.shakes", function()
	it("catches at the rate p (within 2%) over 20000 seeded trials", function()
		for _, p in ipairs({ 0.05, 0.3, 0.8 }) do
			local rate = shake_rate(p, 20000, 424242)
			assert.is_true(math.abs(rate - p) <= 0.02, string.format("p=%.2f measured %.4f", p, rate))
		end
	end)

	it("returns 0 to 3 visible shakes", function()
		local rng = R.new(7)
		for _ = 1, 2000 do
			local n = L.shakes(0.5, rng)
			assert.is_true(n >= 0 and n <= 3)
		end
	end)

	it("a forced pass on every check catches with 3 shakes", function()
		local always_pass = { float = function() return 0 end }
		local n, caught = L.shakes(0.3, always_pass)
		assert.equals(3, n)
		assert.is_true(caught)
	end)

	it("a forced fail on the first check gives 0 shakes and no catch", function()
		local always_fail = { float = function() return 0.9999 end }
		local n, caught = L.shakes(0.3, always_fail)
		assert.equals(0, n)
		assert.is_false(caught)
	end)

	it("p at or below 0 never catches and uses no randomness", function()
		local never = { float = function() error("rng must not be used") end }
		assert.is_false(select(2, L.shakes(0, never)))
		assert.is_false(select(2, L.shakes(-0.5, never)))
	end)

	it("p at or above 1 always catches with 3 shakes, whatever the rng", function()
		local never = { float = function() error("rng must not be used") end }
		local n, caught = L.shakes(1, never)
		assert.equals(3, n)
		assert.is_true(caught)
	end)
end)

describe("capture_logic Master Ball", function()
	it("is always 1, whatever the catch chance", function()
		assert.equals(1, L.effective_p("master_ball", 0.001))
		assert.equals(1, L.effective_p("master_ball", 0))
	end)

	it("always catches over 500 seeded trials", function()
		local rng = R.new(99)
		for _ = 1, 500 do
			local _, caught = L.shakes(L.effective_p("master_ball", 0.01), rng)
			assert.is_true(caught)
		end
	end)

	it("leaves the other balls' chance alone", function()
		assert.equals(0.25, L.effective_p("poke_ball", 0.25))
		assert.equals(0.4, L.effective_p("great_ball", 0.4))
	end)
end)

describe("capture_logic ball multiplier from items.json", function()
	local items = items_from_json()

	it("reads the catch multiplier of each ball", function()
		assert.equals(1.0, L.catch_mult(items.poke_ball))
		assert.equals(1.5, L.catch_mult(items.great_ball))
		assert.equals(2.0, L.catch_mult(items.ultra_ball))
		assert.equals(255.0, L.catch_mult(items.master_ball))
	end)

	it("is nil for a record that is not a ball", function()
		assert.is_nil(L.catch_mult(items.potion))
		assert.is_nil(L.catch_mult(nil))
	end)

	it("maps item names to ball ids and back", function()
		assert.equals("great_ball", L.ball_id("minemon:great_ball"))
		assert.equals("minemon:ultra_ball", L.item_name("ultra_ball"))
		assert.is_nil(L.ball_id("minemon:potion"))
		assert.is_nil(L.ball_id("minemon_party:party_ball"))
		assert.is_nil(L.ball_id(nil))
	end)
end)

describe("capture_logic odds", function()
	it("rounds the chance to whole percent and clamps it", function()
		assert.equals(26, L.odds_percent(0.257))
		assert.equals(100, L.odds_percent(1.5))
		assert.equals(0, L.odds_percent(-1))
		assert.equals(0, L.odds_percent(nil))
	end)

	it("colours the bands: green from 60, yellow from 25, red below", function()
		assert.equals("green", L.odds_band(100))
		assert.equals("green", L.odds_band(60))
		assert.equals("yellow", L.odds_band(59))
		assert.equals("yellow", L.odds_band(25))
		assert.equals("red", L.odds_band(24))
		assert.equals("red", L.odds_band(0))
	end)

	it("has a HUD colour per band", function()
		assert.equals(0x55FF55, L.ODDS_RGB.green)
		assert.equals(0xFFFF55, L.ODDS_RGB.yellow)
		assert.equals(0xFF5555, L.ODDS_RGB.red)
	end)

	it("writes the odds text", function()
		assert.equals("Catch ~42%", L.odds_text(42))
	end)
end)

describe("capture_logic tooltip and names", function()
	it("writes the catch rate line with the multiplier", function()
		assert.equals("Catch rate ×1", L.tooltip_line(1.0))
		assert.equals("Catch rate ×1.5", L.tooltip_line(1.5))
		assert.equals("Catch rate ×255", L.tooltip_line(255.0))
	end)

	it("title-cases the species name and prefers a nickname", function()
		assert.equals("Mr Mime", L.display_name("mr_mime", ""))
		assert.equals("Cyndaquil", L.display_name("cyndaquil", nil))
		assert.equals("Sparky", L.display_name("cyndaquil", "Sparky"))
	end)
end)

describe("capture_logic kit, messages and hits", function()
	it("gives the starter kit once, to a player with creatures", function()
		assert.is_true(L.kit_due(1, false))
		assert.is_false(L.kit_due(1, true))
		assert.is_false(L.kit_due(0, false))
		assert.equals(5, L.KIT_BALLS)
	end)

	it("has the messages of the capture sequence", function()
		assert.equals("Gotcha! Rattata was caught!", L.caught_line("Rattata"))
		assert.equals("Oh no! Rattata broke free!", L.broke_free_line("Rattata"))
		assert.equals("It's too strong — weaken it first!", L.too_strong_line())
		assert.equals("Pidgey was sent to the PC.", L.sent_to_pc_line("Pidgey"))
	end)

	it("drops a ball on anything that is not a wild creature", function()
		assert.equals("drop", L.hit_outcome(false, false))
		assert.equals("drop", L.hit_outcome(false, true))
	end)

	it("bounces off a wild creature that is not exhausted, and captures an exhausted one", function()
		assert.equals("bounce", L.hit_outcome(true, false))
		assert.equals("capture", L.hit_outcome(true, true))
	end)

	it("the shake check and the odds use the constants of the design", function()
		assert.equals(4, L.SHAKE_CHECKS)
		assert.equals(70, L.CAUGHT_BOND)
		assert.equals(0.25, L.ODDS_INTERVAL)
		assert.equals(24, L.ODDS_RANGE)
	end)
end)
