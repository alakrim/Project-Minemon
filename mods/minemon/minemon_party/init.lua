-- minemon_party: the player's party, the starter, the Party Ball and the owned creature (T-22, M1 contract).
-- Glue: storage in player meta, the active creature per player, the events and the globalstep. The rules are in
-- party_logic.lua (pure, busted-tested). brain.lua is the owned brain (D-027), ui.lua the formspecs, the party HUD,
-- the Party Ball item and the chat commands.
--
-- The party list lives in self.cache[name]. The active member is the same table as its entity's _mm, so HP changes
-- from the damage path land in the list at once; the list is written to player meta on every change and every 5 s.
-- luacheck: read_globals core minemon mcl_util vector
-- luacheck: globals minemon

local MODPATH = core.get_modpath("minemon_party")
local LOGIC = dofile(MODPATH .. "/party_logic.lua")

local KEY = "minemon:party:list"
local BALL = "minemon_party:party_ball"
local SAVE_S = 5 -- the party list is written to player meta at least this often
local TICK_S = 0.5 -- regeneration, the faint timer and the HUD refresh run at this rate

minemon.party = minemon.party or {}
local API = minemon.party

local S = {
	LOGIC = LOGIC,
	BALL = BALL,
	active = {}, -- owner name -> { obj, guid, uid, name, player, target, walking }
	cache = {}, -- owner name -> party list (members are shared with the entities' _mm)
	timers = {}, -- uid -> { regen = seconds }; recalled creatures only, not persisted
	hud_dirty = {}, -- owner name -> true when the HUD needs a refresh
	starter = {}, -- owner name -> { reopens = n }
	rng = minemon.rng.new(math.floor(core.get_us_time() % 2147483646) * 1000003 + 1),
}

local UI -- set after ui.lua loads (the chooser and the HUD)

local function name_of(player)
	return player:get_player_name()
end

local function species_of(m)
	return minemon.data.get_species(m.species_id)
end

-- The name shown to the player for a member: nickname or species name.
function S.member_display(m)
	local sp = species_of(m)
	return LOGIC.member_name(m, sp and sp.name or "creature")
end

function S.say(name, text)
	core.chat_send_player(name, text)
end

function S.mark(name)
	S.hud_dirty[name] = true
end

function S.is_dead(player)
	local lives = minemon.lives
	if lives == nil or lives.get == nil then
		return false
	end
	local state = lives.get(player)
	return state ~= nil and state.dead == true
end

local function is_starter(species_id)
	for _, id in ipairs(LOGIC.STARTERS) do
		if id == species_id then
			return true
		end
	end
	return false
end

-- Storage ----------------------------------------------------------------------------------------------------------

-- The party of a player, loaded from player meta the first time (then cached).
function S.list(player)
	local name = name_of(player)
	local list = S.cache[name]
	if list == nil then
		local raw = player:get_meta():get_string(KEY)
		local parsed = nil
		if raw ~= "" then
			local ok, value = pcall(core.parse_json, raw)
			if ok then
				parsed = value
			end
		end
		list = LOGIC.load(parsed, minemon.instance.deserialize)
		S.cache[name] = list
	end
	return list
end

-- Writes the cached party to player meta.
function S.save(player)
	local list = S.cache[name_of(player)]
	if list == nil then
		return
	end
	player:get_meta():set_string(KEY, core.write_json(LOGIC.save(list, minemon.instance.serialize)))
end

-- The active record of a player, if its entity still exists. An entity that vanished without a faint event (for
-- example removed by mcl_void_damage) counts as recalled: the member is written back as it was last synced.
function S.active_rec(name)
	local rec = S.active[name]
	if rec == nil then
		return nil
	end
	local le = rec.obj:is_valid() and rec.obj:get_luaentity() or nil
	if le == nil or le._removed then
		core.log("action", "[minemon_party] active creature of " .. tostring(name) .. " vanished; recalled")
		S.recall(name, true)
		return nil
	end
	return rec
end

-- The member the active creature of a player stands for, or nil.
function S.active_member(name)
	local rec = S.active_rec(name)
	if rec == nil then
		return nil
	end
	return rec.obj:get_luaentity()._mm
end

-- Sets the entity's stats from its member: HP, max HP, the nametag. Safe to call again.
local function refresh_entity(le, m, species)
	local obj = le.object
	local st = minemon.instance.stats(m, species)
	le.hp_max = st.hp
	le.health = m.hp
	le.old_health = m.hp
	le.nametag = string.format("%s Lv %d", LOGIC.member_name(m, species.name), m.level)
	obj:set_properties({ hp_max = st.hp })
	obj:set_hp(math.max(1, m.hp))
	le:update_tag()
end

-- Taking over an entity after its party list was replaced (API.set): the entity follows the new member, or leaves.
local function rebind(name)
	local rec = S.active_rec(name)
	if rec == nil then
		return
	end
	local list = S.cache[name] or {}
	local i = LOGIC.index_of(list, rec.uid)
	if i == nil then
		S.recall(name, true)
		return
	end
	local le = rec.obj:get_luaentity()
	local species = species_of(list[i])
	if species == nil then
		S.recall(name, true)
		return
	end
	le._mm = list[i]
	refresh_entity(le, list[i], species)
end

-- Sending out, recalling and fainting ------------------------------------------------------------------------------

-- Spawns the lead (or the member at index) 2 m in front of the player. Returns true, or false and a reason.
function S.send_out(player, index)
	local name = name_of(player)
	if S.active_rec(name) then
		return false, "already out"
	end
	local list = S.list(player)
	index = index or LOGIC.lead_index(list)
	if index == nil then
		S.say(name, "All your creatures have fainted.")
		return false, "none alive"
	end
	local m = list[index]
	if m == nil then
		return false, "no such member"
	end
	if not LOGIC.is_alive(m) then
		S.say(name, S.member_display(m) .. " has fainted and cannot be sent out.")
		return false, "fainted"
	end
	local species = species_of(m)
	if species == nil then
		return false, "unknown species"
	end
	local spot = LOGIC.in_front(player:get_pos(), player:get_look_dir())
	local obj = minemon.creatures.spawn(vector.new(spot.x, spot.y, spot.z), m.species_id, m.level, name)
	if obj == nil then
		return false, "spawn failed"
	end
	-- The spawn made a new instance; the party member replaces it (same uid), then the entity takes its stats.
	local le = obj:get_luaentity()
	m.owner = name
	le._mm = m
	le._mm_party = true -- only creatures sent out by the party are managed by the owned brain (D-028)
	le.owner = name
	le.tamed = true
	refresh_entity(le, m, species)
	S.active[name] = {
		obj = obj,
		guid = obj:get_guid(),
		uid = m.uid,
		name = name,
		player = player,
		target = nil,
		walking = false,
	}
	S.say(name, "Go, " .. LOGIC.member_name(m, species.name) .. "!")
	minemon.events.fire("creature_sent_out", player, obj)
	S.mark(name)
	return true
end

-- Removes the active creature. The member is already in the list (shared table), so this only saves and removes the
-- entity. quiet: no "come back" line (death, leave, the owner being offline).
function S.recall(name, quiet)
	local rec = S.active[name]
	if rec == nil then
		return false
	end
	S.active[name] = nil
	local le = rec.obj:is_valid() and rec.obj:get_luaentity() or nil
	local display = nil
	if le ~= nil and le._mm ~= nil then
		display = S.member_display(le._mm)
	end
	if le ~= nil and not le._removed then
		mcl_util.remove_entity(le)
	end
	if rec.player ~= nil and rec.player:is_valid() then
		S.save(rec.player)
	end
	S.mark(name)
	if not quiet and display ~= nil then
		S.say(name, display .. ", come back!")
	end
	minemon.events.fire("creature_recalled", rec.player)
	return true
end

-- The creature_fainted handler: the member keeps HP 0, the entity is removed, the lead moves on.
function S.on_fainted(obj, owner)
	if type(owner) ~= "string" or owner == "" then
		return
	end
	local le = obj:get_luaentity()
	local m = le and le._mm
	if m == nil then
		return
	end
	local rec = S.active[owner]
	local keep_player = rec and rec.player or nil
	if rec ~= nil and rec.guid == obj:get_guid() then
		S.active[owner] = nil
	end
	m.hp = 0
	m.faint_s = 0
	-- Removed on the next step, not now: this runs inside the attacker's punch, and the attacker's code reads the
	-- target's position after the punch returns (a nil position there is an error in mcl's dogfight path).
	if le ~= nil then
		le._party_fainted = true
		core.after(0, function()
			if le.object:is_valid() and not le._removed then
				mcl_util.remove_entity(le)
			end
		end)
	end
	local p = core.get_player_by_name(owner) or keep_player
	S.say(owner, core.colorize("#FF3030", S.member_display(m) .. " fainted!"))
	if p ~= nil then
		local list = S.list(p)
		local lead = LOGIC.lead_index(list)
		if lead then
			S.say(owner, "Next up: " .. S.member_display(list[lead]) .. ".")
		else
			S.say(owner, "All your creatures have fainted.")
		end
		S.save(p)
	end
	S.mark(owner)
