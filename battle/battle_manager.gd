extends Node

enum BattleState { MENU, IDLE, COUNTDOWN, BATTLE, VICTORY, RESET }

signal state_changed(new_state)
signal battle_started()
signal battle_ended(winning_faction)
signal unit_spawned(unit)
signal countdown_tick(seconds_left: float)

var current_state: BattleState = BattleState.MENU
var factions: Array = []
var battle_time: float = 0.0
var game_speed: float = 1.0
var paused: bool = false
var total_kills: int = 0
var countdown_time: float = 3.0
var countdown_left: float = 0.0

func _process(delta: float) -> void:
	if current_state == BattleState.COUNTDOWN and not paused:
		countdown_left -= delta * game_speed
		countdown_tick.emit(max(countdown_left, 0.0))
		if countdown_left <= 0.0:
			change_state(BattleState.BATTLE)
	elif current_state == BattleState.BATTLE and not paused:
		battle_time += delta * game_speed
		_check_victory()

func change_state(new_state: BattleState) -> void:
	current_state = new_state
	state_changed.emit(new_state)
	match new_state:
		BattleState.BATTLE:
			battle_started.emit()
		BattleState.VICTORY:
			_stop_all_units()
		BattleState.MENU, BattleState.IDLE:
			_reset_battle()

## Halts every surviving unit the moment the fight is decided: marching
## warbands otherwise keep walking to their waypoint (their march bypasses the
## combat state machine) and knockback keeps corpses sliding around a dead field.
func _stop_all_units() -> void:
	for f in factions:
		for u in f.units:
			if is_instance_valid(u) and u.has_method("stop_motion"):
				u.stop_motion()

func start_game() -> void:
	change_state(BattleState.IDLE)

func request_countdown() -> bool:
	var ready := true
	for f in factions:
		if f.get_alive_count() <= 0:
			ready = false
	if not ready:
		return false
	countdown_left = 0.0
	change_state(BattleState.BATTLE)
	return true

func start_battle() -> void:
	change_state(BattleState.BATTLE)

func register_faction(faction) -> void:
	factions.append(faction)
	faction.battle_manager = self

func get_faction(id: int):
	for f in factions:
		if f.faction_id == id:
			return f
	return null

const UNIT_GRID_CELL := 2.0
var _unit_grid: Dictionary = {}
var _unit_grid_tick: int = -1

func get_nearby_units(position: Vector3, radius: float, exclude_unit) -> Array:
	var tick: int = Engine.get_physics_frames()
	if tick != _unit_grid_tick:
		_unit_grid.clear()
		for f in factions:
			for u in f.units:
				if is_instance_valid(u) and u.is_inside_tree():
					var key: Vector2i = Vector2i(
						floori(u.global_position.x / UNIT_GRID_CELL),
						floori(u.global_position.z / UNIT_GRID_CELL))
					if not _unit_grid.has(key):
						_unit_grid[key] = []
					_unit_grid[key].append(u)
		_unit_grid_tick = tick
	var out: Array = []
	var span: int = maxi(1, ceili(radius / UNIT_GRID_CELL))
	var center: Vector2i = Vector2i(
		floori(position.x / UNIT_GRID_CELL),
		floori(position.z / UNIT_GRID_CELL))
	for dx in range(-span, span + 1):
		for dz in range(-span, span + 1):
			var cell: Array = _unit_grid.get(center + Vector2i(dx, dz), [])
			for u in cell:
				if u != exclude_unit and position.distance_to(u.global_position) <= radius:
					out.append(u)
	return out

func spawn_unit(unit_resource, faction_id: int, position: Vector3, sender: String = "", opts: Dictionary = {}) -> void:
	var faction = get_faction(faction_id)
	if not faction:
		return
	faction.spawn_unit(unit_resource, position, sender, opts)

func _check_victory() -> void:
	var alive_factions: Array = []
	for f in factions:
		if f.get_alive_count() > 0:
			alive_factions.append(f.faction_id)
	if alive_factions.size() == 1:
		change_state(BattleState.VICTORY)
		battle_ended.emit(alive_factions[0])
	elif alive_factions.size() == 0 and factions.size() > 0:
		change_state(BattleState.VICTORY)
		battle_ended.emit(-1)

func _reset_battle() -> void:
	battle_time = 0.0
	total_kills = 0
	for f in factions:
		f.clear_all_units()

func set_game_speed(speed: float) -> void:
	game_speed = clamp(speed, 0.25, 4.0)

func toggle_pause() -> void:
	paused = not paused

func get_battle_stats() -> Dictionary:
	var stats = {
		"battle_time": battle_time,
		"total_kills": total_kills,
		"factions": []
	}
	for f in factions:
		stats.factions.append(f.get_stats())
	return stats
