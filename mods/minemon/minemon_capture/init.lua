-- minemon_capture: thrown balls, catch odds, shakes, break-free, creature_defeated and creature_captured (T-26, D-030).
-- Glue only. The rules are in capture_logic.lua (pure, busted-tested). The throw is an entity that flies on its own
-- path (raycast per step); the capture sequence is a chain of core.after timers. Test entry points: minemon.capture
-- ._resolve (the whole outcome, at once) and ._hit_object (what a hit does).
-- luacheck: read_globals core minemon vector mcl_util ItemStack
-- luacheck: globals minemon

local MODPATH = core.get_modpath("minemon_capture")
local L = dofile(MODPATH .. "/capture_logic.lua")

local THROWN = "minemon_capture:thrown"
local BALL_VISUAL = "minemon_capture:ball_visual"
local KIT_KEY = "minemon:capture:kit"
local SOUND_THROW = "mcl_throwing_throw" -- VoxeLibre throw sound (mcl_throwing)
local SOUND_CLICK = "default_place_node_hard" -- the shake click
local SOUND_CATCH = "mcl_experience_level_up" -- the catch chime (VoxeLibre)
local PARTICLE = "mcl_particles_smoke.png" -- VoxeLibre texture, as minemon_creatures uses
local GOLD = "#FFD700"
local RED = "#FF3030"
local TICK_S = 0.1 -- one step of the shake wobble
local EYE_HEIGHT = 1.625
local HUD_TYPE = core.features.hud_def_type_field and "type" or "hud_elem_type"

minemon.capture = minemon.capture or {}
local API = minemon.capture

local function say(name, text)
	core.chat_send_player(name, text)
end

local function species_of(inst)
	return minemon.data.get_species(inst.species_id)
end

local function display_of(inst)
	local sp = species_of(inst)
	return L.display_name(sp and sp.name or "creature", inst.nickname)
end

local function eye_pos(player)
	local props = player:get_properties() or {}
	return vector.add(player:get_pos(), vector.new(0, props.eye_height or EYE_HEIGHT, 0))
end

local function stop_moving(obj)
	obj:set_velocity(vector.new(0, 0, 0))
end

-- Particles: a small puff. Used for a broken ball and for a catch.
local function puff(pos, gold)
	if pos == nil then
		return
	end
	core.add_particlespawner({
		amount = gold and 30 or 14,
		time = 0.3,
		minpos = vector.add(pos, vector.new(-0.3, 0, -0.3)),
		maxpos = vector.add(pos, vector.new(0.3, 0.6, 0.3)),
		minvel = vector.new(-0.6, 0.4, -0.6),
		maxvel = vector.new(0.6, 1.6, 0.6),
		minacc = vector.new(0, -1, 0),
		maxacc = vector.new(0, -1, 0),
		minexptime = 0.4,
		maxexptime = 0.9,
		minsize = 1,
		maxsize = 2.5,
		texture = PARTICLE,
	})
end

-- The ball visual: a wielditem on the ground during a capture. Its staticdata names the item.
core.register_entity(BALL_VISUAL, {
	initial_properties = {
		physical = false,
		pointable = false,
		collide_with_objects = false,
		visual = "wielditem",
		visual_size = { x = 0.35, y = 0.35 },
		collisionbox = { -0.1, -0.1, -0.1, 0.1, 0.1, 0.1 },
		static_save = false,
	},
	on_activate = function(self, staticdata)
		local data = core.parse_json(staticdata or "")
		local item = type(data) == "table" and data.item or L.item_name("poke_ball")
		self.object:set_properties({ textures = { item } })
	end,
})

-- The thrown ball. Its staticdata: { ball = item name, thrower = player name, v = {x, y, z} }. It is not saved.
local function land(self, pos)
	core.add_item(pos or self.pos, self.item)
	self.object:remove()
end

-- First thing the segment from a to b hits: a node, or an object other than the ball and its thrower. nil if none.
local function first_hit(self, a, b)
	local thrower = self.thrower and core.get_player_by_name(self.thrower) or nil
	for pt in core.raycast(a, b, true, false) do
		if pt.type == "node" then
			return pt
		end
		if pt.type == "object" and pt.ref ~= self.object and pt.ref ~= thrower then
			return pt
		end
	end
	return nil
end

