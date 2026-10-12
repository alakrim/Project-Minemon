extends GutTest
## Contract: DamageResult fields amount:int, crit:bool, effectiveness:float, missed:bool.


func test_fields_have_their_declared_types() -> void:
	var result := DamageResult.new()
	assert_typeof(result.amount, TYPE_INT)
	assert_typeof(result.crit, TYPE_BOOL)
	assert_typeof(result.effectiveness, TYPE_FLOAT)
	assert_typeof(result.missed, TYPE_BOOL)


func test_defaults_describe_a_neutral_hit() -> void:
	var result := DamageResult.new()
	assert_eq(result.amount, 0)
	assert_false(result.crit)
	assert_false(result.missed)
	assert_almost_eq(result.effectiveness, 1.0, 0.0001)
