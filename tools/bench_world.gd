extends SceneTree
## Benchmark: generates and meshes 81 columns (9 x 9), then prints ms per column and the face total.
## Run: $GODOT --headless --path . -s tools/bench_world.gd   (not part of check.sh)

const GRID_HALF: int = 4


func _initialize() -> void:
	var reg := BlockRegistry.new()
	var errors: Array[String] = reg.load_from("res://data/blocks.json")
	if not errors.is_empty():
		print("bench aborted, block data errors: %s" % str(errors))
		quit(1)
		return

	var gen := TerrainGenerator.new(1)
	var positions: Array[Vector2i] = []
	for z: int in range(-GRID_HALF, GRID_HALF + 1):
		for x: int in range(-GRID_HALF, GRID_HALF + 1):
			positions.append(Vector2i(x, z))

	var chunks: Dictionary[Vector2i, Chunk] = {}
	var gen_us: Array[int] = []
	for pos: Vector2i in positions:
		var t0: int = Time.get_ticks_usec()
		chunks[pos] = gen.generate(pos)
		gen_us.append(Time.get_ticks_usec() - t0)

	var column_ms: Array[float] = []
	var total_faces: int = 0
	for i: int in positions.size():
		var pos: Vector2i = positions[i]
		var t0: int = Time.get_ticks_usec()
		var snap := ChunkSnapshot.new(
			chunks[pos],
			chunks.get(pos + Vector2i(0, -1)),
			chunks.get(pos + Vector2i(0, 1)),
			chunks.get(pos + Vector2i(1, 0)),
			chunks.get(pos + Vector2i(-1, 0))
		)
		var data: ChunkMeshData = ChunkMesher.build(snap, reg)
		var mesh_us: int = Time.get_ticks_usec() - t0
		total_faces += data.face_count
		column_ms.append((gen_us[i] + mesh_us) / 1000.0)

	var sum_ms: float = 0.0
	var max_ms: float = 0.0
	for ms: float in column_ms:
		sum_ms += ms
		max_ms = maxf(max_ms, ms)
	var avg_ms: float = sum_ms / float(column_ms.size())
	print("bench_world: columns=%d" % column_ms.size())
	print("bench_world: avg_ms_per_column=%.3f" % avg_ms)
	print("bench_world: max_ms_per_column=%.3f" % max_ms)
	print("bench_world: total_faces=%d" % total_faces)
	quit(0)
