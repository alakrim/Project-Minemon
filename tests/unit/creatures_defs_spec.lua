-- Unit tests for mods/minemon/minemon_creatures/defs.lua (pure logic, no Luanti).
-- Species records are copied from mods/minemon/minemon_core/data/species.json (only the fields defs.lua reads).
-- luacheck: globals describe it assert

local here = debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$") or "."
local D = dofile(here .. "/../../mods/minemon/minemon_creatures/defs.lua")

local SPECIES = {
	{ id = 1, name = "bulbasaur", types = { "grass", "poison" }, body_plan = "quadruped",
		size_class = "small", temperament = "peaceful", eldritch = false, catch_rate = 45,
		habitats = { "plains", "swamp" }, evolutions = { { to = 2 } },
		base_stats = { hp = 45, atk = 49, def = 49, spa = 65, spd = 65, spe = 45 } },
	{ id = 2, name = "ivysaur", types = { "grass", "poison" }, body_plan = "quadruped",
		size_class = "medium", temperament = "peaceful", eldritch = false, catch_rate = 45,
		habitats = { "plains", "swamp" }, evolutions = { { to = 3 } },
		base_stats = { hp = 60, atk = 62, def = 63, spa = 80, spd = 80, spe = 60 } },
	{ id = 3, name = "venusaur", types = { "grass", "poison" }, body_plan = "quadruped",
		size_class = "large", temperament = "peaceful", eldritch = false, catch_rate = 45,
		habitats = { "plains", "swamp" }, evolutions = {},
		base_stats = { hp = 80, atk = 82, def = 83, spa = 100, spd = 100, spe = 80 } },
	{ id = 4, name = "charmander", types = { "fire" }, body_plan = "biped",
		size_class = "small", temperament = "skittish", eldritch = false, catch_rate = 45,
		habitats = { "mountain" }, evolutions = { { to = 5 } },
		base_stats = { hp = 39, atk = 52, def = 43, spa = 60, spd = 50, spe = 65 } },
	{ id = 7, name = "squirtle", types = { "water" }, body_plan = "biped",
		size_class = "small", temperament = "skittish", eldritch = false, catch_rate = 45,
		habitats = { "beach", "water" }, evolutions = { { to = 8 } },
		base_stats = { hp = 44, atk = 48, def = 65, spa = 50, spd = 64, spe = 43 } },
	{ id = 16, name = "pidgey", types = { "normal", "flying" }, body_plan = "avian",
		size_class = "tiny", temperament = "skittish", eldritch = false, catch_rate = 255,
		habitats = { "forest" }, evolutions = { { to = 17 } },
		base_stats = { hp = 40, atk = 45, def = 40, spa = 35, spd = 35, spe = 56 } },
	{ id = 17, name = "pidgeotto", types = { "normal", "flying" }, body_plan = "avian",
		size_class = "medium", temperament = "territorial", eldritch = false, catch_rate = 120,
		habitats = { "forest" }, evolutions = { { to = 18 } },
		base_stats = { hp = 63, atk = 60, def = 55, spa = 50, spd = 50, spe = 71 } },
	{ id = 18, name = "pidgeot", types = { "normal", "flying" }, body_plan = "avian",
		size_class = "medium", temperament = "skittish", eldritch = false, catch_rate = 45,
		habitats = { "forest" }, evolutions = {},
		base_stats = { hp = 83, atk = 80, def = 75, spa = 70, spd = 70, spe = 101 } },
	{ id = 19, name = "rattata", types = { "normal" }, body_plan = "quadruped",
		size_class = "tiny", temperament = "aggressive", eldritch = false, catch_rate = 255,
		habitats = { "plains" }, evolutions = { { to = 20 } },
		base_stats = { hp = 30, atk = 56, def = 35, spa = 25, spd = 35, spe = 72 } },
	{ id = 25, name = "pikachu", types = { "electric" }, body_plan = "quadruped",
		size_class = "small", temperament = "peaceful", eldritch = false, catch_rate = 190,
		habitats = { "forest" }, evolutions = { { to = 26 } },
		base_stats = { hp = 35, atk = 55, def = 40, spa = 50, spd = 50, spe = 90 } },
	{ id = 26, name = "raichu", types = { "electric" }, body_plan = "biped",
		size_class = "small", temperament = "aggressive", eldritch = false, catch_rate = 75,
		habitats = { "forest" }, evolutions = {},
		base_stats = { hp = 60, atk = 90, def = 55, spa = 90, spd = 80, spe = 110 } },
	{ id = 92, name = "gastly", types = { "ghost", "poison" }, body_plan = "other",
		size_class = "medium", temperament = "territorial", eldritch = true, catch_rate = 190,
		habitats = { "cave", "swamp" }, evolutions = { { to = 93 } },
		base_stats = { hp = 30, atk = 35, def = 30, spa = 100, spd = 35, spe = 80 } },
	{ id = 131, name = "lapras", types = { "water", "ice" }, body_plan = "fish",
		size_class = "large", temperament = "peaceful", eldritch = true, catch_rate = 45,
		habitats = { "sea", "snow", "water" }, evolutions = {},
		base_stats = { hp = 130, atk = 85, def = 80, spa = 85, spd = 95, spe = 60 } },
	{ id = 143, name = "snorlax", types = { "normal" }, body_plan = "biped",
		size_class = "large", temperament = "peaceful", eldritch = true, catch_rate = 25,
		habitats = { "mountain" }, evolutions = {},
		base_stats = { hp = 160, atk = 110, def = 65, spa = 65, spd = 110, spe = 30 } },
	{ id = 95, name = "onix", types = { "rock", "ground" }, body_plan = "serpent",
		size_class = "colossal", temperament = "peaceful", eldritch = true, catch_rate = 45,
		habitats = { "cave", "desert" }, evolutions = { { to = 208 } },
		base_stats = { hp = 35, atk = 45, def = 160, spa = 30, spd = 45, spe = 70 } },
	{ id = 122, name = "mr_mime", types = { "psychic" }, body_plan = "biped",
		size_class = "medium", temperament = "aggressive", eldritch = false, catch_rate = 45,
		habitats = { "urban" }, evolutions = {},
		base_stats = { hp = 40, atk = 45, def = 65, spa = 100, spd = 120, spe = 90 } },
	{ id = 129, name = "magikarp", types = { "water" }, body_plan = "fish",
		size_class = "medium", temperament = "skittish", eldritch = false, catch_rate = 255,
		habitats = { "beach", "water" }, evolutions = { { to = 130 } },
		base_stats = { hp = 20, atk = 10, def = 55, spa = 15, spd = 20, spe = 80 } },
	{ id = 130, name = "gyarados", types = { "water", "flying" }, body_plan = "serpent",
		size_class = "colossal", temperament = "aggressive", eldritch = true, catch_rate = 45,
		habitats = { "beach", "water" }, evolutions = {},
		base_stats = { hp = 95, atk = 125, def = 79, spa = 60, spd = 100, spe = 81 } },
	{ id = 133, name = "eevee", types = { "normal" }, body_plan = "quadruped",
		size_class = "tiny", temperament = "skittish", eldritch = false, catch_rate = 45,
		habitats = { "urban" }, evolutions = { { to = 134 }, { to = 135 }, { to = 136 }, { to = 196 }, { to = 197 } },
		base_stats = { hp = 55, atk = 55, def = 50, spa = 45, spd = 65, spe = 55 } },
	{ id = 134, name = "vaporeon", types = { "water" }, body_plan = "quadruped",
		size_class = "medium", temperament = "territorial", eldritch = false, catch_rate = 45,
		habitats = { "urban", "water" }, evolutions = {},
		base_stats = { hp = 130, atk = 65, def = 60, spa = 110, spd = 95, spe = 65 } },
	{ id = 144, name = "articuno", types = { "ice", "flying" }, body_plan = "avian",
		size_class = "large", temperament = "territorial", eldritch = false, catch_rate = 3,
		habitats = { "rare", "snow" }, evolutions = {},
		base_stats = { hp = 90, atk = 85, def = 100, spa = 95, spd = 125, spe = 85 } },
	{ id = 145, name = "zapdos", types = { "electric", "flying" }, body_plan = "avian",
		size_class = "large", temperament = "aggressive", eldritch = false, catch_rate = 3,
		habitats = { "rare" }, evolutions = {},
		base_stats = { hp = 90, atk = 90, def = 85, spa = 125, spd = 90, spe = 100 } },
	{ id = 150, name = "mewtwo", types = { "psychic" }, body_plan = "biped",
		size_class = "large", temperament = "aggressive", eldritch = true, catch_rate = 3,
		habitats = { "rare" }, evolutions = {},
		base_stats = { hp = 106, atk = 110, def = 90, spa = 154, spd = 90, spe = 130 } },
	{ id = 151, name = "mew", types = { "psychic" }, body_plan = "biped",
		size_class = "small", temperament = "territorial", eldritch = false, catch_rate = 45,
		habitats = { "rare" }, evolutions = {},
		base_stats = { hp = 100, atk = 100, def = 100, spa = 100, spd = 100, spe = 100 } },
	{ id = 152, name = "chikorita", types = { "grass" }, body_plan = "quadruped",
		size_class = "medium", temperament = "peaceful", eldritch = false, catch_rate = 45,
		habitats = { "plains" }, evolutions = { { to = 153 } },
		base_stats = { hp = 45, atk = 49, def = 65, spa = 49, spd = 65, spe = 45 } },
	{ id = 155, name = "cyndaquil", types = { "fire" }, body_plan = "biped",
		size_class = "small", temperament = "skittish", eldritch = false, catch_rate = 45,
		habitats = { "plains" }, evolutions = { { to = 156 } },
		base_stats = { hp = 39, atk = 52, def = 43, spa = 60, spd = 50, spe = 65 } },
	{ id = 158, name = "totodile", types = { "water" }, body_plan = "biped",
		size_class = "small", temperament = "skittish", eldritch = false, catch_rate = 45,
		habitats = { "beach", "water" }, evolutions = { { to = 159 } },
		base_stats = { hp = 50, atk = 65, def = 64, spa = 44, spd = 48, spe = 43 } },
	{ id = 172, name = "pichu", types = { "electric" }, body_plan = "quadruped",
		size_class = "tiny", temperament = "territorial", eldritch = false, catch_rate = 190,
		habitats = { "forest" }, evolutions = { { to = 25 } },
		base_stats = { hp = 20, atk = 40, def = 15, spa = 35, spd = 35, spe = 60 } },
	{ id = 201, name = "unown", types = { "psychic" }, body_plan = "other",
		size_class = "small", temperament = "territorial", eldritch = true, catch_rate = 225,
		habitats = { "rare" }, evolutions = {},
		base_stats = { hp = 48, atk = 72, def = 48, spa = 72, spd = 48, spe = 48 } },
	{ id = 245, name = "suicune", types = { "water" }, body_plan = "quadruped",
		size_class = "large", temperament = "territorial", eldritch = false, catch_rate = 3,
		habitats = { "plains", "water" }, evolutions = {},
		base_stats = { hp = 100, atk = 75, def = 115, spa = 90, spd = 115, spe = 85 } },
	{ id = 249, name = "lugia", types = { "psychic", "flying" }, body_plan = "avian",
		size_class = "huge", temperament = "territorial", eldritch = true, catch_rate = 3,
		habitats = { "rare" }, evolutions = {},
		base_stats = { hp = 106, atk = 90, def = 130, spa = 90, spd = 154, spe = 110 } },
	{ id = 250, name = "ho_oh", types = { "fire", "flying" }, body_plan = "avian",
		size_class = "huge", temperament = "aggressive", eldritch = true, catch_rate = 3,
		habitats = { "rare" }, evolutions = {},
		base_stats = { hp = 106, atk = 130, def = 90, spa = 110, spd = 154, spe = 90 } },
	{ id = 251, name = "celebi", types = { "psychic", "grass" }, body_plan = "biped",
		size_class = "small", temperament = "territorial", eldritch = false, catch_rate = 45,
		habitats = { "forest" }, evolutions = {},
		base_stats = { hp = 100, atk = 100, def = 100, spa = 100, spd = 100, spe = 100 } },
}

