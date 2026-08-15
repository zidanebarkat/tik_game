extends CanvasLayer

@onready var fps_label: Label = $MarginContainer/VBoxContainer/FPSLabel
@onready var population_label: Label = $MarginContainer/VBoxContainer/PopulationLabel
@onready var kills_label: Label = $MarginContainer/VBoxContainer/KillsLabel
@onready var time_label: Label = $MarginContainer/VBoxContainer/TimeLabel
@onready var gift_feed: VBoxContainer = $MarginContainer/VBoxContainer/GiftFeed
@onready var kill_feed: VBoxContainer = $MarginContainer/VBoxContainer/KillFeed
@onready var status_label: Label = $StatusLabel
@onready var hints_label: Label = $HintsLabel
@onready var countdown_label: Label = $CountdownLabel
@onready var start_fight_button: Button = $StartFightButton
@onready var spectate_panel: PanelContainer = $SpectatePanel
@onready var spectate_name: Label = $SpectatePanel/SpectateBox/SpectateInfo/SpectateName
@onready var spectate_tag: Label = $SpectatePanel/SpectateBox/SpectateInfo/SpectateTag
@onready var spectate_hp: ProgressBar = $SpectatePanel/SpectateBox/SpectateInfo/SpectateHP
@onready var spectate_portrait: TextureRect = $SpectatePanel/SpectateBox/SpectatePortrait
@onready var leaderboard_panel: PanelContainer = $LeaderboardPanel
@onready var leaderboard_box: VBoxContainer = $LeaderboardPanel/LeaderboardBox
@onready var leaderboard_title: Label = $LeaderboardPanel/LeaderboardBox/LeaderboardTitle
@onready var arrival_panel: PanelContainer = $ArrivalPanel
@onready var arrival_portrait: TextureRect = $ArrivalPanel/ArrivalBox/ArrivalPortrait
@onready var arrival_label: Label = $ArrivalPanel/ArrivalBox/ArrivalInfo/ArrivalLabel
@onready var arrival_tier: Label = $ArrivalPanel/ArrivalBox/ArrivalInfo/ArrivalTier
@onready var result_panel: PanelContainer = $ResultPanel
@onready var result_title: Label = $ResultPanel/ResultBox/ResultTitle
@onready var result_stats: Label = $ResultPanel/ResultBox/ResultStats

signal arrival_began(viewer_name: String)

var battle_manager = null
var main_scene = null
var commander_manager = null
var team_manager = null
var max_feed_items: int = 10
var max_kill_feed_items: int = 5
var _leaderboard_rows: Array = []

const TEAM_RED := Color(0.9, 0.3, 0.3)
const TEAM_BLUE := Color(0.35, 0.6, 0.95)
const TEAM_NONE := Color(0.92, 0.92, 0.92)
const RANK_GOLD := Color(1, 0.85, 0.4, 1)

const ARRIVAL_HOLD := 2.6
var _arrival_queue: Array = []
var _arrival_active := false
var _arrival_timer := 0.0

func _process(_delta: float) -> void:
	if fps_label:
		fps_label.text = "FPS: %d" % Engine.get_frames_per_second()
	if battle_manager:
		if time_label:
			time_label.text = "Time: %.1f" % battle_manager.battle_time
		if kills_label:
			var total_kills = 0
			for f in battle_manager.factions:
				total_kills += f.kills
			kills_label.text = "Kills: %d" % total_kills
		if population_label:
			var total_pop = 0
			for f in battle_manager.factions:
				total_pop += f.population
			population_label.text = "Population: %d" % total_pop
	_update_spectate_panel()
	_update_arrival()

func queue_arrival(viewer_name: String, viewer_id: String, tier: String, portrait: Texture2D) -> void:
	_arrival_queue.append({
		"name": viewer_name,
		"id": viewer_id,
		"tier": tier,
		"portrait": portrait,
	})
	if not _arrival_active:
		_show_next_arrival()

func _show_next_arrival() -> void:
	if _arrival_queue.is_empty():
		_arrival_active = false
		if arrival_panel:
			arrival_panel.visible = false
		return
	_arrival_active = true
	var ev = _arrival_queue.pop_front()
	if arrival_panel:
		arrival_panel.visible = true
	var eng = RegistryAccess.get_engagement()
	var title := ""
	if eng:
		title = eng.get_title(ev.id)
	if arrival_label:
		var prefix := "%s " % title if not title.is_empty() else ""
		arrival_label.text = "%s%s's warband has arrived!" % [prefix, ev.name]
	if arrival_tier:
		arrival_tier.text = "%s Commander warband" % ev.tier.capitalize()
	if arrival_portrait:
		arrival_portrait.texture = ev.portrait if ev.portrait else null
	if commander_manager and commander_manager.has_method("play_horn"):
		commander_manager.play_horn()
	arrival_began.emit(ev.name)
	_arrival_timer = ARRIVAL_HOLD

