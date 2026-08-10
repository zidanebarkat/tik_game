extends Node
## EngagementTracker autoload.
## Part 8 engagement layer: turns raw gift events into the "that's my name on
## screen" payoff.
##  - cumulative spend per viewer this stream
##  - commander titles by cumulative spend (Baron / Warlord / King)
##  - a persistent, per-viewer banner color (repeat gifters are recognizable
##    before the nameplate is read)
##  - kill-feed entries attributed to a commander's squad
##  - a session leaderboard (top commanders by gift value)

signal kill_feed_entry(entry: Dictionary)
signal leaderboard_changed()

const TITLE_TIERS := [
	{"min_spend": 500, "title": "King", "color": Color(0.72, 0.34, 0.9)},
	{"min_spend": 100, "title": "Warlord", "color": Color(0.9, 0.45, 0.15)},
	{"min_spend": 20, "title": "Baron", "color": Color(0.9, 0.75, 0.25)},
]

const BANNER_PALETTE := [
	Color(0.85, 0.7, 0.2),
	Color(0.25, 0.65, 0.9),
	Color(0.9, 0.35, 0.35),
	Color(0.35, 0.75, 0.4),
	Color(0.75, 0.4, 0.85),
	Color(0.9, 0.6, 0.25),
	Color(0.3, 0.8, 0.75),
	Color(0.85, 0.45, 0.6),
]

const LEADERBOARD_SIZE := 3
const KILL_FEED_MAX := 5

var _viewers: Dictionary = {}

func _ready() -> void:
	var reg = RegistryAccess.get_registry()
	if reg:
		reg.unit_died.connect(_on_unit_died)

func record_gift(viewer_id: String, viewer_name: String, value: float, is_commander: bool = false) -> void:
	if viewer_id.is_empty() or value <= 0.0:
		return
	var safe_name := viewer_name if not viewer_name.is_empty() else viewer_id
	var entry: Dictionary = _viewers.get(viewer_id, {"name": safe_name, "spend": 0.0})
	entry["name"] = safe_name
	entry["spend"] = float(entry.get("spend", 0.0)) + value
	if is_commander:
		entry["commander_spend"] = float(entry.get("commander_spend", 0.0)) + value
	_viewers[viewer_id] = entry
	leaderboard_changed.emit()

func get_viewer_spend(viewer_id: String) -> float:
	if viewer_id.is_empty():
		return 0.0
	var e: Dictionary = _viewers.get(viewer_id, {})
	return float(e.get("spend", 0.0))

func get_title(viewer_id: String) -> String:
	return _title_for_spend(get_viewer_spend(viewer_id)).title

func get_title_color(viewer_id: String) -> Color:
	return _title_for_spend(get_viewer_spend(viewer_id)).color

func get_banner_color(viewer_id: String) -> Color:
	var h := absi(hash(viewer_id if not viewer_id.is_empty() else "anon"))
	return BANNER_PALETTE[h % BANNER_PALETTE.size()]

func get_leaderboard(limit: int = LEADERBOARD_SIZE) -> Array:
	var entries: Array = []
	for vid in _viewers:
		var e: Dictionary = _viewers[vid]
		if float(e.get("spend", 0.0)) <= 0.0:
			continue
		entries.append({
			"viewer_id": vid,
			"name": str(e.get("name", vid)),
			"spend": float(e.get("spend", 0.0)),
			"title": _title_for_spend(float(e.get("spend", 0.0))).title,
			"color": _title_for_spend(float(e.get("spend", 0.0))).color,
		})
	entries.sort_custom(func(a, b): return a.spend > b.spend)
	return entries.slice(0, limit)

func _title_for_spend(spend: float) -> Dictionary:
	for tier in TITLE_TIERS:
		if spend >= float(tier.min_spend):
			return tier
	return {"title": "", "color": Color(0.9, 0.85, 0.7)}

func _on_unit_died(victim) -> void:
	if victim == null or not is_instance_valid(victim):
		return
	var killer = victim.get_last_attacker()
	if killer == null or not is_instance_valid(killer):
		return
	if str(killer.commander_id).is_empty():
		return
	var killer_type: String = killer.get_unit_type()
	var killer_label: String = "commander" if killer_type == "commander" else killer_type
	var entry := {
		"commander_name": str(killer.commander_name),
		"killer_label": killer_label,
		"victim_label": _victim_label(victim),
		"color": get_banner_color(str(killer.commander_id)),
	}
	kill_feed_entry.emit(entry)

func _victim_label(victim) -> String:
	if not str(victim.commander_id).is_empty():
		return "%s's %s" % [str(victim.commander_name), victim.get_unit_type()]
	return "raider" if victim.faction_id == 1 else "host unit"
