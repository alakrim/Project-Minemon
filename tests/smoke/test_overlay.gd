extends GutTest
## Smoke tests for the debug overlay: it instances, is visible, and writes its required lines.

const OVERLAY_SCENE: PackedScene = preload("res://ui/debug_overlay.tscn")


func test_overlay_refresh_writes_required_lines() -> void:
	var overlay: DebugOverlay = add_child_autofree(OVERLAY_SCENE.instantiate())
	assert_true(overlay.visible, "overlay must be visible by default")
	overlay.refresh()
	var label: Label = overlay.get_node("Label")
	assert_string_contains(label.text, "FPS:")
	assert_string_contains(label.text, "GPU:")
	assert_string_contains(label.text, "Frame ms:")
	assert_string_contains(label.text, "Memory MB:")
	assert_string_contains(label.text, "Draw calls:")
	assert_string_contains(label.text, "Renderer:")
	assert_string_contains(label.text, "Pos:")


func test_set_extra_line_appears_after_refresh() -> void:
	var overlay: DebugOverlay = add_child_autofree(OVERLAY_SCENE.instantiate())
	overlay.set_extra("Chunks", "9")
	overlay.refresh()
	var label: Label = overlay.get_node("Label")
	assert_string_contains(label.text, "Chunks: 9")
