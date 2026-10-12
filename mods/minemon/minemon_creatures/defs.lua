-- minemon_creatures: pure logic (no core access). Builds the mcl_mobs definition data from a species entry,
-- works out evolution stages and spawn plans. Busted-tested in tests/unit/creatures_defs_spec.lua.

local M = {}

M.PREFIX = "minemon_creatures:"

-- Size class to visual and collision scale (T-21a brief).
M.SIZE_SCALE = { tiny = 0.5, small = 0.8, medium = 1.2, large = 1.8, huge = 2.6, colossal = 3.5 }

-- Collision box at scale 1: half width 0.25, height 0.5.
local BASE_HALF_WIDTH = 0.25
local BASE_HEIGHT = 0.5

-- Animation ranges of the stand-in models (T-18): stand 0-20, walk 21-41, run 42-52, punch 53-63,
-- die 64-74, sit 75-85.
M.ANIMATION = {
	stand_start = 0, stand_end = 20,
	walk_start = 21, walk_end = 41,
	run_start = 42, run_end = 52,
	punch_start = 53, punch_end = 63,
	die_start = 64, die_end = 74,
	sit_start = 75, sit_end = 85,
}

-- Clip speeds in frames per second, as recommended by T-18 and used for the pack's clips (T-25c).
M.ANIMATION_SPEED = { stand = 4, walk = 20, run = 30, punch = 14, die = 10, sit = 6 }

-- Clips that play once and hold their last frame (T-18). Stand, walk and run loop.
M.ANIMATION_NO_LOOP = { punch = true, die = true, sit = true }

-- Collision box limits for the pack models, in nodes (T-25c). The width is the full width; the box is half each way.
M.PACK_WIDTH_RANGE = { 0.3, 3.0 }
M.PACK_HEIGHT_RANGE = { 0.3, 4.0 }

-- A wild creature is shiny with chance 1 in SHINY_ODDS (T-25c).
M.SHINY_ODDS = 512

-- Water nodes that fish swim in (VoxeLibre names, as in mobs_mc/cod.lua).
M.FISH_FLY_IN = { "mcl_core:water_source", "mclx_core:river_water_source" }

M.STAGE_MIN_LEVEL = { [1] = 2, [2] = 16, [3] = 30 }

-- Group size for small aggressive species: mcl_mobs spawns GROUP_SIZE, plus one more with a chance (2 or 3).
M.GROUP_SIZE = 2

-- Legendary and mythical species, and Unown, never spawn naturally (D-026, T-21a brief).
M.NO_SPAWN_NAMES = {
	articuno = true, zapdos = true, moltres = true, mewtwo = true, mew = true, raikou = true,
	entei = true, suicune = true, lugia = true, ho_oh = true, celebi = true, unown = true,
}

-- Starter families (Bulbasaur, Charmander, Squirtle, Chikorita, Cyndaquil, Totodile): no natural spawns.
M.STARTER_IDS = {
	[1] = true, [2] = true, [3] = true, [4] = true, [5] = true, [6] = true, [7] = true, [8] = true, [9] = true,
	[152] = true, [153] = true, [154] = true, [155] = true, [156] = true, [157] = true,
	[158] = true, [159] = true, [160] = true,
}

local HOSTILE_TEMPERAMENTS = { aggressive = true, territorial = true }
local KNOWN_TEMPERAMENTS = { aggressive = true, territorial = true, skittish = true, peaceful = true }

-- UTF-8 for the female and male signs (U+2640, U+2642), as in the display names "Nidoran♀" and "Nidoran♂".
local FEMALE_SIGN = "\226\153\128"
local MALE_SIGN = "\226\153\130"

