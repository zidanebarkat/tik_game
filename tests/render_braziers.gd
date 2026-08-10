extends SceneTree

func _init() -> void:
	_run()

func _run() -> void:
	await process_frame
	var scene = load("res://maps/main_battlefield.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var menu: Node = scene.get_node_or_null("MainMenu")
	if menu:
		menu.visible = false
	var hud: Node = scene.get_node_or_null("HUD")
	if hud:
		hud.visible = false
	var cam: Camera3D = scene.get_node_or_null("RTSCamera")
	cam.make_current()
	cam.position = Vector3(0, 46, 59)
	cam.look_at(Vector3(0, 0, 0), Vector3.UP)
	cam.fov = 60.0
	var bm = scene.get_node("BattleManager")
	bm.start_game()
	for i in range(40):
		await process_frame
	var img = root.get_texture().get_image()
	img.save_png("/tmp/brazier_ring.png")
	var w := img.get_width()
	var h := img.get_height()
	var count := 0
	for y in range(0, h, 2):
		for x in range(0, w, 2):
			var c: Color = img.get_pixel(x, y)
			if c.r > 0.75 and c.g > 0.3 and c.b < 0.5 and c.r > c.g:
				count += 1
	print("orange pixels: %d" % count)
	quit(0)
