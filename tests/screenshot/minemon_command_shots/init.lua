-- Screenshot scene for the move command bar (T-29): a stone platform, the player's Cyndaquil sent out 2 m in front of
-- the player with a known moveset (Ember, Absorb, Acid Armor, Tackle), Absorb selected (slot 2), and Ember on cooldown.
-- Test-only: loaded by scripts/screenshot.sh through MINEMON_SHOT_EXTRA_MODS, never shipped. Keep PLAYER_POS in sync
-- with tests/screenshot/command.json. The cooldown is set directly on the creature (a test scene, not game code), so
-- it lasts through the shot.
--
-- Timeline after the join: the starter is chosen at once (so the chooser never covers the shot); at SETUP_S the scene
-- is built. The shot helper's first shot teleports the player to PLAYER_POS at 1 s, before the setup.
--
-- luacheck: read_globals core minemon vector VoxelManip VoxelArea

local FLOOR_Y = 180 -- the stone top is at y = 180.5 (the floor the minemon_combat_fx scene uses for seed 1337)
local ABOVE = 6
local PLATFORM = { x0 = -12, x1 = 12, z0 = -12, z1 = 12 }
local PLAYER_POS = vector.new(0, FLOOR_Y + 0.5, -4.5)
local CYNDAQUIL = 155
local SETUP_S = 2
local CLEAR_R = 30 -- natural mobs within this radius of the scene are removed
local COOLDOWN_S = 600 -- the Ember cooldown outlasts the shot

local started = false

local function log(msg)
	core.log("action", "[minemon_command_shots] " .. msg)
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
	local lead = minemon.party.get(player)[1]
	if lead == nil then
		log("no party member")
		return
	end
	lead.moves = {
		{ id = "ember", pp = 25 },
		{ id = "absorb", pp = 20 },
		{ id = "acid_armor", pp = 40 },
		{ id = "tackle", pp = 35 },
	}
	local sent, why = minemon.party.send_out(player, 1)
	if not sent then
		log("send_out failed: " .. tostring(why))
		return
	end
	local obj = minemon.party.get_active(player)
	local le = obj:get_luaentity()
	le._mm_cooldown = { ember = core.get_gametime() + COOLDOWN_S }
	minemon.party.command.cycle(player) -- slot 1 to slot 2 (Absorb)
	log("scene ready: Ember on cooldown, selected " .. tostring(minemon.party.command.selected(player)))
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
