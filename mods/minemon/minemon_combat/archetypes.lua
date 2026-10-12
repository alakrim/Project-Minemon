-- The six move archetypes (T-23 brief). Glue: each function resolves one use of a move, after its cast time.
-- G is the context that init.lua builds (creature and player views, damage, stages, feedback, rng).
-- luacheck: read_globals core vector vl_projectile mcl_util

local EFX = dofile(core.get_modpath("minemon_combat") .. "/effects_logic.lua")

local M = {}

local GREY_TEXT = 0xA0A0A0
local GREEN_TEXT = 0x33DD55

M.ORB = "minemon_combat:orb"
M.ORB_SPEED = 14 -- metres per second
M.ORB_LIFE_S = 3
M.CLOUD_RADIUS = 2.5
M.CLOUD_LIFE_S = 3
M.CLOUDS_CAP = 16
M.ANIM_SPEED = 15

local clouds = {}

local function roll_chance(G, percent)
	return G.rng:float() * 100 < percent
end

local function feedback(G, pos, eff, res, move)
	if move.category == "status" and eff > 0 then
		return
	end
	local F = G.vfx.FEEDBACK
	if eff <= 0 then
		G.feedback_near(pos, F.none.text, F.none.colour)
	elseif eff > 1 then
		G.feedback_near(pos, F.super.text, F.super.colour)
	elseif eff < 1 then
		G.feedback_near(pos, F.weak.text, F.weak.colour)
	elseif res.crit then
		G.feedback_near(pos, F.crit.text, F.crit.colour)
	end
end

-- Applies the status and stat effects of a move that hit one victim. Status chance is per hit; stat changes use
-- stat_chance (100 when absent). Targets that are immune to the type take no status. Statuses go through G.apply_kind
-- (primary or volatile).
local function apply_effects(G, user, victim, move, eff)
	local effect = move.effect or {}
	if effect.status ~= nil and eff > 0 then
		if roll_chance(G, effect.status_chance or 100) then
			G.apply_kind(victim, effect.status, { hurts = move.power ~= nil, seeder = user })
		end
	end
	local changes = effect.stat_changes or {}
	if #changes > 0 and roll_chance(G, effect.stat_chance or 100) then
		for _, c in ipairs(changes) do
			local who = (c.target == "user") and user or victim
			G.apply_stage(who, c.stat, c.stages)
		end
	end
end

local BLOCKED_RESULT = { amount = 0, crit = false, effectiveness = 1.0, missed = true }

-- Shared resolution for one victim: the victim's protect blocks everything. Otherwise the damage (Gen 2 formulas, with
-- the mechanics of effects_logic: power by moment, fixed, one-hit KO, half HP, psywave), the screens and endure, then
-- the effects if the move hit. scale multiplies the damage (area falloff). Returns the damage result, or nil when a
-- view is missing.
function M.resolve(G, user, victim, move_id, move, scale)
	local atk = G.view_of(user)
	local def = G.view_of(victim)
	if not atk or not def then
		return nil
	end
	local pos = victim:get_pos()
	if G.has_volatile(victim, "protect") then
		G.feedback_near(pos, EFX.TEXT.blocked, GREY_TEXT)
		return BLOCKED_RESULT
	end
	local mv, heal = EFX.prepare(move, move.mech, atk, G.rng)
	if G.has_volatile(user, "focus") then
		mv = EFX.with_high_crit(mv)
	end
	local res = G.formulas.damage(atk, def, mv, G.type_mult, G.rng)
	if res.missed then
		return res
	end
	if heal then
		local added = G.heal_obj(victim, EFX.heal_amount(def.stats.hp, 0.25))
		if added > 0 then
			G.feedback_near(pos, EFX.TEXT.healed, GREEN_TEXT)
		end
		return res
	end
	res = EFX.post_damage(move.mech, res, atk, def, G.rng)
	if res.missed then
		return res
	end
	local eff = res.effectiveness
	local amount = res.amount
	if amount > 0 and scale then
		amount = math.max(1, math.floor(amount * scale))
	end
	if amount > 0 then
		amount = EFX.screened(amount, move.category, G.has_volatile(victim, "light_screen"),
			G.has_volatile(victim, "reflect"))
	end
	if amount > 0 and G.has_volatile(victim, "endure") then
		amount = EFX.endured(amount, def.hp)
	end
	if amount > 0 then
		G.apply_damage(victim, amount, user, { move_id = move_id, effectiveness = eff, crit = res.crit })
		if move.type == "fire" then
			G.status.thaw_on_fire(victim)
		end
		local flinch = (move.effect or {}).flinch_chance
		if flinch ~= nil and roll_chance(G, flinch) then
			G.apply_kind(victim, "flinch", { refresh = true })
		end
	end
	if eff > 0 then
		apply_effects(G, user, victim, move, eff)
	end
	feedback(G, pos, eff, res, move)
	return res
