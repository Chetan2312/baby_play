extends Node
## Scenes, games and vision routing. Two modes:
##   session    (default) SessionDirector runs the anganwadi session; this file loads the
##              games it asks for (run_game), routes vision signals, pauses when the
##              children leave, and reports game_done.
##   free_play  "Choose a game": children pick a game by holding a hand on its card
##              (GamePicker). The first card, "Today's session", starts the session.
## Start screen (centre profile "landing"): picker (default) or session (idle screen).
##
## Dev-build keys: X skip round · L language mode · K primary language · T toddler/kid ·
## C camera · S skeleton · D debug · F2 Devanagari test · Ctrl+Q quit.
## Worker buttons (start/next/repeat/stop) come through InputRouter, not here.

signal game_done(result: Dictionary)

enum Phase { BOOT, IDLE, PLAYING, PAUSED, DEVA }

const UiKit = preload("res://core/UiKit.gd")
const SupervisorScript = preload("res://scenes/Supervisor.gd")
const GAME_SCENES := {
	"simon_says": "res://games/simon_says/SimonSays.tscn",
	"bubble_pop": "res://games/bubble_pop/BubblePop.tscn",
}
const PICKER_SCENE := "res://scenes/GamePicker.tscn"
const SESSION_CARD := "session"   # picker card that starts the fixed session
const DEVA_SCENE := "res://scenes/DevaTest.tscn"

var phase := Phase.BOOT
var mode := "session"         # session | free_play
# set by Main via attach()
var main: Node = null
var camera_layer = null
var game_root: Node2D = null
var game_ui: Control = null
var avatar = null
var mascot = null
var praise = null
var overlay = null
var supervisor_layer: Control = null

var current = null            # current scene node (idle / picker / game)
var current_game = null       # current BaseGame, or null
var current_game_id := ""
var _game_ended := false      # current_game already reported finished
var present_since := -1.0
var absent_since := 0.0
var _pause_card: Control = null
var _phase_before_deva := Phase.IDLE
var _supervisor: Control = null
var _last_picked := ""
var _last_level := ""


func attach(main_node: Node, parts: Dictionary) -> void:
	main = main_node
	camera_layer = parts["camera"]
	game_root = parts["game_root"]
	game_ui = parts["game_ui"]
	avatar = parts["avatar"]
	mascot = parts["mascot"]
	praise = parts["praise"]
	overlay = parts["overlay"]
	supervisor_layer = parts["supervisor"]
	VisionClient.pose_updated.connect(_on_pose)
	VisionClient.gesture.connect(_on_gesture)
	VisionClient.motion.connect(_on_motion)
	VisionClient.loudness.connect(_on_loudness)
	VisionClient.no_player.connect(_on_no_player)
	VisionClient.connected_changed.connect(_on_connected)


func boot() -> void:
	VisionClient.set_players("single")
	VisionClient.set_difficulty(Settings.difficulty)
	if Settings.camera != "":
		VisionClient.set_camera(Settings.camera)
	if Settings.deva_test:
		show_deva_test()
	elif Settings.free_play:
		enter_free_play()
	else:
		go_home()


## The start screen: the game picker, or the session's idle screen (centre profile "landing").
func go_home() -> void:
	if landing_picker():
		enter_free_play()
	else:
		mode = "session"
		SessionDirector.go_idle()


func landing_picker() -> bool:
	return str(Centre.value("landing")) == "picker"


func now_s() -> float:
	return Time.get_ticks_msec() / 1000.0


func s(key: String) -> float:
	return float(ContentDB.session.get(key, ContentDB.SESSION_DEFAULTS.get(key, 0.0)))


# ---- scene switching -----------------------------------------------------------

func _clear_current() -> void:
	if current_game != null and current_game.finished.is_connected(_on_game_finished):
		current_game.finished.disconnect(_on_game_finished)
	if current != null and is_instance_valid(current):
		current.queue_free()
	current = null
	current_game = null
	current_game_id = ""
	_game_ended = false
	for c in game_ui.get_children():
		c.queue_free()
	_pause_card = null
	praise.clear()
	AudioDirector.stop_voice()


func _spawn(path: String):
	var scene = load(path)
	if scene == null:
		overlay.toast("Missing scene: " + path)
		return null
	var node = scene.instantiate()
	game_root.add_child(node)
	current = node
	return node


## Empty screen (camera mirror + mascot) for SessionDirector's mascot lines.
func clear_screen() -> void:
	stop_game()
	_clear_current()
	phase = Phase.IDLE
	camera_layer.set_mode("mirror")
	VisionClient.subscribe(true)


## Non-game scene (idle screen) → its root node.
func show_scene(path: String):
	clear_screen()
	return _spawn(path)


func has_game(game_id: String) -> bool:
	return GAME_SCENES.has(game_id) and not ContentDB.game(game_id).is_empty()


