extends SceneTree
## Part 12 checkpoint: gift-triggered super strike (execute ultimate).
## Auto-targets the densest enemy cluster, telegraphs, then instant-kills every
## enemy inside the blast via execute_kill() — HP/armor bypassed, Titans die —
## while anything outside the radius (friend or far enemy) survives. A short
## lockout prevents back-to-back gifts from stacking detonations.

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
	await create_timer(0.3).timeout
	var bm = scene.get_node("BattleManager")
	bm.start_game()
	var militia = load("res://units/resources/militia.tres")
	bm.spawn_unit(militia, 0, Vector3(-60, 0, -60), "", { "force_position": Vector3(-60, 0, -60) })
	for p in [Vector3(0, 0, 0), Vector3(1.5, 0, 0), Vector3(-1.5, 0, 0),
			Vector3(0, 0, 1.5), Vector3(0, 0, -1.5)]:
		bm.spawn_unit(militia, 1, p, "", { "force_position": p })
	bm.spawn_unit(militia, 1, Vector3(60, 0, 60), "", { "force_position": Vector3(60, 0, 60) })
	await create_timer(0.3).timeout
	var red: Array = bm.get_faction(0).units
	var blue: Array = bm.get_faction(1).units.duplicate()
	check(red.size() == 1 and blue.size() == 6, "one red and six blue units spawned")

	var sp = scene.get_node("SuperPower")
	check(sp != null and sp.is_available(), "super power ready before trigger")

	var fired = sp.trigger_super(1)
	check(fired, "super power fired on the blue cluster")
	check(not sp.is_available(), "super power on lockout right after trigger")

	await create_timer(1.4).timeout

	var killed := 0
	for u in blue:
		if is_instance_valid(u) and u.current_health <= 0.0 and u.is_executed:
			killed += 1
	check(killed == 5, "all 5 clustered blues executed (%d/5)" % killed)
	check(is_instance_valid(blue[5]) and blue[5].current_health > 0.0, "far blue outside blast survives")
	check(is_instance_valid(red[0]) and red[0].current_health > 0.0, "red unit (friendly side) survives")
	check(sp._telegraph_nodes.is_empty(), "telegraph VFX cleaned up after detonation")

	await create_timer(0.6).timeout
	check(not sp.is_available(), "lockout still active shortly after strike")

	scene.queue_free()
	await create_timer(0.4).timeout
	_finish()

func _finish() -> void:
	print("CHECKPOINT12 RESULT pass=%d fail=%d" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
