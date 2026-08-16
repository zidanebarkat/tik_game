extends Node3D

const TEST_SPAWN_KEYS := {
	KEY_Q: {"faction": 0, "unit": "knight"},
	KEY_W: {"faction": 0, "unit": "militia"},
	KEY_A: {"faction": 0, "unit": "spearman"},
	KEY_D: {"faction": 0, "unit": "titan"},
	KEY_T: {"faction": 0, "unit": "tank"},
	KEY_E: {"faction": 1, "unit": "knight"},
	KEY_S: {"faction": 1, "unit": "militia"},
	KEY_F: {"faction": 1, "unit": "spearman"},
	KEY_G: {"faction": 1, "unit": "titan"},
	KEY_Y: {"faction": 1, "unit": "tank"},
}

@onready var battle_manager = $BattleManager
@onready var spawn_manager = $SpawnManager
@onready var gift_manager = $GiftManager
@onready var team_manager = $TeamManager
@onready var websocket_client = $WebSocketClient
@onready var hud = $HUD
@onready var main_menu = $MainMenu
@onready var camera: Camera3D = $RTSCamera
@onready var battle_camera: Camera3D = $BattleCamera
@onready var super_power = $SuperPower
@onready var director = $DirectorCam
@onready var world_env: WorldEnvironment = $WorldEnvironment
@onready var dir_light: DirectionalLight3D = $DirectionalLight3D

var _base_env: Environment = null
var _base_light_transform: Transform3D
var _base_light_color: Color
var _base_light_energy: float
var _base_light_shadow: bool

var arrival_cut_enabled := true
var _pending_cut_cmd = null
var _arrival_cam: Camera3D = null
var _arrival_cut_timer := 0.0

var overview_cut_enabled := true
var overview_cut_interval := 45.0
var overview_cut_duration := 4.0
var _overview_cam: Camera3D = null
var _overview_timer := 0.0
var _overview_active := false
var _overview_elapsed := 0.0
var _overview_mid: Vector3 = Vector3.ZERO
var _overview_span: Vector3 = Vector3.RIGHT

## How long the result is shown after a fight before returning to the menu.
## `result_return_enabled` can be turned off by tests / integration harnesses
## that need the battlefield to stay populated after a faction is wiped.
var result_return_enabled := true
var result_return_delay := 5.0
var _result_timer := -1.0
var _last_result_text := ""

func _process(delta: float) -> void:
	if _arrival_cut_timer > 0.0:
		_arrival_cut_timer -= delta
		var sc = RegistryAccess.get_spectator()
		if sc and sc.is_spectating():
			_arrival_cut_timer = 0.0
		if _arrival_cut_timer <= 0.0:
			_restore_broadcast_camera()
	if _overview_active:
		_update_overview_cut(delta)
	elif overview_cut_enabled and _arrival_cut_timer <= 0.0 \
			and not (director and director.is_active()):
		var sc = RegistryAccess.get_spectator()
		if battle_manager and battle_manager.current_state == battle_manager.BattleState.BATTLE \
				and sc and sc.is_spectating():
			_overview_timer += delta
			if _overview_timer >= overview_cut_interval:
				_overview_timer = 0.0
				_start_overview_cut()
	if _result_timer >= 0.0:
		_result_timer -= delta
		if _result_timer <= 0.0:
			_return_to_menu()

func _restore_broadcast_camera() -> void:
	if _arrival_cam and _arrival_cam.is_current():
		_restore_to_current_mode()

## Hands control back to whatever camera mode the user had selected before a
## broadcast cut (RTS, battle overview, or spectator) grabbed the view.
func _restore_to_current_mode() -> void:
	var sc = RegistryAccess.get_spectator()
	if sc and sc.is_spectating() and sc.get_current_target() != null:
		sc.camera.current = true
	elif sc and sc.is_battle_mode() and sc.battle_camera and is_instance_valid(sc.battle_camera):
		sc.battle_camera.make_current()
	elif camera:
		camera.make_current()

## Public hook for the cinematic director camera: return the view to whichever
## manual camera mode the user had selected before it took over.
func restore_manual_camera() -> void:
	_restore_to_current_mode()

