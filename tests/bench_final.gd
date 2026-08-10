extends SceneTree
## Part 5 scale curve: FPS vs horde size on the finished environment, rendered
## at a target resolution like the CEDAR/HD 6370M hardware.
##   godot --path . -s tests/bench_final.gd -- <per_faction> <resolution>

func _fps(window: float) -> Array:
	var n := int(window)
	var sum := 0.0
	var mn := 1e9
	var mx := 0.0
	var vals: Array[float] = []
	for i in n:
		await process_frame
		var f := Engine.get_frames_per_second()
		sum += f
		mn = minf(mn, f)
		mx = maxf(mx, f)
		vals.append(f)
	vals.sort()
	return [sum / n, mn, mx, vals[int(n * 0.25)]]

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var per := 10
	var res := 720
	if args.size() > 0:
		per = int(args[0])
	if args.size() > 1:
		res = int(args[1])
	_run(per, res)

func _run(per: int, res: int) -> void:
	await process_frame
	root.size = Vector2i(int(res * 16.0 / 9.0), res)
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
	for i in range(per):
		bm.spawn_unit(militia, 0, Vector3(randf_range(-20, 20), 0, randf_range(-30, -10)))
	for i in range(per):
		bm.spawn_unit(knight, 1, Vector3(randf_range(-20, 20), 0, randf_range(10, 30)))
	for i in range(80):
		await process_frame
	var reg = RegistryAccess.get_registry()
	var r := await _fps(90)
	print("FINAL %dv%d %dp avg=%.1f min=%.1f max=%.1f p25=%.1f alive=%d" % [
		per, per, res, r[0], r[1], r[2], r[3], reg.get_alive_count()])
	quit(0)
