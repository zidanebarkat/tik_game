extends CharacterBody3D

const UnitStateScript = preload("res://ai/state_machine.gd")
const TITAN_RIG_SCENE := preload("res://units/models/titan_rig.tscn")
const PALADIN_RIG_SCENE := preload("res://units/models/paladin_rig.tscn")
const TANK_SCENE := preload("res://assets/weapons/tank/tank.tscn")
const MUZZLE_FLASH_SCENE := preload("res://effects/muzzle_flash.tscn")
const TANK_MUZZLE_OFFSET := Vector3(0.0, 1.79, -2.46)

@export var stats: Resource
@export var faction_id: int = 0
var faction_manager = null

var current_health: float = 0.0
var state_machine = null
var squad_id: int = 0
var squad_offset: Vector3 = Vector3.ZERO
var attack_phase: float = 0.0
var experience: int = 0
var level: int = 1
var kills: int = 0
var deaths: int = 0
var damage_dealt: float = 0.0
var distance_traveled: float = 0.0
var gift_owner: String = ""
var display_name: String = ""
var commander_id: String = ""
var commander_name: String = ""
var portrait_texture: Texture2D = null
var aura_damage_mult: float = 1.0
var faction_tag: String = ""
var reinforce_waypoint: Vector3 = Vector3.INF
var reinforce_time: float = 0.0
var march_leader: bool = false
var march_slot: Vector3 = Vector3.ZERO
var march_speed: float = 3.2
var banner_color: Color = Color(0.85, 0.7, 0.2)
var commander_title: String = ""
var commander_title_color: Color = Color(0.9, 0.85, 0.7)
var _marching: bool = false
var _march_leader_ref = null
var _aura_tick: int = 0
var _banner_falling := false
var _think_tick := 0
var _think_delta := 0.0

const AURA_RADIUS := 16.0
const AURA_DAMAGE_MULT := 1.1
const AURA_TICK_FRAMES := 30

var _last_position: Vector3
var _last_attacker = null
var _last_damage_time: float = -100.0

var _surface_type: String = "stone"
var _step_accum: float = 0.0
const STEP_INTERVAL := 2.2

var _anim_player = null
var _current_anim: String = ""
var _anim_enabled: bool = true
var _anim_lod_tick: int = 0
var _idle_anim: String = "idle"
var _move_anim: String = "walk"
var _attack_anim: String = "attack"
var _death_anim: String = "death"
var _dying: bool = false
var _dying_timer: float = 0.0
var _knockback: Vector3 = Vector3.ZERO
var _knockback_time: float = 0.0
var _ground_tick: int = 0
var _muzzle_flash = null
var _banner = null
var _nameplate = null

const TITAN_BITE_BONES := {
	"jawJA_JNT_1_2": 32.0,
	"headJA_JNT_4_5": -26.0,
	"neckJA_JNT_6_7": 22.0,
	"neckJB_JNT_5_6": 19.0,
	"neckJC_JNT_0_1": 15.0,
	"spineJA_JNT_125_126": 6.0,
	"spineJB_JNT_53_54": 5.5,
	"spineJC_JNT_52_53": 4.5,
	"spineJD_JNT_51_52": 4.0,
	"spineJE_JNT_50_51": 3.0,
	"spineJF_JNT_49_50": 2.5,
	"l_armJA_JNT_26_27": 35.0,
	"r_armJA_JNT_47_48": 35.0,
}
const TITAN_BITE_TIMES := [0.0, 0.8, 1.15, 1.45, 1.8, 2.5]
const TITAN_BITE_AMOUNT := [0.0, 0.0, 1.0, 1.0, 0.0, 0.0]
const TITAN_BITE_LUNGE := [0.0, 0.0, 14.0, 14.0, 0.0, 0.0]

const ANIM_LOD_DISTANCE := 70.0
const ANIM_LOD_TICKS := 15

const THINK_LOD_DISTANCE := 80.0
const THINK_LOD_TICKS := 8

func _ready() -> void:
	current_health = stats.max_health
	state_machine = UnitStateScript.new(self)
	attack_phase = randf_range(0.0, 0.35)
	_setup_visual()
	_last_position = global_position
	_register_with_registry()

func _register_with_registry() -> void:
	var reg = RegistryAccess.get_registry()
	if reg:
		reg.register(self)

