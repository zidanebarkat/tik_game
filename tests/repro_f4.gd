extends SceneTree

var _pass := 0
var _fail := 0

func check(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
		print("PASS ", msg)
	else:
		_fail += 1
		print("FAIL ", msg)

func _init() -> void:
	_run()

func _run() -> void:
	await create_timer(0.2).timeout
	var scene = load("res://maps/main_battlefield.tscn").instantiate()
	root.add_child(scene)
	await create_timer(0.3).timeout
	var bm = scene.get_node("BattleManager")
	var director = scene.get_node("DirectorCam")
	var camera = scene.get_node("RTSCamera")
	var hud = scene.get_node("HUD")
	var menu = scene.get_node("MainMenu")
	var militia = load("res://units/resources/militia.tres")
	var knight = load("res://units/resources/knight.tres")
	bm.start_game()
	for i in range(4):
		bm.spawn_unit(militia, 0, Vector3(10 + i, 0, 10 + i), "", { "force_position": Vector3(10 + i, 0, 10 + i) })
	for i in range(4):
		bm.spawn_unit(knight, 1, Vector3(12 + i, 0, 12 + i), "", { "force_position": Vector3(12 + i, 0, 12 + i) })
	bm.request_countdown()
	await create_timer(0.2).timeout
	check(bm.current_state == bm.BattleState.BATTLE, "fight is live")
	var waited := 0.0
	while bm.current_state == bm.BattleState.BATTLE and waited < 20.0:
		await create_timer(0.5).timeout
		waited += 0.5
	check(bm.current_state == bm.BattleState.VICTORY, "fight reaches VICTORY")
	check(hud.result_panel.visible, "result panel is visible")
	check(director._mode == director.MODE.FINAL, "director plays FINAL shot")
	check(scene._result_timer > 0.0, "return-to-menu timer armed")
	# move the camera away so we can verify it snaps home
	camera.global_position = Vector3(0, 500, 0)
	var t0: float = scene._result_timer
	waited = 0.0
	while scene._result_timer > 0.0 and waited < t0 + 2.0:
		await create_timer(0.5).timeout
		waited += 0.5
	check(bm.current_state == bm.BattleState.MENU, "game returned to MENU after result")
	check(menu.visible, "main menu is visible")
	var lr = menu.get_node_or_null("Center/VBox/LastResult")
	check(lr != null and lr.visible and lr.text != "", "menu shows the last result")
	check(not director.is_active(), "director stopped")
	check(camera.is_current(), "RTS camera current in menu")
	check(camera.global_position.y > 100.0, "camera snapped home, y=" + str(camera.global_position.y))
	check(bm.get_faction(0).get_alive_count() == 0 and bm.get_faction(1).get_alive_count() == 0, "all units cleared")
	# start a new round from the menu
	menu._on_start_pressed()
	check(bm.current_state == bm.BattleState.IDLE, "new round starts from menu")
	print("REPRO RESULT pass=%d fail=%d" % [_pass, _fail])
	quit(_fail > 0)