## Session mode: load and start a game. extra (pack, step …) is merged into setup().
## → false if the game isn't available (SessionDirector then plays its fallback).
func run_game(game_id: String, extra := {}) -> bool:
	stop_game()
	_clear_current()
	if not has_game(game_id):
		return false
	var g = _spawn(GAME_SCENES[game_id])
	if g == null:
		return false
	current_game = g
	current_game_id = game_id
	g.finished.connect(_on_game_finished)
	var cfg := {"difficulty": Settings.difficulty, "content": ContentDB.game(game_id)}
	cfg.merge(extra)
	g.setup(cfg)
	VisionClient.subscribe(g.needs_frames, g.needs_mask, g.needs_mic, Array(g.motions))
	VisionClient.set_difficulty(Settings.difficulty)
	camera_layer.set_mode(g.camera_mode)
	mascot.go_home()
	phase = Phase.PLAYING
	g.start()
	return true


## Stop the current game now (next / stop / supervisor). Counts the time played.
func stop_game() -> void:
	if current_game != null and is_instance_valid(current_game) and not _game_ended:
		_game_ended = true
		Stats.end_game(current_game_id, {"duration_s": current_game.duration_s(),
			"movement": current_game.movement, "stopped": true})
	if phase in [Phase.PLAYING, Phase.PAUSED] and mode == "session":
		phase = Phase.IDLE


func request_game_finish() -> void:
	if current_game != null and is_instance_valid(current_game) and not _game_ended:
		current_game.request_finish()


func repeat_prompt() -> void:
	if current_game != null and is_instance_valid(current_game) and phase == Phase.PLAYING:
		current_game.repeat_prompt()


func _on_game_finished(result: Dictionary) -> void:
	_game_ended = true
	Stats.end_game(current_game_id, result)
	if mode == "session":
		phase = Phase.IDLE
		game_done.emit(result)
		return
	show_picker.call_deferred()   # free play: back to "Choose a game"


# ---- free play: "Choose a game" picker (supervisor menu) ---------------------------

## Free-play games count rounds and movement minutes, not sessions (no daily cap).
func enter_free_play() -> void:
	mode = "free_play"
	show_picker()


func exit_free_play() -> void:
	stop_game()
	mode = "session"
	go_home()


func show_picker() -> void:
	if mode != "free_play":
		return
	var picker = show_scene(PICKER_SCENE)
	if picker != null:
		picker.setup_picker([SESSION_CARD] + game_ids(), _last_picked, _last_level)


## Picker cards for the built games, in GAME_SCENES order. A game with a "picker" list
## in its content gets one card per entry: "<game>@<pack>" (Fruit bubbles, Number bubbles).
func game_ids() -> Array:
	var out: Array = []
	for gid in GAME_SCENES:
		if not has_game(gid):
			continue
		var entries: Array = ContentDB.game(gid).get("picker", [])
		if entries.is_empty():
			out.append(gid)
		for e in entries:
			out.append("%s@%s" % [gid, str(e.get("pack", ""))])
	return out


## Levels a picker card offers (easy / medium / hard), [] = start straight away.
func card_levels(card: String) -> Array:
	var levels = ContentDB.game(card.get_slice("@", 0)).get("levels", {})
	if levels is Dictionary and not levels.is_empty() and levels.values()[0] is Dictionary:
		return levels.keys()
	return []


## Picker → start a game. "<game>@<pack>" picks the pack, otherwise this week's pack
## (the game falls back to its default pack). level: from the picker's level page.
func pick_game(card: String, level := "") -> void:
	_last_picked = card
	if level != "":
		_last_level = level
	if card == SESSION_CARD:
		mode = "session"
		SessionDirector.start()
		return
	var gid := card.get_slice("@", 0)
	var pack := card.get_slice("@", 1) if card.contains("@") else ""
	if pack == "":
		var packs: Array = ContentDB.week(Centre.week()).get("packs", [])
		pack = str(packs[0]) if not packs.is_empty() else ""
	if not run_game(gid, {"pack": pack, "level": level}):
		overlay.toast("Game not available: " + gid)
		show_picker()


## InputRouter actions while in free play.
func free_play_action(action_name: String) -> void:
	if phase in [Phase.PLAYING, Phase.PAUSED]:
		match action_name:
			"next", "select":
				if phase == Phase.PAUSED:
					_resume()
				elif current_game != null:
					current_game.skip()
			"prev":
				repeat_prompt()
			"back", "long":
				stop_game()
				show_picker()
		return
	if current != null and is_instance_valid(current) and current.has_method("on_action"):
		current.on_action(action_name)   # the picker: move / start / back


# ---- supervisor menu -------------------------------------------------------------

func open_supervisor() -> void:
	if _supervisor != null and is_instance_valid(_supervisor):
		return
	if mode == "free_play":   # closing the menu goes home again
		stop_game()
		mode = "session"
	AudioDirector.stop_voice()
	_supervisor = SupervisorScript.new()
	supervisor_layer.add_child(_supervisor)
	_supervisor.closed.connect(_on_supervisor_closed)
	InputRouter.push_handler(_supervisor)


