-- minemon_growth (T-27, D-030): exp, levels, move learning, bond and evolution (stones and the Link Cable).
-- Glue: chat, formspecs, the evolution cinematic, the evolution items, the bond clock and the commands.
-- The rules are in growth_logic.lua (pure, busted-tested). Party members are written only through
-- minemon.party.update_member (by uid).
-- luacheck: read_globals core minemon vector
-- luacheck: globals minemon

local MODPATH = core.get_modpath("minemon_growth")
local LOGIC = dofile(MODPATH .. "/growth_logic.lua")

local ITEM_PREFIX = "minemon:"
local FORM_LEARN = "minemon_growth:learn"
local FORM_EVOLVE = "minemon_growth:evolve"
local GREEN = "#55FF55"
local GOLD = "#FFD700"
local SOUND_EVOLVE = "mcl_portals_open_end_portal" -- VoxeLibre, deep and ominous
local SOUND_LEVEL = "mcl_experience_level_up" -- VoxeLibre
local SPARK_TEXTURE = "minemon_combat_spark.png" -- minemon_combat's spark (ours)
local SMOKE_TEXTURE = "mcl_particles_smoke.png" -- VoxeLibre
local EVO_ITEM_KINDS = { evo_stone = true, held_evo = true, evo = true }
local CINE_TICK_S = 0.25 -- the cinematic's particles and glow run at this rate; the freeze runs every step
local BOND_TICK_S = 0.5
local LEARN_DELAY_S = 2 -- queued learn prompts reopen this long after a join

minemon.growth = minemon.growth or {}
local API = minemon.growth

local S = {
	players = {}, -- owner name -> the last player object that sent one of its creatures out
	queue = {}, -- owner name -> learn prompts, oldest first: { uid, move } (kept across a leave)
	cine = {}, -- owner name -> the running evolution cinematic
	bond_acc = {}, -- owner name -> seconds the active creature has been out
}

-- Helpers -------------------------------------------------------------------------------------------------------------

local function name_of(player)
	return player:get_player_name()
end

local function say(name, text)
	core.chat_send_player(name, text)
end

local function colour(hex, text)
	return core.colorize(hex, text)
end

local function player_valid(p)
	return p ~= nil and p:is_valid()
end

