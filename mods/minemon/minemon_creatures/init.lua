-- minemon_creatures: one mcl_mobs mob per species (D-026, T-21a). Glue only. The rules live in defs.lua and
-- habitats.lua (pure) and spawning.lua (spawn glue). Health is custom: the instance holds it (self._mm.hp).
-- luacheck: read_globals core mcl_mobs
-- luacheck: globals minemon

local MODPATH = core.get_modpath("minemon_creatures")
local defs = dofile(MODPATH .. "/defs.lua")
local spawning = dofile(MODPATH .. "/spawning.lua")
local runtime = dofile(MODPATH .. "/runtime.lua")
local wild_brain = dofile(MODPATH .. "/wild_brain.lua")
local dread = dofile(MODPATH .. "/dread_logic.lua") -- Dread variants (T-30, D-031)
local dread_fx = dofile(MODPATH .. "/dread_fx.lua")

minemon.creatures = minemon.creatures or {}
local API = minemon.creatures

-- The pure Dread rules (T-30), for minemon_dread: the spawn roll, shard counts, the dawn and sting ranges.
API.dread_rules = dread

-- The generated Cobblemon pack's entry for a dex number, or nil (T-25c, D-029). The pack defines a global.
local function pack_entry(dex)
	local pack = rawget(_G, "minemon_pack")
	local models = pack and pack.models
	return models and models[dex] or nil
end

-- A wild creature is one without an owner and not tamed (T-30 uses it for the Dread hostility).
local function wild_entity(self)
	return (self.owner == nil or self.owner == "") and self.tamed ~= true
end

-- Sets the model, texture and collision box for the instance's shiny state (T-25c). mcl_mobs picks its own
-- texture at activation, so this runs from on_spawn and after_activate. The base texture is kept for the Dread look.
local function apply_visual(self, species)
	local inst = self._mm
	if inst == nil then
		return
	end
	local vis = defs.visual_for(species, pack_entry(species.id), inst.shiny == true)
	local base = vis.textures[1][1]
	self._mm_base_texture = base
	self.object:set_properties({
		mesh = vis.mesh,
		textures = { dread_fx.texture_for(base, inst.dread == true) }, -- the engine takes one flat list of names
		visual_size = vis.visual_size,
		collisionbox = vis.collisionbox,
		selectionbox = vis.selectionbox,
	})
end

-- Sets the instance's stats on the entity: HP, damage, nametag (and the object HP, which the engine ignores).
local function apply(self, species)
	local inst = self._mm
	local st = minemon.instance.stats(inst, species)
	local is_dread = inst.dread == true
	self.hp_max = st.hp
	self.health = inst.hp
	self.old_health = inst.hp
	self.damage = 1 + math.floor(st.atk / 25 + inst.level / 10)
	local props = { hp_max = st.hp }
	if wild_entity(self) then
		props.nametag_color = is_dread and dread.NAMETAG_COLOUR or defs.nametag_color(species)
		if is_dread then
			self.passive = false -- a wild Dread creature is aggressive whatever its temperament (D-031)
		end
	end
	self.object:set_properties(props)
	self.object:set_hp(inst.hp)
	self.nametag = dread.nametag(defs.nametag_text(species, inst.level), is_dread)
	self:update_tag()
end

-- Makes a wild creature Dread (T-30): the flag, a higher level, the Dread stats and the exp for that level. HP is full.
-- rng is a minemon.rng for the level bump.
local function set_dread(self, species, rng)
	local inst = self._mm
	inst.dread = true
	inst.level = dread.dread_level(inst.level, rng)
	inst.exp = minemon.formulas.exp_for_level(inst.level, species.growth_rate)
	inst.hp = minemon.instance.stats(inst, species).hp
end

-- on_spawn runs once per entity, after activation. A natural spawn has no instance yet: its level comes from
-- the position and is at least the stage's minimum (the spawn gate checks the same level at the spawn node).
-- A natural spawn is wild, so it rolls for shiny (T-25c).
local function make_on_spawn(species, min_level)
	return function(self)
		if self._mm == nil then
			local pos = self.object:get_pos()
			local level = math.max(spawning.level_at(pos), min_level)
			local rng = spawning.rng_at(pos)
			self._mm = minemon.instance.new(species, level, rng)
			self._mm.shiny = defs.roll_shiny(rng)
			-- The Dread roll (T-30, D-031): only at night, rarer near the origin, never inside a Sanctuary ward.
			local in_ward = minemon.sanctuary ~= nil and minemon.sanctuary.is_safe ~= nil
				and minemon.sanctuary.is_safe(pos) == true
			local dist = math.sqrt(pos.x * pos.x + pos.z * pos.z)
			if dread.roll(dist, core.get_timeofday(), in_ward, rng) then
				set_dread(self, species, rng)
			end
		end
		apply(self, species)
		apply_visual(self, species)
		return true
	end
