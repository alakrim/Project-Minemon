-- Named event registry. Pure: the logger is injected, so this file never touches the Luanti API.
-- M.create(logger) returns { register = fn(name, handler), fire = fn(name, ...) }.
-- fire calls every handler for the name in registration order. Each call runs under pcall, so one failing
-- handler is logged through logger(message) and does not stop the others.

local M = {}

function M.create(logger)
	local log = logger or function() end
	local handlers = {}
	local api = {}

	function api.register(name, handler)
		assert(type(name) == "string", "minemon: event name must be a string")
		assert(type(handler) == "function", "minemon: event handler must be a function")
		local list = handlers[name]
		if not list then
			list = {}
			handlers[name] = list
		end
		list[#list + 1] = handler
	end

	function api.fire(name, ...)
		local list = handlers[name]
		if not list then
			return
		end
		-- Copy first, so a handler that registers another handler does not change this round.
		local snapshot = {}
		for i, handler in ipairs(list) do
			snapshot[i] = handler
		end
		for i, handler in ipairs(snapshot) do
			local ok, err = pcall(handler, ...)
			if not ok then
				log(string.format("event '%s' handler %d failed: %s", name, i, tostring(err)))
			end
		end
	end

	return api
end

return M
