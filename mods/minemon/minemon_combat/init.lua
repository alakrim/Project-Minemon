-- minemon_combat: real-time creature moves (T-23, M1 contract, fixed in T-23b, status pass in T-31). Glue only. The
-- rules are pure and busted-tested: moves_logic.lua (archetypes, validation), choose_logic.lua (move choice),
-- status_logic.lua (primary status maths and the bounded registry) and effects_logic.lua (volatile statuses, stage
-- decay, the mechanics of special moves). This file builds the context G, the public API, the cast brain and the
-- single globalstep. archetypes.lua has the six archetypes, status.lua the statuses, effects.lua the one-shot move
-- effects, vfx.lua the particles and HUD text and safe.lua the pcall wrapper for every callback.
-- luacheck: read_globals core vector mcl_util vl_projectile
-- luacheck: globals minemon

local MODPATH = core.get_modpath("minemon_combat")

local function load(name)
	return dofile(MODPATH .. "/" .. name .. ".lua")
end

local LOGIC = load("moves_logic")
local CHOOSE = load("choose_logic")
local SL = load("status_logic")
local EFX = load("effects_logic")
local VFX = load("vfx")
local STATUS = load("status")
local EFFECTS = load("effects")
local ARCH = load("archetypes")
local SAFE = load("safe")

minemon.combat = minemon.combat or {}
local API = minemon.combat

-- Seeded from the clock. The first Park-Miller draw of a small seed is near 0, so the seed is spread out.
local rng = minemon.rng.new(math.floor(core.get_us_time() % 2147483646) * 1000003 + 1)

local PLAYER_LEVEL = 20
local PLAYER_STATS = { hp = 100, atk = 60, def = 60, spa = 60, spd = 60, spe = 60 }
local PLAYER_HEIGHT = 1.7
local TICK_S = 0.5
local GREY_TEXT = 0xA0A0A0
local WHITE_TEXT = 0xFFFFFF

local G = {
	rng = rng,
	formulas = minemon.formulas,
	logic = LOGIC,
	vfx = VFX,
	status = STATUS,
	effects = EFFECTS,
	type_mult = minemon.data.type_multiplier,
}

-- Casts in progress, keyed by the user's luaentity: { move_id, target }. Kept out of the entity fields: mcl_mobs
-- saves every field, and a cast saved across a reload would block the creature forever (its timer is lost).
local casting = setmetatable({}, { __mode = "k" })

-- A creature's instance and luaentity, or nil for players and for anything that is not a creature.
local function creature_of(obj)
	if not obj or not obj:get_pos() or obj:is_player() then
		return nil, nil
	end
	local inst = minemon.creatures.get_instance(obj)
	if not inst then
		return nil, nil
	end
	return inst, obj:get_luaentity()
end

-- A player, or one of our creatures. Anything else (an item, an orb, a mob that is not ours) is not a valid target.
local function valid_target(obj)
	if not obj or not obj:get_pos() then
		return false
	end
	return obj:is_player() or creature_of(obj) ~= nil
end

-- The extended move (effects_logic.extend) for a move id, cached per raw move table.
local extended_cache = {}
local function extended(move_id, raw)
	local hit = extended_cache[move_id]
	if hit == nil or hit.raw ~= raw then
		hit = { raw = raw, move = EFX.extend(move_id, raw) }
		extended_cache[move_id] = hit
	end
	return hit.move
end

-- Turns obj to face target at once (yaw 0 faces +z, as G.forward). For a mcl mob the pending smooth turn is set to
-- the same yaw, so mcl does not turn back towards its own wander target.
function G.face(obj, target)
	local a, b = obj:get_pos(), target:get_pos()
	if not a or not b then
		return
	end
	local yaw = math.atan2(-(b.x - a.x), b.z - a.z)
	obj:set_yaw(yaw)
	local le = obj:get_luaentity()
	if le then
		le.target_yaw = yaw % (2 * math.pi)
		le.delay = 0
	end
end

function G.guid(obj)
	return obj:get_guid()
end

function G.height(obj)
	if obj:is_player() then
		return PLAYER_HEIGHT
	end
	local cb = obj:get_properties().collisionbox
	return (cb and cb[5]) or 0.5
end

