extends SceneTree
## Part 3 checkpoint: commander & squad unit roster (tank + commander stats, banner, nameplate).

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
	var commander = load("res://units/resources/commander.tres")
	var tank = load("res://units/resources/tank.tres")
	var militia = load("res://units/resources/militia.tres")
	check(commander != null and tank != null, "commander + tank resources exist")
	check(commander.max_health == 350.0, "commander HP 350")
	check(commander.armor == 12.0, "commander armor 12")
	check(commander.attack_damage == 30.0, "commander damage 30")
	check(tank.armor == 15.0, "tank armor 15 (highest)")
	check(tank.move_speed < militia.move_speed, "tank slower than infantry")
	check(commander.population_value == 5, "commander population cost 5")

	var reg = RegistryAccess.get_registry()
	var scene = load("res://maps/main_battlefield.tscn").instantiate()
	root.add_child(scene)
	await create_timer(0.3).timeout
	var bm = scene.get_node("BattleManager")
	var cm = RegistryAccess.get_commander_manager()
	bm.start_game()
	var knight = load("res://units/resources/knight.tres")
	for i in range(10):
		bm.spawn_unit(militia, 0, Vector3(randf_range(-20, 20), 0, randf_range(-30, -10)))
	for i in range(10):
		bm.spawn_unit(knight, 1, Vector3(randf_range(-20, 20), 0, randf_range(10, 30)))
	bm.request_countdown()
	await create_timer(0.2).timeout
	cm.debug_spawn("bronze", "RosterCheck", "roster1")
	await create_timer(0.5).timeout
	var cmdrs = reg.get_alive_commanders()
	check(cmdrs.size() >= 1, "commander unit spawned")
	var c = cmdrs[0] if cmdrs.size() > 0 else null
	if c:
		check(c.stats.unit_name == "Commander", "unit type is commander")
		check(c.get_node_or_null("Banner") != null, "commander carries a banner")
		var banner = c.get_node_or_null("Banner")
		check(banner != null and banner.get_node_or_null("Nameplate") != null, "banner has a nameplate")
		check(c.get_display_name() == "RosterCheck", "commander display name set")
		check(c.get_faction_tag() == "commander_roster1", "commander faction tag")
		check(c.march_speed > 0.0, "commander march speed configured")
	scene.queue_free()
	await create_timer(0.4).timeout
	_finish()

func _finish() -> void:
	print("CHECKPOINT3 RESULT pass=%d fail=%d" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
