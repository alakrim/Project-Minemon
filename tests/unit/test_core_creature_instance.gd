extends GutTest
## Unit tests for CreatureInstance: to_dict/from_dict round-trip for every field, also through JSON.


func _sample() -> CreatureInstance:
	var c := CreatureInstance.new()
	c.uid = "a1b2c3"
	c.species_id = 155
	c.nickname = "Ember"
	c.level = 12
	c.total_exp = 1234
	c.ivs = {"hp": 15, "atk": 7, "def": 3, "spa": 12, "spd": 9, "spe": 14}
	c.bond = 200
	c.current_hp = 31
	c.status = "burn"
	c.moves = [{"id": "tackle", "pp": 35}, {"id": "ember", "pp": 20}]
	c.held_item = "potion"
	c.ball = "great_ball"
	c.shiny = true
	c.caught_at = "route_1"
	return c


func _assert_same(a: CreatureInstance, b: CreatureInstance) -> void:
	assert_eq(a.uid, b.uid, "uid")
	assert_eq(a.species_id, b.species_id, "species_id")
	assert_eq(a.nickname, b.nickname, "nickname")
	assert_eq(a.level, b.level, "level")
	assert_eq(a.total_exp, b.total_exp, "total_exp")
	assert_eq(a.ivs, b.ivs, "ivs")
	assert_eq(a.bond, b.bond, "bond")
	assert_eq(a.current_hp, b.current_hp, "current_hp")
	assert_eq(a.status, b.status, "status")
	assert_eq(a.moves, b.moves, "moves")
	assert_eq(a.held_item, b.held_item, "held_item")
	assert_eq(a.ball, b.ball, "ball")
	assert_eq(a.shiny, b.shiny, "shiny")
	assert_eq(a.caught_at, b.caught_at, "caught_at")


func test_dict_round_trip_keeps_every_field() -> void:
	var original: CreatureInstance = _sample()
	_assert_same(original, CreatureInstance.from_dict(original.to_dict()))


func test_json_round_trip_keeps_every_field() -> void:
	# Saves are JSON, where numbers come back as floats; from_dict must restore ints.
	var original: CreatureInstance = _sample()
	var text: String = JSON.stringify(original.to_dict())
	var parsed: Variant = JSON.parse_string(text)
	var restored: CreatureInstance = CreatureInstance.from_dict(parsed)
	_assert_same(original, restored)
	assert_typeof(restored.level, TYPE_INT)
	assert_typeof(restored.moves[0]["pp"], TYPE_INT)


func test_to_dict_does_not_share_nested_state() -> void:
	var original: CreatureInstance = _sample()
	var dict: Dictionary = original.to_dict()
	dict["ivs"]["hp"] = 0
	assert_eq(original.ivs["hp"], 15)
