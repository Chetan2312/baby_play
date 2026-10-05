extends Node
## The self-running anganwadi session (content/sessions/<id>.yaml, picked by the centre
## profile): one "start" press → greet → warm-up → this week's theme → talk-back →
## cool-down → goodbye → idle "see you tomorrow" screen. Ends by itself.
##
## Worker buttons (InputRouter): next = start / skip to the next step · prev = repeat the
## prompt · back / long press = stop (goodbye line, then idle) · supervisor = menu.
## Daily cap (max_sessions_per_day / max_minutes_per_day): start shows the mascot resting.
##
## Game steps run for their minutes × (session_minutes / total_minutes). A game that
## finishes early starts again while ≥ RESTART_MIN_S of the step is left. A game that
## isn't built yet plays the session's fallback_game (content_lint lists them).

enum St { IDLE, RUNNING }

const UiKit = preload("res://core/UiKit.gd")
const IDLE_SCENE := "res://scenes/Idle.tscn"
const RESTART_MIN_S := 45.0
const FORCE_AFTER_S := 60.0     # game ignored request_finish this long → stop it
const OVERRUN_S := 120.0        # past session_minutes by this much → straight to goodbye

var st := St.IDLE
var session: Dictionary = {}
var steps: Array = []
var step_idx := -1
var step: Dictionary = {}
var segments: Array = []        # current game step: [{game, seconds, pack}]
var seg_idx := -1
var seg_deadline := 0.0
var seg_finish_requested := false
var _in_bridge := false        # bridge line before a game step: next skips only the line
var started_at := 0.0
var _gen := 0                   # bumped on every transition; stale awaits compare it


func _ready() -> void:
	InputRouter.push_handler(self)
	GameManager.game_done.connect(_on_game_done)


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func state_name() -> String:
	if st == St.IDLE:
		return "idle"
	return "%s (%d/%d)" % [str(step.get("id", "?")), step_idx + 1, steps.size()]


# ---- idle ----------------------------------------------------------------------

## variant: ready (boot) | tomorrow (after a session) | rest (daily cap reached)
func go_idle(variant := "ready") -> void:
	st = St.IDLE
	_gen += 1
	segments = []
	var idle = GameManager.show_scene(IDLE_SCENE)
	if idle != null:
		idle.setup_idle(variant)


# ---- buttons -------------------------------------------------------------------

func on_action(action_name: String) -> void:
	if action_name == "supervisor":
		open_supervisor()
		return
	if GameManager.mode == "free_play":
		GameManager.free_play_action(action_name)
		return
	match action_name:
		"next", "select":
			if st == St.IDLE:
				start()
			else:
				next_step()
		"prev":
			if st == St.RUNNING:
				repeat()
		"back", "long":
			if st == St.RUNNING:
				stop()


func open_supervisor() -> void:
	if st == St.RUNNING:   # quietly end the session; it still counts
		_gen += 1
		segments = []
		GameManager.stop_game()
		Stats.end_session()
		st = St.IDLE
	GameManager.open_supervisor()


# ---- session -------------------------------------------------------------------

func start() -> void:
	if st == St.RUNNING:
		return
	if Stats.cap_reached(Centre.int_value("max_sessions_per_day"), Centre.int_value("max_minutes_per_day")):
		print("[session] daily cap reached")
		go_idle("rest")
		return
	session = ContentDB.session_def(str(Centre.value("session")))
	if session.is_empty():
		GameManager.overlay.toast("Session '%s' not found: ./run.sh content" % str(Centre.value("session")))
		return
	steps = session.get("steps", [])
	st = St.RUNNING
	started_at = _now()
	step_idx = -1
	print("[session] start %s, %d min, week %d" % [str(session.get("id")), int(Settings.session_minutes), Centre.week()])
	Stats.start_session()
	AudioDirector.sfx("start")
	_advance()


func _scale() -> float:
	var total := float(session.get("total_minutes", Settings.session_minutes))
	return Settings.session_minutes / total if total > 0.0 else 1.0


func _is_game(st_: Dictionary) -> bool:
	return str(st_.get("type", "game")) == "game"


func _goodbye_index() -> int:
	for i in range(steps.size() - 1, -1, -1):
		if str(steps[i].get("then", "")) == "end_session":
			return i
	return -1


func _advance() -> void:
	_gen += 1
	var gen := _gen
	segments = []
	_in_bridge = false
	step_idx += 1
	var bye := _goodbye_index()
	if bye > step_idx and _now() - started_at > Settings.session_minutes * 60.0 + OVERRUN_S:
		step_idx = bye
	if step_idx >= steps.size():
		_end()
		return
	var prev: Dictionary = steps[step_idx - 1] if step_idx > 0 else {}
	step = steps[step_idx]
	print("[session] step ", step.get("id", "?"))
	if not _is_game(step):
		await _say_line(str(step.get("line", "")), gen, str(step.get("then", "")) == "end_session")
		if gen != _gen:
			return
		Stats.step_completed(str(step.get("id", "")))
		if str(step.get("then", "")) == "end_session":
			_end()
		else:
			_advance()
		return
	if not prev.is_empty() and _is_game(prev):
		_in_bridge = true
		await _bridge(gen)
		if gen != _gen:
			return
		_in_bridge = false
	_start_game_step()