end

-- An owned entity with no active record (after a restart): its member gets the entity's HP when the owner is online,
-- then the entity is removed.
function S.orphan(le)
	local name = le.owner
	local m = le._mm
	local p = nil
	if type(name) == "string" and name ~= "" then
		p = core.get_player_by_name(name)
	end
	if p ~= nil and m ~= nil then
		local list = S.list(p)
		local i = LOGIC.index_of(list, m.uid)
		if i ~= nil then
			list[i].hp = m.hp
			S.save(p)
			S.mark(name)
		end
	end
	core.log("action", "[minemon_party] removed an owned creature with no active record (owner " .. tostring(name) .. ")")
	mcl_util.remove_entity(le)
end

-- Starter and HP -----------------------------------------------------------------------------------------------------

-- The starter choice: a level 5 member, the Party Ball, the join line. Only for an empty party.
function S.choose_starter(player, species_id)
	local name = name_of(player)
	if #S.list(player) > 0 then
		return false, "party is not empty"
	end
	local species = minemon.data.get_species(species_id)
	if species == nil or not is_starter(species.id) then
		return false, "not a starter"
	end
	local m = minemon.instance.new(species, LOGIC.STARTER_LEVEL, S.rng)
	LOGIC.ensure(m)
	m.owner = name
	S.cache[name] = { m }
	S.save(player)
	local inv = player.get_inventory and player:get_inventory() or nil
	if inv ~= nil then
		inv:add_item("main", BALL)
	end
	S.say(name, LOGIC.member_name(m, species.name) .. " joined you. Stay close — the wild is dangerous.")
	S.starter[name] = nil
	S.mark(name)
	return true, m
