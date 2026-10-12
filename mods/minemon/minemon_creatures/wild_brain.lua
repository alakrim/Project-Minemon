-- minemon_creatures: the wild creature brain (T-21b, D-009, D-026). Glue only: the decisions are in wild_logic.lua.
-- The brain applies to creatures without an owner. Each creature thinks every THINK_S seconds, from a random start
-- phase, so the creatures do not all think on the same step. A think sets the danger tuning (melee damage, bite
-- period) and the run speed from the instance stats, then acts on decide(ctx):
--   hunt_player    do_attack on the player (mcl dogfight does the damage); +20% run speed
--   fight_creature do_attack on the creature; choose_move and use_move when in range (minemon_combat)
--   flee           runaway state, turned away from the threat (S-12 section 3)
--   idle           returns nothing, so mcl wanders; clears a stale attack
-- Transient state (anger, last attacker, current action) lives in a weak table, not in entity fields, so mcl's
-- staticdata never keeps a timer from an earlier server run.
-- luacheck: read_globals core minemon vector

local MODPATH = core.get_modpath("minemon_creatures")
local LOGIC = dofile(MODPATH .. "/wild_logic.lua")
local defs = dofile(MODPATH .. "/defs.lua")

local M = {}

local MOVE_CHECK_RANGE = 12 -- nodes; moves are chosen only this close (the longest move range is 12)
local LOG_EVERY = 100 -- errors between two log lines

-- Where the brain reads the players and their active creatures. Tests replace these with fakes.
-- minemon.party comes from T-22; without it nobody has a creature out.
M.sources = {
	players = function()
		return core.get_connected_players()
	end,
	active_of = function(player)
		local party = minemon.party
		if party == nil or type(party.get_active) ~= "function" then
			return nil
		end
		local ok, obj = pcall(party.get_active, player)
		if ok then
			return obj
		end
		return nil
	end,
}

local rng = minemon.rng.new(4242) -- start phases only; the seed is fixed so runs are repeatable
local counters = { thinks = 0, errors = 0 }
local transient = setmetatable({}, { __mode = "k" })

local function now_s()
	return core.get_us_time() / 1e6
end

local function transient_of(le)
	local t = transient[le]
	if t == nil then
		t = {}
		transient[le] = t
	end
	return t
end

