extends GutTest
## Unit tests for TerrainGenerator: determinism, seed sensitivity, surface_height and top_y.

const SAMPLE_POINTS: Array[Vector2i] = [
	Vector2i(0, 0),
	Vector2i(3, 7),
	Vector2i(9, 2),
	Vector2i(12, 14),
	Vector2i(15, 15),
]


func _top_solid_y(reg: BlockRegistry, c: Chunk, x: int, z: int) -> int:
	for y: int in range(Chunk.HEIGHT - 1, -1, -1):
		if reg.is_solid(c.get_block(Vector3i(x, y, z))):
			return y
	return -1


func test_same_seed_and_position_give_identical_blocks() -> void:
	var a: PackedByteArray = TerrainGenerator.new(1).generate(Vector2i(2, -3)).raw_blocks()
	var b: PackedByteArray = TerrainGenerator.new(1).generate(Vector2i(2, -3)).raw_blocks()
	assert_eq(a, b)


func test_seeds_one_and_two_give_different_blocks() -> void:
	var a: PackedByteArray = TerrainGenerator.new(1).generate(Vector2i(0, 0)).raw_blocks()
	var b: PackedByteArray = TerrainGenerator.new(2).generate(Vector2i(0, 0)).raw_blocks()
	assert_ne(a, b)


func test_surface_height_matches_top_solid_block_at_sample_points() -> void:
	var reg := BlockRegistry.new()
	assert_eq(reg.load_from("res://data/blocks.json").size(), 0)
	var gen := TerrainGenerator.new(1)
	var chunk: Chunk = gen.generate(Vector2i(0, 0))
	for point: Vector2i in SAMPLE_POINTS:
		var expected: int = _top_solid_y(reg, chunk, point.x, point.y)
		assert_eq(
			gen.surface_height(point.x, point.y),
			expected,
			"surface_height mismatch at column %s" % str(point)
		)


func test_generated_chunk_top_y_matches_highest_non_air_block() -> void:
	var chunk: Chunk = TerrainGenerator.new(1).generate(Vector2i(1, 1))
	var highest: int = -1
	for y: int in Chunk.HEIGHT:
		for z: int in Chunk.SIZE:
			for x: int in Chunk.SIZE:
				if chunk.get_block(Vector3i(x, y, z)) != 0:
					highest = maxi(highest, y)
	assert_eq(chunk.top_y, highest)
