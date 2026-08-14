extends Node
## SpectatorCam autoload: 3rd-person follow camera that can attach to any
## living unit. Press M to toggle; hold M to cycle targets; auto-switches when
## the spectated unit dies. The rig uses kinematic repositioning + slerp
## smoothing instead of reparenting so it can never be freed along with a dying
## unit and rotation is smooth instead of snapping.

const CAMERA_CONFIG := {
	"militia":   {"height": 2.0, "distance": 4.5, "pitch": 18.0},
	"spearman":  {"height": 2.2, "distance": 5.0, "pitch": 18.0},
	"knight":    {"height": 2.6, "distance": 5.8, "pitch": 18.0},
	"tank":      {"height": 4.5, "distance": 10.0, "pitch": 22.0},
	"titan":     {"height": 5.5, "distance": 13.0, "pitch": 22.0},
	"commander": {"height": 3.2, "distance": 7.0, "pitch": 18.0},
}
const DEFAULT_CFG := {"height": 2.5, "distance": 6.0, "pitch": 18.0}

const LOOK_AHEAD := 3.0
const LOOK_UP := 1.0

const FOLLOW_SPEED := 10.0
const ROT_SPEED := 6.0
const VEL_SMOOTH := 8.0
const VEL_MIN := 0.15
const CYCLE_HOLD_DELAY := 0.6
const CYCLE_INTERVAL := 1.2
const DEATH_HOLD := 1.2
const ARRIVAL_CUT_TIME := 3.0

var active := false
var target = null
var main_camera: Camera3D = null

## Part 7: when a commander squad's arrival march finishes while we are already
## spectating, snap to that commander for a few seconds, then hand control back
## to whoever was being followed before. Toggleable at runtime.
var auto_cut_on_arrival: bool = true

var rig: Node3D
var spring: SpringArm3D
var camera: Camera3D

var _hold_time := 0.0
var _cycle_timer := 0.0
var _pending_switch := -1.0
var _return_target = null
var _arrival_cut_timer := -1.0
var _arrival_connected := false
var _last_tpos := Vector3.INF
var _smooth_vel := Vector3.ZERO

func _ready() -> void:
	rig = Node3D.new()
	rig.name = "SpectatorRig"
	spring = SpringArm3D.new()
	spring.name = "SpringArm"
	spring.spring_length = 6.0
	spring.margin = 0.05
	spring.collision_mask = 0b10
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.fov = 70.0
	spring.add_child(camera)
	rig.add_child(spring)
	add_child(rig)
	rig.visible = false
	var reg = RegistryAccess.get_registry()
	if reg:
		reg.unit_died.connect(_on_unit_died)

func setup(main_cam: Camera3D) -> void:
	main_camera = main_cam

func is_spectating() -> bool:
	return active

func get_current_target():
	return target if active else null

func _process(delta: float) -> void:
	if not _arrival_connected:
		var cm = RegistryAccess.get_commander_manager()
		if cm and cm.has_signal("arrival_finished"):
			cm.arrival_finished.connect(_on_arrival_finished)
			_arrival_connected = true
	if Input.is_action_just_pressed("spectate_toggle"):
		if active:
			_toggle_off()
		else:
			_toggle_on()
		return
	if not active:
		return
	if Input.is_key_pressed(KEY_M):
		_hold_time += delta
		if _hold_time >= CYCLE_HOLD_DELAY:
			_cycle_timer -= delta
			if _cycle_timer <= 0.0:
				_cycle()
				_cycle_timer = CYCLE_INTERVAL
	else:
		_hold_time = 0.0
	if _pending_switch > 0.0:
		_pending_switch -= delta
		if _pending_switch <= 0.0:
			_pending_switch = -1.0
			_cycle()
	if target == null or not is_instance_valid(target) or not target.is_inside_tree():
		if _pending_switch > 0.0:
			_pending_switch = -1.0
			_cycle()
		else:
			_toggle_off()
		return
	if _arrival_cut_timer > 0.0:
		_arrival_cut_timer -= delta
		if _arrival_cut_timer <= 0.0:
			_arrival_cut_timer = -1.0
			_end_arrival_cut()
	_update_follow(delta)

