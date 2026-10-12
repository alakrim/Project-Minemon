extends GutTest
## Smoke test for the boot scene: with view radius 1 the world loads and the player
## becomes active above ground.

const MAIN_SCENE: PackedScene = preload("res://main.tscn")
const MAX_FRAMES: int = 300
const TEST_SEED: int = 1337


func test_main_loads_world_and_activates_player() -> void:
	var saved_radius: int = Settings.view_radius
	Settings.view_radius = 1
	var main: Node = add_child_autofree(MAIN_SCENE.instantiate())
	var player: Player = main.get_node("Player") as Player
	var frames: int = 0
	while not player.active and frames < MAX_FRAMES:
		await get_tree().process_frame
		frames += 1
	Settings.view_radius = saved_radius

	assert_true(player.active, "player must be active within %d frames" % MAX_FRAMES)
	var streamer: WorldStreamer = main.get_node("World/WorldStreamer") as WorldStreamer
	assert_gte(streamer.loaded_count(), 9, "view radius 1 must load at least 9 columns")
	var ground: float = float(TerrainGenerator.new(TEST_SEED).surface_height(0, 0))
	assert_gt(player.global_position.y, ground, "player must stand above the ground")


func test_streamer_moves_then_frees_without_error() -> void:
	# Regression: finished worker tasks must be waited on when pruned, or the engine aborts at exit.
	var streamer := WorldStreamer.new()
	streamer.seed = TEST_SEED
	streamer.view_radius = 2
	add_child(streamer)
	var moves: Array[Vector3] = [
		Vector3(0.5, 0.0, 0.5),
		Vector3(40.0, 0.0, 0.5),
		Vector3(80.0, 0.0, 40.0),
		Vector3(0.5, 0.0, 120.0),
		Vector3(-60.0, 0.0, -30.0),
	]
	for pos: Vector3 in moves:
		streamer.set_focus(pos)
		for i: int in 5:
			await get_tree().process_frame
	streamer.queue_free()
	for i: int in 5:
		await get_tree().process_frame
	assert_false(is_instance_valid(streamer), "streamer must be freed")
	assert_no_new_orphans()


func test_benchmark_seconds_argument_parsing() -> void:
	assert_eq(Benchmark.parse_seconds(PackedStringArray(["--bench-seconds=15"])), 15.0)
	assert_eq(Benchmark.parse_seconds(PackedStringArray(["--bench-seconds=2.5"])), 2.5)
	assert_eq(
		Benchmark.parse_seconds(PackedStringArray(["--benchmark"])), 60.0, "no value gives 60"
	)
	assert_eq(Benchmark.parse_seconds(PackedStringArray()), 60.0, "no arguments give 60")
	assert_eq(Benchmark.parse_seconds(PackedStringArray(["--bench-seconds=abc"])), 60.0)
	assert_eq(Benchmark.parse_seconds(PackedStringArray(["--bench-seconds="])), 60.0)
	assert_eq(Benchmark.parse_seconds(PackedStringArray(["--bench-seconds=0"])), 60.0)
	assert_eq(Benchmark.parse_seconds(PackedStringArray(["--bench-seconds=-3"])), 60.0)
	assert_eq(Benchmark.parse_seconds(PackedStringArray(["--bench-seconds=inf"])), 60.0)
	assert_eq(Benchmark.parse_seconds(PackedStringArray(["--bench-seconds=15s"])), 60.0)