local function by_id(id)
	for _, sp in ipairs(SPECIES) do
		if sp.id == id then
			return sp
		end
	end
	error("no fixture species " .. id)
end

local function close(a, b)
	return math.abs(a - b) < 1e-6
end

describe("creatures_defs key and names", function()
	it("key_for lowercases and turns non-alphanumerics into underscores", function()
		assert.equals("mr_mime", D.key_for("Mr. Mime"))
		assert.equals("mr_mime", D.key_for("mr_mime"))
		assert.equals("ho_oh", D.key_for("Ho-Oh"))
		assert.equals("nidoran_f", D.key_for("nidoran_f"))
		assert.equals("rattata", D.key_for({ name = "rattata" }))
	end)

	it("key_for gives the data's canonical names for display names (T-21b)", function()
		assert.equals("farfetchd", D.key_for("Farfetch'd"))
		assert.equals("nidoran_f", D.key_for("Nidoran♀"))
		assert.equals("nidoran_m", D.key_for("Nidoran♂"))
		assert.equals("mr_mime", D.key_for("Mr. Mime"))
		assert.equals("farfetchd", D.key_for({ name = "farfetchd" }))
		assert.equals("nidoran_f", D.key_for({ name = "nidoran_f" }))
	end)

	it("key_for of a display name matches the entity name of the species", function()
		assert.equals("minemon_creatures:farfetchd", D.entity_name({ name = D.key_for("Farfetch'd") }))
		assert.equals("minemon_creatures:nidoran_m", D.entity_name({ name = D.key_for("Nidoran♂") }))
	end)

	it("entity_name adds the minemon_creatures prefix", function()
		assert.equals("minemon_creatures:mr_mime", D.entity_name({ name = "mr_mime" }))
	end)

	it("display_name title-cases each word", function()
		assert.equals("Rattata", D.display_name(by_id(19)))
		assert.equals("Mr Mime", D.display_name(by_id(122)))
	end)

	it("nametag_text is 'Name Lv N'; the colour is red only for aggressive species", function()
		assert.equals("Rattata Lv 4", D.nametag_text(by_id(19), 4))
		assert.equals("#FF3030", D.nametag_color(by_id(19)))
		assert.equals("#FFFFFF", D.nametag_color(by_id(129)))
	end)
end)

