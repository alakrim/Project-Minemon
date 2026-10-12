-- minemon_creatures: habitat tag to VoxeLibre biome names (pure; no core access).
-- Exact names come from .tools/voxelibre/mods/MAPGEN/mcl_biomes/init.lua; tests/fixtures/biomes.txt lists them.

local M = {}

-- Overworld base biomes (mcl_biomes overworld_biomes). Mapgen registers "<base>_ocean",
-- "<base>_deep_ocean" and "<base>_underground" for each of them.
M.OVERWORLD = {
	"IcePlains", "IcePlainsSpikes", "ColdTaiga", "ExtremeHills", "ExtremeHillsM", "ExtremeHills+",
	"Taiga", "MegaTaiga", "MegaSpruceTaiga", "StoneBeach", "Plains", "SunflowerPlains", "Forest",
	"FlowerForest", "BirchForest", "BirchForestM", "RoofedForest", "Swampland", "Jungle", "JungleM",
	"JungleEdge", "JungleEdgeM", "MushroomIsland", "Desert", "Savanna", "SavannaM", "Mesa", "MesaBryce",
	"MesaPlateauF", "MesaPlateauFM", "MangroveSwamp", "BambooJungle", "BambooJungleM", "BambooJungleEdge",
	"BambooJungleEdgeM",
}

local function suffixed(suffix)
	local out = {}
	for i, base in ipairs(M.OVERWORLD) do
		out[i] = base .. suffix
	end
	return out
end

-- Surface groups share one spawn entry per species (no double weight when two surface tags match).
M.GROUPS = {
	plains = { kind = "surface", biomes = { "Plains", "SunflowerPlains", "Savanna" } },
	forest = { kind = "surface", biomes = { "Forest", "FlowerForest", "BirchForest", "RoofedForest" } },
	mountain = {
		kind = "surface",
		biomes = { "ExtremeHills", "ExtremeHillsM", "ExtremeHills+", "ExtremeHills+_snowtop" },
	},
	desert = {
		kind = "surface",
		biomes = {
			"Desert", "Mesa", "MesaBryce", "MesaBryce_sandlevel", "MesaPlateauF", "MesaPlateauF_grasstop",
			"MesaPlateauF_sandlevel", "MesaPlateauFM", "MesaPlateauFM_grasstop", "MesaPlateauFM_sandlevel",
			"Mesa_sandlevel",
		},
	},
	snow = { kind = "surface", biomes = { "IcePlains", "ColdTaiga" } },
	swamp = { kind = "surface", biomes = { "Swampland", "MangroveSwamp" } },
	urban = { kind = "surface", biomes = { "Plains" } },
	beach = {
		kind = "surface",
		biomes = {
			"Plains_beach", "Forest_beach", "Taiga_beach", "FlowerForest_beach", "ExtremeHills_beach",
			"Savanna_beach", "ColdTaiga_beach",
		},
	},
	-- Underground: spawn on solid ground at height 0 or below (T-21a brief).
	cave = { kind = "cave", biomes = suffixed("_underground") },
	-- Rivers and oceans: shallow ocean water.
	water = { kind = "water", biomes = suffixed("_ocean") },
	-- Sea: deep ocean.
	sea = { kind = "water", biomes = suffixed("_deep_ocean") },
	-- No natural spawn.
	rare = { kind = "none", biomes = {} },
}

-- Every biome name any group can use (for the fixture test).
function M.all_names()
	local seen, out = {}, {}
	for _, g in pairs(M.GROUPS) do
		for _, name in ipairs(g.biomes) do
			if not seen[name] then
				seen[name] = true
				out[#out + 1] = name
			end
		end
	end
	table.sort(out)
	return out
end

-- Spawn entries for a list of habitat tags. Each entry is one mcl_mobs:spawn_setup call:
-- {group, type_of_spawning, max_height, biomes}. Surface tags merge into one entry.
function M.plan(tags)
	local entries, by_group = {}, {}
	for _, tag in ipairs(tags) do
		local g = M.GROUPS[tag]
		assert(g, "unknown habitat: " .. tostring(tag))
		if g.kind ~= "none" then
			local group = g.kind == "surface" and "surface" or tag
			local entry = by_group[group]
			if not entry then
				local type_of_spawning = "overworld"
				local max_height = nil
				if g.kind == "cave" then
					type_of_spawning = "ground"
					max_height = 0
				elseif g.kind == "water" then
					type_of_spawning = "water"
				end
				entry = { group = group, type_of_spawning = type_of_spawning, max_height = max_height, biomes = {} }
				by_group[group] = entry
				entries[#entries + 1] = entry
			end
			local present = {}
			for _, name in ipairs(entry.biomes) do
				present[name] = true
			end
			for _, name in ipairs(g.biomes) do
				if not present[name] then
					present[name] = true
					entry.biomes[#entry.biomes + 1] = name
				end
			end
		end
	end
	return entries
end

return M
