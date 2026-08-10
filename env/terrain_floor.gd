## Rebuilds the terrain_materials.glb ground as a gapless, tagged arena floor.
##
## The GLB ships the floor as 16 flat 300x300 patches laid on a 400-grid with
## 100-unit seams between them, each wearing a different texture (a patchwork of
## stone, dirt, grass and desert). Here we re-place each patch with the same
## mesh stretched 4/3 about its centre so the patches tile with no gaps, and
## force every patch onto one shared floor material (grass) so the arena reads
## as a single terrain type. Each patch pairs with a StaticBody3D (layer 2, the
## layer units raycast against) carrying a surface_type tag for the footstep
## system.
extends Node3D

const TERRAIN_SCENE := "res://assets/environments/terrain_materials.glb"
const GROUND_SURFACE := preload("res://env/ground_surface.gd")

# Uniform floor: every patch shares one material (cloned from the source grass
# patch, which keeps its albedo/roughness/normal channels) and one surface tag.
const SURFACE_TYPE := "grass"
const GRASS_PATCH := "Plane_Material_007_0"

var _floor_material: StandardMaterial3D

# Maps a patch's mesh-local XY plane onto the horizontal world floor, stretching
# each 300u patch to 400u (fills the 100u seams). Columns: X=(4/3,0,0),
# Y=(0,0,4/3), Z=(0,-1,0). Det > 0, so winding is preserved (faces stay up).
const FLOOR_BASIS := Basis(
	Vector3(4.0 / 3.0, 0.0, 0.0),
	Vector3(0.0, 0.0, 4.0 / 3.0),
	Vector3(0.0, -1.0, 0.0)
)

const PATCH_SIZE := 400.0
const COLLISION_HEIGHT := 0.1

func _ready() -> void:
	var src: PackedScene = load(TERRAIN_SCENE)
	var inst := src.instantiate()
	add_child(inst)
	var patches := inst.find_children("*", "MeshInstance3D", true, false)
	_floor_material = _clone_grass_material(patches)
	for mi in patches:
		_build_patch(mi)
	inst.queue_free()

func _clone_grass_material(patches: Array) -> StandardMaterial3D:
	for mi in patches:
		if mi.name == GRASS_PATCH:
			var orig: StandardMaterial3D = mi.get_surface_override_material(0)
			if orig == null:
				orig = mi.mesh.surface_get_material(0)
			if orig:
				return orig.duplicate()
	return null

func _build_patch(mi: MeshInstance3D) -> void:
	var aabb: AABB = mi.mesh.get_aabb()
	var cx := aabb.position.x + aabb.size.x * 0.5
	var cy := aabb.position.y + aabb.size.y * 0.5
	var patch_name: String = mi.name

	var vis := MeshInstance3D.new()
	vis.name = patch_name
	vis.mesh = mi.mesh
	if _floor_material:
		vis.material_override = _floor_material
	vis.transform = Transform3D(FLOOR_BASIS, Vector3(-cx / 3.0, 0.0, -cy / 3.0))
	add_child(vis)

	var body := StaticBody3D.new()
	body.name = patch_name + "_coll"
	body.collision_layer = 2
	body.collision_mask = 0
	body.set_script(GROUND_SURFACE)
	body.surface_type = SURFACE_TYPE
	body.position = Vector3(cx, 0.0, cy)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(PATCH_SIZE, COLLISION_HEIGHT, PATCH_SIZE)
	shape.shape = box
	shape.position = Vector3(0.0, -COLLISION_HEIGHT * 0.5, 0.0)
	body.add_child(shape)
	add_child(body)
