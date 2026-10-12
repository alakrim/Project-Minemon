class_name JsonValues
extends RefCounted
## Turns parsed JSON values (numbers arrive as floats) into typed GDScript values.


static func to_int_dict(raw: Variant) -> Dictionary:
	var out: Dictionary = {}
	if raw is Dictionary:
		var source: Dictionary = raw
		for key: Variant in source:
			out[str(key)] = int(source[key])
	return out


static func to_string_array(raw: Variant) -> Array[String]:
	var out: Array[String] = []
	if raw is Array:
		var source: Array = raw
		for item: Variant in source:
			out.append(str(item))
	return out


static func to_dict_array(raw: Variant) -> Array:
	var out: Array = []
	if raw is Array:
		var source: Array = raw
		for item: Variant in source:
			if item is Dictionary:
				var entry: Dictionary = item
				out.append(entry.duplicate(true))
	return out
