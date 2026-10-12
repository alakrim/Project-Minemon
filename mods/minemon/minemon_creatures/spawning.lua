-- minemon_creatures: natural spawning glue (T-21a). Registers mcl_mobs:spawn_setup entries, the level gate,
-- a local cap, and the sweep that removes wild creatures far from every player.
-- Why the sweep: a nametag blocks mcl_mobs despawn and is excluded from its spawn caps (mcl_mobs spawning.lua
-- lines 187-188 and 1231), and wild creatures carry "Name Lv N" nametags. Without the sweep and the local cap,
-- natural spawns would never stop.
-- luacheck: read_globals core minemon mcl_mobs mcl_util vector

local MODPATH = core.get_modpath("minemon_creatures")
local defs = dofile(MODPATH .. "/defs.lua")
local habitats = dofile(MODPATH .. "/habitats.lua")

local M = {}

local LOCAL_RADIUS = 32 -- nodes around a candidate position that are counted
local LOCAL_CAP = 6 -- wild creatures allowed inside LOCAL_RADIUS
local SWEEP_PERIOD = 5 -- seconds between sweeps
local DESPAWN_DISTANCE = 96 -- wild creatures farther than this from every player are removed

-- Seed from the node position, so a position gives the same level in the spawn gate and in on_spawn.
local function seed_for(pos)
	return core.hash_node_position(vector.round(pos)) % 2147483647
end

function M.rng_at(pos)
	return minemon.rng.new(seed_for(pos))
end

function M.is_night()
	local t = core.get_timeofday()
	return t < 0.2 or t > 0.8
end

-- Wild level at a position: distance from the origin in xz, night bonus, seeded jitter (D-026).
function M.level_at(pos)
	local dist = math.sqrt(pos.x * pos.x + pos.z * pos.z)
	return minemon.formulas.wild_level(dist, M.is_night(), M.rng_at(pos))
end

-- True for a loaded wild creature of ours: no owner and not tamed.
function M.is_wild(le)
	return type(le) == "table" and le.is_mob == true and type(le.name) == "string"
		and le.name:sub(1, #defs.PREFIX) == defs.PREFIX and le._mm ~= nil and not le.tamed
		and (le.owner == nil or le.owner == "")
end

function M.wild_nearby(pos, radius)
	local n = 0
	for _, obj in ipairs(core.get_objects_inside_radius(pos, radius or LOCAL_RADIUS)) do
		if M.is_wild(obj:get_luaentity()) then
			n = n + 1
		end
	end
	return n
end

-- check_position for mcl_mobs:spawn_setup: the level gate (S-12 section 2), then the local cap.
local function gate(min_level)
	return function(pos)
		-- Sanctuary wards (D-030): no wild spawn within 24 nodes of a sanctuary centre.
		if minemon.sanctuary and minemon.sanctuary.blocks_spawn and minemon.sanctuary.blocks_spawn(pos) then
			return false
		end
		if M.level_at(pos) < min_level then
			return false
		end
		return M.wild_nearby(pos) < LOCAL_CAP
	end
end

local gates = {} -- mob name -> the check_position it was registered with

-- One spawn_setup call per habitat entry (surface tags merged, see habitats.plan).
function M.register(name, plan)
	local check = gate(plan.min_level)
	gates[name] = check
	for _, entry in ipairs(habitats.plan(plan.habitats)) do
		mcl_mobs:spawn_setup({
			name = name,
			type_of_spawning = entry.type_of_spawning,
			biomes = entry.biomes,
			max_height = entry.max_height,
			chance = plan.chance,
			check_position = check,
		})
	end
end

-- True when the spawn gate of a registered mob passes at pos (the level gate, the local cap and the Sanctuary
-- ward). Integration tests use it, so a refused spawn is checked through the same gate mcl_mobs runs (T-28).
function M.gate_passes(name, pos)
	local check = gates[name]
	return check ~= nil and check(pos) == true
end

-- luacheck: globals minemon
minemon.creatures = minemon.creatures or {}
minemon.creatures.gate_passes = M.gate_passes

local function near_any(pos, players)
	for _, p in ipairs(players) do
		if vector.distance(pos, p) <= DESPAWN_DISTANCE then
			return true
		end
	end
	return false
end

-- Every SWEEP_PERIOD seconds: remove wild creatures that no player is near. Does nothing without players,
-- so a headless test world keeps the creatures it spawned.
local timer = 0
core.register_globalstep(function(dtime)
	timer = timer + dtime
	if timer < SWEEP_PERIOD then
		return
	end
	timer = 0
	local players = core.get_connected_players()
	if #players == 0 then
		return
	end
	local positions = {}
	for _, p in ipairs(players) do
		positions[#positions + 1] = p:get_pos()
	end
	local doomed = {}
	for _, le in pairs(core.luaentities) do
		if M.is_wild(le) then
			local pos = le.object:get_pos()
			if pos and not near_any(pos, positions) then
				doomed[#doomed + 1] = le
			end
		end
	end
	for _, le in ipairs(doomed) do
		mcl_util.remove_entity(le)
	end
end)

return M
