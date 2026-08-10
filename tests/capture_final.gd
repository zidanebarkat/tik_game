extends SceneTree
func _init() -> void:
	await process_frame
	root.size = Vector2i(1280, 720)
	var scene = load("res://maps/main_battlefield.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var cam: Camera3D = scene.get_node_or_null("RTSCamera")
	cam.make_current()
	cam.position = Vector3(0, 75 * sin(deg_to_rad(38)), 75 * cos(deg_to_rad(38)))
	cam.look_at(Vector3.ZERO, Vector3.UP)
	cam.fov = 60.0
	var bm = scene.get_node("BattleManager")
	bm.start_game()
	var militia = load("res://units/resources/militia.tres")
	var knight = load("res://units/resources/knight.tres")
	for i in range(10):
		bm.spawn_unit(militia, 0, Vector3(randf_range(-20, 20), 0, randf_range(-30, -10)))
	for i in range(10):
		bm.spawn_unit(knight, 1, Vector3(randf_range(-20, 20), 0, randf_range(10, 30)))
	for i in range(30):
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png("/tmp/part5_final_720p.png")
	print("CAPTURED", img.get_width(), "x", img.get_height())
	quit(0)
