extends Node
## Session flow: Attract → greeting → games (playlist) → Finish → Attract.
## Loads games, subscribes vision data from each game's export flags, routes
## vision signals to the current game, pauses when the child leaves.
##
## Tester keys: Space skip · L language mode · K primary language · T toddler/kid ·
## C camera · S skeleton · D debug · F2 Devanagari test · Esc quit

enum Phase { BOOT, ATTRACT, GREETING, PLAYING, PAUSED, FINISH, DEVA }

const UiKit = preload("res://core/UiKit.gd")
const GAME_SCENES := {
	"simon_says": "res://games/simon_says/SimonSays.tscn",
}
const ATTRACT_SCENE := "res://scenes/Attract.tscn"
const FINISH_SCENE := "res://scenes/Finish.tscn"
const DEVA_SCENE := "res://scenes/DevaTest.tscn"

var phase := Phase.BOOT
# set by Main via attach()
var main: Node = null
var camera_layer = null
var game_root: Node2D = null
var game_ui: Control = null
var avatar = null
var mascot = null
var praise = null
var overlay = null

var current = null            # current scene node (attract / game / finish)
var current_game = null       # current BaseGame, or null
var current_game_id := ""
var playlist_idx := 0
var session_started_ms := 0
var session_results: Array = []
var present_since := -1.0
var absent_since := 0.0
var _pause_card: Control = null
var _phase_before_deva := Phase.ATTRACT


func attach(main_node: Node, parts: Dictionary) -> void:
	main = main_node
	camera_layer = parts["camera"]
	game_root = parts["game_root"]
	game_ui = parts["game_ui"]
	avatar = parts["avatar"]
	mascot = parts["mascot"]
	praise = parts["praise"]
	overlay = parts["overlay"]
	VisionClient.pose_updated.connect(_on_pose)
	VisionClient.gesture.connect(_on_gesture)
	VisionClient.motion.connect(_on_motion)
	VisionClient.loudness.connect(_on_loudness)
	VisionClient.no_player.connect(_on_no_player)
	VisionClient.connected_changed.connect(_on_connected)


func boot() -> void:
	VisionClient.set_players("single")
	VisionClient.set_difficulty(Settings.difficulty)
	VisionClient.set_camera(Settings.camera)
	if Settings.deva_test:
		show_deva_test()
	else:
		go_attract()


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


func go_attract() -> void:
	_clear_current()
	phase = Phase.ATTRACT
	camera_layer.set_mode("mirror")
	VisionClient.subscribe(true)
	mascot.go_home()
	_spawn(ATTRACT_SCENE)


func start_session() -> void:
	if phase == Phase.GREETING or phase == Phase.PLAYING:
		return
	_clear_current()
	phase = Phase.GREETING
	session_started_ms = Time.get_ticks_msec()
	session_results = []
	playlist_idx = 0
	Stats.start_session({"difficulty": Settings.difficulty, "language_mode": Settings.language_mode,
		"primary_language": Settings.primary_language,
		"camera": str(VisionClient.info.get("camera", "?"))})
	AudioDirector.sfx("start")
	mascot.go_spotlight()
	mascot.play("wave_hello")
	praise.burst(Vector2(game_ui.size.x / 2.0, game_ui.size.y / 3.0), 50, 700.0)
	var card := UiKit.card(UiKit.line_rows("greeting_01", Settings.ordered_langs(), 100))
	UiKit.top_center(game_ui, card)
	await AudioDirector.say("greeting_01", Settings.prompt_langs(0), true)
	if phase != Phase.GREETING:
		return
	_load_game(Settings.playlist[0])


func _load_game(game_id: String) -> void:
	_clear_current()
	var path: String = GAME_SCENES.get(game_id, "")
	if path == "" or ContentDB.game(game_id).is_empty():
		overlay.toast("Game not available: " + game_id)
		_finish()
		return
	var g = _spawn(path)
	if g == null:
		_finish()
		return
	current_game = g
	current_game_id = game_id
	g.finished.connect(_on_game_finished)
	g.setup({"difficulty": Settings.difficulty, "content": ContentDB.game(game_id)})
	VisionClient.subscribe(g.needs_frames, g.needs_mask, g.needs_mic, Array(g.motions))
	VisionClient.set_difficulty(Settings.difficulty)
	camera_layer.set_mode(g.camera_mode)
	mascot.go_home()
	phase = Phase.PLAYING
	g.start()


func _on_game_finished(result: Dictionary) -> void:
	Stats.end_game(current_game_id, result)
	session_results.append(result)
	playlist_idx += 1
	if playlist_idx < Settings.playlist.size() and not _session_over():
		_load_game(Settings.playlist[playlist_idx])
	else:
		_finish()


func _session_over() -> bool:
	return (Time.get_ticks_msec() - session_started_ms) / 60000.0 >= Settings.session_minutes


func _finish() -> void:
	_clear_current()
	phase = Phase.FINISH
	var stars := 0
	for r in session_results:
		stars += int(r.get("successes", 0))
	Stats.end_session({"stars": stars, "games": session_results.size()})
	var f = _spawn(FINISH_SCENE)
	if f != null:
		f.setup_finish(stars)


func end_session_to_attract() -> void:
	if phase in [Phase.GREETING, Phase.PLAYING, Phase.PAUSED]:
		Stats.end_session({"abandoned": true})
	go_attract()


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
		Phase.ATTRACT:
			if present_for >= s("attract_detect_s"):
				start_session()
		Phase.PLAYING:
			if not present and absent_for >= s("pause_after_s"):
				_pause()
		Phase.PAUSED:
			if present_for >= s("resume_detect_s"):
				_resume()
			elif absent_for >= s("abandon_s"):
				end_session_to_attract()

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
	var card := UiKit.card(UiKit.line_rows("callback_01", Settings.ordered_langs(), 90))
	_pause_card = UiKit.center(game_ui, card)
	AudioDirector.say(AudioDirector.pick_line("callback"), Settings.prompt_langs(0), true)


func _resume() -> void:
	phase = Phase.PLAYING
	if _pause_card != null and is_instance_valid(_pause_card):
		_pause_card.queue_free()
	_pause_card = null
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


# ---- tester keys ---------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_ESCAPE:
			get_tree().quit()
		KEY_SPACE:
			match phase:
				Phase.ATTRACT:
					start_session()
				Phase.PLAYING:
					if current_game != null:
						current_game.skip()
				Phase.PAUSED:
					_resume()
				Phase.FINISH:
					go_attract()
		KEY_L:
			overlay.toast("Language mode: " + Settings.cycle_language_mode())
		KEY_K:
			overlay.toast("Primary language: " + Settings.cycle_primary_language())
		KEY_T:
			var d := Settings.toggle_difficulty()
			VisionClient.set_difficulty(d)
			overlay.toast("Difficulty: " + d + " (next game)")
		KEY_C:
			var cam := "noir" if str(VisionClient.info.get("camera", Settings.camera)) == "wide" else "wide"
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
				go_attract()
			else:
				show_deva_test()


func show_deva_test() -> void:
	_phase_before_deva = phase
	_clear_current()
	phase = Phase.DEVA
	_spawn(DEVA_SCENE)
