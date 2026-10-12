extends GutTest
## Unit tests for Catch: hand-computed chances, status multipliers, ball ordering, bounds and seeded rolls.


func _species(catch_rate: int) -> SpeciesData:
	var sp := SpeciesData.new()
	sp.catch_rate = catch_rate
	return sp


func test_full_hp_poke_ball_against_gengar() -> void:
	# a = (3*max - 2*cur) * 45 * 1 / (3*max) with cur = max: (3 - 2) * 45 / 3 = 15. Chance = 15/255.
	var chance: float = Catch.chance(_species(45), 1.0, 1.0, "")
	assert_almost_eq(chance, 15.0 / 255.0, 0.000001)


func test_zero_hp_uses_full_factor() -> void:
	# a = (3 - 0) * 45 / 3 = 45. Chance = 45/255.
	assert_almost_eq(Catch.chance(_species(45), 0.0, 1.0, ""), 45.0 / 255.0, 0.000001)


func test_sleep_doubles_and_burn_multiplies_by_one_and_a_half() -> void:
	assert_almost_eq(Catch.chance(_species(45), 1.0, 1.0, "sleep"), 30.0 / 255.0, 0.000001)
	assert_almost_eq(Catch.chance(_species(45), 1.0, 1.0, "freeze"), 30.0 / 255.0, 0.000001)
	assert_almost_eq(Catch.chance(_species(45), 1.0, 1.0, "burn"), 22.5 / 255.0, 0.000001)
	assert_almost_eq(Catch.chance(_species(45), 1.0, 1.0, "paralysis"), 22.5 / 255.0, 0.000001)
	assert_almost_eq(Catch.chance(_species(45), 1.0, 1.0, "poison"), 22.5 / 255.0, 0.000001)


func test_ball_ordering_poke_great_ultra_master() -> void:
	var sp: SpeciesData = _species(45)
	var poke: float = Catch.chance(sp, 1.0, 1.0, "")
	var great: float = Catch.chance(sp, 1.0, 1.5, "")
	var ultra: float = Catch.chance(sp, 1.0, 2.0, "")
	var master: float = Catch.chance(sp, 1.0, 255.0, "")
	assert_lt(poke, great)
	assert_lt(great, ultra)
	assert_lt(ultra, master)
	assert_almost_eq(master, 1.0, 0.000001, "master ball is a certain catch")


func test_chance_stays_within_zero_and_one() -> void:
	var out_of_bounds: int = 0
	for rate: int in [3, 45, 127, 255]:
		for hp: float in [0.0, 0.5, 1.0]:
			for ball: float in [1.0, 1.5, 2.0, 255.0]:
				for status: String in ["", "sleep", "burn"]:
					var chance: float = Catch.chance(_species(rate), hp, ball, status)
					if chance < 0.0 or chance > 1.0:
						out_of_bounds += 1
	assert_eq(out_of_bounds, 0)


func test_roll_with_zero_and_one_are_certain() -> void:
	var rng := Rng.new(5)
	var misses_at_zero: int = 0
	var catches_at_one: int = 0
	for i: int in 200:
		if Catch.roll(0.0, rng):
			misses_at_zero += 1
		if Catch.roll(1.0, rng):
			catches_at_one += 1
	assert_eq(misses_at_zero, 0)
	assert_eq(catches_at_one, 200)


func test_seeded_roll_at_half_is_about_half() -> void:
	var rng := Rng.new(1234)
	var catches: int = 0
	for i: int in 2000:
		if Catch.roll(0.5, rng):
			catches += 1
	assert_between(catches, 900, 1100)
