extends SceneTree

func _fps(window: float) -> Array:
	var n := int(window)
	var sum := 0.0
	var mn := 1e9
	var mx := 0.0
	for i in n:
		await process_frame
		var f := Engine.get_frames_per_second()
		sum += f
		mn = minf(mn, f)
		mx = maxf(mx, f)
	return [sum / n, mn, mx]

func _init() -> void:
	_run()

func _run() -> void:
	await process_frame
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
	for i in range(1):
		bm.spawn_unit(militia, 0, Vector3(randf_range(-20, 20), 0, randf_range(-30, -10)))
	for i in range(10):
		bm.spawn_unit(knight, 1, Vector3(randf_range(-20, 20), 0, randf_range(10, 30)))
	for i in range(60):
		await process_frame
	var r := await _fps(60)
	print("FINAL 1v10 720p avg=%.1f min=%.1f max=%.1f" % [r[0], r[1], r[2]])
	var img = root.get_texture().get_image()
	img.save_png("/tmp/part3_final.png")
	quit(0)
