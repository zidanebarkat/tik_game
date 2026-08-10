extends SceneTree
## Part 7 checkpoint: spectator auto-cut on arrival + identity overlay.

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
	for i in range(15):
		bm.spawn_unit(militia, 0, Vector3(randf_range(-20, 20), 0, randf_range(-30, -10)))
	for i in range(15):
		bm.spawn_unit(knight, 1, Vector3(randf_range(-20, 20), 0, randf_range(10, 30)))
	bm.request_countdown()
	await create_timer(0.2).timeout
	check(sc.auto_cut_on_arrival, "auto-cut on arrival enabled")
	check(reg.SPECTATE_WEIGHTS.get("commander", 0.0) == 3.0, "commander spectate_weight = 3.0")
	var highest := true
	for k in reg.SPECTATE_WEIGHTS:
		if float(reg.SPECTATE_WEIGHTS[k]) > 3.0:
			highest = false
	check(highest, "commander weight is highest in the pool")

	cm.debug_spawn("silver", "viewerAlpha", "alpha7")
	await create_timer(0.4).timeout
	var cmdrs = reg.get_alive_commanders()
	var c = cmdrs[0] if cmdrs.size() > 0 else null
	check(c != null, "silver commander spawned")
	if c == null:
		_finish()
		return
	check(c.commander_id == "alpha7" and c.commander_name == "viewerAlpha", "commander identity")
	check(c.stats.max_health == 350.0 and c.stats.armor == 12.0, "commander stats")
	var escorts: Array = []
	for u in reg.alive_units:
		if u.commander_id == "alpha7" and u.get_unit_type() != "commander":
			escorts.append(u)
	check(escorts.size() >= 6, "escort present in registry")

	sc._toggle_on()
	sc._attach(c)
	check(sc.is_spectating() and sc.get_current_target() == c, "spectating commander")
	await create_timer(0.2).timeout
	var hud = scene.get_node("HUD")
	check(hud.spectate_panel.visible, "overlay shows spectating panel")
	check(hud.spectate_tag.text == "COMMANDER", "overlay tags commander")
	check(hud.spectate_name.text == "viewerAlpha", "overlay shows viewer username")
	check(hud.spectate_portrait.visible, "commander portrait overlay visible")

	var esc = escorts[0] if escorts.size() > 0 else null
	if esc:
		sc._attach(esc)
		await create_timer(0.2).timeout
		check(hud.spectate_tag.text == "fighting for viewerAlpha", "escort overlay shows 'fighting for viewerAlpha'")
		check(not hud.spectate_portrait.visible, "escort overlay hides portrait")

	var titan = load("res://units/resources/titan.tres")
	bm.spawn_unit(titan, 1, Vector3.ZERO, "", {"force_position": Vector3(80, 0, -80)})
	await create_timer(0.2).timeout
	var titans: Array = reg.get_alive_by_type("titan")
	check(titans.size() >= 1, "safe titan available as return target")
	var safe = titans[0] if titans.size() > 0 else null
	sc._attach(safe)
	check(sc.get_current_target() == safe, "camera parked on titan before arrival")

	c.march_speed = 80.0
	for i in range(200):
		await create_timer(0.05).timeout
		if not c.is_marching():
			break
	check(not c.is_marching(), "commander arrival march finished")
	check(sc.get_current_target() == c, "auto-cut snapped camera to arriving commander")
	await create_timer(0.3).timeout
	check(hud.spectate_name.text == "viewerAlpha", "overlay follows auto-cut to viewer")
	check(hud.spectate_portrait.visible, "commander portrait shown during auto-cut")
	await create_timer(4.0).timeout
	check(sc.get_current_target() == safe, "auto-cut returned to previous target")

	sc.auto_cut_on_arrival = false
	sc._attach(safe)
	cm.debug_spawn("bronze", "viewerBeta", "beta7")
	await create_timer(0.5).timeout
	var bc = null
	for x in reg.get_alive_commanders():
		if x.commander_id == "beta7":
			bc = x
	if bc:
		bc.march_speed = 80.0
	for i in range(200):
		await create_timer(0.05).timeout
		if bc == null or not is_instance_valid(bc) or not bc.is_marching():
			break
	check(sc.get_current_target() == safe, "auto-cut disabled: camera untouched by second arrival")
	sc._toggle_off()
	scene.queue_free()
	await create_timer(0.4).timeout
	_finish()

func _finish() -> void:
	print("CHECKPOINT7 RESULT pass=%d fail=%d" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
