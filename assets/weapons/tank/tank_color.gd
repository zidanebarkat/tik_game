extends Node3D

var faction_manager = null
var faction_id: int = 0

func _ready() -> void:
	apply_team_color()

func apply_team_color() -> void:
	var color := Color.WHITE
	if faction_manager and faction_manager.has_method("get_faction_color"):
		color = faction_manager.get_faction_color()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = 0.0
	mat.roughness = 0.85
	_tint_meshes(self, mat)

func _tint_meshes(node: Node, mat: StandardMaterial3D) -> void:
	for child in node.get_children():
		if child is MeshInstance3D and child.mesh != null:
			child.material_override = mat
		if child.get_child_count() > 0:
			_tint_meshes(child, mat)
