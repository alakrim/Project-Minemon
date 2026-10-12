extends GutTest
## Unit tests for Stats.calc with Cyndaquil (base 39/52/43/60/50/65), at L5 and L50, plus the bond bonus.

const CYNDAQUIL_BASE: Dictionary = {"hp": 39, "atk": 52, "def": 43, "spa": 60, "spd": 50, "spe": 65}


func _ivs(value: int) -> Dictionary:
	return {"hp": value, "atk": value, "def": value, "spa": value, "spd": value, "spe": value}


func test_cyndaquil_level_5_zero_iv() -> void:
	# HP: floor(78*5/100)=3, +5+10 = 18. Others: floor(104*5/100)=5 etc, +5.
	var stats: Dictionary = Stats.calc(CYNDAQUIL_BASE, 5, _ivs(0), 0)
	assert_eq(stats, {"hp": 18, "atk": 10, "def": 9, "spa": 11, "spd": 10, "spe": 11})


func test_cyndaquil_level_5_max_iv() -> void:
	# HP: floor(93*5/100)=4, +15 = 19. Atk: floor(119*5/100)=5, +5 = 10. Spe: floor(145*5/100)=7, +5 = 12.
	var stats: Dictionary = Stats.calc(CYNDAQUIL_BASE, 5, _ivs(15), 0)
	assert_eq(stats, {"hp": 19, "atk": 10, "def": 10, "spa": 11, "spd": 10, "spe": 12})


func test_cyndaquil_level_50_zero_iv() -> void:
	# HP: floor(78*50/100)=39, +50+10 = 99. Atk: 52+5 = 57. Spe: 65+5 = 70.
	var stats: Dictionary = Stats.calc(CYNDAQUIL_BASE, 50, _ivs(0), 0)
	assert_eq(stats, {"hp": 99, "atk": 57, "def": 48, "spa": 65, "spd": 55, "spe": 70})


func test_cyndaquil_level_50_max_iv() -> void:
	var stats: Dictionary = Stats.calc(CYNDAQUIL_BASE, 50, _ivs(15), 0)
	assert_eq(stats, {"hp": 106, "atk": 64, "def": 55, "spa": 72, "spd": 62, "spe": 77})


func test_bond_bonus_is_floor_of_bond_over_25_percent() -> void:
	# Bond 255 gives floor(255/25) = 10%: 99 -> 108 (108.9 floored), 57 -> 62, 70 -> 77.
	var stats: Dictionary = Stats.calc(CYNDAQUIL_BASE, 50, _ivs(0), 255)
	assert_eq(stats["hp"], 108)
	assert_eq(stats["atk"], 62)
	assert_eq(stats["spe"], 77)
	# Bond 24 gives 0%, bond 25 gives 1%: 99 * 1.01 = 99.99, floored to 99.
	assert_eq(Stats.calc(CYNDAQUIL_BASE, 50, _ivs(0), 24)["hp"], 99)
	assert_eq(Stats.calc(CYNDAQUIL_BASE, 50, _ivs(0), 25)["hp"], 99)
	assert_eq(Stats.calc(CYNDAQUIL_BASE, 50, _ivs(0), 50)["hp"], 100)
