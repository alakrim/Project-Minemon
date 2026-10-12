class_name DataValidator
extends RefCounted
## Checks the parsed data/ documents against the PLAN.md data contracts. Pure: parsed JSON in, errors out.
## Each error is one string: "<file>[<entry>].<field>: <problem>". Empty array means valid.

const TYPE_COUNT: int = 17
const CATEGORIES: PackedStringArray = ["physical", "special", "status"]
const ARCHETYPES: PackedStringArray = [
	"projectile", "beam", "melee_arc", "area_burst", "aura", "status_cloud"
]
const GROWTH_RATES: PackedStringArray = [
	"fast", "medium_fast", "medium_slow", "slow", "erratic", "fluctuating"
]
const TEMPERAMENTS: PackedStringArray = ["aggressive", "territorial", "skittish", "peaceful"]
const SIZE_CLASSES: PackedStringArray = ["tiny", "small", "medium", "large", "huge", "colossal"]
const BODY_PLANS: PackedStringArray = [
	"biped", "quadruped", "serpent", "avian", "blob", "insect", "fish", "other"
]
const ITEM_KINDS: PackedStringArray = ["ball", "medicine", "evo", "held", "key"]
const STAGE_KEYS: PackedStringArray = ["atk", "def", "spa", "spd", "spe", "acc", "eva"]
const BASE_STAT_KEYS: PackedStringArray = ["hp", "atk", "def", "spa", "spd", "spe"]
const STATUSES: PackedStringArray = ["sleep", "freeze", "paralysis", "burn", "poison"]
const TARGETS: PackedStringArray = ["self", "target"]
const TIMES_OF_DAY: PackedStringArray = ["morning", "day", "night"]
const STAT_RELATIONS: PackedStringArray = ["atk>def", "atk<def", "atk=def"]
const EVO_CONDITION_KEYS: PackedStringArray = [
	"min_level", "item", "held_item", "time_of_day", "min_bond", "stat_relation", "trade"
]
const MOVE_EFFECT_KEYS: PackedStringArray = [
	"status",
	"status_chance",
	"stat_changes",
	"fixed_damage",
	"ohko",
	"hits",
	"drain_frac",
	"recoil_frac",
	"recharge",
	"flinch_chance",
	"high_crit",
	"heal_frac",
	"weather"
]
const CHART_VALUES: Array = [0.0, 0.5, 2.0]


## Returns every problem found, across types, items, moves and species.
static func validate(
	types_doc: Dictionary, items_doc: Dictionary, moves_doc: Dictionary, species_doc: Array
) -> Array[String]:
	var errors: Array[String] = []
	var known_types: Array[String] = _check_types(types_doc, errors)
	_check_items(items_doc, errors)
	_check_moves(moves_doc, known_types, errors)
	_check_species(species_doc, known_types, moves_doc, errors)
	return errors


static func _check_types(doc: Dictionary, errors: Array[String]) -> Array[String]:
	var names: Array[String] = []
	var raw: Variant = doc.get("types", null)
	if typeof(raw) != TYPE_ARRAY:
		_err(errors, "types.json.types", "must be an array")
	else:
		var source: Array = raw
		for name_value: Variant in source:
			names.append(str(name_value))
	if names.size() != TYPE_COUNT:
		_err(errors, "types.json.types", "needs %d names, got %d" % [TYPE_COUNT, names.size()])
	var chart: Variant = doc.get("chart", null)
	if typeof(chart) != TYPE_DICTIONARY:
		_err(errors, "types.json.chart", "must be an object")
		return names
	var chart_doc: Dictionary = chart
	for atk: Variant in chart_doc:
		var row_loc: String = "types.json.chart[%s]" % str(atk)
		if not names.has(str(atk)):
			_err(errors, row_loc, "unknown attacking type")
		var row: Variant = chart_doc[atk]
		if typeof(row) != TYPE_DICTIONARY:
			_err(errors, row_loc, "must be an object")
			continue
		var row_doc: Dictionary = row
		for dfn: Variant in row_doc:
			var loc: String = "%s[%s]" % [row_loc, str(dfn)]
			if not names.has(str(dfn)):
				_err(errors, loc, "unknown defending type")
			var mult: Variant = row_doc[dfn]
			if not _is_number(mult) or not CHART_VALUES.has(float(mult)):
				_err(errors, loc, "%s not in 0, 0.5, 2" % JSON.stringify(mult))
	return names