func _unregister_from_registry() -> void:
	var reg = RegistryAccess.get_registry()
	if reg:
		reg.unregister(self)

func _setup_visual() -> void:
	var rig_scene: PackedScene = TANK_SCENE if stats.unit_name == "Tank" else (TITAN_RIG_SCENE if stats.unit_name == "Titan" else PALADIN_RIG_SCENE)
	if not rig_scene:
		return
	var visual = rig_scene.instantiate()
	visual.name = "Visual"
	add_child(visual)
	visual.rotation.y = PI
	_anim_player = visual.get_node_or_null("AnimationPlayer")
	if stats.unit_name == "Titan":
		_idle_anim = "idle"
		_move_anim = "idle"
		_attack_anim = "bite"
		_death_anim = ""
		_build_titan_bite_anim()
	elif stats.unit_name == "Commander":
		_move_anim = "run"
		_attack_anim = "slash"
		_build_commander_banner()
	else:
		_move_anim = "run" if stats.unit_name == "Knight" else "walk"
		_attack_anim = "slash"
	_enter_idle_pose()
	_apply_team_color(visual)
	if stats.unit_name == "Tank":
		_muzzle_flash = MUZZLE_FLASH_SCENE.instantiate()
		_muzzle_flash.name = "MuzzleFlash"
		_muzzle_flash.position = TANK_MUZZLE_OFFSET
		add_child(_muzzle_flash)

func flash_muzzle() -> void:
	if _muzzle_flash and is_instance_valid(_muzzle_flash):
		_muzzle_flash.call("flash")

func _apply_team_color(root: Node) -> void:
	var mat: StandardMaterial3D = null
	if faction_manager and faction_manager.has_method("get_team_material"):
		mat = faction_manager.get_team_material()
	if mat == null:
		mat = StandardMaterial3D.new()
		mat.albedo_color = Color.WHITE
		mat.metallic = 0.0
		mat.roughness = 0.85
	_tint_meshes(root, mat)

func _tint_meshes(node: Node, mat: StandardMaterial3D) -> void:
	for child in node.get_children():
		if child is MeshInstance3D and child.mesh != null:
			child.material_override = mat
		if child.get_child_count() > 0:
			_tint_meshes(child, mat)

func _play_anim(name: String) -> void:
	if name.is_empty() or not _anim_player or not _anim_player.has_animation(name):
		return
	if name != _current_anim:
		_anim_player.play(name)
		_current_anim = name

func _enter_idle_pose() -> void:
	if not _anim_player or _current_anim == _idle_anim:
		return
	_anim_player.play(_idle_anim)
	_anim_player.pause()
	_anim_player.seek(0.0, true)
	_current_anim = _idle_anim

func _update_anim_lod() -> void:
	_anim_lod_tick += 1
	if _anim_lod_tick % ANIM_LOD_TICKS != 0:
		return
	if not _anim_player:
		return
	var should_animate := true
	var cam := get_viewport().get_camera_3d()
	if cam:
		should_animate = global_position.distance_to(cam.global_position) <= ANIM_LOD_DISTANCE
	if should_animate and not _anim_enabled:
		_anim_player.process_mode = Node.PROCESS_MODE_INHERIT
		_anim_enabled = true
	elif not should_animate and _anim_enabled:
		_anim_player.process_mode = Node.PROCESS_MODE_DISABLED
		_anim_enabled = false

## Part 9: squad units far from the current camera drop their AI think-rate to
## a fraction (kept time-correct by accumulating delta). Only squad units get
## this — host/raider units keep full-rate AI.
func _should_throttle_think() -> bool:
	if commander_id.is_empty():
		return false
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return false
	return global_position.distance_to(cam.global_position) > THINK_LOD_DISTANCE

