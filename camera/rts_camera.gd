extends Camera3D

@export var move_speed: float = 40.0
@export var zoom_speed: float = 5.0
@export var rotate_speed: float = 0.003
@export var min_distance: float = 10.0
@export var max_distance: float = 150.0

var _rotation_angle: float = 0.0
var _pitch: float = -38.0
var _distance: float = 75.0
var _target: Vector3 = Vector3.ZERO
var _is_rotating: bool = false
var _is_panning: bool = false

func _ready() -> void:
	_update_camera_transform()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed:
					_distance = max(_distance - zoom_speed, min_distance)
					_update_camera_transform()
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					_distance = min(_distance + zoom_speed, max_distance)
					_update_camera_transform()
			MOUSE_BUTTON_RIGHT:
				_is_rotating = event.pressed
			MOUSE_BUTTON_MIDDLE:
				_is_panning = event.pressed
	if event is InputEventMouseMotion:
		if _is_rotating:
			_rotation_angle -= event.relative.x * rotate_speed
			_pitch = clamp(_pitch - event.relative.y * rotate_speed, -80.0, -10.0)
			_update_camera_transform()
		if _is_panning:
			var right = global_transform.basis.x
			var forward = -global_transform.basis.z
			_target += right * -event.relative.x * 0.1
			_target += forward * -event.relative.y * 0.1
			_update_camera_transform()

func _process(delta: float) -> void:
	var move_dir = Vector3.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		move_dir.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		move_dir.x += 1
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		move_dir.z -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		move_dir.z += 1
	if move_dir.length() > 0:
		var forward = -global_transform.basis.z
		var right = global_transform.basis.x
		_target += (right * move_dir.x + forward * move_dir.z).normalized() * move_speed * delta
		_update_camera_transform()

func _update_camera_transform() -> void:
	var offset = Vector3(0, _distance * sin(-deg_to_rad(_pitch)), _distance * cos(-deg_to_rad(_pitch)))
	offset = offset.rotated(Vector3.UP, _rotation_angle)
	global_position = _target + offset
	look_at(_target, Vector3.UP)
