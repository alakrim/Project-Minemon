class_name ChunkMesher
extends RefCounted
## Turns a ChunkSnapshot into packed mesh arrays. Pure data: no scene-tree or Resource access,
## so it is safe on worker threads. The inner loop reads the snapshot's padded byte array directly
## and uses per-block lookup tables, so it makes no function calls per voxel.

## Face order: +X, -X, +Y, -Y, +Z, -Z.
const FACE_DIRS: Array[Vector3i] = [
	Vector3i(1, 0, 0),
	Vector3i(-1, 0, 0),
	Vector3i(0, 1, 0),
	Vector3i(0, -1, 0),
	Vector3i(0, 0, 1),
	Vector3i(0, 0, -1),
]
## Four corners per face, counter-clockwise seen from outside the block.
const FACE_CORNERS: Array[Vector3] = [
	Vector3(1, 0, 0),
	Vector3(1, 1, 0),
	Vector3(1, 1, 1),
	Vector3(1, 0, 1),
	Vector3(0, 0, 1),
	Vector3(0, 1, 1),
	Vector3(0, 1, 0),
	Vector3(0, 0, 0),
	Vector3(0, 1, 0),
	Vector3(0, 1, 1),
	Vector3(1, 1, 1),
	Vector3(1, 1, 0),
	Vector3(0, 0, 1),
	Vector3(0, 0, 0),
	Vector3(1, 0, 0),
	Vector3(1, 0, 1),
	Vector3(1, 0, 1),
	Vector3(1, 1, 1),
	Vector3(0, 1, 1),
	Vector3(0, 0, 1),
	Vector3(0, 0, 0),
	Vector3(0, 1, 0),
	Vector3(1, 1, 0),
	Vector3(1, 0, 0),
]
## Face shade: top 1.0, sides 0.8, bottom 0.6.
const FACE_SHADE: Array[float] = [0.8, 0.8, 1.0, 0.6, 0.8, 0.8]


static func build(snap: ChunkSnapshot, blocks: BlockRegistry) -> ChunkMeshData:
	var out := ChunkMeshData.new()
	var pad: PackedByteArray = snap.padded_blocks()
	var transparent := PackedByteArray()
	var colors := PackedColorArray()
	transparent.resize(256)
	colors.resize(256)
	for id: int in 256:
		transparent[id] = 1 if blocks.is_transparent(id) else 0
		colors[id] = blocks.color(id)
	var offsets := PackedInt32Array(
		[
			1,
			-1,
			ChunkSnapshot.PAD_LAYER,
			-ChunkSnapshot.PAD_LAYER,
			ChunkSnapshot.PAD_ROW,
			-ChunkSnapshot.PAD_ROW
		]
	)
	var y_limit: int = mini(snap.top_y() + 1, Chunk.HEIGHT)
	for y: int in y_limit:
		for z: int in Chunk.SIZE:
			for x: int in Chunk.SIZE:
				var at: int = (
					(x + 1) + (z + 1) * ChunkSnapshot.PAD_ROW + (y + 1) * ChunkSnapshot.PAD_LAYER
				)
				var id: int = pad[at]
				if id == 0:
					continue
				for face: int in 6:
					var neighbour: int = pad[at + offsets[face]]
					if neighbour == id or transparent[neighbour] == 0:
						continue
					_emit_face(out, x, y, z, face, colors[id])
	return out


static func _emit_face(
	out: ChunkMeshData, x: int, y: int, z: int, face: int, block_color: Color
) -> void:
	var shade: float = FACE_SHADE[face]
	var shaded := Color(block_color.r * shade, block_color.g * shade, block_color.b * shade, 1.0)
	var normal := Vector3(FACE_DIRS[face])
	var origin := Vector3(x, y, z)
	var base: int = out.vertices.size()
	for corner: int in 4:
		out.vertices.append(origin + FACE_CORNERS[face * 4 + corner])
		out.normals.append(normal)
		out.colors.append(shaded)
	# Godot front faces are clockwise seen from outside, so the triangles are wound (0,2,1) and (0,3,2).
	out.indices.append(base)
	out.indices.append(base + 2)
	out.indices.append(base + 1)
	out.indices.append(base)
	out.indices.append(base + 3)
	out.indices.append(base + 2)
	out.face_count += 1