end

-- after_activate runs on every activation, after on_spawn: the runtime hook first, then the visuals (T-25c).
local function make_after_activate(species)
	return function(self, staticdata, def, dtime)
		runtime.after_activate(self, staticdata, def, dtime)
		apply_visual(self, species)
	end
end

local function species_list()
	local out = {}
	for _, id in ipairs(minemon.data.all_species_ids()) do
		out[#out + 1] = minemon.data.get_species(id)
	end
	return out
end

local function register_all()
	local list = species_list()
	local stages = defs.stages(list)
	for _, sp in ipairs(list) do
		local stage = stages[sp.id]
		local name = defs.entity_name(sp)
		local def = defs.build_def(sp, pack_entry(sp.id))
		def.on_spawn = make_on_spawn(sp, defs.min_spawn_level(stage))
		-- Runtime hooks (T-24): brains, the single damage path, punches, death safety net.
		def.do_custom = runtime.do_custom
		def.do_punch = runtime.do_punch
		def.deal_damage = runtime.deal_damage
		def.after_activate = make_after_activate(sp)
		def.on_die = runtime.on_die
		mcl_mobs.register_mob(name, def)
		local plan = defs.spawn_plan(sp, stage)
		if plan then
			spawning.register(name, plan)
		end
	end
end

if minemon.data ~= nil then
	register_all()
end

-- Public API (PLAN.md M1 contract).

function API.key_for(species)
	return defs.key_for(species)
end

function API.entity_name(species)
	return defs.entity_name(species)
end

function API.get_instance(obj)
	local le = obj and obj:get_luaentity()
	if not le or type(le.name) ~= "string" or le.name:sub(1, #defs.PREFIX) ~= defs.PREFIX then
		return nil
	end
	return le._mm
end

-- Runtime API (T-24, D-027). The rules are in runtime_logic.lua; see runtime.lua for the hooks.

-- The single damage path: returns the HP removed. info = {move_id?, effectiveness?, crit?, source?, type?}.
API.damage = runtime.damage

-- Adds HP up to max; returns the HP added. Exhausted creatures do not heal.
API.heal = runtime.heal

-- Called when a creature's HP reaches 0: wild creatures become exhausted, owned creatures faint.
API.on_zero_hp = runtime.on_zero_hp

-- A failed capture (D-030, T-26): the exhausted creature breaks free and turns on the aggressor for 30 s.
API.break_free = runtime.break_free

function API.is_exhausted(obj)
	return runtime.is_exhausted(obj)
end

function API.is_owned(obj)
	return runtime.is_owned(obj)
end

function API.owner_name(obj)
	return runtime.owner_name(obj)
end

-- Brains run in do_custom in registration order. Return true to stop the chain (mcl default states still run),
-- "skip_states" to stop the chain and skip the default states, or nil to continue.
API.register_brain = runtime.register_brain

-- Wild brain (T-21b, D-009, D-026): aggressive, territorial, skittish and peaceful temperaments. It runs in the
-- brain chain and hears every hit on a wild creature. The rules are in wild_logic.lua; wild_brain.lua is the glue.
API.wild = wild_brain
API.register_brain("wild", wild_brain.think)
minemon.events.register("creature_hurt", wild_brain.on_hurt)

-- Makes an existing wild creature Dread (T-30). Used by the integration tests and by forced spawns. Returns true when
-- the creature is Dread afterwards, false for an entity that is not one of ours.
function API.make_dread(obj)
	local le = obj and obj:get_luaentity()
	if not le or type(le.name) ~= "string" or le.name:sub(1, #defs.PREFIX) ~= defs.PREFIX or le._mm == nil then
		return false
	end
	if le._mm.dread == true then
		return true
	end
	local species = minemon.data.get_species(le._mm.species_id)
	if species == nil then
		return false
	end
	set_dread(le, species, spawning.rng_at(obj:get_pos()))
	apply(le, species)
	apply_visual(le, species)
	return true
end

-- A wild creature (owner_name nil) despawns through the sweep in spawning.lua. An owned one is tamed,
-- persistent and never despawns.
function API.spawn(pos, species_id, level, owner_name)
	local species = minemon.data.get_species(species_id)
	if not species then
		return nil
	end
	level = level or spawning.level_at(pos)
	local rng = spawning.rng_at(pos)
	local inst = minemon.instance.new(species, level, rng)
	local staticdata = { _mm = inst }
	if owner_name and owner_name ~= "" then
		staticdata.owner = owner_name
		staticdata.tamed = true
		staticdata.persistent = true
		staticdata.can_despawn = false
	else
		-- A wild spawn rolls for shiny (T-25c). Owned spawns (captures) keep the instance's own flag.
		inst.shiny = defs.roll_shiny(rng)
	end
	return core.add_entity(pos, defs.entity_name(species), core.serialize(staticdata))
end
