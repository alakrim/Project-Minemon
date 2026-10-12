extends GutTest
## Unit tests for Damage: a hand-computed hit, misses and crits, STAB, fixed damage and seeded statistics.


## Rng stub with fixed roll values, so one hit can be checked by hand.
class FixedRng:
	extends Rng
	var float_value: float = 0.5
	var int_value: int = 100

	func _init() -> void:
		super(0)

	func randf() -> float:
		return float_value

	func randi_range(_from: int, _to: int) -> int:
		return int_value


func _rng(float_value: float, int_value: int) -> FixedRng:
	var rng := FixedRng.new()
	rng.float_value = float_value
	rng.int_value = int_value
	return rng


func _chart() -> TypeChart:
	return TypeChart.new(
		{"fire": {"grass": 2.0, "water": 0.5}, "electric": {"water": 0.5, "ground": 0.0}}
	)


func _move(overrides: Dictionary) -> MoveData:
	var d: Dictionary = {
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
		"effect": {},
	}
	for key: Variant in overrides:
		d[key] = overrides[key]
	return MoveData.from_dict(d)


## Level 50 fire-type attacker with Sp.Atk 100 and Atk 100, all stages 0.
func _attacker(level: int = 50, types: Array[String] = ["fire"]) -> CombatantView:
	var view := CombatantView.new()
	view.level = level
	view.stats = {"hp": 100, "atk": 100, "def": 100, "spa": 100, "spd": 100, "spe": 100}
	view.types = types
	return view


## Normal-type defender with Sp.Def 50 and Def 50, all stages 0.
func _defender(types: Array[String] = ["normal"], spd: int = 50) -> CombatantView:
	var view := CombatantView.new()
	view.level = 50
	view.stats = {"hp": 100, "atk": 50, "def": 50, "spa": 50, "spd": spd, "spe": 50}
	view.types = types
	return view


func test_hand_computed_special_hit() -> void:
	# A = spa 100 x stage 1 = 100. D = spd 50 x stage 1 = 50.
	# step1 = floor(2*50/5 + 2) = 22.
	# step2 = floor(22 * 40 * 100 / 50) = 1760. base = floor(1760 / 50) + 2 = 37.
	# STAB 1.5 (fire move, fire user), type 1.0 (normal defender), crit 1.0, random 1.0.
	# raw = 37 * 1.5 = 55.5, floored to 55.
	var result: DamageResult = Damage.compute(
		_attacker(), _defender(), _move({}), _chart(), _rng(0.5, 100)
	)
	assert_eq(result.amount, 55)
	assert_false(result.missed)
	assert_false(result.crit)
	assert_almost_eq(result.effectiveness, 1.0, 0.0001)


func test_low_random_roll_lowers_damage() -> void:
	# Same hit with random 85/100: 37 * 1.5 * 0.85 = 47.175, floored to 47.
	var result: DamageResult = Damage.compute(
		_attacker(), _defender(), _move({}), _chart(), _rng(0.5, 85)
	)
	assert_eq(result.amount, 47)


func test_crit_doubles_damage() -> void:
	# A roll of 0.01 is below the 1/16 crit chance: 37 * 1.5 * 2.0 = 111.
	var result: DamageResult = Damage.compute(
		_attacker(), _defender(), _move({}), _chart(), _rng(0.01, 100)
	)
	assert_true(result.crit)
	assert_eq(result.amount, 111)


func test_normal_crit_chance_is_one_sixteenth() -> void:
	# 0.1 is above 1/16, so no crit for an ordinary move.
	var result: DamageResult = Damage.compute(
		_attacker(), _defender(), _move({}), _chart(), _rng(0.1, 100)
	)
	assert_false(result.crit)


func test_high_crit_chance_is_one_quarter() -> void:
	# 0.1 is below 1/4, so a high_crit move crits: 111.
	var move: MoveData = _move({"effect": {"high_crit": true}})
	var result: DamageResult = Damage.compute(
		_attacker(), _defender(), move, _chart(), _rng(0.1, 100)
	)
	assert_true(result.crit)
	assert_eq(result.amount, 111)


func test_miss_when_roll_is_above_accuracy() -> void:
	# Accuracy 1 and roll 0.5 (50 >= 1) misses, which deals no damage.
	var move: MoveData = _move({"accuracy": 1})
	var result: DamageResult = Damage.compute(
		_attacker(), _defender(), move, _chart(), _rng(0.5, 100)
	)
	assert_true(result.missed)
	assert_eq(result.amount, 0)


