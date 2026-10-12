extends SceneTree
## Profiler for WorldStreamer. Runs the boot scene on the benchmark path (headless, 15 s by default) with
## WorldStreamer.profile_enabled on, then prints the 99th-percentile and maximum main-thread ms that each
## WorldStreamer._process call took. Not part of check.sh.
## Run: $GODOT --headless --path . -s tools/profile_stream.gd -- --benchmark --bench-seconds=15

## Loaded at run time, not preloaded: a preload is compiled before the autoloads (Settings, Data) exist
## when a script runs through -s, and the scene would then fail to compile.
const MAIN_SCENE_PATH: String = "res://main.tscn"
const BENCHMARK_ARG: String = "--benchmark"
const BENCHMARK_NODE: String = "Benchmark"
const PERCENTILE: float = 0.99
const TARGET_P99_MS: float = 8.0
const TARGET_MAX_MS: float = 25.0
## The run gives up if the benchmark has not started after this many milliseconds (world loading).
const START_TIMEOUT_MS: int = 240000

var _main: Node
var _armed: bool = false
var _started_ms: int = 0


func _initialize() -> void:
	if not BENCHMARK_ARG in OS.get_cmdline_user_args():
		print("profile_stream: run with -- --benchmark --bench-seconds=15")
		quit(1)
		return
	WorldStreamer.profile_enabled = true
	var scene: PackedScene = load(MAIN_SCENE_PATH) as PackedScene
	_main = scene.instantiate()
	root.add_child(_main)
	_started_ms = Time.get_ticks_msec()


## Waits until the boot scene starts its benchmark, then clears the samples taken during loading and
## listens for the benchmark's end. Returning false keeps the loop running.
func _process(_delta: float) -> bool:
	if _armed:
		return false
	var bench: Node = _main.get_node_or_null(BENCHMARK_NODE)
	if bench == null:
		if Time.get_ticks_msec() - _started_ms > START_TIMEOUT_MS:
			print("profile_stream: the benchmark did not start in time")
			quit(1)
			return true
		return false
	_armed = true
	WorldStreamer.profile_ms.clear()
	bench.finished.connect(_report)
	return false


func _report() -> void:
	var sorted: PackedFloat64Array = WorldStreamer.profile_ms.duplicate()
	sorted.sort()
	var count: int = sorted.size()
	if count == 0:
		print("profile_stream: no WorldStreamer frames were recorded")
		return
	var index: int = clampi(ceili(count * PERCENTILE) - 1, 0, count - 1)
	var p99_ms: float = sorted[index]
	var max_ms: float = sorted[count - 1]
	var p99_verdict: String = _verdict(p99_ms <= TARGET_P99_MS)
	var max_verdict: String = _verdict(max_ms <= TARGET_MAX_MS)
	print("profile_stream: frames=%d" % count)
	print("profile_stream: p99_ms=%.2f target<=%.1f %s" % [p99_ms, TARGET_P99_MS, p99_verdict])
	print("profile_stream: max_ms=%.2f target<=%.1f %s" % [max_ms, TARGET_MAX_MS, max_verdict])


func _verdict(ok: bool) -> String:
	return "PASS" if ok else "FAIL"
