extends GutTest
## Unit tests for Settings: defaults, save/load round-trip, corrupt and partial files.

const SETTINGS_SCRIPT: GDScript = preload("res://game/settings.gd")
const TMP_FILE: String = "test_settings_tmp.json"
const TMP_PATH: String = "user://test_settings_tmp.json"


func before_each() -> void:
	_remove_tmp()


func after_each() -> void:
	_remove_tmp()


func _remove_tmp() -> void:
	var dir: DirAccess = DirAccess.open("user://")
	if dir != null and dir.file_exists(TMP_FILE):
		dir.remove(TMP_FILE)


func _write_text(text: String) -> void:
	var file: FileAccess = FileAccess.open(TMP_PATH, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _new_settings(path: String) -> Node:
	var settings: Node = autofree(SETTINGS_SCRIPT.new())
	settings.set_path_for_tests(path)
	return settings


func test_defaults_when_no_file() -> void:
	var settings: Node = _new_settings(TMP_PATH)
	settings.load_settings()
	assert_eq(settings.view_radius, 4, "view_radius default")
	assert_eq(settings.fullscreen, false, "fullscreen default")
	assert_almost_eq(settings.mouse_sensitivity, 0.002, 0.0000001, "mouse_sensitivity default")


func test_save_load_round_trip() -> void:
	var first: Node = _new_settings(TMP_PATH)
	first.view_radius = 7
	first.fullscreen = true
	first.mouse_sensitivity = 0.0045
	assert_true(first.save_settings(), "save_settings reports success")

	var second: Node = _new_settings(TMP_PATH)
	second.load_settings()
	assert_eq(second.view_radius, 7, "view_radius round-trip")
	assert_eq(second.fullscreen, true, "fullscreen round-trip")
	assert_almost_eq(second.mouse_sensitivity, 0.0045, 0.0000001, "mouse_sensitivity round-trip")


func test_corrupt_json_falls_back_to_defaults() -> void:
	_write_text("{ this is not json")
	var settings: Node = _new_settings(TMP_PATH)
	settings.load_settings()
	assert_eq(settings.view_radius, 4, "view_radius falls back")
	assert_eq(settings.fullscreen, false, "fullscreen falls back")
	assert_almost_eq(settings.mouse_sensitivity, 0.002, 0.0000001, "sensitivity falls back")


func test_missing_keys_fall_back_per_key() -> void:
	_write_text('{"view_radius": 7}')
	var settings: Node = _new_settings(TMP_PATH)
	settings.load_settings()
	assert_eq(settings.view_radius, 7, "present key is read")
	assert_eq(settings.fullscreen, false, "missing fullscreen uses default")
	assert_almost_eq(
		settings.mouse_sensitivity, 0.002, 0.0000001, "missing sensitivity uses default"
	)


func test_wrong_types_fall_back_to_defaults() -> void:
	_write_text('{"view_radius": "big", "fullscreen": 1, "mouse_sensitivity": "fast"}')
	var settings: Node = _new_settings(TMP_PATH)
	settings.load_settings()
	assert_eq(settings.view_radius, 4, "string view_radius uses default")
	assert_eq(settings.fullscreen, false, "numeric fullscreen uses default")
	assert_almost_eq(
		settings.mouse_sensitivity, 0.002, 0.0000001, "string sensitivity uses default"
	)
