class_name TypeChart
extends RefCounted
## Type effectiveness lookup. Built from the "chart" in data/types.json; only non-1.0 entries are stored.

var _chart: Dictionary = {}


func _init(chart: Dictionary) -> void:
	_chart = chart.duplicate(true)


## Product of the attacking type's multiplier against each defending type (dual types multiply).
func multiplier(atk: String, defs: Array[String]) -> float:
	var result: float = 1.0
	var row: Dictionary = _chart.get(atk, {})
	for def_type: String in defs:
		result *= float(row.get(def_type, 1.0))
	return result