## Part 10: a periodic wide strategic pan across the whole field, interleaved
## with the spectator cuts, so the broadcast alternates between "look how many
## people are helping" and "that's you, right there".
func _start_overview_cut() -> void:
	if _overview_active or battle_manager == null:
		return
	var c0 := _faction_spawn_center(0)
	var c1 := _faction_spawn_center(1)
	var mid := (c0 + c1) * 0.5
	var axis := c1 - c0
	axis.y = 0.0
	if axis.length() < 1.0:
		axis = Vector3(1.0, 0.0, 0.0)
	axis = axis.normalized()
	_overview_mid = mid
	_overview_span = axis
	if _overview_cam == null:
		_overview_cam = Camera3D.new()
		_overview_cam.name = "OverviewCam"
		_overview_cam.fov = 65.0
		add_child(_overview_cam)
	_overview_cam.make_current()
	_overview_active = true
	_overview_elapsed = 0.0

func _update_overview_cut(delta: float) -> void:
	_overview_elapsed += delta
	var t := clampf(_overview_elapsed / overview_cut_duration, 0.0, 1.0)
	var pan := 1.0 - 2.0 * t
	var height := 55.0
	var cam_pos := _overview_mid + _overview_span * (pan * 60.0) + Vector3(0, height, 0)
	_overview_cam.global_position = cam_pos
	_overview_cam.look_at(_overview_mid + _overview_span * (pan * 8.0) + Vector3(0, 2.0, 0), Vector3.UP)
	if _overview_elapsed >= overview_cut_duration:
		_end_overview_cut()

func _end_overview_cut() -> void:
	_overview_active = false
	_restore_to_current_mode()

func _faction_spawn_center(fid: int) -> Vector3:
	var f = battle_manager.get_faction(fid)
	var acc := Vector3.ZERO
	if f and f.faction_data and f.faction_data.spawn_areas.size() > 0:
		for a in f.faction_data.spawn_areas:
			acc += a
		acc /= f.faction_data.spawn_areas.size()
	return acc

func _ready() -> void:
	_base_env = world_env.environment
	_base_light_transform = dir_light.transform
	_base_light_color = dir_light.light_color
	_base_light_energy = dir_light.light_energy
	_base_light_shadow = dir_light.shadow_enabled
	battle_manager.register_faction($FactionRed)
	battle_manager.register_faction($FactionBlue)
	spawn_manager.battle_manager = battle_manager
	gift_manager.battle_manager = battle_manager
	gift_manager.spawn_manager = spawn_manager
	gift_manager.team_manager = team_manager
	gift_manager.super_power = super_power
	if super_power and super_power.has_method("setup"):
		super_power.setup(battle_manager)
	if director and director.has_method("setup"):
		director.setup(battle_manager, self)
	team_manager.battle_manager = battle_manager
	var cm = RegistryAccess.get_commander_manager()
	if cm:
		cm.battle_manager = battle_manager
		cm.default_faction_id = 0
		gift_manager.commander_manager = cm
		cm.warband_spawned.connect(_on_warband_spawned)
	if hud:
		hud.setup(battle_manager, self, team_manager)
		hud.commander_manager = cm
		hud.arrival_began.connect(_on_arrival_began)
	websocket_client.gift_received.connect(_on_gift_received)
	websocket_client.comment_received.connect(_on_comment_received)
	websocket_client.command_received.connect(_on_command_received)
	var sc = RegistryAccess.get_spectator()
	if sc:
		sc.setup(camera, battle_camera)
	if main_menu:
		main_menu.setup(self)
	battle_manager.battle_ended.connect(_on_battle_ended)

func start_game() -> void:
	_result_timer = -1.0
	battle_manager.start_game()

func request_countdown() -> bool:
	_result_timer = -1.0
	return battle_manager.request_countdown()

func _on_gift_received(gift_name: String, sender: String, count: int, user_id: String = "") -> void:
	var team: int = team_manager.get_team(user_id if not user_id.is_empty() else sender)
	gift_manager.process_gift(gift_name, sender, count, user_id)
	if hud:
		hud.add_gift_feed_item(sender, gift_name, count, team)

