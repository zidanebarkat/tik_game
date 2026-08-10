## Distant mountain backdrop ringed around the battlefield.
##
## Replaces the old world_env valley (whose 1400-unit-tall mountains engulfed
## the rebuilt flat arena). The same low-poly mountain mesh is instanced in a
## wide ring beyond the rolling-hill shell, sized and placed so its peaks poke
## just above the horizon through the dusty fog as a scenic backdrop without
## touching the playable floor.
extends Node3D

const MOUNTAIN_SCENE := "res://assets/environments/mountain_low_poly.glb"

const MESH_HALF_HEIGHT := 705.0
const RING_RADIUS_MIN := 1600.0
const RING_RADIUS_MAX := 2000.0
const COUNT := 10

func _ready() -> void:
	var src: PackedScene = load(MOUNTAIN_SCENE)
	var base := src.instantiate()
	var mesh_instance: MeshInstance3D = null
	for mi in base.find_children("*", "MeshInstance3D", true, false):
		mesh_instance = mi
		break
	var mesh: Mesh = mesh_instance.mesh if mesh_instance else null
	base.queue_free()
	if mesh == null:
		return
	for i in range(COUNT):
		var angle := TAU * float(i) / float(COUNT) + randf_range(-0.12, 0.12)
		var radius := randf_range(RING_RADIUS_MIN, RING_RADIUS_MAX)
		var scale := randf_range(0.18, 0.28)
		var origin_y := randf_range(105.0, 145.0) - MESH_HALF_HEIGHT * scale
		var mi := MeshInstance3D.new()
		mi.name = "Mountain_%02d" % i
		mi.mesh = mesh
		var t := Transform3D(Basis(Vector3(0, 1, 0), angle))
		mi.transform = t.scaled(Vector3(scale * randf_range(0.8, 1.2), scale, scale))
		mi.position = Vector3(cos(angle) * radius, origin_y, sin(angle) * radius)
		add_child(mi)
