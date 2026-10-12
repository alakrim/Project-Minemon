-- Integration test (T-29): the move command bar of minemon_party in the assembled game, with a fake player (no real
-- players). A stone platform at the origin is forceloaded. The starter Cyndaquil gets a known moveset (Ember, Tackle
-- at 0 PP, Absorb, Acid Armor). Checks: send out resets the selection to slot 1 and draws the bar (4 names, PP text);
-- Z-style cycling (the cycle function) skips 0-PP moves, wraps, and returns false when no move has PP; the Party
-- Ball's on_use (the wrapper in command.lua) orders a wild target and queues the selected move, and the owned brain
-- casts it (Ember PP 25 -> 24, cooldown set, queue cleared); an expired queue is cleared without a cast; a self-target
-- move is cast on air click (sneak cycles, a click on air with an attack move does not cast); recall removes the bar.
-- Writes PASS n or FAIL <reason> to test_result.txt, then shuts down.
-- Not covered here (no real player): the rendering of the bar (screenshot tests/screenshot/command.json), the Z key
-- edge (command_logic_spec covers the cycle rules), and the 0.25 s redraw cadence.
-- luacheck: read_globals core minemon vector

local PLATFORM_Y = 5 -- stone top at y = 5.5; the fake player stands there
local HALF = 6
local TOP_Y = 9
local STONE = "mcl_core:stone"
local NAME = "command_test_player"
local RATTATA = 19
local CYNDAQUIL = 155
local EMBER = "ember"
local TACKLE = "tackle"
local ABSORB = "absorb"
local ACID_ARMOR = "acid_armor"
local BALL = "minemon_party:party_ball"
local TICK_S = 0.25
local WAIT_MAX_S = 10

local finished = false
local checks = 0

local function finish(line)
	if finished then
		return
	end
	finished = true
	core.safe_file_write(core.get_worldpath() .. "/test_result.txt", line .. "\n")
	core.request_shutdown()
end

local function check(cond, msg)
	checks = checks + 1
	if not cond then
		error(msg, 0)
	end
end

-- The fake player: the methods the party and the command bar use, plus the HUD calls. hud_change and hud_remove fail
-- on an unknown id, as the engine does, so a stale id shows up here.
local function make_fake()
	local store = {}
	local meta = {
		get_string = function(_, key)
			return store[key] or ""
		end,
		set_string = function(_, key, value)
			store[key] = value
		end,
	}
	local fake = { ctrl = { sneak = false, zoom = false }, hud = {}, hud_added = 0, hud_removed = 0 }
	local next_id = 0
	fake.get_meta = function()
		return meta
	end
	fake.get_player_name = function()
		return NAME
	end
	fake.get_pos = function()
		return vector.new(0, PLATFORM_Y + 0.5, 0)
	end
	fake.get_look_dir = function()
		return vector.new(0, 0, 1)
	end
	fake.is_valid = function()
		return true
	end
	fake.is_player = function()
		return true
	end
	fake.get_guid = function()
		return "command-test-fake-player"
	end
	fake.get_player_control = function()
		return fake.ctrl
	end
	fake.hud_add = function(_, def)
		next_id = next_id + 1
		fake.hud[next_id] = def
		fake.hud_added = fake.hud_added + 1
		return next_id
	end
	fake.hud_change = function(_, id, key, value)
		if fake.hud[id] == nil then
			error("hud_change on unknown id " .. tostring(id), 0)
		end
		fake.hud[id][key] = value
	end
	fake.hud_remove = function(_, id)
		if fake.hud[id] == nil then
			error("hud_remove on unknown id " .. tostring(id), 0)
		end
		fake.hud[id] = nil
		fake.hud_removed = fake.hud_removed + 1
	end
	return fake
end

local function build_platform()
	for x = -HALF, HALF do
		for z = -HALF, HALF do
			core.set_node(vector.new(x, PLATFORM_Y, z), { name = STONE })
			for y = PLATFORM_Y + 1, TOP_Y do
				core.set_node(vector.new(x, y, z), { name = "air" })
			end
		end
	end
	for _, p in ipairs({ { -HALF, -HALF }, { HALF, -HALF }, { -HALF, HALF }, { HALF, HALF } }) do
		check(core.forceload_block(vector.new(p[1], PLATFORM_Y, p[2]), true, 256), "forceload failed")
	end
