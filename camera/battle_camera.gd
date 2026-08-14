extends Camera3D
class_name BattleCamera

## UEBS-style battle overview camera.
## Sits at a fixed downward pitch and automatically dollies in/out so
## every living unit in `unit_group` (plus the player) stays framed.
##
## SETUP:
## 1. Add this script to a Camera3D node (can live anywhere in the tree,
##    it uses top_level so parent transforms don't fight the math).
## 2. In each enemy/player script's _ready(), call:
##        add_to_group("battle_units")
## 3. Give enemy/player scripts an `is_alive() -> bool` method
##    (return health > 0). If missing, the camera just includes them
##    regardless of state.
## 4. To switch into this camera: battle_camera.current = true
##    (and set your other Camera3D's `current = false`).

@export_group("Framing")
@export var pitch_degrees: float = 40.0          # downward tilt; 35-45 is the UEBS sweet spot
@export var padding: float = 1.35                # >1.0 = breathing room around the action
@export var min_distance: float = 6.0            # never push in closer than this (avoids nose-to-nose zoom on a 1v1)
@export var max_distance: float = 45.0           # hard ceiling so a stray unit can't yank the camera to orbit
@export var max_unit_search_radius: float = 60.0 # ignore units this far from the player (e.g. units still routing to the castle)

@export_group("Smoothing")
@export var position_smoothing: float = 4.0      # higher = camera catches up to target faster
@export var rotation_smoothing: float = 5.0

@export_group("Performance")
@export var recompute_interval: float = 0.1      # how often to rescan all units (seconds); smoothing still runs every frame

@export_group("Targets")
@export var player: Node3D
@export var unit_group: StringName = &"battle_units"

var _target_pos: Vector3
var _current_look: Vector3
var _cached_center: Vector3
var _cached_radius: float = 8.0
var _recompute_timer: float = 0.0

func _ready() -> void:
	top_level = true
	_current_look = global_position
	if is_instance_valid(player):
		_cached_center = player.global_position

func _physics_process(delta: float) -> void:
	_recompute_timer -= delta
	if _recompute_timer <= 0.0:
		_recompute_timer = recompute_interval
		var frame := _compute_frame()
		_cached_center = frame.center
		_cached_radius = frame.radius

	_apply_frame(_cached_center, _cached_radius, delta)

## Scans all living units (+ player) and returns a bounding sphere to frame.
func _compute_frame() -> Dictionary:
	var points: Array[Vector3] = []

	if is_instance_valid(player):
		points.append(player.global_position)

	for unit in get_tree().get_nodes_in_group(unit_group):
		if not is_instance_valid(unit):
			continue
		if unit.has_method("is_alive") and not unit.is_alive():
			continue
		if is_instance_valid(player) and unit.global_position.distance_to(player.global_position) > max_unit_search_radius:
			continue
		points.append(unit.global_position)

	if points.is_empty():
		return {"center": _cached_center, "radius": _cached_radius}

	var box := AABB(points[0], Vector3.ZERO)
	for p in points:
		box = box.expand(p)

	var radius: float = max(box.get_longest_axis_size() * 0.5, 3.0)
	return {"center": box.get_center(), "radius": radius}

## Positions/orients the camera to fit a sphere of `radius` around `center`.
func _apply_frame(center: Vector3, radius: float, delta: float) -> void:
	var half_fov := deg_to_rad(fov) * 0.5
	var distance: float = (radius * padding) / max(sin(half_fov), 0.1)
	distance = clamp(distance, min_distance, max_distance)

	var pitch := deg_to_rad(pitch_degrees)
	var offset := Vector3(0.0, sin(pitch), cos(pitch)) * distance

	_target_pos = center + offset
	var pos_t := 1.0 - exp(-position_smoothing * delta)
	var look_t := 1.0 - exp(-rotation_smoothing * delta)

	global_position = global_position.lerp(_target_pos, pos_t)
	_current_look = _current_look.lerp(center, look_t)
	look_at(_current_look, Vector3.UP)
