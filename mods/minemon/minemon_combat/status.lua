-- Status effects on creatures and players (T-23, T-31). Glue: the maths is in status_logic.lua and effects_logic.lua.
-- Two kinds of state, each in a bounded registry keyed by the object's guid (player name for players):
--  - the primary status, one per object: sleep, paralysis, burn, poison, freeze. The creature's instance keeps it in
--    inst.status, so it survives an unload (T-23b: restore_on_activate).
--  - volatile statuses, several at once and short: confusion, trap, leech seed, flinch, protect and the side buffs.
--    They are not saved; a reload clears them.
-- A creature's walk and run speed follow refresh_speed: the primary status, the spe stage, and trap (no running, so a
-- trapped creature cannot flee). A creature's nametag shows its status tag (EFX.with_status_tag).
-- luacheck: read_globals core minemon

local SL = dofile(core.get_modpath("minemon_combat") .. "/status_logic.lua")
local EFX = dofile(core.get_modpath("minemon_combat") .. "/effects_logic.lua")

local M = {}
local registry = SL.new_registry(SL.REGISTRY_CAP)
local vregistry = SL.new_registry(SL.REGISTRY_CAP)
local activated = setmetatable({}, { __mode = "k" }) -- luaentity -> true once its first tick ran

local function key_of(obj)
	return obj:get_guid()
end

-- Max HP of a creature (from its instance) or a player.
function M.max_hp(obj)
	if obj:is_player() then
		return 100
	end
	local inst = minemon.creatures.get_instance(obj)
	local sp = inst and minemon.data.get_species(inst.species_id)
	if inst and sp then
		return minemon.instance.stats(inst, sp).hp
	end
	return obj:get_properties().hp_max or 20
end

-- The primary status kind of obj, or "none".
function M.get(obj)
	if not obj or not obj:get_pos() then
		return "none"
	end
	local e = registry.get(key_of(obj))
	return e and e.record.kind or "none"
end

-- True when obj has the volatile kind now.
function M.has(obj, kind)
	if not obj or not obj:get_pos() then
		return false
	end
	local e = vregistry.get(key_of(obj))
	return e ~= nil and e.kinds[kind] ~= nil
end

local function volatile_set(obj)
	local set = {}
	local e = vregistry.get(key_of(obj))
	if e then
		for k in pairs(e.kinds) do
			set[k] = true
		end
	end
	return set
end

-- Walk and run speed of a creature: the primary status times the spe stage; running also stops while trapped. A
-- creature uses its saved base speeds (T-23b). A player only gets the paralysis physics speed.
function M.refresh_speed(obj)
	if not obj or not obj:get_pos() then
		return
	end
	local kind = M.get(obj)
	local inst = minemon.creatures.get_instance(obj)
	local le = obj:get_luaentity()
	if inst and le then
		inst.status = kind
		if le._mm_base_walk == nil then
			le._mm_base_walk = le.walk_velocity or 0
		end
		if le._mm_base_run == nil then
			le._mm_base_run = le.run_velocity or 0
		end
		local stage = (le._mm_stages and le._mm_stages.spe) or 0
		local walk = SL.speed_mult(kind) * minemon.formulas.stage_mult(stage)
		local run = walk * (M.has(obj, "trap") and 0 or 1)
		le.walk_velocity = le._mm_base_walk * walk
		le.run_velocity = le._mm_base_run * run
	elseif obj:is_player() then
		local p = obj:get_physics_override()
		p.speed = kind == "paralysis" and SL.PARALYSIS_SPEED or 1
		obj:set_physics_override(p)
	end
end

-- The status tag on the nametag (creatures only).
function M.refresh_tag(obj)
	local le = obj:get_luaentity()
	if not le or type(le.nametag) ~= "string" or not minemon.creatures.get_instance(obj) then
		return
	end
	local tag = EFX.tag_for(M.get(obj), volatile_set(obj))
	local text = EFX.with_status_tag(le.nametag, tag)
	if text ~= le.nametag then
		le.nametag = text
		le:update_tag()
	end
end

-- Sleep sits the creature down; waking stands it up, unless it is exhausted (it sits then too).
local function set_sleep_pose(obj, asleep)
	local le = obj:get_luaentity()
	if le and minemon.creatures.get_instance(obj) and not le._mm_exhausted then
		le:set_animation(asleep and "sit" or "stand")
	end
end

local function refresh(obj)
	M.refresh_speed(obj)
	M.refresh_tag(obj)
end

-- Gives obj a primary status. duration (optional) overrides a sleep's random length (rest: 5 s). Returns false when obj
-- already has one, or the kind is not in the primary set.
function M.apply(obj, kind, rng, duration)
	if not SL.is_minimal(kind) or not obj or not obj:get_pos() then
		return false
	end
	local key = key_of(obj)
	if registry.get(key) ~= nil then
		return false
	end
	if not registry.put(key, { obj = obj, record = SL.new_record(kind, rng, duration) }) then
		return false
	end
	if kind == "sleep" then
		set_sleep_pose(obj, true)
	end
	refresh(obj)
	return true
end

