class_name Damage
extends RefCounted
## Gen-2-style hit resolution: accuracy roll, base formula, STAB, type chart, crit and random spread.
## Rolls happen in a fixed order (accuracy, crit, random) so a seeded Rng gives repeatable results.

const CRIT_CHANCE: float = 1.0 / 16.0
const HIGH_CRIT_CHANCE: float = 1.0 / 4.0
const CRIT_MULT: float = 2.0
const STAB_MULT: float = 1.5
const RANDOM_MIN: int = 85
const RANDOM_MAX: int = 100


## Stage multiplier: stage s gives (2 + max(s,0)) / (2 + max(-s,0)), with s clamped to -6..6.
static func stage_mult(stage: int) -> float:
	var s: int = clampi(stage, -6, 6)
	return float(2 + maxi(s, 0)) / float(2 + maxi(-s, 0))


static func compute(
	atk: CombatantView, target: CombatantView, move: MoveData, chart: TypeChart, rng: Rng
) -> DamageResult:
	var result := DamageResult.new()
	result.effectiveness = chart.multiplier(move.type, target.types)
	if move.has_accuracy():
		var acc_stage: int = int(atk.stages.get("acc", 0))
		var eva_stage: int = int(target.stages.get("eva", 0))
		var hit_chance: float = float(move.accuracy) * stage_mult(acc_stage) / stage_mult(eva_stage)
		if rng.randf() * 100.0 >= hit_chance:
			result.missed = true
			return result
	if move.is_status():
		return result
	if move.has_fixed_damage():
		if result.effectiveness > 0.0:
			result.amount = _fixed_amount(move, atk)
		return result
	if not move.has_power():
		return result

	var physical: bool = move.category == "physical"
	var atk_key: String = "atk" if physical else "spa"
	var def_key: String = "def" if physical else "spd"
	var attack: float = floorf(
		float(atk.stats.get(atk_key, 1)) * stage_mult(int(atk.stages.get(atk_key, 0)))
	)
	var defence: float = floorf(
		float(target.stats.get(def_key, 1)) * stage_mult(int(target.stages.get(def_key, 0)))
	)
	defence = maxf(defence, 1.0)
	var level_term: int = 2 * atk.level / 5 + 2
	var base: int = floori(float(level_term) * float(move.power) * attack / defence) / 50 + 2

	result.crit = rng.randf() < (HIGH_CRIT_CHANCE if move.is_high_crit() else CRIT_CHANCE)
	var roll: float = float(rng.randi_range(RANDOM_MIN, RANDOM_MAX)) / 100.0
	var stab: float = STAB_MULT if atk.types.has(move.type) else 1.0
	var crit_mult: float = CRIT_MULT if result.crit else 1.0
	if result.effectiveness <= 0.0:
		return result
	var raw: float = float(base) * stab * result.effectiveness * crit_mult * roll
	result.amount = maxi(1, floori(raw))
	return result


static func _fixed_amount(move: MoveData, atk: CombatantView) -> int:
	var raw: Variant = move.effect["fixed_damage"]
	if raw is String:
		return atk.level
	return int(raw)
