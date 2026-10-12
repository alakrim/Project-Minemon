-- Combat callbacks run under pcall (T-23b): an error is logged and never reaches the server. The same message is
-- logged at most once every LOG_EVERY_S seconds, so a callback that fails every 0.5 s cannot flood the log.
-- luacheck: read_globals core

local M = {}

M.LOG_EVERY_S = 10
local last_logged = {}

-- Calls fn(...) under pcall. Returns true when fn ran without error.
function M.call(label, fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then
		local now = core.get_us_time() / 1e6
		if last_logged[label] == nil or now - last_logged[label] >= M.LOG_EVERY_S then
			last_logged[label] = now
			core.log("error", "[minemon_combat] " .. label .. " failed: " .. tostring(err))
		end
	end
	return ok
end

return M
