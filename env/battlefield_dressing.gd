## Scatters low-cost ancient-battlefield dressing around the arena: rocks,
## ruined columns, banners and a ring of glowing braziers. Each prop type is a
## single MultiMeshInstance3D (one draw call each), kept well outside the central
## combat zone. Purely visual - the floor collision stays a flat layer the units
## walk on. Braziers use emissive quads only (no OmniLights - too costly on
## TeraScale GPUs), so they add ~zero draw cost.
extends Node3D

const SEED := 20260810
const AVOID_RADIUS := 15.0

var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.seed = SEED
	_add_rocks()
	_add_columns()
	_add_banners()
	_add_braziers()

func _place(radius_min: float, radius_max: float) -> Vector3:
	var a := _rng.randf_range(0.0, TAU)
	var r := sqrt(_rng.randf_range(radius_min * radius_min, radius_max * radius_max))
	var p := Vector3(cos(a) * r, 0.0, sin(a) * r)
	if p.length() < AVOID_RADIUS:
		return _place(radius_min, radius_max)
	return p

func _make_multimesh(mesh: Mesh, count: int) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = count
	return mm

func _add_rocks() -> void:
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 6
	mesh.rings = 4
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.42, 0.40, 0.36)
	mat.roughness = 0.95
	mesh.material = mat
	var mm := _make_multimesh(mesh, 42)
	for i in mm.instance_count:
		var p := _place(16.0, 110.0)
		var sx := _rng.randf_range(0.7, 1.9)
		var sy := _rng.randf_range(0.45, 1.1)
		var sz := _rng.randf_range(0.7, 1.9)
		var b := Basis(Vector3.UP, _rng.randf_range(0.0, TAU)).scaled(Vector3(sx, sy, sz))
		var y := 0.5 * sy
		mm.set_instance_transform(i, Transform3D(b, Vector3(p.x, y, p.z)))
	_mount(mm)

func _add_columns() -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.34
	mesh.bottom_radius = 0.4
	mesh.height = 2.6
	mesh.radial_segments = 6
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.63, 0.61, 0.57)
	mat.roughness = 0.9
	mesh.material = mat
	var mm := _make_multimesh(mesh, 14)
	for i in mm.instance_count:
		var p := _place(24.0, 120.0)
		var tilt := _rng.randf_range(-0.16, 0.16)
		var b := Basis(Vector3.UP, _rng.randf_range(0.0, TAU)) * Basis(Vector3.RIGHT, tilt)
		mm.set_instance_transform(i, Transform3D(b, Vector3(p.x, 1.3, p.z)))
	_mount(mm)

func _add_banners() -> void:
	var pole := BoxMesh.new()
	pole.size = Vector3(0.12, 3.0, 0.12)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.32, 0.28, 0.24)
	wood.roughness = 0.9
	pole.material = wood
	var mm_p := _make_multimesh(pole, 10)
	for i in mm_p.instance_count:
		var p := _place(30.0, 130.0)
		var b := Basis(Vector3.UP, _rng.randf_range(0.0, TAU))
		mm_p.set_instance_transform(i, Transform3D(b, Vector3(p.x, 1.5, p.z)))
	_mount(mm_p)

	var flag := QuadMesh.new()
	flag.size = Vector2(1.2, 0.75)
	flag.orientation = PlaneMesh.FACE_Z
	var cloth := StandardMaterial3D.new()
	cloth.albedo_color = Color(0.62, 0.12, 0.12)
	cloth.emission_enabled = true
	cloth.emission = Color(0.35, 0.05, 0.05)
	cloth.cull_mode = BaseMaterial3D.CULL_DISABLED
	flag.material = cloth
	var mm_f := _make_multimesh(flag, 10)
	for i in mm_f.instance_count:
		var p := _place(30.0, 130.0)
		var b := Basis(Vector3.UP, _rng.randf_range(0.0, TAU))
		mm_f.set_instance_transform(i, Transform3D(b, Vector3(p.x, 2.4, p.z)))
	_mount(mm_f)

func _add_braziers() -> void:
	var ring_radius := 62.0
	var count := 16
	var stand := BoxMesh.new()
	stand.size = Vector3(0.28, 1.1, 0.28)
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.24, 0.22, 0.19)
	iron.roughness = 0.85
	stand.material = iron
	var mm_s := _make_multimesh(stand, count)
	for i in count:
		var a := TAU * i / count
		var p := Vector3(cos(a) * ring_radius, 0.0, sin(a) * ring_radius)
		mm_s.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(p.x, 0.55, p.z)))
	_mount(mm_s)

	var flame := QuadMesh.new()
	flame.size = Vector2(0.6, 0.8)
	flame.orientation = PlaneMesh.FACE_X
	var fire := StandardMaterial3D.new()
	fire.albedo_color = Color(0.02, 0.01, 0.0, 1)
	fire.emission_enabled = true
	fire.emission = Color(1.0, 0.28, 0.05)
	fire.emission_energy = 1.9
	fire.cull_mode = BaseMaterial3D.CULL_DISABLED
	flame.material = fire
	var mm_f := _make_multimesh(flame, count)
	for i in count:
		var a := TAU * i / count
		var p := Vector3(cos(a) * ring_radius, 0.0, sin(a) * ring_radius)
		var fb := Basis(Vector3.UP, a).scaled(Vector3(1, 1, 1))
		mm_f.set_instance_transform(i, Transform3D(fb, Vector3(p.x, 1.7, p.z)))
	var mi_f := _mount(mm_f)
	mi_f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _mount(mm: MultiMesh) -> MultiMeshInstance3D:
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	add_child(mi)
	return mi
