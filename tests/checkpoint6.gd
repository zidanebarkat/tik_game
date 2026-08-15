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
	var director = scene.get_node("DirectorCam")
	check(director != null and director.is_active(), "director auto-follow active during battle")
	var rts = scene.get_node("RTSCamera")
	if c:
		c.march_speed = 60.0
	# wait for the march to finish: the director should cut to an ARRIVAL shot
	var t := 0.0
	while t < 4.0 and director._mode != director.MODE.ARRIVAL:
		await create_timer(0.1).timeout
		t += 0.1
	check(director._mode == director.MODE.ARRIVAL, "director cuts to ARRIVAL on warband arrival")
	check(not rts.is_current(), "RTS camera released during arrival shot")
	# the auto-follower keeps following the fight; no manual return mid-battle
	await create_timer(1.0).timeout
	check(director.is_active(), "director keeps following the fight after arrival")

	sc._toggle_on()
	await create_timer(0.1).timeout
	check(sc.is_spectating(), "spectating viewer engaged")
	check(not director.is_active(), "director yields to manual spectate mode")
	cm.debug_spawn("bronze", "CamCheck2", "cam2")
	await create_timer(0.4).timeout
	check(not director.is_active(), "no director cut while viewer spectates")
	check(sc.is_spectating(), "viewer spectating uninterrupted")
	sc._toggle_off()
	scene.queue_free()
	await create_timer(0.4).timeout
	_finish()

func _finish() -> void:
	print("CHECKPOINT6 RESULT pass=%d fail=%d" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