core.register_entity(THROWN, {
	initial_properties = {
		physical = false,
		pointable = false,
		collide_with_objects = false,
		visual = "wielditem",
		visual_size = { x = 0.3, y = 0.3 },
		collisionbox = { -0.1, -0.1, -0.1, 0.1, 0.1, 0.1 },
		static_save = false,
	},
	on_activate = function(self, staticdata)
		local data = core.parse_json(staticdata or "")
		if type(data) ~= "table" or L.ball_id(data.ball) == nil then
			self.object:remove()
			return
		end
		local v = type(data.v) == "table" and data.v or { x = 0, y = 0, z = 0 }
		self.item = data.ball
		self.thrower = data.thrower
		self.vel = vector.new(tonumber(v.x) or 0, tonumber(v.y) or 0, tonumber(v.z) or 0)
		self.age = 0
		self.pos = self.object:get_pos()
		self.object:set_properties({ textures = { data.ball } })
	end,
	on_step = function(self, dtime)
		if self.item == nil then
			return
		end
		self.age = self.age + dtime
		if self.age > L.THROW_MAX_AGE then
			land(self, self.pos)
			return
		end
		self.vel.y = self.vel.y - L.THROW_GRAVITY * dtime
		local to = vector.add(self.pos, vector.multiply(self.vel, dtime))
		local hit = first_hit(self, self.pos, to)
		if hit == nil then
			self.pos = to
			self.object:set_pos(to)
			return
		end
		if hit.type == "node" then
			land(self, hit.above or self.pos)
			return
		end
		self.object:remove()
		API._hit_object(core.get_player_by_name(self.thrower or "") or nil, hit.ref, L.ball_id(self.item),
			hit.intersection_point or self.pos)
	end,
})

-- Left click throws (on_use). The ball item is used up unless the player is in creative mode.
local function throw(stack, user)
	if user == nil or not user:is_player() then
		return stack
	end
	local ball_id = L.ball_id(stack:get_name())
	if ball_id == nil then
		return stack
	end
	local name = user:get_player_name()
	local dir = user:get_look_dir()
	local start = vector.add(eye_pos(user), vector.multiply(dir, 0.6))
	local v = vector.multiply(dir, L.THROW_SPEED)
	local staticdata = core.write_json({
		ball = L.item_name(ball_id), thrower = name, v = { x = v.x, y = v.y, z = v.z },
	})
	if core.add_entity(start, THROWN, staticdata) == nil then
		return stack
	end
	core.sound_play(SOUND_THROW, { pos = start, max_hear_distance = 16 }, true)
	if not core.is_creative_enabled(name) then
		stack:take_item(1)
	end
	return stack
end

-- Items. The leading colon keeps the names minemon:<id> (D-030). The description is the items.json name plus the
-- catch multiplier line.
local ICON_PREFIX = "minemon_capture_"
for _, id in ipairs(L.BALLS) do
	local item = minemon.data.get_item(id)
	assert(item ~= nil and L.catch_mult(item) ~= nil, "minemon_capture: items.json has no ball " .. id)
	core.register_craftitem(":" .. L.item_name(id), {
		description = item.name .. "\n" .. L.tooltip_line(L.catch_mult(item))
			.. (id == "umbral_ball" and "\nCatch rate ×3 against Dread creatures" or ""),
		_doc_items_longdesc = "A ball that catches exhausted wild creatures.",
		_doc_items_usagehelp = "Left click: throw at an exhausted creature. Hold it to see the catch odds.",
		inventory_image = ICON_PREFIX .. id .. ".png",
		stack_max = 64,
		groups = { craftitem = 1 },
		on_use = throw,
	})
end

-- Recipes (grind): VoxeLibre items. The Master Ball has no recipe. Recipes use the plain item names: the leading colon
-- is only for registration, and a recipe written with it does not match the registered item (checked by the test).
-- The iron nugget of the design is not in VoxeLibre; the gold nugget is its closest substitute.
core.register_craft({
	output = L.item_name("poke_ball") .. " 2",
	recipe = {
		{ "mcl_core:gold_nugget" },
		{ "mesecons:redstone" },
		{ "mcl_core:gold_nugget" },
	},
})
core.register_craft({
	type = "shapeless",
	output = L.item_name("great_ball"),
	recipe = { L.item_name("poke_ball"), "mcl_dye:blue" },
})
core.register_craft({
	type = "shapeless",
	output = L.item_name("ultra_ball"),
	recipe = { L.item_name("poke_ball"), "mcl_core:gold_ingot", "mcl_core:obsidian" },
})
-- The Umbral Ball (T-30, D-031): an Ultra Ball and four Dread Shards (minemon_dread registers the shard).
core.register_craft({
	type = "shapeless",
	output = L.item_name("umbral_ball"),
	recipe = { L.item_name("ultra_ball"), "minemon:dread_shard", "minemon:dread_shard", "minemon:dread_shard",
		"minemon:dread_shard" },
})

