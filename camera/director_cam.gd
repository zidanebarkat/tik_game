extends Node
## Cinematic director camera (the "auto-follower"). While a battle is live it
## flies its own camera over the mid-fight, framing the action from a slow
## orbiting wide shot, then cutting to dramatic close-ups for key moments:
##
##   ENGAGE  - units from both sides clash in a melee cluster
##   ARRIVAL - a commander's warband marches in
##   SUPER   - the Meteor super power detonates
##   FINAL   - the battle ends (slow sweeping victory shot)
##
## The camera glides with exponential smoothing so every cut feels intentional.
## It yields whenever the user takes manual control (M camera cycle) and can be
## turned off with F4 (restores the previous camera).

const MODE := {
	"IDLE": 0,
	"WIDE": 1,
	"ENGAGE": 2,
	"ARRIVAL": 3,
	"SUPER": 4,
	"FINAL": 5,
}

@export_group("Framing")
@export var wide_distance: float = 78.0
@export var wide_height: float = 46.0
@export var orbit_speed := 0.07
@export var engage_distance: float = 30.0
@export var engage_height: float = 13.0
@export var arrive_distance: float = 24.0
@export var arrive_height: float = 9.0
@export var final_distance: float = 55.0
@export var final_height: float = 30.0

@export_group("Timing")
@export var engage_duration: float = 5.0
@export var engage_cooldown: float = 14.0
@export var arrival_duration: float = 3.8
@export var super_duration: float = 2.6
@export var final_duration: float = 7.0

@export_group("Detection")
@export var engage_radius: float = 5.5
@export var min_fighters: int = 3
@export var recompute_interval: float = 0.15

@export_group("Smoothing")
@export var pos_smooth: float = 4.0
@export var look_smooth: float = 6.0

@export_group("Bounds")
@export var cam_bound: float = 720.0
@export var min_height: float = 2.0
@export var max_height: float = 600.0

var battle_manager = null
var main_scene = null
var enabled := true

var _cam: Camera3D
var _mode: int = MODE.IDLE
var _timer := 0.0
var _cooldown := 0.0
var _orbit := 0.0
var _action_center := Vector3.ZERO
var _look := Vector3.ZERO
var _focus := Vector3.ZERO
var _shot_angle := 0.0
var _arrive_facing := Vector3(0.0, 0.0, 1.0)
var _recompute := 0.0
var _active := false
var _initialized := false

func _ready() -> void:
	_cam = Camera3D.new()
	_cam.name = "DirectorCam"
	_cam.fov = 70.0
	add_child(_cam)

func setup(bm, ms) -> void:
	battle_manager = bm
	main_scene = ms
	if bm and not bm.battle_ended.is_connected(_on_battle_ended):
		bm.battle_ended.connect(_on_battle_ended)
	if ms:
		var sp = ms.get_node_or_null("SuperPower")
		if sp and sp.has_signal("detonated") and not sp.detonated.is_connected(_on_super_detonated):
			sp.detonated.connect(_on_super_detonated)
	var cm = RegistryAccess.get_commander_manager()
	if cm and cm.has_signal("arrival_finished") and not cm.arrival_finished.is_connected(_on_arrival_finished):
		cm.arrival_finished.connect(_on_arrival_finished)

func is_active() -> bool:
	return _active

func toggle() -> void:
	enabled = not enabled
	if not enabled:
		_mode = MODE.IDLE
		_timer = 0.0
		_active = false
		if _cam:
			_cam.current = false
		if main_scene and main_scene.has_method("restore_manual_camera"):
			main_scene.restore_manual_camera()

## Hard stop: cancel whatever shot is running and hand the view back to the
## manual camera. Used when the game leaves the battlefield for the menu.
func stop() -> void:
	_mode = MODE.IDLE
	_timer = 0.0
	_active = false
	if _cam:
		_cam.current = false
	if main_scene and main_scene.has_method("restore_manual_camera"):
		main_scene.restore_manual_camera()

func _process(delta: float) -> void:
	if battle_manager == null:
		return
	_recompute -= delta
	if _recompute <= 0.0:
		_recompute = recompute_interval
		_update_action_center()
	_cooldown = maxf(_cooldown - delta, 0.0)

	var manual := false
	var sc = RegistryAccess.get_spectator()
	if sc:
		manual = sc.is_spectating() \
				or (sc.has_method("is_battle_mode") and sc.is_battle_mode())
	var in_battle: bool = battle_manager.current_state == battle_manager.BattleState.BATTLE \
			or _mode == MODE.FINAL
	var want_active: bool = enabled and in_battle and not manual

	if want_active:
		_active = true
		_cam.make_current()
	elif _active:
		_active = false
		_cam.current = false

	_update_mode(delta, in_battle)

func _update_mode(delta: float, in_battle: bool) -> void:
	if _mode == MODE.FINAL:
		_timer -= delta
		_final_shot(delta)
		if _timer <= 0.0:
			_mode = MODE.IDLE
			_restore()
		return
	if not in_battle:
		if _mode != MODE.IDLE:
			_mode = MODE.IDLE
			_restore()
		return
	if _mode == MODE.ENGAGE or _mode == MODE.ARRIVAL or _mode == MODE.SUPER:
		_timer -= delta
		if _timer <= 0.0:
			_mode = MODE.WIDE
	elif _mode == MODE.IDLE:
		_mode = MODE.WIDE

	if _mode == MODE.WIDE and _cooldown <= 0.0:
		var cluster = _detect_engagement()
		if cluster != null:
			_start_mode(MODE.ENGAGE, engage_duration, cluster)
			_cooldown = engage_cooldown

	match _mode:
		MODE.ENGAGE:
			_engage_shot(delta)
		MODE.ARRIVAL:
			_arrival_shot(delta)
		MODE.SUPER:
			_super_shot(delta)
		_:
			_wide_shot(delta)

