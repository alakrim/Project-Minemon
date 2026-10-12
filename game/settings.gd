extends Node
## Autoload "Settings". User settings, saved as JSON in user://settings.json.
## A missing or corrupt file, or missing or mistyped keys, fall back to the defaults.

const DEFAULT_PATH: String = "user://settings.json"
const DEFAULT_VIEW_RADIUS: int = 4
const MIN_VIEW_RADIUS: int = 1
const MAX_VIEW_RADIUS: int = 16
const DEFAULT_FULLSCREEN: bool = false
const DEFAULT_MOUSE_SENSITIVITY: float = 0.002

var view_radius: int = DEFAULT_VIEW_RADIUS
var fullscreen: bool = DEFAULT_FULLSCREEN
var mouse_sensitivity: float = DEFAULT_MOUSE_SENSITIVITY

var _path: String = DEFAULT_PATH


func _ready() -> void:
	load_settings()


func set_path_for_tests(p_path: String) -> void:
	_path = p_path


func load_settings() -> void:
	_reset_to_defaults()
	if not FileAccess.file_exists(_path):
		return
	var parser: JSON = JSON.new()
	if parser.parse(FileAccess.get_file_as_string(_path)) != OK:
		return
	if typeof(parser.data) != TYPE_DICTIONARY:
		return
	var data: Dictionary = parser.data
	view_radius = clampi(
		_read_int(data, "view_radius", DEFAULT_VIEW_RADIUS), MIN_VIEW_RADIUS, MAX_VIEW_RADIUS
	)
	fullscreen = _read_bool(data, "fullscreen", DEFAULT_FULLSCREEN)
	var sensitivity: float = _read_float(data, "mouse_sensitivity", DEFAULT_MOUSE_SENSITIVITY)
	mouse_sensitivity = sensitivity if sensitivity > 0.0 else DEFAULT_MOUSE_SENSITIVITY


func save_settings() -> bool:
	var data: Dictionary = {
		"view_radius": view_radius,
		"fullscreen": fullscreen,
		"mouse_sensitivity": mouse_sensitivity,
	}
	var file: FileAccess = FileAccess.open(_path, FileAccess.WRITE)
	if file == null:
		push_warning("Could not write settings to %s" % _path)
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	return true


func _reset_to_defaults() -> void:
	view_radius = DEFAULT_VIEW_RADIUS
	fullscreen = DEFAULT_FULLSCREEN
	mouse_sensitivity = DEFAULT_MOUSE_SENSITIVITY


func _read_int(data: Dictionary, key: String, fallback: int) -> int:
	var value: Variant = data.get(key, fallback)
	if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
		return int(value)
	return fallback


func _read_float(data: Dictionary, key: String, fallback: float) -> float:
	var value: Variant = data.get(key, fallback)
	if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
		return float(value)
	return fallback


func _read_bool(data: Dictionary, key: String, fallback: bool) -> bool:
	var value: Variant = data.get(key, fallback)
	if typeof(value) == TYPE_BOOL:
		return value
	return fallback
