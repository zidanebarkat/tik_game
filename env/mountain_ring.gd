## Distant mountain backdrop using the hand-authored world_env layout.
##
## Reuses the mountain placement from maps/world_env.tscn (the user's preferred
## ring), hiding the oversized valley floor and rescaling each mountain so its
## world peak lands in the same height band as the earlier approved ring,
## keeping the relative height variety of the original layout.
extends Node3D

const WORLD_ENV_SCENE := "res://maps/world_env.tscn"
const EXCLUDED_NODES := ["WorldFloor", "ValleyTerrain"]
const PEAK_MIN := 421.0
const PEAK_MAX := 612.0
const TARGET_MIN := 105.0
const TARGET_MAX := 145.0

func _ready() -> void:
	var src: PackedScene = load(WORLD_ENV_SCENE)
	var env := src.instantiate()
	add_child(env)
	for child in env.get_children():
		if child.name in EXCLUDED_NODES:
			child.queue_free()
	for mi in env.find_children("*", "MeshInstance3D", true, false):
		if not is_instance_valid(mi):
			continue
		var aabb: AABB = mi.mesh.get_aabb()
		var g: Transform3D = mi.global_transform
		var peak := -1e9
		var origin_y := g.origin.y
		for x in [aabb.position.x, aabb.end.x]:
			for y in [aabb.position.y, aabb.end.y]:
				for z in [aabb.position.z, aabb.end.z]:
					peak = maxf(peak, (g * Vector3(x, y, z)).y)
		if peak <= origin_y:
			continue
		var t: float = (peak - PEAK_MIN) / (PEAK_MAX - PEAK_MIN)
		var target := TARGET_MIN + t * (TARGET_MAX - TARGET_MIN)
		var k := (target - origin_y) / (peak - origin_y)
		mi.scale *= k
