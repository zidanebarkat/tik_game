extends SceneTree
## Part 1 checkpoint: spectator camera core (manual toggle + follow + death switch).

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
	bm.start_game()
	var militia = load("res://units/resources/militia.tres")
	var knight = load("res://units/resources/knight.tres")
	bm.spawn_unit(militia, 0, Vector3(0, 0, -10))
	bm.spawn_unit(knight, 1, Vector3(0, 0, 10))
	await create_timer(0.2).timeout
	var rts_cam = scene.get_node("RTSCamera")
	check(sc.main_camera != null, "spectator camera bound to RTS camera")
	check(not sc.is_spectating(), "spectator idle by default")
	sc._toggle_on()
	check(sc.is_spectating(), "manual toggle starts spectating")
	var t = sc.get_current_target()
	check(t != null, "spectating a target")
	if t:
		var cfg: Dictionary = sc.CAMERA_CONFIG.get(t.get_unit_type(), {})
		var expect: float = cfg.get("distance", -1.0)
		check(is_equal_approx(sc.spring.spring_length, expect), "camera config applied per unit type")
	check(sc.camera.current, "spectator camera is current")
	check(not rts_cam.current, "RTS camera released while spectating")
	if t:
		t.take_damage(9999.0)
		await create_timer(2.0).timeout
		check(sc.is_spectating(), "still spectating after target death")
		var cur = sc.get_current_target()
		check(cur != null and cur != t, "auto-switched away from dead target")
		check(reg.is_eligible(cur), "new target is spectate-eligible")
	sc._toggle_off()
	check(not sc.is_spectating(), "toggle off stops spectating")
	check(rts_cam.current, "RTS camera restored")
	scene.queue_free()
	await create_timer(0.4).timeout
	_finish()

func _finish() -> void:
	print("CHECKPOINT1 RESULT pass=%d fail=%d" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
