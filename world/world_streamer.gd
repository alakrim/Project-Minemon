class_name WorldStreamer
extends Node3D
## Streams voxel columns in around a focus point.
## Threading: worker tasks only run ColumnJobs (a RefCounted that never references this Node). They push
## plain results into its mutex-guarded queue. The main thread makes snapshots, builds ArrayMeshes and
## collision, and owns every Node. Freeing the streamer waits for its in-flight tasks first.

const COLUMN_SIZE: int = Chunk.SIZE
const APPLY_PER_FRAME: int = 4
const MESH_REQUESTS_PER_FRAME: int = 8
const BLOCKS_PATH: String = "res://data/blocks.json"
const RESULT_CHUNK: int = ColumnJobs.RESULT_CHUNK
const RESULT_MESH: int = ColumnJobs.RESULT_MESH
const NEIGHBOUR_OFFSETS: Array[Vector2i] = [
	Vector2i(0, -1), Vector2i(0, 1), Vector2i(1, 0), Vector2i(-1, 0)
]

## Debug only (tools/profile_stream.gd). When true, _process records its main-thread time in ms.
static var profile_enabled: bool = false
## Main-thread ms of each _process call while profile_enabled is true.
static var profile_ms: PackedFloat64Array = PackedFloat64Array()

## Seed used by the terrain. Read once, when the streamer first initialises.
var seed: int = 1
## Columns around the focus that are loaded (Chebyshev distance).
var view_radius: int = 4
## Columns around the focus that get trimesh collision.
var collision_radius: int = 2

var _runner: ColumnJobs
var _blocks: BlockRegistry
var _material: StandardMaterial3D
var _chunks: Dictionary[Vector2i, Chunk] = {}
## Column -> serial of the newest job asked for it. A result with any other serial is stale and dropped.
var _serials: Dictionary[Vector2i, int] = {}
var _nodes: Dictionary[Vector2i, MeshInstance3D] = {}
var _bodies: Dictionary[Vector2i, StaticBody3D] = {}
var _ready_meshes: Array[Dictionary] = []
## Columns waiting for a mesh request, in order. _mesh_queued is the same set, for de-duplication.
var _mesh_queue: Array[Vector2i] = []
var _mesh_queued: Dictionary[Vector2i, bool] = {}
var _task_ids: Array[int] = []
var _serial: int = 0
var _focus_column: Vector2i = Vector2i.ZERO
var _closing: bool = false


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_shutdown()


func _ready() -> void:
	_ensure_ready()


func _process(_delta: float) -> void:
	if profile_enabled:
		var started: int = Time.get_ticks_usec()
		_process_frame()
		profile_ms.append(float(Time.get_ticks_usec() - started) / 1000.0)
	else:
		_process_frame()


func _process_frame() -> void:
	if _closing:
		return
	_ensure_ready()
	_prune_tasks()
	_drain_results()
	_issue_mesh_requests(MESH_REQUESTS_PER_FRAME)
	_apply_meshes(APPLY_PER_FRAME)


func _exit_tree() -> void:
	_shutdown()


func set_focus(pos: Vector3) -> void:
	if _closing:
		return
	_ensure_ready()
	_focus_column = _column_of(pos)
	_unload_far()
	var r: int = view_radius
	for dz: int in range(-r, r + 1):
		for dx: int in range(-r, r + 1):
			var col: Vector2i = _focus_column + Vector2i(dx, dz)
			if _serials.has(col):
				continue
			_request_generate(col)
	_refresh_collision()


func loaded_count() -> int:
	return _nodes.size()


func has_collision_at(pos: Vector3) -> bool:
	return _bodies.has(_column_of(pos))


## Waits for every queued task and applies every finished mesh.
func flush() -> void:
	_ensure_ready()
	_wait_and_drain()
	_apply_meshes(_ready_meshes.size())


