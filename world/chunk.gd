class_name Chunk
extends RefCounted
## A column of 16 x 128 x 16 blocks. Block 0 is air. Index = x + z*16 + y*256.
## top_y is the highest non-air y in the column, or -1 when the column is all air.

const SIZE: int = 16
const HEIGHT: int = 128
const VOLUME: int = SIZE * SIZE * HEIGHT
const LAYER: int = SIZE * SIZE

var pos: Vector2i
var top_y: int = -1
var _blocks: PackedByteArray = PackedByteArray()
var _biomes: PackedByteArray = PackedByteArray()


func _init(p_pos: Vector2i) -> void:
	pos = p_pos
	_blocks.resize(VOLUME)
	_biomes.resize(LAYER)


static func index_of(x: int, y: int, z: int) -> int:
	return x + z * SIZE + y * LAYER


static func in_bounds(p: Vector3i) -> bool:
	return p.x >= 0 and p.x < SIZE and p.y >= 0 and p.y < HEIGHT and p.z >= 0 and p.z < SIZE


func get_block(p: Vector3i) -> int:
	if not in_bounds(p):
		return 0
	return _blocks[index_of(p.x, p.y, p.z)]


func set_block(p: Vector3i, id: int) -> void:
	if not in_bounds(p):
		return
	var value: int = clampi(id, 0, 255)
	_blocks[index_of(p.x, p.y, p.z)] = value
	if value != 0 and p.y > top_y:
		top_y = p.y
	elif value == 0 and p.y == top_y:
		_recalculate_top()


## Biome id of local column (x, z); see TerrainGenerator BIOME_* constants. Out of range returns 0.
func get_biome(x: int, z: int) -> int:
	if x < 0 or x >= SIZE or z < 0 or z >= SIZE:
		return 0
	return _biomes[x + z * SIZE]


func set_biome(x: int, z: int, biome: int) -> void:
	if x < 0 or x >= SIZE or z < 0 or z >= SIZE:
		return
	_biomes[x + z * SIZE] = clampi(biome, 0, 255)


## Read-only view of the raw biome bytes (index x + z*16). Callers must duplicate before keeping it.
func raw_biomes() -> PackedByteArray:
	return _biomes


## Read-only view of the raw block bytes. Callers must duplicate before keeping it.
func raw_blocks() -> PackedByteArray:
	return _blocks


func _recalculate_top() -> void:
	for y: int in range(top_y - 1, -1, -1):
		var start: int = y * LAYER
		for i: int in LAYER:
			if _blocks[start + i] != 0:
				top_y = y
				return
	top_y = -1
