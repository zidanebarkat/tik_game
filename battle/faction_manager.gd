extends Node3D

const UNIT_SCENE = preload("res://units/scenes/unit_base.tscn")

const FRONT_DEPTH := 2.5
const KNIGHT_DEPTH := 0.5
const TITAN_DEPTH := -2.5
const HALF_LINE := 10.0
const KNIGHT_FLANK_GAP := 2.5
const KNIGHT_RANK_GAP := 2.0
const TITAN_GAP := 6.0
const TANK_GAP := 30.0
const INF_ROW_COUNT := 10
const INF_SPACING := 2.0
const INF_Z_START := -9.0
const RANK_GAP := 1.5
const SQUAD_SIZE := 8

@export var faction_id: int = 0
@export var faction_data: Resource

var battle_manager = null
var units: Array = []
var kills: int = 0
var deaths: int = 0
var population: int = 0
var max_population: int = 1000
var team_material: StandardMaterial3D = null

func get_team_material() -> StandardMaterial3D:
	if team_material == null:
		team_material = StandardMaterial3D.new()
		team_material.albedo_color = get_faction_color()
		team_material.metallic = 0.0
		team_material.roughness = 0.85
	return team_material

var _infantry_total: int = 0
var _knight_slot: int = 0
var _titan_total: int = 0
var _tank_total: int = 0

func get_faction_color() -> Color:
	return faction_data.color if faction_data else Color.WHITE

func spawn_unit(unit_resource, position: Vector3, sender: String = "", opts: Dictionary = {}) -> void:
	if population >= max_population:
		return
	var unit = UNIT_SCENE.instantiate()
	unit.stats = unit_resource
	unit.faction_id = faction_id
	unit.faction_manager = self
	unit.gift_owner = sender
	add_child(unit)
	var spawn_pos: Vector3 = opts.get("force_position", _get_formation_position(unit_resource))
	unit.global_position = spawn_pos
	unit.squad_id = units.size() / SQUAD_SIZE
	unit.squad_offset = spawn_pos - _base_pos()
	if opts.has("rotation_y"):
		unit.rotation.y = float(opts.rotation_y)
	else:
		unit.rotation.y = PI if faction_id == 1 else 0.0
	if opts.has("display_name"):
		unit.display_name = str(opts.display_name)
	if opts.has("portrait_texture"):
		unit.portrait_texture = opts.portrait_texture
	if opts.has("commander_id"):
		unit.commander_id = str(opts.commander_id)
	if opts.has("commander_name"):
		unit.commander_name = str(opts.commander_name)
	if opts.has("faction_tag"):
		unit.faction_tag = str(opts.faction_tag)
	if opts.has("banner_color"):
		unit.banner_color = opts.banner_color
	if opts.has("commander_title"):
		unit.commander_title = str(opts.commander_title)
	if opts.has("commander_title_color"):
		unit.commander_title_color = opts.commander_title_color
	if opts.has("march_waypoint"):
		unit.reinforce_waypoint = opts.march_waypoint
	units.append(unit)
	population += unit_resource.population_value
	if battle_manager:
		battle_manager.unit_spawned.emit(unit)

func _base_pos() -> Vector3:
	var base := Vector3.ZERO
	if faction_data and faction_data.spawn_areas.size() > 0:
		for a in faction_data.spawn_areas:
			base += a
		base /= faction_data.spawn_areas.size()
	return base

func _get_formation_position(unit_resource) -> Vector3:
	var base := _base_pos()
	var facing := 1.0 if faction_id == 0 else -1.0
	var pos := Vector3(base.x, base.y, base.z)
	match unit_resource.unit_name:
		"Knight":
			var slot: int = _knight_slot
			_knight_slot += 1
			var side := -1.0 if slot % 2 == 0 else 1.0
			var rank := int(slot / 2)
			pos.x = base.x + (KNIGHT_DEPTH - rank * KNIGHT_RANK_GAP) * facing
			pos.z = base.z + side * (HALF_LINE + KNIGHT_FLANK_GAP)
		"Titan":
			var t: int = _titan_total
			_titan_total += 1
			var side := -1.0 if t % 2 == 0 else 1.0
			var offset := int((t + 1) / 2)
			pos.x = base.x + TITAN_DEPTH * facing
			pos.z = base.z + side * offset * TITAN_GAP
		"Tank":
			var tk: int = _tank_total
			_tank_total += 1
			var tside := -1.0 if tk % 2 == 0 else 1.0
			var toffset := int((tk + 1) / 2)
			pos.x = base.x + FRONT_DEPTH * facing
			pos.z = base.z + tside * toffset * TANK_GAP
		_:
			var i: int = _infantry_total
			_infantry_total += 1
			var row := int(i / INF_ROW_COUNT)
			pos.x = base.x + (FRONT_DEPTH - row * RANK_GAP) * facing
			pos.z = base.z + INF_Z_START + (i % INF_ROW_COUNT) * INF_SPACING
	return pos

func on_unit_died(unit) -> void:
	deaths += 1
	units.erase(unit)
	population = max(0, population - unit.stats.population_value)

func get_enemy_units(my_faction: int) -> Array:
	if not battle_manager:
		return []
	var enemies: Array = []
	for f in battle_manager.factions:
		if f.faction_id != my_faction:
			enemies.append_array(f.units)
	return enemies

func get_alive_count() -> int:
	var count := 0
	for u in units:
		if is_instance_valid(u) and u.current_health > 0:
			count += 1
	return count

func clear_all_units() -> void:
	for u in units:
		if is_instance_valid(u):
			u.queue_free()
	units.clear()
	population = 0
	_infantry_total = 0
	_knight_slot = 0
	_titan_total = 0
	_tank_total = 0

func get_stats() -> Dictionary:
	return {
		"faction_id": faction_id,
		"name": faction_data.faction_name if faction_data else "Unknown",
		"kills": kills,
		"deaths": deaths,
		"population": population,
		"alive": get_alive_count()
	}
