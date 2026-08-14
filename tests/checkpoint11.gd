extends SceneTree
## Part 11 checkpoint: battle ends the moment one faction is wiped out.
## Surviving units (including warbands mid-march, whose march bypasses the
## combat state machine) must come to a full stop, and the battle manager
## must reach VICTORY.

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
	bm.spawn_unit(militia, 0, Vector3(0, 0, -10))
	bm.spawn_unit(militia, 0, Vector3(-3, 0, -8))
	bm.spawn_unit(militia, 1, Vector3(0, 0, 10))
	await create_timer(0.2).timeout
	var red: Array = bm.get_faction(0).units
	var blue: Array = bm.get_faction(1).units
	check(red.size() == 2 and blue.size() == 1, "two red units and one blue unit spawned")

	var marcher = red[0]
	marcher.start_march(Vector3(0, 0, -200), true, Vector3.ZERO)
	check(marcher.is_marching(), "red unit set to march to waypoint")

	var ended := []
	bm.battle_ended.connect(func(w): ended.append(w))
	check(bm.request_countdown(), "battle starts")
	check(bm.current_state == bm.BattleState.BATTLE, "state is BATTLE")

	blue[0].take_damage(99999.0, red[1])
	await create_timer(0.6).timeout

	check(bm.current_state == bm.BattleState.VICTORY, "state reaches VICTORY after wipe")
	check(ended.size() == 1 and ended[0] == 0, "battle_ended emitted with red as winner")
	check(not marcher.is_marching(), "marching unit released from march")
	check(marcher.velocity.length() < 0.01, "surviving unit velocity zeroed")
	var before: Vector3 = marcher.global_position
	await create_timer(0.5).timeout
	check(marcher.global_position.distance_to(before) < 0.01, "surviving unit stays frozen in place")
	var stats: Dictionary = bm.get_battle_stats()
	var red_stats: Dictionary = stats.factions[0]
	check(red_stats.alive > 0 and stats.factions[1].alive == 0, "result stats reflect one survivor faction")

	scene.queue_free()
	await create_timer(0.4).timeout
	_finish()

func _finish() -> void:
	print("CHECKPOINT11 RESULT pass=%d fail=%d" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
