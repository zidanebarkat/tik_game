extends SceneTree
## Part 9 checkpoint: horde stress + spectate cycling + physics/memory budgets.

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
	var tank = load("res://units/resources/tank.tres")
	for i in range(80):
		bm.spawn_unit(militia, 0, Vector3(randf_range(-20, 20), 0, randf_range(-40, -20)))
	for i in range(80):
		bm.spawn_unit(knight, 1, Vector3(randf_range(-20, 20), 0, randf_range(20, 40)))
	for i in range(8):
		bm.spawn_unit(tank, 0, Vector3(randf_range(-20, 20), 0, randf_range(-45, -25)))
	bm.request_countdown()
	await create_timer(0.3).timeout
	check(reg.get_alive_count() >= 160, "horde spawned (%d alive)" % reg.get_alive_count())
	cm.debug_spawn("silver", "StressSilver", "s9s")
	cm.debug_spawn("gold", "StressGold", "s9g")
	cm.debug_spawn("bronze", "StressBronze", "s9b")
	await create_timer(0.5).timeout
	check(reg.get_alive_commanders().size() == 3, "three commander warbands present")

	sc._toggle_on()
	var stuck := 0
	var first = sc.get_current_target()
	var changed := false
	for i in range(60):
		sc._cycle()
		var cur = sc.get_current_target()
		if cur == null or not is_instance_valid(cur) or cur._dying:
			stuck += 1
		elif cur != first:
			changed = true
		await create_timer(0.5).timeout
	check(stuck == 0, "spectate cycling never sticks to invalid unit")
	check(changed, "spectate cycling rotates through horde")
	check(sc.is_spectating(), "spectator alive after 60 cycles")
	sc._toggle_off()

	var mem0 := OS.get_static_memory_usage()
	var start := Time.get_ticks_usec()
	var last := start
	var frame_count := 0
	var worst := 0.0
	for i in range(90):
		await physics_frame
		frame_count += 1
		var now := Time.get_ticks_usec()
		var dt := (now - last) / 1000.0
		last = now
		if dt > worst:
			worst = dt
	var elapsed := (Time.get_ticks_usec() - start) / 1000.0
	var avg := elapsed / float(frame_count)
	check(avg < 50.0, "avg physics frame %.1fms < 50ms (worst %.1fms)" % [avg, worst])
	var mem1 := OS.get_static_memory_usage()
	var delta_mem := (mem1 - mem0) / (1024.0 * 1024.0)
	check(delta_mem < 32.0, "static memory delta %.1fMB < 32MB" % delta_mem)
	scene.queue_free()
	await create_timer(0.4).timeout
	_finish()

func _finish() -> void:
	print("CHECKPOINT9 RESULT pass=%d fail=%d" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