func _start_mode(mode: int, duration: float, focus: Vector3) -> void:
	_mode = mode
	_timer = duration
	_focus = focus
	_shot_angle = randf_range(0.0, TAU)

func _on_arrival_finished(commander) -> void:
	if not enabled or battle_manager == null:
		return
	if battle_manager.current_state != battle_manager.BattleState.BATTLE:
		return
	if commander == null or not is_instance_valid(commander) or not commander.is_inside_tree():
		return
	_arrive_facing = commander.global_basis.z
	_arrive_facing.y = 0.0
	_arrive_facing = _arrive_facing.normalized() if _arrive_facing.length() > 0.01 \
			else Vector3(0.0, 0.0, 1.0)
	_start_mode(MODE.ARRIVAL, arrival_duration, commander.global_position)
	_active = true
	_cam.make_current()

func _on_super_detonated(pos: Vector3, _faction_id: int) -> void:
	if not enabled or battle_manager == null:
		return
	if battle_manager.current_state != battle_manager.BattleState.BATTLE:
		return
	_start_mode(MODE.SUPER, super_duration, pos)
	_active = true
	_cam.make_current()

func _on_battle_ended(_winning_faction) -> void:
	if not enabled:
		return
	_update_action_center()
	_start_mode(MODE.FINAL, final_duration, _action_center)
	_active = true
	_cam.make_current()

func _restore() -> void:
	_active = false
	if _cam:
		_cam.current = false
	if main_scene and main_scene.has_method("restore_manual_camera"):
		main_scene.restore_manual_camera()

func _update_action_center() -> void:
	var reg = RegistryAccess.get_registry()
	var acc := Vector3.ZERO
	var n := 0
	if reg:
		for u in reg.alive_units:
			if is_instance_valid(u) and u.current_health > 0.0:
				acc += u.global_position
				n += 1
	if n > 0:
		_action_center = acc / n
	else:
		_action_center = _fallback_center()
	_action_center.y = 0.0

func _fallback_center() -> Vector3:
	var acc := Vector3.ZERO
	var n := 0
	if battle_manager:
		for f in battle_manager.factions:
			if f and f.faction_data and f.faction_data.spawn_areas.size() > 0:
				var fa := Vector3.ZERO
				for a in f.faction_data.spawn_areas:
					fa += a
				acc += fa / f.faction_data.spawn_areas.size()
				n += 1
	if n > 0:
		return acc / n
	return Vector3.ZERO

## Returns the centroid of a melee cluster (units from both sides in contact),
## or null when there is no real fight going on right now.
func _detect_engagement():
	var reg = RegistryAccess.get_registry()
	if reg == null or reg.alive_units.is_empty() or battle_manager == null:
		return null
	var fighters: Array = []
	for u in reg.alive_units:
		if not is_instance_valid(u) or u.current_health <= 0.0:
			continue
		for e in battle_manager.get_nearby_units(u.global_position, engage_radius, u):
			if is_instance_valid(e) and e.faction_id != u.faction_id and e.current_health > 0.0:
				fighters.append(u)
				break
	if fighters.size() < min_fighters:
		return null
	var acc := Vector3.ZERO
	for u in fighters:
		acc += u.global_position
	var center := acc / fighters.size()
	center.y = 0.0
	return center

func _wide_shot(delta: float) -> void:
	_orbit += orbit_speed * delta
	var dist := wide_distance + sin(_orbit * 2.0) * 6.0
	var pos := _action_center + Vector3(cos(_orbit), 0.0, sin(_orbit)) * dist
	pos.y = wide_height
	_frame_to(_clamp_pos(pos), _action_center + Vector3(0.0, 5.0, 0.0), delta)

func _engage_shot(delta: float) -> void:
	var dir := Vector3(cos(_shot_angle), 0.0, sin(_shot_angle))
	var pos := _focus + dir * engage_distance
	pos.y = engage_height
	_frame_to(_clamp_pos(pos), _focus + Vector3(0.0, 2.5, 0.0), delta)

func _arrival_shot(delta: float) -> void:
	var pos := _focus - _arrive_facing * arrive_distance
	pos.y = arrive_height
	_frame_to(_clamp_pos(pos), _focus + Vector3(0.0, 2.0, 0.0), delta)

func _super_shot(delta: float) -> void:
	var dir := Vector3(cos(_shot_angle), 0.0, sin(_shot_angle))
	var pos := _focus + dir * 26.0
	pos.y = 22.0
	_frame_to(_clamp_pos(pos), _focus, delta)

func _final_shot(delta: float) -> void:
	_orbit += orbit_speed * 0.6 * delta
	var pos := _action_center + Vector3(cos(_orbit), 0.0, sin(_orbit)) * final_distance
	pos.y = final_height
	_frame_to(_clamp_pos(pos), _action_center + Vector3(0.0, 4.0, 0.0), delta)

func _frame_to(pos: Vector3, look: Vector3, delta: float) -> void:
	if not _initialized:
		_initialized = true
		_cam.global_position = pos
		_look = look
	_cam.global_position = _cam.global_position.lerp(pos, 1.0 - exp(-pos_smooth * delta))
	_look = _look.lerp(look, 1.0 - exp(-look_smooth * delta))
	if _cam.global_position.distance_to(_look) > 0.5:
		_cam.look_at(_look, Vector3.UP)

func _clamp_pos(p: Vector3) -> Vector3:
	p.x = clampf(p.x, -cam_bound, cam_bound)
	p.z = clampf(p.z, -cam_bound, cam_bound)
	p.y = clampf(p.y, min_height, max_height)
	return p
