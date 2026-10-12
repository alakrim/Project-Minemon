extends GutTest
## Unit tests for Chunk: index layout, get/set, and bounds.


func test_set_then_get_round_trips() -> void:
	var c := Chunk.new(Vector2i.ZERO)
	c.set_block(Vector3i(3, 10, 5), 3)
	assert_eq(c.get_block(Vector3i(3, 10, 5)), 3)


func test_index_layout_is_x_plus_z_times_16_plus_y_times_256() -> void:
	assert_eq(Chunk.index_of(1, 0, 0), 1)
	assert_eq(Chunk.index_of(0, 0, 1), 16)
	assert_eq(Chunk.index_of(0, 1, 0), 256)
	var c := Chunk.new(Vector2i.ZERO)
	c.set_block(Vector3i(2, 3, 4), 8)
	assert_eq(c.raw_blocks()[Chunk.index_of(2, 3, 4)], 8)


func test_out_of_range_get_returns_air() -> void:
	var c := Chunk.new(Vector2i.ZERO)
	assert_eq(c.get_block(Vector3i(-1, 0, 0)), 0)
	assert_eq(c.get_block(Vector3i(16, 0, 0)), 0)
	assert_eq(c.get_block(Vector3i(0, 128, 0)), 0)
	assert_eq(c.get_block(Vector3i(0, -1, 0)), 0)


func test_out_of_range_set_is_ignored() -> void:
	var c := Chunk.new(Vector2i.ZERO)
	c.set_block(Vector3i(16, 0, 0), 3)
	c.set_block(Vector3i(0, 0, -1), 3)
	c.set_block(Vector3i(0, 128, 0), 3)
	var nonzero: int = 0
	for value: int in c.raw_blocks():
		if value != 0:
			nonzero += 1
	assert_eq(c.raw_blocks().size(), Chunk.VOLUME)
	assert_eq(nonzero, 0, "out-of-range set must not write any block")


func test_top_y_tracks_highest_non_air_block() -> void:
	var c := Chunk.new(Vector2i.ZERO)
	assert_eq(c.top_y, -1, "an all-air column has top_y -1")
	c.set_block(Vector3i(0, 10, 0), 3)
	assert_eq(c.top_y, 10)
	c.set_block(Vector3i(0, 40, 0), 3)
	assert_eq(c.top_y, 40)
	c.set_block(Vector3i(0, 40, 0), 0)
	assert_eq(c.top_y, 10, "removing the top block must lower top_y")
	c.set_block(Vector3i(0, 10, 0), 0)
	assert_eq(c.top_y, -1)
