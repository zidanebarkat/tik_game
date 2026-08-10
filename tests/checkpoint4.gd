extends SceneTree
## Part 4 checkpoint: gift -> commander spawn, tier routing, concurrent-commander cap + queue.

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
	var gift_mgr = scene.get_node("GiftManager")
	var cm = RegistryAccess.get_commander_manager()
	bm.start_game()
	var militia = load("res://units/resources/militia.tres")
	var knight = load("res://units/resources/knight.tres")
	for i in range(10):
		bm.spawn_unit(militia, 0, Vector3(randf_range(-20, 20), 0, randf_range(-30, -10)))
	for i in range(10):
		bm.spawn_unit(knight, 1, Vector3(randf_range(-20, 20), 0, randf_range(10, 30)))
	bm.request_countdown()
	await create_timer(0.2).timeout
	check(gift_mgr.gift_map.size() >= 12, "gift map loaded (%d gifts)" % gift_mgr.gift_map.size())
	check(str(gift_mgr.gift_map.get("Galaxy", {}).get("commander_tier", "")) == "bronze", "Galaxy -> bronze tier")
	check(str(gift_mgr.gift_map.get("Rocket", {}).get("commander_tier", "")) == "silver", "Rocket -> silver tier")
	check(str(gift_mgr.gift_map.get("Universe", {}).get("commander_tier", "")) == "gold", "Universe -> gold tier")
	check(int(gift_mgr.gift_map.get("Galaxy", {}).get("value", 0)) == 20, "Galaxy gift value 20")
	check(int(gift_mgr.gift_map.get("Universe", {}).get("value", 0)) == 500, "Universe gift value 500")

	gift_mgr.process_gift("Galaxy", "senderA", 1, "uidA")
	gift_mgr.process_gift("Rocket", "senderB", 1, "uidB")
	gift_mgr.process_gift("Universe", "senderC", 1, "uidC")
	await create_timer(0.5).timeout
	check(reg.get_alive_commanders().size() == 3, "three commander warbands spawned (cap reached)")

	gift_mgr.process_gift("Galaxy", "senderD", 1, "uidD")
	await create_timer(0.3).timeout
	check(cm.pending_events.size() >= 1, "4th gift queued at cap")
	check(reg.get_alive_commanders().size() == 3, "cap respected: still 3 active")

	var victim = reg.get_alive_commanders()[0] if reg.get_alive_commanders().size() > 0 else null
	if victim:
		victim.take_damage(9999.0)
	await create_timer(2.0).timeout
	check(reg.get_alive_commanders().size() == 3, "slot freed -> queued warband issued")
	check(cm.pending_events.size() == 0, "queue drained")

	gift_mgr.process_gift("Rose", "senderE", 1, "uidE")
	await create_timer(0.5).timeout
	var rosters: Array = reg.get_alive_by_type("knight")
	check(rosters.size() >= 8, "unit-tier gift routed to spawn (Rose -> knight)")
	scene.queue_free()
	await create_timer(0.4).timeout
	_finish()

func _finish() -> void:
	print("CHECKPOINT4 RESULT pass=%d fail=%d" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
