extends Node3D
## Boot scene. Builds the generated world, spawns the player once its collision exists, and starts the
## benchmark instead when "--benchmark" is on the command line. The debug overlay shows fps and chunks.

const WORLD_SEED: int = 1337
const SPAWN_LIFT: float = 2.0
const BENCH_HEIGHT: float = 20.0
const LOADING_TEXT: String = "Generating world…"
const BENCHMARK_ARG: String = "--benchmark"
const ENVIRONMENT_SCENE: PackedScene = preload("res://world/environment.tscn")
const PLAYER_SCENE: PackedScene = preload("res://entities/player.tscn")
const OVERLAY_SCENE: PackedScene = preload("res://ui/debug_overlay.tscn")

var _streamer: WorldStreamer
var _overlay: DebugOverlay
var _player: Player
var _benchmark: Benchmark = null
var _benchmark_mode: bool = false
var _spawned: bool = false
var _ground: int = 0

@onready var _world: Node3D = $World
@onready var _ui: CanvasLayer = $UI
@onready var _loading_label: Label = $UI/Label
@onready var _boot_camera: Camera3D = $BootCamera


func _ready() -> void:
	_benchmark_mode = BENCHMARK_ARG in OS.get_cmdline_user_args()
	_world.add_child(ENVIRONMENT_SCENE.instantiate())

	_streamer = WorldStreamer.new()
	_streamer.name = "WorldStreamer"
	_streamer.seed = WORLD_SEED
	_streamer.view_radius = Settings.view_radius
	_world.add_child(_streamer)

	_overlay = OVERLAY_SCENE.instantiate() as DebugOverlay
	_ui.add_child(_overlay)

	_loading_label.text = LOADING_TEXT
	_loading_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_loading_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_loading_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	_loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_streamer.set_focus(Vector3.ZERO)
	_streamer.flush()

	_ground = TerrainGenerator.new(WORLD_SEED).surface_height(0, 0)
	_player = PLAYER_SCENE.instantiate() as Player
	_player.name = "Player"
	_player.active = false
	add_child(_player)
	_player.global_position = Vector3(0.5, float(_ground) + SPAWN_LIFT, 0.5)


func _process(_delta: float) -> void:
	# During the benchmark, the benchmark node owns the streamer focus.
	if _benchmark == null:
		_streamer.set_focus(_player.global_position)
	_overlay.set_extra("Chunks", str(_streamer.loaded_count()))
	if not _spawned and _streamer.has_collision_at(_player.global_position):
		_spawned = true
		_spawn_player()


func _spawn_player() -> void:
	_boot_camera.queue_free()
	_loading_label.hide()
	if _benchmark_mode:
		_start_benchmark()
	else:
		_player.active = true


func _start_benchmark() -> void:
	var camera: Camera3D = _player.get_node("Camera") as Camera3D
	var spawn: Vector3 = _player.global_position
	_benchmark = Benchmark.new()
	_benchmark.name = "Benchmark"
	add_child(_benchmark)
	var centre := Vector3(spawn.x, float(_ground) + BENCH_HEIGHT, spawn.z)
	_benchmark.start(_player, camera, _streamer, centre)
