class_name MoveData
extends RefCounted
## One move, built from one entry of data/moves.json.
## A null power or accuracy is stored as -1; use has_power() and has_accuracy().

var id: String = ""
var name: String = ""
var type: String = ""
var category: String = ""
var power: int = -1
var accuracy: int = -1
var pp: int = 0
var priority: int = 0
var archetype: String = ""
var range_m: float = 0.0
var cast_s: float = 0.0
var cooldown_s: float = 0.0
var effect: Dictionary = {}


static func from_dict(d: Dictionary) -> MoveData:
	var m := MoveData.new()
	m.id = str(d.get("id", ""))
	m.name = str(d.get("name", ""))
	m.type = str(d.get("type", ""))
	m.category = str(d.get("category", ""))
	m.power = _int_or_null(d.get("power"))
	m.accuracy = _int_or_null(d.get("accuracy"))
	m.pp = int(d.get("pp", 0))
	m.priority = int(d.get("priority", 0))
	m.archetype = str(d.get("archetype", ""))
	m.range_m = float(d.get("range_m", 0.0))
	m.cast_s = float(d.get("cast_s", 0.0))
	m.cooldown_s = float(d.get("cooldown_s", 0.0))
	var raw_effect: Variant = d.get("effect", {})
	if raw_effect is Dictionary:
		var effect_dict: Dictionary = raw_effect
		m.effect = effect_dict.duplicate(true)
	return m


func has_power() -> bool:
	return power >= 0


func has_accuracy() -> bool:
	return accuracy >= 0


func is_status() -> bool:
	return category == "status"


func has_fixed_damage() -> bool:
	return effect.has("fixed_damage")


func is_high_crit() -> bool:
	return effect.get("high_crit", false) == true


static func _int_or_null(value: Variant) -> int:
	if value == null:
		return -1
	return int(value)