func _ensure_ready() -> void:
	if _runner != null:
		return
	_runner = ColumnJobs.new(TerrainGenerator.new(seed))
	_blocks = BlockRegistry.new()
	var errors: Array[String] = _blocks.load_from(BLOCKS_PATH)
	for error: String in errors:
		push_error(error)
	_material = StandardMaterial3D.new()
	_material.vertex_color_use_as_albedo = true
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL


func _column_of(pos: Vector3) -> Vector2i:
	return Vector2i(floori(pos.x / COLUMN_SIZE), floori(pos.z / COLUMN_SIZE))


func _origin_of(col: Vector2i) -> Vector3:
	return Vector3(float(col.x * COLUMN_SIZE), 0.0, float(col.y * COLUMN_SIZE))


func _chebyshev(col: Vector2i) -> int:
	return maxi(absi(col.x - _focus_column.x), absi(col.y - _focus_column.y))


func _next_serial() -> int:
	_serial += 1
	return _serial


func _is_latest(col: Vector2i, serial: int) -> bool:
	return _serials.get(col, -1) == serial


func _request_generate(col: Vector2i) -> void:
	var serial: int = _next_serial()
	_serials[col] = serial
	_task_ids.append(
		WorkerThreadPool.add_task(Callable(_runner, &"run_generate").bind(col, serial))
	)


## Main thread, O(1): copies the raw bytes of the column and its neighbours. The worker does the padding.
func _request_mesh(col: Vector2i) -> void:
	var serial: int = _next_serial()
	_serials[col] = serial
	var inputs: Array = ChunkSnapshot.copy_inputs(
		_chunks[col],
		_chunks.get(col + Vector2i(0, -1)),
		_chunks.get(col + Vector2i(0, 1)),
		_chunks.get(col + Vector2i(1, 0)),
		_chunks.get(col + Vector2i(-1, 0))
	)
	_task_ids.append(
		WorkerThreadPool.add_task(Callable(_runner, &"run_mesh").bind(col, serial, inputs, _blocks))
	)


## Main thread: queues a column for a mesh request. A column already queued is not added twice.
func _enqueue_mesh(col: Vector2i) -> void:
	if _mesh_queued.has(col):
		return
	_mesh_queued[col] = true
	_mesh_queue.append(col)


## Main thread: issues at most `limit` queued mesh requests. The rest stay queued for later frames.
func _issue_mesh_requests(limit: int) -> void:
	if _closing:
		return
	var issued: int = 0
	while issued < limit and not _mesh_queue.is_empty():
		var col: Vector2i = _mesh_queue.pop_front()
		_mesh_queued.erase(col)
		if not _chunks.has(col):
			continue
		_request_mesh(col)
		issued += 1


## Main thread: moves finished job results into the main-thread queues.
func _drain_results() -> void:
	for entry: Dictionary in _runner.take_done():
		if entry["kind"] == RESULT_CHUNK:
			_accept_chunk(entry)
		else:
			_accept_mesh(entry)


func _accept_chunk(entry: Dictionary) -> void:
	var col: Vector2i = entry["pos"]
	if not _is_latest(col, entry["serial"]):
		return
	_chunks[col] = entry["payload"]
	if _closing:
		return
	_enqueue_mesh(col)
	for offset: Vector2i in NEIGHBOUR_OFFSETS:
		var neighbour: Vector2i = col + offset
		if _chunks.has(neighbour):
			_enqueue_mesh(neighbour)


func _accept_mesh(entry: Dictionary) -> void:
	var col: Vector2i = entry["pos"]
	if not _is_latest(col, entry["serial"]):
		return
	_ready_meshes.append({"pos": col, "serial": entry["serial"], "data": entry["payload"]})


func _apply_meshes(limit: int) -> void:
	var applied: int = 0
	while applied < limit and not _ready_meshes.is_empty():
		var item: Dictionary = _ready_meshes.pop_front()
		var col: Vector2i = item["pos"]
		if not _chunks.has(col) or not _is_latest(col, item["serial"]):
			continue
		_apply_column(col, item["data"] as ChunkMeshData)
		applied += 1


