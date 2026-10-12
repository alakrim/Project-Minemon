extends GutTest
## Contract: MoveData.from_dict(d) -> MoveData; null power and accuracy read as absent.


func test_from_dict_returns_move_data() -> void:
	var raw: Dictionary = {
		"id": "ember",
		"name": "Ember",
		"type": "fire",
		"category": "special",
		"power": 40,
		"accuracy": 100,
		"pp": 25,
		"priority": 0,
		"archetype": "projectile",
		"range_m": 12.0,
		"cast_s": 0.5,
		"cooldown_s": 1.2,
		"effect": {"status": "burn", "status_chance": 10},
	}
	var move: MoveData = MoveData.from_dict(raw)
	assert_is(move, MoveData)
	assert_typeof(move.power, TYPE_INT)
	assert_true(move.has_power())
	assert_true(move.has_accuracy())


func test_null_power_and_accuracy_are_reported_absent() -> void:
	var move: MoveData = MoveData.from_dict({"power": null, "accuracy": null, "category": "status"})
	assert_false(move.has_power())
	assert_false(move.has_accuracy())
	assert_true(move.is_status())
