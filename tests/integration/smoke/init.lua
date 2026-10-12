-- Headless smoke test for the assembled Minemon game (docs/CONVENTIONS.md, tests/integration).
-- Runs its checks after core.after(1, ...), writes <world>/test_result.txt ("PASS n" or
-- "FAIL <reason>") and calls core.request_shutdown().

local MAX_SECONDS = 60
local RADIUS = 16

local start_us = core.get_us_time()
local passes = 0
local failures = {}
local done = false

local function check(name, ok, detail)
	if ok then
		passes = passes + 1
	else
		table.insert(failures, name .. (detail and (" (" .. detail .. ")") or ""))
	end
end

local function finish()
	if done then
		return
	end
	done = true
	local elapsed = (core.get_us_time() - start_us) / 1e6
	check("e: run under " .. MAX_SECONDS .. " s", elapsed < MAX_SECONDS, string.format("took %.2f s", elapsed))
	local body
	if #failures == 0 then
		body = string.format("PASS %d\n", passes)
	else
		body = "FAIL " .. table.concat(failures, "; ") .. "\n"
	end
	local path = core.get_worldpath() .. "/test_result.txt"
	if not core.safe_file_write(path, body) then
		core.log("error", "[minemon_test_smoke] could not write " .. path)
	end
	core.log("action", "[minemon_test_smoke] " .. body:gsub("\n", ""))
	core.request_shutdown()
end

local function fatal(msg)
	table.insert(failures, "error: " .. tostring(msg))
	finish()
end

local function count_solid()
	local n = 0
	for x = -RADIUS, RADIUS do
		for y = -RADIUS, RADIUS do
			for z = -RADIUS, RADIUS do
				local node = core.get_node_or_nil({ x = x, y = y, z = z })
				if node and node.name ~= "air" and node.name ~= "ignore" then
					n = n + 1
				end
			end
		end
	end
	return n
end

local function check_api()
	check("a: minemon and minemon.version exist",
		type(minemon) == "table" and type(minemon.version) == "string")

	check("b: VoxeLibre loaded (mcl_core modpath and mcl_core:stone registered)",
		core.get_modpath("mcl_core") ~= nil and core.registered_nodes["mcl_core:stone"] ~= nil)

	local mobs = rawget(_G, "mcl_mobs")
	check("c: mcl_mobs exposes register_mob",
		type(mobs) == "table" and type(mobs.register_mob) == "function")
end

local function check_spawn_area()
	local pos1 = { x = -RADIUS, y = -RADIUS, z = -RADIUS }
	local pos2 = { x = RADIUS, y = RADIUS, z = RADIUS }
	local emerge_errors = 0
	core.emerge_area(pos1, pos2, function(_, action, calls_remaining)
		if action == core.EMERGE_ERRORED or action == core.EMERGE_CANCELLED then
			emerge_errors = emerge_errors + 1
		end
		if calls_remaining > 0 then
			return
		end
		local ok, err = pcall(function()
			local solid = count_solid()
			check("d: at least one non-air node in -16..16 after emerge", solid > 0,
				"non-air nodes: " .. solid .. ", emerge errors: " .. emerge_errors)
			finish()
		end)
		if not ok then
			fatal(err)
		end
	end)
end

core.after(1, function()
	local ok, err = pcall(function()
		check_api()
		check_spawn_area()
	end)
	if not ok then
		fatal(err)
	end
end)
