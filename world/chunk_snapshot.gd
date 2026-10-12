class_name ChunkSnapshot
extends RefCounted
## Immutable padded copy of a chunk and its 4 neighbours, ready for meshing. Two steps:
##   1. copy_inputs(): main thread, O(1) per chunk. Native copies of the raw block bytes and their top_y.
##   2. from_raw(): worker thread only. Slices the neighbour borders and builds the padded array.
## The streamer never calls the Chunk constructor on the main thread (it uses steps 1 and 2).
## Neighbour directions: north = z-1, south = z+1, east = x+1, west = x-1. A missing neighbour counts as air.
##
## padded_blocks() is the chunk with a 1-block air ring on every side (x, z and y), so the mesher can
## look up neighbours with plain index arithmetic: index = (x+1) + (z+1)*PAD_ROW + (y+1)*PAD_LAYER.
## Input order: 0 centre, 1 north, 2 south, 3 east, 4 west.

const PAD_ROW: int = Chunk.SIZE + 2
const PAD_LAYER: int = PAD_ROW * PAD_ROW
const PAD_VOLUME: int = PAD_LAYER * (Chunk.HEIGHT + 2)

var _padded: PackedByteArray = PackedByteArray()
var _top_y: int = -1


## Convenience for tools and tests: copies the inputs and builds the snapshot on the calling thread.
## The streamer does not use this; it calls copy_inputs() on the main thread and from_raw() on a worker.
func _init(
	c: Chunk = null,
	north: Chunk = null,
	south: Chunk = null,
	east: Chunk = null,
	west: Chunk = null
) -> void:
	var inputs: Array = copy_inputs(c, north, south, east, west)
	_fill(inputs[0], inputs[1])


## Highest non-air y over the column and its 4 neighbours (-1 when all are air).
func top_y() -> int:
	return _top_y


func padded_blocks() -> PackedByteArray:
	return _padded


## Returns the block at p. Valid for x and z in -1..16 (the border ring); outside that range it is air.
func get_block(p: Vector3i) -> int:
	if p.y < 0 or p.y >= Chunk.HEIGHT:
		return 0
	if p.x < -1 or p.x > Chunk.SIZE or p.z < -1 or p.z > Chunk.SIZE:
		return 0
	return _padded[(p.x + 1) + (p.z + 1) * PAD_ROW + (p.y + 1) * PAD_LAYER]


## Main thread, O(1) per chunk. Returns [blocks, tops]: blocks is an Array[PackedByteArray] of the raw
## bytes of the centre and its 4 neighbours (native copies; empty when a chunk is missing) and tops is a
## PackedInt32Array of their top_y values (-1 when missing). Pass both to from_raw() on a worker.
static func copy_inputs(
	centre: Chunk, north: Chunk, south: Chunk, east: Chunk, west: Chunk
) -> Array:
	var blocks: Array[PackedByteArray] = [
		_copy_of(centre), _copy_of(north), _copy_of(south), _copy_of(east), _copy_of(west)
	]
	var tops := PackedInt32Array(
		[_top_of(centre), _top_of(north), _top_of(south), _top_of(east), _top_of(west)]
	)
	return [blocks, tops]


## Worker thread only: builds the padded snapshot from the inputs of copy_inputs().
static func from_raw(blocks: Array[PackedByteArray], tops: PackedInt32Array) -> ChunkSnapshot:
	var snap := ChunkSnapshot.new()
	snap._fill(blocks, tops)
	return snap


func _fill(blocks: Array[PackedByteArray], tops: PackedInt32Array) -> void:
	var top: int = -1
	for t: int in tops:
		top = maxi(top, t)
	_top_y = top
	_padded = _build_padded(blocks)


static func _copy_of(c: Chunk) -> PackedByteArray:
	if c == null:
		return PackedByteArray()
	return c.raw_blocks().duplicate()


static func _top_of(c: Chunk) -> int:
	if c == null:
		return -1
	return c.top_y


static func _build_padded(blocks: Array[PackedByteArray]) -> PackedByteArray:
	var centre: PackedByteArray = blocks[0]
	var north: PackedByteArray = blocks[1]
	var south: PackedByteArray = blocks[2]
	var east: PackedByteArray = blocks[3]
	var west: PackedByteArray = blocks[4]
	var pad := PackedByteArray()
	pad.resize(PAD_VOLUME)
	for y: int in Chunk.HEIGHT:
		var pad_base: int = (y + 1) * PAD_LAYER
		var src_base: int = y * Chunk.LAYER
		if not centre.is_empty():
			for z: int in Chunk.SIZE:
				var pad_row: int = pad_base + (z + 1) * PAD_ROW + 1
				var src_row: int = src_base + z * Chunk.SIZE
				for x: int in Chunk.SIZE:
					pad[pad_row + x] = centre[src_row + x]
		for a: int in Chunk.SIZE:
			if not north.is_empty():
				# The north neighbour's z = 15 row.
				pad[pad_base + 1 + a] = north[src_base + (Chunk.SIZE - 1) * Chunk.SIZE + a]
			if not south.is_empty():
				# The south neighbour's z = 0 row.
				pad[pad_base + (Chunk.SIZE + 1) * PAD_ROW + 1 + a] = south[src_base + a]
			if not west.is_empty():
				# The west neighbour's x = 15 column.
				pad[pad_base + (a + 1) * PAD_ROW] = west[
					src_base + (Chunk.SIZE - 1) + a * Chunk.SIZE
				]
			if not east.is_empty():
				# The east neighbour's x = 0 column.
				pad[pad_base + (a + 1) * PAD_ROW + Chunk.SIZE + 1] = east[src_base + a * Chunk.SIZE]
	return pad
