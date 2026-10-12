extends GutTest
## Unit tests for BlockRegistry: the data file loads and the flags are right.


func _registry() -> BlockRegistry:
	var reg := BlockRegistry.new()
	var errors: Array[String] = reg.load_from("res://data/blocks.json")
	assert_eq(errors.size(), 0, "blocks.json must load without errors")
	return reg


func test_air_is_transparent_and_not_solid() -> void:
	var reg := _registry()
	assert_true(reg.is_transparent(0))
	assert_false(reg.is_solid(0))


func test_stone_is_solid_and_opaque() -> void:
	var reg := _registry()
	assert_true(reg.is_solid(3))
	assert_false(reg.is_transparent(3))


func test_water_is_transparent_and_not_solid() -> void:
	var reg := _registry()
	assert_true(reg.is_transparent(5))
	assert_false(reg.is_solid(5))


func test_color_reads_the_hex_value() -> void:
	var reg := _registry()
	assert_eq(reg.color(3), Color.html("#7d7d7d"))


func test_missing_file_reports_an_error() -> void:
	var reg := BlockRegistry.new()
	var errors: Array[String] = reg.load_from("res://data/does_not_exist.json")
	assert_eq(errors.size(), 1)
