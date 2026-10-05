extends "res://core/BaseGame.gd"
## Simon Says: Body Parts (port of Demo 1).
## Mascot says the prompt → child holds the pose (vision sends gesture start/held) →
## praise + word in 3 scripts. Timeout → mascot demonstrates + hint → gentle move on.
## All timing comes from content/games/simon_says.yaml; gesture tolerances from the
## vision service (set_difficulty).

const UiKit = preload("res://core/UiKit.gd")
const ProgressRingScript = preload("res://core/ProgressRing.gd")
const RoundDotsScript = preload("res://core/RoundDots.gd")

enum St { IDLE, INTRO, LISTEN, HINT, CELEBRATE, DONE }

var st := St.IDLE
var st_time := 0.0
var content: Dictionary = {}
var settings: Dictionary = {}
var difficulty := "toddler"
var prompts: Dictionary = {}
var pool: Array = []
var prompt: Dictionary = {}
var round_idx := 0
var attempt := 1
var armed := false
var armed_at := 0.0
var listen_elapsed := 0.0
var listen_time := 0.0
var prompt_started := 0.0
var gstate: Dictionary = {}     # gesture name -> "start" | "held" | "end" (active player)
var gstart: Dictionary = {}
var results: Array = []
var successes := 0
var events: Array = []

var _bag: Array = []
var _last_id := ""
var _card: Control = null
var _ring = null
var _dots = null


func _init() -> void:
	game_id = "simon_says"
	needs_frames = true
	camera_mode = "mirror"


func setup(cfg: Dictionary) -> void:
	super.setup(cfg)
	content = cfg.get("content", {})
	settings = content.get("settings", {})
	difficulty = str(cfg.get("difficulty", "toddler"))
	for p in content.get("prompts", []):
		prompts[str(p["id"])] = p
	var levels: Dictionary = content.get("levels", {})
	for pid in levels.get(difficulty, levels.get("toddler", [])):
		if prompts.has(str(pid)):
			pool.append(str(pid))
	if pool.is_empty():
		pool = prompts.keys()


func num(key: String, fallback := 0.0) -> float:
	return float(settings.get(key, fallback))


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func start() -> void:
	super.start()
	_build_ui()
	GameManager.mascot.play("wave_hello")
	var intro := str(content.get("intro_line", ""))
	if intro != "":
		await AudioDirector.say(intro, Settings.prompt_langs(0))
	if st == St.DONE or not is_inside_tree():
		return
	_next_round()


func _build_ui() -> void:
	var ui: Control = GameManager.game_ui
	# Corner widgets grow INTO the screen (left / up) from their anchor, or they hang off the edge.
	_ring = ProgressRingScript.new()
	_ring.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	ui.add_child(_ring)
	_ring.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_ring.offset_left = -_ring.custom_minimum_size.x
	_ring.offset_right = 0.0
	_dots = RoundDotsScript.new()
	_dots.refresh(int(num("rounds", 10)), results, 0)
	_dots.grow_vertical = Control.GROW_DIRECTION_BEGIN
	ui.add_child(_dots)
	_dots.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_dots.offset_top = -_dots.custom_minimum_size.y
	_dots.offset_bottom = 0.0


# ---- rounds --------------------------------------------------------------------

func _draw_prompt() -> Dictionary:
	if _bag.is_empty():
		_bag = pool.duplicate()
		_bag.shuffle()
		if _bag.size() > 1 and _bag[-1] == _last_id:
			var tmp = _bag[0]
			_bag[0] = _bag[-1]
			_bag[-1] = tmp
	var pid: String = _bag.pop_back()
	_last_id = pid
	return prompts[pid]


func _next_round() -> void:
	if finish_requested or round_idx >= int(num("rounds", 10)):
		_finish_game()
		return
	round_idx += 1
	attempt = 1
	prompt = _draw_prompt()
	_intro()


func _intro() -> void:
	st = St.INTRO
	st_time = 0.0
	armed = false
	listen_time = 0.0
	listen_elapsed = 0.0
	prompt_started = _now()
	GameManager.mascot.stop_demo()
	GameManager.mascot.go_home()
	_show_prompt_card()
	_dots.refresh(int(num("rounds", 10)), results, round_idx)
	_ring.value = 0.0
	AudioDirector.say(str(prompt["line"]), Settings.prompt_langs(round_idx - 1), true)


func _show_prompt_card() -> void:
	_hide_prompt_card()
	var rows := UiKit.prompt_rows(str(prompt["line"]), Settings.display_langs(round_idx - 1))
	_card = UiKit.side_card(GameManager.game_ui, rows)


func _hide_prompt_card() -> void:
	if _card != null and is_instance_valid(_card):
		_card.queue_free()
	_card = null


