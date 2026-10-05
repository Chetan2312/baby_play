extends Node
## Headless smoke test of the anganwadi session flow, driven through InputRouter exactly
## like the remote (no vision service needed):
##   godot --headless --path game res://tests/SessionSmoke.tscn -- --usage-dir=/tmp/x
## Prints "SMOKE OK" or "SMOKE FAIL: …" and exits 0 / 1. tools/tests/test_godot_smoke.py
## runs it when a Godot binary is available.

var fails: Array = []
var _profile_existed := false


func _ready() -> void:
	_profile_existed = FileAccess.file_exists(Centre.USER_PATH)
	add_child(load("res://scenes/Main.tscn").instantiate())
	await _run()
	if not _profile_existed:
		DirAccess.remove_absolute(Centre.USER_PATH)
	if fails.is_empty():
		print("SMOKE OK")
	else:
		print("SMOKE FAIL: ", "; ".join(PackedStringArray(fails)))
	get_tree().quit(0 if fails.is_empty() else 1)


func check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)
		print("  FAIL ", msg)


func wait(s := 0.25) -> void:
	await get_tree().create_timer(s).timeout


func press(a: String, s := 0.25) -> void:
	InputRouter.fire(a)
	await wait(s)


## Short press of the single button through the real input path.
func tap_key(code: Key) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.pressed = pressed
		Input.parse_input_event(e)
		await wait(0.05)
	await wait(0.2)


func tap_pointer() -> void:
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = Vector2(400, 300)
		Input.parse_input_event(e)
		await wait(0.05)
	await wait(0.2)


func step_id() -> String:
	return str(SessionDirector.step.get("id", ""))


func idle_variant() -> String:
	var c = GameManager.current
	return str(c.variant) if c != null and is_instance_valid(c) and "variant" in c else ""


func _run() -> void:
	await wait(0.5)
	var sd = SessionDirector
	var base_sessions := Stats.sessions_today()
	Centre.set_value("max_sessions_per_day", base_sessions + 2)
	check(sd.st == sd.St.IDLE and idle_variant() == "ready", "boots to the idle screen")

	# session 1: start → greet (runs out by itself) → warm-up (Simon Says) → time up → theme
	# (bridge line skipped) → stop → goodbye → idle
	await tap_key(KEY_SPACE)
	check(sd.st == sd.St.RUNNING and step_id() == "greet", "Space → start → greet (got %s)" % step_id())
	for i in 40:
		if step_id() != "greet":
			break
		await wait()
	check(step_id() == "warmup" and GameManager.current_game_id == "simon_says", "greet ends by itself → warm-up Simon Says")
	sd.seg_deadline = sd._now() - 1.0
	await wait()
	check(GameManager.current_game != null and GameManager.current_game.finish_requested, "step time up → request_finish")
	await press("next")
	check(step_id() == "theme" and sd._in_bridge, "next → theme, bridge line first (got %s)" % step_id())
	await press("next", 0.4)   # skips only the bridge line
	check(step_id() == "theme", "next during the bridge stays on theme (got %s)" % step_id())
	var games: Array = sd.segments.map(func(x): return x["game"])
	check(games == ["simon_says"], "week 3 games not built → one fallback segment (got %s)" % str(games))
	await press("prev")
	await press("back", 0.4)
	check(step_id() == "goodbye", "stop → goodbye (got %s)" % step_id())
	await press("next", 0.4)
	check(sd.st == sd.St.IDLE and idle_variant() == "tomorrow", "session ends → idle 'see you tomorrow'")
	check(Stats.sessions_today() == base_sessions + 1, "session counted")

	# session 2 (started with a screen tap / click), then the daily cap
	await tap_pointer()
	check(sd.st == sd.St.RUNNING, "tap/click → start")
	await press("back", 0.4)
	await press("next", 0.4)
	check(Stats.sessions_today() == base_sessions + 2, "second session counted")
	await press("next", 0.4)
	check(sd.st == sd.St.IDLE and idle_variant() == "rest", "daily cap → mascot resting")

	# supervisor menu: PIN 1234 with next/select, then a few items
	await press("supervisor")
	check(GameManager.supervisor_open(), "supervisor menu opens")
	var sup = GameManager._supervisor
	for d in [1, 2, 3, 4]:
		for i in d:
			InputRouter.fire("next")
		await press("select", 0.1)
	check(sup.page == sup.Page.MENU, "correct PIN → menu")
	var week_before := Centre.week()
	await press("select", 0.1)   # item 0: week
	check(Centre.week() != week_before, "week cycles")
	while Centre.week() != week_before:
		await press("select", 0.05)
	for i in 7:
		InputRouter.fire("next")
	await press("select", 0.1)   # item 7: lift today's cap
	check(not Stats.cap_reached(Centre.int_value("max_sessions_per_day"), Centre.int_value("max_minutes_per_day")), "cap lifted")
	await press("next", 0.05)
	await press("select", 0.1)   # item 8: usage page
	check(sup.page == sup.Page.USAGE, "usage page")
	await press("back", 0.1)
	for i in 3:
		InputRouter.fire("next")
	await press("select", 0.1)   # item 11: status page
	check(sup.page == sup.Page.STATUS and sup.status_lines().size() > 5, "status page")
	await press("back", 0.1)
	await press("prev", 0.05)
	await press("select", 0.3)   # item 10: privacy page
	check(sup.page == sup.Page.PRIVACY, "privacy page")
	await press("back", 0.1)
	await press("back", 0.3)
	check(not GameManager.supervisor_open() and idle_variant() == "ready", "menu closes → idle")

	# supervisor during a session ends it quietly
	await press("next")
	check(sd.st == sd.St.RUNNING, "cap lifted → session starts")
	await press("supervisor")
	check(sd.st == sd.St.IDLE and GameManager.supervisor_open(), "supervisor during a session")
	await press("back", 0.3)
	var e: Dictionary = Stats.day_entry()
	check(int(e["steps_completed"].get("greet", 0)) >= 1, "completed steps counted (skipped ones are not)")
	check(e["games"].has("simon_says"), "game counted")
	Centre.set_value("max_sessions_per_day", 2)
