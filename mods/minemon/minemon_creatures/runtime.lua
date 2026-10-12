-- minemon_creatures: runtime glue (T-24, D-027). The hooks mcl_mobs calls (do_custom, do_punch, deal_damage,
-- after_activate, on_die), the single damage path, the exhausted and faint states, and the brain chain.
-- The rules live in runtime_logic.lua (pure, busted-tested). defs.lua gives the temperament rule.
--
-- Why a guard replaces mcl's check_for_death (findings, VoxeLibre 0.92.3):
--  - Punches never reach deal_damage. mcl_mobs on_punch calls do_punch (combat.lua:538-542) and subtracts
--    self.health itself (combat.lua:701). do_punch returns false, so that subtraction is skipped and
--    damage goes through M.damage instead.
--  - Other paths subtract self.health and then call check_for_death: fall (physics.lua:986 via damage_mob),
--    fire, lava, drowning, suffocation, light (physics.lua:593-597, 722-776, 809-840). check_for_death is
--    called every step (physics.lua:1029 via check_dying), so the guard also reconciles HP each step.
--  - mcl's check_for_death clamps self.health to initial_properties.hp_max (physics.lua:482), which is not
--    our max HP, so the guard never calls the original while HP is above 0.
--  - mcl's death path removes the object (physics.lua:513-523, 552-586). The guard never lets HP reach
--    that path for our creatures.
--  - The engine removes a lua entity whose HP reaches 0 (luaentity_sao.cpp setHP), so the engine HP is kept
--    at 1 or more.
-- luacheck: read_globals core minemon mcl_mobs mcl_util vector

local MODPATH = core.get_modpath("minemon_creatures")
local LOGIC = dofile(MODPATH .. "/runtime_logic.lua")
local defs = dofile(MODPATH .. "/defs.lua")
local dread = dofile(MODPATH .. "/dread_logic.lua")
local dread_fx = dofile(MODPATH .. "/dread_fx.lua")

local M = {}

local TINT = "^[colorize:#ff000060" -- red damage tint (PLAN D-027)
local TINT_TIME = 0.2 -- seconds the tint stays
local FAINT_GRACE = 0.5 -- seconds a fainted owned creature may stay before it is removed
local PARTICLE_TEXTURE = "mcl_particles_smoke.png" -- VoxeLibre texture, used by mcl_mobs' own hit effects
local HURT_SOUND = "default_punch" -- VoxeLibre sound, used by mcl_mobs' punch fallback

local brains = {} -- { name, fn } in registration order
local brain_names = {}
local last_logged = {} -- brain name -> seconds of its last log line