func _update_arrival() -> void:
	if not _arrival_active:
		return
	_arrival_timer -= get_process_delta_time()
	if _arrival_timer <= 0.0:
		if arrival_panel:
			arrival_panel.visible = false
		_arrival_active = false
		_show_next_arrival()

func _update_spectate_panel() -> void:
	if not spectate_panel:
		return
	var sc = RegistryAccess.get_spectator()
	if sc == null or not sc.is_spectating():
		spectate_panel.visible = false
		return
	var t = sc.get_current_target()
	if t == null or not is_instance_valid(t):
		spectate_panel.visible = false
		return
	spectate_panel.visible = true
	spectate_name.text = t.get_display_name()
	spectate_hp.max_value = t.stats.max_health
	spectate_hp.value = t.current_health
	var is_cmd = t.get_unit_type() == "commander"
	if is_cmd:
		spectate_tag.text = "COMMANDER"
		spectate_portrait.visible = t.portrait_texture != null
		if t.portrait_texture:
			spectate_portrait.texture = t.portrait_texture
	elif not t.commander_id.is_empty():
		spectate_tag.text = "fighting for %s" % t.commander_name
		spectate_portrait.visible = false
	else:
		spectate_tag.text = ""
		spectate_portrait.visible = false

func setup(bm, ms = null, tm = null) -> void:
	battle_manager = bm
	main_scene = ms
	team_manager = tm
	battle_manager.state_changed.connect(_on_state_changed)
	battle_manager.countdown_tick.connect(_on_countdown_tick)
	battle_manager.battle_ended.connect(_on_battle_ended)
	start_fight_button.pressed.connect(_on_start_fight_pressed)
	var eng = RegistryAccess.get_engagement()
	if eng:
		eng.kill_feed_entry.connect(_on_kill_feed_entry)
		eng.leaderboard_changed.connect(_refresh_leaderboard)
	_on_state_changed(battle_manager.current_state)

func _on_state_changed(new_state) -> void:
	countdown_label.visible = false
	hints_label.visible = false
	if result_panel:
		result_panel.visible = (new_state == battle_manager.BattleState.VICTORY)
	match new_state:
		battle_manager.BattleState.MENU:
			status_label.text = "MENU"
			start_fight_button.visible = false
		battle_manager.BattleState.IDLE:
			status_label.text = "WAITING FOR VIEWERS - press SPACE or Start Fight when ready."
			hints_label.visible = true
			hints_label.text = "TEST SPAWNS | RED: Q=Knight W=Militia A=Spearman D=Titan | BLUE: E=Knight S=Militia F=Spearman G=Titan"
			start_fight_button.visible = true
		battle_manager.BattleState.COUNTDOWN:
			status_label.text = "GET READY!"
			start_fight_button.visible = false
			countdown_label.visible = true
		battle_manager.BattleState.BATTLE:
			status_label.text = "FIGHT!"
			start_fight_button.visible = false
		battle_manager.BattleState.VICTORY:
			status_label.text = "BATTLE OVER - press R for a new round, ESC for menu"
			start_fight_button.visible = false
		battle_manager.BattleState.RESET:
			status_label.text = "RESET"
			start_fight_button.visible = false
	_refresh_leaderboard()

func _on_countdown_tick(seconds_left: float) -> void:
	if seconds_left <= 0.0:
		countdown_label.visible = false
	else:
		countdown_label.text = str(ceili(seconds_left))

func _on_battle_ended(winning_faction: int) -> void:
	_show_result(winning_faction)

func _show_result(winning_faction: int) -> void:
	if result_panel == null or battle_manager == null:
		return
	var title := "DRAW!"
	if winning_faction >= 0:
		var f = battle_manager.get_faction(winning_faction)
		var name: String = f.faction_data.faction_name if f and f.faction_data else "Unknown"
		title = "%s WINS!" % name
	result_title.text = title
	var stats: Dictionary = battle_manager.get_battle_stats()
	var lines: PackedStringArray = []
	for f in stats.get("factions", []):
		lines.append("%s   |   kills: %d   |   survivors: %d" % [
			f.get("name", "Unknown"), f.get("kills", 0), f.get("alive", 0)])
	lines.append("Battle time: %.1fs   |   total kills: %d" % [
		stats.get("battle_time", 0.0), stats.get("total_kills", 0)])
	result_stats.text = "\n".join(lines)
	result_panel.visible = true

