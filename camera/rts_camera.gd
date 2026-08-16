extends Camera3D
## Free fly camera (the RTS default cam). Full 6-DOF flight like a 3rd-person
## free cam, with damped smooth movement and safe clamps.
##
##   WASD / arrows : move forward / back / strafe relative to where you look
##   Q / E         : descend / ascend (PageDown / PageUp also work)
##   Left or right mouse-drag : look around — free yaw (360 deg) + pitch
##   Middle-drag   : pan (translate without turning)
##   Mouse wheel   : zoom in / out along your view direction
##   Shift / Ctrl  : fly 2.5x faster / 0.4x slower
##
## Movement glides toward its targets (exponential smoothing), and the camera
## can never sink below the arena floor or drift off the play field. Controls
## stay live even when another camera (battle overview / spectator) is showing.

@export var move_speed: float = 60.0     # travel speed at 1x (units / s)
@export var rotate_speed: float = 0.22   # look-around sensitivity (degrees / px)
@export var floor_height: float = 0.0    # arena floor Y (camera stays above it)
@export var min_cam_height: float = 2.0  # how close the camera may get to the floor
@export var max_cam_height: float = 500.0
@export var arena_bound: float = 700.0   # +/- X/Z play-field clamp

const POS_SMOOTH := 9.0
const ROT_SMOOTH := 14.0
const SPEED_SMOOTH := 5.0
const PITCH_LIMIT_DEG := 89.0
const ZOOM_STEP := 0.12
const PAN_SCALE := 0.12
const FAST_MULT := 2.5
const SLOW_MULT := 0.4

const MOVE_KEYS := [
	KEY_W, KEY_A, KEY_S, KEY_D,
	KEY_Q, KEY_E,
	KEY_PAGEUP, KEY_PAGEDOWN,
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
var _home_pos := Vector3.ZERO
var _home_basis := Basis()

func _ready() -> void:
	_home_pos = transform.origin
	_home_basis = transform.basis
	_speed = move_speed
	_speed_t = move_speed
	_pos = global_position
	_tpos = global_position
	_sync_from_transform()
	_sync_basis()
	global_position = _pos

## Snap the free cam back to its scene-defined drone home and make it current.
## Used when returning to the menu so the next round starts from the classic
## high overview instead of wherever the user flew during the last fight.
func reset_to_home() -> void:
	transform = Transform3D(_home_basis, _home_pos)
	_sync_from_transform()
	_sync_basis()
	_pos = _home_pos
	_tpos = _home_pos
	global_position = _pos
	make_current()

## Seed yaw / pitch from wherever the scene placed the camera so the first
## frame frames the arena instead of snapping to a canned angle.
func _sync_from_transform() -> void:
	var fwd := -global_transform.basis.z
	_yaw = atan2(-fwd.x, -fwd.z)
	_pitch = asin(clampf(fwd.y, -1.0, 1.0))
	_yaw_t = _yaw
	_pitch_t = _pitch

## Swallow the movement keys so the debug test-spawn hotkeys (WASD/Q/E in
## main_battlefield) can't fire at the same time. Accepted here in _input
## because that phase runs before _unhandled_input. Always on, so the cam
## stays responsive in any camera mode.
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and MOVE_KEYS.has(event.keycode):
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed:
					_tpos += _view_forward() * (ZOOM_STEP * _speed)
					_clamp_target()
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					_tpos -= _view_forward() * (ZOOM_STEP * _speed)
					_clamp_target()
			MOUSE_BUTTON_RIGHT:
				_rotating = event.pressed
			MOUSE_BUTTON_LEFT:
				_rotating = event.pressed
			MOUSE_BUTTON_MIDDLE:
				_panning = event.pressed
	if event is InputEventMouseMotion:
		var rad := deg_to_rad(rotate_speed)
		if _rotating:
			_yaw_t -= event.relative.x * rad
			_pitch_t = clampf(
				_pitch_t - event.relative.y * rad,
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
	if Input.is_key_pressed(KEY_E) or Input.is_key_pressed(KEY_PAGEUP):
		dir.y += 1.0
	if Input.is_key_pressed(KEY_Q) or Input.is_key_pressed(KEY_PAGEDOWN):
		dir.y -= 1.0
	if not dir.is_zero_approx():
		var fwd := Vector3(-sin(_yaw), 0.0, -cos(_yaw))
		var rgt := Vector3(cos(_yaw), 0.0, -sin(_yaw))
		var move := (fwd * -dir.z + rgt * dir.x + Vector3.UP * dir.y).normalized()
		var speed := _speed
		if Input.is_key_pressed(KEY_SHIFT):
			speed *= FAST_MULT
		elif Input.is_key_pressed(KEY_CTRL):
			speed *= SLOW_MULT
		_tpos += move * speed * delta
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
	_tpos.y = clampf(_tpos.y, floor_height + min_cam_height, max_cam_height)
	_tpos.x = clampf(_tpos.x, -arena_bound, arena_bound)
	_tpos.z = clampf(_tpos.z, -arena_bound, arena_bound)

## Current looking direction (pitch included) — used by wheel zoom.
func _view_forward() -> Vector3:
	var cp := cos(_pitch)
	return Vector3(-sin(_yaw) * cp, sin(_pitch), -cos(_yaw) * cp)

## Build an orthonormal yaw + pitch basis (no roll) so the view always sits
## upright and never tips sideways.
func _sync_basis() -> void:
	var cp := cos(_pitch)
	var back := Vector3(sin(_yaw) * cp, -sin(_pitch), cos(_yaw) * cp)
	var rgt := Vector3(cos(_yaw), 0.0, -sin(_yaw))
	var up := back.cross(rgt)
	global_transform.basis = Basis(rgt, up, back)
