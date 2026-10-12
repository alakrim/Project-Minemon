extends GutTest
## Smoke tests for the player scene: it has a camera, is inert when inactive, and falls when active.

const PLAYER_SCENE: PackedScene = preload("res://entities/player.tscn")
const PHYSICS_FRAMES: int = 10


func test_player_scene_has_camera_child() -> void:
	var player: Player = add_child_autofree(PLAYER_SCENE.instantiate())
	var camera: Node = player.get_node_or_null("Camera")
	assert_not_null(camera, "Camera child missing")
	assert_true(camera is Camera3D, "Camera must be a Camera3D")


func test_inactive_player_does_not_move() -> void:
	var player: Player = PLAYER_SCENE.instantiate()
	player.active = false
	add_child_autofree(player)
	var start: Vector3 = player.global_position
	for i: int in PHYSICS_FRAMES:
		await get_tree().physics_frame
	assert_eq(player.global_position, start, "inactive player must not move")


func test_active_player_falls_under_gravity() -> void:
	# Control case: proves the inactive test above is not passing vacuously.
	var player: Player = PLAYER_SCENE.instantiate()
	player.active = true
	add_child_autofree(player)
	var start_y: float = player.global_position.y
	for i: int in PHYSICS_FRAMES:
		await get_tree().physics_frame
	assert_lt(player.global_position.y, start_y, "active player must fall")