static func _check_items(items: Dictionary, errors: Array[String]) -> void:
	for item_id: Variant in items:
		var loc: String = "items.json[%s]" % str(item_id)
		var raw: Variant = items[item_id]
		if typeof(raw) != TYPE_DICTIONARY:
			_err(errors, loc, "must be an object")
			continue
		var entry: Dictionary = raw
		if _present(entry, "name", loc, errors):
			_text(errors, loc + ".name", entry["name"])
		if _present(entry, "kind", loc, errors):
			_enum(errors, loc + ".kind", entry["kind"], ITEM_KINDS)
		var kind: String = str(entry.get("kind", ""))
		if kind == "ball" or entry.has("catch_mult"):
			if _present(entry, "catch_mult", loc, errors):
				var mult: Variant = entry["catch_mult"]
				if not _is_number(mult) or float(mult) <= 0.0:
					_err(
						errors,
						loc + ".catch_mult",
						"%s must be a number above 0" % JSON.stringify(mult)
					)
		if entry.has("heal"):
			_int_range(errors, loc + ".heal", entry["heal"], 0, 9999)
		if _present(entry, "price", loc, errors):
			_int_range(errors, loc + ".price", entry["price"], 0, 999999)


static func _check_moves(
	moves: Dictionary, known_types: Array[String], errors: Array[String]
) -> void:
	for move_id: Variant in moves:
		var loc: String = "moves.json[%s]" % str(move_id)
		var raw: Variant = moves[move_id]
		if typeof(raw) != TYPE_DICTIONARY:
			_err(errors, loc, "must be an object")
			continue
		var move: Dictionary = raw
		if _present(move, "name", loc, errors):
			_text(errors, loc + ".name", move["name"])
		if _present(move, "type", loc, errors):
			_enum(errors, loc + ".type", move["type"], PackedStringArray(known_types))
		if _present(move, "category", loc, errors):
			_enum(errors, loc + ".category", move["category"], CATEGORIES)
		if _present(move, "power", loc, errors) and move["power"] != null:
			_int_range(errors, loc + ".power", move["power"], 1, 250)
		if _present(move, "accuracy", loc, errors) and move["accuracy"] != null:
			_int_range(errors, loc + ".accuracy", move["accuracy"], 1, 100)
		if _present(move, "pp", loc, errors):
			_int_range(errors, loc + ".pp", move["pp"], 1, 64)
		if _present(move, "priority", loc, errors):
			_int_range(errors, loc + ".priority", move["priority"], -7, 7)
		if _present(move, "archetype", loc, errors):
			_enum(errors, loc + ".archetype", move["archetype"], ARCHETYPES)
		for field: String in ["range_m", "cast_s", "cooldown_s"]:
			if _present(move, field, loc, errors):
				_non_negative(errors, loc + "." + field, move[field])
		if _present(move, "effect", loc, errors):
			var effect: Variant = move["effect"]
			if typeof(effect) != TYPE_DICTIONARY:
				_err(errors, loc + ".effect", "must be an object")
			else:
				var effect_doc: Dictionary = effect
				_check_effect(effect_doc, loc + ".effect", errors)


static func _check_effect(effect: Dictionary, loc: String, errors: Array[String]) -> void:
	for key: Variant in effect:
		var field: String = str(key)
		var floc: String = loc + "." + field
		var value: Variant = effect[key]
		if not MOVE_EFFECT_KEYS.has(field):
			_err(errors, floc, "unknown effect key")
		elif field == "status":
			_enum(errors, floc, value, STATUSES)
		elif field == "status_chance" or field == "flinch_chance":
			_int_range(errors, floc, value, 1, 100)
		elif field == "stat_changes":
			_check_stat_changes(value, floc, errors)
		elif field == "fixed_damage":
			if typeof(value) == TYPE_STRING:
				_enum(errors, floc, value, PackedStringArray(["level"]))
			else:
				_int_range(errors, floc, value, 0, 999)
		elif field == "ohko" or field == "recharge" or field == "high_crit":
			_bool(errors, floc, value)
		elif field == "hits":
			_check_hits(value, floc, errors)
		elif field == "drain_frac" or field == "recoil_frac" or field == "heal_frac":
			if not _is_number(value) or float(value) < 0.0 or float(value) > 1.0:
				_err(errors, floc, "%s not in 0..1" % JSON.stringify(value))
		elif field == "weather":
			_text(errors, floc, value)


static func _check_stat_changes(value: Variant, loc: String, errors: Array[String]) -> void:
	if typeof(value) != TYPE_ARRAY:
		_err(errors, loc, "must be an array")
		return
	var changes: Array = value
	for i: int in changes.size():
		var eloc: String = "%s[%d]" % [loc, i]
		var change: Variant = changes[i]
		if typeof(change) != TYPE_DICTIONARY:
			_err(errors, eloc, "must be an object")
			continue
		var doc: Dictionary = change
		if _present(doc, "stat", eloc, errors):
			_enum(errors, eloc + ".stat", doc["stat"], STAGE_KEYS)
		if _present(doc, "stages", eloc, errors):
			_int_range(errors, eloc + ".stages", doc["stages"], -6, 6)
		if _present(doc, "target", eloc, errors):
			_enum(errors, eloc + ".target", doc["target"], TARGETS)