-- The luaentity of one of our creatures, or nil.
local function ours(obj)
	if not obj then
		return nil
	end
	local le = obj:get_luaentity()
	if not le or type(le.name) ~= "string" or le.name:sub(1, #defs.PREFIX) ~= defs.PREFIX then
		return nil
	end
	if le._mm == nil then
		return nil
	end
	return le
end

local function owned(le)
	return (le.owner ~= nil and le.owner ~= "") or le.tamed == true
end

local function max_hp(le)
	return le.hp_max or le._mm.hp
end

-- Pushes the instance HP to the entity fields and the engine HP. The engine HP is at least 1, because the
-- engine removes a lua entity whose HP reaches 0.
local function write_hp(le)
	local hp = le._mm.hp
	le.health = hp
	le.old_health = hp
	le.object:set_hp(math.max(1, hp))
end

-- Stops horizontal movement and keeps the vertical velocity, so gravity still applies.
local function stop_moving(obj)
	local v = obj:get_velocity()
	if v then
		obj:set_velocity({ x = 0, y = v.y, z = 0 })
	end
end

local function hurt_effects(le)
	local obj = le.object
	le:add_texture_mod(TINT)
	core.after(TINT_TIME, function()
		if obj:is_valid() and not le._removed then
			le:remove_texture_mod(TINT)
		end
	end)
	local pos = obj:get_pos()
	if pos then
		mcl_mobs.effect(pos, 5, PARTICLE_TEXTURE, 1, 2, 2, nil)
	end
	-- A Dread creature cries lower (T-30): the same sound at pitch 0.6.
	local pitch = (le._mm and le._mm.dread == true) and dread.HURT_PITCH or 1.0
	core.sound_play(HURT_SOUND, { object = obj, max_hear_distance = 8, pitch = pitch }, true)
end

local function enter_exhausted(le)
	le._mm_exhausted = true
	le._mm_exhausted_t = LOGIC.EXHAUST_SECONDS
	le.state = "stand"
	le.attack = nil
	le.passive = true
	stop_moving(le.object)
	le.nametag = LOGIC.with_suffix(le.nametag)
	le:update_tag()
	le:set_animation("sit")
end

-- Passive as the temperament says. A wild Dread creature is never passive (T-30, D-031); an owned one keeps its
-- temperament.
local function base_passive(le)
	if le._mm.dread == true and not owned(le) then
		return false
	end
	local species = minemon.data.get_species(le._mm.species_id)
	return not (species ~= nil and defs.is_hostile(species.temperament))
end

-- Exhaustion over: passive from the temperament, 25% HP, flee (S-12 section 3).
local function recover(le)
	local inst = le._mm
	le._mm_exhausted = nil
	le._mm_exhausted_t = nil
	le.passive = base_passive(le)
	inst.hp = LOGIC.recovery_hp(max_hp(le))
	write_hp(le)
	le.nametag = LOGIC.without_suffix(le.nametag)
	le:update_tag()
	le.state = "runaway"
	le.runaway_timer = 0
	le:set_animation("stand")
end

local function exhausted_step(le, dtime)
	local left, done = LOGIC.tick_exhausted(le._mm_exhausted_t or LOGIC.EXHAUST_SECONDS, dtime)
	if done then
		recover(le)
		return
	end
	le._mm_exhausted_t = left
	le.state = "stand"
	le.attack = nil
	le.passive = true
	stop_moving(le.object)
	le:set_animation("sit")
end

-- Enraged over (after break_free): the temperament's passive state again. The brains run from the next step.
local function calm(le)
	le._mm_enraged_t = nil
	le.passive = base_passive(le)
	le.attack = nil
	le.state = "stand"
end

-- Faint: an owned creature at 0 HP. The creature_fainted handler (T-22) recalls it; if it is still there
-- after FAINT_GRACE seconds, it is removed here and a warning is logged.
local function faint(le)
	local obj = le.object
	le.attack = nil
	le.state = "stand"
	le.passive = true
	stop_moving(obj)
	minemon.events.fire("creature_fainted", obj, le.owner)
	core.after(FAINT_GRACE, function()
		if not obj:is_valid() or le._removed then
			return
		end
		core.log("warning", string.format("[minemon_creatures] fainted creature %s (owner %s) was still present "
			.. "after %.1f s; removed by minemon_creatures", tostring(le.name), tostring(le.owner), FAINT_GRACE))
		mcl_util.remove_entity(le)
	end)
end

-- Reconciles the entity HP with the instance HP. mcl_mobs may have changed self.health directly; the difference
-- is applied as damage or healing, so the instance stays the one place where HP is kept.
local function sync(le)
	local inst = le._mm
	local kind, amount = LOGIC.reconcile(le.health or inst.hp, inst.hp, max_hp(le))
	if kind == "damage" then
		M.damage(le.object, amount, nil, { source = "mcl" }) -- writes the HP itself
	elseif kind == "heal" then
		M.heal(le.object, amount) -- writes the HP itself
	elseif le.health ~= inst.hp then
		write_hp(le)
	end
end

-- The single damage path. Lowers the instance HP and the entity HP together (clamped at 0), shows the tint,
-- the particles and the hurt sound, and fires creature_hurt. Ignored while the creature is exhausted.
-- Returns the HP actually removed.
function M.damage(obj, amount, attacker, info)
	local le = ours(obj)
	if not le then
		return 0
	end
	local inst = le._mm
	local new_hp, dealt, reached_zero = LOGIC.damage_step(inst.hp, max_hp(le), amount, le._mm_exhausted == true)
	inst.hp = new_hp
	write_hp(le)
	if dealt > 0 then
		hurt_effects(le)
		minemon.events.fire("creature_hurt", obj, dealt, attacker, info)
	end
	if reached_zero then
		M.on_zero_hp(obj, attacker)
	end
	return dealt
end

-- Adds HP up to max. Returns the HP added. Exhausted creatures recover only by the timer, so heal does nothing
-- for them.
function M.heal(obj, amount)
	local le = ours(obj)
	if not le then
		return 0
	end
	local inst = le._mm
	local new_hp, added = LOGIC.heal_step(inst.hp, max_hp(le), amount, le._mm_exhausted == true)
	inst.hp = new_hp
	write_hp(le)
	return added
end

-- Called once when HP reaches 0 from above 0. Wild creatures become exhausted; owned creatures faint.
-- A wild creature that becomes exhausted fires creature_defeated(le, attacker) (D-030); attacker may be nil.
function M.on_zero_hp(obj, attacker)
	local le = ours(obj)
	if not le or le._mm_exhausted then -- already exhausted: no second defeat (W1 verdict)
		return
	end
	if LOGIC.zero_outcome(owned(le)) == "faint" then
		faint(le)
	else
		enter_exhausted(le)
		minemon.events.fire("creature_defeated", le, type(attacker) == "userdata" and attacker or nil)
	end
end

-- A failed capture (D-030): exhaustion ends as recover does (25% HP, suffix removed), then the creature does not flee.
-- It turns on the aggressor (mcl's attack state) for LOGIC.ENRAGE_SECONDS. Returns true, or false for a non-creature.
function M.break_free(obj, aggressor)
	local le = ours(obj)
	if le == nil then
		return false
	end
	if le._mm_exhausted then
		recover(le)
	end
	le.passive = false
	le._mm_enraged_t = LOGIC.ENRAGE_SECONDS
	if type(aggressor) == "userdata" and aggressor:is_valid() then
		le:do_attack(aggressor)
	end
	return true
end

function M.is_exhausted(obj)
	local le = ours(obj)
	return le ~= nil and le._mm_exhausted == true
end

function M.is_owned(obj)
	local le = ours(obj)
	return le ~= nil and owned(le)
end

function M.owner_name(obj)
	local le = ours(obj)
	if le and owned(le) then
		return le.owner
	end
	return nil
end

-- Registers a brain: fn(self, dtime) runs in do_custom, in registration order. See runtime_logic.run_chain
-- for the return values. Names are unique.
function M.register_brain(name, fn)
	assert(type(name) == "string" and name ~= "", "minemon.creatures: brain name must be a non-empty string")
	assert(type(fn) == "function", "minemon.creatures: brain must be a function")
	assert(not brain_names[name], "minemon.creatures: brain already registered: " .. name)
	brain_names[name] = true
	brains[#brains + 1] = { name = name, fn = fn }
end

local function log_brain_error(name, message)
	local now = core.get_us_time() / 1e6
	if LOGIC.should_log(last_logged[name], now, LOGIC.LOG_INTERVAL) then
		last_logged[name] = now
		core.log("error", string.format("[minemon_creatures] brain '%s' failed: %s", name, message))
	end
end

-- mcl_mobs do_custom hook. Syncs HP, then either runs the exhausted state (no brains, no default states), the
-- enraged state (no brains: mcl's default states run the attack set by break_free), or the brain chain.
-- Returns false to skip mcl's do_states, or nil.
function M.do_custom(self, dtime)
	if self._mm == nil then
		return nil
	end
	sync(self)
	dread_fx.sync(self)
	if self._mm_exhausted then
		exhausted_step(self, dtime)
		return false
	end
	if self._mm_enraged_t ~= nil then
		local left, done = LOGIC.tick_enraged(self._mm_enraged_t, dtime)
		if not done then
			self._mm_enraged_t = left
			return nil
		end
		calm(self)
	end
	return LOGIC.run_chain(brains, self, dtime, log_brain_error)
end

-- mcl_mobs do_punch hook. Runs after mcl's invulnerability and reach checks (combat.lua:512-520). Applies the
-- punch through M.damage and returns false, so mcl's own subtraction and knockback are skipped.
function M.do_punch(self, hitter, tflp, tool_caps, _dir)
	local groups = tool_caps and tool_caps.damage_groups
	local interval = tool_caps and tool_caps.full_punch_interval
	local raw = LOGIC.punch_damage(groups, self.object:get_armor_groups(), tflp, interval)
	local dealt = M.damage(self.object, raw, hitter, { source = "punch" })
	if dealt > 0 then
		self.invul_timestamp = core.get_us_time()
	end
	return false
end

-- mcl_mobs deal_damage hook (init.lua:351-378 calls it through mcl_util.deal_damage).
function M.deal_damage(self, damage, reason)
	reason = reason or {}
	M.damage(self.object, damage, reason.source or reason.direct, { source = "mcl", type = reason.type })
end

-- Replaces mcl_mobs' check_for_death for this entity: syncs HP and never lets mcl's death path run.
-- Installed as an instance field in after_activate.
local function guard(self, _cause, _cmi_cause, _info)
	if self.state == "die" then
		return true
	end
	if self._mm ~= nil then
		sync(self)
	end
	return false
end

-- Runs on every activation, after on_spawn. The instance is the authority: the entity HP is set from it.
function M.after_activate(self, _staticdata, _def, _dtime)
	if self._mm == nil then
		return
	end
	self.check_for_death = guard
	write_hp(self)
	if self._mm_exhausted then
		self.state = "stand"
		self.attack = nil
		self.passive = true
		stop_moving(self.object)
		self:set_animation("sit")
	elseif self._mm.dread == true and not owned(self) then
		self.passive = false -- a wild Dread creature is aggressive (T-30, D-031)
	end
end

-- Safety net: mcl's death path reached this entity (the guard should prevent it). The object is removed by mcl
-- right after this returns true. An owned creature fires creature_fainted first.
function M.on_die(self, _pos, _cause)
	if self._mm ~= nil then
		self._mm.hp = 0
		write_hp(self)
	end
	if owned(self) then
		M.on_zero_hp(self.object, nil)
	else
		core.log("warning", "[minemon_creatures] wild creature died through the mcl_mobs death path; removed")
	end
	return true
end

return M
