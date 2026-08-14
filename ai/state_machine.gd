extends RefCounted

enum State { IDLE, MOVE, SEEK, ATTACK, RETREAT, DEAD }

const SEP_RADIUS := 1.0
const SEP_FORCE := 1.5
const TARGET_REACQUIRE_INTERVAL := 0.25
# Movement smoothing: units accelerate/decelerate toward a desired velocity and
# turn toward a heading at a bounded rate instead of snapping both each frame.
const ACCEL := 8.0
const TURN_RATE := 10.0
const CHASE_LEAD := 0.7
const CHASE_LEAD_MAX := 2.5
const CHASE_REAIM := 0.6

var unit: CharacterBody3D
var current_state: State = State.IDLE
var target: CharacterBody3D = null
var state_time: float = 0.0
var _acquire_cooldown: float = 0.0
var _threat_timer: float = 0.0
var _advance_dir: Vector3 = Vector3.FORWARD
var _aim_timer: float = 0.0
var _chase_aim: Vector3 = Vector3.ZERO
var _chase_timer: float = 0.0

func _init(p_unit: CharacterBody3D) -> void:
	unit = p_unit

func transition_to(new_state: State) -> void:
	current_state = new_state
	state_time = 0.0
	# Attack-phase sync: each unit's first strike of a melee is offset by a
	# small per-unit phase, so a squad's hits land inside one coordinated
	# window instead of firing on identical timers.
	if new_state == State.ATTACK and "attack_phase" in unit:
		state_time = -unit.attack_phase

func update(delta: float) -> void:
	if not is_instance_valid(unit) or not unit.is_inside_tree():
		return
	state_time += delta
	var battle_manager = unit.faction_manager.battle_manager if unit.faction_manager else null
	if battle_manager and battle_manager.current_state != battle_manager.BattleState.BATTLE:
		if current_state != State.DEAD:
			transition_to(State.IDLE)
		unit.velocity = Vector3.ZERO
		return
	match current_state:
		State.IDLE:
			_update_idle(delta)
		State.MOVE:
			_update_move(delta)
		State.SEEK:
			_update_seek(delta)
		State.ATTACK:
			_update_attack(delta)
		State.RETREAT:
			_update_idle(delta)
		State.DEAD:
			pass

func _update_idle(delta: float) -> void:
	_acquire_cooldown -= delta
	if _acquire_cooldown > 0.0:
		_advance_forward(delta)
		return
	_acquire_cooldown = TARGET_REACQUIRE_INTERVAL
	target = _acquire_target()
	if target:
		transition_to(State.SEEK)
	else:
		_advance_forward(delta)

func _update_move(delta: float) -> void:
	if not is_valid_target():
		transition_to(State.IDLE)
		return
	_pursue(delta)
	if unit.global_position.distance_to(target.global_position) <= unit.stats.attack_range:
		transition_to(State.ATTACK)

func _update_seek(delta: float) -> void:
	_check_threat(delta)
	if not is_valid_target():
		transition_to(State.IDLE)
		return
	_pursue(delta)
	if unit.global_position.distance_to(target.global_position) <= unit.stats.attack_range:
		transition_to(State.ATTACK)

func _update_attack(delta: float) -> void:
	_check_threat(delta)
	if not is_valid_target():
		transition_to(State.IDLE)
		return
	var dist = unit.global_position.distance_to(target.global_position)
	# Hysteresis: don't drop back into a chase until the target is well outside
	# range, so a target hovering near the range edge doesn't cause stop-go jitter.
	if dist > unit.stats.attack_range * 1.5:
		transition_to(State.SEEK)
		return
	_face_target(delta)
	if dist > unit.stats.attack_range:
		# Gliding follow: keep moving toward a retreating target instead of
		# standing still and stop-go stuttering while it backs away.
		_pursue(delta)
	else:
		# Hold in place to swing; only a tiny anti-stack shuffle (capped at 12%
		# of move speed) so a crowd can't shove the unit out of its own reach and
		# force a stop-go chase loop around the target.
		unit.velocity = _smoothed_velocity(_separation(0.12), delta)
		unit.move_and_slide()
	if state_time >= 1.0 / unit.stats.attack_speed:
		_deal_damage()
		state_time = 0.0