describe("creatures_defs temperament and size", function()
	it("aggressive and territorial are hostile; skittish and peaceful are passive", function()
		assert.is_true(D.is_hostile("aggressive"))
		assert.is_true(D.is_hostile("territorial"))
		assert.is_false(D.is_hostile("skittish"))
		assert.is_false(D.is_hostile("peaceful"))
	end)

	it("an unknown temperament is an error", function()
		assert.has_error(function()
			D.is_hostile("grumpy")
		end)
	end)

	it("size_scale maps the six size classes", function()
		assert.equals(0.5, D.size_scale("tiny"))
		assert.equals(0.8, D.size_scale("small"))
		assert.equals(1.2, D.size_scale("medium"))
		assert.equals(1.8, D.size_scale("large"))
		assert.equals(2.6, D.size_scale("huge"))
		assert.equals(3.5, D.size_scale("colossal"))
		assert.has_error(function()
			D.size_scale("gigantic")
		end)
	end)
end)

describe("creatures_defs.build_def", function()
	it("Rattata (aggressive, tiny, quadruped) has the expected spawn class, mesh, texture and size", function()
		local d = D.build_def(by_id(19))
		assert.equals("hostile", d.spawn_class)
		assert.equals("animal", d.type)
		assert.is_false(d.passive)
		assert.equals("mesh", d.visual)
		assert.equals("mm_quadruped.glb", d.mesh)
		assert.are.same({ { "mm_type_normal.png" } }, d.textures)
		-- The brief says small, but species.json says tiny: the data wins.
		assert.is_true(close(d.visual_size.x, 0.5))
		assert.is_true(close(d.visual_size.y, 0.5))
		assert.is_true(close(d.collisionbox[5], 0.25))
		assert.equals(12 + 6, d.view_range)
		assert.is_false(d.fly)
		assert.is_nil(d.fly_in)
		assert.is_false(d.breathes_in_water)
		assert.equals(1 + math.floor(56 / 30), d.damage)
		assert.equals(2.5, d.reach)
		assert.are.same({}, d.drops)
		assert.is_true(d.can_despawn)
		assert.equals(2, d.spawn_in_group)
		assert.equals(2, d.spawn_in_group_min)
	end)

	it("Rattata is in a group of 2 or 3 (aggressive, tiny); Pidgey (skittish) and Gyarados (colossal) are not", function()
		local rattata = D.build_def(by_id(19))
		assert.equals(2, rattata.spawn_in_group)
		assert.equals(2, rattata.spawn_in_group_min)
		assert.equals(0, D.build_def(by_id(16)).spawn_in_group)
		assert.is_nil(D.build_def(by_id(16)).spawn_in_group_min)
		assert.equals(0, D.build_def(by_id(130)).spawn_in_group)
		assert.equals(0, D.build_def(by_id(25)).spawn_in_group)
	end)

	it("Rattata walk and run speeds follow spe", function()
		local d = D.build_def(by_id(19))
		assert.is_true(close(d.walk_velocity, 0.8 + 72 / 150))
		assert.is_true(close(d.run_velocity, 2 * (0.8 + 72 / 150)))
	end)

	it("Gyarados is serpent, aggressive and very large (colossal in the data, not large)", function()
		local d = D.build_def(by_id(130))
		assert.equals("mm_serpent.glb", d.mesh)
		assert.equals("hostile", d.spawn_class)
		assert.is_true(close(d.visual_size.x, 3.5))
		assert.equals(0, d.spawn_in_group)
	end)

	it("Magikarp is a fish: fly_in is water, it breathes water and does not fly", function()
		local d = D.build_def(by_id(129))
		assert.is_false(d.fly)
		assert.is_true(d.breathes_in_water)
		assert.is_true(d.passive)
		assert.equals("passive", d.spawn_class)
		local has_water = false
		for _, n in ipairs(d.fly_in) do
			if n == "mcl_core:water_source" then
				has_water = true
			end
		end
		assert.is_true(has_water)
	end)

	it("Pidgey is avian: it flies, and it is tiny and passive", function()
		local d = D.build_def(by_id(16))
		assert.is_true(d.fly)
		assert.equals("mm_avian.glb", d.mesh)
		assert.equals("passive", d.spawn_class)
		assert.is_true(close(d.visual_size.x, 0.5))
	end)

	it("the medium scale is 1.2 and the collision box scales with it", function()
		local d = D.build_def(by_id(122))
		assert.is_true(close(d.visual_size.x, 1.2))
		assert.is_true(close(d.collisionbox[1], -0.3))
		assert.is_true(close(d.collisionbox[4], 0.3))
		assert.is_true(close(d.collisionbox[5], 0.6))
	end)

	it("the animation ranges match the T-18 contract", function()
		local a = D.build_def(by_id(19)).animation
		assert.equals(0, a.stand_start)
		assert.equals(20, a.stand_end)
		assert.equals(21, a.walk_start)
		assert.equals(41, a.walk_end)
		assert.equals(42, a.run_start)
		assert.equals(52, a.run_end)
		assert.equals(53, a.punch_start)
		assert.equals(63, a.punch_end)
		assert.equals(64, a.die_start)
		assert.equals(74, a.die_end)
		assert.equals(75, a.sit_start)
		assert.equals(85, a.sit_end)
	end)

	it("the def holds data only (no functions), so the glue can add hooks", function()
		for _, sp in ipairs(SPECIES) do
			for k, v in pairs(D.build_def(sp)) do
				assert.is_not.equals("function", type(v), sp.name .. "." .. k)
			end
		end
	end)
end)

