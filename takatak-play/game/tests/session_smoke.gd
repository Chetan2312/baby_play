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


## Keep fake tracked hands "fresh" for a while, as if the vision service sent them.
func show_hands(counts: Array, seconds: float) -> void:
	var hs: Array = []
	for i in counts.size():
		var kp: Array = []
		for k in 21:
			kp.append([0.4 + 0.2 * i, 0.4])
		hs.append({"player": 1, "side": ["l", "r"][i], "gesture": "other", "count": counts[i],
			"fingers": [false, false, false, false, false], "tip": [0.4, 0.4], "kp": kp})
	var t := 0.0
	while t < seconds:
		VisionClient.hands = hs
		VisionClient.hands_received += 1
		VisionClient.last_hands_ms = Time.get_ticks_msec()
		await wait(0.05)
		t += 0.05


func finger_math_checks() -> void:
	var FM = load("res://games/finger_math/FingerMath.gd")
	check(FM.finger_total([{"player": 1, "count": 5}, {"player": 1, "count": 1}], [1]) == 6, "5 + 1 fingers = 6")
	check(FM.finger_total([{"player": 1, "count": 3}, {"player": 2, "count": 3}], [1]) == 3, "only the playing child's hands")
	check(FM.finger_total([], [1]) == -1, "no hands → no answer")
	GameManager.mode = "free_play"
	GameManager.pick_game("finger_math", "hard")
	await wait_game("finger_math")
	var fm = GameManager.current_game
	check(fm != null and fm.level == "hard", "finger math, hard")
	var ok := true
	for i in 300:
		var q: Dictionary = fm.make_question(["add", "sub", "count"][i % 3], 1, 10)
		var expect: int = q["a"] + q["b"] if q["kind"] == "add" else (q["a"] - q["b"] if q["kind"] == "sub" else q["a"])
		ok = ok and q["answer"] == expect and q["answer"] >= 1 and q["answer"] <= 10 and q["a"] >= 1 \
			and (q["kind"] == "count" or q["b"] >= 1)
	check(ok, "questions: answers 1–10, both numbers ≥ 1")
	for i in 60:
		if fm.st == fm.St.PLAY:
			break
		await wait(0.1)
	fm.question = {"kind": "add", "a": 3, "b": 3, "answer": 6}
	await show_hands([2, 2], 1.6)                      # 4: wrong, held → −1 once
	check(fm.wrong == 1 and fm.score == -1, "wrong total held → −1 (got wrong %d)" % fm.wrong)
	await show_hands([2, 2], 1.4)
	check(fm.wrong == 1, "the same wrong total isn't counted twice")
	await show_hands([5, 1], 1.5)                      # 5 + 1 = 6: right
	check(fm.correct == 1 and fm.score == 0 and fm.st == fm.St.CELEBRATE, "5 fingers + 1 finger = 6 → right")
	VisionClient.hands = []
	VisionClient.last_hands_ms = -100000
	await press("back", 0.4)                           # back to the picker