func _pursue(delta: float) -> void:
	if not is_valid_target():
		return
	# Stable pursuit: aim at the target's predicted position (lead), re-aimed
	# every 0.6s. The lead is clamped so a knocked-back or sprinting target can't
	# drag the chaser off to an empty spot — that's what made units "run away"
	# from the enemy mid-fight and wander back.
	_chase_timer -= delta
	if _chase_timer <= 0.0 or unit.global_position.distance_to(_chase_aim) > 4.0:
		var lead: Vector3 = target.velocity * CHASE_LEAD
		lead.y = 0.0
		_chase_aim = target.global_position + lead.limit_length(CHASE_LEAD_MAX)
		_chase_timer = CHASE_REAIM
	var desired: Vector3 = _chase_aim - unit.global_position
	desired.y = 0.0
	if desired.length() < 0.001:
		desired = -unit.global_basis.z
	else:
		desired = desired.normalized()
	_apply_motion(desired, unit.stats.move_speed, 0.35, delta)

func _enemy_base_pos() -> Vector3:
	var fm = unit.faction_manager
	if fm and fm.battle_manager:
		for f in fm.battle_manager.factions:
			if f.faction_id != fm.faction_id and f.faction_data and f.faction_data.spawn_areas.size() > 0:
				var sum := Vector3.ZERO
				for a in f.faction_data.spawn_areas:
					sum += a
				return sum / float(f.faction_data.spawn_areas.size())
	return unit.global_position + -unit.global_basis.z * 10.0

func _advance_forward(delta: float) -> void:
	if unit.get_unit_type() == "commander":
		_advance_commander(delta)
		return
	# Re-aim toward the enemy side every 2s; march in a stable straight line in
	# between so units advance as an orderly line instead of steering frame-by-frame.
	_aim_timer -= delta
	if _aim_timer <= 0.0:
		var to := _enemy_base_pos() - unit.global_position
		to.y = 0.0
		_advance_dir = to.normalized() if to.length() > 0.001 else -unit.global_basis.z
		# March to the enemy base plus this unit's formation slot. Far away the
		# offset is negligible (everyone shares the heading); up close it keeps
		# the squad in its formation instead of collapsing onto one point.
		var off: Vector3 = unit.squad_offset
		if off.length() > 0.01:
			var aimed := to + off
			aimed.y = 0.0
			if aimed.length() > 0.001:
				_advance_dir = aimed.normalized()
		_aim_timer = 2.0
	_apply_motion(_advance_dir, unit.stats.move_speed, 0.6, delta)

func _apply_motion(dir: Vector3, speed: float, sep_scale: float = 0.6, delta: float = -1.0) -> void:
	if delta < 0.0:
		delta = unit.get_physics_process_delta_time()
	_turn_toward(dir, delta)
	# Move along the smoothed facing rather than the raw input direction so a
	# heading change produces a natural arc instead of a sideways strafe.
	var fwd: Vector3 = -unit.global_basis.z
	fwd.y = 0.0
	if fwd.length() < 0.001:
		fwd = dir
	unit.velocity = _smoothed_velocity(fwd.normalized() * speed + _separation(sep_scale), delta)
	unit.move_and_slide()

func _smoothed_velocity(desired: Vector3, delta: float) -> Vector3:
	desired.y = 0.0
	var cur := unit.velocity
	cur.y = 0.0
	var blend := minf(1.0, ACCEL * delta)
	var v := cur.lerp(desired, blend)
	v.y = 0.0
	return v

func _turn_toward(dir: Vector3, delta: float) -> void:
	if delta < 0.0:
		delta = unit.get_physics_process_delta_time()
	dir.y = 0.0
	if dir.length() < 0.001:
		return
	unit.rotation.y = lerp_angle(unit.rotation.y, atan2(-dir.x, -dir.z), minf(1.0, TURN_RATE * delta))