func test_status_move_deals_no_damage() -> void:
	var move: MoveData = _move({"category": "status", "power": null, "accuracy": 100})
	var result: DamageResult = Damage.compute(
		_attacker(), _defender(), move, _chart(), _rng(0.5, 100)
	)
	assert_eq(result.amount, 0)
	assert_false(result.missed)


func test_fixed_damage_level_uses_attacker_level() -> void:
	var move: MoveData = _move(
		{"category": "physical", "power": null, "effect": {"fixed_damage": "level"}}
	)
	var result: DamageResult = Damage.compute(
		_attacker(50), _defender(), move, _chart(), _rng(0.5, 100)
	)
	assert_eq(result.amount, 50)


func test_fixed_damage_is_zero_against_immunity() -> void:
	var move: MoveData = _move(
		{"type": "electric", "category": "physical", "power": null, "effect": {"fixed_damage": 20}}
	)
	var types: Array[String] = ["ground"]
	var result: DamageResult = Damage.compute(
		_attacker(), _defender(types), move, _chart(), _rng(0.5, 100)
	)
	assert_eq(result.amount, 0)
	assert_almost_eq(result.effectiveness, 0.0, 0.0001)


func test_immunity_deals_zero_damage() -> void:
	var move: MoveData = _move({"type": "electric"})
	var types: Array[String] = ["ground"]
	var result: DamageResult = Damage.compute(
		_attacker(), _defender(types), move, _chart(), _rng(0.5, 100)
	)
	assert_eq(result.amount, 0)


func test_minimum_one_damage_when_effective() -> void:
	# Level 2, spa 1, Sp.Def 255, power 1, electric into water (0.5), no STAB.
	# base = 2, raw = 2 * 0.5 * 0.85 = 0.85, floored to 0, then raised to the minimum of 1.
	var move: MoveData = _move({"type": "electric", "power": 1})
	var attacker_types: Array[String] = ["fire"]
	var attacker: CombatantView = _attacker(2, attacker_types)
	attacker.stats["spa"] = 1
	var water: Array[String] = ["water"]
	var result: DamageResult = Damage.compute(
		attacker, _defender(water, 255), move, _chart(), _rng(0.5, 85)
	)
	assert_eq(result.amount, 1)


func test_stab_only_for_the_users_own_type() -> void:
	# Normal user with a fire move: no STAB, so 37 with a full roll.
	var normal_types: Array[String] = ["normal"]
	var result: DamageResult = Damage.compute(
		_attacker(50, normal_types), _defender(), _move({}), _chart(), _rng(0.5, 100)
	)
	assert_eq(result.amount, 37)


func test_stage_multiplier_formula() -> void:
	assert_almost_eq(Damage.stage_mult(0), 1.0, 0.0001)
	assert_almost_eq(Damage.stage_mult(1), 1.5, 0.0001)
	assert_almost_eq(Damage.stage_mult(-1), 2.0 / 3.0, 0.0001)
	assert_almost_eq(Damage.stage_mult(6), 4.0, 0.0001)
	assert_almost_eq(Damage.stage_mult(-6), 0.25, 0.0001)


func test_seeded_misses_follow_accuracy() -> void:
	var rng := Rng.new(1234)
	var move: MoveData = _move({"accuracy": 1})
	var misses: int = 0
	for i: int in 2000:
		if Damage.compute(_attacker(), _defender(), move, _chart(), rng).missed:
			misses += 1
	assert_gt(misses, 1900, "accuracy 1 should miss about 99% of the time")


func test_null_accuracy_never_misses() -> void:
	var rng := Rng.new(1234)
	var move: MoveData = _move({"accuracy": null})
	var misses: int = 0
	for i: int in 500:
		if Damage.compute(_attacker(), _defender(), move, _chart(), rng).missed:
			misses += 1
	assert_eq(misses, 0)


func test_seeded_crit_rate_is_about_one_in_sixteen() -> void:
	var rng := Rng.new(1234)
	var crits: int = 0
	for i: int in 1600:
		if Damage.compute(_attacker(), _defender(), _move({}), _chart(), rng).crit:
			crits += 1
	assert_between(crits, 60, 140, "1600 rolls at 1/16 should give about 100 crits")


func test_same_seed_gives_same_damage_sequence() -> void:
	var first := Rng.new(99)
	var second := Rng.new(99)
	var a: Array[int] = []
	var b: Array[int] = []
	for i: int in 50:
		a.append(Damage.compute(_attacker(), _defender(), _move({}), _chart(), first).amount)
		b.append(Damage.compute(_attacker(), _defender(), _move({}), _chart(), second).amount)
	assert_eq(a, b)
