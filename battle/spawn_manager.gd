extends Node

var queue: Array = []
var battle_manager = null
var batch_size: int = 10
var spawn_interval: float = 0.1
var _timer: float = 0.0

func _process(delta: float) -> void:
	if queue.is_empty():
		return
	var bstate = battle_manager.current_state if battle_manager else null
	if bstate != null and (bstate == battle_manager.BattleState.MENU \
			or bstate == battle_manager.BattleState.RESET):
		queue.clear()
		return
	_timer += delta
	if _timer >= spawn_interval:
		_process_batch()
		_timer = 0.0

func add_request(faction_id: int, unit_resource, position: Vector3, sender: String = "", priority: int = 0) -> void:
	var req = {
		"faction_id": faction_id,
		"unit_resource": unit_resource,
		"position": position,
		"sender": sender,
		"priority": priority,
		"timestamp": Time.get_ticks_msec() / 1000.0
	}
	queue.append(req)
	queue.sort_custom(func(a, b): return a.priority > b.priority)

func _process_batch() -> void:
	var count = mini(batch_size, queue.size())
	for i in range(count):
		var req = queue.pop_front()
		if battle_manager:
			battle_manager.spawn_unit(req.unit_resource, req.faction_id, req.position, req.sender)

func clear() -> void:
	queue.clear()
