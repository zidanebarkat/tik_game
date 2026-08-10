extends SceneTree
## Part 4 surface-aware footstep verification: distinct procedural streams,
## per-surface tag readback through a walking unit, step emission switching
## with the surface type, and a shared pooled FX node (no per-unit audio).

var _fail := 0

func check(cond: bool, msg: String) -> void:
	if cond:
		print("PASS ", msg)
	else:
		_fail += 1
		print("FAIL ", msg)

func _init() -> void:
	_run()

func _ground_hit(pos: Vector3) -> Dictionary:
	var space := root.get_world_3d().direct_space_state
	return space.intersect_ray(PhysicsRayQueryParameters3D.create(
		pos + Vector3(0, 40, 0), pos + Vector3(0, -1, 0), 2))

func _step_unit(unit) -> void:
	unit._last_position = unit.global_position
	unit.global_position.x += 2.5
	unit._accumulate_step()

func _run() -> void:
	await process_frame

	var stone := ProceduralFootsteps.make_wav("stone")
	var dirt := ProceduralFootsteps.make_wav("dirt")
	var grass := ProceduralFootsteps.make_wav("grass")
	check(stone != null and dirt != null and grass != null, "procedural step streams generated")
	check(stone.data != dirt.data and dirt.data != grass.data and stone.data != grass.data,
		"three distinct surface streams (stone/dirt/grass)")

	var scene = load("res://maps/main_battlefield.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var bm = scene.get_node("BattleManager")
	bm.start_game()
	var militia = load("res://units/resources/militia.tres")
	bm.spawn_unit(militia, 0, Vector3(200, 0, 200))
	for i in range(12):
		await physics_frame

	var reg = RegistryAccess.get_registry()
	var unit = null
	for u in reg.alive_units:
		if is_instance_valid(u):
			unit = u
			break
	check(unit != null, "footstep test unit spawned")
	if unit == null:
		_finish()
		return

	unit.global_position = Vector3(200, 0, 200)
	unit._refresh_surface(_ground_hit(unit.global_position))
	check(unit._surface_type == "grass", "unit reads grass at (200,200) (%s)" % unit._surface_type)

	var fx = FootstepFX.get_instance()
	check(fx != null, "shared FootstepFX node present")
	unit._marching = true
	var before: int = fx.play_count
	_step_unit(unit)
	check(fx.play_count == before + 1, "step emitted on movement")
	check(fx.last_surface == "grass", "grass footstep selected (%s)" % fx.last_surface)

	unit.global_position = Vector3(200, 0, -200)
	unit._refresh_surface(_ground_hit(unit.global_position))
	check(unit._surface_type == "grass", "unit reads grass at (200,-200) (%s)" % unit._surface_type)
	before = fx.play_count
	_step_unit(unit)
	check(fx.last_surface == "grass" and fx.play_count == before + 1, "grass footstep after teleport")

	unit.global_position = Vector3(-600, 0, -600)
	unit._refresh_surface(_ground_hit(unit.global_position))
	check(unit._surface_type == "grass", "unit reads grass at (-600,-600) (%s)" % unit._surface_type)
	before = fx.play_count
	_step_unit(unit)
	check(fx.last_surface == "grass" and fx.play_count == before + 1, "grass footstep across far field")

	check(fx.get_child_count() <= 20, "shared pooled FX node (children=%d)" % fx.get_child_count())
	var no_per_unit := true
	for u in reg.alive_units:
		if is_instance_valid(u) and u.find_children("*", "AudioStreamPlayer3D", true, false).size() > 0:
			no_per_unit = false
	check(no_per_unit, "no per-unit audio nodes")

	unit._marching = false
	_finish()

func _finish() -> void:
	print("PART4 SURFACE RESULT fail=%d" % _fail)
	quit(0 if _fail == 0 else 1)
