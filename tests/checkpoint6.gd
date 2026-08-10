extends SceneTree
## Part 6 checkpoint: arrival camera cut (broadcast) for non-spectating viewers.

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
	var sc = RegistryAccess.get_spectator()
	var reg = RegistryAccess.get_registry()
	var scene = load("res://maps/main_battlefield.tscn").instantiate()
	root.add_child(scene)
	await create_timer(0.3).timeout
	var bm = scene.get_node("BattleManager")
	var cm = RegistryAccess.get_commander_manager()
	bm.start_game()
	var militia = load("res://units/resources/militia.tres")
	var knight = load("res://units/resources/knight.tres")
	for i in range(20):
		bm.spawn_unit(militia, 0, Vector3(randf_range(-20, 20), 0, randf_range(-30, -10)))
	for i in range(20):
		bm.spawn_unit(knight, 1, Vector3(randf_range(-20, 20), 0, randf_range(10, 30)))
	bm.request_countdown()
	await create_timer(0.2).timeout
	check(not sc.is_spectating(), "spectator idle before arrival")
	cm.debug_spawn("silver", "CamCheck", "cam1")
	await create_timer(0.4).timeout
	var cmdrs = reg.get_alive_commanders()
	var c = cmdrs[0] if cmdrs.size() > 0 else null
	check(c != null and c.is_marching(), "commander marching toward field")
	var arr_cam = scene.get_node_or_null("ArrivalCam")
	check(arr_cam != null, "arrival cut camera created on warband spawn")
	if arr_cam:
		check(arr_cam.is_current(), "arrival camera is current for broadcast")
	var rts = scene.get_node("RTSCamera")
	check(not rts.current, "RTS camera released during arrival cut")
	if c:
		c.march_speed = 60.0
	await create_timer(4.0).timeout
	check(rts.is_current(), "arrival cut auto-returned to RTS camera")

	sc._toggle_on()
	check(sc.is_spectating(), "spectating viewer engaged")
	cm.debug_spawn("bronze", "CamCheck2", "cam2")
	await create_timer(0.4).timeout
	arr_cam = scene.get_node_or_null("ArrivalCam")
	check(arr_cam == null or not arr_cam.is_current(), "no arrival cut while viewer spectates")
	check(sc.is_spectating(), "viewer spectating uninterrupted")
	sc._toggle_off()
	scene.queue_free()
	await create_timer(0.4).timeout
	_finish()

func _finish() -> void:
	print("CHECKPOINT6 RESULT pass=%d fail=%d" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
