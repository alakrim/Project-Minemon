extends GutTest
## Contract: CreatureInstance fields, to_dict() -> Dictionary and static from_dict(d) -> CreatureInstance.


func test_fields_have_their_declared_types() -> void:
	var c := CreatureInstance.new()
	assert_typeof(c.uid, TYPE_STRING)
	assert_typeof(c.species_id, TYPE_INT)
	assert_typeof(c.ivs, TYPE_DICTIONARY)
	assert_typeof(c.moves, TYPE_ARRAY)
	assert_typeof(c.shiny, TYPE_BOOL)


func test_to_dict_and_from_dict_exist_and_return_the_right_types() -> void:
	var c := CreatureInstance.new()
	assert_has_method(c, "to_dict")
	assert_typeof(c.to_dict(), TYPE_DICTIONARY)
	assert_is(CreatureInstance.from_dict({}), CreatureInstance)