describe("creatures_defs.stages", function()
	local list = { by_id(16), by_id(17), by_id(18), by_id(172), by_id(25), by_id(26), by_id(133), by_id(134),
		by_id(1), by_id(2), by_id(3) }
	local stage = D.stages(list)

	it("counts evolutions: Pidgey 1, Pidgeotto 2, Pidgeot 3", function()
		assert.equals(1, stage[16])
		assert.equals(2, stage[17])
		assert.equals(3, stage[18])
	end)

	it("handles a baby chain and an Eevee branch: Pichu 1, Pikachu 2, Raichu 3, Eevee 1, Vaporeon 2", function()
		assert.equals(1, stage[172])
		assert.equals(2, stage[25])
		assert.equals(3, stage[26])
		assert.equals(1, stage[133])
		assert.equals(2, stage[134])
	end)

	it("Bulbasaur 1 and Venusaur 3", function()
		assert.equals(1, stage[1])
		assert.equals(3, stage[3])
	end)
end)

describe("creatures_defs.spawn_plan exclusions", function()
	it("legendaries, mythicals and Unown never spawn", function()
		for _, id in ipairs({ 144, 145, 150, 151, 201, 250, 249, 245, 251 }) do
			local plan, reason = D.spawn_plan(by_id(id), 1)
			assert.is_nil(plan, by_id(id).name)
			assert.equals("legendary_or_unown", reason)
		end
	end)

	it("starter families never spawn naturally", function()
		for _, id in ipairs({ 4, 7, 152, 155, 158 }) do
			local plan, reason = D.spawn_plan(by_id(id), 1)
			assert.is_nil(plan)
			assert.equals("starter", reason)
		end
	end)

	it("eldritch species spawn normally: Onix, Gastly, Gyarados, Lapras, Snorlax (T-21b)", function()
		for _, id in ipairs({ 95, 92, 130, 131, 143 }) do
			local plan, reason = D.spawn_plan(by_id(id), 1)
			assert.is_not_nil(plan, by_id(id).name .. " should spawn, got " .. tostring(reason))
		end
		assert.are.same({ "cave", "desert" }, D.spawn_plan(by_id(95), 1).habitats)
		assert.are.same({ "cave", "swamp" }, D.spawn_plan(by_id(92), 1).habitats)
	end)

	it("a species with only the rare habitat does not spawn", function()
		local plan, reason = D.spawn_plan({ id = 999, name = "ghost_test", catch_rate = 45, eldritch = false,
			habitats = { "rare" }, evolutions = {}, base_stats = {} }, 1)
		assert.is_nil(plan)
		assert.equals("no_habitat", reason)
	end)

	it("a normal species spawns with the level-2 minimum and its catch rate as weight", function()
		local plan = D.spawn_plan(by_id(19), 1)
		assert.equals(255, plan.chance)
		assert.equals(2, plan.min_level)
		assert.equals(1, plan.stage)
		assert.are.same({ "plains" }, plan.habitats)
	end)
end)

