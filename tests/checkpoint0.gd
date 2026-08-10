extends SceneTree
## Part 0 checkpoint: BattleRegistry + SpectatorCam foundations.

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
	var sc = RegistryAccess.get_spectator()
	check(reg != null, "BattleRegistry autoload present")
	check(sc != null, "SpectatorCam autoload present")
	check(reg.SPECTATE_WEIGHTS.has("commander"), "commander in spectate weights")
	check(reg.SPECTATE_WEIGHTS.get("commander", 0.0) == 3.0, "commander weight is highest (3.0)")
	check(sc.CAMERA_CONFIG.has("tank"), "camera config covers tank")
	check(sc.CAMERA_CONFIG.has("titan"), "camera config covers titan")
	check(sc.CAMERA_CONFIG.has("commander"), "camera config covers commander")

	var scene = load("res://maps/main_battlefield.tscn").instantiate()
	root.add_child(scene)
	await create_timer(0.3).timeout
	var bm = scene.get_node("BattleManager")
	bm.start_game()
	var militia = load("res://units/resources/militia.tres")
	bm.spawn_unit(militia, 0, Vector3(0, 0, -10))
	await create_timer(0.2).timeout
	var units: Array = reg.get_alive_by_type("militia")
	check(units.size() >= 1, "spawned militia registered")
	var u = units[0] if units.size() > 0 else null
	check(u != null and reg.is_eligible(u), "living unit is spectate-eligible")
	if u:
		u.take_damage(9999.0)
		await create_timer(0.4).timeout
		check(reg.get_alive_by_type("militia").size() == 0, "dead unit unregistered")
		check(not reg.is_eligible(u), "dead unit not eligible")
	scene.queue_free()
	await create_timer(0.4).timeout
	check(reg.get_alive_count() == 0, "registry empty after scene teardown")
	_finish()

func _finish() -> void:
	print("CHECKPOINT0 RESULT pass=%d fail=%d" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
