class_name Atmosphere
extends Node3D
## Drives the daytime look from one value, time_of_day (0..1, 0.5 = noon). apply_time sets the sun
## angle, colour and energy, sky colours, fog colour and range, ambient light and cloud tint from the
## keyframe tables below. Each frame it keeps the cloud layer centred over the active camera.

const CLOUD_HEIGHT: float = 140.0
## Compass direction of the sun's arc, in radians around Y.
const SUN_AZIMUTH: float = -1.1
const SUNRISE_TIME: float = 0.25
const AMBIENT_MIX_TO_TOP: float = 0.25

## Keyframes (time_of_day). The tables below are index-aligned with these; 0.0 and 1.0 are both night.
const KEY_TIMES: Array[float] = [0.0, 0.25, 0.4, 0.6, 0.75, 0.9, 1.0]
const SKY_TOP: Array[Color] = [
	Color(0.02, 0.035, 0.09, 1.0),
	Color(0.36, 0.42, 0.6, 1.0),
	Color(0.3, 0.45, 0.62, 1.0),
	Color(0.3, 0.45, 0.62, 1.0),
	Color(0.34, 0.35, 0.53, 1.0),
	Color(0.02, 0.035, 0.09, 1.0),
	Color(0.02, 0.035, 0.09, 1.0),
]
## Also the fog colour, so distant terrain melts into the sky.
const SKY_HORIZON: Array[Color] = [
	Color(0.07, 0.09, 0.16, 1.0),
	Color(0.88, 0.72, 0.66, 1.0),
	Color(0.74, 0.78, 0.8, 1.0),
	Color(0.74, 0.78, 0.8, 1.0),
	Color(0.9, 0.66, 0.58, 1.0),
	Color(0.07, 0.09, 0.16, 1.0),
	Color(0.07, 0.09, 0.16, 1.0),
]
const GROUND_HORIZON: Array[Color] = [
	Color(0.05, 0.06, 0.1, 1.0),
	Color(0.5, 0.45, 0.45, 1.0),
	Color(0.56, 0.58, 0.6, 1.0),
	Color(0.56, 0.58, 0.6, 1.0),
	Color(0.45, 0.4, 0.42, 1.0),
	Color(0.05, 0.06, 0.1, 1.0),
	Color(0.05, 0.06, 0.1, 1.0),
]
const SUN_COLOR: Array[Color] = [
	Color(0.45, 0.52, 0.7, 1.0),
	Color(1.0, 0.66, 0.46, 1.0),
	Color(1.0, 0.93, 0.82, 1.0),
	Color(1.0, 0.93, 0.82, 1.0),
	Color(1.0, 0.6, 0.38, 1.0),
	Color(0.45, 0.52, 0.7, 1.0),
	Color(0.45, 0.52, 0.7, 1.0),
]
const CLOUD_TINT: Array[Color] = [
	Color(0.2, 0.23, 0.34, 1.0),
	Color(1.0, 0.8, 0.72, 1.0),
	Color(1.0, 0.98, 0.95, 1.0),
	Color(1.0, 0.98, 0.95, 1.0),
	Color(1.0, 0.78, 0.66, 1.0),
	Color(0.2, 0.23, 0.34, 1.0),
	Color(0.2, 0.23, 0.34, 1.0),
]
const SUN_ENERGY: Array[float] = [0.0, 0.7, 1.15, 1.15, 0.7, 0.0, 0.0]
const AMBIENT_ENERGY: Array[float] = [1.0, 0.8, 0.55, 0.55, 0.95, 1.0, 1.0]
## Depth fog: starts at FOG_BEGIN and is opaque at FOG_END. Nights are closer.
const FOG_BEGIN: Array[float] = [10.0, 18.0, 24.0, 24.0, 18.0, 10.0, 10.0]
const FOG_END: Array[float] = [40.0, 50.0, 60.0, 60.0, 50.0, 40.0, 40.0]

## Time of day in 0..1 (0.5 = noon). apply_time stores the wrapped value here.
@export var time_of_day: float = 0.38

@onready var _sun: DirectionalLight3D = $Sun
@onready var _world_env: WorldEnvironment = $WorldEnvironment
@onready var _clouds: MeshInstance3D = $Clouds


func _ready() -> void:
	apply_time(time_of_day)


func _process(_delta: float) -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return
	var eye: Vector3 = camera.global_position
	_clouds.global_position = Vector3(eye.x, CLOUD_HEIGHT, eye.z)


## Sets every time-dependent value from t (0..1, 0.5 = noon).
func apply_time(t: float) -> void:
	time_of_day = fposmod(t, 1.0)
	var seg: int = _segment(time_of_day)
	var r: float = _blend(seg, time_of_day)

	var top: Color = _sample_color(SKY_TOP, seg, r)
	var horizon: Color = _sample_color(SKY_HORIZON, seg, r)
	var sun_color: Color = _sample_color(SUN_COLOR, seg, r)
	var sun_energy: float = lerpf(SUN_ENERGY[seg], SUN_ENERGY[seg + 1], r)

	# Light travels from the sun towards the ground; the sun rises at SUNRISE_TIME.
	var angle: float = TAU * (time_of_day - SUNRISE_TIME)
	var light_dir := Vector3(
		-cos(angle) * cos(SUN_AZIMUTH), -sin(angle), -cos(angle) * sin(SUN_AZIMUTH)
	)
	_sun.rotation = Vector3(
		asin(clampf(light_dir.y, -1.0, 1.0)), atan2(-light_dir.x, -light_dir.z), 0.0
	)
	_sun.light_color = sun_color
	_sun.light_energy = sun_energy

	var env: Environment = _world_env.environment
	var sky_material: ProceduralSkyMaterial = env.sky.sky_material as ProceduralSkyMaterial
	sky_material.sky_top_color = top
	sky_material.sky_horizon_color = horizon
	sky_material.ground_horizon_color = _sample_color(GROUND_HORIZON, seg, r)
	env.fog_light_color = horizon
	env.fog_depth_begin = lerpf(FOG_BEGIN[seg], FOG_BEGIN[seg + 1], r)
	env.fog_depth_end = lerpf(FOG_END[seg], FOG_END[seg + 1], r)
	env.ambient_light_color = horizon.lerp(top, AMBIENT_MIX_TO_TOP)
	env.ambient_light_energy = lerpf(AMBIENT_ENERGY[seg], AMBIENT_ENERGY[seg + 1], r)

	var cloud_material: ShaderMaterial = _clouds.material_override as ShaderMaterial
	cloud_material.set_shader_parameter("cloud_tint", _sample_color(CLOUD_TINT, seg, r))


## Index of the keyframe interval [KEY_TIMES[i], KEY_TIMES[i + 1]] that holds t.
func _segment(t: float) -> int:
	for i: int in KEY_TIMES.size() - 1:
		if t <= KEY_TIMES[i + 1]:
			return i
	return KEY_TIMES.size() - 2


## Eased position of t inside its interval, 0..1.
func _blend(seg: int, t: float) -> float:
	var span: float = KEY_TIMES[seg + 1] - KEY_TIMES[seg]
	var linear: float = clampf((t - KEY_TIMES[seg]) / span, 0.0, 1.0)
	return smoothstep(0.0, 1.0, linear)


func _sample_color(table: Array[Color], seg: int, r: float) -> Color:
	return table[seg].lerp(table[seg + 1], r)
