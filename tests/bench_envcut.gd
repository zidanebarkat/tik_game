extends SceneTree
## Part 5 env-lever audit at fixed 40v40 horde (720p): how much do fog, dynamic
## shadows and dressing cost each? Confirms none of the prompt's Parts 1-3 cuts
## are needed to stay playable.
##   godot --path . -s tests/bench_envcut.gd -- <full|nofog|noshadow|nodressing|nolight>

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
	var args := OS.get_cmdline_user_args()
	var cfg := "full"
	if args.size() > 0:
		cfg = args[0]
	_run(cfg)

func _run(cfg: String) -> void:
	await process_frame
	root.size = Vector2i(1280, 720)
	var scene = load("res://maps/main_battlefield.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	match cfg:
		"nofog":
			var env: Environment = scene.get_node_or_null("WorldEnvironment").environment
			if env:
				env.fog_enabled = false
		"noshadow":
			var sun := scene.get_node_or_null("DirectionalLight3D") as DirectionalLight3D
			if sun:
				sun.shadow_enabled = false
		"shadow512":
			ProjectSettings.set_setting("rendering/lights_and_shadows/directional_shadow_size", 512)
		"shadow1024":
			ProjectSettings.set_setting("rendering/lights_and_shadows/directional_shadow_size", 1024)
		"nodressing":
			var dressing: Node = scene.find_child("Dressing", true, false)
			if dressing:
				dressing.visible = false
		"nolight":
			var env2: Environment = scene.get_node_or_null("WorldEnvironment").environment
			if env2:
				env2.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
				env2.ambient_light_color = Color(0.3, 0.27, 0.23)
				env2.ambient_light_energy = 1.0
	var cam: Camera3D = scene.get_node_or_null("RTSCamera")
	cam.make_current()
	cam.position = Vector3(0, 75 * sin(deg_to_rad(38)), 75 * cos(deg_to_rad(38)))
	cam.look_at(Vector3.ZERO, Vector3.UP)
	cam.fov = 60.0
	var bm = scene.get_node("BattleManager")
	bm.start_game()
	var militia = load("res://units/resources/militia.tres")
	var knight = load("res://units/resources/knight.tres")
	for i in range(40):
		bm.spawn_unit(militia, 0, Vector3(randf_range(-20, 20), 0, randf_range(-30, -10)))
	for i in range(40):
		bm.spawn_unit(knight, 1, Vector3(randf_range(-20, 20), 0, randf_range(10, 30)))
	for i in range(80):
		await process_frame
	var r := await _fps(90)
	print("ENVCUT %s 40v40 720p avg=%.1f min=%.1f max=%.1f" % [cfg, r[0], r[1], r[2]])
	quit(0)