static func _check_hits(value: Variant, loc: String, errors: Array[String]) -> void:
	if typeof(value) != TYPE_ARRAY or (value as Array).size() != 2:
		_err(errors, loc, "must be [min, max]")
		return
	var pair: Array = value
	_int_range(errors, loc + "[0]", pair[0], 1, 10)
	_int_range(errors, loc + "[1]", pair[1], 1, 10)
	if _is_int(pair[0]) and _is_int(pair[1]) and int(pair[0]) > int(pair[1]):
		_err(errors, loc, "min above max")


static func _check_species(
	species: Array, known_types: Array[String], moves: Dictionary, errors: Array[String]
) -> void:
	var ids: Array[int] = []
	for raw: Variant in species:
		if typeof(raw) == TYPE_DICTIONARY and _is_int((raw as Dictionary).get("id")):
			ids.append(int((raw as Dictionary)["id"]))
	var seen: Array[int] = []
	for i: int in species.size():
		var raw: Variant = species[i]
		if typeof(raw) != TYPE_DICTIONARY:
			_err(errors, "species.json[%d]" % i, "must be an object")
			continue
		var entry: Dictionary = raw
		var key: String = str(i)
		if _is_int(entry.get("id")):
			key = str(int(entry["id"]))
		var loc: String = "species.json[%s]" % key
		if _present(entry, "id", loc, errors):
			if not _is_int(entry["id"]) or int(entry["id"]) < 1:
				_err(
					errors,
					loc + ".id",
					"%s must be an integer of 1 or more" % JSON.stringify(entry["id"])
				)
			elif seen.has(int(entry["id"])):
				_err(errors, loc + ".id", "duplicate id")
			else:
				seen.append(int(entry["id"]))
		_check_species_fields(entry, loc, known_types, errors)
		_check_learnset(entry, loc, moves, errors)
		_check_evolutions(entry, loc, ids, errors)


static func _check_species_fields(
	entry: Dictionary, loc: String, known_types: Array[String], errors: Array[String]
) -> void:
	if _present(entry, "name", loc, errors):
		_text(errors, loc + ".name", entry["name"])
	if _present(entry, "types", loc, errors):
		var types: Variant = entry["types"]
		if (
			typeof(types) != TYPE_ARRAY
			or (types as Array).size() < 1
			or (types as Array).size() > 2
		):
			_err(errors, loc + ".types", "needs 1 to 2 types, got %s" % JSON.stringify(types))
		else:
			var type_list: Array = types
			for type_value: Variant in type_list:
				_enum(errors, loc + ".types", type_value, PackedStringArray(known_types))
	if _present(entry, "base_stats", loc, errors):
		_check_base_stats(entry["base_stats"], loc + ".base_stats", errors)
	if _present(entry, "catch_rate", loc, errors):
		_int_range(errors, loc + ".catch_rate", entry["catch_rate"], 3, 255)
	if _present(entry, "growth_rate", loc, errors):
		_enum(errors, loc + ".growth_rate", entry["growth_rate"], GROWTH_RATES)
	if _present(entry, "base_exp", loc, errors):
		_int_range(errors, loc + ".base_exp", entry["base_exp"], 1, 1000)
	if _present(entry, "gender_ratio", loc, errors):
		_int_range(errors, loc + ".gender_ratio", entry["gender_ratio"], -1, 8)
	if _present(entry, "temperament", loc, errors):
		_enum(errors, loc + ".temperament", entry["temperament"], TEMPERAMENTS)
	if _present(entry, "size_class", loc, errors):
		_enum(errors, loc + ".size_class", entry["size_class"], SIZE_CLASSES)
	if _present(entry, "body_plan", loc, errors):
		_enum(errors, loc + ".body_plan", entry["body_plan"], BODY_PLANS)
	if _present(entry, "habitats", loc, errors):
		var habitats: Variant = entry["habitats"]
		if typeof(habitats) != TYPE_ARRAY or (habitats as Array).is_empty():
			_err(errors, loc + ".habitats", "needs at least one habitat")
		else:
			var habitat_list: Array = habitats
			for habitat: Variant in habitat_list:
				_text(errors, loc + ".habitats", habitat)
	if _present(entry, "eldritch", loc, errors):
		_bool(errors, loc + ".eldritch", entry["eldritch"])


static func _check_base_stats(value: Variant, loc: String, errors: Array[String]) -> void:
	if typeof(value) != TYPE_DICTIONARY:
		_err(errors, loc, "must be an object")
		return
	var stats: Dictionary = value
	for stat: String in BASE_STAT_KEYS:
		if not stats.has(stat):
			_err(errors, loc + "." + stat, "missing")
		else:
			_int_range(errors, loc + "." + stat, stats[stat], 1, 255)


