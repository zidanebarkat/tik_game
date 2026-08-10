extends SceneTree
## Part 10 checkpoint: 50 mixed gifts through the pipeline, leaderboard, cap, leak check.

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
	var eng = RegistryAccess.get_engagement()
	bm.start_game()
	var militia = load("res://units/resources/militia.tres")
	var knight = load("res://units/resources/knight.tres")
	for i in range(40):
		bm.spawn_unit(militia, 0, Vector3(randf_range(-20, 20), 0, randf_range(-30, -10)))
	for i in range(40):
		bm.spawn_unit(knight, 1, Vector3(randf_range(-20, 20), 0, randf_range(10, 30)))
	bm.request_countdown()
	await create_timer(0.2).timeout
	check(gift_mgr.gift_map.size() >= 12, "gift map loaded (%d gifts)" % gift_mgr.gift_map.size())

	var gift_names := ["Galaxy", "Rocket", "Universe", "Share", "Rose", "Phoenix", "Lion", "Tiger", "Heart", "Skull", "Dragon", "Castle"]
	var viewers := 12
	var mem0 := OS.get_static_memory_usage()
	for i in range(50):
		var gift: String = gift_names[i % gift_names.size()]
		var viewer := "viewer%02d" % (i % viewers)
		gift_mgr.process_gift(gift, "sender " + viewer, 1, viewer)
	await create_timer(2.0).timeout
	var cmdr_count: int = reg.get_alive_commanders().size()
	check(cmdr_count > 0 and cmdr_count <= 3, "commander cap respected (active=%d)" % cmdr_count)
	check(cm.pending_events.size() <= 12, "overflow commanders queued, none lost (queue=%d)" % cm.pending_events.size())

	var lb: Array = eng.get_leaderboard(3)
	check(lb.size() == 3, "leaderboard has 3 entries")
	if lb.size() >= 3:
		check(float(lb[0].spend) >= float(lb[1].spend), "leaderboard sorted desc (1>=2)")
		check(float(lb[1].spend) >= float(lb[2].spend), "leaderboard sorted desc (2>=3)")
	var total_spend := 0.0
	for i in range(50):
		var gift: String = gift_names[i % gift_names.size()]
		total_spend += float(gift_mgr.gift_map[gift].value)
	check(float(lb[0].spend) + float(lb[1].spend) + float(lb[2].spend) <= total_spend + 0.5, "leaderboard spends within total")
	var any_title := false
	for i in range(viewers):
		if str(eng.get_title("viewer%02d" % i)) != "":
			any_title = true
	check(any_title, "commander gifters earned titles (Baron/Warlord/King)")

	scene.queue_free()
	await create_timer(0.4).timeout
	var mem1 := OS.get_static_memory_usage()
	var delta_mem := (mem1 - mem0) / (1024.0 * 1024.0)
	check(delta_mem < 32.0, "static memory delta %.1fMB < 32MB" % delta_mem)
	check(reg.get_alive_count() == 0, "registry clean after teardown")
	_finish()

func _finish() -> void:
	print("CHECKPOINT10 RESULT pass=%d fail=%d" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
