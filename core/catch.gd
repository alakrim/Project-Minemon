class_name Catch
extends RefCounted
## Gen-style catch chance: a = (3*max - 2*cur) * catch_rate * ball / (3*max) * status.
## Chance = clamp(a/255, 0, 1). hp_frac stands in for cur/max.


static func status_mult(status: String) -> float:
	if status == "sleep" or status == "freeze":
		return 2.0
	if status == "paralysis" or status == "burn" or status == "poison":
		return 1.5
	return 1.0


static func chance(sp: SpeciesData, hp_frac: float, ball_mult: float, status: String) -> float:
	var frac: float = clampf(hp_frac, 0.0, 1.0)
	var a: float = (3.0 - 2.0 * frac) * float(sp.catch_rate) * ball_mult / 3.0 * status_mult(status)
	return clampf(a / 255.0, 0.0, 1.0)


static func roll(chance_value: float, rng: Rng) -> bool:
	return rng.randf() < chance_value
