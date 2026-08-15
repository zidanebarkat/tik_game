extends Camera3D
## Free fly camera (the RTS default cam). Full 6-DOF flight like a 3rd-person
## free cam, with damped smooth movement and safe clamps.
##
##   WASD / arrows : move forward / back / strafe relative to where you look
##   Q / E         : descend / ascend
##   Right-drag    : look around (free yaw + pitch, not orbit-locked)
##   Middle-drag   : pan (translate without turning)
##   Mouse wheel   : raise / lower travel speed
##
## Movement glides toward its targets (exponential smoothing), and the camera
## can never sink below the arena floor or drift off the play field.

@export var move_speed: float = 60.0     # travel speed at 1x (units / s)
@export var rotate_speed: float = 0.22   # look-around sensitivity (degrees / px)
@export var min_speed: float = 4.0       # slowest the scroll wheel can go
@export var max_speed: float = 400.0     # fastest the scroll wheel can go
@export var floor_height: float = 0.0    # arena floor Y (camera stays above it)
@export var min_cam_height: float = 2.0  # how close the camera may get to the floor
@export var arena_bound: float = 700.0   # +/- X/Z play-field clamp

const POS_SMOOTH := 9.0
const ROT_SMOOTH := 14.0
const SPEED_SMOOTH := 5.0
const PITCH_LIMIT_DEG := 85.0
const WHEEL_STEP := 1.18
const PAN_SCALE := 0.12

const MOVE_KEYS := [
	KEY_W, KEY_A, KEY_S, KEY_D,
	KEY_Q, KEY_E,
	KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT,
]

var _yaw := 0.0
var _yaw_t := 0.0
var _pitch := 0.0
var _pitch_t := 0.0
var _pos := Vector3.ZERO
var _tpos := Vector3.ZERO
var _speed := 60.0
var _speed_t := 60.0
var _rotating := false
var _panning := false

func _ready() -> void:
	_speed = move_speed
	_speed_t = move_speed
	_pos = global_position
	_tpos = global_position
	_sync_from_transform()
	_sync_basis()
	global_position = _pos

## Seed yaw / pitch from wherever the scene placed the camera so the first
## frame frames the arena instead of snapping to a canned angle.
func _sync_from_transform() -> void:
	var fwd := -global_transform.basis.z
	_yaw = atan2(-fwd.x, -fwd.z)
	_pitch = asin(clampf(fwd.y, -1.0, 1.0))
	_yaw_t = _yaw
	_pitch_t = _pitch

## Swallow the movement keys while the free cam is active so the debug
## test-spawn hotkeys (WASD/Q/E in main_battlefield) don't fire at the same
## time. Accepted here in _input because that phase runs before _unhandled_input.
func _input(event: InputEvent) -> void:
	if not is_current() or not (event is InputEventKey and event.pressed):
		return
	if MOVE_KEYS.has(event.keycode):
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if not is_current():
		return
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed:
					_speed_t = clampf(_speed_t * WHEEL_STEP, min_speed, max_speed)
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					_speed_t = clampf(_speed_t / WHEEL_STEP, min_speed, max_speed)
			MOUSE_BUTTON_RIGHT:
				_rotating = event.pressed
			MOUSE_BUTTON_MIDDLE:
				_panning = event.pressed
	if event is InputEventMouseMotion:
		var rad := deg_to_rad(rotate_speed)
		if _rotating:
			_yaw_t -= event.relative.x * rad
			_pitch_t = clampf(
				_pitch_t + event.relative.y * rad,
				-deg_to_rad(PITCH_LIMIT_DEG),
				deg_to_rad(PITCH_LIMIT_DEG)
			)
		if _panning:
			var rgt := Vector3(cos(_yaw), 0.0, -sin(_yaw))
			var k := PAN_SCALE * _speed / maxf(move_speed, 1.0)
			_tpos += rgt * (-event.relative.x * k)
			_tpos.y += event.relative.y * k
			_clamp_target()

func _process(delta: float) -> void:
	var dir := Vector3.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		dir.z -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		dir.z += 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		dir.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		dir.x += 1.0
	if Input.is_key_pressed(KEY_E):
		dir.y += 1.0
	if Input.is_key_pressed(KEY_Q):
		dir.y -= 1.0
	if not dir.is_zero_approx():
		var fwd := Vector3(-sin(_yaw), 0.0, -cos(_yaw))
		var rgt := Vector3(cos(_yaw), 0.0, -sin(_yaw))
		var move := (fwd * -dir.z + rgt * dir.x + Vector3.UP * dir.y).normalized()
		_tpos += move * _speed * delta
	_clamp_target()

	_speed = lerpf(_speed, _speed_t, 1.0 - exp(-SPEED_SMOOTH * delta))
	_pos = _pos.lerp(_tpos, 1.0 - exp(-POS_SMOOTH * delta))
	_yaw = lerp_angle(_yaw, _yaw_t, 1.0 - exp(-ROT_SMOOTH * delta))
	_pitch = lerp_angle(_pitch, _pitch_t, 1.0 - exp(-ROT_SMOOTH * delta))

	# Snap when the dampers have settled so an idle camera holds perfectly still.
	if _tpos.distance_squared_to(_pos) < 0.0001:
		_pos = _tpos
	if absf(angle_difference(_yaw, _yaw_t)) < 0.0002:
		_yaw = _yaw_t
	if absf(angle_difference(_pitch, _pitch_t)) < 0.0002:
		_pitch = _pitch_t

	_pos.y = maxf(_pos.y, floor_height + min_cam_height)
	_sync_basis()
	global_position = _pos

func _clamp_target() -> void:
	_tpos.y = maxf(_tpos.y, floor_height + min_cam_height)
	_tpos.x = clampf(_tpos.x, -arena_bound, arena_bound)
	_tpos.z = clampf(_tpos.z, -arena_bound, arena_bound)

## Build an orthonormal yaw + pitch basis (no roll) so the view always sits
## upright and never tips sideways.
func _sync_basis() -> void:
	var cp := cos(_pitch)
	var back := Vector3(sin(_yaw) * cp, -sin(_pitch), cos(_yaw) * cp)
	var rgt := Vector3(cos(_yaw), 0.0, -sin(_yaw))
	var up := back.cross(rgt)
	global_transform.basis = Basis(rgt, up, back)
