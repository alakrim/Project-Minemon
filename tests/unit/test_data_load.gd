extends GutTest
## Unit tests for the Data registry: shipped data validates, the bad fixture gives exactly 5 named errors,
## and the shipped Gen 2 values match the sources.

const BAD_DIR: String = "res://tests/fixtures/bad_data"


func after_each() -> void:
	Data.load_all()


func test_shipped_data_has_no_errors() -> void:
	var errors: Array[String] = Data.load_all()
	assert_eq(errors, [], "shipped data should validate with no errors")


func test_bad_fixture_gives_exactly_five_errors() -> void:
	var errors: Array[String] = Data.load_all(BAD_DIR)
	assert_eq(errors.size(), 5, "errors were: " + str(errors))


func test_bad_fixture_errors_each_name_their_field() -> void:
	var errors: Array[String] = Data.load_all(BAD_DIR)
	var expected: Array[String] = [
		"species.json[16].types:",
		"species.json[19].catch_rate:",
		"species.json[155].growth_rate:",
		"species.json[92].learnset[",
		"moves.json[ember].category:",
	]
	for prefix: String in expected:
		var found: bool = false
		for error: String in errors:
			if error.begins_with(prefix):
				found = true
		assert_true(found, "no error names " + prefix)


func test_failed_load_serves_nothing() -> void:
	Data.load_all(BAD_DIR)
	assert_null(Data.species(19), "a load with errors should leave the registry empty")


func test_shipped_species_values_match_sources() -> void:
	# Raticate (20): base stats 55/81/60/50/70/97, catch rate 127 (PokeAPI CSVs).
	var raticate: SpeciesData = Data.species(20)
	assert_eq(
		raticate.base_stats, {"hp": 55, "atk": 81, "def": 60, "spa": 50, "spd": 70, "spe": 97}
	)
	assert_eq(raticate.catch_rate, 127)
	# Gengar (94): catch rate 45.
	assert_eq(Data.species(94).catch_rate, 45)


func test_ember_matches_gen_2_values() -> void:
	# Ember: power 40, accuracy 100, PP 25, burn 10% (PokeAPI moves.csv; Bulbapedia Ember page).
	var ember: MoveData = Data.move("ember")
	assert_eq(ember.power, 40)
	assert_eq(ember.accuracy, 100)
	assert_eq(ember.pp, 25)
	assert_eq(ember.category, "special")


func test_gen_2_chart_has_steel_resisting_ghost() -> void:
	# Gen 2 (Pokemon Showdown data/mods/gen2/typechart.ts): Ghost into Steel is not very effective.
	var steel: Array[String] = ["steel"]
	assert_almost_eq(Data.chart().multiplier("ghost", steel), 0.5, 0.0001)
	# Electric into Steel is neutral in Gen 2.
	assert_almost_eq(Data.chart().multiplier("electric", steel), 1.0, 0.0001)


func test_registry_holds_the_eleven_species() -> void:
	assert_eq(Data.all_species_ids(), [16, 17, 18, 19, 20, 92, 93, 94, 155, 156, 157])


func test_every_learnset_move_and_evolution_target_exists() -> void:
	var missing: Array[String] = []
	for id: int in Data.all_species_ids():
		var sp: SpeciesData = Data.species(id)
		for row: Dictionary in sp.learnset:
			if Data.move(str(row["move"])) == null:
				missing.append("%d:%s" % [id, row["move"]])
		for evo: Dictionary in sp.evolutions:
			if Data.species(int(evo["to"])) == null:
				missing.append("%d->%s" % [id, evo["to"]])
	assert_eq(missing, [])


func test_unknown_ids_return_null() -> void:
	assert_null(Data.species(999))
	assert_null(Data.move("no_such_move"))
	assert_null(Data.item("no_such_item"))


func test_cyndaquil_learnset_matches_gold_silver_csv() -> void:
	# PokeAPI pokemon_moves.csv: pokemon_id 155, version_group_id 3 (gold-silver),
	# method 1 (level-up), level <= 20.
	Data.load_all()
	var expected: Array[String] = [
		"1:tackle", "1:leer", "6:smokescreen", "12:ember", "19:quick_attack"
	]
	var actual: Array[String] = []
	for row: Dictionary in Data.species(155).learnset:
		actual.append("%d:%s" % [int(row["level"]), str(row["move"])])
	expected.sort()
	actual.sort()
	assert_eq(actual, expected)


func test_gold_silver_learnset_row_counts_match_csv() -> void:
	# Level-up rows per species from pokemon_moves.csv (gold-silver, level <= 20). Duplicate moves are kept.
	Data.load_all()
	var expected: Dictionary = {
		16: 4,
		17: 6,
		18: 7,
		19: 5,
		20: 6,
		92: 5,
		93: 6,
		94: 6,
		155: 5,
		156: 5,
		157: 6,
	}
	for id: int in expected:
		assert_eq(
			Data.species(id).learnset.size(), expected[id], "learnset rows for species %d" % id
		)


func test_scary_face_accuracy_is_gen_2_90() -> void:
	# move_changelog.csv: accuracy was 90 until version group 11.
	Data.load_all()
	assert_eq(Data.move("scary_face").accuracy, 90)