describe("creatures_defs minimum spawn level", function()
	it("unevolved needs level 2, stage 2 needs 16, stage 3 needs 30", function()
		assert.equals(2, D.min_spawn_level(1))
		assert.equals(16, D.min_spawn_level(2))
		assert.equals(30, D.min_spawn_level(3))
	end)

	it("an unknown stage is an error", function()
		assert.has_error(function()
			D.min_spawn_level(4)
		end)
	end)

	it("evolved forms spawn 4x rarer and need their stage's level", function()
		local list = { by_id(16), by_id(17), by_id(18) }
		local stage = D.stages(list)
		local p2 = D.spawn_plan(by_id(17), stage[17])
		local p3 = D.spawn_plan(by_id(18), stage[18])
		assert.equals(16, p2.min_level)
		assert.equals(30, p3.min_level)
		assert.equals(30, p2.chance)
		assert.equals(2, p3.chance)
	end)
end)

-- T-25c: visual_for (pack and stand-in paths), the animation table, the shiny roll.
local PACK_RATTATA = {
	mesh = "mmp_0019.glb", texture = "mmp_0019.png", texture_shiny = "mmp_0019_s.png",
	height = 0.6, width = 1.6, scale_hint = 1.6,
	anims = { stand = { 0, 20 }, walk = { 21, 41 }, run = { 42, 52 }, punch = { 53, 63 }, die = { 64, 74 },
		sit = { 75, 85 } },
}

