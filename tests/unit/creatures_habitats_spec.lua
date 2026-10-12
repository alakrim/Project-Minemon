-- Unit tests for mods/minemon/minemon_creatures/habitats.lua (pure) against the biome fixture generated from
-- VoxeLibre 0.92.3 MAPGEN/mcl_biomes/init.lua (tests/fixtures/biomes.txt).
-- luacheck: globals describe it assert

local here = debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$") or "."
local H = dofile(here .. "/../../mods/minemon/minemon_creatures/habitats.lua")

local function load_fixture()
	local f = assert(io.open(here .. "/../fixtures/biomes.txt", "r"))
	local set = {}
	for line in f:lines() do
		if line ~= "" and line:sub(1, 1) ~= "#" then
			set[line] = true
		end
	end
	f:close()
	return set
end

local FIXTURE = load_fixture()

local function entry_for(entries, group)
	for _, e in ipairs(entries) do
		if e.group == group then
			return e
		end
	end
	return nil
end

local function has(list, name)
	for _, v in ipairs(list) do
		if v == name then
			return true
		end
	end
	return false
end

describe("creatures_habitats names", function()
	it("every biome name the habitats use exists in the VoxeLibre fixture", function()
		local names = H.all_names()
		assert.is_true(#names > 100)
		for _, name in ipairs(names) do
			assert.is_true(FIXTURE[name] == true, "missing biome: " .. name)
		end
	end)

	it("every overworld base has ocean, deep ocean and underground variants", function()
		assert.equals(35, #H.OVERWORLD)
		for _, base in ipairs(H.OVERWORLD) do
			for _, suffix in ipairs({ "_ocean", "_deep_ocean", "_underground" }) do
				assert.is_true(FIXTURE[base .. suffix] == true, "missing " .. base .. suffix)
			end
		end
	end)

	it("the brief's Mesa, ExtremeHills and beach names are present", function()
		assert.is_true(FIXTURE["Mesa"] and FIXTURE["MesaPlateauF"] and FIXTURE["MesaBryce"])
		assert.is_true(FIXTURE["ExtremeHills"] and FIXTURE["ExtremeHillsM"] and FIXTURE["ExtremeHills+"])
		assert.is_true(FIXTURE["Plains_beach"] and FIXTURE["ColdTaiga_beach"])
	end)
end)

describe("creatures_habitats groups", function()
	it("every habitat tag in species.json is a known group", function()
		for _, tag in ipairs({ "plains", "water", "mountain", "forest", "swamp", "urban", "beach", "desert",
			"sea", "cave", "snow", "rare" }) do
			assert.is_not_nil(H.GROUPS[tag], tag)
		end
	end)

	it("rare has no biomes and is never planned", function()
		assert.are.same({}, H.GROUPS.rare.biomes)
		assert.are.same({}, H.plan({ "rare" }))
	end)

	it("an unknown habitat tag is an error", function()
		assert.has_error(function()
			H.plan({ "moon" })
		end)
	end)
end)

describe("creatures_habitats.plan", function()
	it("surface tags merge into one overworld entry without duplicate biomes", function()
		local entries = H.plan({ "plains", "urban", "forest" })
		assert.equals(1, #entries)
		local e = entries[1]
		assert.equals("overworld", e.type_of_spawning)
		assert.is_nil(e.max_height)
		assert.is_true(has(e.biomes, "Plains"))
		assert.is_true(has(e.biomes, "Savanna"))
		assert.is_true(has(e.biomes, "Forest"))
		local count = 0
		for _, name in ipairs(e.biomes) do
			if name == "Plains" then
				count = count + 1
			end
		end
		assert.equals(1, count)
	end)

	it("cave is underground: type ground, max height 0, underground biomes only", function()
		local e = entry_for(H.plan({ "cave" }), "cave")
		assert.equals("ground", e.type_of_spawning)
		assert.equals(0, e.max_height)
		assert.equals(35, #e.biomes)
		for _, name in ipairs(e.biomes) do
			assert.is_true(name:match("_underground$") ~= nil, name)
		end
	end)

	it("water uses shallow ocean biomes and sea uses deep ocean biomes, both as water spawns", function()
		local w = entry_for(H.plan({ "water" }), "water")
		local s = entry_for(H.plan({ "sea" }), "sea")
		assert.equals("water", w.type_of_spawning)
		assert.equals("water", s.type_of_spawning)
		assert.is_true(w.biomes[1]:match("_ocean$") ~= nil)
		assert.is_true(s.biomes[1]:match("_deep_ocean$") ~= nil)
	end)

	it("water and sea stay separate entries; surface and cave stay separate too", function()
		local entries = H.plan({ "water", "sea", "cave", "mountain", "desert" })
		assert.equals(4, #entries)
	end)

	it("beach is a surface group of beach biomes", function()
		local e = entry_for(H.plan({ "beach" }), "surface")
		assert.is_true(has(e.biomes, "Plains_beach"))
		assert.equals("overworld", e.type_of_spawning)
	end)

	it("desert covers Desert and the Mesa variants", function()
		local e = entry_for(H.plan({ "desert" }), "surface")
		assert.is_true(has(e.biomes, "Desert"))
		assert.is_true(has(e.biomes, "Mesa"))
		assert.is_true(has(e.biomes, "MesaPlateauFM_grasstop"))
	end)
end)
