extends GutTest
## Atmosphere tests: sun energy by time of day, fog colour matching the sky horizon, night fog
## closer than day fog, and the clouds scene instancing.

const ENVIRONMENT_SCENE: PackedScene = preload("res://world/environment.tscn")
const CLOUDS_SCENE: PackedScene = preload("res://world/clouds.tscn")
const CHECK_TIMES: Array[float] = [0.3, 0.5, 0.75]


func _make_atmosphere() -> Atmosphere:
	return add_child_autofree(ENVIRONMENT_SCENE.instantiate()) as Atmosphere


func _environment(atmosphere: Atmosphere) -> Environment:
	return atmosphere.get_node("WorldEnvironment").environment as Environment


func test_noon_sun_is_brighter_than_night() -> void:
	var atmosphere := _make_atmosphere()
	var sun := atmosphere.get_node("Sun") as DirectionalLight3D
	atmosphere.apply_time(0.5)
	var noon: float = sun.light_energy
	atmosphere.apply_time(0.9)
	var night: float = sun.light_energy
	assert_gt(noon, night, "sun energy at noon must beat night")


func test_fog_colour_equals_sky_horizon_at_three_times() -> void:
	var atmosphere := _make_atmosphere()
	for t: float in CHECK_TIMES:
		atmosphere.apply_time(t)
		var env: Environment = _environment(atmosphere)
		var sky_material := env.sky.sky_material as ProceduralSkyMaterial
		assert_eq(
			env.fog_light_color,
			sky_material.sky_horizon_color,
			"fog colour must equal sky horizon at time %s" % str(t)
		)


func test_night_fog_is_closer_than_day_fog() -> void:
	var atmosphere := _make_atmosphere()
	var env: Environment = _environment(atmosphere)
	atmosphere.apply_time(0.5)
	var day_begin: float = env.fog_depth_begin
	var day_end: float = env.fog_depth_end
	atmosphere.apply_time(0.9)
	assert_lt(env.fog_depth_begin, day_begin, "night fog must start closer than day fog")
	assert_lt(env.fog_depth_end, day_end, "night fog must be opaque closer than day fog")


func test_day_fog_is_fully_opaque_by_loaded_edge() -> void:
	# Radius 4 chunks reach about 64 m; the fog must be opaque by 60 m.
	var atmosphere := _make_atmosphere()
	atmosphere.apply_time(0.5)
	var env: Environment = _environment(atmosphere)
	assert_lte(env.fog_depth_end, 64.0, "day fog must be opaque within the loaded radius")
	assert_gt(env.fog_depth_begin, 0.0, "fog must not start at the camera")


func test_clouds_scene_instances() -> void:
	var clouds: Node = CLOUDS_SCENE.instantiate()
	add_child_autofree(clouds)
	assert_true(clouds is MeshInstance3D, "clouds root must be a MeshInstance3D")
	var mesh_instance := clouds as MeshInstance3D
	assert_not_null(mesh_instance.mesh, "clouds must have a plane mesh")
	assert_true(mesh_instance.material_override is ShaderMaterial, "clouds need the shader")


func test_environment_includes_clouds_at_height() -> void:
	var atmosphere := _make_atmosphere()
	var clouds := atmosphere.get_node("Clouds") as MeshInstance3D
	assert_not_null(clouds, "environment must contain the clouds scene")
	atmosphere.apply_time(0.5)
	assert_eq(clouds.position.y, Atmosphere.CLOUD_HEIGHT, "clouds must sit at y = 140")