func _build_titan_bite_anim() -> void:
	if not _anim_player or not _anim_player.has_animation("idle"):
		return
	var idle: Animation = _anim_player.get_animation("idle")
	var bite: Animation = idle.duplicate(true)
	bite.resource_name = "bite"
	bite.length = 2.5
	bite.loop_mode = Animation.LOOP_LINEAR
	for t in range(bite.get_track_count()):
		if bite.track_get_type(t) != Animation.TYPE_ROTATION_3D:
			continue
		var bone: String = str(bite.track_get_path(t)).get_slice(":", 1)
		if not TITAN_BITE_BONES.has(bone):
			continue
		var base: Quaternion = idle.track_get_key_value(t, 0)
		while bite.track_get_key_count(t) > 0:
			bite.track_remove_key(t, 0)
		for i in range(TITAN_BITE_TIMES.size()):
			var delta := Quaternion(Vector3(1, 0, 0), deg_to_rad(TITAN_BITE_BONES[bone] * TITAN_BITE_AMOUNT[i]))
			bite.track_insert_key(t, TITAN_BITE_TIMES[i], base * delta)
	var pt := bite.add_track(Animation.TYPE_POSITION_3D)
	bite.track_set_path(pt, NodePath("Skeleton3D:GLTF_created_0_rootJoint"))
	bite.track_set_interpolation_type(pt, Animation.INTERPOLATION_LINEAR)
	for i in range(TITAN_BITE_TIMES.size()):
		bite.track_insert_key(pt, TITAN_BITE_TIMES[i], Vector3(0, 0, TITAN_BITE_LUNGE[i]))
	_anim_player.get_animation_library("").add_animation("bite", bite)

func apply_knockback(impulse: Vector3, duration: float = 0.2) -> void:
	_knockback = impulse
	_knockback_time = maxf(_knockback_time, duration)

func _build_commander_banner() -> void:
	var banner := Node3D.new()
	banner.name = "Banner"
	banner.position = Vector3(0, 1.15, 0.5)
	add_child(banner)
	_banner = banner

	var pole_mat := StandardMaterial3D.new()
	pole_mat.albedo_color = banner_color.lightened(0.15)
	pole_mat.metallic = 0.6
	pole_mat.roughness = 0.4

	var pole := MeshInstance3D.new()
	pole.name = "Pole"
	var pole_mesh := CylinderMesh.new()
	pole_mesh.top_radius = 0.035
	pole_mesh.bottom_radius = 0.035
	pole_mesh.height = 2.3
	pole_mesh.radial_segments = 6
	pole.mesh = pole_mesh
	pole.position = Vector3(0, 1.15, 0.0)
	pole.material_override = pole_mat
	banner.add_child(pole)

	var flag := MeshInstance3D.new()
	flag.name = "Flag"
	var flag_mesh := QuadMesh.new()
	flag_mesh.size = Vector2(0.95, 0.62)
	flag.mesh = flag_mesh
	flag.position = Vector3(0.02, 2.32, 0.06)
	flag.rotation_degrees = Vector3(0, 90, 0)
	var flag_mat := StandardMaterial3D.new()
	flag_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if portrait_texture:
		flag_mat.albedo_texture = portrait_texture
	else:
		flag_mat.albedo_color = banner_color
	flag.material_override = flag_mat
	banner.add_child(flag)

	var finial := MeshInstance3D.new()
	finial.name = "Finial"
	var sphere := SphereMesh.new()
	sphere.radius = 0.08
	sphere.height = 0.16
	sphere.radial_segments = 8
	sphere.rings = 4
	finial.mesh = sphere
	finial.position = Vector3(0, 2.35, 0.0)
	finial.material_override = pole_mat
	banner.add_child(finial)

	var plate := Label3D.new()
	plate.name = "Nameplate"
	var title_prefix := ""
	if not commander_title.is_empty():
		title_prefix = "%s " % commander_title
	plate.text = title_prefix + get_display_name()
	plate.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	plate.pixel_size = 0.006
	plate.font_size = 64
	plate.outline_size = 12
	plate.outline_modulate = Color(0, 0, 0, 0.9)
	plate.modulate = commander_title_color
	plate.position = Vector3(0, 2.7, 0)
	banner.add_child(plate)
	_nameplate = plate

func _set_banner_theme_color(color: Color) -> void:
	if not _banner:
		return
	var flag = _banner.get_node_or_null("Flag")
	if flag and flag.material_override and portrait_texture == null:
		(flag.material_override as StandardMaterial3D).albedo_color = color

