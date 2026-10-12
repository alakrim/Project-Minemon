-- Unit tests for mods/minemon/minemon_creatures/wild_logic.lua (T-21b, pure logic, no Luanti).
-- Covers: every temperament against a player with or without an active creature, near or far, day or night, hurt or
-- not, and low HP; the anger times; the melee damage and bite period; the danger numbers for Rattata L3 and L5,
-- Spearow L4 and Raticate L20 (computed with minemon_core's Gen 2 stat formula at IV 8, bond 0).
-- luacheck: globals describe it assert

local here = debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$") or "."
local L = dofile(here .. "/../../mods/minemon/minemon_creatures/wild_logic.lua")
local F = dofile(here .. "/../../mods/minemon/minemon_core/formulas.lua")

local NOW = 1000
local P = { name = "player" } -- opaque targets: the logic only passes them through
local C = { name = "creature" }
local A = { name = "attacker" }

-- A context with the defaults of a peaceful, healthy creature alone in the day; over replaces fields.
-- The view range follows defs.lua: 18 for aggressive species (12 + 6), 12 for the rest.
local function ctx(over)
	local c = {
		temperament = "peaceful",
		types = { "normal" },
		hp_frac = 1,
		is_night = false,
		view_range = 12,
		now = NOW,
		angry_until = 0,
	}
	if over and over.temperament == "aggressive" then
		c.view_range = 18
	end
	for k, v in pairs(over or {}) do
		c[k] = v
	end
	return c
end

local function expect(result, action, target)
	assert.equals(action, result.action)
	if target ~= nil then
		assert.equals(target, result.target)
	end
end

local function close(a, b)
	return math.abs(a - b) < 1e-6
end

describe("wild_logic.is_night and anger_seconds", function()
	it("night is before 0.2 and after 0.8 of the day, as in spawning.lua", function()
		assert.is_true(L.is_night(0.1))
		assert.is_true(L.is_night(0.9))
		assert.is_false(L.is_night(0.2))
		assert.is_false(L.is_night(0.5))
		assert.is_false(L.is_night(0.8))
	end)

	it("angry seconds: 30 for the hostile temperaments and the skittish, 10 for peaceful", function()
		assert.equals(30, L.anger_seconds("aggressive"))
		assert.equals(30, L.anger_seconds("territorial"))
		assert.equals(30, L.anger_seconds("skittish"))
		assert.equals(10, L.anger_seconds("peaceful"))
		assert.equals(10, L.anger_seconds("grumpy"))
	end)
end)

describe("wild_logic aggressive", function()
	it("with no player near: idle", function()
		expect(L.decide(ctx({ temperament = "aggressive" })), "idle")
	end)

	it("a player in view and no creature out: hunt the player", function()
		expect(L.decide(ctx({ temperament = "aggressive", player = P, player_distance = 3 })), "hunt_player", P)
	end)

	it("a player in view with a creature within 16 nodes: fight that creature", function()
		local r = L.decide(ctx({ temperament = "aggressive", player = P, player_distance = 3,
			creature = C, creature_distance = 5 }))
		expect(r, "fight_creature", C)
	end)

	it("a player's creature farther than 16 nodes: hunt the player instead", function()
		local r = L.decide(ctx({ temperament = "aggressive", player = P, player_distance = 3,
			creature = C, creature_distance = 20 }))
		expect(r, "hunt_player", P)
	end)

	it("a player beyond the view range by day: idle", function()
		expect(L.decide(ctx({ temperament = "aggressive", player = P, player_distance = 25 })), "idle")
	end)

	it("the view range grows by 1.5 at night: a player at 25 is hunted", function()
		expect(L.decide(ctx({ temperament = "aggressive", player = P, player_distance = 25, is_night = true })),
			"hunt_player", P)
	end)

	it("a player beyond the night view range (18 x 1.5 = 27): idle", function()
		expect(L.decide(ctx({ temperament = "aggressive", player = P, player_distance = 30, is_night = true })),
			"idle")
	end)

	it("at night with a creature in range, the creature is fought at a long view distance", function()
		local r = L.decide(ctx({ temperament = "aggressive", player = P, player_distance = 25, is_night = true,
			creature = C, creature_distance = 10 }))
		expect(r, "fight_creature", C)
	end)

	it("being hurt changes nothing for an aggressive creature: it still hunts", function()
		local r = L.decide(ctx({ temperament = "aggressive", player = P, player_distance = 3,
			angry_until = NOW + 30, hurt_by = "creature" }))
		expect(r, "hunt_player", P)
	end)

	it("low HP by day: flee", function()
		expect(L.decide(ctx({ temperament = "aggressive", player = P, player_distance = 3, hp_frac = 0.1 })), "flee")
	end)

	it("low HP at night: fight to the end, so it still hunts", function()
		expect(L.decide(ctx({ temperament = "aggressive", player = P, player_distance = 3, hp_frac = 0.1,
			is_night = true })), "hunt_player", P)
	end)

	it("low HP at night with no player: idle, it does not flee (fights to the end)", function()
		expect(L.decide(ctx({ temperament = "aggressive", hp_frac = 0.1, is_night = true })), "idle")
	end)

	it("HP exactly at 0.2 is not low", function()
		expect(L.decide(ctx({ temperament = "aggressive", player = P, player_distance = 3, hp_frac = 0.2 })),
			"hunt_player", P)
	end)
end)

describe("wild_logic territorial", function()
	it("a player at 10 nodes, not hurt, by day: idle", function()
		expect(L.decide(ctx({ temperament = "territorial", player = P, player_distance = 10 })), "idle")
	end)

	it("a player within 5 nodes: hunt the player", function()
		expect(L.decide(ctx({ temperament = "territorial", player = P, player_distance = 4 })), "hunt_player", P)
	end)

	it("a player at 10 nodes but angry (hurt): hunt the player", function()
		expect(L.decide(ctx({ temperament = "territorial", player = P, player_distance = 10,
			angry_until = NOW + 30, hurt_by = "player" })), "hunt_player", P)
	end)

	it("the anger has run out: idle again", function()
		expect(L.decide(ctx({ temperament = "territorial", player = P, player_distance = 10,
			angry_until = NOW, hurt_by = "player" })), "idle")
	end)

	it("angry but the player is beyond the view range (12): idle", function()
		expect(L.decide(ctx({ temperament = "territorial", player = P, player_distance = 13,
			angry_until = NOW + 30 })), "idle")
	end)

	it("close, with a creature within 16 nodes: fight that creature", function()
		expect(L.decide(ctx({ temperament = "territorial", player = P, player_distance = 4,
			creature = C, creature_distance = 6 })), "fight_creature", C)
	end)

	it("a ghost type at night hunts a player at 10 nodes without being hurt", function()
		expect(L.decide(ctx({ temperament = "territorial", types = { "ghost", "poison" }, player = P,
			player_distance = 10, is_night = true })), "hunt_player", P)
	end)

	it("a ghost type by day, not hurt, at 10 nodes: idle", function()
		expect(L.decide(ctx({ temperament = "territorial", types = { "ghost" }, player = P,
			player_distance = 10 })), "idle")
	end)

	it("a poison type at night uses the aggressive view range (12 x 1.5 = 18)", function()
		expect(L.decide(ctx({ temperament = "territorial", types = { "poison" }, player = P, player_distance = 17,
			is_night = true })), "hunt_player", P)
	end)

	it("a normal type at night, not hurt, at 10 nodes: idle", function()
		expect(L.decide(ctx({ temperament = "territorial", types = { "normal" }, player = P, player_distance = 10,
			is_night = true })), "idle")
	end)

	it("low HP: flee", function()
		expect(L.decide(ctx({ temperament = "territorial", player = P, player_distance = 3, hp_frac = 0.05 })), "flee")
	end)
end)

describe("wild_logic skittish", function()
	it("a player at 6 nodes: flee", function()
		expect(L.decide(ctx({ temperament = "skittish", player = P, player_distance = 6 })), "flee")
	end)

	it("a player at 9 nodes: idle", function()
		expect(L.decide(ctx({ temperament = "skittish", player = P, player_distance = 9 })), "idle")
	end)

	it("hurt by a player with the player gone: flee", function()
		expect(L.decide(ctx({ temperament = "skittish", angry_until = NOW + 30, hurt_by = "player" })), "flee")
	end)

	it("hurt by something else: flee", function()
		expect(L.decide(ctx({ temperament = "skittish", angry_until = NOW + 30, hurt_by = "other" })), "flee")
	end)

	it("the hurt has expired: idle", function()
		expect(L.decide(ctx({ temperament = "skittish", angry_until = NOW - 1, hurt_by = "other" })), "idle")
	end)

	it("a player's creature near but the player far: idle", function()
		expect(L.decide(ctx({ temperament = "skittish", player = P, player_distance = 20, creature = C,
			creature_distance = 3 })), "idle")
	end)

	it("low HP: flee", function()
		expect(L.decide(ctx({ temperament = "skittish", hp_frac = 0.1 })), "flee")
	end)
end)

describe("wild_logic peaceful", function()
	it("a player at 2 nodes, not hurt: idle (peaceful creatures wander)", function()
		expect(L.decide(ctx({ temperament = "peaceful", player = P, player_distance = 2 })), "idle")
	end)

	it("hurt by a player: flee", function()
		expect(L.decide(ctx({ temperament = "peaceful", angry_until = NOW + 10, hurt_by = "player", player = P,
			player_distance = 2 })), "flee")
	end)

	it("hurt by a creature within 16 nodes: fight back against that creature, once", function()
		expect(L.decide(ctx({ temperament = "peaceful", angry_until = NOW + 10, hurt_by = "creature", attacker = A,
			attacker_distance = 5 })), "fight_creature", A)
	end)

	it("hurt by a creature beyond 16 nodes: flee", function()
		expect(L.decide(ctx({ temperament = "peaceful", angry_until = NOW + 10, hurt_by = "creature", attacker = A,
			attacker_distance = 20 })), "flee")
	end)

	it("the anger has run out after a creature's hit: idle", function()
		expect(L.decide(ctx({ temperament = "peaceful", angry_until = NOW, hurt_by = "creature", attacker = A,
			attacker_distance = 5 })), "idle")
	end)

	it("hurt by something else: flee", function()
		expect(L.decide(ctx({ temperament = "peaceful", angry_until = NOW + 10, hurt_by = "other" })), "flee")
	end)

	it("low HP after a creature's hit: flee, not fight", function()
		expect(L.decide(ctx({ temperament = "peaceful", angry_until = NOW + 10, hurt_by = "creature", attacker = A,
			attacker_distance = 5, hp_frac = 0.15 })), "flee")
	end)
end)

describe("wild_logic unknown temperament", function()
	it("is idle", function()
		expect(L.decide(ctx({ temperament = "grumpy", player = P, player_distance = 1 })), "idle")
	end)
end)

describe("wild_logic melee damage and bite period", function()
	it("melee damage is max(2, floor(1.5 + level*0.15 + atk/20 + 0.5))", function()
		assert.equals(2, L.melee_damage(1, 0))
		assert.equals(2, L.melee_damage(3, 8))
		assert.equals(3, L.melee_damage(5, 11))
		assert.equals(3, L.melee_damage(4, 10))
		assert.equals(6, L.melee_damage(20, 39))
	end)

	it("attack period is 1.2 - spe/200, at least 0.5", function()
		assert.is_true(close(L.attack_period(0), 1.2))
		assert.is_true(close(L.attack_period(9), 1.155))
		assert.is_true(close(L.attack_period(100), 0.7))
		assert.is_true(close(L.attack_period(200), 0.5))
		assert.is_true(close(L.attack_period(300), 0.5))
	end)

	it("the hunting run speed is +20%; otherwise the base speed", function()
		assert.is_true(close(L.run_speed(2, true), 2.4))
		assert.is_true(close(L.run_speed(2, false), 2))
	end)
end)

describe("wild_logic danger numbers (IV 8, bond 0, a 20 HP unarmoured player)", function()
	local IV8 = { hp = 8, atk = 8, def = 8, spa = 8, spd = 8, spe = 8 }

	-- Stats from the Gen 2 formula in minemon_core, with the species base stats from species.json.
	local function stats_of(base, level)
		return F.calc_stats(base, level, IV8, 0)
	end

	it("Rattata L3: atk 8, spe 9; 2 damage per bite, a bite every 1.155 s, 10 bites, 11.55 s", function()
		local st = stats_of({ hp = 30, atk = 56, def = 35, spa = 25, spd = 35, spe = 72 }, 3)
		assert.equals(8, st.atk)
		assert.equals(9, st.spe)
		local d = L.danger(3, st.atk, st.spe, 20)
		assert.equals(2, d.damage)
		assert.is_true(close(d.period, 1.155))
		assert.is_true(close(d.bites_per_s, 1 / 1.155))
		assert.equals(10, d.bites)
		assert.is_true(close(d.seconds, 11.55))
	end)

	it("two Rattata L3 bite together: about half the time of one", function()
		local st = stats_of({ hp = 30, atk = 56, def = 35, spa = 25, spd = 35, spe = 72 }, 3)
		local d = L.danger(3, st.atk, st.spe, 20)
		-- 2 creatures: 20 HP / (2 bites per period x 2 damage) = 5 periods.
		local periods = math.ceil(20 / (2 * d.damage))
		assert.equals(5, periods)
		assert.is_true(close(periods * d.period, 5.775))
	end)

	it("Rattata L5: atk 11, spe 12; 3 damage, a bite every 1.14 s, 7 bites, 7.98 s", function()
		local st = stats_of({ hp = 30, atk = 56, def = 35, spa = 25, spd = 35, spe = 72 }, 5)
		assert.equals(11, st.atk)
		assert.equals(12, st.spe)
		local d = L.danger(5, st.atk, st.spe, 20)
		assert.equals(3, d.damage)
		assert.is_true(close(d.period, 1.14))
		assert.equals(7, d.bites)
		assert.is_true(close(d.seconds, 7.98))
	end)

	it("Spearow L4: atk 10, spe 10; 3 damage, a bite every 1.15 s, 7 bites, 8.05 s", function()
		local st = stats_of({ hp = 40, atk = 60, def = 30, spa = 31, spd = 31, spe = 70 }, 4)
		assert.equals(10, st.atk)
		assert.equals(10, st.spe)
		local d = L.danger(4, st.atk, st.spe, 20)
		assert.equals(3, d.damage)
		assert.is_true(close(d.period, 1.15))
		assert.equals(7, d.bites)
		assert.is_true(close(d.seconds, 8.05))
	end)

	it("Raticate L20: atk 39, spe 45; 6 damage, a bite every 0.975 s, 4 bites, 3.9 s", function()
		local st = stats_of({ hp = 55, atk = 81, def = 60, spa = 50, spd = 70, spe = 97 }, 20)
		assert.equals(39, st.atk)
		assert.equals(45, st.spe)
		local d = L.danger(20, st.atk, st.spe, 20)
		assert.equals(6, d.damage)
		assert.is_true(close(d.period, 0.975))
		assert.equals(4, d.bites)
		assert.is_true(close(d.seconds, 3.9))
	end)
end)
