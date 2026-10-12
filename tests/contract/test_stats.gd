extends GutTest
## Contract: Stats.calc(base, level, ivs, bond) -> Dictionary with keys hp..spe.


func test_calc_returns_all_six_stats_as_ints() -> void:
	var base: Dictionary = {"hp": 45, "atk": 49, "def": 49, "spa": 65, "spd": 65, "spe": 45}
	var stats: Dictionary = Stats.calc(base, 5, {}, 0)
	assert_typeof(stats, TYPE_DICTIONARY)
	for key: String in ["hp", "atk", "def", "spa", "spd", "spe"]:
		assert_typeof(stats[key], TYPE_INT, key)