static func _check_learnset(
	entry: Dictionary, loc: String, moves: Dictionary, errors: Array[String]
) -> void:
	if not _present(entry, "learnset", loc, errors):
		return
	var learnset: Variant = entry["learnset"]
	if typeof(learnset) != TYPE_ARRAY:
		_err(errors, loc + ".learnset", "must be an array")
		return
	var rows: Array = learnset
	for i: int in rows.size():
		var row_loc: String = "%s.learnset[%d]" % [loc, i]
		var row: Variant = rows[i]
		if typeof(row) != TYPE_DICTIONARY:
			_err(errors, row_loc, "must be an object")
			continue
		var doc: Dictionary = row
		if _present(doc, "level", row_loc, errors):
			_int_range(errors, row_loc + ".level", doc["level"], 1, 100)
		if _present(doc, "move", row_loc, errors):
			var move_id: Variant = doc["move"]
			if typeof(move_id) != TYPE_STRING or not moves.has(move_id):
				_err(errors, row_loc + ".move", "%s is not in moves.json" % JSON.stringify(move_id))


static func _check_evolutions(
	entry: Dictionary, loc: String, ids: Array[int], errors: Array[String]
) -> void:
	if not _present(entry, "evolutions", loc, errors):
		return
	var evolutions: Variant = entry["evolutions"]
	if typeof(evolutions) != TYPE_ARRAY:
		_err(errors, loc + ".evolutions", "must be an array")
		return
	var rows: Array = evolutions
	for i: int in rows.size():
		var row_loc: String = "%s.evolutions[%d]" % [loc, i]
		var row: Variant = rows[i]
		if typeof(row) != TYPE_DICTIONARY:
			_err(errors, row_loc, "must be an object")
			continue
		var doc: Dictionary = row
		if _present(doc, "to", row_loc, errors):
			var target: Variant = doc["to"]
			if not _is_int(target) or not ids.has(int(target)):
				_err(
					errors,
					row_loc + ".to",
					"%s is not a species id in species.json" % JSON.stringify(target)
				)
		if _present(doc, "conditions", row_loc, errors):
			_check_conditions(doc["conditions"], row_loc + ".conditions", errors)


static func _check_conditions(value: Variant, loc: String, errors: Array[String]) -> void:
	if typeof(value) != TYPE_DICTIONARY:
		_err(errors, loc, "must be an object")
		return
	var conditions: Dictionary = value
	for key: Variant in conditions:
		var field: String = str(key)
		var floc: String = loc + "." + field
		var cond: Variant = conditions[key]
		if not EVO_CONDITION_KEYS.has(field):
			_err(errors, floc, "unknown condition")
		elif field == "min_level":
			_int_range(errors, floc, cond, 1, 100)
		elif field == "item" or field == "held_item":
			_text(errors, floc, cond)
		elif field == "time_of_day":
			_enum(errors, floc, cond, TIMES_OF_DAY)
		elif field == "min_bond":
			_int_range(errors, floc, cond, 0, 255)
		elif field == "stat_relation":
			_enum(errors, floc, cond, STAT_RELATIONS)
		elif field == "trade":
			_bool(errors, floc, cond)


static func _present(doc: Dictionary, key: String, loc: String, errors: Array[String]) -> bool:
	if doc.has(key):
		return true
	_err(errors, loc + "." + key, "missing")
	return false


static func _err(errors: Array[String], loc: String, problem: String) -> void:
	errors.append("%s: %s" % [loc, problem])


static func _is_int(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	return typeof(value) == TYPE_FLOAT and float(value) == floorf(float(value))


static func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT


static func _int_range(
	errors: Array[String], loc: String, value: Variant, low: int, high: int
) -> void:
	if not _is_int(value) or float(value) < float(low) or float(value) > float(high):
		_err(errors, loc, "%s not in %d..%d" % [JSON.stringify(value), low, high])


static func _non_negative(errors: Array[String], loc: String, value: Variant) -> void:
	if not _is_number(value) or float(value) < 0.0:
		_err(errors, loc, "%s must be a number of 0 or more" % JSON.stringify(value))


static func _text(errors: Array[String], loc: String, value: Variant) -> void:
	if typeof(value) != TYPE_STRING or (value as String).is_empty():
		_err(errors, loc, "%s must be a non-empty string" % JSON.stringify(value))


static func _bool(errors: Array[String], loc: String, value: Variant) -> void:
	if typeof(value) != TYPE_BOOL:
		_err(errors, loc, "%s must be true or false" % JSON.stringify(value))


static func _enum(
	errors: Array[String], loc: String, value: Variant, options: PackedStringArray
) -> void:
	if typeof(value) != TYPE_STRING or not options.has(str(value)):
		_err(errors, loc, "%s not in %s" % [JSON.stringify(value), ", ".join(options)])
