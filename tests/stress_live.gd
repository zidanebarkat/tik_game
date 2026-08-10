extends SceneTree
## Live-traffic stress host: boots the real main scene, opens a battle, keeps the
## spectator + overview cuts running while the bridge simulator floods gifts in.
## Renders normally (like the CEDAR laptop) when run WITHOUT --headless.
##
##   godot --path . -s tests/stress_live.gd -- <seconds>

var _seconds := 90.0

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_seconds = maxf(30.0, float(args[0]))
	print("[stress] window = %.0f seconds" % _seconds)
	_run()

func _run() -> void:
	await create_timer(0.5).timeout
	var scene = load("res://maps/main_battlefield.tscn").instantiate()
	root.add_child(scene)
	await create_timer(1.0).timeout
	var bm = scene.get_node("BattleManager")
	var cm = RegistryAccess.get_commander_manager()
	var reg = RegistryAccess.get_registry()
	var sc = RegistryAccess.get_spectator()
	bm.start_game()
	var militia = load("res://units/resources/militia.tres")
	var knight = load("res://units/resources/knight.tres")
	for i in range(40):
		bm.spawn_unit(militia, 0, Vector3(randf_range(-20, 20), 0, randf_range(-30, -10)))
	for i in range(40):
		bm.spawn_unit(knight, 1, Vector3(randf_range(-20, 20), 0, randf_range(10, 30)))
	bm.request_countdown()
	await create_timer(0.3).timeout
	sc._toggle_on()
	var started := Time.get_ticks_msec() / 1000.0
	var peak_alive := 0
	var peak_cmdrs := 0
	var tick := 0
	while (Time.get_ticks_msec() / 1000.0) - started < _seconds:
		await create_timer(2.0).timeout
		tick += 1
		sc._cycle()
		if tick % 5 == 0:
			cm.debug_spawn(["bronze", "silver", "gold"][tick % 3], "stress_%d" % tick, "stress_%d" % tick)
		peak_alive = maxi(peak_alive, reg.get_alive_count())
		peak_cmdrs = maxi(peak_cmdrs, reg.get_alive_commanders().size())
		var eng = RegistryAccess.get_engagement()
		var lb := 0
		if eng:
			lb = eng.get_leaderboard(3).size()
		print("[stress] tick=%d alive=%d commanders=%d lb=%d state=%d" % [
			tick, reg.get_alive_count(), reg.get_alive_commanders().size(), lb, bm.current_state])
	print("[stress] DONE peak_alive=%d peak_commanders=%d" % [peak_alive, peak_cmdrs])
	sc._toggle_off()
	scene.queue_free()
	await create_timer(0.5).timeout
	print("[stress] FINISHED cleanly")
	quit(0)
