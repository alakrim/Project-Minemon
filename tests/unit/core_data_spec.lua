-- Unit tests for minemon_core data.lua and instance.lua, run against the real data/*.json files.
-- busted has no core.parse_json, so this file carries a small JSON decoder (plain data, no escapes beyond
-- the standard set). Pure logic only, no Luanti.
-- luacheck: globals describe it assert

local here = debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$") or "."
local CORE = here .. "/../../mods/minemon/minemon_core/"
local DATA_DIR = CORE .. "data/"
local D = dofile(CORE .. "data.lua")
local F = dofile(CORE .. "formulas.lua")
local I = dofile(CORE .. "instance.lua")
local R = dofile(CORE .. "rng.lua")

local function decode_json(text)
	local pos = 1
	local parse_value

	local function skip_ws()
		pos = text:find("[^ \t\r\n]", pos) or (#text + 1)
	end

	local function utf8_char(code)
		if code < 0x80 then
			return string.char(code)
		end
		if code < 0x800 then
			return string.char(0xC0 + math.floor(code / 64), 0x80 + code % 64)
		end
		return string.char(0xE0 + math.floor(code / 4096), 0x80 + math.floor(code / 64) % 64, 0x80 + code % 64)
	end

	local escapes = { ['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" }

	local function parse_string()
		pos = pos + 1
		local parts = {}
		while true do
			local s = text:find('["\\]', pos)
			assert(s, "unterminated string")
			parts[#parts + 1] = text:sub(pos, s - 1)
			if text:sub(s, s) == '"' then
				pos = s + 1
				break
			end
			local esc = text:sub(s + 1, s + 1)
			if esc == "u" then
				parts[#parts + 1] = utf8_char(tonumber(text:sub(s + 2, s + 5), 16))
				pos = s + 6
			else
				parts[#parts + 1] = assert(escapes[esc], "bad escape")
				pos = s + 2
			end
		end
		return table.concat(parts)
	end

	local function parse_number()
		local num = text:match("^-?%d+%.?%d*[eE][-+]?%d+", pos) or text:match("^-?%d+%.?%d*", pos)
		assert(num, "bad number at " .. pos)
		pos = pos + #num
		return tonumber(num)
	end

	local function parse_array()
		pos = pos + 1
		local arr = {}
		skip_ws()
		if text:sub(pos, pos) == "]" then
			pos = pos + 1
			return arr
		end
		while true do
			arr[#arr + 1] = parse_value()
			skip_ws()
			local c = text:sub(pos, pos)
			pos = pos + 1
			if c == "]" then
				return arr
			end
			assert(c == ",", "expected , in array")
			skip_ws()
		end
	end

	local function parse_object()
		pos = pos + 1
		local obj = {}
		skip_ws()
		if text:sub(pos, pos) == "}" then
			pos = pos + 1
			return obj
		end
		while true do
			skip_ws()
			assert(text:sub(pos, pos) == '"', "expected a key at " .. pos)
			local key = parse_string()
			skip_ws()
			assert(text:sub(pos, pos) == ":", "expected : at " .. pos)
			pos = pos + 1
			skip_ws()
			obj[key] = parse_value()
			skip_ws()
			local c = text:sub(pos, pos)
			pos = pos + 1
			if c == "}" then
				return obj
			end
			assert(c == ",", "expected , in object")
		end
	end

	function parse_value()
		skip_ws()
		local c = text:sub(pos, pos)
		if c == "{" then
			return parse_object()
		end
		if c == "[" then
			return parse_array()
		end
		if c == '"' then
			return parse_string()
		end
		if text:sub(pos, pos + 3) == "true" then
			pos = pos + 4
			return true
		end
		if text:sub(pos, pos + 4) == "false" then
			pos = pos + 5
			return false
		end
		if text:sub(pos, pos + 3) == "null" then
			pos = pos + 4
			return nil
		end
		return parse_number()
	end

	return parse_value()
end

local function read_json(name)
	local f = assert(io.open(DATA_DIR .. name .. ".json", "rb"))
	local text = f:read("*a")
	f:close()
	return decode_json(text)
end

local REG = D.new({
	species = read_json("species"),
	moves = read_json("moves"),
	types = read_json("types"),
	items = read_json("items"),
})
local INST = I.create(F, REG)

-- Walks a value and reports whether it is JSON-safe: strings, numbers, booleans and plain tables only.
local function is_json_safe(value)
	local kind = type(value)
	if kind == "string" or kind == "boolean" then
		return true
	end
	if kind == "number" then
		return value == value and value ~= math.huge and value ~= -math.huge
	end
	if kind ~= "table" then
		return false
	end
	for k, v in pairs(value) do
		if type(k) ~= "string" and type(k) ~= "number" then
			return false
		end
		if not is_json_safe(v) then
			return false
		end
	end
	return true
end

describe("data registry", function()
	it("looks species up by name (any case) and by id", function()
		assert.equals(19, REG.get_species("Rattata").id)
		assert.equals("rattata", REG.get_species(19).name)
		assert.equals(19, REG.get_species("RATTATA").id)
		assert.is_nil(REG.get_species("missingno"))
		assert.is_nil(REG.get_species(252))
		assert.is_nil(REG.get_species(nil))
	end)

	it("lists ids 1..251 and returns a fresh table each time", function()
		local ids = REG.all_species_ids()
		assert.equals(251, #ids)
		assert.equals(1, ids[1])
		assert.equals(251, ids[251])
		ids[1] = 999
		assert.equals(1, REG.all_species_ids()[1])
	end)

	it("type_multiplier: electric on ground is 0, and dual types multiply", function()
		assert.equals(0, REG.type_multiplier("electric", { "ground" }))
		assert.equals(0, REG.type_multiplier("electric", "ground"))
		assert.equals(4, REG.type_multiplier("water", { "fire", "ground" }))
		assert.equals(2, REG.type_multiplier("fire", { "grass", "poison" }))
		assert.equals(0.5, REG.type_multiplier("fire", { "water" }))
		assert.equals(0, REG.type_multiplier("normal", { "ghost" }))
		assert.equals(1, REG.type_multiplier("fire", {}))
	end)

	it("get_move and get_item read the move and item tables", function()
		assert.equals(25, REG.get_move("ember").pp)
		assert.is_nil(REG.get_move("no_such_move"))
		assert.equals(1.0, REG.get_item("poke_ball").catch_mult)
	end)

	it("every species has a usable growth rate and every learnset move exists", function()
		for _, id in ipairs(REG.all_species_ids()) do
			local sp = REG.get_species(id)
			assert.equals(100, F.level_for_exp(F.exp_for_level(100, sp.growth_rate), sp.growth_rate), sp.name)
			for _, entry in ipairs(sp.learnset) do
				assert.is_truthy(REG.get_move(entry.move), sp.name .. " learns unknown move " .. entry.move)
			end
		end
	end)
end)

describe("instance (real data)", function()
	local cyndaquil = REG.get_species("cyndaquil")

	local function ids_of(moves)
		local out = {}
		for i, mv in ipairs(moves) do
			out[i] = mv.id
		end
		return out
	end

	it("creates Cyndaquil L12 with ember among its moves and the correct fields", function()
		local inst = INST.new(cyndaquil, 12, R.new(7))
		assert.equals(155, inst.species_id)
		assert.equals(12, inst.level)
		assert.equals(973, inst.exp)
		assert.equals("", inst.nickname)
		assert.equals(0, inst.bond)
		assert.equals("none", inst.status)
		assert.equals("poke_ball", inst.ball)
		assert.is_false(inst.shiny)
		assert.is_nil(inst.owner)
	end)

	it("L12 moves are the four learnset moves so far, with pp from the move data", function()
		local inst = INST.new(cyndaquil, 12, R.new(7))
		assert.are.same({ "leer", "tackle", "smokescreen", "ember" }, ids_of(inst.moves))
		assert.equals(25, inst.moves[4].pp)
		assert.equals(30, inst.moves[1].pp)
	end)

	it("L50 keeps only the last four learnset moves", function()
		local inst = INST.new(cyndaquil, 50, R.new(3))
		assert.are.same({ "quick_attack", "flame_wheel", "swift", "flamethrower" }, ids_of(inst.moves))
	end)

	it("L1 gives only the level 1 moves", function()
		local inst = INST.new(cyndaquil, 1, R.new(3))
		assert.are.same({ "leer", "tackle" }, ids_of(inst.moves))
	end)

	it("uid is <species_id>-<1..1e9> and the IVs are 0..15 integers", function()
		local inst = INST.new(cyndaquil, 12, R.new(7))
		local n = inst.uid:match("^155%-(%d+)$")
		assert.is_truthy(n)
		assert.is_true(tonumber(n) >= 1 and tonumber(n) <= 1000000000)
		for _, key in ipairs(I.IV_KEYS) do
			local v = inst.ivs[key]
			assert.is_true(v >= 0 and v <= 15 and v == math.floor(v), key .. " = " .. tostring(v))
		end
	end)

	it("the same seed gives the same creature, and hp matches the stats", function()
		local a = INST.new(cyndaquil, 12, R.new(2026))
		local b = INST.new(cyndaquil, 12, R.new(2026))
		assert.are.same(a, b)
		assert.equals(F.calc_stats(cyndaquil.base_stats, 12, a.ivs, 0).hp, a.hp)
		assert.are.same(F.calc_stats(cyndaquil.base_stats, 12, a.ivs, 0), INST.stats(a, cyndaquil))
	end)

	it("serialize then deserialize gives back the same instance", function()
		local inst = INST.new(cyndaquil, 12, R.new(7))
		inst.nickname = "Flicker"
		inst.bond = 130
		inst.status = "burn"
		inst.owner = "alice"
		assert.are.same(inst, INST.deserialize(INST.serialize(inst)))
	end)

	it("serialize output is JSON-safe and does not share tables with the instance", function()
		local inst = INST.new(cyndaquil, 12, R.new(7))
		local out = INST.serialize(inst)
		assert.is_true(is_json_safe(out))
		out.moves[1].pp = 0
		out.ivs.hp = 99
		assert.is_true(inst.moves[1].pp ~= 0)
		assert.is_true(inst.ivs.hp ~= 99)
	end)

	it("deserialize fills defaults for missing fields", function()
		local inst = INST.deserialize({ species_id = 155, level = 5 })
		assert.equals(155, inst.species_id)
		assert.equals(5, inst.level)
		assert.equals("", inst.nickname)
		assert.equals("none", inst.status)
		assert.equals("poke_ball", inst.ball)
		assert.equals(0, inst.bond)
		assert.is_false(inst.shiny)
		assert.are.same({}, inst.moves)
	end)
end)