-- The point at 80% of the body height, where beams start and end.
function G.eye(obj)
	return vector.add(obj:get_pos(), vector.new(0, G.height(obj) * 0.8, 0))
end

-- Horizontal unit vector the object faces (yaw 0 faces +z, as in Luanti).
function G.forward(obj)
	local yaw = obj:get_yaw()
	return vector.new(-math.sin(yaw), 0, math.cos(yaw))
end

function G.types_of(obj)
	if obj:is_player() then
		return { "normal" }
	end
	local inst = creature_of(obj)
	local sp = inst and minemon.data.get_species(inst.species_id)
	return (sp and sp.types) or { "normal" }
end

-- Current HP of a creature or a player.
function G.hp_of(obj)
	if obj:is_player() then
		return obj:get_hp()
	end
	local inst = creature_of(obj)
	return inst and inst.hp or 0
end

-- The attacker or defender view of formulas.damage (see PLAN.md, minemon.formulas.damage). hp is the current HP.
function G.view_of(obj)
	if obj:is_player() then
		return { level = PLAYER_LEVEL, stats = PLAYER_STATS, types = { "normal" }, status = STATUS.get(obj),
			stages = {}, hp = obj:get_hp() }
	end
	local inst, le = creature_of(obj)
	if not inst then
		return nil
	end
	local sp = minemon.data.get_species(inst.species_id)
	if not sp then
		return nil
	end
	return {
		level = inst.level,
		stats = minemon.instance.stats(inst, sp),
		types = sp.types,
		status = STATUS.get(obj),
		stages = le._mm_stages or {},
		hp = inst.hp,
	}
end

-- A creature that is alive, or a player with HP.
function G.is_combatant(obj)
	if not obj or not obj:get_pos() then
		return false
	end
	if obj:is_player() then
		return obj:get_hp() > 0
	end
	local inst, le = creature_of(obj)
	return inst ~= nil and le ~= nil and inst.hp > 0 and not le._removed
end

-- The user itself, and its owner's creatures and owner player. Wild creatures have no friends.
function G.is_friend(user, obj)
	if G.guid(obj) == G.guid(user) then
		return true
	end
	local ule = user:get_luaentity()
	local owner = ule and ule.owner
	if owner == nil or owner == "" then
		return false
	end
	if obj:is_player() then
		return obj:get_player_name() == owner
	end
	local ole = obj:get_luaentity()
	return ole ~= nil and ole.owner == owner
end

function G.roll(percent)
	return rng:float() * 100 < percent
end

function G.animate(obj, clip)
	local le = obj:get_luaentity()
	local a = le and le.animation
	if a and a[clip .. "_start"] then
		obj:set_animation({ x = a[clip .. "_start"], y = a[clip .. "_end"] }, 15, 0, false)
	end
end

-- Damage through minemon.creatures.damage (T-24) when it exists. Until then, mcl_util.deal_damage, which runs the
-- mob's own damage path, and the instance HP is synced to the entity health afterwards. A sleeping creature is not
-- woken by damage (T-31, as in Gen 2).
function G.apply_damage(victim, amount, user, info)
	amount = math.floor(amount)
	if amount <= 0 then
		return
	end
	if victim:is_player() then
		local p = LOGIC.player_damage(amount)
		if user then
			victim:punch(user, 1.0, { full_punch_interval = 1, damage_groups = { fleshy = p } })
		else
			mcl_util.deal_damage(victim, p, { type = "generic" })
		end
		return
	end
	if minemon.creatures.damage then
		minemon.creatures.damage(victim, amount, user, info)
		return
	end
	local reason = user and { type = "mob", source = user } or { type = "generic" }
	mcl_util.deal_damage(victim, amount, reason)
	local inst, le = creature_of(victim)
	if inst and le and type(le.health) == "number" then
		inst.hp = math.max(0, math.floor(le.health))
	end
end

-- Adds HP up to max (creatures through the creature API, players directly). Returns the HP added.
function G.heal_obj(obj, amount)
	amount = math.floor(amount or 0)
	if amount <= 0 or not obj or not obj:get_pos() then
		return 0
	end
	if obj:is_player() then
		local hp = obj:get_hp()
		local new = math.min(PLAYER_STATS.hp, hp + amount)
		obj:set_hp(new)
		return new - hp
	end
	return minemon.creatures.heal(obj, amount) or 0
