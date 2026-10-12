extends GutTest
## Unit tests for Lives: three respawns, then a permanent death on the fourth.


func test_starts_with_three_lives() -> void:
	var lives := Lives.new()
	assert_eq(lives.lives_left, 3)


func test_first_three_deaths_respawn_and_count_down() -> void:
	var lives := Lives.new()
	assert_eq(lives.on_death(), "respawn")
	assert_eq(lives.lives_left, 2)
	assert_eq(lives.on_death(), "respawn")
	assert_eq(lives.lives_left, 1)
	assert_eq(lives.on_death(), "respawn")
	assert_eq(lives.lives_left, 0)


func test_fourth_death_is_permadeath_and_stays_so() -> void:
	var lives := Lives.new()
	for i: int in 3:
		lives.on_death()
	assert_eq(lives.on_death(), "permadeath")
	assert_eq(lives.on_death(), "permadeath")
	assert_eq(lives.lives_left, 0)