-- Registers a primary status again with a fresh duration (SL.restore_record). An unknown kind, or a full registry,
-- clears the status instead. Returns true when the status was registered.
function M.restore(obj, kind)
	if not obj or not obj:get_pos() then
		return false
	end
	local key = key_of(obj)
	if registry.get(key) ~= nil then
		return false
	end
	if SL.is_minimal(kind) and registry.put(key, { obj = obj, record = SL.restore_record(kind) }) then
		refresh(obj)
		return true
	end
	refresh(obj)
	return false
end

function M.clear(obj)
	local key = key_of(obj)
	if registry.get(key) == nil then
		return
	end
	local was = M.get(obj)
	registry.remove(key)
	if obj:get_pos() then
		if was == "sleep" then
			set_sleep_pose(obj, false)
		end
		refresh(obj)
	end
end

-- Gives obj a volatile status. An existing one is kept unless opts.refresh is set (side buffs and protect refresh).
-- opts: hurts (trap from a move with power), seeder (leech seed's user). Returns true when it was applied.
function M.apply_volatile(obj, kind, rng, opts)
	if not EFX.is_volatile(kind) or not obj or not obj:get_pos() then
		return false
	end
	opts = opts or {}
	local key = key_of(obj)
	local e = vregistry.get(key)
	if e == nil then
		e = { obj = obj, kinds = {} }
		if not vregistry.put(key, e) then
			return false
		end
	end
	if e.kinds[kind] ~= nil and not opts.refresh then
		return false
	end
	e.kinds[kind] = EFX.volatile_record(kind, rng, opts)
	refresh(obj)
	return true
end

-- Removes one volatile kind from obj.
function M.clear_volatile(obj, kind)
	local key = key_of(obj)
	local e = vregistry.get(key)
	if e == nil or e.kinds[kind] == nil then
		return
	end
	e.kinds[kind] = nil
	if next(e.kinds) == nil then
		vregistry.remove(key)
	end
	if obj:get_pos() then
		refresh(obj)
	end
end

-- Removes every volatile status from obj.
function M.clear_all_volatile(obj)
	vregistry.remove(key_of(obj))
	if obj:get_pos() then
		refresh(obj)
	end
end

-- The seeder of obj's leech seed, or nil.
function M.seeder_of(obj)
	local e = vregistry.get(key_of(obj))
	local rec = e and e.kinds.leech
	return rec and rec.seeder or nil
end

-- A fire move thaws a frozen target.
function M.thaw_on_fire(obj)
	if M.get(obj) == "freeze" then
		M.clear(obj)
	end
end

-- The "status_restore" brain (T-23b). Runs on the first tick of each activation, because the luaentity table is new
-- on every activation. If the instance says a status that the registry does not hold, the status is restored; a
-- status the registry already holds is left alone. Entries for removed objects are pruned by tick(): a removed
-- entity has no speed left to restore, and the saved staticdata carries the status for the next activation.
function M.restore_on_activate(le)
	if activated[le] then
		return
	end
	activated[le] = true
	local inst = le._mm
	local obj = le.object
	if not inst or inst.status == nil or inst.status == "none" or not obj or not obj:get_pos() then
		return
	end
	if M.get(obj) == "none" then
		M.restore(obj, inst.status)
	end
end

-- Advances every primary status by dt seconds (init.lua calls this every 0.5 s). damage_fn(obj, amount) applies burn
-- and poison damage. Removed objects are pruned first.
function M.tick(dt, rng, damage_fn)
	registry.prune(function(e)
		return e.obj:get_pos() ~= nil
	end)
	registry.each(function(_, e)
		local obj = e.obj
		local out = SL.advance(e.record, dt, rng, M.max_hp(obj))
		if out.damage > 0 then
			damage_fn(obj, out.damage)
		end
		if out.cured then
			M.clear(obj)
		end
	end)
end

-- Advances every volatile status by dt seconds: trap damage, leech drains, and expiry. damage_fn(obj, n) hurts obj;
-- drain_fn(seeder, victim, n) moves n HP from victim to seeder.
function M.tick_volatile(dt, damage_fn, drain_fn)
	vregistry.prune(function(e)
		return e.obj:get_pos() ~= nil
	end)
	vregistry.each(function(key, e)
		local obj = e.obj
		local max_hp = M.max_hp(obj)
		local kinds = {}
		for kind in pairs(e.kinds) do
			kinds[#kinds + 1] = kind
		end
		table.sort(kinds)
		local changed = false
		for _, kind in ipairs(kinds) do
			local rec = e.kinds[kind]
			if rec ~= nil then
				local out = EFX.advance_volatile(rec, dt, max_hp)
				if out.damage > 0 then
					damage_fn(obj, out.damage)
				end
				if out.drain > 0 and rec.seeder then
					drain_fn(rec.seeder, obj, out.drain)
				end
				if out.expired then
					e.kinds[kind] = nil
					changed = true
				end
			end
		end
		if next(e.kinds) == nil then
			vregistry.remove(key)
		end
		if changed and obj:get_pos() then
			refresh(obj)
		end
	end)
end

return M