describe("creatures_defs.visual_for without a pack entry (stand-ins)", function()
	it("Pikachu (small) uses the quadruped stand-in, its electric texture and the 0.8 scale", function()
		local v = D.visual_for(by_id(25), nil, false)
		assert.equals("mm_quadruped.glb", v.mesh)
		assert.are.same({ { "mm_type_electric.png" } }, v.textures)
		assert.is_true(close(v.visual_size.x, 0.8))
		assert.is_true(close(v.visual_size.y, 0.8))
		assert.is_true(close(v.visual_size.z, 0.8))
		assert.is_true(close(v.collisionbox[1], -0.2))
		assert.is_true(close(v.collisionbox[5], 0.4))
		assert.are.same(v.collisionbox, v.selectionbox)
	end)

	it("a nil shiny flag is not shiny; a shiny stand-in takes the shiny type texture", function()
		assert.are.same({ { "mm_type_electric.png" } }, D.visual_for(by_id(25), nil).textures)
		assert.are.same({ { "mm_type_electric_shiny.png" } }, D.visual_for(by_id(25), nil, true).textures)
	end)

	it("the stand-in collision box and visual size follow the size class", function()
		local v = D.visual_for(by_id(130), nil, false) -- colossal
		assert.is_true(close(v.visual_size.x, 3.5))
		assert.is_true(close(v.collisionbox[5], 1.75))
	end)
end)