func _on_supervisor_closed(next: String) -> void:
	if _supervisor != null:
		InputRouter.pop_handler(_supervisor)
		_supervisor.queue_free()
		_supervisor = null
	if next == "free_play":
		enter_free_play()
	else:
		go_home()


func supervisor_open() -> bool:
	return _supervisor != null and is_instance_valid(_supervisor)


# ---- presence / pause ----------------------------------------------------------

func _process(_delta: float) -> void:
	var now := now_s()
	var present := not VisionClient.active_people.is_empty()
	if present:
		if present_since < 0.0:
			present_since = now
		absent_since = -1.0
	else:
		present_since = -1.0
		if absent_since < 0.0:
			absent_since = now
	var present_for := now - present_since if present_since >= 0.0 else 0.0
	var absent_for := now - absent_since if absent_since >= 0.0 else 0.0

	match phase:
		Phase.PLAYING:
			if not present and absent_for >= s("pause_after_s"):
				_pause()
		Phase.PAUSED:
			if present_for >= s("resume_detect_s"):
				_resume()
			elif absent_for >= s("abandon_s"):
				if mode == "free_play":
					stop_game()
					show_picker()
				else:
					_resume_card_only()
					SessionDirector.on_abandon()

	if mascot != null and present:
		var nose := VisionClient.kp(VisionClient.active_people[0], "nose")
		if nose.z > 0.3:
			mascot.look_at_point(VisionClient.to_screen(Vector2(nose.x, nose.y), main.get_viewport().get_visible_rect().size))


func _pause() -> void:
	phase = Phase.PAUSED
	if current_game != null:
		current_game.pause()
	AudioDirector.stop_voice()
	mascot.go_spotlight()
	mascot.play("wave_hello", 3.0)
	# the children have left: the centre is free, and the side column holds the game's prompt
	var card := UiKit.card(UiKit.line_rows("callback_01", Settings.ordered_langs(), 80))
	_pause_card = UiKit.center(game_ui, card)
	AudioDirector.say(AudioDirector.pick_line("callback"), Settings.prompt_langs(0), true)


func _resume_card_only() -> void:
	if _pause_card != null and is_instance_valid(_pause_card):
		_pause_card.queue_free()
	_pause_card = null


func _resume() -> void:
	phase = Phase.PLAYING
	_resume_card_only()
	AudioDirector.stop_voice()
	mascot.go_home()
	mascot.play("cheer", 1.2)
	if current_game != null:
		current_game.resume()


# ---- vision routing ------------------------------------------------------------

func _on_pose(people: Array) -> void:
	if phase == Phase.PLAYING and current_game != null:
		current_game.on_pose(people)


func _on_gesture(player: int, gname: String, state: String, conf: float) -> void:
	if phase == Phase.PLAYING and current_game != null:
		current_game.on_gesture(player, gname, state, conf)


func _on_motion(player: int, mname: String, conf: float, count: int) -> void:
	if phase == Phase.PLAYING and current_game != null:
		current_game.on_motion(player, mname, conf, count)


func _on_loudness(db: float, speaking: bool) -> void:
	if phase == Phase.PLAYING and current_game != null:
		current_game.on_loudness(db, speaking)


func _on_no_player(seconds: float) -> void:
	if phase == Phase.PLAYING and current_game != null:
		current_game.on_no_player(seconds)


func _on_connected(connected: bool) -> void:
	if connected:
		VisionClient.set_difficulty(Settings.difficulty)


# ---- dev keys (dev builds only) ------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not Settings.is_dev():
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_Q:
			if key.ctrl_pressed:
				get_tree().quit()
		KEY_X:
			if phase == Phase.PLAYING and current_game != null:
				current_game.skip()
		KEY_L:
			overlay.toast("Language mode: " + Settings.cycle_language_mode())
		KEY_K:
			overlay.toast("Primary language: " + Settings.cycle_primary_language())
		KEY_T:
			var d := Settings.toggle_difficulty()
			VisionClient.set_difficulty(d)
			overlay.toast("Difficulty: " + d + " (next game)")
		KEY_C:
			var cam := "noir" if str(VisionClient.info.get("camera", "wide")) == "wide" else "wide"
			Settings.camera = cam
			Settings.save_settings()
			VisionClient.set_camera(cam)
			overlay.toast("Camera: " + cam)
		KEY_S:
			avatar.show_skeleton = not avatar.show_skeleton
		KEY_D:
			overlay.show_debug = not overlay.show_debug
		KEY_F2:
			if phase == Phase.DEVA:
				phase = _phase_before_deva
				go_home()
			else:
				show_deva_test()


func show_deva_test() -> void:
	_phase_before_deva = phase
	stop_game()
	_clear_current()
	phase = Phase.DEVA
	_spawn(DEVA_SCENE)
