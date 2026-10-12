class_name TerrainGenerator
extends RefCounted
## Deterministic terrain for one seed. Pure data: runs on worker threads (no scene-tree or Resource access).
## Trees are decided per world column, and the margin around each chunk is checked too,
## so a tree that reaches into a chunk is planted there as well (no seams at chunk borders).

const SEA_LEVEL: int = 32
const MIN_HEIGHT: int = 1
const MAX_HEIGHT: int = 100
const SNOW_LINE: int = 80
const HEIGHT_FREQUENCY: float = 0.004
const BIOME_FREQUENCY: float = 0.0015
const TREE_ODDS: int = 40
const TREE_MARGIN: int = 3

const BIOME_PLAINS: int = 0
const BIOME_FOREST: int = 1
const BIOME_MOUNTAIN: int = 2
const BIOME_BEACH: int = 3

const BLOCK_GRASS: int = 1
const BLOCK_DIRT: int = 2
const BLOCK_STONE: int = 3
const BLOCK_SAND: int = 4
const BLOCK_WATER: int = 5
const BLOCK_LOG: int = 6
const BLOCK_LEAVES: int = 7
const BLOCK_SNOW: int = 8

var _seed: int
var _height_noise: GradientNoise
var _biome_noise: GradientNoise


func _init(p_seed: int) -> void:
	_seed = p_seed
	_height_noise = GradientNoise.new(Rng.new(p_seed).fork("height").seed, HEIGHT_FREQUENCY)
	_biome_noise = GradientNoise.new(Rng.new(p_seed).fork("biome").seed, BIOME_FREQUENCY)


func generate(pos: Vector2i) -> Chunk:
	var chunk := Chunk.new(pos)
	var origin_x: int = pos.x * Chunk.SIZE
	var origin_z: int = pos.y * Chunk.SIZE
	for lz: int in Chunk.SIZE:
		for lx: int in Chunk.SIZE:
			_fill_column(chunk, lx, lz, origin_x + lx, origin_z + lz)
	for tx: int in range(origin_x - TREE_MARGIN, origin_x + Chunk.SIZE + TREE_MARGIN):
		for tz: int in range(origin_z - TREE_MARGIN, origin_z + Chunk.SIZE + TREE_MARGIN):
			_plant_tree_if_any(chunk, tx, tz)
	return chunk


## Y of the top solid (ground) block at a world column. Needs no chunk and no trees.
func surface_height(x: int, z: int) -> int:
	var n: float = _height_noise.sample(float(x), float(z))
	var height: int = floori(20.0 + n * 70.0)
	return clampi(height, MIN_HEIGHT, MAX_HEIGHT) - 1


func biome_at(x: int, z: int) -> int:
	var b: float = _biome_noise.sample(float(x), float(z))
	if b > 0.35:
		return BIOME_MOUNTAIN
	if b < -0.35:
		return BIOME_FOREST
	if absf(b) < 0.06:
		return BIOME_BEACH
	return BIOME_PLAINS


func _fill_column(chunk: Chunk, lx: int, lz: int, wx: int, wz: int) -> void:
	var top: int = surface_height(wx, wz)
	var top_id: int = _top_block(top, biome_at(wx, wz))
	var sub_id: int = _sub_block(top_id)
	for y: int in range(0, top + 1):
		var id: int = BLOCK_STONE
		if y == top:
			id = top_id
		elif y >= top - 3:
			id = sub_id
		chunk.set_block(Vector3i(lx, y, lz), id)
	for y: int in range(top + 1, SEA_LEVEL):
		chunk.set_block(Vector3i(lx, y, lz), BLOCK_WATER)


func _top_block(top: int, biome: int) -> int:
	if top > SNOW_LINE:
		return BLOCK_SNOW
	if biome == BIOME_BEACH or top <= SEA_LEVEL + 1:
		return BLOCK_SAND
	if biome == BIOME_MOUNTAIN:
		return BLOCK_STONE
	return BLOCK_GRASS


func _sub_block(top_id: int) -> int:
	if top_id == BLOCK_SAND:
		return BLOCK_SAND
	if top_id == BLOCK_STONE:
		return BLOCK_STONE
	return BLOCK_DIRT


func _plant_tree_if_any(chunk: Chunk, tx: int, tz: int) -> void:
	if biome_at(tx, tz) != BIOME_FOREST:
		return
	var base_y: int = surface_height(tx, tz)
	if base_y < SEA_LEVEL:
		return
	var rng: Rng = Rng.new(_seed).fork("tree:%d,%d" % [tx, tz])
	if rng.randi_range(0, TREE_ODDS - 1) != 0:
		return
	var trunk: int = rng.randi_range(4, 6)
	var local_x: int = tx - chunk.pos.x * Chunk.SIZE
	var local_z: int = tz - chunk.pos.y * Chunk.SIZE
	var crown_y: int = base_y + trunk
	for h: int in range(1, trunk + 1):
		chunk.set_block(Vector3i(local_x, base_y + h, local_z), BLOCK_LOG)
	for dy: int in range(-2, 2):
		var radius: int = 2 if dy < 0 else 1
		for dx: int in range(-radius, radius + 1):
			for dz: int in range(-radius, radius + 1):
				if absi(dx) == radius and absi(dz) == radius:
					continue
				_set_leaf_if_air(chunk, Vector3i(local_x + dx, crown_y + dy, local_z + dz))


func _set_leaf_if_air(chunk: Chunk, p: Vector3i) -> void:
	if chunk.get_block(p) == 0:
		chunk.set_block(p, BLOCK_LEAVES)
