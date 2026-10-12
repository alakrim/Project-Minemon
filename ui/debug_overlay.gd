class_name DebugOverlay
extends CanvasLayer
## Debug overlay: fps, frame time, memory, draw calls, renderer, GPU and position.
## Toggled with the toggle_debug action. Refreshes every 0.25 s.

const REFRESH_INTERVAL: float = 0.25
const BYTES_PER_MB: float = 1048576.0

var _extras: Dictionary = {}
var _elapsed: float = 0.0
var _frame_time_sum: float = 0.0
var _frame_count: int = 0

@onready var _label: Label = $Label


func _ready() -> void:
	refresh()


func _process(delta: float) -> void:
	_frame_time_sum += delta
	_frame_count += 1
	_elapsed += delta
	if _elapsed >= REFRESH_INTERVAL:
		_elapsed = 0.0
		refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_debug"):
		visible = not visible


## Adds or replaces an extra "key: value" line below the built-in lines.
func set_extra(key: String, value: String) -> void:
	_extras[key] = value


## Rewrites the label from the current monitors. Frame ms is the mean since the last refresh.
func refresh() -> void:
	var frame_ms: float = 0.0
	if _frame_count > 0:
		frame_ms = _frame_time_sum / _frame_count * 1000.0
	_frame_time_sum = 0.0
	_frame_count = 0

	var memory_mb: float = Performance.get_monitor(Performance.MEMORY_STATIC) / BYTES_PER_MB
	var draw_calls: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var pos_text: String = "n/a"
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera != null:
		var p: Vector3 = camera.global_position
		pos_text = "%.1f, %.1f, %.1f" % [p.x, p.y, p.z]

	var lines: PackedStringArray = PackedStringArray()
	lines.append("FPS: %d" % int(Engine.get_frames_per_second()))
	lines.append("Frame ms: %.2f" % frame_ms)
	lines.append("Memory MB: %.1f" % memory_mb)
	lines.append("Draw calls: %d" % draw_calls)
	lines.append("Renderer: %s" % RenderingServer.get_current_rendering_method())
	lines.append("GPU: %s" % RenderingServer.get_video_adapter_name())
	lines.append("Pos: %s" % pos_text)
	for key: String in _extras.keys():
		lines.append("%s: %s" % [key, _extras[key]])
	_label.text = "\n".join(lines)