func _physics_process(delta: float) -> void:
	if _dying:
		_dying_timer -= delta
		if _banner and _banner_falling:
			_banner.rotation.x = move_toward(_banner.rotation.x, PI / 2.0, delta * 2.2)
			_banner.global_position.y = lerpf(_banner.global_position.y, global_position.y + 0.15, delta * 3.0)
		if _knockback_time > 0.0:
			_dying_timer = maxf(_dying_timer, _knockback_time)
			_knockback_time -= delta
			velocity = _knockback
			_knockback *= 0.9
			move_and_slide()
		if _dying_timer <= 0.0:
			queue_free()
		return
	if state_machine and state_machine.current_state == UnitStateScript.State.DEAD:
		return
	if _knockback_time > 0.0:
		_knockback_time -= delta
		if _knockback_time <= 0.0:
			_knockback = Vector3.ZERO
			velocity = Vector3.ZERO
		else:
			velocity = _knockback
			_knockback *= 0.88
		move_and_slide()
		_stick_to_ground()
		if is_inside_tree():
			distance_traveled += global_position.distance_to(_last_position)
			_last_position = global_position
		return
	if _marching:
		_update_march(delta)
		_play_anim(_move_anim)
		_stick_to_ground()
		_accumulate_step()
		if is_inside_tree():
			distance_traveled += global_position.distance_to(_last_position)
			_last_position = global_position
		return
	_tick_aura()
	_update_anim_lod()
	if state_machine:
		if _should_throttle_think():
			_think_delta += delta
			_think_tick += 1
			if _think_tick % THINK_LOD_TICKS == 0:
				state_machine.update(_think_delta)
				_think_delta = 0.0
			else:
				# Thinking is throttled but movement must not be: keep sliding
				# with the last commanded velocity so far units don't crawl.
				move_and_slide()
		else:
			_think_delta = 0.0
			_think_tick = 0
			state_machine.update(delta)
		match state_machine.current_state:
			UnitStateScript.State.ATTACK:
				_play_anim(_attack_anim)
			UnitStateScript.State.SEEK, UnitStateScript.State.MOVE:
				_play_anim(_move_anim)
			_:
				_enter_idle_pose()
	_stick_to_ground()
	_accumulate_step()
	if is_inside_tree():
		distance_traveled += global_position.distance_to(_last_position)
		_last_position = global_position

func _stick_to_ground() -> void:
	if not is_inside_tree():
		return
	_ground_tick += 1
	if _ground_tick % 12 != 0:
		return
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3(0, 30, 0)
	var to := global_position + Vector3(0, -50, 0)
	var query := PhysicsRayQueryParameters3D.create(from, to, 2, [get_rid()])
	var hit := space.intersect_ray(query)
	if hit:
		global_position.y = hit.position.y
		_refresh_surface(hit)

## Reads the tagged ground surface under the unit (Part 4 footstep feedback).
func _refresh_surface(hit: Dictionary) -> void:
	var coll := hit.get("collider") as Object
	if coll:
		var surf = coll.get("surface_type")
		if surf is String and not surf.is_empty():
			_surface_type = surf

func _is_walking() -> bool:
	if _marching:
		return true
	if state_machine:
		var st: int = state_machine.current_state
		return st == UnitStateScript.State.MOVE or st == UnitStateScript.State.SEEK
	return false

func _accumulate_step() -> void:
	if not _is_walking():
		_step_accum = 0.0
		return
	var dx := global_position.x - _last_position.x
	var dz := global_position.z - _last_position.z
	_step_accum += sqrt(dx * dx + dz * dz)
	if _step_accum < STEP_INTERVAL:
		return
	_step_accum = 0.0
	_emit_footstep()

func _emit_footstep() -> void:
	var fx = FootstepFX.get_instance()
	if fx:
		fx.play_step(global_position, _surface_type)

func take_damage(amount: float, attacker = null) -> void:
	var final_damage = max(amount - stats.armor, 0.0)
	current_health -= final_damage
	_last_attacker = attacker
	_last_damage_time = Time.get_ticks_msec() / 1000.0
	if attacker and is_instance_valid(attacker) and attacker != self:
		attacker.damage_dealt += final_damage
	if current_health <= 0:
		die()

const RECENT_ATTACKER_WINDOW := 2.5

func get_last_attacker():
	if not _last_attacker:
		return null
	if not is_instance_valid(_last_attacker) or not _last_attacker.is_inside_tree():
		return null
	if Time.get_ticks_msec() / 1000.0 - _last_damage_time > RECENT_ATTACKER_WINDOW:
		return null
	return _last_attacker

