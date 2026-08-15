extends Node
## CommanderManager autoload.
## Turns a qualifying gift into a full named, bannered warband: a commander
## carrying the viewer's name/portrait at the head of a squad column, spawning
## together at a reinforcement point on the map edge (away from the melee).
##
## A tiny FIFO queue backs the concurrent-commander cap: if the cap is hit the
## gift waits for a slot instead of overlapping a live squad.

signal warband_spawned(viewer_name: String, viewer_id: String, tier: String, commander_unit)
signal warband_queued(viewer_name: String, viewer_id: String, tier: String)
signal arrival_finished(commander_unit)

const MAX_ACTIVE_COMMANDERS := 3
const TIERS := {
	"bronze": {
		"pop": 8,
		"squad": ["militia", "militia", "militia", "militia", "spearman", "spearman", "knight", "commander"],
	},
	"silver": {
		"pop": 15,
		"squad": ["spearman", "spearman", "spearman", "knight", "knight", "knight", "tank", "commander"],
	},
	"gold": {
		"pop": 25,
		"squad": ["knight", "knight", "knight", "knight", "tank", "tank", "titan", "titan", "commander"],
	},
}

const ESCORT_SLOTS := [
	Vector3(0.9, 0.0, -2.2),
	Vector3(-0.9, 0.0, -2.2),
	Vector3(1.8, 0.0, -4.4),
	Vector3(0.0, 0.0, -4.4),
	Vector3(-1.8, 0.0, -4.4),
	Vector3(2.7, 0.0, -6.6),
	Vector3(0.9, 0.0, -6.6),
	Vector3(-0.9, 0.0, -6.6),
	Vector3(-2.7, 0.0, -6.6),
]

const REINFORCE_BACK_DISTANCE := 30.0
const REINFORCE_WAYPOINT_AHEAD := 15.0
const MARCH_SPEED := 3.4
const LANE_SPACING := 7.0
const PORTRAIT_SIZE := 128

var battle_manager = null
var default_faction_id: int = 0

var pending_events: Array = []
var _portrait_cache: Dictionary = {}
var _squad_sequence: int = 0
var _horn_player: AudioStreamPlayer = null
var _arrival_cut_pending: Array = []

func _ready() -> void:
	_horn_player = AudioStreamPlayer.new()
	_horn_player.name = "HornPlayer"
	_horn_player.stream = ProceduralHorn.make_horn_wav()
	add_child(_horn_player)

func play_horn() -> void:
	if _horn_player and _horn_player.stream:
		_horn_player.play()

func _process(delta: float) -> void:
	_try_issue_next()
	_update_arrival_cuts()

func is_battle_live() -> bool:
	if not battle_manager:
		return false
	return battle_manager.current_state == battle_manager.BattleState.BATTLE

func active_commander_count() -> int:
	var reg = RegistryAccess.get_registry()
	if reg:
		return reg.get_alive_commanders().size()
	return 0

## Entry point from the gift pipeline. `avatar_url` is optional: when empty a
## cached placeholder is used (real avatar fetching is wired externally).
## `team` (0=red, 1=blue) comes from the viewer's team comment; -1 means the
## viewer never picked a side and falls back to the default faction.
func process_commander_gift(gift_name: String, tier: String, viewer_id: String,
		viewer_name: String, avatar_url: String = "", team: int = -1) -> void:
	if not TIERS.has(tier):
		return
	var safe_id := viewer_id if not viewer_id.is_empty() else viewer_name
	var safe_name := viewer_name if not viewer_name.is_empty() else safe_id
	var event := {
		"gift": gift_name,
		"tier": tier,
		"viewer_id": safe_id,
		"viewer_name": safe_name,
		"avatar_url": avatar_url,
		"team": team,
	}
	if not _can_spawn(event):
		pending_events.append(event)
		warband_queued.emit(safe_name, safe_id, tier)
		return
	_spawn_squad(event)

## Injects a viewer avatar texture (e.g. from an HTTP fetch) into the cache.
func set_viewer_portrait(viewer_id: String, texture: Texture2D) -> void:
	if viewer_id.is_empty() or texture == null:
		return
	_portrait_cache[viewer_id] = texture

func get_viewer_portrait(viewer_id: String) -> Texture2D:
	var cached: Texture2D = _portrait_cache.get(viewer_id)
	if cached:
		return cached
	var placeholder := _make_placeholder_portrait(viewer_id)
	_portrait_cache[viewer_id] = placeholder
	return placeholder

## Debug / test hook: fires a commander gift without a real TikTok event.
func debug_spawn(tier: String, viewer_name: String = "DebugViewer", viewer_id: String = "") -> void:
	var vid := viewer_id if not viewer_id.is_empty() else "debug_" + viewer_name
	process_commander_gift("DebugGift", tier, vid, viewer_name)

func _can_spawn(event: Dictionary) -> bool:
	if not is_battle_live():
		return false
	if active_commander_count() >= MAX_ACTIVE_COMMANDERS:
		return false
	var pop_cost: int = TIERS[event.tier].pop
	var faction = _target_faction(int(event.get("team", -1)))
	if faction and faction.population + pop_cost > faction.max_population:
		return false
	return true

func _target_faction(team: int = -1):
	if not battle_manager:
		return null
	if team == 0 or team == 1:
		return battle_manager.get_faction(team)
	return battle_manager.get_faction(default_faction_id)

