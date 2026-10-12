class_name Player
extends CharacterBody3D
## Player body: walk, sprint, jump, fly and mouse-look. Reads input only through InputMap actions.

const WALK_SPEED: float = 4.3
const SPRINT_SPEED: float = 5.6
const JUMP_VELOCITY: float = 8.0
const GRAVITY: float = 25.0
const FLY_SPEED: float = 10.0
const PITCH_LIMIT: float = 1.5533430342749532  # 89 degrees in radians

@export var active: bool = true:
	set(value):
		active = value
		_apply_active()

var _pitch: float = 0.0
var _flying: bool = false

@onready var _camera: Camera3D = $Camera


func _ready() -> void:
	_apply_active()


func _apply_active() -> void:
	# Gameplay starts when the player becomes active: take the camera and capture the mouse.
	if active and is_node_ready():
		_camera.make_current()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		rotate_y(-motion.relative.x * Settings.mouse_sensitivity)
		_pitch = clampf(
			_pitch - motion.relative.y * Settings.mouse_sensitivity, -PITCH_LIMIT, PITCH_LIMIT
		)
		_camera.rotation.x = _pitch
	elif event.is_action_pressed("menu"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event.is_action_pressed("attack") and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed("toggle_fly"):
		_flying = not _flying
		velocity.y = 0.0


func _physics_process(delta: float) -> void:
	if not active:
		return
	var input_dir: Vector2 = Input.get_vector(
		"move_left", "move_right", "move_forward", "move_back"
	)
	var direction: Vector3 = global_transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)
	direction = direction.normalized()
	if _flying:
		var vertical: float = 0.0
		if Input.is_action_pressed("jump"):
			vertical += 1.0
		if Input.is_action_pressed("dodge"):
			vertical -= 1.0
		velocity = Vector3(direction.x * FLY_SPEED, vertical * FLY_SPEED, direction.z * FLY_SPEED)
	else:
		var speed: float = SPRINT_SPEED if Input.is_action_pressed("sprint") else WALK_SPEED
		if not is_on_floor():
			velocity.y -= GRAVITY * delta
		elif Input.is_action_pressed("jump"):
			velocity.y = JUMP_VELOCITY
		else:
			velocity.y = 0.0
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	move_and_slide()