end

-- Raises or lowers a stat stage of a creature. A drop is refused while the creature has Mist. Returns true when the
-- stage was set.
function G.apply_stage(obj, stat, stages)
	local inst, le = creature_of(obj)
	if not inst then
		return false
	end
	if EFX.blocks_drop(stages, STATUS.has(obj, "mist")) then
		G.feedback_near(obj:get_pos(), EFX.TEXT.mist_blocks, GREY_TEXT)
		return false
	end
	le._mm_stages = le._mm_stages or {}
	le._mm_stages[stat] = LOGIC.clamp_stage((le._mm_stages[stat] or 0) + stages)
	EFFECTS.note_stages(le)
	STATUS.refresh_speed(obj)
	return true
end

-- Gives obj a status by kind: a primary one (sleep, paralysis, burn, poison, freeze) or a volatile one (confusion,
-- trap, leech, flinch, protect and the side buffs). opts: duration (primary sleep), hurts, seeder, refresh. Leech
-- seed does not take on a grass type. Returns true when the status was given; it shows the text and a burst.
function G.apply_kind(obj, kind, opts)
	opts = opts or {}
	if not obj or not obj:get_pos() then
		return false
	end
	local applied = false
	if SL.is_minimal(kind) then
		applied = STATUS.apply(obj, kind, G.rng, opts.duration)
	elseif EFX.is_volatile(kind) then
		local immune = kind == "leech" and EFX.seed_immune(G.types_of(obj))
		applied = (not immune) and STATUS.apply_volatile(obj, kind, G.rng, opts)
	end
	if applied then
		local text = EFX.STATUS_TEXT[kind]
		if text then
			G.feedback_near(obj:get_pos(), text, WHITE_TEXT)
		end
		VFX.burst(G.eye(obj), EFX.kind_type(kind), "puff", 0.6, 0.3)
	end
	return applied
end

-- Effectiveness text for every player within FEEDBACK_RANGE_M of pos.
function G.feedback_near(pos, text, colour)
	if not pos or not text then
		return
	end
	for _, player in ipairs(core.get_connected_players()) do
		local pp = player:get_pos()
		if pp and vector.distance(pp, pos) <= VFX.FEEDBACK_RANGE_M then
			VFX.feedback(player, text, colour)
		end
	end
end

function G.has_volatile(obj, kind)
	return STATUS.has(obj, kind)
end

ARCH.register_orb(G)

local function now()
	return core.get_gametime()
end

local function on_cooldown_le(le, move_id)
	local ready = le and le._mm_cooldown and le._mm_cooldown[move_id]
	return ready ~= nil and now() < ready
end

local function find_slot(inst, move_id)
	for _, slot in ipairs(inst.moves or {}) do
		if slot.id == move_id then
			return slot
		end
	end
	return nil
end

local function in_range(user, target, move)
	return vector.distance(user:get_pos(), target:get_pos()) <= move.range_m + LOGIC.RANGE_SLACK
end

local function is_owned(inst, le)
	return (inst.owner ~= nil and inst.owner ~= "") or (le.owner ~= nil and le.owner ~= "")
end

-- Runs when the cast time ends. A flinched user's cast is cancelled. A confused user that turned on itself hurts
-- itself instead. Otherwise the target is checked again: it must still be a valid target and in range. The user turns
-- to it once more, so the melee check uses the facing at execution.
local function finish_cast(user, target, move_id, move, confused)
	local le = user:get_luaentity()
	if le then
		casting[le] = nil
	end
	if not user:get_pos() or not creature_of(user) then
		return
	end
	if STATUS.has(user, "flinch") then
		G.feedback_near(G.eye(user), EFX.TEXT.flinched, GREY_TEXT)
		return
	end
	if confused then
		EFFECTS.self_hit(G, user)
		return
	end
	local needs_target = LOGIC.needs_target(move.archetype)
	if needs_target then
		if not valid_target(target) then
			return
		end
		if LOGIC.needs_range(move.archetype) and not in_range(user, target, move) then
			return
		end
		G.face(user, target)
	end
	ARCH.fire(G, move.archetype, user, target, move_id, move)
	EFFECTS.on_cast(G, user, target, move)
