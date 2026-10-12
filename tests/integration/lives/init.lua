-- Integration check for minemon_lives. Fake players are not available headless, so the
-- per-player flow is covered by the unit tests and the in-game checklist in the T-15 report.
-- Writes PASS n or FAIL <reason> to test_result.txt in the world dir, then shuts down.
-- luacheck: read_globals core minemon

local function check_all()
	local checks = {
		function()
			assert(minemon and minemon.lives, "minemon.lives is missing")
		end,
		function()
			local L = minemon.lives
			assert(type(L.get) == "function", "minemon.lives.get is missing")
			assert(type(L.give_life) == "function", "minemon.lives.give_life is missing")
			assert(type(L.revive) == "function", "minemon.lives.revive is missing")
		end,
		function()
			assert(minemon.lives.MAX == 3, "minemon.lives.MAX must be 3")
		end,
		function()
			assert(core.registered_chatcommands["lives"], "/lives is not registered")
		end,
		function()
			assert(core.registered_chatcommands["lives_revive"], "/lives_revive is not registered")
		end,
		function()
			assert(core.registered_chatcommands["lives_give"], "/lives_give is not registered")
		end,
	}
	for i, check in ipairs(checks) do
		local ok, err = pcall(check)
		if not ok then
			return "FAIL check " .. i .. ": " .. tostring(err)
		end
	end
	return "PASS " .. #checks
end

core.after(1, function()
	local result = check_all()
	core.safe_file_write(core.get_worldpath() .. "/test_result.txt", result)
	core.request_shutdown()
end)