end

-- The HUD text of the element that shows text in a bar (name or PP line), or nil.
local function hud_has_text(fake, text)
	for _, def in pairs(fake.hud) do
		if def.text == text then
			return true
		end
	end
	return false
end

-- The Party Ball's on_use, as the game calls it (the item stack is not used).
local function ball_use(fake, pointed)
	local def = core.registered_items[BALL]
	check(def ~= nil and type(def.on_use) == "function", "the Party Ball has no on_use")
	def.on_use(nil, fake, pointed)
end

-- Runs the steps as a coroutine, so the checks can wait for the owned brain (which runs in the game's steps).
local function steps(fake)
	local cmd = minemon.party.command
	check(cmd ~= nil and cmd.cycle ~= nil and cmd.queued ~= nil, "the command table is not exported")

	local function wait_s(seconds)
		local n = math.max(1, math.floor(seconds / TICK_S + 0.5))
		for _ = 1, n do
			coroutine.yield()
		end
	end

	local function wait_until(cond, what)
		local waited = 0
		while not cond() do
			check(waited < WAIT_MAX_S, "timed out waiting for " .. what)
			coroutine.yield()
			waited = waited + TICK_S
		end
	end

	-- (1) the starter, a known moveset, send out: the selection is slot 1 and the bar shows the moves
	local ok, first = minemon.party.choose_starter(fake, CYNDAQUIL)
	check(ok, "choose_starter failed: " .. tostring(first))
	first.moves = {
		{ id = EMBER, pp = 25 },
		{ id = TACKLE, pp = 0 },
		{ id = ABSORB, pp = 20 },
		{ id = ACID_ARMOR, pp = 40 },
	}
	local sent, why2 = minemon.party.send_out(fake, 1)
	check(sent, "send_out failed: " .. tostring(why2))
	local obj = minemon.party.get_active(fake)
	check(obj ~= nil, "no active creature after send_out")
	check(cmd.selected(fake) == 1, "the selection is not slot 1 after send_out: " .. tostring(cmd.selected(fake)))
	cmd.draw(fake)
	check(fake.hud_added >= 24, "the bar did not draw its elements: " .. fake.hud_added)
	check(hud_has_text(fake, "Ember"), "the bar does not show Ember")
	check(hud_has_text(fake, "Acid Armor"), "the bar does not show Acid Armor")
	check(hud_has_text(fake, "PP 0/35"), "the bar does not show the PP of Tackle")
	check(hud_has_text(fake, "PP 25/25"), "the bar does not show the PP of Ember")

	-- (2) cycling skips the 0-PP Tackle and wraps round
	check(cmd.cycle(fake) == true, "cycle from 1 failed")
	check(cmd.selected(fake) == 3, "cycle did not skip Tackle: " .. tostring(cmd.selected(fake)))
	check(cmd.cycle(fake) == true and cmd.selected(fake) == 4, "cycle from 3 did not reach Acid Armor")
	check(cmd.cycle(fake) == true and cmd.selected(fake) == 1, "cycle did not wrap to Ember")

	-- (3) no move with PP: cycling fails and the selection stays
	first.moves[1].pp = 0
	first.moves[3].pp = 0
	first.moves[4].pp = 0
	check(cmd.cycle(fake) == false, "cycle with no PP left should fail")
	check(cmd.selected(fake) == 1, "the selection moved when no move had PP")
	first.moves[1].pp = 25
	first.moves[3].pp = 20
	first.moves[4].pp = 40

	-- (4) the Party Ball orders a wild Rattata and queues Ember; the owned brain casts it
	local wild = minemon.creatures.spawn(vector.new(0.5, PLATFORM_Y + 1, -4), RATTATA, 5, nil)
	check(wild ~= nil, "wild spawn failed")
	ball_use(fake, { type = "object", ref = wild })
	local q = cmd.queued(fake)
	check(q ~= nil and q.move == EMBER, "the order did not queue Ember")
	check(q.expires > core.get_gametime(), "the queue has no future expiry")
	wait_until(function()
		return cmd.queued(fake) == nil
	end, "the queued Ember to be cast")
	check(first.moves[1].pp == 24, "Ember PP is " .. first.moves[1].pp .. ", the queued cast did not happen")
	check(minemon.combat.on_cooldown(obj, EMBER), "Ember is not on cooldown after the queued cast")
	wild:remove()

	-- (5) an expired queue is cleared and does not cast: the creature and a wild target are 17 m apart, out of reach
	-- of every move (the longest is 12 m), so the AI cannot cast either
	obj:set_pos(vector.new(-6, PLATFORM_Y + 1, -6))
	local far = minemon.creatures.spawn(vector.new(6, PLATFORM_Y + 1, 6), RATTATA, 5, nil)
	check(far ~= nil, "far wild spawn failed")
	ball_use(fake, { type = "object", ref = far })
	local live = cmd.queued(fake)
	check(live ~= nil and live.move == EMBER, "the far order did not queue Ember")
	live.expires = core.get_gametime() - 1
	wait_s(0.75)
	check(cmd.queued(fake) == nil, "the expired queue was not cleared")
	check(first.moves[1].pp == 24, "an expired queue cast Ember")
	far:remove()

	-- (6) self-target: sneak + air click cycles to Acid Armor (aura), an air click casts it
	fake.ctrl.sneak = true
	ball_use(fake, { type = "nothing" })
	check(cmd.selected(fake) == 3, "sneak click did not cycle to Absorb: " .. tostring(cmd.selected(fake)))
	ball_use(fake, { type = "nothing" })
	check(cmd.selected(fake) == 4, "sneak click did not cycle to Acid Armor: " .. tostring(cmd.selected(fake)))
	fake.ctrl.sneak = false
	wait_until(function()
		return not minemon.combat.on_cooldown(obj, EMBER)
	end, "Ember's cooldown to end")
	ball_use(fake, { type = "nothing" })
	check(first.moves[4].pp == 39, "air click did not cast Acid Armor: PP " .. first.moves[4].pp)
	check(minemon.combat.on_cooldown(obj, ACID_ARMOR), "Acid Armor is not on cooldown after the air click")

	-- (7) an attack move on air does not cast: sneak click back to Ember, air click
	fake.ctrl.sneak = true
	ball_use(fake, { type = "nothing" })
	fake.ctrl.sneak = false
	check(cmd.selected(fake) == 1, "sneak click did not cycle back to Ember: " .. tostring(cmd.selected(fake)))
	ball_use(fake, { type = "nothing" })
	check(first.moves[1].pp == 24, "an air click cast Ember without a target")
	check(cmd.queued(fake) == nil, "an air click queued a move")

	-- (8) no PP: an order still targets, but nothing is queued
	local wild2 = minemon.creatures.spawn(vector.new(0.5, PLATFORM_Y + 1, -4), RATTATA, 5, nil)
	check(wild2 ~= nil, "second wild spawn failed")
	first.moves[1].pp = 0
	first.moves[3].pp = 0
	first.moves[4].pp = 0
	ball_use(fake, { type = "object", ref = wild2 })
	check(cmd.queued(fake) == nil, "an order with no PP queued a move")
	wild2:remove()
	first.moves[1].pp = 24
	first.moves[3].pp = 20
	first.moves[4].pp = 39

	-- (9) recall removes the bar; the next send out selects slot 1 again
	cmd.cycle(fake)
	check(cmd.selected(fake) ~= 1, "the selection did not move off Ember before the recall")
	local removed_before = fake.hud_removed
	check(minemon.party.recall(fake) == true, "recall returned false")
	check(fake.hud_removed > removed_before, "the bar was not removed on recall")
	check(cmd.selected(fake) == nil, "a selection is reported after recall")
	check(cmd.queued(fake) == nil, "a queue is reported after recall")
	local again, why3 = minemon.party.send_out(fake, 1)
	check(again, "second send_out failed: " .. tostring(why3))
	check(cmd.selected(fake) == 1, "send out did not reset the selection to slot 1")
	minemon.party.recall(fake)
end

local co = nil

local function pump()
	local ok, err = coroutine.resume(co)
	if not ok then
		finish("FAIL " .. tostring(err))
		return
	end
	if coroutine.status(co) == "dead" then
		finish(string.format("PASS %d checks", checks))
		return
	end
	core.after(TICK_S, pump)
end

core.after(1, function()
	local ok, err = pcall(function()
		build_platform()
		local fake = make_fake()
		co = coroutine.create(function()
			steps(fake)
		end)
	end)
	if not ok then
		finish("FAIL " .. tostring(err))
		return
	end
	pump()
end)