describe("creatures_defs.visual_for with a pack entry", function()
	it("uses the pack mesh and texture at visual_size 1", function()
		local v = D.visual_for(by_id(19), PACK_RATTATA, false)
		assert.equals("mmp_0019.glb", v.mesh)
		assert.are.same({ { "mmp_0019.png" } }, v.textures)
		assert.is_true(close(v.visual_size.x, 1))
		assert.is_true(close(v.visual_size.y, 1))
		assert.is_true(close(v.visual_size.z, 1))
	end)

	it("the collision box is half the pack width each way, and the pack height up", function()
		local v = D.visual_for(by_id(19), PACK_RATTATA, false)
		assert.is_true(close(v.collisionbox[1], -0.8))
		assert.is_true(close(v.collisionbox[2], 0))
		assert.is_true(close(v.collisionbox[3], -0.8))
		assert.is_true(close(v.collisionbox[4], 0.8))
		assert.is_true(close(v.collisionbox[5], 0.6))
		assert.is_true(close(v.collisionbox[6], 0.8))
		assert.are.same(v.collisionbox, v.selectionbox)
	end)

	it("clamps the collision width to 0.3-3.0 and the height to 0.3-4.0", function()
		local wide = D.visual_for(by_id(1), { mesh = "a.glb", texture = "a.png", width = 4.331, height = 0.9 }, false)
		assert.is_true(close(wide.collisionbox[4], 1.5)) -- width 3.0 -> half 1.5
		local narrow = D.visual_for(by_id(1), { mesh = "a.glb", texture = "a.png", width = 0.1, height = 0.9 }, false)
		assert.is_true(close(narrow.collisionbox[4], 0.15)) -- width 0.3 -> half 0.15
		local tall = D.visual_for(by_id(1), { mesh = "a.glb", texture = "a.png", width = 1, height = 9 }, false)
		assert.is_true(close(tall.collisionbox[5], 4.0))
		local short = D.visual_for(by_id(1), { mesh = "a.glb", texture = "a.png", width = 1, height = 0.01 }, false)
		assert.is_true(close(short.collisionbox[5], 0.3))
	end)

	it("a shiny pack creature takes texture_shiny; a normal one takes texture", function()
		assert.are.same({ { "mmp_0019_s.png" } }, D.visual_for(by_id(19), PACK_RATTATA, true).textures)
		assert.are.same({ { "mmp_0019.png" } }, D.visual_for(by_id(19), PACK_RATTATA, false).textures)
	end)

	it("build_def with a pack entry takes the pack mesh, texture and size", function()
		local d = D.build_def(by_id(19), PACK_RATTATA)
		assert.equals("mmp_0019.glb", d.mesh)
		assert.are.same({ { "mmp_0019.png" } }, d.textures)
		assert.is_true(close(d.visual_size.x, 1))
		assert.is_true(close(d.collisionbox[5], 0.6))
		assert.is_true(close(d.initial_properties.collisionbox[5], 0.6))
		assert.equals("hostile", d.spawn_class) -- the temperament rules are unchanged
	end)

	it("build_def without a pack entry is the stand-in definition", function()
		local d = D.build_def(by_id(19), nil)
		assert.equals("mm_quadruped.glb", d.mesh)
		assert.is_true(close(d.visual_size.x, 0.5))
		assert.is_true(close(d.collisionbox[5], 0.25))
	end)
end)