## Mascot line on an empty screen; returns when it has been spoken (or skipped).
func _say_line(line_id: String, gen: int, goodbye := false) -> void:
	GameManager.clear_screen()
	var m = GameManager.mascot
	m.go_spotlight()
	m.play("wave_bye" if goodbye else "wave_hello", 3.0)
	UiKit.top_center(GameManager.game_ui, UiKit.card(UiKit.line_rows(line_id, Settings.ordered_langs(), 96)))
	if goodbye:
		GameManager.praise.rain(120)
	else:
		GameManager.praise.burst(Vector2(GameManager.game_ui.size.x / 2.0, GameManager.game_ui.size.y / 3.0), 50, 700.0)
	await AudioDirector.say(line_id, Settings.prompt_langs(0))
	if gen == _gen:
		await get_tree().create_timer(0.6).timeout


func _bridge(gen: int) -> void:
	var prefix := str(session.get("bridge_prefix", ""))
	var lid := AudioDirector.pick_line("transition", prefix) if prefix != "" else ""
	if lid == "" or not lid.begins_with(prefix):
		return
	await _say_line(lid, gen)


func _resolve_game(game_id: String) -> String:
	if GameManager.has_game(game_id):
		return game_id
	var fb := str(session.get("fallback_game", "simon_says"))
	print("[session] game '%s' not built yet → %s" % [game_id, fb])
	return fb


func _start_game_step() -> void:
	var ids: Array = []
	var packs: Array = []
	if str(step.get("game", "")) == "from_week":
		var w := ContentDB.week(Centre.week())
		ids = w.get("games", [])
		packs = w.get("packs", [])
	else:
		ids = [str(step.get("game", ""))]
		if step.has("pack"):
			packs = [str(step["pack"])]
	var resolved: Array = []
	for gid in ids:
		var r := _resolve_game(str(gid))
		if resolved.is_empty() or resolved[-1] != r:   # two missing games → one fallback, not two
			resolved.append(r)
	if resolved.is_empty():
		resolved = [_resolve_game("")]
	var secs := float(step.get("minutes", 3)) * 60.0 * _scale()
	segments = []
	for i in resolved.size():
		segments.append({"game": resolved[i], "seconds": secs / resolved.size(),
			"pack": str(packs[mini(i, packs.size() - 1)]) if not packs.is_empty() else ""})
	seg_idx = -1
	_next_segment()


func _next_segment() -> void:
	seg_idx += 1
	if seg_idx >= segments.size():
		Stats.step_completed(str(step.get("id", "")))
		_advance()
		return
	seg_deadline = _now() + float(segments[seg_idx]["seconds"])
	_launch()


func _launch() -> void:
	seg_finish_requested = false
	var seg: Dictionary = segments[seg_idx]
	if not GameManager.run_game(str(seg["game"]), {"pack": seg["pack"], "step": str(step.get("id", ""))}):
		GameManager.overlay.toast("Game not available: " + str(seg["game"]))
		_next_segment.call_deferred()


func _process(_delta: float) -> void:
	if st != St.RUNNING or seg_idx < 0 or seg_idx >= segments.size():
		return
	var now := _now()
	if not seg_finish_requested and now >= seg_deadline:
		seg_finish_requested = true
		GameManager.request_game_finish()
	elif seg_finish_requested and now >= seg_deadline + FORCE_AFTER_S:
		GameManager.stop_game()
		_next_segment()


func _on_game_done(_result: Dictionary) -> void:
	if st != St.RUNNING or seg_idx < 0 or seg_idx >= segments.size():
		return
	if not seg_finish_requested and seg_deadline - _now() >= RESTART_MIN_S:
		_launch()      # finished early: play again until the step's time is up
	else:
		_next_segment()


func next_step() -> void:
	if st != St.RUNNING:
		return
	AudioDirector.stop_voice()
	if _in_bridge:
		_in_bridge = false
		_gen += 1
		_start_game_step()
		return
	GameManager.stop_game()
	_advance()


func repeat() -> void:
	if not segments.is_empty():
		GameManager.repeat_prompt()
	else:            # mascot line: say it again
		step_idx -= 1
		AudioDirector.stop_voice()
		_advance()


## Stop: skip to the goodbye line, then idle.
func stop() -> void:
	if st != St.RUNNING:
		return
	var bye := _goodbye_index()
	if bye < 0 or step_idx >= bye:
		_end()
		return
	AudioDirector.stop_voice()
	GameManager.stop_game()
	step_idx = bye - 1
	_advance()


## GameManager: the children left during a game and didn't come back.
func on_abandon() -> void:
	print("[session] children gone → goodbye")
	stop()


func _end() -> void:
	if st != St.RUNNING:
		return
	GameManager.stop_game()
	Stats.end_session()
	print("[session] end after %.1f min" % ((_now() - started_at) / 60.0))
	go_idle("tomorrow")
