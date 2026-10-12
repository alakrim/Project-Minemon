-- minemon_core: the global `minemon` table and the Gen 2 rules (data, formulas, rng, instance, events).
-- The pure modules (data, formulas, rng, instance, events) do not touch the Luanti API, so busted can test
-- them. This file is the glue: it reads and parses data/*.json, and it gives the logger to the event registry.
-- luacheck: globals minemon

minemon = rawget(_G, "minemon") or {}
minemon.version = "0.1.0"

local MODPATH = core.get_modpath("minemon_core")

local function load_module(name)
	return dofile(MODPATH .. "/" .. name .. ".lua")
end

-- io.open in read mode works for untrusted mods, because the sandbox allows reads from mod directories.
local function read_json(name)
	local path = MODPATH .. "/data/" .. name .. ".json"
	local f, err = io.open(path, "rb")
	if not f then
		error("minemon_core: cannot open " .. path .. ": " .. tostring(err))
	end
	local text = f:read("*a")
	f:close()
	local parsed, parse_err = core.parse_json(text, nil, true)
	if parsed == nil then
		error("minemon_core: cannot parse data/" .. name .. ".json: " .. tostring(parse_err))
	end
	return parsed
end

minemon.data = load_module("data").new({
	species = read_json("species"),
	moves = read_json("moves"),
	types = read_json("types"),
	items = read_json("items"),
})
minemon.rng = load_module("rng")
minemon.formulas = load_module("formulas")
minemon.instance = load_module("instance").create(minemon.formulas, minemon.data)
minemon.events = load_module("events").create(function(message)
	core.log("error", "[minemon_core] " .. message)
end)
