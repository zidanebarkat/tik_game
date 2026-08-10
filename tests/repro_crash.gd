extends SceneTree
## Minimal crash repro (v2) with clean mode routing.
##
##   godot --headless --path . -s tests/repro_crash.gd -- <mode> <delay_ms>
##
## modes:
##   spawn_fight   : direct spawns, factions interleaved (combat + deaths)
##   spawn_nofight : direct spawns, all units far apart (no combat, no deaths)
##   gift_fight    : gift_manager flood, both factions near each other
##   idle_units    : baseline units present, gift flood, battle stays IDLE

var _mode := "gift_fight"
var _delay_ms := 15

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_mode = args[0]
	if args.size() > 1:
		_delay_ms = maxi(1, int(args[1]))
	print("[repro] mode=%s delay=%dms" % [_mode, _delay_ms])
	_run()

func _run() -> void:
	await create_timer(0.5).timeout
	var scene = load("res://maps/main_battlefield.tscn").instantiate()
	root.add_child(scene)
	await create_timer(1.0).timeout
	var bm = scene.get_node("BattleManager")
	var gift_mgr = scene.get_node("GiftManager")
	var reg = RegistryAccess.get_registry()
	bm.start_game()
	var militia = load("res://units/resources/militia.tres")
	var knight = load("res://units/resources/knight.tres")
	if _mode != "battle_empty":
		for i in range(40):
			bm.spawn_unit(militia, 0, Vector3(randf_range(-20, 20), 0, randf_range(-30, -10)))
		for i in range(40):
			if _mode == "spawn_nofight":
				bm.spawn_unit(knight, 1, Vector3(500 + i * 3, 0, 500))
			else:
				bm.spawn_unit(knight, 1, Vector3(randf_range(-20, 20), 0, randf_range(10, 30)))
	if _mode == "idle_units":
		pass
	elif _mode == "battle_empty":
		bm.change_state(bm.BattleState.BATTLE)
	else:
		bm.request_countdown()
	await create_timer(0.3).timeout

	var unit_gifts := ["Share", "Dragon", "Castle", "Heart", "Rose", "Skull", "Phoenix", "Lion", "Tiger"]
	var unit_res := {
		"Share": load("res://units/resources/knight.tres"),
		"Dragon": load("res://units/resources/titan.tres"),
		"Castle": load("res://units/resources/tank.tres"),
		"Heart": load("res://units/resources/spearman.tres"),
		"Rose": load("res://units/resources/knight.tres"),
		"Skull": load("res://units/resources/titan.tres"),
		"Phoenix": load("res://units/resources/knight.tres"),
		"Lion": load("res://units/resources/militia.tres"),
		"Tiger": load("res://units/resources/spearman.tres"),
	}
	var n := 0
	while n < 400:
		if _mode == "spawn_fight" or _mode == "spawn_nofight" or _mode == "battle_empty":
			var g2: String = unit_gifts[n % unit_gifts.size()]
			var fid: int = 0 if n % 2 == 0 else 1
			var pos: Vector3 = Vector3(randf_range(-15, 15), 0, randf_range(-20, 20))
			if _mode == "spawn_nofight":
				pos = Vector3(-100, 0, 100)
			bm.spawn_unit(unit_res[g2], fid, pos)
		else:
			var gift: String
			if _mode == "gift_fight":
				gift = unit_gifts[n % unit_gifts.size()]
			else:
				gift = unit_gifts[n % unit_gifts.size()]
			gift_mgr.process_gift(gift, "sender_%d" % n, 1, "uid_%d" % n)
		n += 1
		await create_timer(float(_delay_ms) / 1000.0).timeout
		if n % 50 == 0:
			print("[repro] n=%d alive=%d commanders=%d state=%d" % [
				n, reg.get_alive_count(), reg.get_alive_commanders().size(), bm.current_state])
	print("[repro] DONE n=%d alive=%d" % [n, reg.get_alive_count()])
	scene.queue_free()
	await create_timer(0.5).timeout
	print("[repro] FINISHED cleanly")
	quit(0)
