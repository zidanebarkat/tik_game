extends SceneTree
## Part 14 checkpoint: commander warbands spawn on the GIFTER'S team, not a
## hardcoded side. Blue-viewer commander gifts must raise the blue faction and
## red-viewer gifts the red faction; nobody's warband may leak to the other side.

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

func _has_commander(faction, viewer_id: String) -> bool:
	for u in faction.units:
		if is_instance_valid(u) and str(u.commander_id) == viewer_id:
			return true
	return false

func _run() -> void:
	await create_timer(0.2).timeout
	var scene = load("res://maps/main_battlefield.tscn").instantiate()
	root.add_child(scene)
	await create_timer(0.3).timeout
	var bm = scene.get_node("BattleManager")
	var gift_mgr = scene.get_node("GiftManager")
	var team_mgr = scene.get_node("TeamManager")
	var militia = load("res://units/resources/militia.tres")
	bm.start_game()
	bm.spawn_unit(militia, 0, Vector3(-60, 0, -60), "", { "force_position": Vector3(-60, 0, -60) })
	bm.spawn_unit(militia, 1, Vector3(60, 0, 60), "", { "force_position": Vector3(60, 0, 60) })

	team_mgr.assign_team("blue_gifter", 1)
	team_mgr.assign_team("red_gifter", 0)

	# Gifts land while IDLE (battle not live) -> FIFO queued, issued on BATTLE.
	gift_mgr.process_gift("Galaxy", "BlueFan", 1, "blue_gifter")
	gift_mgr.process_gift("Galaxy", "RedFan", 1, "red_gifter")
	check(bm.get_faction(0).units.size() == 1 and bm.get_faction(1).units.size() == 1,
			"no warbands spawned before battle is live")
	bm.request_countdown()
	await create_timer(1.6).timeout

	var blue_has_cmd: bool = _has_commander(bm.get_faction(1), "blue_gifter")
	var red_has_cmd: bool = _has_commander(bm.get_faction(0), "red_gifter")
	check(blue_has_cmd, "blue viewer's warband raised the blue faction")
	check(red_has_cmd, "red viewer's warband raised the red faction")
	check(not _has_commander(bm.get_faction(0), "blue_gifter"), "blue warband did NOT leak to red")
	check(not _has_commander(bm.get_faction(1), "red_gifter"), "red warband did NOT leak to blue")
	check(bm.get_faction(1).units.size() > 1, "blue warband is a full squad (%d units)" % bm.get_faction(1).units.size())

	scene.queue_free()
	await create_timer(0.4).timeout
	_finish()

func _finish() -> void:
	print("CHECKPOINT14 RESULT pass=%d fail=%d" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