-- "cyndaquil" -> "Cyndaquil", "mr_mime" -> "Mr Mime" (the rule of minemon_party).
local function display_name(raw)
	local parts = {}
	for word in tostring(raw or ""):gmatch("[^_]+") do
		parts[#parts + 1] = word:sub(1, 1):upper() .. word:sub(2)
	end
	return table.concat(parts, " ")
end

local function label(m, sp)
	if m.nickname and m.nickname ~= "" then
		return m.nickname
	end
	return display_name(sp and sp.name or "creature")
end

local function species_of(m)
	return minemon.data.get_species(m.species_id)
end

local function move_name(id)
	local mv = minemon.data.get_move(id)
	return mv and mv.name or display_name(id)
end

local function pp_of(id)
	local mv = minemon.data.get_move(id)
	return mv and mv.pp or 0
end

-- The player object for an owner name: the online player, else the last object that sent a creature out.
local function player_for(name)
	local p = core.get_player_by_name(name)
	if p ~= nil then
		return p
	end
	local tracked = S.players[name]
	if player_valid(tracked) then
		return tracked
	end
	return nil
end

-- The member with this uid, and its index in the party.
local function find(player, uid)
	for i, m in ipairs(minemon.party.get(player)) do
		if m.uid == uid then
			return m, i
		end
	end
	return nil, nil
end

-- The uid of the active creature, or nil.
local function active_uid(player)
	local obj = minemon.party.get_active(player)
	if obj == nil then
		return nil
	end
	local inst = minemon.creatures.get_instance(obj)
	return inst and inst.uid or nil
end

-- The uid of the active creature, else of the lead; nil when nobody is alive.
local function target_uid(player)
	local uid = active_uid(player)
	if uid ~= nil then
		return uid
	end
	local idx = minemon.party.lead_index(player)
	if idx == nil then
		return nil
	end
	return minemon.party.get(player)[idx].uid
end

-- Changes one member by uid through the party (the only write path).
local function write(player, uid, fn)
	return minemon.party.update_member(player, uid, fn)
end

local function has_item(player, id)
	local inv = player:get_inventory()
	return inv ~= nil and inv:contains_item("main", ITEM_PREFIX .. id)
end

-- Context for the evolution rules. used_item is an item id (for example "thunder_stone") or nil.
local function context(player, used_item, m, sp)
	return {
		is_night = LOGIC.is_night(core.get_timeofday()),
		used_item = used_item,
		link_cable = used_item == "link_cable",
		inventory_has = function(id)
			return has_item(player, id)
		end,
		stats = minemon.instance.stats(m, sp),
	}
end

-- Learn prompts -------------------------------------------------------------------------------------------------------

local function learn_formspec(m, move_id)
	local sp = species_of(m)
	local mv = minemon.data.get_move(move_id) or {}
	local power = mv.power and tostring(mv.power) or "--"
	local line1 = string.format("%s wants to learn %s.", label(m, sp), mv.name or display_name(move_id))
	local line2 = string.format("(%s, %s power). Forget a move?", display_name(mv.type or "normal"), power)
	local fs = {
		"size[8,6.6]",
		"label[0.4,0.4;" .. core.formspec_escape(line1) .. "]",
		"label[0.4,0.85;" .. core.formspec_escape(line2) .. "]",
	}
	for i, slot in ipairs(m.moves) do
		local sm = minemon.data.get_move(slot.id) or {}
		local text = string.format("%s  (%s, %s PP)", sm.name or display_name(slot.id),
			display_name(sm.type or "normal"), tostring(slot.pp or 0))
		fs[#fs + 1] = string.format("button[0.4,%.2f;7.2,0.8;replace_%d;%s]", 1.5 + (i - 1) * 0.9, i,
			core.formspec_escape(text))
	end
	fs[#fs + 1] = "button[0.4,5.5;7.2,0.8;keep;Don't learn]"
	return table.concat(fs)
end

-- Shows the head of the prompt queue, unless the evolution cinematic is on screen (the prompts wait for it).
local function pump(player)
	local name = name_of(player)
	if S.cine[name] ~= nil then
		return
	end
	local q = S.queue[name] or {}
	while #q > 0 do
		local head = q[1]
		local m = find(player, head.uid)
		if m ~= nil then
			core.show_formspec(name, FORM_LEARN, learn_formspec(m, head.move))
			return
		end
		table.remove(q, 1) -- the member is gone
	end
end

-- Learns what a member can learn from candidates: free slots at once (chat line each), the rest as queued prompts.
local function learn(player, uid, candidates)
	local name = name_of(player)
	local m = find(player, uid)
	if m == nil or #candidates == 0 then
		return
	end
	local pending = {}
	for _, item in ipairs(S.queue[name] or {}) do
		if item.uid == uid then
			pending[#pending + 1] = item.move
		end
	end
	local plan = nil
	write(player, uid, function(mm)
		plan = LOGIC.plan_learns(mm.moves, candidates, pending, pp_of)
		mm.moves = plan.moves
	end)
	if plan == nil then
		return
	end
	for _, id in ipairs(plan.learned) do
		say(name, string.format("%s learned %s!", label(m, species_of(m)), move_name(id)))
	end
	if #plan.prompts > 0 then
		local q = S.queue[name] or {}
		S.queue[name] = q
		for _, id in ipairs(plan.prompts) do
			q[#q + 1] = { uid = uid, move = id }
		end
		pump(player)
	end
end

-- A button on the prompt: replace the slot, or "Don't learn". Closing the formspec counts as "Don't learn".
local function handle_learn(player, fields)
	local name = name_of(player)
	local q = S.queue[name] or {}
	local head = q[1]
	if head == nil then
		return
	end
	local chosen = nil
	for i = 1, LOGIC.MAX_MOVES do
		if fields["replace_" .. i] ~= nil then
			chosen = i
			break
		end
	end
	if chosen == nil and fields.keep == nil and fields.quit == nil then
		return
	end
	table.remove(q, 1)
	local m = find(player, head.uid)
	local forgot = nil
	if m ~= nil and chosen ~= nil then
		write(player, head.uid, function(mm)
			local new = LOGIC.replace_move(mm.moves, chosen, head.move, pp_of(head.move))
			if new ~= nil then
				forgot = mm.moves[chosen].id
				mm.moves = new
			end
		end)
	end
	if m ~= nil then
		if forgot ~= nil then
			say(name, string.format("%s forgot %s and learned %s!", label(m, species_of(m)), move_name(forgot),
				move_name(head.move)))
		else
			say(name, string.format("%s did not learn %s.", label(m, species_of(m)), move_name(head.move)))
		end
	end
	pump(player)
end

-- Evolution cinematic -------------------------------------------------------------------------------------------------

local function evolve_formspec(text)
	return table.concat({
		"size[6,3]",
		"label[0.4,0.6;What? " .. core.formspec_escape(text) .. " is evolving!]",
		"button[1.5,1.5;3,0.9;stop;Stop it!]",
	})
end

-- Gives back the creature's own look: glow off. Safe when the entity is gone.
local function restore(run)
	local obj = run.obj
	if obj ~= nil and obj:is_valid() then
		obj:set_properties({ glow = 0 })
	end
end

-- Holds the creature still in place for the whole cinematic (every globalstep: it is one entity).
local function freeze(run)
	local obj = run.obj
	if obj == nil or not obj:is_valid() or run.frozen == nil then
		return
	end
	obj:set_velocity(vector.new(0, 0, 0))
	obj:set_pos(run.frozen)
end

-- Glow flicker and the dark spiral, every CINE_TICK_S: two purple and one black particle per tick.
local function visuals(run)
	local obj = run.obj
	if obj == nil or not obj:is_valid() or run.frozen == nil then
		return
	end
	local glow = math.floor(7 + 7 * math.abs(math.sin(run.t * 23)))
	obj:set_properties({ glow = glow })
	local f = run.frozen
	for k = 0, 2 do
		local s = LOGIC.spiral(run.t + k * 0.1)
		local a = s.angle + k * (2 * math.pi / 3)
		local px = f.x + math.cos(a) * s.radius
		local py = f.y + 0.5 + s.height
		local pz = f.z + math.sin(a) * s.radius
		local dark = (k == 1) and "#0a0a0a" or "#5a1f7a"
		core.add_particle({
			pos = { x = px, y = py, z = pz },
			velocity = { x = (f.x - px) * 2, y = -0.8, z = (f.z - pz) * 2 },
			acceleration = { x = 0, y = 0, z = 0 },
			expirationtime = 0.6,
			size = 2.2,
			collisiondetection = false,
			texture = SMOKE_TEXTURE .. "^[colorize:" .. dark .. ":230",
			glow = 6,
		})
	end
end

-- Takes the item(s) of a use from the inventory. Returns false, changing nothing, when one is missing.
local function consume_items(player, consume)
	local inv = player:get_inventory()
	if inv == nil then
		return false
	end
	local ids = { consume.item }
	if consume.held ~= nil then
		ids[#ids + 1] = consume.held
	end
	for _, id in ipairs(ids) do
		if not inv:contains_item("main", ITEM_PREFIX .. id) then
			return false
		end
	end
	for _, id in ipairs(ids) do
		inv:remove_item("main", ITEM_PREFIX .. id)
	end
	return true
end

-- The evolution itself: recall if out, the new species keeps uid, nickname, ivs, exp, bond, moves and status, the HP
-- fraction is kept, then the creature goes out again if it was out. Returns true when it evolved.
local function evolve(player, uid, to)
	local name = name_of(player)
	local m = find(player, uid)
	local sp_to = minemon.data.get_species(to)
	if m == nil or sp_to == nil then
		return false
	end
	local sp_from = species_of(m)
	if sp_from == nil or m.species_id == to then
		return false
	end
	local old_id = m.species_id
	local old_label = label(m, sp_from)
	local was_out = active_uid(player) == uid
	if was_out then
		minemon.party.recall(player)
	end
	write(player, uid, function(mm)
		local old_max = minemon.instance.stats(mm, sp_from).hp
		mm.species_id = to
		local new_max = minemon.instance.stats(mm, sp_to).hp
		mm.hp = LOGIC.rescale_hp(mm.hp, old_max, new_max)
	end)
	local m2, index = find(player, uid)
	if m2 == nil then
		return false
	end
	say(name, colour(GOLD, string.format("%s evolved into %s!", old_label, label(m2, sp_to))))
	if was_out and index ~= nil then
		minemon.party.send_out(player, index)
	end
	-- The new species' moves at the current level (entries with level == m2.level); older moves are not offered.
	learn(player, uid, LOGIC.learn_candidates(sp_to.learnset, m2.level - 1, m2.level))
	minemon.events.fire("creature_evolved", player, m2, old_id)
	return true
end

-- Starts the cinematic: the creature (if it is out) is frozen and lit; the formspec stays for 6 s. consume is the
-- item set to take when it completes (nil for a level-up). Returns false when one is already running.
local function start_cinematic(player, uid, to, consume)
	local name = name_of(player)
	if S.cine[name] ~= nil then
		return false
	end
	local m = find(player, uid)
	if m == nil then
		return false
	end
	local obj = nil
	if active_uid(player) == uid then
		obj = minemon.party.get_active(player)
	end
	local frozen = nil
	if obj ~= nil then
		frozen = obj:get_pos()
	end
	local run = {
		name = name,
		player = player,
		uid = uid,
		to = to,
		consume = consume,
		label = label(m, species_of(m)),
		t = 0,
		acc = 0,
		obj = obj,
		frozen = frozen,
	}
	S.cine[name] = run
	if frozen ~= nil then
		core.sound_play(SOUND_EVOLVE, { pos = frozen, gain = 0.8, max_hear_distance = 32 })
	end
	core.show_formspec(name, FORM_EVOLVE, evolve_formspec(run.label))
	return true
end

-- "Stop it!": the cinematic ends, nothing changes, and the creature is free again.
local function stop_cinematic(player)
	local name = name_of(player)
	local run = S.cine[name]
	if run == nil then
		return
	end
	S.cine[name] = nil
	restore(run)
	core.close_formspec(name, FORM_EVOLVE)
	say(name, run.label .. " stopped evolving.")
	pump(player)
end

-- The 6 s are up: take the items, then evolve.
local function complete_cinematic(name)
	local run = S.cine[name]
	if run == nil then
		return
	end
	S.cine[name] = nil
	restore(run)
	core.close_formspec(name, FORM_EVOLVE)
	local player = run.player
	if not player_valid(player) then
		return
	end
	if run.consume ~= nil and not consume_items(player, run.consume) then
		say(name, run.label .. " stopped evolving.")
		return
	end
	evolve(player, run.uid, run.to)
	pump(player)
end

-- Exp and levels ------------------------------------------------------------------------------------------------------

local function sparkle(obj)
	core.add_particlespawner({
		amount = 36,
		time = 0.6,
		minpos = { x = -0.5, y = 0.2, z = -0.5 },
		maxpos = { x = 0.5, y = 1.2, z = 0.5 },
		minvel = { x = -0.6, y = 0.6, z = -0.6 },
		maxvel = { x = 0.6, y = 1.6, z = 0.6 },
		minacc = { x = 0, y = -0.5, z = 0 },
		maxacc = { x = 0, y = -0.5, z = 0 },
		minexptime = 0.6,
		maxexptime = 1.0,
		minsize = 1.0,
		maxsize = 2.0,
		texture = SPARK_TEXTURE,
		glow = 12,
		attached = obj,
	})
end

-- After a level-up: an evolution whose conditions hold (level-only, or level plus another condition) starts.
local function maybe_evolve(player, uid)
	local m = find(player, uid)
	if m == nil then
		return
	end
	local sp = species_of(m)
	if sp == nil then
		return
	end
	local evo = LOGIC.matching_evolution(m, sp, context(player, nil, m, sp))
	if evo ~= nil then
		start_cinematic(player, uid, evo.to, nil)
	end
end

-- Adds exp to a member: each level recomputes the stats (HP fraction kept) and adds bond; then the learnset and the
-- evolution check. Returns the exp added.
local function grant_exp(player, uid, gain)
	local name = name_of(player)
	gain = math.floor(tonumber(gain) or 0)
	local m0 = find(player, uid)
	if m0 == nil or gain <= 0 then
		return 0
	end
	local sp = species_of(m0)
	if sp == nil then
		return 0
	end
	local old_level = m0.level
	local levels = {}
	write(player, uid, function(m)
		local prev_max = minemon.instance.stats(m, sp).hp
		m.exp = m.exp + gain
		local target = LOGIC.level_after(minemon.formulas, m.exp, sp.growth_rate, m.level)
		while m.level < target do
			m.level = m.level + 1
			m.bond = LOGIC.bond_after_level(m.bond)
			local new_max = minemon.instance.stats(m, sp).hp
			m.hp = LOGIC.rescale_hp(m.hp, prev_max, new_max)
			prev_max = new_max
			levels[#levels + 1] = m.level
		end
	end)
	if #levels == 0 then
		return gain
	end
	local m = find(player, uid)
	for _, lv in ipairs(levels) do
		say(name, colour(GREEN, string.format("%s grew to Lv %d!", label(m, sp), lv)))
	end
	if active_uid(player) == uid then
		local obj = minemon.party.get_active(player)
		if obj ~= nil then
			sparkle(obj)
		end
	end
	if core.get_player_by_name(name) ~= nil then
		core.sound_play(SOUND_LEVEL, { to_player = name, gain = 0.6 })
	end
	learn(player, uid, LOGIC.learn_candidates(sp.learnset, old_level, m.level))
	maybe_evolve(player, uid)
	return gain
end

-- Items ---------------------------------------------------------------------------------------------------------------

-- A stone or the Link Cable, used on the target creature. Matches a conditions set with this item; then the cinematic
-- (or, with instant, the items are taken and it evolves at once). Otherwise "It had no effect.".
local function use_item(player, id, instant)
	local name = name_of(player)
	if S.cine[name] ~= nil then
		say(name, "Something is already changing.")
		return false
	end
	local uid = target_uid(player)
	local m = nil
	if uid ~= nil then
		m = find(player, uid)
	end
	local sp = m and species_of(m) or nil
	local evo = nil
	if sp ~= nil then
		evo = LOGIC.matching_evolution(m, sp, context(player, id, m, sp))
	end
	if evo == nil then
		say(name, "It had no effect.")
		return false
	end
	local consume = { item = id, held = evo.conditions.held_item }
	if instant then
		if not consume_items(player, consume) then
			say(name, "It had no effect.")
			return false
		end
		return evolve(player, uid, evo.to)
	end
	return start_cinematic(player, uid, evo.to, consume)
end

local function use_from_hand(user, id)
	if user == nil or not user:is_player() then
		return
	end
	use_item(user, id, false)
end

-- Reads items.json (the same file minemon_core parses) for the evolution items.
local function read_items()
	local path = core.get_modpath("minemon_core") .. "/data/items.json"
	local f = io.open(path, "rb")
	if not f then
		return {}
	end
	local text = f:read("*a")
	f:close()
	local parsed = core.parse_json(text, nil, true)
	if type(parsed) ~= "table" then
		return {}
	end
	return parsed
end

for id, raw in pairs(read_items()) do
	if type(raw) == "table" and EVO_ITEM_KINDS[raw.kind] then
		local item_id = id
		core.register_craftitem(":" .. ITEM_PREFIX .. item_id, {
			description = raw.name or item_id,
			inventory_image = "minemon_evo_" .. item_id .. ".png",
			stack_max = 64,
			groups = { craftitem = 1 },
			on_place = function(_stack, placer)
				use_from_hand(placer, item_id)
				return nil
			end,
			on_secondary_use = function(_stack, user)
				use_from_hand(user, item_id)
				return nil
			end,
		})
	end
end

-- The attacker's beneficiary: a player's active creature, or an owned creature itself. Returns player, uid or nil.
local function beneficiary(attacker)
	if attacker.is_player and attacker:is_player() then
		local uid = active_uid(attacker)
		if uid == nil then
			return nil
		end
		return attacker, uid
	end
	if minemon.creatures.is_owned(attacker) then
		local owner = minemon.creatures.owner_name(attacker)
		local inst = minemon.creatures.get_instance(attacker)
		local p = nil
		if type(owner) == "string" then
			p = player_for(owner)
		end
		if p == nil or inst == nil then
			return nil
		end
		return p, inst.uid
	end
	return nil
end

-- Bond clock ----------------------------------------------------------------------------------------------------------

local function bond_clock(dt)
	for _, player in ipairs(core.get_connected_players()) do
		local name = name_of(player)
		local uid = active_uid(player)
		if uid == nil then
			S.bond_acc[name] = nil
		else
			local acc, points = LOGIC.bond_tick(S.bond_acc[name], dt)
			S.bond_acc[name] = acc
			if points > 0 then
				write(player, uid, function(m)
					m.bond = LOGIC.add_bond(m.bond, points)
				end)
			end
		end
	end
end

local bond_acc_t = 0

core.register_globalstep(function(dtime)
	if next(S.cine) ~= nil then
		local done = {}
		for name, run in pairs(S.cine) do
			run.t = run.t + dtime
			freeze(run)
			run.acc = run.acc + dtime
			if run.acc >= CINE_TICK_S then
				run.acc = 0
				visuals(run)
			end
			if run.t >= LOGIC.CINEMATIC_S then
				done[#done + 1] = name
			end
		end
		for _, name in ipairs(done) do
			complete_cinematic(name)
		end
	end
	bond_acc_t = bond_acc_t + dtime
	if bond_acc_t >= BOND_TICK_S then
		local dt = bond_acc_t
		bond_acc_t = 0
		bond_clock(dt)
	end
end)

-- Events and players --------------------------------------------------------------------------------------------------

-- The creature_defeated contract (M1, fired by T-26 when a wild creature becomes exhausted).
minemon.events.register("creature_defeated", function(victim_le, attacker)
	if attacker == nil or victim_le == nil or victim_le._mm == nil then
		return
	end
	local victim = victim_le._mm
	local vsp = minemon.data.get_species(victim.species_id)
	if vsp == nil then
		return
	end
	local player, uid = beneficiary(attacker)
	if player == nil or uid == nil then
		return
	end
	local m = find(player, uid)
	if m == nil then
		return
	end
	grant_exp(player, uid, minemon.formulas.exp_gain(vsp.base_exp, victim.level, m.bond))
end)

-- A fainted owned creature loses 5 bond. The party's own handler runs first (it depends on this mod's party).
minemon.events.register("creature_fainted", function(obj, owner)
	if type(owner) ~= "string" or owner == "" then
		return
	end
	local le = obj:get_luaentity()
	local inst = le and le._mm
	if inst == nil then
		return
	end
	local p = player_for(owner)
	if p == nil then
		return
	end
	write(p, inst.uid, function(m)
		m.bond = LOGIC.add_bond(m.bond, LOGIC.BOND_FAINT)
	end)
end)

minemon.events.register("creature_sent_out", function(player, _obj)
	S.players[name_of(player)] = player
end)

core.register_on_player_receive_fields(function(player, formname, fields)
	if formname == FORM_LEARN then
		handle_learn(player, fields)
		return true
	end
	if formname == FORM_EVOLVE then
		if fields.stop ~= nil then
			stop_cinematic(player)
		end
		return true
	end
	return nil
end)

core.register_on_joinplayer(function(player)
	local name = name_of(player)
	if #(S.queue[name] or {}) > 0 then
		core.after(LEARN_DELAY_S, function()
			local p = core.get_player_by_name(name)
			if p ~= nil then
				pump(p)
			end
		end)
	end
end)

core.register_on_leaveplayer(function(player)
	local name = name_of(player)
	local run = S.cine[name]
	if run ~= nil then
		S.cine[name] = nil
		restore(run)
	end
	S.bond_acc[name] = nil
end)

-- Chat commands -------------------------------------------------------------------------------------------------------

core.register_chatcommand("exp", {
	description = "Show the level and exp of your active creature",
	func = function(name)
		local p = core.get_player_by_name(name)
		if p == nil then
			return false, "You are not online."
		end
		local uid = active_uid(p)
		if uid == nil then
			return false, "No creature is out. Send one out with the Party Ball first."
		end
		local m = find(p, uid)
		local sp = m and species_of(m) or nil
		if m == nil or sp == nil then
			return false, "No creature is out."
		end
		local who = label(m, sp)
		if m.level >= LOGIC.MAX_LEVEL then
			return true, string.format("%s: Lv %d, exp %d (max level)", who, m.level, m.exp)
		end
		local need = minemon.formulas.exp_for_level(m.level + 1, sp.growth_rate)
		return true, string.format("%s: Lv %d, exp %d, next level at %d (%d to go)", who, m.level, m.exp, need,
			math.max(0, need - m.exp))
	end,
})

core.register_chatcommand("givexp", {
	params = "<n>",
	description = "Give exp to your active creature, or to your lead when none is out (privilege give)",
	privs = { give = true },
	func = function(name, param)
		local n = math.floor(tonumber(param) or 0)
		if n <= 0 then
			return false, "Usage: /givexp <n>, with n of 1 or more."
		end
		local p = core.get_player_by_name(name)
		if p == nil then
			return false, "You are not online."
		end
		local uid = target_uid(p)
		if uid == nil then
			return false, "No creature to receive exp."
		end
		grant_exp(p, uid, n)
		return true, string.format("Gave %d exp.", n)
	end,
})

-- Bond shows as hearts in the party formspec (ui.lua calls this hook).
minemon.party.bond_text = function(m)
	return string.rep("♥", LOGIC.hearts(m.bond))
end

-- Public API ----------------------------------------------------------------------------------------------------------

function API.grant_exp(player, uid, gain)
	return grant_exp(player, uid, gain)
end

-- Test hooks (T-27 brief): the evolution without the 6 s cinematic. _evolve_now ends a running cinematic first.
function API._evolve_now(player, uid, to)
	local name = name_of(player)
	local run = S.cine[name]
	if run ~= nil then
		S.cine[name] = nil
		restore(run)
		core.close_formspec(name, FORM_EVOLVE)
	end
	return evolve(player, uid, to)
end

function API._use_item_now(player, id)
	return use_item(player, id, true)
end

-- More test hooks: the cinematic state, the learn queue, and the two formspec answers without a real player.
function API._cinematic(name)
	return S.cine[name]
end

function API._pending(name)
	return #(S.queue[name] or {})
end

function API._answer_evolve(player, fields)
	if fields.stop ~= nil then
		stop_cinematic(player)
	end
end

function API._answer_learn(player, fields)
	handle_learn(player, fields)
end

return API