-- A wild creature of ours: a luaentity with an instance, no owner and not tamed.
local function is_wild(le)
	return type(le) == "table" and le._mm ~= nil and type(le.name) == "string"
		and le.name:sub(1, #defs.PREFIX) == defs.PREFIX and le.tamed ~= true
		and (le.owner == nil or le.owner == "")
end

-- An object that can be a target: one of our creatures, alive and not exhausted, with a position. Else nil.
local function target_creature(obj)
	if obj == nil or not obj:is_valid() or obj:get_pos() == nil then
		return nil
	end
	local inst = minemon.creatures.get_instance(obj)
	if inst == nil or inst.hp <= 0 or minemon.creatures.is_exhausted(obj) then
		return nil
	end
	return obj
end

local function nearest_player(pos)
	local best, best_d = nil, nil
	for _, p in ipairs(M.sources.players()) do
		local pp = p:get_pos()
		if pp then
			local d = vector.distance(pos, pp)
			if best_d == nil or d < best_d then
				best, best_d = p, d
			end
		end
	end
	return best, best_d
end

-- The decision context (see wild_logic.lua).
local function build_ctx(self, pos, species, inst, stats, t)
	-- A Dread creature is aggressive whatever its species temperament (T-30, D-031).
	local is_dread = inst.dread == true
	local ctx = {
		temperament = is_dread and "aggressive" or species.temperament,
		dread = is_dread,
		types = species.types,
		hp_frac = stats.hp > 0 and inst.hp / stats.hp or 0,
		is_night = LOGIC.is_night(core.get_timeofday()),
		view_range = self.view_range or 12,
		now = now_s(),
		angry_until = t.angry_until or 0,
		hurt_by = t.hurt_by,
	}
	local player, player_d = nearest_player(pos)
	if player ~= nil then
		ctx.player = player
		ctx.player_distance = player_d
		local creature = target_creature(M.sources.active_of(player))
		if creature ~= nil then
			ctx.creature = creature
			ctx.creature_distance = vector.distance(pos, creature:get_pos())
		end
	end
	local attacker = t.attacker and target_creature(t.attacker)
	if attacker ~= nil then
		ctx.attacker = attacker
		ctx.attacker_distance = vector.distance(pos, attacker:get_pos())
	end
	return ctx
end

-- Starts an attack on target unless it is already the target. do_attack does nothing in the attack and runaway
-- states (mcl combat.lua:39), so those are left first.
local function engage(self, target)
	local cur = self.attack
	if self.state == "attack" and cur ~= nil and cur:is_valid() and cur:get_guid() == target:get_guid() then
		return
	end
	if self.state == "attack" or self.state == "runaway" then
		self.state = "stand"
	end
	self:do_attack(target)
end

-- Creature moves through minemon_combat. choose_move and use_move check the cooldowns and the range themselves.
local function use_moves(obj, target, dist)
	local combat = minemon.combat
	if combat == nil or dist > MOVE_CHECK_RANGE then
		return
	end
	local move_id = combat.choose_move(obj, target)
	if move_id ~= nil then
		combat.use_move(obj, target, move_id)
	end
end

-- Runaway from the nearest player in FLEE_PLAYER_RANGE, else from the creature that hit us. The timer is reset
-- each think, so the flight lasts while the decision says flee (mcl stops runaway after 5 s).
local function flee(self, pos, ctx)
	local threat = nil
	if ctx.player ~= nil and ctx.player_distance ~= nil and ctx.player_distance <= LOGIC.FLEE_PLAYER_RANGE then
		threat = ctx.player:get_pos()
	elseif ctx.attacker ~= nil then
		threat = ctx.attacker:get_pos()
	end
	if threat ~= nil then
		self:turn_in_direction(pos.x - threat.x, pos.z - threat.z, 1)
	end
	if self.state == "attack" then
		self.attack = nil
	end
	self.state = "runaway"
	self.runaway_timer = 0
end

-- Sanctuary wards (D-030, minemon_sanctuary). A target inside a ward is dropped; the ward centre it was in is
-- returned so the creature can walk away from it. Returns nil when no target was in a ward.
local function drop_warded(ctx, sanct)
	local centre = nil
	if ctx.player ~= nil and sanct.ward_centre(ctx.player:get_pos()) ~= nil then
		centre = sanct.ward_centre(ctx.player:get_pos())
		ctx.player, ctx.player_distance = nil, nil
	end
	if ctx.creature ~= nil and sanct.ward_centre(ctx.creature:get_pos()) ~= nil then
		centre = centre or sanct.ward_centre(ctx.creature:get_pos())
		ctx.creature, ctx.creature_distance = nil, nil
	end
	if ctx.attacker ~= nil and sanct.ward_centre(ctx.attacker:get_pos()) ~= nil then
		centre = centre or sanct.ward_centre(ctx.attacker:get_pos())
		ctx.attacker, ctx.attacker_distance = nil, nil
	end
	return centre
end

-- Walks away from a ward centre: the same runaway as flee(), turned away from the centre.
local function walk_away(self, pos, centre)
	self:turn_in_direction(pos.x - centre.x, pos.z - centre.z, 1)
	if self.state == "attack" then
		self.attack = nil
	end
	self.state = "runaway"
	self.runaway_timer = 0
end

local function perform(self, pos, dec, ctx, t)
	local base = self._mm_run_base
	local action = dec.action
	if action == "hunt_player" then
		self.run_velocity = LOGIC.run_speed(base, true)
		engage(self, dec.target)
		t.action = "hunt"
	elseif action == "fight_creature" then
		self.run_velocity = LOGIC.run_speed(base, false)
		engage(self, dec.target)
		use_moves(self.object, dec.target, vector.distance(pos, dec.target:get_pos()))
		t.action = "fight"
	elseif action == "flee" then
		self.run_velocity = base
		flee(self, pos, ctx)
		t.action = "flee"
	else
		self.run_velocity = base
		if (t.action == "hunt" or t.action == "fight") and self.state == "attack" then
			self.attack = nil
			self.state = "stand"
		end
		t.action = nil
	end
	return nil
end

local function think(self, dtime)
	if self._mm == nil or self._mm_exhausted == true or not is_wild(self) then
		return nil
	end
	local t = transient_of(self)
	if t.countdown == nil then
		t.countdown = rng:float() * LOGIC.THINK_S
	end
	t.countdown = t.countdown - dtime
	if t.countdown > 0 then
		return nil
	end
	t.countdown = LOGIC.THINK_S
	counters.thinks = counters.thinks + 1

	local pos = self.object:get_pos()
	local inst = self._mm
	local species = minemon.data.get_species(inst.species_id)
	if pos == nil or species == nil then
		return nil
	end
	local stats = minemon.instance.stats(inst, species)
	-- Danger tuning: the melee damage and the bite period come from the instance stats and the level.
	self.damage = LOGIC.melee_damage(inst.level, stats.atk)
	self.attack_frequency = LOGIC.attack_period(stats.spe)
	-- The base run speed is kept on the entity, so a saved +20% is never taken as the base.
	if self._mm_run_base == nil then
		self._mm_run_base = self.run_velocity
	end
	local ctx = build_ctx(self, pos, species, inst, stats, t)
	-- Sanctuary wards (D-030): a creature inside a ward is never aggressive and walks out of it; a target inside a
	-- ward is dropped, and a creature that was hunting or fighting it walks away from the ward.
	local sanct = minemon.sanctuary
	if sanct ~= nil and sanct.ward_centre ~= nil then
		local home = sanct.ward_centre(pos)
		if home ~= nil then
			walk_away(self, pos, home)
			self.run_velocity = self._mm_run_base
			t.action = "flee"
			return nil
		end
		local centre = drop_warded(ctx, sanct)
		if centre ~= nil and (t.action == "hunt" or t.action == "fight") then
			walk_away(self, pos, centre)
			self.run_velocity = self._mm_run_base
			t.action = "flee"
			return nil
		end
	end
	return perform(self, pos, LOGIC.decide(ctx), ctx, t)
end

-- The mcl brain entry: fn(self, dtime). Errors are counted and logged (a few times), and never stop the chain.
function M.think(self, dtime)
	local ok, res = pcall(think, self, dtime)
	if ok then
		return res
	end
	counters.errors = counters.errors + 1
	if counters.errors == 1 or counters.errors % LOG_EVERY == 0 then
		core.log("error", string.format("[minemon_creatures] wild brain failed (%d so far): %s",
			counters.errors, tostring(res)))
	end
	return nil
end

-- creature_hurt handler: a wild creature is angry for ANGER seconds after a hit, and remembers who hit it. The
-- attacker is kept only when it is one of our creatures (it can fight back); otherwise the hit came from a player,
-- or from something else (fall, fire, a mob), and the creature treats it as a threat.
function M.on_hurt(obj, _amount, attacker, _info)
	local le = obj and obj:get_luaentity()
	if not is_wild(le) then
		return
	end
	local species = minemon.data.get_species(le._mm.species_id)
	local t = transient_of(le)
	t.angry_until = now_s() + LOGIC.anger_seconds(species and species.temperament or "peaceful")
	t.hurt_by = "other"
	t.attacker = nil
	if type(attacker) == "userdata" and attacker:is_valid() then
		if minemon.creatures.get_instance(attacker) ~= nil then
			t.hurt_by = "creature"
			t.attacker = attacker
		elseif attacker:is_player() then
			t.hurt_by = "player"
		end
	end
end

-- Replaces the player and active-creature sources (integration tests). nil keeps the current source.
function M.set_sources(players, active_of)
	if players ~= nil then
		M.sources.players = players
	end
	if active_of ~= nil then
		M.sources.active_of = active_of
	end
end

-- Counters for the tests: thinks made and brain errors.
function M.stats()
	return { thinks = counters.thinks, errors = counters.errors }
end

return M
