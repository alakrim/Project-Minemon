extends GutTest
## Unit tests for TypeChart: single and dual types, neutral entries, 4x and 0x results.


func _chart() -> TypeChart:
	var table: Dictionary = {
		"ice": {"dragon": 2.0, "ground": 2.0, "water": 0.5},
		"electric": {"ground": 0.0, "flying": 2.0},
		"fire": {"grass": 2.0},
	}
	return TypeChart.new(table)


func test_single_type_super_and_not_very_effective() -> void:
	var types: Array[String] = ["grass"]
	assert_almost_eq(_chart().multiplier("fire", types), 2.0, 0.0001)
	var water: Array[String] = ["water"]
	assert_almost_eq(_chart().multiplier("ice", water), 0.5, 0.0001)


func test_missing_entry_is_neutral() -> void:
	var types: Array[String] = ["normal"]
	assert_almost_eq(_chart().multiplier("fire", types), 1.0, 0.0001)
	assert_almost_eq(_chart().multiplier("unknown", types), 1.0, 0.0001)


func test_dual_type_gives_four_times() -> void:
	# Ice into Dragon/Ground: 2 * 2 = 4.
	var types: Array[String] = ["dragon", "ground"]
	assert_almost_eq(_chart().multiplier("ice", types), 4.0, 0.0001)


func test_dual_type_gives_zero_when_one_type_is_immune() -> void:
	# Electric into Ground/Flying: 0 * 2 = 0.
	var types: Array[String] = ["ground", "flying"]
	assert_almost_eq(_chart().multiplier("electric", types), 0.0, 0.0001)
