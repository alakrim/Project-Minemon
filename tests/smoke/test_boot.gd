extends GutTest
## Smoke test: the boot scene loads and has its required nodes.

const MAIN_SCENE: PackedScene = preload("res://main.tscn")


func test_main_scene_has_boot_nodes() -> void:
	var main: Node = add_child_autofree(MAIN_SCENE.instantiate())
	assert_not_null(main.get_node_or_null("World"), "World node missing")
	assert_not_null(main.get_node_or_null("UI"), "UI node missing")
	assert_not_null(main.get_node_or_null("BootCamera"), "BootCamera node missing")
