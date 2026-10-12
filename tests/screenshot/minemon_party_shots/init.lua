-- Screenshot scene for minemon_party (T-22): a stone platform, the player's Cyndaquil sent out 2 m in front of the
-- player, and a wild Rattata 6 m away that the Cyndaquil is ordered to attack. Test-only: loaded by
-- scripts/screenshot.sh through MINEMON_SHOT_EXTRA_MODS, never shipped. Keep PLAYER_POS in sync with
-- tests/screenshot/party.json.
--
-- Timeline after the join: the starter is chosen at once (so the chooser, which opens 1 s after a join with an empty
-- party, never covers the shots); at SETUP_S the scene is built and the Cyndaquil is sent out. The shot helper's
-- first shot teleports the player to PLAYER_POS at 1 s, before the setup.
--
-- luacheck: read_globals core minemon vector VoxelManip VoxelArea

local FLOOR_Y = 180 -- the stone top is at y = 180.5 (the floor the minemon_combat_fx scene uses for seed 1337)
local ABOVE = 6
local PLATFORM = { x0 = -12, x1 = 12, z0 = -12, z1 = 12 }
local PLAYER_POS = vector.new(0, FLOOR_Y + 0.5, -4.5)
local RATTATA_POS = vector.new(0, FLOOR_Y + 1, 1.5) -- 6 m in front of the player
local CYNDAQUIL = 155
local RATTATA = 19
local SETUP_S = 2
local CLEAR_R = 30 -- natural mobs within this radius of the scene are removed

local started = false

local function log(msg)
	core.log("action", "[minemon_party_shots] " .. msg)
end

local function build_platform()
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

local function setup(player)
	build_platform()
	clear_mobs(PLAYER_POS)
	player:set_pos(PLAYER_POS)
	local sent, why = minemon.party.send_out(player, 1)
	if not sent then
		log("send_out failed: " .. tostring(why))
		return
	end
	local rat = minemon.creatures.spawn(RATTATA_POS, RATTATA, 5, nil)
	if not rat then
		log("spawn failed for the Rattata")
		return
	end
	local le = rat:get_luaentity()
	le.walk_velocity = 0
	le.run_velocity = 0
	rat:set_yaw(math.pi) -- faces the player (-z)
	local ordered = minemon.party.order(player, rat)
	log("scene ready: Cyndaquil out, Rattata ordered attack = " .. tostring(ordered))
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
end)
