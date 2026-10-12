class_name Stats
extends RefCounted
## Stat calculation: Gen-2-style base formula with the bond bonus (bond replaces stat experience, D-017).

const KEYS: PackedStringArray = ["hp", "atk", "def", "spa", "spd", "spe"]


## base: species base stats. ivs: 0-15 per stat. bond: 0-255, adds floor(bond/25)% to every stat.
static func calc(base: Dictionary, level: int, ivs: Dictionary, bond: int) -> Dictionary:
	var out: Dictionary = {}
	var bonus_percent: int = 100 + clampi(bond, 0, 255) / 25
	for key: String in KEYS:
		var base_value: int = int(base.get(key, 0))
		var iv: int = int(ivs.get(key, 0))
		var core: int = (2 * base_value + iv) * level / 100
		var value: int = core + level + 10 if key == "hp" else core + 5
		out[key] = value * bonus_percent / 100
	return out
