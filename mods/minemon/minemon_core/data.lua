-- Data registry (minemon_core). Pure: it receives already-parsed tables, so it never reads files.
-- init.lua parses data/*.json with parse_json and passes the results to M.new.

local M = {}

local function index_species(list)
	local by_id, by_name, ids = {}, {}, {}
	for _, sp in ipairs(list) do
		assert(type(sp.id) == "number" and type(sp.name) == "string", "minemon: species entry needs id and name")
		by_id[sp.id] = sp
		by_name[string.lower(sp.name)] = sp
		ids[#ids + 1] = sp.id
	end
	table.sort(ids)
	return by_id, by_name, ids
end

-- tables: { species = array, moves = map, types = { chart = map, types = array }, items = map }
function M.new(tables)
	assert(type(tables) == "table", "minemon: data.new needs a table of parsed data")
	assert(type(tables.species) == "table", "minemon: data.new needs species")
	assert(type(tables.moves) == "table", "minemon: data.new needs moves")
	assert(type(tables.types) == "table" and type(tables.types.chart) == "table", "minemon: data.new needs types.chart")
	assert(type(tables.items) == "table", "minemon: data.new needs items")

	local by_id, by_name, ids = index_species(tables.species)
	local moves = tables.moves
	local items = tables.items
	local chart = tables.types.chart

	local reg = {}

	-- id (number) or name (string, case-insensitive). Returns the species table or nil.
	function reg.get_species(id_or_name)
		if type(id_or_name) == "number" then
			return by_id[id_or_name]
		end
		if type(id_or_name) == "string" then
			return by_name[string.lower(id_or_name)]
		end
		return nil
	end

	function reg.get_move(id)
		return moves[id]
	end

	function reg.get_item(id)
		return items[id]
	end

	-- Ids 1..251 in ascending order (a fresh table each call).
	function reg.all_species_ids()
		local out = {}
		for i, id in ipairs(ids) do
			out[i] = id
		end
		return out
	end

	-- Product of the attacking type's multiplier against each defending type. def_types is a list of type names.
	-- The chart stores only entries that are not 1.0, so a missing entry counts as 1.0.
	function reg.type_multiplier(atk_type, def_types)
		if type(def_types) == "string" then
			def_types = { def_types }
		end
		local row = chart[atk_type] or {}
		local result = 1.0
		for _, def_type in ipairs(def_types or {}) do
			result = result * (row[def_type] or 1.0)
		end
		return result
	end

	return reg
end

return M