end

-- Projectile: an orb flies from the user towards the target at ORB_SPEED. The first creature or player that is not
-- the user or its owner's creatures is hit (see register_orb).
function M.projectile(G, user, target, move_id, move)
	local eu, et = G.eye(user), G.eye(target)
	local dir = vector.normalize(vector.subtract(et, eu))
	local start = vector.add(eu, vector.multiply(dir, 0.8))
	G.vfx.burst(start, move.type, "orb", 1.5, 0.2)
	local obj = vl_projectile.create(M.ORB, {
		pos = start,
		dir = dir,
		velocity = M.ORB_SPEED,
		drag = 0,
		owner = user,
		extra = { user = user, move_id = move_id, move = move },
	})
	if obj then
		obj:set_properties({ textures = { G.vfx.texture("orb", move.type) } })
	end
	return obj ~= nil
end

-- Beam: an instant raycast from the user's eye to the target's eye. Blocks stop it. It hits the first object on the
-- line that is not the user.
function M.beam(G, user, target, move_id, move)
	local eu, et = G.eye(user), G.eye(target)
	local stop, hit = et, nil
	for pointed in core.raycast(eu, et, true, false) do
		if pointed.type == "node" then
			stop = pointed.intersection_point or stop
			break
		elseif pointed.type == "object" and pointed.ref ~= nil and G.guid(pointed.ref) ~= G.guid(user) then
			hit = pointed.ref
			stop = pointed.intersection_point or et
			break
		end
	end
	G.vfx.line(eu, stop, move.type)
	if hit then
		M.resolve(G, user, hit, move_id, move)
	end
	return true
end

-- Melee arc: the target must be within range (plus body slack) and in front of the user (dot > 0.3).
function M.melee_arc(G, user, target, move_id, move)
	local pu, pt = user:get_pos(), target:get_pos()
	local to = vector.subtract(pt, pu)
	to.y = 0
	local d = vector.length(to)
	if d <= 0 or d > move.range_m + G.logic.RANGE_SLACK then
		return false
	end
	local fwd = G.forward(user)
	local dir = vector.multiply(to, 1 / d)
	if vector.dot(dir, fwd) <= 0.3 then
		return false
	end
	G.animate(user, "punch")
	user:add_velocity(vector.multiply(dir, 2))
	G.vfx.swoosh(vector.add(pu, vector.new(0, G.height(user) * 0.4, 0)), fwd, move.type)
	M.resolve(G, user, target, move_id, move)
	return true
end

-- Area burst: every creature or player within range_m of the target, except the user and its owner's creatures.
-- Damage falls off linearly to 50% at the edge.
function M.area_burst(G, user, target, move_id, move)
	local centre = vector.add(target:get_pos(), vector.new(0, G.height(target) * 0.4, 0))
	local radius = move.range_m
	G.vfx.sphere(centre, radius, move.type)
	for _, obj in ipairs(core.get_objects_inside_radius(centre, radius)) do
		if G.is_combatant(obj) and G.guid(obj) ~= G.guid(user) and not G.is_friend(user, obj) then
			local d = vector.distance(centre, obj:get_pos())
			local scale = 1 - 0.5 * math.min(1, d / radius)
			M.resolve(G, user, obj, move_id, move, scale)
		end
	end
	return true
end

-- Aura: stat changes on the user, or on the target when the change says target = "target". Glow on the user.
function M.aura(G, user, target, _move_id, move)
	local effect = move.effect or {}
	G.vfx.aura(vector.add(user:get_pos(), vector.new(0, G.height(user) * 0.5, 0)), move.type)
	for _, c in ipairs(effect.stat_changes or {}) do
		local who = user
		if c.target == "target" and target ~= nil and target:get_pos() then
			who = target
		end
		if roll_chance(G, effect.stat_chance or 100) then
			G.apply_stage(who, c.stat, c.stages)
		end
	end
	return true
end

-- Status cloud: a puff cloud at the target for CLOUD_LIFE_S seconds. Its accuracy roll is made once, at the cast.
-- Victims inside are checked every 0.5 s (M.tick_clouds): stat changes apply once on first contact, and the status
-- is rolled until it lands.
function M.status_cloud(G, user, target, _move_id, move)
	local centre = vector.add(target:get_pos(), vector.new(0, 0.2, 0))
	-- Without a view (a target that is not a creature or player) the cloud is cosmetic: no accuracy roll, no effects.
	local atk, def = G.view_of(user), G.view_of(target)
	local hit = false
	if atk and def then
		local res = G.formulas.damage(atk, def, move, G.type_mult, G.rng)
		hit = not res.missed
	end
	G.vfx.cloud(centre, M.CLOUD_RADIUS, move.type, M.CLOUD_LIFE_S)
	if hit then
		for _, c in ipairs(move.effect and move.effect.stat_changes or {}) do
			if c.target == "user" then
				G.apply_stage(user, c.stat, c.stages)
			end
		end
	end
	if #clouds >= M.CLOUDS_CAP then
		table.remove(clouds, 1)
	end
	clouds[#clouds + 1] = {
		pos = centre, user = user, move = move, hit = hit, age = 0, seen = {},
	}
	return true