-- The odds for a wild creature hit by a ball, as a percent: nil when the creature is not an exhausted wild one.
local function odds_for(obj, ball_id)
	if not minemon.creatures.is_exhausted(obj) or minemon.creatures.is_owned(obj) then
		return nil
	end
	local inst = minemon.creatures.get_instance(obj)
	local sp = inst and species_of(inst)
	local base = L.catch_mult(minemon.data.get_item(ball_id))
	if sp == nil or base == nil then
		return nil
	end
	local mult = L.ball_mult(ball_id, inst, base)
	local max = minemon.instance.stats(inst, sp).hp
	local frac = max > 0 and inst.hp / max or 0
	local p = L.effective_p(ball_id, minemon.formulas.catch_chance(sp.catch_rate, frac, mult, inst.status))
	return L.odds_percent(p)
end

-- The exhausted wild creature the player's look ray reaches within ODDS_RANGE, or nil. The first thing hit counts.
local function odds_target(player)
	local dir = player:get_look_dir()
	local from = eye_pos(player)
	local to = vector.add(from, vector.multiply(dir, L.ODDS_RANGE))
	for pt in core.raycast(from, to, true, false) do
		if pt.type == "node" then
			return nil
		end
		if pt.type == "object" and pt.ref ~= player then
			return pt.ref
		end
	end
	return nil
end

-- Odds HUD: while a ball is wielded and an exhausted wild creature is in the look ray, "Catch ~NN%" near the crosshair.
local odds_huds = {} -- player name -> hud id
local odds_acc = 0

local function set_odds_hud(player, text, colour)
	local name = player:get_player_name()
	local id = odds_huds[name]
	if text == nil then
		if id ~= nil then
			player:hud_remove(id)
			odds_huds[name] = nil
		end
		return
	end
	if id == nil then
		odds_huds[name] = player:hud_add({
			[HUD_TYPE] = "text",
			position = { x = 0.5, y = 0.5 },
			offset = { x = 0, y = 40 },
			alignment = { x = 0, y = 0 },
			text = text,
			number = colour,
			z_index = 100,
			style = 1,
		})
	else
		player:hud_change(id, "text", text)
		player:hud_change(id, "number", colour)
	end
end

local function update_odds(player)
	local ball_id = L.ball_id(player:get_wielded_item():get_name())
	local pct = nil
	if ball_id ~= nil then
		local target = odds_target(player)
		pct = target and odds_for(target, ball_id) or nil
	end
	if pct == nil then
		set_odds_hud(player, nil)
		return
	end
	set_odds_hud(player, L.odds_text(pct), L.ODDS_RGB[L.odds_band(pct)])
end

core.register_globalstep(function(dtime)
	odds_acc = odds_acc + dtime
	if odds_acc < L.ODDS_INTERVAL then
		return
	end
	odds_acc = 0
	for _, player in ipairs(core.get_connected_players()) do
		update_odds(player)
	end
end)

core.register_on_leaveplayer(function(player)
	odds_huds[player:get_player_name()] = nil
end)

-- The capture sequence ------------------------------------------------------------------------------------------------

-- Wobbles the ball visual side to side for one shake. done() runs at the end; without a ball, it just waits.
local function wobble(ball, done)
	if ball == nil or not ball:is_valid() then
		core.after(L.SHAKE_SECONDS, done)
		return
	end
	local ticks = math.floor(L.SHAKE_SECONDS / TICK_S + 0.5)
	local function tick(k)
		if not ball:is_valid() then
			done()
			return
		end
		if k > ticks then
			ball:set_rotation(vector.new(0, 0, 0))
			done()
			return
		end
		local phase = k / ticks * math.pi * 2
		ball:set_rotation({ x = 0, y = 0, z = math.sin(phase) * 0.35 })
		core.after(TICK_S, function()
			tick(k + 1)
		end)
	end
	tick(1)
end

local function remove_ball(ctx, burst)
	local ball = ctx.ball_obj
	ctx.ball_obj = nil
	if ball ~= nil and ball:is_valid() then
		if burst then
			puff(ball:get_pos())
		end
		ball:remove()
	end
end

