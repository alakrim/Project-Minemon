extends GutTest
## Contract: Lives has lives_left:int (default 3) and on_death() -> String ("respawn" or "permadeath").


func test_lives_has_int_count_defaulting_to_three() -> void:
	var lives := Lives.new()
	assert_typeof(lives.lives_left, TYPE_INT)
	assert_eq(lives.lives_left, 3)


func test_on_death_returns_string() -> void:
	var lives := Lives.new()
	assert_typeof(lives.on_death(), TYPE_STRING)