func _on_comment_received(sender: String, user_id: String, text: String) -> void:
	var uid := user_id if not user_id.is_empty() else sender
	var team: int = team_manager.parse_team_comment(text)
	if team != -1:
		team_manager.assign_team(uid, team)
		if hud:
			hud.add_gift_feed_item("JOIN", "%s joined %s" % [sender, team_manager.get_team_name(uid)], 0)

func _on_command_received(cmd: String) -> void:
	match cmd:
		"start_game":
			start_game()
		"countdown":
			if battle_manager.current_state == battle_manager.BattleState.IDLE:
				request_countdown()
		"new_round":
			if battle_manager.current_state != battle_manager.BattleState.MENU:
				battle_manager.start_game()
		"menu":
			battle_manager.change_state(battle_manager.BattleState.MENU)
			if main_menu:
				main_menu.visible = true
		"pause":
			battle_manager.toggle_pause()
		"speed1x":
			battle_manager.set_game_speed(1.0)
		"speed2x":
			battle_manager.set_game_speed(2.0)
		"clear_teams":
			team_manager.clear()
		_:
			if cmd.begins_with("spawn_commander "):
				var tier := cmd.trim_prefix("spawn_commander ").strip_edges()
				_fire_commander_gift(tier)
			elif cmd == "arrival_cut on":
				arrival_cut_enabled = true
			elif cmd == "arrival_cut off":
				arrival_cut_enabled = false

func _fire_commander_gift(tier: String) -> void:
	var cm = RegistryAccess.get_commander_manager()
	if cm:
		cm.debug_spawn(tier)
		if hud:
			hud.add_gift_feed_item("CMD", "spawning %s warband" % tier, 1)

func _fire_super_power() -> void:
	# Debug/test hook: hits the densest cluster of the blue (faction 1) side.
	if super_power and super_power.trigger_super(1):
		if hud:
			hud.add_gift_feed_item("POWER", "Meteor strike incoming", 1)

func _on_warband_spawned(viewer_name: String, viewer_id: String, tier: String, commander_unit) -> void:
	_pending_cut_cmd = commander_unit
	if hud:
		var cm = RegistryAccess.get_commander_manager()
		var portrait = cm.get_viewer_portrait(viewer_id) if cm else null
		hud.queue_arrival(viewer_name, viewer_id, tier, portrait)

func _on_arrival_began(_viewer_name: String) -> void:
	if director and director.is_active():
		return
	if not arrival_cut_enabled:
		return
	if _pending_cut_cmd == null or not is_instance_valid(_pending_cut_cmd):
		return
	var sc = RegistryAccess.get_spectator()
	if sc and sc.is_spectating():
		return
	if _arrival_cam == null:
		_arrival_cam = Camera3D.new()
		_arrival_cam.name = "ArrivalCam"
		_arrival_cam.fov = 60.0
		add_child(_arrival_cam)
	var cmd_pos = _pending_cut_cmd.global_position
	var dir = _pending_cut_cmd.global_basis.z
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.01 else Vector3(0, 0, 1)
	_arrival_cam.global_position = cmd_pos - dir * 26.0 + Vector3(0, 13.0, 0)
	_arrival_cam.look_at(cmd_pos + Vector3(0, 2.0, 0), Vector3.UP)
	_arrival_cam.make_current()
	_arrival_cut_timer = 3.2

func _on_battle_ended(winning_faction) -> void:
	_end_overview_cut()
	_restore_broadcast_camera()
	var msg := "Draw!" if winning_faction == -1 else "Victory!"
	if winning_faction >= 0:
		var f = battle_manager.get_faction(winning_faction)
		if f and f.faction_data:
			msg = "%s wins!" % f.faction_data.faction_name
	_last_result_text = msg
	if hud:
		hud.add_gift_feed_item("SYSTEM", msg, 0)
	if result_return_enabled:
		_result_timer = result_return_delay