func heal(amount: float) -> void:
	current_health = min(current_health + amount, stats.max_health)

func die() -> void:
	if _dying:
		return
	_dying = true
	if _banner:
		_banner_falling = true
	_unregister_from_registry()
	if _knockback_time <= 0.0:
		velocity = Vector3.ZERO
	if state_machine:
		state_machine.transition_to(UnitStateScript.State.DEAD)
	deaths += 1
	if _last_attacker and is_instance_valid(_last_attacker):
		_last_attacker.kills += 1
		var fm = _last_attacker.faction_manager
		if fm:
			fm.kills += 1
		var bm = faction_manager.battle_manager if faction_manager else null
		if bm:
			bm.total_kills += 1
	if faction_manager and faction_manager.has_method("on_unit_died"):
		faction_manager.on_unit_died(self)
	_play_anim(_death_anim)
	_dying_timer = _death_duration()

func _death_duration() -> float:
	if not _death_anim.is_empty() and _anim_player and _anim_player.has_animation(_death_anim):
		return min(_anim_player.get_animation(_death_anim).length, 2.0)
	return 0.5

func get_health_percent() -> float:
	return current_health / stats.max_health if stats.max_health > 0 else 0.0

func get_unit_type() -> String:
	return stats.unit_name.to_lower()

func get_faction_tag() -> String:
	if not faction_tag.is_empty():
		return faction_tag
	if not commander_id.is_empty():
		return "commander_" + commander_id
	return "host" if faction_id == 0 else "raiders"

func get_display_name() -> String:
	return display_name if not display_name.is_empty() else stats.unit_name

func start_march(waypoint: Vector3, is_leader: bool, slot: Vector3) -> void:
	reinforce_waypoint = waypoint
	march_leader = is_leader
	march_slot = slot
	_marching = true
	_march_leader_ref = null

func _release_from_march() -> void:
	_marching = false
	reinforce_waypoint = Vector3.INF
	_march_leader_ref = null

func is_marching() -> bool:
	return _marching

func _find_march_leader():
	var reg = RegistryAccess.get_registry()
	if not reg:
		return null
	for c in reg.get_alive_commanders():
		if is_instance_valid(c) and c != self \
				and c.commander_id == commander_id and c.march_leader:
			return c
	return null

func _update_march(delta: float) -> void:
	if march_leader:
		var target := reinforce_waypoint
		var diff := target - global_position
		diff.y = 0.0
		var dist := diff.length()
		if dist <= 1.5:
			_release_from_march()
			return
		var step := march_speed * delta
		var dir := diff / maxf(dist, 0.001)
		global_position += dir * minf(step, dist)
		rotation.y = atan2(-dir.x, -dir.z)
		velocity = dir * march_speed
		return
	if _march_leader_ref == null or not is_instance_valid(_march_leader_ref):
		_march_leader_ref = _find_march_leader()
	if _march_leader_ref == null or not _march_leader_ref._marching:
		_release_from_march()
		return
	var target = _march_leader_ref.global_position + march_slot
	var diff2 = target - global_position
	diff2.y = 0.0
	var dist2 = diff2.length()
	if dist2 <= 0.6:
		global_position.x = target.x
		global_position.z = target.z
		return
	var step2 := march_speed * delta
	var dir2 = diff2 / maxf(dist2, 0.001)
	global_position += dir2 * minf(step2, dist2)
	rotation.y = atan2(-dir2.x, -dir2.z)
	velocity = dir2 * march_speed

func is_spectate_eligible() -> bool:
	return not _dying and is_inside_tree() and current_health > 0.0

func get_current_target():
	return state_machine.target if state_machine else null

func _tick_aura() -> void:
	_aura_tick += 1
	if _aura_tick % AURA_TICK_FRAMES != 0:
		return
	aura_damage_mult = 1.0
	if commander_id.is_empty() or stats.unit_name == "Commander" or _dying or not faction_manager:
		return
	for u in faction_manager.units:
		if not is_instance_valid(u) or u == self or u._dying:
			continue
		if u.get_unit_type() != "commander" or u.commander_id != commander_id:
			continue
		if global_position.distance_to(u.global_position) <= AURA_RADIUS:
			aura_damage_mult = AURA_DAMAGE_MULT
			break

func _exit_tree() -> void:
	_unregister_from_registry()
