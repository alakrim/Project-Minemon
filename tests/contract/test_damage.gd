extends GutTest
## Contract: Damage.compute(atk, target, move, chart, rng) -> DamageResult; stage_mult -> float.


func test_compute_exists_and_returns_damage_result() -> void:
	var atk := CombatantView.new()
	var target := CombatantView.new()
	var move: MoveData = MoveData.from_dict({"type": "normal", "category": "status", "power": null})
	var result: DamageResult = Damage.compute(atk, target, move, TypeChart.new({}), Rng.new(1))
	assert_is(result, DamageResult)


func test_stage_mult_returns_float() -> void:
	assert_typeof(Damage.stage_mult(1), TYPE_FLOAT)
