extends GutTest
## Streamer tests in a headless scene: loaded columns, collision radius, flush, shutdown and stale meshes.


func test_view_radius_one_loads_nine_columns_with_collision() -> void:
	var streamer := WorldStreamer.new()
	streamer.seed = 1
	streamer.view_radius = 1
	add_child_autofree(streamer)
	streamer.set_focus(Vector3.ZERO)
	streamer.flush()
	assert_eq(streamer.loaded_count(), 9)
	assert_true(streamer.has_collision_at(Vector3.ZERO))


func test_collision_only_within_collision_radius() -> void:
	var streamer := WorldStreamer.new()
	streamer.seed = 1
	streamer.view_radius = 2
	streamer.collision_radius = 1
	add_child_autofree(streamer)
	streamer.set_focus(Vector3.ZERO)
	streamer.flush()
	assert_eq(streamer.loaded_count(), 25)
	assert_true(
		streamer.has_collision_at(Vector3(8.0, 0.0, 8.0)), "column (0,0) must have collision"
	)
	assert_false(
		streamer.has_collision_at(Vector3(40.0, 0.0, 0.0)),
		"column (2,0) is outside collision_radius 1"
	)


func test_freeing_streamer_right_after_set_focus_is_safe() -> void:
	var streamer := WorldStreamer.new()
	streamer.seed = 1
	streamer.view_radius = 2
	add_child(streamer)
	streamer.set_focus(Vector3.ZERO)
	streamer.free()
	assert_no_new_orphans()


func test_queue_free_with_tasks_running_is_safe_across_frames() -> void:
	var streamer := WorldStreamer.new()
	streamer.seed = 1
	streamer.view_radius = 2
	add_child(streamer)
	streamer.set_focus(Vector3.ZERO)
	streamer.queue_free()
	for i: int in 5:
		await get_tree().process_frame
	assert_false(is_instance_valid(streamer), "streamer must be deleted")
	assert_no_new_orphans()


func test_stale_mesh_is_dropped_after_unload_and_reload() -> void:
	var streamer := WorldStreamer.new()
	streamer.seed = 1
	streamer.view_radius = 1
	add_child_autofree(streamer)
	streamer.set_focus(Vector3.ZERO)
	streamer.flush()
	var stale: int = streamer._serials[Vector2i.ZERO] - 1
	streamer._ready_meshes.append(
		{"pos": Vector2i.ZERO, "serial": stale, "data": ChunkMeshData.new()}
	)
	streamer.set_focus(Vector3(1000.0, 0.0, 0.0))
	var pending_for_origin: int = 0
	for item: Dictionary in streamer._ready_meshes:
		if item["pos"] == Vector2i.ZERO:
			pending_for_origin += 1
	assert_eq(pending_for_origin, 0, "unload must purge pending meshes of the unloaded column")
	streamer.set_focus(Vector3.ZERO)
	streamer.flush()
	var mesh: Mesh = streamer._nodes[Vector2i.ZERO].mesh
	assert_gt(mesh.get_surface_count(), 0, "the empty stale mesh must not replace the real one")


func test_five_requests_for_one_column_in_one_frame_give_one_job() -> void:
	var streamer := WorldStreamer.new()
	streamer.seed = 1
	streamer.view_radius = 1
	add_child_autofree(streamer)
	streamer.set_focus(Vector3.ZERO)
	streamer.flush()
	for i: int in 5:
		streamer._enqueue_mesh(Vector2i.ZERO)
	streamer._issue_mesh_requests(WorldStreamer.MESH_REQUESTS_PER_FRAME)
	assert_eq(streamer._task_ids.size(), 1, "one column must give one mesh job")
	assert_eq(streamer._mesh_queue.size(), 0, "nothing may stay queued for that column")
	streamer.flush()


func test_at_most_eight_mesh_requests_are_issued_per_frame() -> void:
	var streamer := WorldStreamer.new()
	streamer.seed = 1
	streamer.view_radius = 3
	add_child_autofree(streamer)
	streamer.set_focus(Vector3.ZERO)
	streamer.flush()
	for z: int in range(-2, 2):
		for x: int in range(-2, 3):
			streamer._enqueue_mesh(Vector2i(x, z))
	assert_eq(streamer._mesh_queue.size(), 20, "20 distinct columns must be queued")
	streamer._process(0.0)
	assert_eq(streamer._mesh_queue.size(), 12, "one frame must issue 8 and keep 12 queued")
	streamer._process(0.0)
	assert_eq(streamer._mesh_queue.size(), 4, "the next frame must issue 8 more")
	streamer.flush()
	assert_eq(streamer._mesh_queue.size(), 0, "flush must issue every queued request")


func test_profiling_is_off_by_default_and_records_nothing() -> void:
	assert_false(WorldStreamer.profile_enabled, "profiling must be off unless a tool turns it on")
	var streamer := WorldStreamer.new()
	streamer.seed = 1
	streamer.view_radius = 1
	add_child_autofree(streamer)
	streamer.set_focus(Vector3.ZERO)
	streamer.flush()
	streamer._process(0.0)
	assert_eq(
		WorldStreamer.profile_ms.size(), 0, "no timing may be recorded while profiling is off"
	)