func _squad_centroid() -> Vector3:
	var fm = unit.faction_manager
	if not fm:
		return Vector3.INF
	var acc := Vector3.ZERO
	var n := 0
	for u in fm.units:
		if is_instance_valid(u) and u != unit and not u._dying \
				and u.commander_id == unit.commander_id and not u.commander_id.is_empty():
			acc += u.global_position
			n += 1
	if n == 0:
		return Vector3.INF
	return acc / n

func _advance_commander(delta: float) -> void:
	_aim_timer -= delta
	if _aim_timer <= 0.0:
		var to := _enemy_base_pos() - unit.global_position
		to.y = 0.0
		_advance_dir = to.normalized() if to.length() > 0.001 else -unit.global_basis.z
		_aim_timer = 2.0
	_turn_toward(_advance_dir, delta)
	var centroid := _squad_centroid()
	var speed = unit.stats.move_speed * 0.72
	if centroid.is_finite():
		var ahead := (unit.global_position - centroid).dot(_advance_dir)
		if ahead > 7.0:
			unit.velocity = _smoothed_velocity(_separation(), delta)
			unit.move_and_slide()
			return
	_apply_motion(_advance_dir, speed, 0.6, delta)

func is_valid_target() -> bool:
	return target != null and is_instance_valid(target) and target.is_inside_tree() \
			and not (target.has_method("is_spectate_eligible") and not target.is_spectate_eligible())

func _face_target(delta: float) -> void:
	if is_valid_target():
		_turn_toward(target.global_position - unit.global_position, delta)

func _separation(cap_scale: float = 0.6) -> Vector3:
	var push := Vector3.ZERO
	var fm = unit.faction_manager
	if not fm or not fm.battle_manager:
		return push
	var is_tank: bool = unit.stats.unit_name == "Tank"
	var sep_radius: float = 14.0 if is_tank else SEP_RADIUS
	var sep_force: float = 30.0 if is_tank else SEP_FORCE
	for other in fm.battle_manager.get_nearby_units(unit.global_position, sep_radius, unit):
		var to = unit.global_position - other.global_position
		var dist = to.length()
		if dist < sep_radius and dist > 0.0001:
			push += to.normalized() * (1.0 - dist / sep_radius) * sep_force
	# Separation spreads units sideways but must never shove them backward
	# (away from the enemy they're facing), or units jitter back and forth.
	var fwd := -unit.global_basis.z
	var fwd_component := push.dot(fwd)
	if fwd_component < 0.0:
		push -= fwd * fwd_component
	# Never let separation override the unit's own forward motion, or units jitter
	# sideways randomly in a crowd.
	return push.limit_length(unit.stats.move_speed * cap_scale)

const BLAST_RADIUS := 7.0
const BLAST_POWER := 60.0
const BLAST_UPWARD := 0.4
const BLAST_DAMAGE := 400.0

func _deal_damage() -> void:
	if is_valid_target() and target.has_method("take_damage"):
		var stats = unit.stats
		unit.call("flash_muzzle")
		if stats.unit_name == "Tank":
			_apply_blast()
		else:
			target.take_damage(stats.attack_damage * unit.aura_damage_mult, unit)
			_apply_melee_impact(stats)

func _apply_melee_impact(stats) -> void:
	if stats.attack_range >= 5.0 or not is_valid_target():
		return
	# Melee hit staggers the victim; the harder the attacker is charging, the
	# harder the knockback. A stationary swing just flinches, a charge shoves.
	var speed: float = unit.velocity.length()
	var dir := unit.global_position.direction_to(target.global_position)
	dir.y = 0.2
	var force: float = 2.0 + speed * 0.9
	target.call("apply_knockback", dir * force)

