-- minemon_lives: 3 lives per player. The 4th death is permanent: ghost mode.
-- The rules are pure and live in lives_logic.lua. This file is the Luanti glue:
-- callbacks, HUD, privileges, chat commands. State is per player, in player meta.
-- luacheck: read_globals core
-- luacheck: globals minemon

local LOGIC = dofile(core.get_modpath("minemon_lives") .. "/lives_logic.lua")
local MAX = LOGIC.MAX

local KEY_STATE = "minemon:lives:state"
local KEY_PENDING = "minemon:lives:pending"
local KEY_SAVED_PRIVS = "minemon:lives:saved_privs"
local KEY_SAVED_PROPS = "minemon:lives:saved_props"

local HUD_TYPE = core.features.hud_def_type_field and "type" or "hud_elem_type"
local COLOR_LIFE = 0xFF3030
local COLOR_LAST = 0x8B0000
local COLOR_DEAD = 0x9A9A9A
local COLOR_SHADOW = 0x000000
local COLOR_BANNER = 0xFFFFFF
local COLOR_GHOST_BANNER = 0xB00000
local SOUND_LOST_LIFE = "mobs_mc_vex_death" -- VoxeLibre ghostly sound; skipped if mobs_mc is absent

local hud_ids = {} -- [player name] = {shadow = id, text = id}
local banners = {} -- [player name] = {id = id, gen = n}

local function trim(s)
	return ((s or ""):match("^%s*(.-)%s*$"))
end

local function load_state(player)
	return LOGIC.deserialize(player:get_meta():get_string(KEY_STATE), MAX)
end

local function save_state(player, state)
	player:get_meta():set_string(KEY_STATE, LOGIC.serialize(state, MAX))
end

local function lives_label(state)
	if state.dead then
		return "☠ Permadeath", COLOR_DEAD
	end
	if state.lives == 0 then
		return "♥ 0 - next death is permanent", COLOR_LAST
	end
	return "♥ " .. state.lives, COLOR_LIFE
end

local function lost_life_text(lives)
	if lives == 1 then
		return "1 life left"
	end
	return lives .. " lives left"
end

-- HUD: a red top-left text with a black copy one pixel behind it as the outline.

local function create_hud(player)
	local shadow = player:hud_add({
		[HUD_TYPE] = "text",
		position = { x = 0, y = 0 },
		offset = { x = 10, y = 10 },
		alignment = { x = 1, y = 1 },
		text = "",
		number = COLOR_SHADOW,
		size = { x = 2, y = 0 },
		style = 1,
		z_index = 100,
	})
	local text = player:hud_add({
		[HUD_TYPE] = "text",
		position = { x = 0, y = 0 },
		offset = { x = 8, y = 8 },
		alignment = { x = 1, y = 1 },
		text = "",
		number = COLOR_LIFE,
		size = { x = 2, y = 0 },
		style = 1,
		z_index = 101,
	})
	hud_ids[player:get_player_name()] = { shadow = shadow, text = text }
end

local function refresh_hud(player)
	local h = hud_ids[player:get_player_name()]
	if not h then
		return
	end
	local label, color = lives_label(load_state(player))
	player:hud_change(h.shadow, "text", label)
	player:hud_change(h.text, "text", label)
	player:hud_change(h.text, "number", color)
end

-- Centred HUD text that removes itself after `seconds`. A newer banner replaces an older one.
local function show_banner(player, text, color, seconds)
	local name = player:get_player_name()
	local gen = 1
	local prev = banners[name]
	if prev then
		player:hud_remove(prev.id)
		gen = prev.gen + 1
	end
	local id = player:hud_add({
		[HUD_TYPE] = "text",
		position = { x = 0.5, y = 0.35 },
		alignment = { x = 0, y = 0 },
		offset = { x = 0, y = 0 },
		text = text,
		number = color,
		size = { x = 4, y = 0 },
		style = 1,
		z_index = 200,
	})
	banners[name] = { id = id, gen = gen }
	core.after(seconds, function()
		local cur = banners[name]
		if not cur or cur.gen ~= gen then
			return
		end
		banners[name] = nil
		local p = core.get_player_by_name(name)
		if p then
			p:hud_remove(cur.id)
		end
	end)
end

local function play_lost_life_sound(name)
	if core.get_modpath("mobs_mc") then
		core.sound_play(SOUND_LOST_LIFE, { to_player = name, gain = 0.8 })
	end
end

-- Ghost mode: no interact, can fly and noclip, invisible, not pointable, immortal.
-- The real privileges and visibility are saved once in meta, so re-applying does not overwrite them.

local function enter_ghost(player)
	local meta = player:get_meta()
	local name = player:get_player_name()

	if meta:get_string(KEY_SAVED_PRIVS) == "" then
		meta:set_string(KEY_SAVED_PRIVS, core.write_json(core.get_player_privs(name)))
	end
	if meta:get_string(KEY_SAVED_PROPS) == "" then
		local props = player:get_properties()
		local vs = props.visual_size or {}
		meta:set_string(KEY_SAVED_PROPS, core.write_json({
			visual_size = { x = vs.x or 1, y = vs.y or 1, z = vs.z or 1 },
			pointable = props.pointable ~= false,
			nametag = props.nametag or name,
		}))
	end

	local privs = {}
	for priv, granted in pairs(core.get_player_privs(name)) do
		privs[priv] = granted
	end
	privs.interact = nil
	privs.fly = true
	privs.noclip = true
	core.set_player_privs(name, privs)

	player:set_properties({ visual_size = { x = 0, y = 0, z = 0 }, pointable = false, nametag = "" })

	local groups = player:get_armor_groups()
	groups.immortal = 1
	player:set_armor_groups(groups)
