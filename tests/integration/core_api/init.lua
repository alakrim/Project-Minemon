-- Integration test (M1 T-20): the minemon_core API is loaded and works inside the assembled game.
-- Writes PASS n or FAIL <reason> to test_result.txt in the world folder, then shuts the server down.
-- luacheck: globals minemon

local function write_result(line)
	core.safe_file_write(core.get_worldpath() .. "/test_result.txt", line .. "\n")
	core.request_shutdown()
end

local function run_checks()
	local checks = 0
	local function check(condition, reason)
		checks = checks + 1
		if not condition then
			error(reason, 0)
		end
	end

	check(type(minemon) == "table", "global minemon is missing")
	for _, name in ipairs({ "data", "formulas", "rng", "instance", "events" }) do
		check(type(minemon[name]) == "table", "minemon." .. name .. " is missing")
	end

	local data = minemon.data
	check(data.get_species("Rattata").id == 19, "get_species('Rattata').id is not 19")
	check(data.get_species(19).name == "rattata", "get_species(19).name is not rattata")
	check(data.type_multiplier("electric", { "ground" }) == 0, "electric on ground is not 0")
	check(#data.all_species_ids() == 251, "all_species_ids is not 251 long")

	check(minemon.formulas.exp_for_level(12, "medium_slow") == 973, "exp_for_level(12, medium_slow) is not 973")
	local wild = minemon.formulas.wild_level(800, false, minemon.rng.new(5))
	check(wild >= 10 and wild <= 14, "wild_level(800) is outside 10..14: " .. wild)

	local cyndaquil = data.get_species("cyndaquil")
	local inst = minemon.instance.new(cyndaquil, 12, minemon.rng.new(7))
	check(inst.species_id == 155, "instance species_id is not 155")
	check(inst.level == 12 and inst.exp == 973, "instance level or exp is wrong")
	check(string.match(inst.uid, "^155%-%d+$") ~= nil, "instance uid has the wrong shape: " .. inst.uid)
	local has_ember = false
	for _, mv in ipairs(inst.moves) do
		if mv.id == "ember" then
			has_ember = true
		end
	end
	check(has_ember, "Cyndaquil L12 has no ember")
	local expected_hp = minemon.formulas.calc_stats(cyndaquil.base_stats, 12, inst.ivs, 0).hp
	check(inst.hp == expected_hp, "instance hp does not match calc_stats")
	check(minemon.instance.stats(inst, cyndaquil).hp == inst.hp, "instance.stats disagrees with hp")

	local copy = minemon.instance.deserialize(minemon.instance.serialize(inst))
	check(copy.uid == inst.uid and copy.hp == inst.hp, "serialize round trip lost fields")

	local a_ran, b_ran = false, false
	minemon.events.register("minemon_test_event", function()
		a_ran = true
		error("deliberate test failure")
	end)
	minemon.events.register("minemon_test_event", function()
		b_ran = true
	end)
	minemon.events.fire("minemon_test_event", inst, nil)
	check(a_ran and b_ran, "a failing event handler stopped the others")

	return checks
end

core.after(1, function()
	local ok, result = pcall(run_checks)
	if ok then
		write_result("PASS " .. result)
	else
		write_result("FAIL " .. tostring(result))
	end
end)
