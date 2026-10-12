extends GutTest
## Unit tests for Exp: gain, the six growth-rate curves at L10 and L100, level 1, and the level_for inverse.

const GROWTHS: Array[String] = [
	"fast", "medium_fast", "medium_slow", "slow", "erratic", "fluctuating"
]


func _species(base_exp: int) -> SpeciesData:
	var sp := SpeciesData.new()
	sp.base_exp = base_exp
	return sp


func test_gain_is_floor_of_base_level_over_7() -> void:
	# Rattata base 51, level 5, bond 0: floor(51 * 5 / 7) = floor(36.43) = 36.
	assert_eq(Exp.gain(_species(51), 5, 0), 36)


func test_gain_bond_multiplier() -> void:
	# Bond 255 gives x(1 + 255/510) = x1.5: floor(36.43 * 1.5) = floor(54.64) = 54.
	assert_eq(Exp.gain(_species(51), 5, 255), 54)


func test_exp_for_level_10_for_every_growth_rate() -> void:
	var expected: Dictionary = {
		"fast": 800,
		"medium_fast": 1000,
		"medium_slow": 560,
		"slow": 1250,
		"erratic": 1800,
		"fluctuating": 540,
	}
	for growth: String in GROWTHS:
		assert_eq(Exp.exp_for_level(10, growth), expected[growth], "level 10 for " + growth)


func test_exp_for_level_100_for_every_growth_rate() -> void:
	var expected: Dictionary = {
		"fast": 800000,
		"medium_fast": 1000000,
		"medium_slow": 1059860,
		"slow": 1250000,
		"erratic": 600000,
		"fluctuating": 1640000,
	}
	for growth: String in GROWTHS:
		assert_eq(Exp.exp_for_level(100, growth), expected[growth], "level 100 for " + growth)


func test_level_1_needs_zero_exp_for_every_growth_rate() -> void:
	for growth: String in GROWTHS:
		assert_eq(Exp.exp_for_level(1, growth), 0, "level 1 for " + growth)


func test_level_for_inverts_exp_for_level() -> void:
	var mismatches: Array[String] = []
	for growth: String in GROWTHS:
		for lv: int in range(1, 101):
			var total: int = Exp.exp_for_level(lv, growth)
			if Exp.level_for(total, growth) != lv:
				mismatches.append("%s L%d" % [growth, lv])
	assert_eq(mismatches, [], "level_for(exp_for_level(L)) should return L")


func test_level_for_just_below_a_threshold_gives_the_level_below() -> void:
	assert_eq(Exp.level_for(Exp.exp_for_level(10, "medium_fast") - 1, "medium_fast"), 9)


func test_level_for_is_capped_at_100() -> void:
	assert_eq(Exp.level_for(999999999, "medium_fast"), 100)
	assert_eq(Exp.level_for(0, "slow"), 1)
