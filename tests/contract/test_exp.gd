extends GutTest
## Contract: Exp.gain, Exp.exp_for_level and Exp.level_for all return int.


func test_gain_exp_for_level_and_level_for_return_ints() -> void:
	var sp := SpeciesData.new()
	sp.base_exp = 51
	assert_typeof(Exp.gain(sp, 5, 0), TYPE_INT)
	assert_typeof(Exp.exp_for_level(10, "medium_fast"), TYPE_INT)
	assert_typeof(Exp.level_for(1000, "medium_fast"), TYPE_INT)
