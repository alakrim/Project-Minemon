extends GutTest
## Contract: CombatantView fields level, stats, types, status and stages, with their types.


func test_fields_have_their_declared_types() -> void:
	var view := CombatantView.new()
	assert_typeof(view.level, TYPE_INT)
	assert_typeof(view.stats, TYPE_DICTIONARY)
	assert_typeof(view.types, TYPE_ARRAY)
	assert_typeof(view.status, TYPE_STRING)
	assert_typeof(view.stages, TYPE_DICTIONARY)


func test_stages_cover_all_seven_keys_at_zero() -> void:
	var view := CombatantView.new()
	for key: String in ["atk", "def", "spa", "spd", "spe", "acc", "eva"]:
		assert_eq(view.stages[key], 0, key)