-- The creature stays wild and recovers: visible again, the exhausted timer restored. The ball goes back to the player.
local function release(ctx)
	local le = ctx.le
	remove_ball(ctx, false)
	if ctx.obj:is_valid() and not le._removed then
		le._mm_capturing = nil
		le._mm_exhausted_t = ctx.saved_t
		ctx.obj:set_properties({ is_visible = true })
	end
	local player = ctx.player
	if player:is_valid() and player.get_inventory then
		local leftover = player:get_inventory():add_item("main", ItemStack(L.item_name(ctx.ball_id)))
		if not leftover:is_empty() then
			core.add_item(player:get_pos(), leftover)
		end
	end
end

local function break_free(ctx)
	local le = ctx.le
	le._mm_capturing = nil
	remove_ball(ctx, true) -- the ball breaks: no item back
	ctx.obj:set_properties({ is_visible = true })
	local display = display_of(le._mm)
	say(ctx.name, core.colorize(RED, L.broke_free_line(display)))
	minemon.creatures.break_free(ctx.obj, ctx.player)
end

-- The creature is caught: it joins the party, or goes to the PC, or the capture is undone (release).
local function catch(ctx)
	local le = ctx.le
	local inst = le._mm
	local player = ctx.player
	local display = display_of(inst)
	local before = { owner = inst.owner, ball = inst.ball, bond = inst.bond, hp = inst.hp }
	inst.owner = ctx.name
	inst.ball = ctx.ball_id
	inst.bond = L.caught_bond(inst) -- a Dread creature starts with a low bond (T-30)
	inst.hp = math.max(1, inst.hp) -- an exhausted creature is at 0 HP; a caught one joins at least at 1 HP
	local placed = false
	local list = minemon.party.get(player)
	if #list < L.PARTY_MAX then
		list[#list + 1] = inst
		minemon.party.set(player, list)
		placed = true
	elseif minemon.pc ~= nil and type(minemon.pc.deposit) == "function" then
		placed = minemon.pc.deposit(player, inst) and true or false
		if placed then
			say(ctx.name, L.sent_to_pc_line(display))
		end
	end
	if not placed then
		inst.owner = before.owner
		inst.ball = before.ball
		inst.bond = before.bond
		inst.hp = before.hp
		say(ctx.name, "Your party is full, and no PC is near. " .. display .. " stays wild.")
		release(ctx)
		return
	end
	local pos = ctx.obj:get_pos()
	remove_ball(ctx, false)
	le._mm_capturing = nil
	mcl_util.remove_entity(le)
	puff(pos, true)
	core.sound_play(SOUND_CATCH, { pos = pos, max_hear_distance = 12 }, true)
	say(ctx.name, core.colorize(GOLD, L.caught_line(display)))
	minemon.events.fire("creature_captured", player, inst)
end

-- Runs the outcome: a caught creature joins the party, a broken one turns on the thrower, a lost connection releases.
local function conclude(ctx)
	if not (ctx.player:is_valid() and ctx.obj:is_valid()) or ctx.le._removed then
		release(ctx)
		return
	end
	if ctx.caught then
		catch(ctx)
	else
		break_free(ctx)
	end
end

-- Freezes and hides the creature, puts the ball on the ground and rolls the shakes. Returns a context for conclude,
-- or nil and a reason. The exhausted timer is paused until the outcome (its saved value comes back on release).
local function begin(player, obj, ball_id, rng)
	if player == nil or obj == nil or not player:is_valid() or not obj:is_valid() then
		return nil, "invalid"
	end
	local le = obj:get_luaentity()
	if le == nil or le._mm == nil then
		return nil, "not a creature"
	end
	if le._mm_capturing then
		return nil, "already capturing"
	end
	if not minemon.creatures.is_exhausted(obj) or minemon.creatures.is_owned(obj) then
		return nil, "not capturable"
	end
	local inst = le._mm
	local sp = species_of(inst)
	local base = L.catch_mult(minemon.data.get_item(ball_id))
	if sp == nil or base == nil then
		return nil, "unknown ball"
	end
	local mult = L.ball_mult(ball_id, inst, base)
	local max = minemon.instance.stats(inst, sp).hp
	local frac = max > 0 and inst.hp / max or 0
	local p = L.effective_p(ball_id, minemon.formulas.catch_chance(sp.catch_rate, frac, mult, inst.status))
	local n, caught = L.shakes(p, rng)

	local ctx = {
		player = player,
		name = player:get_player_name(),
		obj = obj,
		le = le,
		ball_id = ball_id,
		n = n,
		caught = caught,
		saved_t = le._mm_exhausted_t,
	}
	le._mm_capturing = true
	le._mm_exhausted_t = L.PAUSED_TIMER
	le.attack = nil
	stop_moving(obj)
	obj:set_properties({ is_visible = false })
	local pos = obj:get_pos()
	ctx.ball_obj = core.add_entity(vector.add(pos, vector.new(0, 0.3, 0)), BALL_VISUAL,
		core.write_json({ item = L.item_name(ball_id) }))
	return ctx
end

-- Starts a capture with the timed sequence. Returns true, or false and a reason.
function API.start(player, obj, ball_id)
	local rng = minemon.rng.new(math.floor(core.get_us_time() % 2147483646) + 1)
	local ctx, why = begin(player, obj, ball_id, rng)
	if ctx == nil then
		return false, why
	end
	local function step(i)
		if not (ctx.player:is_valid() and ctx.obj:is_valid()) then
			release(ctx)
			return
		end
		if i > ctx.n then
			core.after(0.3, function()
				conclude(ctx)
			end)
			return
		end
		wobble(ctx.ball_obj, function()
			core.sound_play(SOUND_CLICK, { pos = obj:get_pos(), max_hear_distance = 10 }, true)
			step(i + 1)
		end)
	end
	step(1)
	return true
end

-- Runs the whole outcome at once, with the given rng (tests). Returns the shakes and caught, or nil and a reason.
function API._resolve(player, obj, ball_id, rng)
	local ctx, why = begin(player, obj, ball_id, rng)
	if ctx == nil then
		return nil, why
	end
	remove_ball(ctx, false)
	conclude(ctx)
	return ctx.n, ctx.caught
end

-- What a ball does when it hits an object. Returns "drop", "bounce" or "capture". The ball lands at `at` unless it
-- is caught. Only a wild creature can be hit by a catch; a bounce turns the creature on the thrower.
function API._hit_object(player, ref, ball_id, at)
	local item = L.item_name(ball_id or "poke_ball")
	if player == nil or ref == nil or not ref:is_valid() then
		core.add_item(at, item)
		return "drop"
	end
	local is_wild = not ref:is_player() and minemon.creatures.get_instance(ref) ~= nil
		and not minemon.creatures.is_owned(ref)
	local outcome = L.hit_outcome(is_wild, is_wild and minemon.creatures.is_exhausted(ref))
	if outcome == "capture" then
		if API.start(player, ref, ball_id) then
			return "capture"
		end
		outcome = "drop"
	end
	if outcome == "bounce" then
		core.add_item(at, item)
		say(player:get_player_name(), L.too_strong_line())
		local le = ref:get_luaentity()
		if le and le.do_attack and type(player) == "userdata" then
			le:do_attack(player)
		end
		return "bounce"
	end
	core.add_item(at, item)
	return "drop"
end

-- Starter kit ------------------------------------------------------------------------------------------------------

local function kit_check(player)
	if player == nil or not player:is_valid() then
		return
	end
	local meta = player:get_meta()
	if not L.kit_due(#minemon.party.get(player), meta:get_string(KIT_KEY) == "1") then
		return
	end
	if not player.get_inventory then
		return
	end
	local name = player:get_player_name()
	local inv = player:get_inventory()
	local leftover = inv:add_item("main", ItemStack(L.item_name("poke_ball") .. " " .. L.KIT_BALLS))
	if not leftover:is_empty() then
		core.add_item(player:get_pos(), leftover)
	end
	meta:set_string(KIT_KEY, "1")
	say(name, "A starter kit: " .. L.KIT_BALLS .. " Poké Balls. Left click to throw one at an exhausted creature.")
end

core.register_on_joinplayer(function(player)
	kit_check(player)
end)

minemon.events.register("creature_sent_out", function(player)
	local name = player:get_player_name()
	core.after(2, function()
		kit_check(core.get_player_by_name(name))
	end)
end)

-- Admin --------------------------------------------------------------------------------------------------------------

core.register_chatcommand("give_balls", {
	params = "[n]",
	description = "Give yourself n Poké Balls (default 5, at most 64)",
	privs = { give = true },
	func = function(name, param)
		local p = core.get_player_by_name(name)
		if p == nil then
			return false, "You are not online."
		end
		local n = math.max(1, math.min(64, math.floor(tonumber(param) or L.KIT_BALLS)))
		local leftover = p:get_inventory():add_item("main", ItemStack(L.item_name("poke_ball") .. " " .. n))
		if not leftover:is_empty() then
			core.add_item(p:get_pos(), leftover)
		end
		return true, "Gave " .. n .. " Poké Balls."
	end,
})

return API