describe("creatures_defs animation table", function()
	it("has the shared frame ranges, the T-18 speeds and no loop on punch, die and sit", function()
		local a = D.visual_for(by_id(25), nil, false).animation
		assert.equals(0, a.stand_start)
		assert.equals(85, a.sit_end)
		assert.equals(4, a.stand_speed)
		assert.equals(20, a.walk_speed)
		assert.equals(30, a.run_speed)
		assert.equals(14, a.punch_speed)
		assert.equals(10, a.die_speed)
		assert.equals(6, a.sit_speed)
		assert.is_false(a.punch_loop)
		assert.is_false(a.die_loop)
		assert.is_false(a.sit_loop)
		assert.is_nil(a.stand_loop)
		assert.is_nil(a.walk_loop)
		assert.is_nil(a.run_loop)
	end)

	it("the same ranges and speeds for a pack creature", function()
		local a = D.visual_for(by_id(19), PACK_RATTATA, false).animation
		assert.equals(21, a.walk_start)
		assert.equals(41, a.walk_end)
		assert.equals(20, a.walk_speed)
	end)

	it("each call returns a fresh table, so the glue can change one without touching another", function()
		local a = D.animation_table()
		a.walk_speed = 99
		assert.equals(20, D.animation_table().walk_speed)
	end)
end)

describe("creatures_defs shiny roll", function()
	it("rolls int(1, 512) and is shiny only on a 1", function()
		local seen = {}
		local rng = { int = function(_, a, b)
			seen[#seen + 1] = { a, b }
			return 1
		end }
		assert.is_true(D.roll_shiny(rng))
		assert.are.same({ 1, 512 }, seen[1])
		rng = { int = function() return 2 end }
		assert.is_false(D.roll_shiny(rng))
	end)

	it("the odds are 1 in 512", function()
		assert.equals(512, D.SHINY_ODDS)
	end)
end)