func _apply_column(col: Vector2i, data: ChunkMeshData) -> void:
	_remove_column_nodes(col)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Column_%d_%d" % [col.x, col.y]
	mesh_instance.mesh = _build_array_mesh(data)
	mesh_instance.position = _origin_of(col)
	add_child(mesh_instance)
	_nodes[col] = mesh_instance
	_refresh_collision_for(col)


func _build_array_mesh(data: ChunkMeshData) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if data.face_count == 0:
		return mesh
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = data.vertices
	arrays[Mesh.ARRAY_NORMAL] = data.normals
	arrays[Mesh.ARRAY_COLOR] = data.colors
	arrays[Mesh.ARRAY_INDEX] = data.indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, _material)
	return mesh


func _remove_column_nodes(col: Vector2i) -> void:
	if _bodies.has(col):
		_detach_body(col)
	if _nodes.has(col):
		var old: MeshInstance3D = _nodes[col]
		_nodes.erase(col)
		remove_child(old)
		old.free()


func _refresh_collision() -> void:
	for col: Vector2i in _nodes.keys():
		_refresh_collision_for(col)


func _refresh_collision_for(col: Vector2i) -> void:
	var wanted: bool = _chebyshev(col) <= collision_radius
	if wanted and not _bodies.has(col) and _nodes.has(col):
		_attach_body(col)
	elif not wanted and _bodies.has(col):
		_detach_body(col)


func _attach_body(col: Vector2i) -> void:
	var mesh: Mesh = _nodes[col].mesh
	if mesh.get_surface_count() == 0:
		return
	var shape: ConcavePolygonShape3D = mesh.create_trimesh_shape()
	if shape == null:
		return
	var body := StaticBody3D.new()
	var shape_node := CollisionShape3D.new()
	shape_node.shape = shape
	body.add_child(shape_node)
	body.position = _origin_of(col)
	add_child(body)
	_bodies[col] = body


func _detach_body(col: Vector2i) -> void:
	var body: StaticBody3D = _bodies[col]
	_bodies.erase(col)
	remove_child(body)
	body.free()


func _unload_far() -> void:
	var limit: int = view_radius + 1
	for col: Vector2i in _serials.keys():
		if _chebyshev(col) > limit:
			_drop_column(col)


## Forgets a column: its chunk, its nodes, its serial and any mesh still waiting to be applied.
func _drop_column(col: Vector2i) -> void:
	_serials.erase(col)
	_chunks.erase(col)
	_mesh_queued.erase(col)
	_mesh_queue.erase(col)
	_remove_column_nodes(col)
	var kept: Array[Dictionary] = []
	for item: Dictionary in _ready_meshes:
		if item["pos"] != col:
			kept.append(item)
	_ready_meshes = kept


func _prune_tasks() -> void:
	var still_running: Array[int] = []
	for id: int in _task_ids:
		if not WorkerThreadPool.is_task_completed(id):
			still_running.append(id)
		else:
			WorkerThreadPool.wait_for_task_completion(id)
	_task_ids = still_running


## Waits for all queued tasks. Finished results can queue new mesh tasks, so this repeats until none remain.
## Unlike a frame, this issues every queued mesh request, not just MESH_REQUESTS_PER_FRAME of them.
func _wait_and_drain() -> void:
	while true:
		for id: int in _task_ids:
			WorkerThreadPool.wait_for_task_completion(id)
		_task_ids.clear()
		_drain_results()
		_issue_mesh_requests(_mesh_queue.size())
		if _task_ids.is_empty():
			break


## Stops the streamer: waits for every in-flight task and discards pending results. Safe to call twice.
func _shutdown() -> void:
	if _closing or _runner == null:
		_closing = true
		return
	_closing = true
	_wait_and_drain()
	_ready_meshes.clear()
	_mesh_queue.clear()
	_mesh_queued.clear()
