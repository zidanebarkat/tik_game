extends Node
## BattleRegistry autoload singleton.
## Single source of truth for which units are alive, so the spectator camera
## and commander systems never reach into faction internals. Units register
## in their _ready() and unregister on death or when leaving the tree.

signal unit_spawned(unit)
signal unit_died(unit)

const SPECTATE_WEIGHTS := {
	"militia": 1.0,
	"spearman": 1.2,
	"knight": 1.8,
	"tank": 1.8,
	"titan": 2.5,
	"commander": 3.0,
}

var alive_units: Array = []

func register(unit) -> void:
	if unit in alive_units:
		return
	alive_units.append(unit)
	unit_spawned.emit(unit)

func unregister(unit) -> void:
	var idx := alive_units.find(unit)
	if idx < 0:
		return
	alive_units.remove_at(idx)
	unit_died.emit(unit)

func is_eligible(unit) -> bool:
	return is_instance_valid(unit) and unit.is_inside_tree() \
		and unit.has_method("is_spectate_eligible") and unit.is_spectate_eligible()

func get_alive_by_type(type_name: String) -> Array:
	var out: Array = []
	for u in alive_units:
		if is_instance_valid(u) and u.has_method("get_unit_type") and u.get_unit_type() == type_name:
			out.append(u)
	return out

func get_alive_commanders() -> Array:
	return get_alive_by_type("commander")

func get_alive_by_faction(faction: int) -> Array:
	var out: Array = []
	for u in alive_units:
		if is_instance_valid(u) and u.faction_id == faction:
			out.append(u)
	return out

func get_alive_count() -> int:
	var n := 0
	for u in alive_units:
		if is_instance_valid(u) and u.is_inside_tree() and u.current_health > 0.0:
			n += 1
	return n

## Weighted random pick from the alive, spectate-eligible pool. Bigger /
## more visually interesting units are weighted higher than raw population
## would suggest (see SPECTATE_WEIGHTS).
func pick_spectate_target(exclude = null):
	var candidates: Array = []
	var weights: Array = []
	var total := 0.0
	for u in alive_units:
		if not is_eligible(u) or u == exclude:
			continue
		var w: float = SPECTATE_WEIGHTS.get(u.get_unit_type(), 1.0)
		candidates.append(u)
		weights.append(w)
		total += w
	if total <= 0.0 or candidates.is_empty():
		return null
	var roll := randf() * total
	var acc := 0.0
	for i in range(candidates.size()):
		acc += float(weights[i])
		if roll <= acc:
			return candidates[i]
	return candidates[candidates.size() - 1]

func _exit_tree() -> void:
	alive_units.clear()