end

local DISPATCH = {
	projectile = M.projectile,
	beam = M.beam,
	melee_arc = M.melee_arc,
	area_burst = M.area_burst,
	aura = M.aura,
	status_cloud = M.status_cloud,
}

function M.fire(G, archetype, user, target, move_id, move)
	local fn = DISPATCH[archetype]
	if not fn then
		return false
	end
	return fn(G, user, target, move_id, move)
end

local function tick_cloud(G, cloud, dt)
	cloud.age = cloud.age + dt
	if cloud.age >= M.CLOUD_LIFE_S or not cloud.user:get_pos() then
		return false
	end
	if not cloud.hit then
		return true
	end
	local effect = cloud.move.effect or {}
	for _, obj in ipairs(core.get_objects_inside_radius(cloud.pos, M.CLOUD_RADIUS)) do
		-- A protected victim is not touched, and is checked again on a later tick.
		if G.is_combatant(obj) and G.guid(obj) ~= G.guid(cloud.user) and not G.is_friend(cloud.user, obj)
			and not G.has_volatile(obj, "protect") then
			local key = G.guid(obj)
			local seen = cloud.seen[key]
			if not seen then
				seen = { statused = false }
				cloud.seen[key] = seen
				for _, c in ipairs(effect.stat_changes or {}) do
					if c.target == "target" and roll_chance(G, effect.stat_chance or 100) then
						G.apply_stage(obj, c.stat, c.stages)
					end
				end
			end
			local immune = G.type_mult(cloud.move.type, G.types_of(obj)) <= 0
			if not seen.statused and effect.status ~= nil and not immune then
				if roll_chance(G, effect.status_chance or 100)
					and G.apply_kind(obj, effect.status, { hurts = cloud.move.power ~= nil, seeder = cloud.user }) then
					seen.statused = true
				end
			end
		end
	end
	return true
end

-- Ticks every live cloud (called with the 0.5 s status step). Expired clouds are dropped.
function M.tick_clouds(G, dt)
	local alive = {}
	for _, cloud in ipairs(clouds) do
		if tick_cloud(G, cloud, dt) then
			alive[#alive + 1] = cloud
		end
	end
	clouds = alive
end

-- The projectile entity. Its collision hook resolves the hit; allow_punching lets the orb pass through the user and
-- its owner's creatures. damage_groups is a table (S-12 gotcha 3), so vl_projectile's punch does no damage here:
-- resolve() applies the damage through the Gen 2 formulas.
function M.register_orb(G)
	vl_projectile.register(M.ORB, {
		initial_properties = {
			physical = false,
			collide_with_objects = false,
			pointable = false,
			static_save = false,
			visual = "sprite",
			textures = { G.vfx.texture("orb", "normal") },
			visual_size = { x = 2.0, y = 2.0 },
			collisionbox = { -0.1, -0.1, -0.1, 0.1, 0.1, 0.1 },
			glow = 12,
		},
		_vl_projectile = {
			ignore_gravity = true,
			damage_groups = {},
			allow_punching = function(self, _, _, obj)
				local extra = self._vl_projectile and self._vl_projectile.extra
				if not extra or not obj then
					return false
				end
				return G.is_combatant(obj) and not G.is_friend(extra.user, obj)
			end,
			behaviors = { vl_projectile.collides_with_solids, vl_projectile.collides_with_entities },
			on_collide_with_entity = function(self, _, obj)
				local extra = self._vl_projectile and self._vl_projectile.extra
				if extra then
					M.resolve(G, extra.user, obj, extra.move_id, extra.move)
				end
			end,
		},
		-- vl_projectile reads maximum_time from the luaentity, which create() replaces, so the orb ends itself.
		on_step = function(self, dtime)
			if self._removed then
				return
			end
			self._mm_age = (self._mm_age or 0) + dtime
			if self._mm_age >= M.ORB_LIFE_S then
				mcl_util.remove_entity(self)
				return
			end
			self._mm_trail = (self._mm_trail or 0) + dtime
			if self._mm_trail >= 0.1 then
				self._mm_trail = 0
				local p = self.object:get_pos()
				local extra = self._vl_projectile and self._vl_projectile.extra
				if p and extra then
					G.vfx.orb_trail(p, extra.move.type)
				end
			end
			vl_projectile.update_projectile(self, dtime)
		end,
	})
end

return M
