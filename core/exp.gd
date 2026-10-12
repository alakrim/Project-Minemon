class_name Exp
extends RefCounted
## Experience: gain from a defeated species, and the Gen 1-2 level curves for the six growth rates.


## gain = floor(base_exp * L / 7 * (1 + bond / 510)).
static func gain(defeated: SpeciesData, defeated_level: int, bond: int) -> int:
	var bond_mult: float = 1.0 + float(clampi(bond, 0, 255)) / 510.0
	return floori(float(defeated.base_exp) * float(defeated_level) / 7.0 * bond_mult)


## Total experience needed to reach `level`. Level 1 is always 0.
static func exp_for_level(level: int, growth: String) -> int:
	var n: int = clampi(level, 1, 100)
	if n <= 1:
		return 0
	var n3: int = n * n * n
	var total: int = 0
	if growth == "fast":
		total = 4 * n3 / 5
	elif growth == "medium_fast":
		total = n3
	elif growth == "medium_slow":
		total = 6 * n3 / 5 - 15 * n * n + 100 * n - 140
	elif growth == "slow":
		total = 5 * n3 / 4
	elif growth == "erratic":
		total = _erratic(n)
	elif growth == "fluctuating":
		total = _fluctuating(n)
	return maxi(total, 0)


## Highest level whose total experience is <= total_exp, capped at 100.
static func level_for(total_exp: int, growth: String) -> int:
	var best: int = 1
	for lv: int in range(2, 101):
		if exp_for_level(lv, growth) <= total_exp:
			best = lv
		else:
			break
	return best


static func _erratic(n: int) -> int:
	var n3: int = n * n * n
	if n <= 50:
		return n3 * (100 - n) / 50
	if n <= 68:
		return n3 * (150 - n) / 100
	if n <= 98:
		return n3 * ((1911 - 10 * n) / 3) / 500
	return n3 * (160 - n) / 100


static func _fluctuating(n: int) -> int:
	var n3: int = n * n * n
	if n <= 15:
		return n3 * ((n + 1) / 3 + 24) / 50
	if n <= 35:
		return n3 * (n + 14) / 50
	return n3 * (n / 2 + 32) / 50
