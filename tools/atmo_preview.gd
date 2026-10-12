extends Node3D
## Scratch render check for the atmosphere (T-10). Builds a flat field with pillars, adds the
## environment and renders three times of day to builds/atmo_T10_<nnn>.png. Run under Xvfb with
## --rendering-method gl_compatibility. A tool, not a test: it quits when done.

const ENVIRONMENT_SCENE: PackedScene = preload("res://world/environment.tscn")
const TIMES: Array[float] = [0.3, 0.5, 0.75]
const TIMES_ARG: String = "--times="
const WARM_UP_FRAMES: int = 4
const EYE_HEIGHT: float = 2.5
const FIELD_SIZE: float = 400.0
const PILLAR_COLUMNS: int = 13
const PILLAR_ROWS: int = 15
const PILLAR_SPACING_X: float = 9.0
const PILLAR_SPACING_Z: float = 12.0
const PILLAR_BASE_Z: float = -10.0
const PILLAR_PALETTE: Array[Color] = [
	Color(0.42, 0.36, 0.3, 1.0),
	Color(0.5, 0.5, 0.48, 1.0),
	Color(0.3, 0.42, 0.25, 1.0),
	Color(0.55, 0.42, 0.34, 1.0),
]
const GROUND_COLOR: Color = Color(0.28, 0.36, 0.2, 1.0)
const OUTPUT_DIR: String = "builds"


func _ready() -> void:
	var atmosphere: Atmosphere = ENVIRONMENT_SCENE.instantiate() as Atmosphere
	add_child(atmosphere)
	_build_field()
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, EYE_HEIGHT, 6.0)
	camera.fov = 70.0
	add_child(camera)
	camera.make_current()
	_render_all(atmosphere)


func _render_all(atmosphere: Atmosphere) -> void:
	var out_dir: String = ProjectSettings.globalize_path("res://").path_join(OUTPUT_DIR)
	DirAccess.make_dir_recursive_absolute(out_dir)
	for t: float in _times():
		atmosphere.apply_time(t)
		for i: int in WARM_UP_FRAMES:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var image: Image = get_viewport().get_texture().get_image()
		var name_part: String = "%03d" % int(roundf(t * 100.0))
		var path: String = out_dir.path_join("atmo_T10_t%s.png" % name_part)
		image.save_png(path)
		print("saved ", path)
	get_tree().quit()


## Times to render: the three acceptance times, or the list given as --times=0.95,0.2 for a check.
func _times() -> Array[float]:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with(TIMES_ARG):
			var values: Array[float] = []
			for part: String in arg.trim_prefix(TIMES_ARG).split(","):
				values.append(part.to_float())
			return values
	return TIMES


func _build_field() -> void:
	var ground := MeshInstance3D.new()
	var slab := BoxMesh.new()
	slab.size = Vector3(FIELD_SIZE, 1.0, FIELD_SIZE)
	ground.mesh = slab
	ground.material_override = _material(GROUND_COLOR)
	ground.position = Vector3(0.0, -0.5, 0.0)
	add_child(ground)

	var materials: Array[StandardMaterial3D] = []
	for colour: Color in PILLAR_PALETTE:
		materials.append(_material(colour))
	for i: int in PILLAR_COLUMNS:
		for j: int in PILLAR_ROWS:
			var column: int = i - PILLAR_COLUMNS / 2
			var height: float = 2.0 + float(posmod(column * 7 + j * 13, 6))
			var pillar := BoxMesh.new()
			pillar.size = Vector3(1.5, height, 1.5)
			var node := MeshInstance3D.new()
			node.mesh = pillar
			node.material_override = materials[posmod(column + j, PILLAR_PALETTE.size())]
			node.position = Vector3(
				float(column) * PILLAR_SPACING_X,
				height * 0.5,
				PILLAR_BASE_Z - float(j) * PILLAR_SPACING_Z
			)
			add_child(node)


func _material(colour: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	return material
