-- Screenshot scene for minemon_capture (T-26): a stone platform, a wild Rattata 6 m in front of the player and
-- exhausted (0 HP, sitting), and five Poké Balls in the wielded slot. Shot 1 (keep_hud) shows the catch odds HUD.
-- Shot 2 (keep_hud) is taken during the shake sequence: the capture starts CAPTURE_AT_S after the join, which falls
-- between the end of shot 1 and the marker of shot 2 (tests/screenshot/capture.json has the wait times). Test-only:
-- loaded by scripts/screenshot.sh through MINEMON_SHOT_EXTRA_MODS, never shipped. Keep PLAYER_POS in sync with
-- tests/screenshot/capture.json.
--
-- The starter is chosen at join, so the party chooser (which opens 1 s after a join with an empty party) never covers
-- the shots. The party is not used further: the caught Rattata joins it.
--
-- luacheck: read_globals core minemon vector VoxelManip VoxelArea ItemStack

local FLOOR_Y = 180 -- the stone top is at y = 180.5, as in minemon_party_shots
local ABOVE = 6
local PLATFORM = { x0 = -12, x1 = 12, z0 = -12, z1 = 12 }
local PLAYER_POS = vector.new(0, FLOOR_Y + 0.5, -4.5)
local RATTATA_POS = vector.new(0, FLOOR_Y + 1, 1.5) -- 6 m in front of the player
local CYNDAQUIL = 155
local RATTATA = 19
local SETUP_S = 0.5
local CAPTURE_AT_S = 7.2
local CLEAR_R = 30

local started = false

local function log(msg)
	core.log("action", "[minemon_capture_shots] " .. msg)
end

local function build_platform()
	-- VoxelManip loads (or generates) the blocks first, so the nodes stick; plain core.set_node on unloaded blocks
	-- does not, and the player falls through (as seen in the first run).
	local vm = VoxelManip()
	local emin, emax = vm:read_from_map(vector.new(PLATFORM.x0, FLOOR_Y, PLATFORM.z0),
		vector.new(PLATFORM.x1, FLOOR_Y + ABOVE, PLATFORM.z1))
	local area = VoxelArea:new({ MinEdge = emin, MaxEdge = emax })
	local data = vm:get_data()
	local c_air = core.get_content_id("air")
	local c_stone = core.get_content_id("mcl_core:stone")
	for z = PLATFORM.z0, PLATFORM.z1 do
		for x = PLATFORM.x0, PLATFORM.x1 do
			for y = FLOOR_Y, FLOOR_Y + ABOVE do
				data[area:index(x, y, z)] = (y == FLOOR_Y) and c_stone or c_air
			end
		end
	end
	vm:set_data(data)
	vm:write_to_map(true)
end

local function clear_mobs(centre)
	for _, obj in ipairs(core.get_objects_inside_radius(centre, CLEAR_R)) do
		local le = (not obj:is_player()) and obj:get_luaentity() or nil
		if le and le.is_mob then
			obj:remove()
		end
	end
end

local rattata = nil

local function setup(player)
	build_platform()
	clear_mobs(PLAYER_POS)
	player:set_pos(PLAYER_POS)
	player:set_wielded_item(ItemStack("minemon:poke_ball 5"))

	rattata = minemon.creatures.spawn(RATTATA_POS, RATTATA, 5, nil)
	if not rattata then
		log("spawn failed for the Rattata")
		return
	end
	local le = rattata:get_luaentity()
	le.walk_velocity = 0
	le.run_velocity = 0
	rattata:set_yaw(math.pi) -- faces the player (-z)
	minemon.creatures.damage(rattata, 9999, nil, nil) -- exhausted: sits, does not flee
	log("scene ready: exhausted Rattata 6 m away, 5 Poké Balls wielded")
end

core.register_on_joinplayer(function(player)
	if started then
		return
	end
	started = true
	local ok, res = minemon.party.choose_starter(player, CYNDAQUIL)
	log("starter: " .. tostring(ok) .. " " .. tostring(res and res.species_id or res))
	core.after(SETUP_S, function()
		setup(player)
	end)
	core.after(CAPTURE_AT_S, function()
		if rattata and rattata:is_valid() then
			local started_ok, why = minemon.capture.start(player, rattata, "poke_ball")
			log("capture started: " .. tostring(started_ok) .. " " .. tostring(why))
		end
	end)
end)