end

-- Undoes ghost mode. Does nothing for a player who was never in ghost mode.

local function leave_ghost(player)
	local meta = player:get_meta()
	local name = player:get_player_name()

	local saved_privs = core.parse_json(meta:get_string(KEY_SAVED_PRIVS))
	if type(saved_privs) == "table" then
		core.set_player_privs(name, saved_privs)
	end
	meta:set_string(KEY_SAVED_PRIVS, "")

	local saved_props = core.parse_json(meta:get_string(KEY_SAVED_PROPS))
	if type(saved_props) == "table" then
		local vs = saved_props.visual_size or {}
		player:set_properties({
			visual_size = { x = vs.x or 1, y = vs.y or 1, z = vs.z or 1 },
			pointable = saved_props.pointable ~= false,
			nametag = saved_props.nametag or name,
		})
	end
	meta:set_string(KEY_SAVED_PROPS, "")

	local groups = player:get_armor_groups()
	if groups.immortal ~= nil then
		groups.immortal = nil
		player:set_armor_groups(groups)
	end
end

-- Full reset: lives back to MAX, ghost mode undone, HUD updated.
local function revive_player(player)
	local state = LOGIC.revive(load_state(player), MAX)
	save_state(player, state)
	player:get_meta():set_string(KEY_PENDING, "")
	leave_ghost(player)
	refresh_hud(player)
	return state
end

local function give_life_player(player)
	local state = LOGIC.give_life(load_state(player), MAX)
	save_state(player, state)
	refresh_hud(player)
	return state
end

core.register_on_joinplayer(function(player)
	local name = player:get_player_name()
	local meta = player:get_meta()
	local raw = meta:get_string(KEY_STATE)
	local first_join = raw == ""

	local state = LOGIC.deserialize(raw, MAX)
	save_state(player, state)
	meta:set_string(KEY_PENDING, "")

	create_hud(player)
	if state.dead then
		enter_ghost(player)
	end
	refresh_hud(player)

	if first_join then
		core.chat_send_player(name, "You have 3 lives. On your 4th death, your journey ends forever.")
	end
end)

core.register_on_leaveplayer(function(player)
	local name = player:get_player_name()
	hud_ids[name] = nil
	banners[name] = nil
end)

-- The death itself only records the outcome. The messages and ghost mode wait for the respawn.
core.register_on_dieplayer(function(player)
	local state = load_state(player)
	if state.dead then
		return -- already in ghost mode: nothing changes
	end
	local new_state, event = LOGIC.on_death(state, MAX)
	save_state(player, new_state)
	player:get_meta():set_string(KEY_PENDING, event)
	refresh_hud(player)
end)

core.register_on_respawnplayer(function(player)
	local name = player:get_player_name()
	local meta = player:get_meta()
	local event = meta:get_string(KEY_PENDING)
	meta:set_string(KEY_PENDING, "")

	local state = load_state(player)
	if state.dead then
		enter_ghost(player)
	end
	refresh_hud(player)

	if event == "lost_life" then
		show_banner(player, lost_life_text(state.lives), COLOR_BANNER, 4)
		play_lost_life_sound(name)
	elseif event == "last_life" then
		show_banner(player, "LAST LIFE", COLOR_LAST, 5)
	elseif event == "permadeath" then
		show_banner(player, "YOUR JOURNEY ENDS", COLOR_GHOST_BANNER, 6)
		core.chat_send_all(name .. " has fallen forever.")
	end
end)

core.register_chatcommand("lives", {
	description = "Show your remaining lives",
	func = function(name)
		local player = core.get_player_by_name(name)
		if not player then
			return false, "You are not online."
		end
		local state = load_state(player)
		if state.dead then
			return true, "Permadeath"
		end
		return true, string.format("Lives: %d/%d", state.lives, MAX)
	end,
})

core.register_chatcommand("lives_revive", {
	params = "<name>",
	description = "Revive a player: restore lives, privileges and visibility",
	privs = { server = true },
	func = function(_, param)
		local target_name = trim(param)
		if target_name == "" then
			return false, "Usage: /lives_revive <name>"
		end
		local target = core.get_player_by_name(target_name)
		if not target then
			return false, "Player " .. target_name .. " is not online."
		end
		local state = revive_player(target)
		core.chat_send_player(target_name, "An admin has restored your lives.")
		return true, string.format("Revived %s: Lives: %d/%d", target_name, state.lives, MAX)
	end,
})

core.register_chatcommand("lives_give", {
	params = "<name>",
	description = "Give a player one extra life (capped at the maximum)",
	privs = { server = true },
	func = function(_, param)
		local target_name = trim(param)
		if target_name == "" then
			return false, "Usage: /lives_give <name>"
		end
		local target = core.get_player_by_name(target_name)
		if not target then
			return false, "Player " .. target_name .. " is not online."
		end
		if load_state(target).dead then
			return false, target_name .. " is in permadeath. Use /lives_revive first."
		end
		local state = give_life_player(target)
		core.chat_send_player(target_name, string.format("You were given a life. Lives: %d/%d", state.lives, MAX))
		return true, string.format("Gave a life to %s: Lives: %d/%d", target_name, state.lives, MAX)
	end,
})

-- The shared table is created by minemon_core; this mod adds its own sub-table to it.
minemon.lives = {
	MAX = MAX,
	get = load_state,
	give_life = give_life_player,
	revive = revive_player,
}
