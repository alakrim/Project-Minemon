-- Unit tests for mods/minemon/minemon_creatures/dread_logic.lua and the Dread parts of capture_logic.lua (T-30, D-031),
-- pure logic, no Luanti. Covers: the spawn chance curve (origin, 750 nodes, 1500 and beyond), no Dread by day, no
-- Dread inside a ward, the level bump bounds and cap, the nametag, the shard count, the sting range, the ball
-- multipliers (Umbral Ball x3 against Dread, x0.5 otherwise, the other balls x0.75 against Dread) and the Dread bond.
-- luacheck: globals describe it assert

local here = debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$") or "."
local D = dofile(here .. "/../../mods/minemon/minemon_creatures/dread_logic.lua")
local C = dofile(here .. "/../../mods/minemon/minemon_capture/capture_logic.lua")

local NIGHT = 0.9
local DAY = 0.5

-- rng stand-in: float() returns the scripted value, int(a, b) returns b (the top of the range) unless ints is given.
local function scripted(float_value, int_value)
	return {
		float = function()
			return float_value
		end,
		int = function(_, _, b)
			if int_value ~= nil then
				return int_value
			end
			return b
		end,
	}
end

describe("dread_logic constants", function()
	it("matches the T-30 numbers", function()
		assert.equals(1 / 40, D.CHANCE_NEAR)
		assert.equals(1 / 12, D.CHANCE_FAR)
		assert.equals(1500, D.FAR_DISTANCE)
		assert.equals(5, D.LEVEL_BUMP_MIN)
		assert.equals(12, D.LEVEL_BUMP_MAX)
		assert.equals(100, D.LEVEL_CAP)
		assert.equals(20, D.HUNT_RANGE)
		assert.equals(16, D.STING_RANGE)
		assert.equals(20, D.DREAD_CAUGHT_BOND)
		assert.equals("#B0102A", D.NAMETAG_COLOUR)
		assert.equals(0.6, D.HURT_PITCH)
	end)
end)

describe("dread_logic.is_night", function()
	it("is night below 0.23 and above 0.77", function()
		assert.is_true(D.is_night(0.0))
		assert.is_true(D.is_night(0.22))
		assert.is_true(D.is_night(0.78))
		assert.is_true(D.is_night(0.9))
	end)

	it("is day from 0.23 to 0.77, both ends included", function()
		assert.is_false(D.is_night(0.23))
		assert.is_false(D.is_night(0.5))
		assert.is_false(D.is_night(0.77))
	end)
end)

describe("dread_logic.chance", function()
	it("is 1/40 at the origin at night", function()
		assert.is_true(math.abs(D.chance(0, NIGHT) - 1 / 40) < 1e-12)
	end)

	it("is the midpoint of 1/40 and 1/12 at 750 nodes", function()
		local mid = (1 / 40 + 1 / 12) / 2
		assert.is_true(math.abs(D.chance(750, NIGHT) - mid) < 1e-12)
	end)

	it("is 1/12 at 1500 nodes and stays there beyond", function()
		assert.is_true(math.abs(D.chance(1500, NIGHT) - 1 / 12) < 1e-12)
		assert.is_true(math.abs(D.chance(5000, NIGHT) - 1 / 12) < 1e-12)
	end)

	it("rises with the distance", function()
		assert.is_true(D.chance(100, NIGHT) < D.chance(900, NIGHT))
	end)

	it("is zero by day, at any distance", function()
		assert.equals(0, D.chance(0, DAY))
		assert.equals(0, D.chance(1500, DAY))
	end)
end)

describe("dread_logic.roll", function()
	it("is false inside a Sanctuary ward, even when the roll would pass", function()
		assert.is_false(D.roll(1500, NIGHT, true, scripted(0)))
	end)

	it("is false by day without drawing from the rng", function()
		local rng = { float = function() error("no draw by day") end }
		assert.is_false(D.roll(0, DAY, false, rng))
	end)

	it("passes when the draw is below the chance", function()
		assert.is_true(D.roll(0, NIGHT, false, scripted(0.0)))
		assert.is_true(D.roll(0, NIGHT, false, scripted(1 / 40 - 0.001)))
	end)

	it("fails when the draw is at or above the chance", function()
		assert.is_false(D.roll(0, NIGHT, false, scripted(1 / 40)))
		assert.is_false(D.roll(0, NIGHT, false, scripted(0.99)))
	end)

	it("uses the far chance beyond 1500 nodes", function()
		assert.is_true(D.roll(2000, NIGHT, false, scripted(1 / 12 - 0.001)))
		assert.is_false(D.roll(2000, NIGHT, false, scripted(1 / 12)))
	end)
end)

