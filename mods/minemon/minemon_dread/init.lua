-- minemon_dread: the rewards and the night of the Dread variants (T-30, D-031). Glue only: the rules are in
-- minemon_creatures/dread_logic.lua (minemon.creatures.dread_rules). This mod registers the Dread Shard, drops shards
-- when a Dread creature is defeated, takes the wild Dread creatures at dawn ("it cannot bear the light") and plays a
-- sting once per creature when a player first comes near one at night. The coins (x3) are in minemon_sanctuary, and
-- the Umbral Ball in minemon_capture.
-- luacheck: read_globals core mcl_util vector
-- luacheck: globals minemon

local RULES = minemon.creatures.dread_rules
local PREFIX = "minemon_creatures:" -- the entity name prefix of every creature (defs.PREFIX)

local SHARD = "minemon:dread_shard"
local SOUND_STING = "mobs_mc_wither_spawn" -- VoxeLibre, a low sound, played quietly
local SOUND_HISS = "mobs_mc_cat_hiss" -- VoxeLibre, pitched down for the dawn
local SMOKE = "mcl_particles_smoke.png^[colorize:#1a0816:200" -- VoxeLibre smoke, darkened (as dread_fx.lua)
local PERIOD = 0.5 -- seconds between two dawn or sting checks

minemon.dread = minemon.dread or {}
local API = minemon.dread

-- The Dread Shard: a black-violet crystal (our generated icon, tools/gen_icons.py).
core.register_craftitem(":" .. SHARD, {
	description = "Dread Shard\nA cold shard of a corrupted creature. Four of them and an Ultra Ball make an Umbral Ball.",
	_doc_items_longdesc = "Dropped by Dread creatures. It is an ingredient of the Umbral Ball.",
	inventory_image = "minemon_dread_shard.png",
	stack_max = 64,
	groups = { craftitem = 1 },
})

-- The luaentity of one of our creatures, or nil.
local function ours(obj)
	local le = obj and obj:get_luaentity()
	if not le or type(le.name) ~= "string" or le.name:sub(1, #PREFIX) ~= PREFIX or le._mm == nil then
		return nil
	end
	return le
end

local function owned(le)
	return (le.owner ~= nil and le.owner ~= "") or le.tamed == true
end

-- A wild Dread creature that is still a threat: not owned, not defeated, not in a capture, and still here.
local function wild_dread(le)
	return le._mm.dread == true and not owned(le) and not le._mm_exhausted and not le._mm_capturing and not le._removed
end

-- True for a wild Dread creature that is still active (the tests use it).
function API.is_wild_dread(obj)
	local le = ours(obj)
	return le ~= nil and wild_dread(le)
end

-- Shard draws: a seeded RNG, so the drops are repeatable (CONVENTIONS: randomness).
local shard_rng = minemon.rng.new(7741)

-- A defeated Dread creature drops 1 or 2 shards where it lay (creature_defeated, D-031).
minemon.events.register("creature_defeated", function(victim_le, _attacker)
	if type(victim_le) ~= "table" or victim_le._mm == nil or victim_le._mm.dread ~= true then
		return
	end
	local obj = victim_le.object
	local pos = obj and obj:is_valid() and obj:get_pos()
	if not pos then
		return
	end
	core.add_item(pos, SHARD .. " " .. RULES.shard_count(shard_rng))
end)

-- A burst of dark smoke where a creature dissolves.
local function burst(pos)
	core.add_particlespawner({
		amount = 60,
		time = 0.4,
		minpos = { x = pos.x - 0.5, y = pos.y + 0.2, z = pos.z - 0.5 },
		maxpos = { x = pos.x + 0.5, y = pos.y + 1.2, z = pos.z + 0.5 },
		minvel = { x = -1.2, y = 0.6, z = -1.2 },
		maxvel = { x = 1.2, y = 2.0, z = 1.2 },
		minexptime = 0.8,
		maxexptime = 1.6,
		minsize = 3,
		maxsize = 7,
		texture = SMOKE,
	})
end

-- A wild Dread creature dissolves at dawn: smoke, a hiss, and the entity is removed (mcl_util.remove_entity).
-- Returns true when it was removed.
function API.dawn(le)
	local obj = le.object
	local pos = obj and obj:is_valid() and obj:get_pos()
	if not pos then
		return false
	end
	burst(pos)
	core.sound_play(SOUND_HISS, { pos = pos, max_hear_distance = 16, gain = 0.6, pitch = 0.7 }, true)
	mcl_util.remove_entity(le)
	return true
end

local dawn_timer = 0
core.register_globalstep(function(dtime)
	dawn_timer = dawn_timer + dtime
	if dawn_timer < PERIOD then
		return
	end
	dawn_timer = 0
	if RULES.is_night(core.get_timeofday()) then
		return
	end
	local doomed = {}
	for _, le in pairs(core.luaentities) do
		if type(le) == "table" and le._mm ~= nil and wild_dread(le) then
			doomed[#doomed + 1] = le
		end
	end
	for _, le in ipairs(doomed) do
		API.dawn(le)
	end
end)

-- The sting: a player who comes within STING_RANGE of a wild Dread creature at night hears it once per creature.
-- stung[player name][instance uid] = true. Kept in memory only: a restart may sting once more, which is harmless.
local stung = {}
local sting_timer = 0
core.register_globalstep(function(dtime)
	sting_timer = sting_timer + dtime
	if sting_timer < PERIOD then
		return
	end
	sting_timer = 0
	local t = core.get_timeofday()
	if not RULES.is_night(t) then
		return
	end
	for _, player in ipairs(core.get_connected_players()) do
		local name = player:get_player_name()
		local pp = player:get_pos()
		if pp then
			for _, obj in ipairs(core.get_objects_inside_radius(pp, RULES.STING_RANGE)) do
				local le = ours(obj)
				local opos = le and obj:get_pos()
				if le and opos and wild_dread(le) and RULES.in_sting_range(vector.distance(pp, opos), t) then
					stung[name] = stung[name] or {}
					local uid = le._mm.uid
					if not stung[name][uid] then
						stung[name][uid] = true
						core.sound_play(SOUND_STING, { to_player = name, gain = 0.35, pitch = 0.8 })
					end
				end
			end
		end
	end
end)
