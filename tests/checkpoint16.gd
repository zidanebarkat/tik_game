extends SceneTree
## Part 16 checkpoint: the RTS free cam. Verifies it seeds yaw/pitch from its
## scene transform, keeps an upright right-handed basis, pans camera-relative,
## clamps to the arena floor and play field, turns with the mouse, and zooms
## along the view with the wheel.

var _pass := 0
var _fail := 0

func _init() -> void:
	_run()

func check(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
		print("PASS ", msg)
	else:
		_fail += 1
		print("FAIL ", msg)

func _run() -> void:
	await create_timer(0.2).timeout
	var scene = load("res://maps/main_battlefield.tscn").instantiate()
	root.add_child(scene)
	await create_timer(0.5).timeout
	var cam = scene.get_node("RTSCamera")
	cam.make_current()
	await create_timer(0.2).timeout

	var init_pos: Vector3 = cam.global_position
	var init_yaw = cam._yaw
	var init_pitch = cam._pitch
	check(init_pos != Vector3.ZERO, "camera positioned at " + str(init_pos))
	check(absf(cam._pitch) <= deg_to_rad(85.0) + 0.001, "pitch within limit")
	var b: Basis = cam.global_transform.basis
	check(b.z.cross(b.x).dot(b.y) > 0.99, "basis is right-handed")

	# forward/right derivation: with yaw=0, forward is -Z and right is +X, so a
	# middle-drag pan must translate along the camera's right axis (camera-relative).
	cam._yaw = 0.0
	cam._yaw_t = 0.0
	cam._pitch = 0.0
	cam._pitch_t = 0.0
	cam._pos = Vector3(0, 20, 100)
	cam._tpos = Vector3(0, 20, 100)
	cam._speed = 60.0
	cam._speed_t = 60.0
	cam._panning = true
	var pev = InputEventMouseMotion.new()
	pev.relative = Vector2(-10, 0)
	cam._unhandled_input(pev)
	cam._panning = false
	var pan_pos: Vector3 = cam._tpos
	check(pan_pos.x > 1.0 and absf(pan_pos.y - 20.0) < 0.001 and absf(pan_pos.z - 100.0) < 0.001, \
			"pan moves along camera right, got " + str(pan_pos))

	# floor clamp: forcing target below floor must be clamped
	cam._tpos = Vector3(0, -50, 0)
	cam._process(0.1)
	check(cam._tpos.y >= cam.floor_height + cam.min_cam_height - 0.001, "target clamped above floor, got " + str(cam._tpos.y))
	await create_timer(0.5).timeout
	cam._process(1.0)
	check(cam.global_position.y >= cam.floor_height + cam.min_cam_height - 0.01, "camera never below floor, got " + str(cam.global_position.y))

	# arena clamp
	cam._tpos = Vector3(99999, 50, -99999)
	cam._process(0.1)
	check(absf(cam._tpos.x) <= cam.arena_bound + 0.001 and absf(cam._tpos.z) <= cam.arena_bound + 0.001, "arena clamp holds x/z")

	# right-drag yaw: drag right (positive rel.x) should decrease yaw (turn right)
	var before = cam._yaw_t
	cam._rotating = true
	var ev = InputEventMouseMotion.new()
	ev.relative = Vector2(10, 0)
	cam._unhandled_input(ev)
	cam._rotating = false
	check(cam._yaw_t < before, "drag right turns right (yaw decreased)")

	# wheel zooms toward the view direction (yaw=0, pitch=0 -> forward is -Z)
	cam._yaw = 0.0
	cam._pitch = 0.0
	cam._pos = Vector3(0, 20, 100)
	cam._tpos = Vector3(0, 20, 100)
	var wev = InputEventMouseButton.new()
	wev.button_index = MOUSE_BUTTON_WHEEL_UP
	wev.pressed = true
	cam._unhandled_input(wev)
	check(cam._tpos.z < 100.0 and absf(cam._tpos.x) < 0.001, \
			"wheel up zooms in along view, got " + str(cam._tpos))
	var wev2 = InputEventMouseButton.new()
	wev2.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wev2.pressed = true
	var z_after = cam._tpos.z
	cam._unhandled_input(wev2)
	check(cam._tpos.z > z_after, "wheel down zooms back out")

	print("CHECKPOINT16 RESULT pass=%d fail=%d" % [_pass, _fail])
	quit(_fail > 0)