func lane_dash_checks() -> void:
	var LD = load("res://games/lane_dash/LaneDash.gd")
	var body := func(x: float) -> Dictionary:
		return {"id": 1, "active": true, "kp": {"l_hip": [x - 0.03, 0.6, 0.9], "r_hip": [x + 0.03, 0.6, 0.9]}}
	check(is_equal_approx(LD.body_x(body.call(0.3)), 0.3), "body x from the hips")
	check(LD.lane_of(0.3, 1, 0.04) == 0 and LD.lane_of(0.7, 0, 0.04) == 1, "body side picks the lane")
	check(LD.lane_of(0.51, 0, 0.04) == 0 and LD.lane_of(0.49, 1, 0.04) == 1, "no lane flicker in the middle")
	GameManager.mode = "free_play"
	GameManager.pick_game("lane_dash", "hard")
	await wait_game("lane_dash")
	var ld = GameManager.current_game
	check(ld != null and ld.lives == 1, "ninja dash hard: one life")
	# fair patterns over a long song
	ld.lvl["song_beats"] = 4000
	var arrivals := {}
	var fair := true
	for b in 3000:
		for o in ld.plan_spawn(b):
			var arr: int = b + 4
			if o["kind"] == "square":
				for other in arrivals.get(1 - o["lane"], []):
					if absf(arr - other) < 2:
						fair = false
				if not arrivals.has(o["lane"]):
					arrivals[o["lane"]] = []
				arrivals[o["lane"]].append(arr)
	check(fair, "never squares in both lanes within 2 beats")
	ld.lvl["song_beats"] = 64
	for i in 120:
		if ld.st == ld.St.PLAY:
			break
		await wait(0.1)
	check(ld.st == ld.St.PLAY, "countdown → play")
	ld.lvl["spawn_every_beats"] = 100000         # only our objects from here on
	ld.objects.clear()
	ld.lives = 3
	VisionClient.active_people = [body.call(0.3)]  # the child stands in the left lane
	await wait(0.2)
	check(ld.lane == 0, "child on the left → left lane")
	ld.spawn_object("circle", 0, ld.beat_pos + 0.2)
	ld.spawn_object("square", 1, ld.beat_pos + 0.2)
	await wait(0.5)
	check(ld.score == 1 and ld.dodged == 1 and ld.lives == 3, "circle smashed, square in the other lane dodged")
	ld.spawn_object("square", 0, ld.beat_pos + 3.0)  # coming down the child's lane …
	await wait(0.3)
	VisionClient.active_people = [body.call(0.7)]  # … the child steps right
	await wait(0.3)
	check(ld.lane == 1 and ld.reactions.size() == 1, "stepping out of a square's lane → reaction time")
	ld.objects.clear()
	ld.spawn_object("square", 1, ld.beat_pos + 0.2)
	await wait(0.5)
	check(ld.lives == 2 and ld.crashes == 1, "square in your lane → crash, −1 life")
	ld.lives = 1
	ld.spawn_object("square", 1, ld.beat_pos + 0.2)
	await wait(0.5)
	check(ld.st == ld.St.SUMMARY and ld.game_over, "last life gone → game over")
	VisionClient.active_people = []
	await press("back", 0.4)


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
	var wanted: int = bp.per_round()
	bp.targets_spawned = wanted                  # the whole wave is "dropped": only ours are on screen
	bp.bubbles = bp.bubbles.filter(func(x): return x["item"]["id"] != bp.target["id"])
	for i in wanted:
		bp.bubbles.append({"x0": 0.5, "x": 0.5, "y": 0.5, "r": 0.08, "item": bp.target, "phase": 0.0, "speed": 0.0})
		bp.pop_bubble(bp.bubbles[-1])
	check(bp.successes == 1 and bp.st == bp.St.CELEBRATE and bp.hits == wanted,
		"popping every asked bubble of the wave wins the round")
	for i in 200:                                 # next round: bubbles drop from the top
		if bp.round_idx == 2 and not bp.bubbles.is_empty():
			break
		await wait(0.05)
	check(not bp.bubbles.is_empty() and float(bp.bubbles[0]["y"]) < 0.5, "bubbles fall from the top")
	bp.wrong = 0
	bp.missed = 0
	bp.correct = 5
	bp._summary()
	check(bp.perfect and bp.st == bp.St.SUMMARY, "no wrong pop, nothing missed → perfect celebration")
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
	check(picker.games == ["session", "simon_says", "bubble_pop@local_fruits", "bubble_pop@numbers_1_5", "finger_math",
		"lane_dash"],
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
	# one pointer per child: the raised hand; both raised → the clearly higher one; none → none
	var view: Vector2 = nb.get_viewport_rect().size
	var person := func(ly: float, ry: float) -> Dictionary:
		return {"id": 7, "active": true, "kp": {
			"l_elbow": [0.4, 0.5, 0.9], "l_wrist": [0.4, ly, 0.9],
			"r_elbow": [0.6, 0.5, 0.9], "r_wrist": [0.6, ry, 0.9]}}
	VisionClient.active_people = [person.call(0.3, 0.7)]            # left up, right hanging
	var ptrs: Array = nb._find_pointers(0.016, view)
	check(ptrs.size() == 1 and nb._pointer_side[7] == "l", "only the raised hand points")
	VisionClient.active_people = [person.call(0.3, 0.28)]           # both up, right barely higher
	ptrs = nb._find_pointers(0.016, view)
	check(ptrs.size() == 1 and nb._pointer_side[7] == "l", "still one pointer; no flip for a small difference")
	VisionClient.active_people = [person.call(0.3, 0.15)]           # right clearly higher
	ptrs = nb._find_pointers(0.016, view)
	check(nb._pointer_side[7] == "r", "clearly higher hand takes over")
	VisionClient.active_people = [person.call(0.7, 0.7)]            # both hanging
	check(nb._find_pointers(0.016, view).is_empty(), "arms down → no pointer, nothing pops")
	VisionClient.active_people = []
	# finger mode: hand tracking running → only a hand showing POINT pops, at its index tip
	var hand := func(gest: String, tip: Array) -> Dictionary:
		var kp: Array = []
		for i in 21:
			kp.append([0.5, 0.5])
		kp[8] = tip
		return {"player": 7, "side": "r", "gesture": gest, "count": 1, "fingers": [false, true, false, false, false],
			"tip": tip, "kp": kp}
	VisionClient.active_people = [person.call(0.7, 0.7)]            # arms down: no arm pointer
	VisionClient.hands = [hand.call("point", [0.55, 0.3])]
	VisionClient.hands_received += 1
	VisionClient.last_hands_ms = Time.get_ticks_msec()
	ptrs = nb._find_pointers(0.016, view)
	check(nb.pointer_mode == "finger" and ptrs.size() == 1, "finger mode: the pointing hand pops")
	check(ptrs.size() == 1 and (ptrs[0]["pos"] as Vector2).distance_to(VisionClient.to_screen(Vector2(0.55, 0.3), view)) < 2.0,
		"…at its index fingertip")
	VisionClient.hands = [hand.call("open", [0.55, 0.3])]
	VisionClient.hands_received += 1
	check(nb._find_pointers(0.016, view).is_empty(), "an open hand doesn't pop")
	VisionClient.last_hands_ms = -100000                            # hand tracking stopped
	VisionClient.active_people = [person.call(0.3, 0.7)]
	nb._find_pointers(0.016, view)
	check(nb.pointer_mode == "arm", "no hand tracking → falls back to the arm pointer")
	VisionClient.hands = []
	VisionClient.active_people = []
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

	# Finger Math: answers are the total of raised fingers over both hands
	await finger_math_checks()
	# Ninja Dash: lanes from the body position, smash / dodge / crash / game over
	await lane_dash_checks()

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