func _process(delta: float) -> void:
	if paused or st == St.IDLE or st == St.DONE:
		return
	st_time += delta
	match st:
		St.INTRO:
			if st_time >= num("intro_arm_s", 1.0):
				st = St.LISTEN
				st_time = 0.0
				VisionClient.mock_expect(str(prompt["check"]))   # only the mock server acts on this
		St.LISTEN, St.HINT:
			_listen(delta)
		St.CELEBRATE:
			if st_time >= num("celebrate_s", 2.5) and not AudioDirector.is_speaking():
				_next_round()


func _is_on(gname: String) -> bool:
	return str(gstate.get(gname, "end")) != "end"


func _listen(delta: float) -> void:
	var now := _now()
	listen_elapsed += delta
	if not armed and (_is_on("neutral") or listen_elapsed >= num("rearm_gap_s", 1.5)):
		armed = true
		armed_at = now
	var target := str(prompt["check"])
	var frac := 0.0
	if armed:
		var gs := str(gstate.get(target, "end"))
		if gs == "held" and now - armed_at >= num("armed_settle_s", 0.2):
			_success()
			return
		if gs == "start":
			frac = clampf((now - float(gstart.get(target, now))) / maxf(num("hold_fill_s", 0.25), 0.01), 0.0, 0.95)
		elif gs == "held":
			frac = 0.95
	_ring.value = frac
	if not AudioDirector.is_speaking():
		listen_time += delta
	if listen_time >= num("prompt_timeout_s", 8.0):
		if attempt <= int(num("hint_attempts", 1)):
			attempt += 1
			listen_time = 0.0
			_hint()
		else:
			_record("timeout", -1.0)
			GameManager.mascot.stop_demo()
			AudioDirector.encourage(Settings.prompt_langs(round_idx - 1))
			_next_round()


func _hint() -> void:
	st = St.HINT
	GameManager.mascot.go_spotlight()
	GameManager.mascot.demo(str(prompt.get("demo", prompt["check"])))
	var langs := Settings.prompt_langs(round_idx - 1)
	AudioDirector.hint(game_id, langs)
	AudioDirector.say(str(prompt["line"]), langs, false)


func _success() -> void:
	st = St.CELEBRATE
	st_time = 0.0
	armed = false
	successes += 1
	_record("success", _now() - prompt_started)
	_ring.value = 1.0
	_hide_prompt_card()
	GameManager.mascot.stop_demo()
	GameManager.mascot.go_home()
	GameManager.mascot.play("cheer")
	AudioDirector.stop_voice()
	AudioDirector.sfx("success")
	var langs := Settings.word_langs(round_idx - 1)
	var rows: Array = []
	for lang in langs:
		rows.append([ContentDB.text(str(prompt["word"]), str(lang)), str(lang)])
	GameManager.praise.show_word(rows, num("celebrate_s", 2.5))
	var view := get_viewport_rect().size
	GameManager.praise.burst(Vector2(view.x / 2.0, view.y * 0.45), 90)
	if not VisionClient.active_people.is_empty():
		var b: Array = VisionClient.active_people[0].get("bbox", [0.4, 0.2, 0.6, 0.9])
		var center := Vector2((float(b[0]) + float(b[2])) / 2.0, (float(b[1]) + float(b[3])) / 2.0)
		GameManager.praise.burst(VisionClient.to_screen(center, view), 40, 600.0)
	AudioDirector.praise(Settings.prompt_langs(round_idx - 1))
	AudioDirector.say(str(prompt["word"]), langs)


func _record(result: String, time_to_success: float) -> void:
	results.append(result)
	var ev := {"round": round_idx, "prompt": str(prompt.get("id", "")), "result": result,
		"attempt": attempt, "language_mode": Settings.language_mode}
	if time_to_success >= 0.0:
		ev["time_to_success_s"] = snappedf(time_to_success, 0.01)
	events.append(ev)
	Stats.record_round(game_id, ev)
	_dots.refresh(int(num("rounds", 10)), results, round_idx)


func _finish_game() -> void:
	st = St.DONE
	_hide_prompt_card()
	GameManager.mascot.stop_demo()
	finish({"game": game_id, "rounds": round_idx, "successes": successes, "results": results, "events": events})


# ---- BaseGame hooks ------------------------------------------------------------

func on_gesture(_player: int, gname: String, state: String, _conf: float) -> void:
	gstate[gname] = state
	if state == "start":
		gstart[gname] = _now()


func skip() -> void:
	if st in [St.INTRO, St.LISTEN, St.HINT]:
		_record("skipped", -1.0)
		AudioDirector.stop_voice()
		_next_round()
	elif st == St.CELEBRATE:
		AudioDirector.stop_voice()
		_next_round()


func repeat_prompt() -> void:
	if not paused and st in [St.INTRO, St.LISTEN, St.HINT]:
		AudioDirector.stop_voice()
		_intro()


func pause() -> void:
	super.pause()
	GameManager.mascot.stop_demo()


func resume() -> void:
	super.resume()
	if st in [St.INTRO, St.LISTEN, St.HINT]:
		_intro()    # say the same prompt again