func _try_issue_next() -> void:
	if not is_battle_live():
		return
	while pending_events.size() > 0:
		var ev = pending_events.front()
		if not _can_spawn(ev):
			if active_commander_count() >= MAX_ACTIVE_COMMANDERS:
				return
			# pop-capped: drop silently rather than stall the queue forever
			pending_events.pop_front()
			continue
		pending_events.pop_front()
		_spawn_squad(ev)

func _spawn_squad(event: Dictionary) -> void:
	var faction = _target_faction(int(event.get("team", -1)))
	if not faction:
		return
	var tier: String = event.tier
	var viewer_id: String = event.viewer_id
	var viewer_name: String = event.viewer_name
	var portrait := get_viewer_portrait(viewer_id)
	var squad: Array = TIERS[tier].squad

	var eng = RegistryAccess.get_engagement()
	var banner_color := Color(0.85, 0.7, 0.2)
	var title := ""
	var title_color := Color(0.9, 0.85, 0.7)
	if eng:
		banner_color = eng.get_banner_color(viewer_id)
		title = eng.get_title(viewer_id)
		title_color = eng.get_title_color(viewer_id)

	var fwd := _march_direction(faction)
	var right := Vector3(-fwd.z, 0.0, fwd.x)
	var lane := float(_squad_sequence % 4) * LANE_SPACING - LANE_SPACING * 1.5
	_squad_sequence += 1
	var anchor := _reinforcement_anchor(faction) + right * lane
	var waypoint := _faction_center(faction) + fwd * REINFORCE_WAYPOINT_AHEAD

	var commander_unit = null
	var spawned: Array = []
	var escort_idx := 0
	for unit_name in squad:
		var res = load("res://units/resources/%s.tres" % unit_name)
		if res == null:
			continue
		var is_cmd: bool = unit_name == "commander"
		var offset = Vector3.ZERO if is_cmd else ESCORT_SLOTS[mini(escort_idx, ESCORT_SLOTS.size() - 1)]
		if not is_cmd:
			escort_idx += 1
		var local_pos = right * offset.x + fwd * offset.z
		var opts := {
			"force_position": anchor + local_pos,
			"rotation_y": atan2(-fwd.x, -fwd.z),
			"faction_tag": "commander_" + viewer_id,
			"commander_id": viewer_id,
			"commander_name": viewer_name,
			"display_name": viewer_name if is_cmd else "",
			"portrait_texture": portrait if is_cmd else null,
			"banner_color": banner_color,
			"commander_title": title if is_cmd else "",
			"commander_title_color": title_color if is_cmd else Color(0.9, 0.85, 0.7),
		}
		battle_manager.spawn_unit(res, faction.faction_id, anchor + local_pos, viewer_name, opts)
		var unit = battle_manager.get_faction(faction.faction_id).units.back()
		if unit == null or not is_instance_valid(unit):
			continue
		unit.squad_offset = local_pos
		unit.march_speed = MARCH_SPEED
		unit.start_march(waypoint, is_cmd, local_pos if not is_cmd else Vector3.ZERO)
		spawned.append(unit)
		if is_cmd:
			commander_unit = unit
	_arrival_cut_pending.append(commander_unit)
	warband_spawned.emit(viewer_name, viewer_id, tier, commander_unit)

## Part 7: report each commander whose arrival march has finished (released to
## combat AI) so the spectator camera can auto-cut to them. A commander that
## dies during the march is dropped without an event.
func _update_arrival_cuts() -> void:
	if _arrival_cut_pending.is_empty():
		return
	var still_pending: Array = []
	for c in _arrival_cut_pending:
		if not is_instance_valid(c) or c._dying:
			continue
		if not c.is_marching():
			arrival_finished.emit(c)
			continue
		still_pending.append(c)
	_arrival_cut_pending = still_pending

func _faction_base_centroid(faction) -> Vector3:
	var base := Vector3.ZERO
	if faction and faction.faction_data and faction.faction_data.spawn_areas.size() > 0:
		for a in faction.faction_data.spawn_areas:
			base += a
		base /= faction.faction_data.spawn_areas.size()
	return base

func _faction_center(faction) -> Vector3:
	return _faction_base_centroid(faction)

func _enemy_centroid(faction) -> Vector3:
	var enemy_base := Vector3(30.0, 0.0, -30.0)
	if battle_manager:
		for f in battle_manager.factions:
			if f != faction and f.faction_data and f.faction_data.spawn_areas.size() > 0:
				var acc := Vector3.ZERO
				for a in f.faction_data.spawn_areas:
					acc += a
				enemy_base = acc / f.faction_data.spawn_areas.size()
	return enemy_base

func _reinforcement_anchor(faction) -> Vector3:
	var base := _faction_center(faction)
	var dir := _march_direction(faction)
	return base - dir * REINFORCE_BACK_DISTANCE

func _march_direction(faction) -> Vector3:
	var base := _faction_center(faction)
	var enemy_base := _enemy_centroid(faction)
	var dir := enemy_base - base
	dir.y = 0.0
	if dir.length_squared() < 0.01:
		dir = Vector3(0.0, 0.0, 1.0)
	return dir.normalized()

func _make_placeholder_portrait(key: String) -> Texture2D:
	var img := Image.create(PORTRAIT_SIZE, PORTRAIT_SIZE, false, Image.FORMAT_RGBA8)
	var hue := float(abs(hash(key)) % 360) / 360.0
	img.fill(Color.from_hsv(hue, 0.6, 0.75, 1.0))
	return ImageTexture.create_from_image(img)
