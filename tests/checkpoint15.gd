extends SceneTree
## Part 15 checkpoint: LIVE end-to-end wiring. The real node bridge + simulator
## stream comments and gifts over websockets into the game's WebSocketClient,
## through main_battlefield -> gift_manager -> engagement_tracker /
## commander_manager / team_manager. Verifies the whole chain produces data:
##   - engagement counter + leaderboard populated
##   - viewer teams assigned from chat comments
##   - commander warbands actually spawned in battle
##   - every commander sits on their viewer's team faction
## Requires the bridge + simulator running (see tests/e2e_live.sh).

const SIM_TEAMS := {
	"u_1001": 0, "u_1004": 0, "u_1006": 0, "u_1007": 0,
	"u_1002": 1, "u_1003": 1, "u_1005": 1, "u_1008": 1,
}

var _pass := 0
var _fail := 0

func _init() -> void:
	_run()

func check(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
		print("PASS ", msg)
	else:
		_fail += 1
		print("FAIL ", msg)

func _run() -> void:
	await create_timer(0.2).timeout
	var scene = load("res://maps/main_battlefield.tscn").instantiate()
	root.add_child(scene)
	await create_timer(0.3).timeout
	var bm = scene.get_node("BattleManager")
	var ws = scene.get_node("WebSocketClient")
	var team_mgr = scene.get_node("TeamManager")
	var eng = RegistryAccess.get_engagement()
	var reg = RegistryAccess.get_registry()

	bm.start_game()
	var militia = load("res://units/resources/militia.tres")
	for i in range(4):
		bm.spawn_unit(militia, 0, Vector3(-50, 0, -50 + i * 3), "", { "force_position": Vector3(-50, 0, -50 + i * 3) })
	for i in range(4):
		bm.spawn_unit(militia, 1, Vector3(50, 0, 50 - i * 3), "", { "force_position": Vector3(50, 0, 50 - i * 3) })
	bm.request_countdown()
	check(bm.current_state == bm.BattleState.BATTLE, "battle is live before simulator feeds")

	# Give the simulator a few seconds to stream real gifts through the bridge.
	var saw_ws := false
	for i in range(60):
		await create_timer(0.25).timeout
		if ws.connected:
			saw_ws = true
			break
	check(saw_ws, "game websocket connected to the bridge")

	await create_timer(10.0).timeout

	var total: float = eng.get_total_spend()
	check(total > 0.0, "engagement counter populated via live gifts (total=%.0f)" % total)
	var lb: Array = eng.get_leaderboard(3)
	check(lb.size() == 3, "leaderboard has top 3 from live viewers")
	if lb.size() == 3:
		check(float(lb[0].spend) >= float(lb[1].spend) and float(lb[1].spend) >= float(lb[2].spend),
				"leaderboard sorted desc")
		check(float(lb[0].spend) <= total + 0.5, "leaderboard spend within total")

	var assigned := 0
	for vid in SIM_TEAMS:
		if team_mgr.get_team(vid) != -1:
			assigned += 1
	check(assigned >= 4, "viewer teams assigned from chat comments (%d/8)" % assigned)

	var cmdrs: Array = reg.get_alive_commanders()
	check(cmdrs.size() > 0, "commander warbands spawned in battle (active=%d)" % cmdrs.size())

	var team_ok := true
	var checked := 0
	for f in bm.factions:
		for u in f.units:
			if not is_instance_valid(u) or str(u.commander_id).is_empty():
				continue
			var expected: int = SIM_TEAMS.get(str(u.commander_id), -1)
			checked += 1
			if expected != -1 and f.faction_id != expected:
				team_ok = false
	check(team_ok and checked > 0, "all commanders on their viewer's team faction (%d checked)" % checked)

	scene.queue_free()
	await create_timer(0.4).timeout
	_finish()

func _finish() -> void:
	print("CHECKPOINT15 RESULT pass=%d fail=%d" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
