extends Node3D
## Gift-triggered execute ultimate (UEBS-style super strike). Auto-targets the
## densest cluster of the enemy faction, telegraphs a burning ground ring for
## a beat, then instant-kills every enemy inside the blast. Kills go through
## execute_kill() which bypasses HP/armor entirely, so even Titans die.
## Gift-triggered, so a short lockout stops back-to-back gifts from stacking
## detonations.

@export_group("Power")
@export var radius: float = 9.0
@export var telegraph_time: float = 0.9
@export var lockout_time: float = 3.0

@export_group("Telegraph")
@export var ring_color := Color(1.0, 0.5, 0.12)
@export var beam_color := Color(1.0, 0.75, 0.25)
@export var beam_height := 16.0

@export_group("Detonation")
@export var flash_color := Color(1.0, 0.6, 0.15)
@export var particle_count := 48
@export var particle_lifetime := 0.8

var _battle_manager = null
var _last_trigger := -INF
var _telegraph_nodes: Array = []

func setup(bm) -> void:
	_battle_manager = bm

func is_available() -> bool:
	return _battle_manager != null \
		and Time.get_ticks_msec() / 1000.0 >= _last_trigger + lockout_time

## Destroys every unit of `target_faction` in the densest cluster. Returns
## false when no enemies exist or the power is still on lockout. Telegraph and
## detonation are fire-and-forget (signal-connected timer, no await) so gift
## handlers can call it synchronously.
func trigger_super(target_faction: int) -> bool:
	if _battle_manager == null or not is_available():
		return false
	var pos = _densest_cluster(target_faction)
	if pos == null:
		return false
	_last_trigger = Time.get_ticks_msec() / 1000.0
	_telegraph(pos)
	get_tree().create_timer(telegraph_time).timeout.connect(_detonate.bind(pos, target_faction))
	return true

func _densest_cluster(faction_id: int):
	var best_pos: Vector3 = Vector3.ZERO
	var best_count := 0
	for f in _battle_manager.factions:
		if f.faction_id != faction_id:
			continue
		for u in f.units:
			if not is_instance_valid(u) or u.current_health <= 0.0:
				continue
			var n := 0
			for other in _battle_manager.get_nearby_units(u.global_position, radius, u):
				if other.faction_id == faction_id and other.current_health > 0.0:
					n += 1
			if n > best_count:
				best_count = n
				best_pos = u.global_position
	return best_pos if best_count > 0 else null

func _telegraph(pos: Vector3) -> void:
	pos.y = 0.0
	_telegraph_nodes = [_make_disc(pos), _make_beam(pos)]

func _make_disc(pos: Vector3) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 0.06
	var mat := _glow_material(ring_color, 0.0)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	add_child(mi)
	mi.global_position = pos + Vector3(0, 0.04, 0)
	mi.scale = Vector3(0.08, 1.0, 0.08)
	var tw := create_tween()
	tw.tween_property(mi, "scale", Vector3.ONE, telegraph_time).set_trans(Tween.TRANS_CUBIC)
	tw.parallel().tween_method(_set_glow_alpha.bind(mat, ring_color), 0.0, 0.85, telegraph_time)
	return mi

func _make_beam(pos: Vector3) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.35
	mesh.bottom_radius = 0.35
	mesh.height = 1.0
	var mat := _glow_material(beam_color, 0.45)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	add_child(mi)
	mi.global_position = pos + Vector3(0, beam_height * 0.5, 0)
	mi.scale = Vector3(1.0, 0.01, 1.0)
	var tw := create_tween()
	tw.tween_property(mi, "scale", Vector3(1.0, beam_height, 1.0), telegraph_time).set_trans(Tween.TRANS_CUBIC)
	return mi

func _glow_material(color: Color, alpha: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(color, alpha)
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy = 2.0
	return mat

func _set_glow_alpha(a: float, mat: StandardMaterial3D, color: Color) -> void:
	mat.albedo_color = Color(color, a)

func _detonate(pos: Vector3, faction_id: int) -> void:
	pos.y = 0.0
	_flash(pos)
	_particles(pos)
	for u in _battle_manager.get_nearby_units(pos, radius, null):
		if u.faction_id == faction_id and u.has_method("execute_kill") \
				and not u._dying and u.current_health > 0.0:
			u.execute_kill()
	for n in _telegraph_nodes:
		if is_instance_valid(n):
			n.queue_free()
	_telegraph_nodes = []

func _flash(pos: Vector3) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	var mat := _glow_material(flash_color, 0.9)
	var s := MeshInstance3D.new()
	s.mesh = mesh
	s.material_override = mat
	add_child(s)
	s.global_position = pos + Vector3(0, 0.8, 0)
	var tw := create_tween()
	tw.tween_property(s, "scale", Vector3.ONE * radius, 0.35).set_trans(Tween.TRANS_QUAD)
	tw.parallel().tween_method(_set_glow_alpha.bind(mat, flash_color), 0.9, 0.0, 0.45)
	tw.tween_callback(s.queue_free)

func _particles(pos: Vector3) -> void:
	var p := CPUParticles3D.new()
	p.amount = particle_count
	p.lifetime = particle_lifetime
	p.one_shot = true
	p.explosiveness = 1.0
	p.spread = 180.0
	p.direction = Vector3.UP
	p.gravity = Vector3(0.0, -6.0, 0.0)
	p.initial_velocity_min = 6.0
	p.initial_velocity_max = 12.0
	p.scale_amount_min = 0.3
	p.scale_amount_max = 0.7
	p.color = Color(1.0, 0.6, 0.15, 0.9)
	p.emitting = true
	add_child(p)
	p.global_position = pos + Vector3(0, 0.2, 0)
	p.finished.connect(p.queue_free)
