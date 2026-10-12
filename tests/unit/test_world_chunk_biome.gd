extends GutTest


func test_biome_defaults_to_zero() -> void:
	var c: Chunk = Chunk.new(Vector2i.ZERO)
	assert_eq(c.get_biome(3, 4), 0)
	assert_eq(c.raw_biomes().size(), Chunk.LAYER)


func test_biome_set_get_and_bounds() -> void:
	var c: Chunk = Chunk.new(Vector2i.ZERO)
	c.set_biome(15, 15, 3)
	c.set_biome(16, 0, 9)
	c.set_biome(-1, 0, 9)
	assert_eq(c.get_biome(15, 15), 3)
	assert_eq(c.get_biome(16, 0), 0)
	assert_eq(c.get_biome(-1, 0), 0)