func _on_start_fight_pressed() -> void:
	if main_scene and main_scene.has_method("request_countdown"):
		main_scene.request_countdown()

func add_gift_feed_item(sender: String, gift: String, count: int, team: int = -1) -> void:
	if not gift_feed:
		return
	var label = Label.new()
	var tag := ""
	match team:
		0:
			tag = "[RED] "
		1:
			tag = "[BLUE] "
	label.text = "%s%s sent %d x %s" % [tag, sender, count, gift]
	label.add_theme_font_size_override("font_size", 14)
	gift_feed.add_child(label)
	if gift_feed.get_child_count() > max_feed_items:
		gift_feed.get_child(0).queue_free()

func _on_kill_feed_entry(entry: Dictionary) -> void:
	if not kill_feed:
		return
	var label = Label.new()
	label.text = "%s's %s slew a %s" % [entry.commander_name, entry.killer_label, entry.victim_label]
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", entry.color)
	kill_feed.add_child(label)
	while kill_feed.get_child_count() > max_kill_feed_items + 1:
		var first = kill_feed.get_child(1)
		if not first:
			break
		kill_feed.remove_child(first)
		first.queue_free()

func _get_leaderboard_row(index: int) -> HBoxContainer:
	while _leaderboard_rows.size() <= index:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)

		var rank := Label.new()
		rank.name = "Rank"
		rank.custom_minimum_size = Vector2(20, 0)
		rank.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		rank.vertical_alignment = VerticalAlignment.VERTICAL_ALIGNMENT_CENTER
		rank.add_theme_font_size_override("font_size", 16)
		rank.add_theme_color_override("font_color", RANK_GOLD)
		rank.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
		rank.add_theme_constant_override("outline_size", 3)
		row.add_child(rank)

		var portrait := TextureRect.new()
		portrait.name = "Portrait"
		portrait.custom_minimum_size = Vector2(40, 40)
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(portrait)

		var info := VBoxContainer.new()
		info.name = "Info"
		info.add_theme_constant_override("separation", 0)
		var name_label := Label.new()
		name_label.name = "Name"
		name_label.add_theme_font_size_override("font_size", 14)
		name_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
		name_label.add_theme_constant_override("outline_size", 3)
		info.add_child(name_label)
		var stats := Label.new()
		stats.name = "Stats"
		stats.add_theme_font_size_override("font_size", 12)
		stats.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8, 1))
		info.add_child(stats)
		row.add_child(info)

		leaderboard_box.add_child(row)
		_leaderboard_rows.append(row)
	return _leaderboard_rows[index]

func _team_tag(team: int) -> String:
	match team:
		0:
			return "[RED]"
		1:
			return "[BLUE]"
	return ""

func _team_tag_color(team: int) -> Color:
	match team:
		0:
			return TEAM_RED
		1:
			return TEAM_BLUE
	return TEAM_NONE

func _refresh_leaderboard() -> void:
	var eng = RegistryAccess.get_engagement()
	if not eng or not leaderboard_panel:
		return
	var entries = eng.get_leaderboard(3)
	if entries.is_empty() or not battle_manager \
			or battle_manager.current_state == battle_manager.BattleState.MENU \
			or battle_manager.current_state == battle_manager.BattleState.RESET:
		leaderboard_panel.visible = false
		return
	leaderboard_panel.visible = true
	if leaderboard_title:
		leaderboard_title.text = "TOP ENGAGED   ·   TOTAL %d" % int(eng.get_total_spend())
	for i in range(3):
		var row: HBoxContainer = _get_leaderboard_row(i)
		if i < entries.size():
			var e = entries[i]
			var team := -1
			if team_manager:
				team = team_manager.get_team(str(e.viewer_id))
			var rank: Label = row.get_node("Rank")
			var portrait: TextureRect = row.get_node("Portrait")
			var name_label: Label = row.get_node("Info/Name")
			var stats: Label = row.get_node("Info/Stats")
			rank.text = str(i + 1)
			var tag := _team_tag(team)
			name_label.text = ("%s %s" % [tag, e.name]).strip_edges()
			name_label.add_theme_color_override("font_color", _team_tag_color(team))
			var title_part := ""
			if not str(e.title).is_empty():
				title_part = "  ·  %s" % e.title
			stats.text = "%d pts  ·  %d gifts%s" % [int(e.spend), int(e.get("gifts", 0)), title_part]
			var cm = commander_manager if commander_manager else RegistryAccess.get_commander_manager()
			if cm and cm.has_method("get_viewer_portrait"):
				portrait.texture = cm.get_viewer_portrait(str(e.viewer_id))
			else:
				portrait.texture = null
			row.visible = true
		else:
			row.visible = false
