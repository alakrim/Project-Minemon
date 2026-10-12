-- Integration test (T-17): the four Gen 2 data files load with core.parse_json.
-- Reads minemon_core/data/*.json through core.get_modpath, so it needs minemon_core
-- loaded in the assembled game. Writes PASS n or FAIL <reason> to test_result.txt
-- in the world folder, then shuts the server down.

local function write_result(line)
    core.safe_file_write(core.get_worldpath() .. "/test_result.txt", line .. "\n")
    core.request_shutdown()
end

local function fail(reason)
    write_result("FAIL " .. reason)
end

-- Reading needs io, which a normal mod does not have. core.safe_file_write works
-- untrusted, so only the read goes through the insecure environment, and only if
-- the test mod is in secure.trusted_mods. The T-14 runner must set that (not yet in this tree).
local function read_file(path)
    local lib = io or (core.request_insecure_environment and core.request_insecure_environment())
    if not lib or not lib.open then
        return nil, "io unavailable: add minemon_test_data to secure.trusted_mods"
    end
    local f, err = lib.open(path, "r")
    if not f then
        return nil, err
    end
    local text = f:read("*a")
    f:close()
    return text
end

local function load_json(dir, name)
    local text, err = read_file(dir .. name .. ".json")
    if not text then
        return nil, name .. ".json: " .. tostring(err)
    end
    local parsed = core.parse_json(text)
    if type(parsed) ~= "table" then
        return nil, name .. ".json did not parse"
    end
    return parsed
end

core.after(1, function()
    local modpath = core.get_modpath("minemon_core")
    if not modpath then
        return fail("minemon_core is not loaded")
    end
    local dir = modpath .. "/data/"

    local species, err = load_json(dir, "species")
    if not species then
        return fail(err)
    end
    local moves
    moves, err = load_json(dir, "moves")
    if not moves then
        return fail(err)
    end
    local types
    types, err = load_json(dir, "types")
    if not types then
        return fail(err)
    end
    local items
    items, err = load_json(dir, "items")
    if not items then
        return fail(err)
    end

    if #species ~= 251 then
        return fail("expected 251 species, got " .. #species)
    end
    if species[1].id ~= 1 or species[251].id ~= 251 then
        return fail("species ids are not 1..251")
    end
    if next(moves) == nil then
        return fail("moves.json is empty")
    end
    if not types.types or #types.types ~= 17 then
        return fail("types.json must list 17 types")
    end
    if not items.poke_ball then
        return fail("items.json has no poke_ball")
    end

    write_result("PASS " .. #species)
end)
