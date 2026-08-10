extends SceneTree
## Part 2 checkpoint: weighted spectate selection favors bigger units + no stuck camera.

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
	bm.start_game()
	var militia = load("res://units/resources/militia.tres")
	var titan = load("res://units/resources/titan.tres")
	for i in range(100):
		bm.spawn_unit(militia, 0, Vector3(randf_range(-20, 20), 0, randf_range(-30, -10)))
	for i in range(10):
		bm.spawn_unit(titan, 1, Vector3(randf_range(-20, 20), 0, randf_range(10, 30)))
	await create_timer(0.3).timeout
	check(reg.get_alive_count() == 110, "all 110 units registered")
	var invalid := 0
	var titan_picks := 0
	for i in range(2000):
		var p = reg.pick_spectate_target()
		if p == null or not reg.is_eligible(p):
			invalid += 1
		elif p.get_unit_type() == "titan":
			titan_picks += 1
	check(invalid == 0, "every weighted pick is valid/eligible")
	var frac := float(titan_picks) / 2000.0
	check(frac > 0.12, "titan weighting above uniform (got %.3f)" % frac)
	check(frac < 0.32, "titan weighting within expectation (got %.3f)" % frac)

	var sc = RegistryAccess.get_spectator()
	sc._toggle_on()
	check(sc.is_spectating(), "spectating engaged")
	var first = sc.get_current_target()
	var changed := false
	var stuck := 0
	for i in range(30):
		sc._cycle()
		var cur = sc.get_current_target()
		if cur == null or not reg.is_eligible(cur):
			stuck += 1
		elif cur != first:
			changed = true
	check(stuck == 0, "cycling never targets invalid unit")
	check(changed, "cycling rotates targets")
	sc._toggle_off()
	scene.queue_free()
	await create_timer(0.4).timeout
	_finish()

func _finish() -> void:
	print("CHECKPOINT2 RESULT pass=%d fail=%d" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
