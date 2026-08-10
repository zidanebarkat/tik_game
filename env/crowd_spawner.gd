## Attach this script to a MultiMeshInstance3D node.
## It fills a rectangular field with camera-facing billboard "soldiers" —
## hundreds of them for the cost of a single draw call.
extends MultiMeshInstance3D

@export var soldier_spritesheet: Texture2D
@export var rows: int = 12
@export var cols: int = 30
@export var spacing: float = 1.3
@export var jitter: float = 0.45
@export var quad_size: Vector2 = Vector2(1.0, 1.8)
@export var origin_offset: Vector3 = Vector3.ZERO

func _ready() -> void:
	var quad := QuadMesh.new()
	quad.size = quad_size
	quad.orientation = PlaneMesh.FACE_Y  # placeholder if using PlaneMesh instead; QuadMesh ignores this

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = quad
	mm.instance_count = rows * cols
	multimesh = mm

	var mat := ShaderMaterial.new()
	mat.shader = load("res://env/billboard_soldier.gdshader")
	mat.set_shader_parameter("soldier_tex", soldier_spritesheet)
	quad.material = mat

	_place_instances(mm)

func _place_instances(mm: MultiMesh) -> void:
	var i := 0
	for r in rows:
		for c in cols:
			var pos := Vector3(
				(c - cols / 2.0) * spacing + randf_range(-jitter, jitter),
				quad_size.y * 0.5,  # lift so the quad's bottom sits on the ground
				(r - rows / 2.0) * spacing + randf_range(-jitter, jitter)
			) + origin_offset
			# Small random Y rotation so the marching grid doesn't look too uniform
			var basis := Basis(Vector3.UP, randf_range(-0.15, 0.15))
			mm.set_instance_transform(i, Transform3D(basis, pos))
			i += 1