## End-of-game: show the result for a few seconds, then stop everything (units,
## director, spectator) and return to the menu with the result displayed.
func _return_to_menu() -> void:
	_result_timer = -1.0
	if director and director.has_method("stop"):
		director.stop()
	var sc = RegistryAccess.get_spectator()
	if sc and sc.is_spectating():
		sc._toggle_off()
	if battle_manager.current_state != battle_manager.BattleState.MENU:
		battle_manager.change_state(battle_manager.BattleState.MENU)
	if camera and camera.has_method("reset_to_home"):
		camera.reset_to_home()
	if main_menu:
		main_menu.visible = true
		if main_menu.has_method("show_result"):
			main_menu.show_result(_last_result_text)

func _get_spawn_pos(faction_id: int) -> Vector3:
	var faction = battle_manager.get_faction(faction_id)
	if faction and faction.faction_data and faction.faction_data.spawn_areas.size() > 0:
		var base = faction.faction_data.spawn_areas[0]
		return base + Vector3(randf_range(-5, 5), 0, randf_range(-5, 5))
	return Vector3(randf_range(-15, 15), 0, randf_range(-10, 10))

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if TEST_SPAWN_KEYS.has(event.keycode):
			var cfg = TEST_SPAWN_KEYS[event.keycode]
			_spawn_test_unit(cfg.faction, cfg.unit)
			return
		match event.keycode:
			KEY_SPACE:
				if battle_manager.current_state == battle_manager.BattleState.IDLE:
					request_countdown()
			KEY_1:
				_fire_commander_gift("bronze")
			KEY_2:
				_fire_commander_gift("silver")
			KEY_3:
				_fire_commander_gift("gold")
			KEY_4:
				_fire_super_power()
			KEY_R:
				if battle_manager.current_state != battle_manager.BattleState.MENU:
					battle_manager.start_game()
			KEY_ESCAPE:
				_return_to_menu()
			KEY_F4:
				if director:
					director.toggle()
			KEY_F5:
				battle_manager.toggle_pause()
			KEY_F6:
				_start_debug_battle()
			KEY_F7:
				_set_lighting_preset(LightingPresets.Preset.SUNSET)
			KEY_F8:
				_set_lighting_preset(LightingPresets.Preset.NIGHT)
			KEY_F9:
				_set_lighting_preset(LightingPresets.Preset.RAIN)
			KEY_F10:
				_set_lighting_preset(LightingPresets.Preset.DAY)
			KEY_B:
				var reg = RegistryAccess.get_registry()
				if reg:
					print("[BattleRegistry] tracked=%d alive=%d" % [reg.alive_units.size(), reg.get_alive_count()])

func _set_lighting_preset(preset: int) -> void:
	if world_env == null or dir_light == null:
		return
	if preset == LightingPresets.Preset.DAY:
		world_env.environment = _base_env
		dir_light.transform = _base_light_transform
		dir_light.light_color = _base_light_color
		dir_light.light_energy = _base_light_energy
		dir_light.shadow_enabled = _base_light_shadow
		print("[Lighting] preset DAY")
		return
	if LightingPresets.apply(world_env, dir_light, preset):
		print("[Lighting] preset %s" % LightingPresets.Preset.keys()[preset])
	else:
		print("[Lighting] preset %s not ready yet" % LightingPresets.Preset.keys()[preset])

func _spawn_test_unit(faction_id: int, unit_name: String) -> void:
	var state = battle_manager.current_state
	if state == battle_manager.BattleState.MENU or state == battle_manager.BattleState.RESET:
		return
	var res = load("res://units/resources/%s.tres" % unit_name)
	if res == null:
		return
	battle_manager.spawn_unit(res, faction_id, _get_spawn_pos(faction_id))
	if hud:
		hud.add_gift_feed_item("TEST", unit_name, 1)

func _start_debug_battle() -> void:
	battle_manager.start_game()
	var militia = load("res://units/resources/militia.tres")
	var knight = load("res://units/resources/knight.tres")
	for i in range(10):
		battle_manager.spawn_unit(militia, 0, _get_spawn_pos(0))
		battle_manager.spawn_unit(knight, 1, _get_spawn_pos(1))
	request_countdown()