func _apply_blast() -> void:
	# Shell impact = lethal spherical blast at the target. The direct hit deals
	# the full blast damage (wipes infantry at the impact point, wounds
	# titans/tanks); both damage and launch impulse fall off with distance, with
	# an upward bias so survivors/corpses are thrown rather than just pushed.
	if not is_valid_target():
		return
	var bm = unit.faction_manager.battle_manager if unit.faction_manager else null
	if not bm:
		return
	var center: Vector3 = target.global_position
	var source: Vector3 = unit.global_position
	for u in bm.get_nearby_units(center, BLAST_RADIUS, unit):
		if u.faction_id == unit.faction_id:
			continue
		var dist: float = center.distance_to(u.global_position)
		var fall: float = 1.0 - dist / BLAST_RADIUS
		if fall <= 0.0:
			continue
		var dir := source.direction_to(u.global_position)
		dir.y = 0.0
		var impulse := (dir + Vector3.UP * BLAST_UPWARD).normalized() * BLAST_POWER * fall
		u.call("apply_knockback", impulse, 0.7)
		u.call("take_damage", BLAST_DAMAGE * fall * unit.aura_damage_mult, unit)

func _is_target_shared(enemy) -> bool:
	var fm = unit.faction_manager
	if not fm:
		return false
	for u in fm.units:
		if u == unit or not is_instance_valid(u) or u._dying:
			continue
		if u.commander_id.is_empty() or u.commander_id != unit.commander_id:
			continue
		if u.has_method("get_current_target") and u.get_current_target() == enemy:
			return true
	return false

func _acquire_commander_target():
	var my_pos: Vector3 = unit.global_position
	var best = null
	var best_score := -INF
	for u in unit.faction_manager.get_enemy_units(unit.faction_id):
		if not is_instance_valid(u) or not u.is_inside_tree():
			continue
		var dist: float = my_pos.distance_to(u.global_position)
		var score := 0.0
		if _is_target_shared(u):
			score += 3.0
		if u.has_method("get_unit_type") and u.get_unit_type() == "titan":
			score -= 4.0
		score -= dist * 0.02
		if score > best_score:
			best_score = score
			best = u
	return best

func _recent_attacker():
	if unit.has_method("get_last_attacker"):
		return unit.call("get_last_attacker")
	return null

func _is_enemy(u) -> bool:
	return u != null and u != unit and unit.faction_manager and \
		is_instance_valid(u) and u.is_inside_tree() and u.faction_id != unit.faction_id

func _check_threat(delta: float) -> void:
	_threat_timer -= delta
	if _threat_timer > 0.0:
		return
	_threat_timer = TARGET_REACQUIRE_INTERVAL
	# 360° awareness: whoever is actively hitting us wins over the nearest-scan
	# target, even if they came from behind, so units turn to face flankers.
	var attacker = _recent_attacker()
	if not _is_enemy(attacker):
		return
	if attacker.global_position.distance_to(unit.global_position) > unit.stats.vision_radius:
		return
	if is_valid_target() and attacker == target:
		return
	target = attacker

func _acquire_target():
	if not unit.faction_manager:
		return null
	var attacker = _recent_attacker()
	if _is_enemy(attacker) and unit.global_position.distance_to(attacker.global_position) <= unit.stats.vision_radius:
		return attacker
	if unit.get_unit_type() == "commander":
		return _acquire_commander_target()
	var closest = null
	var stats = unit.stats
	# Everyone (tanks included) hunts the nearest enemy anywhere on the map, so
	# no unit stops and waits for a target to wander into vision range.
	var vision := INF
	var closest_dist: float = vision
	var infantry: bool = stats.unit_name == "Militia" or stats.unit_name == "Spearman"
	var closest_lane: float = 9999.0
	var my_pos: Vector3 = unit.global_position
	for u in unit.faction_manager.get_enemy_units(unit.faction_id):
		if not is_instance_valid(u):
			continue
		var dist: float = my_pos.distance_to(u.global_position)
		if dist > vision:
			continue
		if infantry:
			var lane: float = absf(my_pos.z - u.global_position.z)
			if lane < closest_lane or (absf(lane - closest_lane) < 0.001 and dist < closest_dist):
				closest = u
				closest_lane = lane
				closest_dist = dist
		elif dist < closest_dist:
			closest = u
			closest_dist = dist
	return closest
