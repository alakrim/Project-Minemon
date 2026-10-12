class_name BlockRegistry
extends RefCounted
## Block properties loaded from data/blocks.json. Plain data, safe to read on worker threads.

const BLOCK_COUNT: int = 256

var _colors: PackedColorArray = PackedColorArray()
var _solid: PackedByteArray = PackedByteArray()
var _transparent: PackedByteArray = PackedByteArray()


func _init() -> void:
	_colors.resize(BLOCK_COUNT)
	_colors.fill(Color.MAGENTA)
	_solid.resize(BLOCK_COUNT)
	_transparent.resize(BLOCK_COUNT)


## Loads the block table. Returns the list of errors; an empty array means success.
func load_from(path: String) -> Array[String]:
	var errors: Array[String] = []
	if not FileAccess.file_exists(path):
		errors.append("block file missing: %s" % path)
		return errors
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_ARRAY:
		errors.append("block file is not a JSON array: %s" % path)
		return errors
	var entries: Array = parsed as Array
	for entry: Variant in entries:
		if typeof(entry) != TYPE_DICTIONARY:
			errors.append("block entry is not an object")
			continue
		_load_entry(entry as Dictionary, errors)
	return errors


func color(id: int) -> Color:
	if not _in_range(id):
		return Color.MAGENTA
	return _colors[id]


func is_solid(id: int) -> bool:
	return _in_range(id) and _solid[id] == 1


func is_transparent(id: int) -> bool:
	return _in_range(id) and _transparent[id] == 1


func _in_range(id: int) -> bool:
	return id >= 0 and id < BLOCK_COUNT


func _load_entry(entry: Dictionary, errors: Array[String]) -> void:
	var id: int = int(entry.get("id", -1))
	if not _in_range(id):
		errors.append("block id out of range: %d" % id)
		return
	_colors[id] = Color.html(str(entry.get("color", "#ff00ff")))
	_solid[id] = 1 if bool(entry.get("solid", false)) else 0
	_transparent[id] = 1 if bool(entry.get("transparent", false)) else 0
