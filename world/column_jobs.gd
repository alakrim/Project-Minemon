class_name ColumnJobs
extends RefCounted
## Worker-side job runner for WorldStreamer. It holds only plain data, the generator and a mutex,
## never a Node, so queued WorkerThreadPool tasks do not lock the streamer and it can be freed
## at any time (the streamer waits for its tasks first).

const RESULT_CHUNK: int = 0
const RESULT_MESH: int = 1

var _generator: TerrainGenerator
var _mutex: Mutex = Mutex.new()
var _done: Array[Dictionary] = []


func _init(generator: TerrainGenerator) -> void:
	_generator = generator


## Worker thread: generates the chunk for a column and reports it.
func run_generate(col: Vector2i, serial: int) -> void:
	var chunk: Chunk = _generator.generate(col)
	_push({"kind": RESULT_CHUNK, "pos": col, "serial": serial, "payload": chunk})


## Worker thread: pads the raw inputs of ChunkSnapshot.copy_inputs() into a snapshot, meshes it and
## reports the packed arrays. The padding happens here, never on the main thread.
func run_mesh(col: Vector2i, serial: int, inputs: Array, blocks: BlockRegistry) -> void:
	var snap: ChunkSnapshot = ChunkSnapshot.from_raw(inputs[0], inputs[1])
	var data: ChunkMeshData = ChunkMesher.build(snap, blocks)
	_push({"kind": RESULT_MESH, "pos": col, "serial": serial, "payload": data})


## Main thread: takes every finished result and clears the queue.
func take_done() -> Array[Dictionary]:
	_mutex.lock()
	var batch: Array[Dictionary] = _done.duplicate()
	_done.clear()
	_mutex.unlock()
	return batch


func _push(entry: Dictionary) -> void:
	_mutex.lock()
	_done.append(entry)
	_mutex.unlock()
