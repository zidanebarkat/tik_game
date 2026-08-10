extends Node

signal team_changed(user_id: String, team: int)

var battle_manager = null
var teams: Dictionary = {}

func assign_team(user_id: String, team: int) -> void:
	if user_id.is_empty():
		return
	teams[user_id] = 1 if team == 1 else 0
	team_changed.emit(user_id, teams[user_id])

func get_team(user_id: String) -> int:
	if user_id.is_empty() or not teams.has(user_id):
		return -1
	return int(teams[user_id])

func parse_team_comment(text: String) -> int:
	var t := text.to_lower()
	if not t.contains("team"):
		return -1
	var has_red := t.contains("red")
	var has_blue := t.contains("blue")
	if has_red and not has_blue:
		return 0
	if has_blue and not has_red:
		return 1
	return -1

func get_team_name(user_id: String) -> String:
	match get_team(user_id):
		0:
			return "RED"
		1:
			return "BLUE"
		_:
			return "?"

func get_member_count(team: int) -> int:
	var count := 0
	for uid in teams:
		if int(teams[uid]) == team:
			count += 1
	return count

func clear() -> void:
	teams.clear()