describe("dread_logic.dread_level", function()
	it("adds 5 to 12 levels", function()
		assert.equals(14, D.dread_level(9, scripted(0, 5)))
		assert.equals(21, D.dread_level(9, scripted(0, 12)))
	end)

	it("stays within the bump bounds for every draw of the range", function()
		local rng = scripted(0)
		local lo, hi = math.huge, -math.huge
		for bump = D.LEVEL_BUMP_MIN, D.LEVEL_BUMP_MAX do
			local lvl = D.dread_level(20, { float = rng.float, int = function() return bump end })
			lo = math.min(lo, lvl)
			hi = math.max(hi, lvl)
		end
		assert.equals(25, lo)
		assert.equals(32, hi)
	end)

	it("caps at 100", function()
		assert.equals(100, D.dread_level(98, scripted(0, 12)))
		assert.equals(100, D.dread_level(100, scripted(0, 5)))
	end)
end)

describe("dread_logic.nametag", function()
	it("prefixes Dread creatures", function()
		assert.equals("Dread Rattata Lv 14", D.nametag("Rattata Lv 14", true))
	end)

	it("leaves a normal nametag alone", function()
		assert.equals("Rattata Lv 14", D.nametag("Rattata Lv 14", false))
		assert.equals("Rattata Lv 14", D.nametag("Rattata Lv 14", nil))
	end)
end)

describe("dread_logic.shard_count and the sting range", function()
	it("drops 1 or 2 shards", function()
		assert.equals(1, D.shard_count(scripted(0, 1)))
		assert.equals(2, D.shard_count(scripted(0, 2)))
	end)

	it("stings within 16 nodes at night only", function()
		assert.is_true(D.in_sting_range(16, NIGHT))
		assert.is_false(D.in_sting_range(16.5, NIGHT))
		assert.is_false(D.in_sting_range(3, DAY))
	end)
end)

describe("capture_logic.ball_mult (Dread, D-031)", function()
	local dread = { dread = true }
	local normal = { dread = false }

	it("gives the Umbral Ball x3 against a Dread creature", function()
		assert.equals(3.0, C.ball_mult("umbral_ball", dread, 0.5))
	end)

	it("gives the Umbral Ball its base 0.5 against any other creature", function()
		assert.equals(0.5, C.ball_mult("umbral_ball", normal, 0.5))
		assert.equals(0.5, C.ball_mult("umbral_ball", nil, 0.5))
	end)

	it("weakens the other balls to x0.75 against a Dread creature", function()
		assert.equals(0.75, C.ball_mult("poke_ball", dread, 1.0))
		assert.equals(1.125, C.ball_mult("great_ball", dread, 1.5))
	end)

	it("leaves the other balls alone against a normal creature", function()
		assert.equals(1.5, C.ball_mult("great_ball", normal, 1.5))
		assert.equals(1.0, C.ball_mult("poke_ball", nil, 1.0))
	end)

	it("lists the Umbral Ball among the balls", function()
		assert.is_not_nil(C.ball_id("minemon:umbral_ball"))
		assert.equals("minemon:umbral_ball", C.item_name("umbral_ball"))
	end)
end)

describe("capture_logic.caught_bond (D-031)", function()
	it("gives a caught Dread creature bond 20", function()
		assert.equals(20, C.caught_bond({ dread = true }))
	end)

	it("gives any other catch bond 70", function()
		assert.equals(70, C.caught_bond({ dread = false }))
		assert.equals(70, C.caught_bond({}))
		assert.equals(70, C.caught_bond(nil))
	end)
end)

describe("wild_logic: a Dread creature hunts in 20 nodes (T-30, D-031)", function()
	local W = dofile(here .. "/../../mods/minemon/minemon_creatures/wild_logic.lua")

	-- A peaceful species that is Dread: aggressive, so it hunts the nearest player within DREAD_HUNT_RANGE.
	local function ctx(distance, dread)
		return {
			temperament = dread and "aggressive" or "peaceful",
			dread = dread,
			types = { "normal" },
			hp_frac = 1,
			is_night = true,
			player = "player",
			player_distance = distance,
			view_range = 12,
			now = 0,
			angry_until = 0,
		}
	end

	it("hunts a player at 15 nodes when Dread", function()
		assert.equals("hunt_player", W.decide(ctx(15, true)).action)
	end)

	it("does not hunt a player at 25 nodes, even when Dread", function()
		assert.equals("idle", W.decide(ctx(25, true)).action)
	end)

	it("leaves a normal peaceful creature idle at 15 nodes", function()
		assert.equals("idle", W.decide(ctx(15, false)).action)
	end)

	it("keeps the Dread hunt range at 20 nodes", function()
		assert.equals(20, W.DREAD_HUNT_RANGE)
	end)
end)
