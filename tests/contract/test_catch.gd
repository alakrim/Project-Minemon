extends GutTest
## Contract: Catch.chance(sp, hp_frac, ball_mult, status) -> float and Catch.roll(chance, rng) -> bool.


func test_chance_returns_float_between_zero_and_one() -> void:
	var sp := SpeciesData.new()
	sp.catch_rate = 45
	var value: float = Catch.chance(sp, 1.0, 1.0, "")
	assert_typeof(value, TYPE_FLOAT)
	assert_between(value, 0.0, 1.0)


func test_roll_returns_bool() -> void:
	assert_typeof(Catch.roll(0.5, Rng.new(1)), TYPE_BOOL)