end

-- Clears the status and refills the PP of every move (T-28: the Sanctuary altar). PP maxima come from the move data.
local function refill(m)
	m.status = "none"
	for _, mv in ipairs(m.moves or {}) do
		local move = minemon.data.get_move(mv.id)
		if move ~= nil and type(move.pp) == "number" then
			mv.pp = move.pp
		end
	end
end

-- Heals every member: HP to max, status cleared, PP refilled. The active one is healed through the creature API, so
-- its entity agrees.
function S.heal_all(player)
	local name = name_of(player)
	local list = S.list(player)
	local rec = S.active_rec(name)
	for _, m in ipairs(list) do
		local sp = species_of(m)
		if sp ~= nil then
			if rec ~= nil and rec.uid == m.uid then
				minemon.creatures.heal(rec.obj, 9999)
			else
				m.hp = minemon.instance.stats(m, sp).hp
			end
			m.faint_s = 0
			refill(m)
		end
	end
	S.save(player)
	S.mark(name)
end

-- Orders the active creature to attack target. move_name (T-29, optional): the order names the move, "<Name>, use
-- <Move>!", as the command bar does. Returns true when the order was given.
function S.order(player, target, move_name)
	local name = name_of(player)
	local rec = S.active_rec(name)
	if rec == nil or target == nil or not target:is_valid() or target:is_player() then
		return false
	end
	if minemon.creatures.get_instance(target) == nil or minemon.creatures.is_owned(target) then
		return false
	end
	rec.target = target
	local who = S.member_display(rec.obj:get_luaentity()._mm)
	if move_name then
		S.say(name, who .. ", use " .. move_name .. "!")
	else
		S.say(name, who .. ", attack!")
	end
	return true
end

