extends Node
## Headless smoke test of the anganwadi session flow, driven through InputRouter exactly
## like the remote (no vision service needed):
##   godot --headless --path game res://tests/SessionSmoke.tscn -- --usage-dir=/tmp/x
## Prints "SMOKE OK" or "SMOKE FAIL: …" and exits 0 / 1. tools/tests/test_godot_smoke.py
## runs it when a Godot binary is available.

var fails: Array = []
var _profile_existed := false
var _completed := false       # a script error aborts _run silently: then this stays false


func _ready() -> void:
	_profile_existed = FileAccess.file_exists(Centre.USER_PATH)
	Centre.set_value("landing", "session")   # the fixed-session start screen first; picker later
	add_child(load("res://scenes/Main.tscn").instantiate())
	await _run()
	if not _completed:
		fails.append("the test stopped early (script error above)")
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


## wait (≤ 5 s) for a game to be running after its title card
func wait_game(gid: String) -> void:
	for i in 25:
		if GameManager.current_game_id == gid:
			return
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
	check(step_id() == "warmup" and GameManager.current_game_id == "", "warm-up starts with the game's title card")
	await wait_game("simon_says")
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
	await press("next", 0.05)
	await press("select", 0.1)   # item 1: week
	check(Centre.week() != week_before, "week cycles")
	while Centre.week() != week_before:
		await press("select", 0.05)
	for i in 7:
		InputRouter.fire("next")
	await press("select", 0.1)   # item 8: lift today's cap
	check(not Stats.cap_reached(Centre.int_value("max_sessions_per_day"), Centre.int_value("max_minutes_per_day")), "cap lifted")
	await press("next", 0.05)
	await press("select", 0.1)   # item 9: usage page
	check(sup.page == sup.Page.USAGE, "usage page")
	await press("back", 0.1)
	for i in 3:
		InputRouter.fire("next")
	await press("select", 0.1)   # item 12: status page
	check(sup.page == sup.Page.STATUS and sup.status_lines().size() > 5, "status page")
	await press("back", 0.1)
	await press("prev", 0.05)
	await press("select", 0.3)   # item 11: privacy page
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
	# week 2 (fruits): theme = catch_mango (not built → Simon Says) then Bubble Pop
	ContentDB.session["pause_after_s"] = 9999.0   # no camera here: don't pause for "children left"
	Centre.set_value("current_week", 2)
	Centre.set_value("max_sessions_per_day", 99)
	await press("next")          # start
	await press("next")          # greet → warm-up
	await press("next", 0.4)     # warm-up → theme (bridge)
	await press("next", 0.4)     # skip bridge
	games = sd.segments.map(func(x): return x["game"])
	check(games == ["simon_says", "bubble_pop"], "week 2 → fallback + bubble_pop (got %s)" % str(games))
	sd._next_segment()
	await wait_game("bubble_pop")
	var bp = GameManager.current_game
	check(GameManager.current_game_id == "bubble_pop" and bp.pack == "local_fruits", "bubble pop with the fruit pack")
	for i in 30:
		if not bp.target.is_empty() and not bp.bubbles.is_empty():
			break
		await wait(0.2)
	check(not bp.bubbles.is_empty(), "bubbles rise")
	check(bp._photos.size() == 4, "fruit photos loaded (%d)" % bp._photos.size())
	var wanted := int(bp.d("pops_to_win", 2))
	for i in wanted:
		bp.bubbles.append({"x0": 0.5, "x": 0.5, "y": 0.5, "r": 0.08, "item": bp.target, "phase": 0.0, "speed": 0.0})
		bp.pop_bubble(bp.bubbles[-1])
	check(bp.successes == 1 and bp.st == bp.St.CELEBRATE, "popping the asked bubble wins the round")
	await press("supervisor")
	await press("back", 0.3)
	# free play: "Choose a game" — hand dwell picks, buttons move/start/back
	await press("supervisor")
	sup = GameManager._supervisor
	for d in [1, 2, 3, 4]:
		for i in d:
			InputRouter.fire("next")
		await press("select", 0.1)
	for i in 13:
		InputRouter.fire("next")
	await press("select", 0.3)   # item 13: choose a game (free play)
	var picker = GameManager.current
	check(GameManager.mode == "free_play" and picker != null and "games" in picker, "free play opens the game picker")
	check(picker.games == ["session", "simon_says", "bubble_pop@local_fruits", "bubble_pop@numbers_1_5"],
		"picker: session card + games, one card per bubble pack (got %s)" % str(picker.games))
	var rects: Array = picker.card_rects()
	await wait(1.3)    # page cooldown
	picker.fake_hands = [{"pos": (rects[3] as Rect2).get_center(), "radius": 40.0}]
	await wait(0.8)
	check(picker.dwell[3] > 0.2 and picker.dwell[1] == 0.0, "hand on a card fills its ring")
	picker.fake_hands = [{"pos": Vector2(5, 5), "radius": 40.0}]
	await wait(0.6)
	check(picker.dwell[3] < 0.2, "moving away drains the ring")
	picker.fake_hands = [{"pos": (rects[3] as Rect2).get_center(), "radius": 40.0}]
	await wait(1.8)
	check(picker.page == "levels" and picker.games == ["level:easy", "level:medium", "level:hard"],
		"Number bubbles → Easy / Medium / Hard (got %s)" % str(picker.games))
	check(picker.dwell.max() == 0.0, "same hand doesn't pick a level right away (cooldown)")
	picker.fake_hands = []
	await press("back", 0.2)
	check(picker.page == "games" and picker.sel == 3, "back on the level page → games")
	await press("long", 0.3)      # Number bubbles again → levels
	await press("next", 0.1)      # → medium
	await press("long")
	await wait_game("bubble_pop")
	var nb = GameManager.current_game
	check(nb != null and nb.pack == "numbers_1_5" and nb.level == "medium", "number bubbles, medium")
	check(nb.bees_on(), "medium has bees")
	for i in 40:
		if not nb.target.is_empty():
			break
		await wait(0.2)
	var decoy = nb._decoy_pool().filter(func(x): return x["id"] != nb.target["id"])[0]
	nb.bubbles.append({"x0": 0.5, "x": 0.5, "y": 0.5, "r": 0.08, "item": decoy, "phase": 0.0, "speed": 0.0})
	nb.pop_bubble(nb.bubbles[-1])
	nb.bubbles.append({"x0": 0.5, "x": 0.5, "y": 0.5, "r": 0.08, "item": nb.bee, "phase": 0.0, "speed": 0.0})
	nb.pop_bubble(nb.bubbles[-1])
	nb.bubbles.append({"x0": 0.5, "x": 0.5, "y": 0.5, "r": 0.08, "item": nb.target, "phase": 0.0, "speed": 0.0})
	nb.pop_bubble(nb.bubbles[-1])
	check(nb.correct == 1 and nb.wrong == 2 and nb.score == -1,
		"score: −1 decoy, −1 bee, +1 right → −1 (got %d)" % nb.score)
	check(nb._flash > 0.5, "wrong pop flashes red")
	var pool_ids: Array = nb._decoy_pool().map(func(x): return x["id"])
	check(pool_ids.has("mango") and pool_ids.has("two" if nb.target["id"] != "two" else "one"),
		"number decoys mix other numbers and fruits")
	await press("back", 0.4)
	picker = GameManager.current
	check("games" in picker and picker.sel == 3, "back from a game → picker, last card highlighted")
	picker.sel = 1
	await press("long")
	await wait_game("simon_says")
	check(GameManager.current_game_id == "simon_says", "long press starts the highlighted game")
	await press("back", 0.4)
	await press("back", 0.4)
	check(GameManager.mode == "session" and idle_variant() == "ready", "back from the picker → idle")

	# picker as the start screen: "Today's session" card starts the session, home after it
	Centre.set_value("landing", "picker")
	GameManager.go_home()
	await wait(0.3)
	picker = GameManager.current
	check(GameManager.mode == "free_play" and "games" in picker and picker.games[0] == "session", "start screen = picker")
	await press("back", 0.3)
	check("games" in GameManager.current, "back on the start-screen picker stays there")
	GameManager.current.sel = 0
	await press("long", 1.2)
	check(sd.st == sd.St.RUNNING and GameManager.mode == "session", "session card starts the session")
	await press("back", 0.4)      # stop → goodbye
	await press("next", 0.4)      # skip goodbye → "see you tomorrow"
	check(idle_variant() == "tomorrow", "session end → see you tomorrow")
	await press("next", 0.4)      # any press → straight back to the picker
	check(GameManager.mode == "free_play" and "games" in GameManager.current, "→ back to the picker")

	# held Space with X11/XWayland auto-repeat (release+press pairs) is ONE long press
	var fired: Array = []
	var rec := func(a: String) -> void: fired.append(a)
	InputRouter.action.connect(rec)
	InputRouter._single("down", "space")
	for i in 12:
		await wait(0.2)
		InputRouter._single("up", "space")
		await wait(0.03)
		InputRouter._single("down", "space")
	check(InputRouter.hold_seconds() > 2.0, "hold time keeps counting through auto-repeat")
	InputRouter._single("up", "space")
	await wait(0.4)
	InputRouter.action.disconnect(rec)
	check(fired == ["long"], "auto-repeat hold → one 'long' (got %s)" % str(fired))
	await wait(1.5)
	Centre.set_value("landing", "picker")
	Centre.set_value("current_week", 3)
	Centre.set_value("max_sessions_per_day", 2)
	_completed = true
