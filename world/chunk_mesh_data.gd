class_name ChunkMeshData
extends RefCounted
## Packed mesh output of ChunkMesher. Plain arrays only, so it can be built on a worker thread.

var vertices: PackedVector3Array = PackedVector3Array()
var normals: PackedVector3Array = PackedVector3Array()
var colors: PackedColorArray = PackedColorArray()
var indices: PackedInt32Array = PackedInt32Array()
var face_count: int = 0
