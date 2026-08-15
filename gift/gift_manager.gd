extends Node

signal gift_mapped(gift_name: String, unit_resource, faction_id: int)

var gift_map: Dictionary = {}
var spawn_manager = null
var battle_manager = null
var team_manager = null
var commander_manager = null
var super_power = null

func _ready() -> void:
	_load_gift_map()

func _load_gift_map() -> void:
	var file = FileAccess.open("res://gift/gift_mapping.json", FileAccess.READ)
	if file:
		var json = JSON.new()
		var content = file.get_as_text()
		if json.parse(content) == OK:
			gift_map = json.data

func process_gift(gift_name: String, sender: String, count: int, user_id: String = "") -> void:
	if not gift_map.has(gift_name):
		return
	if not battle_manager:
		return
	var bstate = battle_manager.current_state
	if bstate == battle_manager.BattleState.MENU \
			or bstate == battle_manager.BattleState.RESET:
		return
	var mapping = gift_map[gift_name]
	var tier = mapping.get("commander_tier", "")
	var uid := user_id if not user_id.is_empty() else sender
	var value := float(mapping.get("value", 0.0))
	if value > 0.0:
		var eng = RegistryAccess.get_engagement()
		if eng:
			eng.record_gift(uid, sender, value * count, not str(tier).is_empty(), count)
	if mapping.get("super_power", false):
		# Super strike: destroy the densest cluster on the OPPOSING side of the
		# gifter's team. Lockout inside the power stops stacking detonations.
		if super_power and super_power.has_method("trigger_super"):
			var team := _resolve_team(user_id, sender)
			for i in range(count):
				super_power.trigger_super(1 - team)
		return
	if not str(tier).is_empty() and commander_manager:
		for i in range(count):
			commander_manager.process_commander_gift(gift_name, str(tier), user_id, sender)
		return
	var unit_name = mapping.get("unit", "")
	var faction = battle_manager.get_faction(_resolve_team(user_id, sender))
	if not faction:
		return
	var unit_resource = _find_unit_resource(unit_name)
	if not unit_resource:
		return
	for i in range(count):
		var spawn_pos = _get_spawn_position(faction.faction_id)
		spawn_manager.add_request(faction.faction_id, unit_resource, spawn_pos, sender)

func _resolve_team(user_id: String, sender: String) -> int:
	if not team_manager:
		return 0
	var uid := user_id if not user_id.is_empty() else sender
	var team = team_manager.get_team(uid)
	return 0 if team == -1 else team

func _find_unit_resource(unit_name: String):
	var path = "res://units/resources/%s.tres" % unit_name
	if ResourceLoader.exists(path):
		return load(path)
	return null

func _get_spawn_position(faction_id: int) -> Vector3:
	var faction = battle_manager.get_faction(faction_id)
	if faction and faction.faction_data and faction.faction_data.spawn_areas.size() > 0:
		var base = faction.faction_data.spawn_areas[0]
		return base + Vector3(randf_range(-5, 5), 0, randf_range(-5, 5))
	return Vector3(randf_range(-20, 20), 0, randf_range(-20, 20))

func reload_gift_map() -> void:
	_load_gift_map()