func _toggle_on() -> void:
	if main_camera == null:
		return
	var reg = RegistryAccess.get_registry()
	if reg == null:
		return
	var pick = reg.pick_spectate_target()
	if pick == null:
		return
	active = true
	_hold_time = 0.0
	_cycle_timer = 0.0
	_pending_switch = -1.0
	_return_target = null
	_arrival_cut_timer = -1.0
	rig.visible = true
	_attach(pick)
	camera.current = true
	if main_camera and is_instance_valid(main_camera):
		main_camera.current = false

func _toggle_off() -> void:
	active = false
	target = null
	_pending_switch = -1.0
	_return_target = null
	_arrival_cut_timer = -1.0
	rig.visible = false
	camera.current = false
	if main_camera and is_instance_valid(main_camera):
		main_camera.current = true

func _cycle() -> void:
	if not active:
		return
	var reg = RegistryAccess.get_registry()
	if reg == null:
		_toggle_off()
		return
	var next = reg.pick_spectate_target(target)
	if next == null:
		_toggle_off()
		return
	_return_target = null
	_arrival_cut_timer = -1.0
	_attach(next)

func _attach(unit) -> void:
	target = unit
	_last_tpos = unit.global_position
	_smooth_vel = Vector3.ZERO
	var cfg = CAMERA_CONFIG.get(unit.get_unit_type(), DEFAULT_CFG)
	spring.spring_length = cfg.distance
	spring.rotation_degrees = Vector3(-cfg.pitch, 0.0, 0.0)
	rig.global_position = unit.global_position + Vector3(0, cfg.height, 0)
	rig.rotation = Vector3(0, unit.rotation.y, 0)

func _update_follow(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	var cfg = CAMERA_CONFIG.get(target.get_unit_type(), DEFAULT_CFG)
	spring.spring_length = cfg.distance
	spring.rotation_degrees = Vector3(-cfg.pitch, 0.0, 0.0)
	var goal_pos = target.global_position + Vector3(0, cfg.height, 0)
	rig.global_position = rig.global_position.lerp(goal_pos, minf(1.0, FOLLOW_SPEED * delta))
	# Heading comes from the unit's real travel direction, smoothed over time,
	# never its raw rotation.y: units spin frame-to-frame while fighting and
	# tracking that yaw is what made the view shake. When the unit stops to
	# attack, the camera keeps the last heading instead of jittering.
	var tpos: Vector3 = target.global_position
	if _last_tpos.is_finite():
		var inst_vel: Vector3 = (tpos - _last_tpos) / maxf(delta, 0.0001)
		_smooth_vel = _smooth_vel.lerp(inst_vel, minf(1.0, VEL_SMOOTH * delta))
	_last_tpos = tpos
	var vel := _smooth_vel
	vel.y = 0.0
	if vel.length() > VEL_MIN:
		rig.rotation.y = lerp_angle(rig.rotation.y, atan2(-vel.x, -vel.z), minf(1.0, ROT_SPEED * delta))
	var facing := Vector3(-sin(rig.rotation.y), 0.0, -cos(rig.rotation.y))
	var ahead = target.global_position + facing * LOOK_AHEAD + Vector3(0, LOOK_UP, 0)
	if camera.global_position.distance_to(ahead) > 0.01:
		camera.look_at(ahead, Vector3.UP)

func _on_unit_died(unit) -> void:
	if not active or unit != target:
		return
	_pending_switch = DEATH_HOLD

## Part 7: the arrival march of a commander's warband finished, so snap the
## camera onto the commander for a few seconds if we're already spectating and
## the toggle is on. The previous target is restored once the cut expires.
func _on_arrival_finished(commander) -> void:
	if not auto_cut_on_arrival or not active:
		return
	if commander == null or not is_instance_valid(commander) \
			or not commander.is_inside_tree() or commander._dying:
		return
	cut_to_commander(commander)

func cut_to_commander(commander) -> void:
	if not active or commander == null or not is_instance_valid(commander):
		return
	_return_target = target
	_arrival_cut_timer = ARRIVAL_CUT_TIME
	_attach(commander)

func _end_arrival_cut() -> void:
	var reg = RegistryAccess.get_registry()
	var ret = _return_target
	_return_target = null
	if ret != null and is_instance_valid(ret) and ret.is_inside_tree() \
			and reg and reg.is_eligible(ret):
		_attach(ret)
	else:
		_cycle()