end

-- The "combat_cast" brain (T-23b). While a cast runs, the user faces its target every tick and stands still. The
-- chain returns "skip_states", so mcl's wander turns and walks do not run during the cast.
local function cast_brain(self, _dtime)
	local cast = casting[self]
	if cast == nil then
		return nil
	end
	local user = self.object
	if not user or not user:get_pos() then
		return nil
	end
	if cast.target and valid_target(cast.target) then
		G.face(user, cast.target)
	end
	local v = user:get_velocity()
	if v then
		user:set_velocity({ x = 0, y = v.y, z = 0 })
	end
	return "skip_states"
end

-- The "status_restore" brain (T-23b). The first tick of each activation restores a status the instance still has.
local function status_brain(self, _dtime)
	STATUS.restore_on_activate(self)
end

-- The "status_hold" brain (T-31). It runs after the creatures brains of the step. A creature with stat stages joins the
-- decay tick (also after a reload, when the stages come back from the staticdata). A trapped creature cannot run: the
-- wild brain writes run_velocity on every think, so trap sets it to 0 again here. A sleeping or frozen creature does
-- not move or think: it stands still, and mcl's states (and their animations) are skipped, so the sit pose holds.
local function status_hold_brain(self, _dtime)
	local obj = self.object
	if self._mm_stages and next(self._mm_stages) ~= nil then
		EFFECTS.note_stages(self)
	end
	local kind = STATUS.get(obj)
	if kind ~= "sleep" and kind ~= "freeze" then
		if STATUS.has(obj, "trap") then
			self.run_velocity = 0
		end
		return nil
	end
	local v = obj:get_velocity()
	if v then
		obj:set_velocity({ x = 0, y = v.y, z = 0 })
	end
	return "skip_states"
end

minemon.creatures.register_brain("status_restore", status_brain)
minemon.creatures.register_brain("combat_cast", cast_brain)
minemon.creatures.register_brain("status_hold", status_hold_brain)

-- Public API (PLAN.md, minemon_combat). Returns true when the cast started, or false and a reason.
function API.use_move(user, target, move_id)
	local inst, le = creature_of(user)
	if not inst then
		return false, "user is not a creature"
	end
	local raw = minemon.data.get_move(move_id)
	if not raw then
		return false, "unknown move " .. tostring(move_id)
	end
	local move = extended(move_id, raw)
	local slot = find_slot(inst, move_id)
	if not slot then
		return false, "move not in moveset"
	end
	local owned = is_owned(inst, le)
	if owned and (slot.pp or 0) <= 0 then
		return false, "no PP left"
	end
	if on_cooldown_le(le, move_id) then
		return false, "cooldown"
	end
	if casting[le] then
		return false, "busy"
	end
	if minemon.creatures.is_exhausted(user) then
		return false, "exhausted"
	end
	if STATUS.has(user, "flinch") then
		return false, "flinched"
	end
	local status = STATUS.get(user)
	if SL.blocks_moves(status) then
		return false, status == "sleep" and "asleep" or "frozen"
	end
	if status == "paralysis" and SL.paralysis_fails(rng) then
		G.feedback_near(G.eye(user), EFX.TEXT.paralysed, WHITE_TEXT)
		return false, "paralysed"
	end
	local needs_target = LOGIC.needs_target(move.archetype)
	if needs_target then
		if not target or not target:get_pos() or G.guid(target) == G.guid(user) then
			return false, "no target"
		end
		if not valid_target(target) then
			return false, "bad target"
		end
		if LOGIC.needs_range(move.archetype) and not in_range(user, target, move) then
			return false, "out of range"
		end
		G.face(user, target)
	end
	if owned then
		slot.pp = slot.pp - 1
	end
	le._mm_cooldown = le._mm_cooldown or {}
	le._mm_cooldown[move_id] = now() + move.cooldown_s
	-- Confusion: a 33% roll at the cast turns the move on the user (effects.lua self_hit).
	local confused = STATUS.has(user, "confusion") and EFX.confusion_self_hit(rng)
	casting[le] = { move_id = move_id, target = target }
	VFX.windup(G.eye(user), move.type, move.cast_s)
	core.after(move.cast_s, function()
		SAFE.call("cast " .. tostring(move_id), finish_cast, user, target, move_id, move, confused)
	end)
	return true
