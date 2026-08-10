extends SceneTree
## Part 5 checkpoint: commander arrival sequence (march out, escorted, forward-facing, release).

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
	var reg = RegistryAccess.get_registry()
	var scene = load("res://maps/main_battlefield.tscn").instantiate()
	root.add_child(scene)
	await create_timer(0.3).timeout
	var bm = scene.get_node("BattleManager")
	var cm = RegistryAccess.get_commander_manager()
	var arrived: Array = []
	cm.arrival_finished.connect(func(u): arrived.append(u))
	bm.start_game()
	var militia = load("res://units/resources/militia.tres")
	var knight = load("res://units/resources/knight.tres")
	for i in range(10):
		bm.spawn_unit(militia, 0, Vector3(randf_range(-20, 20), 0, randf_range(-30, -10)))
	for i in range(10):
		bm.spawn_unit(knight, 1, Vector3(randf_range(-20, 20), 0, randf_range(10, 30)))
	bm.request_countdown()
	await create_timer(0.2).timeout
	cm.debug_spawn("silver", "Alice", "alice1")
	await create_timer(0.4).timeout
	var cmdrs = reg.get_alive_commanders()
	check(cmdrs.size() >= 1, "commander warband spawned")
	var c = cmdrs[0] if cmdrs.size() > 0 else null
	check(c != null, "commander unit reference")
	if c == null:
		_finish()
		return
	check(c.display_name == "Alice", "commander display name Alice")
	check(c.march_leader, "commander leads the march")
	check(c.is_marching(), "commander begins arrival march")
	var escorts := 0
	for u in reg.alive_units:
		if u.commander_id == "alice1" and u.get_unit_type() != "commander":
			escorts += 1
	check(escorts >= 6, "escort squad spawned with commander (%d)" % escorts)
	var fwd: Vector3 = -c.global_basis.z
	fwd.y = 0.0
	if fwd.length() > 0.01:
		fwd = fwd.normalized()
		var to_wp: Vector3 = c.reinforce_waypoint - c.global_position
		to_wp.y = 0.0
		if to_wp.length() > 0.01:
			to_wp = to_wp.normalized()
			check(fwd.dot(to_wp) > 0.8, "commander faces forward while marching")
	for i in range(200):
		await create_timer(0.1).timeout
		if not c.is_marching():
			break
	check(not c.is_marching(), "arrival march finished")
	check(arrived.size() >= 1, "arrival_finished emitted")
	scene.queue_free()
	await create_timer(0.4).timeout
	_finish()

func _finish() -> void:
	print("CHECKPOINT5 RESULT pass=%d fail=%d" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
