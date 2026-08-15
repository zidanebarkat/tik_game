extends SceneTree
## Part 13 checkpoint: engagement counter + top-3 leaderboard with team,
## portrait and stats. Gifts flow through gift_manager -> engagement_tracker,
## which exposes a running total and per-viewer spend/gift-count. The HUD panel
## renders rows (rank, portrait, team tag, points, gifts, title) and a TOTAL
## engagement counter in its title.

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
	var gift_mgr = scene.get_node("GiftManager")
	var team_mgr = scene.get_node("TeamManager")
	var hud = scene.get_node("HUD")
	var eng = RegistryAccess.get_engagement()
	bm.start_game()

	team_mgr.assign_team("viewer_a", 0)
	team_mgr.assign_team("viewer_b", 1)
	team_mgr.assign_team("viewer_c", 0)
	gift_mgr.process_gift("Galaxy", "Alice", 1, "viewer_a")
	gift_mgr.process_gift("Galaxy", "Alice", 1, "viewer_a")
	gift_mgr.process_gift("Rocket", "Bob", 1, "viewer_b")
	gift_mgr.process_gift("Share", "Carol", 1, "viewer_c")
	gift_mgr.process_gift("Share", "Dave", 1, "viewer_d")
	gift_mgr.process_gift("Share", "Dave", 1, "viewer_d")

	check(is_equal_approx(eng.get_total_spend(), 20.0 + 20.0 + 100.0 + 1.0 + 2.0),
			"engagement counter totals all spend (%.0f)" % eng.get_total_spend())

	var lb: Array = eng.get_leaderboard(3)
	check(lb.size() == 3, "leaderboard returns top 3")
	if lb.size() == 3:
		check(str(lb[0].viewer_id) == "viewer_b", "rank 1 = Bob (Rocket 100)")
		check(str(lb[1].viewer_id) == "viewer_a", "rank 2 = Alice (Galaxy x2)")
		check(float(lb[0].spend) >= float(lb[1].spend) and float(lb[1].spend) >= float(lb[2].spend),
				"leaderboard sorted by spend desc")
		check(int(lb[1].gifts) == 2, "gift count tracked per viewer (%d)" % int(lb[1].gifts))
		check(not str(lb[0].title).is_empty(), "spend threshold earned a title (%s)" % lb[0].title)

	hud._refresh_leaderboard()
	check(hud.leaderboard_panel.visible, "leaderboard panel visible in battle")
	check(hud.leaderboard_title.text.contains("TOTAL %d" % int(eng.get_total_spend())),
			"title shows engagement counter (%s)" % hud.leaderboard_title.text)
	var rows: Array = hud._leaderboard_rows
	check(rows.size() == 3 and rows[0].visible and rows[1].visible and rows[2].visible, "three rows rendered")
	if rows.size() >= 3:
		check(rows[0].get_node("Info/Name").text.contains("[BLUE]"), "rank 1 tagged BLUE (%s)" % rows[0].get_node("Info/Name").text)
		check(rows[1].get_node("Info/Name").text.contains("[RED]"), "rank 2 tagged RED (%s)" % rows[1].get_node("Info/Name").text)
		check(rows[2].get_node("Info/Name").text.strip_edges() == "Dave", "rank 3 unassigned name w/o team tag (%s)" % rows[2].get_node("Info/Name").text)
		check(rows[0].get_node("Portrait").texture != null, "portrait texture on leaderboard rows")
		check(rows[0].get_node("Info/Stats").text.contains("100 pts"), "stats line shows points (%s)" % rows[0].get_node("Info/Stats").text)

	scene.queue_free()
	await create_timer(0.4).timeout
	_finish()

func _finish() -> void:
	print("CHECKPOINT13 RESULT pass=%d fail=%d" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