-- Canonical lowercase key: the sexes become _f and _m, apostrophes go, and every other run of non-alphanumerics
-- becomes "_". "Mr. Mime" -> "mr_mime", "Farfetch'd" -> "farfetchd", "Nidoran♀" -> "nidoran_f" (the data's names).
function M.key_for(species)
	local name = type(species) == "table" and species.name or tostring(species)
	local key = string.lower(name)
	key = key:gsub(FEMALE_SIGN, "_f")
	key = key:gsub(MALE_SIGN, "_m")
	key = key:gsub("'", "")
	key = key:gsub("[^%w]+", "_")
	key = key:gsub("^_+", "")
	key = key:gsub("_+$", "")
	return key
end

function M.entity_name(species)
	return M.PREFIX .. M.key_for(species)
end

-- "mr_mime" -> "Mr Mime", "rattata" -> "Rattata".
function M.display_name(species)
	local parts = {}
	for word in species.name:gmatch("[^_]+") do
		parts[#parts + 1] = word:sub(1, 1):upper() .. word:sub(2)
	end
	return table.concat(parts, " ")
end

function M.size_scale(size_class)
	local s = M.SIZE_SCALE[size_class]
	assert(s, "unknown size_class: " .. tostring(size_class))
	return s
end

function M.is_hostile(temperament)
	assert(KNOWN_TEMPERAMENTS[temperament], "unknown temperament: " .. tostring(temperament))
	return HOSTILE_TEMPERAMENTS[temperament] == true
end

-- Nametag text, e.g. "Rattata Lv 4".
function M.nametag_text(species, level)
	return string.format("%s Lv %d", M.display_name(species), level)
end

-- Red for aggressive species, white for the rest (wild only; owned creatures keep the default colour).
function M.nametag_color(species)
	if species.temperament == "aggressive" then
		return "#FF3030"
	end
	return "#FFFFFF"
end

local function scaled_box(scale)
	local w = BASE_HALF_WIDTH * scale
	local h = BASE_HEIGHT * scale
	return { -w, 0, -w, w, h, w }
end

local function copy_box(box)
	return { box[1], box[2], box[3], box[4], box[5], box[6] }
end

local function clamp(v, range)
	assert(type(v) == "number", "pack entry size must be a number, got " .. tostring(v))
	return math.min(range[2], math.max(range[1], v))
end

-- The animation table of a creature: the shared frame ranges, the speeds and the loop flags. A fresh table.
function M.animation_table()
	local a = {}
	for k, v in pairs(M.ANIMATION) do
		a[k] = v
	end
	for name, speed in pairs(M.ANIMATION_SPEED) do
		a[name .. "_speed"] = speed
	end
	for name in pairs(M.ANIMATION_NO_LOOP) do
		a[name .. "_loop"] = false
	end
	return a
end

-- Visual data for one species (T-25c). pack_entry is minemon_pack.models[dex], or nil. shiny picks the shiny texture.
-- With a pack entry: the pack mesh and texture, visual_size 1 (the models are at true Cobblemon scale), and a
-- collision box from the pack's width and height. Without one: the stand-in mesh for the body plan, the type texture
-- and the size class scale. Returns { mesh, textures, visual_size, collisionbox, selectionbox, animation }.
function M.visual_for(species, pack_entry, shiny)
	assert(type(species) == "table", "species must be a table")
	shiny = shiny == true
	local animation = M.animation_table()
	if pack_entry then
		assert(type(pack_entry.mesh) == "string", "pack entry has no mesh")
		local texture = pack_entry.texture
		if shiny and pack_entry.texture_shiny then
			texture = pack_entry.texture_shiny
		end
		local half_width = clamp(pack_entry.width, M.PACK_WIDTH_RANGE) / 2
		local height = clamp(pack_entry.height, M.PACK_HEIGHT_RANGE)
		local box = { -half_width, 0, -half_width, half_width, height, half_width }
		return {
			mesh = pack_entry.mesh,
			textures = { { texture } },
			visual_size = { x = 1, y = 1, z = 1 },
			collisionbox = box,
			selectionbox = copy_box(box),
			animation = animation,
		}
	end
	local scale = M.size_scale(species.size_class)
	local box = scaled_box(scale)
	local texture = "mm_type_" .. species.types[1] .. (shiny and "_shiny" or "") .. ".png"
	return {
		mesh = "mm_" .. species.body_plan .. ".glb",
		textures = { { texture } },
		visual_size = { x = scale, y = scale, z = scale },
		collisionbox = box,
		selectionbox = copy_box(box),
		animation = animation,
	}
end

-- Whether a new wild creature is shiny: one roll in SHINY_ODDS. rng is a minemon.rng (rng:int(a, b)).
function M.roll_shiny(rng)
	return rng:int(1, M.SHINY_ODDS) == 1
end

-- The mcl_mobs definition data for one species. pack_entry is minemon_pack.models[dex] or nil (T-25c).
-- Hooks (on_spawn) are added by the glue in init.lua.
function M.build_def(species, pack_entry)
	assert(type(species) == "table", "species must be a table")
	local hostile = M.is_hostile(species.temperament)
	local aggressive = species.temperament == "aggressive"
	local fish = species.body_plan == "fish"
	local walk = 0.8 + species.base_stats.spe / 150
	local small = species.size_class == "tiny" or species.size_class == "small"
	local group = aggressive and small -- small aggressive species come in groups of 2 or 3 (T-21b)
	local vis = M.visual_for(species, pack_entry, false)
	local box = vis.collisionbox

	return {
		description = M.display_name(species),
		spawn_class = hostile and "hostile" or "passive",
		type = "animal",
		passive = not hostile,
		attack_type = "dogfight",
		visual = "mesh",
		mesh = vis.mesh,
		textures = vis.textures,
		visual_size = vis.visual_size,
		collisionbox = box,
		selectionbox = vis.selectionbox,
		-- mcl_mobs reads the collision box from initial_properties at activation (VoxeLibre pig.lua does the same).
		initial_properties = { collisionbox = box, selectionbox = vis.selectionbox },
		walk_velocity = walk,
		run_velocity = walk * 2,
		view_range = 12 + (aggressive and 6 or 0),
		fly = species.body_plan == "avian",
		fly_in = fish and M.FISH_FLY_IN or nil,
		breathes_in_water = fish,
		damage = 1 + math.floor(species.base_stats.atk / 30),
		reach = 2.5,
		animation = vis.animation,
		drops = {},
		can_despawn = true,
		-- mcl_mobs spawns spawn_in_group_min, plus one more with a chance: 2 or 3 creatures.
		spawn_in_group = group and M.GROUP_SIZE or 0,
		spawn_in_group_min = group and M.GROUP_SIZE or nil,
	}
end

-- Evolution stage per species id: 1 = no pre-evolution, 2 = evolved once, 3 = evolved twice.
function M.stages(list)
	local pre = {}
	for _, sp in ipairs(list) do
		for _, evo in ipairs(sp.evolutions or {}) do
			pre[evo.to] = sp.id
		end
	end
	local out = {}
	for _, sp in ipairs(list) do
		local depth, cur = 0, sp.id
		while pre[cur] and depth < 2 do
			cur = pre[cur]
			depth = depth + 1
		end
		out[sp.id] = depth + 1
	end
	return out
end

function M.min_spawn_level(stage)
	local lvl = M.STAGE_MIN_LEVEL[stage]
	assert(lvl, "unknown stage: " .. tostring(stage))
	return lvl
end

-- Spawn plan for a species, or nil and a reason. Evolved stages spawn 4x rarer (chance divided by 4 per stage).
-- chance is a selection weight for mcl_mobs: higher means more common, so it follows catch_rate.
-- The eldritch flag does not exclude a species: eldritch species spawn normally (T-21b; it only marks titans, M5).
function M.spawn_plan(species, stage)
	local key = M.key_for(species)
	stage = stage or 1
	if M.NO_SPAWN_NAMES[key] then
		return nil, "legendary_or_unown"
	end
	if M.STARTER_IDS[species.id] then
		return nil, "starter"
	end
	local habitats = {}
	for _, h in ipairs(species.habitats or {}) do
		if h ~= "rare" then
			habitats[#habitats + 1] = h
		end
	end
	if #habitats == 0 then
		return nil, "no_habitat"
	end
	local chance = math.max(1, math.floor(species.catch_rate / (4 ^ (stage - 1))))
	return {
		chance = chance,
		min_level = M.min_spawn_level(stage),
		stage = stage,
		habitats = habitats,
	}
end

return M