-- Replaces the party list of a player (admin and tests). Members beyond MAX and duplicates are dropped.
function S.set(player, list)
	local name = name_of(player)
	local out = {}
	for _, m in ipairs(list or {}) do
		if #out < LOGIC.MAX and type(m) == "table" and type(m.uid) == "string"
			and LOGIC.index_of(out, m.uid) == nil then
			out[#out + 1] = LOGIC.ensure(m)
		end
	end
	S.cache[name] = out
	rebind(name)
	S.save(player)
	S.mark(name)
end

-- Joins, leaves, deaths -------------------------------------------------------------------------------------------

-- Regeneration and the faint timer for the members that are not out. Returns true when an HP changed.
local function tick_members(list, dt, active_uid)
	local changed = false
	for _, m in ipairs(list) do
		if m.uid ~= active_uid then
			local species = species_of(m)
			if species ~= nil then
				local max = minemon.instance.stats(m, species).hp
				if m.hp > 0 then
					local t = S.timers[m.uid] or {}
					S.timers[m.uid] = t
					local acc, hp = LOGIC.regen_step(t.regen, m.hp, max, dt)
					t.regen = acc
					if hp ~= m.hp then
						m.hp = hp
						changed = true
					end
				else
					local left, revived = LOGIC.revive_step(m.faint_s, dt)
					m.faint_s = left
					if revived then
						m.hp = 1
						changed = true
					end
				end
			end
		end
	end
	return changed
end

local tick_acc = 0
local save_acc = 0

core.register_globalstep(function(dtime)
	tick_acc = tick_acc + dtime
	if tick_acc < TICK_S then
		return
	end
	local dt = tick_acc
	tick_acc = 0
	save_acc = save_acc + dt
	local save_now = save_acc >= SAVE_S
	if save_now then
		save_acc = 0
	end
	for _, player in ipairs(core.get_connected_players()) do
		local name = name_of(player)
		local rec = S.active_rec(name)
		if tick_members(S.list(player), dt, rec and rec.uid or nil) then
			S.mark(name)
		end
		if S.hud_dirty[name] then
			S.hud_dirty[name] = nil
			UI.refresh_hud(player)
		end
		if save_now then
			S.save(player)
		end
	end
end)

core.register_on_joinplayer(function(player)
	local name = name_of(player)
	S.cache[name] = nil
	S.list(player)
	S.mark(name)
	if #S.list(player) == 0 and not S.is_dead(player) then
		core.after(1, function()
			local p = core.get_player_by_name(name)
			if p ~= nil and #S.list(p) == 0 then
				UI.show_chooser(p)
			end
		end)
	end
end)

core.register_on_leaveplayer(function(player)
	local name = name_of(player)
	S.recall(name, true)
	S.save(player)
	S.cache[name] = nil
	S.hud_dirty[name] = nil
	S.starter[name] = nil
	UI.forget(name)
end)

core.register_on_dieplayer(function(player)
	S.recall(name_of(player), true)
	S.save(player)
end)

minemon.events.register("creature_fainted", S.on_fainted)
minemon.events.register("creature_hurt", function(obj, _amount, _attacker, _info)
	local le = obj:get_luaentity()
	if le and type(le.owner) == "string" and le.owner ~= "" then
		S.mark(le.owner)
	end
end)

-- UI (HUD, formspecs, the Party Ball, chat commands) and the owned brain.
UI = dofile(MODPATH .. "/ui.lua")(S)
minemon.creatures.register_brain("owned", dofile(MODPATH .. "/brain.lua")(S))
-- The move command bar (T-29). After ui.lua: it replaces the Party Ball's on_use.
local COMMAND = dofile(MODPATH .. "/command.lua")(S)

-- Public API (PLAN.md M1 contract, plus the admin and test helpers in T-22).

function API.get(player)
	return S.list(player)
end

function API.set(player, list)
	S.set(player, list)
end

-- Changes one member, found by uid (growth, T-27): fn(m) edits it in place, then the list is written back through
-- S.set, which rebinds the active entity (its _mm is the same table). Returns true when the member was found.
function API.update_member(player, uid, fn)
	local list = S.list(player)
	local i = LOGIC.index_of(list, uid)
	if i == nil then
		return false
	end
	fn(list[i])
	S.set(player, list)
	return true
end

-- The ObjectRef of the active creature, or nil.
function API.get_active(player)
	local rec = S.active_rec(name_of(player))
	return rec and rec.obj or nil
end

function API.send_out(player, index)
	return S.send_out(player, index)
end

function API.recall(player)
	return S.recall(name_of(player), false)
end

function API.lead_index(player)
	return LOGIC.lead_index(S.list(player))
end

function API.heal_all(player)
	S.heal_all(player)
end

function API.order(player, target)
	return S.order(player, target)
end

function API.choose_starter(player, species_id)
	return S.choose_starter(player, species_id)
end

function API.open_chooser(player)
	UI.show_chooser(player)
end

-- The move command bar (T-29): draw, cycle, self_cast, order, selected (the selected slot, or nil) and queued.
API.command = COMMAND

return API
