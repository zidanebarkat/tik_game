extends SceneTree
## Part 1 ground verification: gapless floor covers the whole arena, every
## patch is raycastable (no seams, no infinite fall), surface_type tags read
## back correctly, and dressing MultiMeshes are in place.

var _fail := 0

func check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS ", msg)
	else:
		_fail += 1
		print("FAIL ", msg)

func _init() -> void:
	_run()

func _run() -> void:
	await process_frame
	var scene = load("res://maps/main_battlefield.tscn")
	check(scene != null, "main_battlefield loads")
	var inst = scene.instantiate()
	root.add_child(inst)
	await process_frame

	var ground = inst.get_node_or_null("Ground")
	check(ground != null, "Ground node present")
	if ground == null:
		quit(1)
		return
	var floor = ground.get_node_or_null("Floor")
	check(floor != null, "Floor builder present")
	await process_frame

	var visuals := []
	var bodies := []
	for c in floor.get_children():
		if c is MeshInstance3D:
			visuals.append(c)
		elif c is StaticBody3D:
			bodies.append(c)
	check(visuals.size() == 16, "16 visual patches rebuilt (%d)" % visuals.size())
	check(bodies.size() == 16, "16 tagged collision patches (%d)" % bodies.size())

	var grass_override := 0
	for v in visuals:
		var mat: StandardMaterial3D = v.material_override
		if mat and mat.albedo_texture and mat.albedo_texture.resource_path.ends_with("terrain_materials_17.png"):
			grass_override += 1
	check(grass_override == visuals.size(),
		"all visual patches share the grass material (%d/16)" % grass_override)

	var space := root.get_world_3d().direct_space_state
	# Gapless scan: rays across the full footprint must all hit ground.
	var scan := 0
	var scan_hits := 0
	for gx in range(-750, 751, 150):
		for gz in range(-750, 751, 150):
			scan += 1
			var from := Vector3(gx, 40.0, gz)
			var to := Vector3(gx, -1.0, gz)
			var q := PhysicsRayQueryParameters3D.create(from, to, 2)
			var hit := space.intersect_ray(q)
			if hit:
				scan_hits += 1
	check(scan_hits == scan, "no gaps: %d/%d floor rays hit ground" % [scan_hits, scan])

	# Surface type lookup per patch centre: uniform grass floor.
	var expected := {
		Vector3(-600, 0, -600): "grass", Vector3(-200, 0, -600): "grass",
		Vector3(200, 0, -600): "grass", Vector3(600, 0, -600): "grass",
		Vector3(-600, 0, -200): "grass", Vector3(-200, 0, -200): "grass",
		Vector3(200, 0, -200): "grass", Vector3(600, 0, -200): "grass",
		Vector3(-600, 0, 200): "grass", Vector3(-200, 0, 200): "grass",
		Vector3(200, 0, 200): "grass", Vector3(600, 0, 200): "grass",
		Vector3(-600, 0, 600): "grass", Vector3(-200, 0, 600): "grass",
		Vector3(200, 0, 600): "grass", Vector3(600, 0, 600): "grass",
	}
	var tagged_ok := 0
	for p in expected:
		var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 40, 0), p + Vector3(0, -1, 0), 2)
		var hit := space.intersect_ray(q)
		if hit and hit.collider.has_method("get") and hit.collider.get("surface_type") == expected[p]:
			tagged_ok += 1
	check(tagged_ok == expected.size(), "surface tags match classified map (%d/%d)" % [tagged_ok, expected.size()])

	var dressing = ground.get_node_or_null("Dressing")
	var mm_count := 0
	if dressing:
		mm_count = dressing.find_children("*", "MultiMeshInstance3D", true, false).size()
	check(mm_count >= 3, "dressing MultiMeshes present (%d types)" % mm_count)

	var militia = load("res://units/resources/militia.tres")
	var bm = inst.get_node("BattleManager")
	bm.start_game()
	for p in [Vector3(0, 0, 0), Vector3(600, 0, 600), Vector3(-600, 0, -600), Vector3(200, 0, 200)]:
		bm.spawn_unit(militia, 0, p)
	var reg = RegistryAccess.get_registry()
	var units := []
	for u in reg.alive_units:
		if is_instance_valid(u):
			units.append(u)
	for i in range(24):
		await physics_frame
	var grounded := 0
	for u in units:
		if is_instance_valid(u) and u.global_position.y > -0.5:
			grounded += 1
	check(grounded == units.size(), "units stay grounded (%d/%d)" % [grounded, units.size()])
	_finish()

func _finish() -> void:
	print("PART1 GROUND RESULT fail=%d" % _fail)
	quit(0 if _fail == 0 else 1)
