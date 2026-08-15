extends SceneTree
## Part 17 checkpoint: cinematic director camera. Verifies it takes over the
## view automatically once a battle is live, frames the mid-fight action center,
## detects melee engagements, cuts to the Meteor blast and the victory final,
## yields to manual camera mode, and hands control back when toggled off (F4).

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
	var director = scene.get_node("DirectorCam")
	var sp = scene.get_node("SuperPower")
	var rts_cam = scene.get_node("RTSCamera")

	check(director != null and director._cam != null, "director exists with its own camera")
	check(director.enabled, "director enabled by default")

	# not active before battle
	await create_timer(0.1).timeout
	check(not director.is_active(), "inactive before battle starts")

	# spawn the armies first so the battle doesn't auto-end as an empty draw
	var militia = load("res://units/resources/militia.tres")
	for i in range(4):
		bm.spawn_unit(militia, 0, Vector3(-60 + i, 0, -60 + i), "", { "force_position": Vector3(-60 + i, 0, -60 + i) })
		bm.spawn_unit(militia, 1, Vector3(60 + i, 0, 60 + i), "", { "force_position": Vector3(60 + i, 0, 60 + i) })
	await create_timer(0.3).timeout

	# take over when battle is live
	bm.start_battle()
	await create_timer(0.25).timeout
	check(director.is_active(), "active while battle is live")
	check(director._cam.is_current(), "director camera is current during battle")
	check(not rts_cam.is_current(), "RTS free cam yielded to director")

	# frames the mid-fight from the wide framing
	var cam_pos: Vector3 = director._cam.global_position
	var center: Vector3 = director._action_center
	check(cam_pos.y > 40.0 and cam_pos.y < 52.0, "wide shot at good height, got " + str(cam_pos.y))
	check(absf(cam_pos.distance_to(center + Vector3(0, director.wide_height, 0)) - director.wide_distance) < 20.0, \
			"camera orbits the action center, dist=" + str(cam_pos.distance_to(center)))

	# engagement detection: units of both sides in contact
	for i in range(4):
		bm.spawn_unit(militia, 0, Vector3(10 + i, 0, 10 + i), "", { "force_position": Vector3(10 + i, 0, 10 + i) })
	for i in range(4):
		bm.spawn_unit(militia, 1, Vector3(12 + i, 0, 12 + i), "", { "force_position": Vector3(12 + i, 0, 12 + i) })
	await create_timer(0.6).timeout
	var cluster = director._detect_engagement()
	check(cluster != null, "melee cluster detected at " + str(cluster))

	# super power detonation cuts to the blast
	sp.detonated.emit(Vector3(0, 0, 0), 1)
	await create_timer(0.1).timeout
	check(director._mode == director.MODE.SUPER, "super detonation triggers SUPER shot")

	# battle end triggers the final sweep
	bm.battle_ended.emit(0)
	await create_timer(0.1).timeout
	check(director._mode == director.MODE.FINAL, "battle end triggers FINAL shot")
	check(director.is_active(), "director stays active for the final")

	# manual camera override yields control
	var sc = RegistryAccess.get_spectator()
	if sc:
		sc._enter_spectate_mode()
		await create_timer(0.1).timeout
		check(not director.is_active(), "director yields to manual spectate mode")
		sc._enter_rts_mode()
		await create_timer(0.1).timeout

	# F4 toggle hands control back to the manual camera
	director.toggle()
	check(not director.enabled, "toggle disables director")
	check(not director.is_active(), "inactive after toggle off")
	check(rts_cam.is_current(), "RTS free cam restored after toggle off")
	director.toggle()
	check(director.enabled, "toggle re-enables director")

	print("CHECKPOINT17 RESULT pass=%d fail=%d" % [_pass, _fail])
	quit(_fail > 0)