end

-- The best move the creature can use now against target (nil target: the user's own view). Returns a move id or nil.
function API.choose_move(user, target)
	local inst, le = creature_of(user)
	if not inst then
		return nil
	end
	local owned = is_owned(inst, le)
	local candidates = {}
	for _, slot in ipairs(inst.moves or {}) do
		local raw = minemon.data.get_move(slot.id)
		if raw then
			candidates[#candidates + 1] = {
				id = slot.id,
				pp = owned and slot.pp or nil,
				move = extended(slot.id, raw),
				on_cooldown = on_cooldown_le(le, slot.id),
			}
		end
	end
	local sp = minemon.data.get_species(inst.species_id)
	local uv = G.view_of(user)
	local has_target = target ~= nil and target:get_pos() ~= nil
	local tv = has_target and G.view_of(target) or nil
	local ctx = {
		user_types = (sp and sp.types) or {},
		target_types = has_target and G.types_of(target) or { "normal" },
		target_status = has_target and STATUS.get(target) or "none",
		type_mult = G.type_mult,
		user_hp_frac = uv and inst.hp / math.max(1, uv.stats.hp) or 1,
		user_stages = uv and uv.stages or {},
		target_stages = tv and tv.stages or {},
	}
	return CHOOSE.choose(candidates, ctx, rng)
end

function API.on_cooldown(user, move_id)
	local _, le = creature_of(user)
	return on_cooldown_le(le, move_id)
end

-- Applies a status by kind to a creature or player: a primary one (freeze, sleep, ...) or a volatile one (leech, trap,
-- ...). seeder (optional) is the user of a leech seed, which drains into it. Returns true when the status was applied.
function API.apply_status(obj, kind, seeder)
	if not valid_target(obj) then
		return false
	end
	return G.apply_kind(obj, kind, { seeder = seeder })
end

-- The primary status of a creature or player: "none", or sleep, paralysis, burn, poison or freeze.
function API.status_of(obj)
	return STATUS.get(obj)
end

-- True when a volatile status of this kind is on obj now (for example "trap", "protect", "confusion").
function API.has_volatile(obj, kind)
	return STATUS.has(obj, kind)
end

-- A trapped creature cannot flee (no running) and cannot be recalled. The recall path in minemon_party checks this.
function API.is_trapped(obj)
	return STATUS.has(obj, "trap")
end

function API.can_recall(obj)
	return not STATUS.has(obj, "trap")
end

-- Clears stages, cooldowns, the cast, the primary and the volatile statuses. For recall (T-22).
function API.reset(obj)
	local inst, le = creature_of(obj)
	if not inst then
		return false
	end
	le._mm_stages = {}
	le._mm_stage_timer = 0
	le._mm_cooldown = {}
	le._mm_protect_streak = nil
	le._mm_protect_t = nil
	casting[le] = nil
	STATUS.clear(obj)
	STATUS.clear_all_volatile(obj)
	STATUS.refresh_speed(obj)
	return true
end

-- Hurts the seeder's victim by amount and moves what was dealt into the seeder (leech seed).
local function drain(seeder, victim, amount)
	if not seeder:get_pos() or not victim:get_pos() then
		return
	end
	local before = G.hp_of(victim)
	G.apply_damage(victim, amount, nil, { move_id = "leech-seed" })
	local dealt = before - G.hp_of(victim)
	if dealt > 0 then
		G.heal_obj(seeder, dealt)
	end
end

-- One globalstep: status ticks, stage decay and cloud checks every 0.5 s (PLAN.md performance rules). Each part runs
-- under pcall, so an error is logged and the server keeps running (T-23b).
local tick_acc = 0
core.register_globalstep(function(dtime)
	tick_acc = tick_acc + dtime
	if tick_acc < TICK_S then
		return
	end
	local dt = tick_acc
	tick_acc = 0
	SAFE.call("status tick", STATUS.tick, dt, rng, G.apply_damage)
	SAFE.call("volatile tick", STATUS.tick_volatile, dt, G.apply_damage, drain)
	SAFE.call("stage decay", EFFECTS.decay_tick, G, dt)
	SAFE.call("cloud tick", ARCH.tick_clouds, G, dt)
end)
