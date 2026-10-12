-- Headless screenshot helper (T-19). Loaded only in the throwaway screenshot world by scripts/screenshot.sh.
-- It is trusted (secure.trusted_mods) so it can use io, which the shell script needs for its marker files.
--
-- Protocol with scripts/screenshot.sh (<world>/minemon_shots.json holds the shot list):
--   1. The player joins; for each shot the mod teleports the player, sets yaw and pitch and the time of day,
--      grants fly and noclip, hides the HUD (unless the shot sets keep_hud: true), waits wait_s, then writes
--      <world>/shot_<name>.ready.
--   2. The shell script captures the X display and deletes that marker.
--   3. The mod sees the marker is gone and starts the next shot. After the last shot it does nothing,
--      and the shell script stops the client.

local worldpath = core.get_worldpath()
local SHOTS_FILE = worldpath .. "/minemon_shots.json"
local POLL_S = 0.25
local MAX_WAIT_POLLS = 2400 -- 600 s; the shell script times out first in practice.
local started = false

local HUD_OFF = {
	hotbar = false,
	healthbar = false,
	crosshair = false,
	wielditem = false,
	breathbar = false,
	minimap = false,
	minimap_radar = false,
	basic_debug = false,
	chat = false,
}

local function log(msg)
	core.log("action", "[minemon_shots] " .. msg)
end

-- The flags hide Luanti's own HUD. VoxeLibre draws its health, hunger, hotbar and crosshair as HUD elements,
-- which the flags do not reach, so every element id is removed too. Removing an id that does not exist is a no-op.
local HUD_ID_MAX = 255

local function clear_hud(player)
	player:hud_set_flags(HUD_OFF)
	for id = 0, HUD_ID_MAX do
		player:hud_remove(id)
	end
end

local function file_exists(path)
	local f = io.open(path, "rb")
	if f then
		f:close()
		return true
	end
	return false
end

local function write_marker(path, name)
	local f = io.open(path, "wb")
	if not f then
		log("cannot write marker " .. path)
		return false
	end
	f:write(name .. "\n")
	f:close()
	return true
end

local function load_shots()
	local f = io.open(SHOTS_FILE, "rb")
	if not f then
		log("missing " .. SHOTS_FILE)
		return nil
	end
	local data = f:read("*a")
	f:close()
	local shots = core.parse_json(data)
	if type(shots) ~= "table" then
		log("cannot parse " .. SHOTS_FILE)
		return nil
	end
	return shots
end

-- Waits until the shell script deletes the marker, then calls done().
local function wait_for_capture(marker, polls, done)
	if not file_exists(marker) then
		done()
		return
	end
	if polls >= MAX_WAIT_POLLS then
		log("gave up waiting for capture of " .. marker)
		done()
		return
	end
	core.after(POLL_S, function()
		wait_for_capture(marker, polls + 1, done)
	end)
end

local function run_shot(player, shots, index)
	local shot = shots[index]
	if not shot then
		log("all " .. #shots .. " shots done")
		return
	end
	local name = shot.name
	local pos = shot.pos
	local target = { x = pos[1], y = pos[2], z = pos[3] }

	-- Positions need their blocks loaded; asking for them now speeds up the wait.
	core.emerge_area(vector.subtract(target, 48), vector.add(target, 48))
	player:set_pos(target)
	-- yaw_deg: 0 along +Z (Luanti convention). pitch_deg: positive looks UP. Luanti's look_vertical is
	-- positive DOWN, hence the minus sign.
	player:set_look_horizontal(math.rad(shot.yaw_deg or 0))
	player:set_look_vertical(-math.rad(shot.pitch_deg or 0))
	core.set_timeofday(shot.time_of_day or 0.5)
	if not shot.keep_hud then
		clear_hud(player)
	end
	core.set_player_privs(player:get_player_name(), { fly = true, noclip = true, fast = true, interact = true })

	local marker = worldpath .. "/shot_" .. name .. ".ready"
	core.after(shot.wait_s or 10, function()
		-- HUD again just before the marker: VoxeLibre may have re-added elements during the wait.
		if not shot.keep_hud then
			clear_hud(player)
		end
		core.after(1, function()
			log("ready " .. name)
			write_marker(marker, name)
			wait_for_capture(marker, 0, function()
				run_shot(player, shots, index + 1)
			end)
		end)
	end)
end

core.register_on_joinplayer(function(player)
	if started then
		return
	end
	started = true
	-- Let the first server steps and the world load settle before the first shot.
	core.after(1, function()
		local shots = load_shots()
		if not shots or #shots == 0 then
			log("no shots to take")
			return
		end
		log("starting " .. #shots .. " shots")
		run_shot(player, shots, 1)
	end)
end)
