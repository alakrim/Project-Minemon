extends Node
## Autoload "Data". Loads the JSON content in data/, validates it and serves typed records.
## Nothing is served unless the whole load validates: a failed load leaves the registry empty.

var _species: Dictionary = {}
var _moves: Dictionary = {}
var _items: Dictionary = {}
var _chart: TypeChart = TypeChart.new({})


func _ready() -> void:
	for error: String in load_all():
		push_error(error)


## Loads and validates every data file in `dir`. Returns the errors; an empty array means OK.
func load_all(dir: String = "res://data") -> Array[String]:
	_clear()
	var errors: Array[String] = []
	var types_doc: Variant = _read_json(dir, "types.json", errors)
	var items_doc: Variant = _read_json(dir, "items.json", errors)
	var moves_doc: Variant = _read_json(dir, "moves.json", errors)
	var species_doc: Variant = _read_json(dir, "species.json", errors)
	if not errors.is_empty():
		return errors
	if not _roots_ok(types_doc, items_doc, moves_doc, species_doc, errors):
		return errors
	var validation: Array[String] = DataValidator.validate(
		types_doc, items_doc, moves_doc, species_doc
	)
	if not validation.is_empty():
		return validation
	_build(types_doc, items_doc, moves_doc, species_doc)
	return errors


func species(id: int) -> SpeciesData:
	return _species.get(id)


func move(id: String) -> MoveData:
	return _moves.get(id)


func item(id: String) -> ItemData:
	return _items.get(id)


func chart() -> TypeChart:
	return _chart


func all_species_ids() -> Array[int]:
	var ids: Array[int] = []
	for id: Variant in _species.keys():
		ids.append(int(id))
	ids.sort()
	return ids


func _clear() -> void:
	_species.clear()
	_moves.clear()
	_items.clear()
	_chart = TypeChart.new({})


func _read_json(dir: String, file: String, errors: Array[String]) -> Variant:
	var path: String = dir.path_join(file)
	if not FileAccess.file_exists(path):
		errors.append("%s: file not found" % file)
		return null
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed == null:
		errors.append("%s: not valid JSON" % file)
	return parsed


func _roots_ok(
	types_doc: Variant,
	items_doc: Variant,
	moves_doc: Variant,
	species_doc: Variant,
	errors: Array[String]
) -> bool:
	var ok: bool = true
	for pair: Array in [
		["types.json", types_doc], ["items.json", items_doc], ["moves.json", moves_doc]
	]:
		if typeof(pair[1]) != TYPE_DICTIONARY:
			errors.append("%s: root must be an object" % pair[0])
			ok = false
	if typeof(species_doc) != TYPE_ARRAY:
		errors.append("species.json: root must be an array")
		ok = false
	return ok


func _build(
	types_doc: Variant, items_doc: Variant, moves_doc: Variant, species_doc: Variant
) -> void:
	var types_dict: Dictionary = types_doc
	_chart = TypeChart.new(types_dict.get("chart", {}))
	var items_dict: Dictionary = items_doc
	for item_id: Variant in items_dict.keys():
		var entry: Dictionary = (items_dict[item_id] as Dictionary).duplicate()
		entry["id"] = str(item_id)
		_items[str(item_id)] = ItemData.from_dict(entry)
	var moves_dict: Dictionary = moves_doc
	for move_id: Variant in moves_dict.keys():
		var entry: Dictionary = (moves_dict[move_id] as Dictionary).duplicate()
		entry["id"] = str(move_id)
		_moves[str(move_id)] = MoveData.from_dict(entry)
	var species_list: Array = species_doc
	for raw: Variant in species_list:
		var record: SpeciesData = SpeciesData.from_dict(raw)
		_species[record.id] = record
