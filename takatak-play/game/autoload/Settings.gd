extends Node
## Persistent settings (user://settings.cfg) + command-line overrides.
## Command line (after "--"): --windowed --screen=N --content=/path --vision=ws://host:port
##   --deva-test --debug --difficulty=toddler|kid --lang=mr|hi|en --language-mode=all|single|rotate

const PATH := "user://settings.cfg"
const LANGS := ["mr", "hi", "en"]
const LANGUAGE_MODES := ["all", "single", "rotate"]
const DIFFICULTIES := ["toddler", "kid"]

var language_mode := "all"
var primary_language := "mr"
var difficulty := "toddler"
var session_minutes := 15.0
var camera := "wide"
var volume := {"Master": 0.0, "Music": -6.0, "Voice": 0.0, "SFX": -4.0, "Echo": 0.0}
var playlist: Array = ["simon_says"]

# runtime only (not saved)
var windowed := false
var screen := -1
var vision_url := "ws://127.0.0.1:8765"
var content_dir := ""
var deva_test := false
var show_debug := false


func _ready() -> void:
	load_settings()
	_parse_args()
	_apply_window()


func load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return
	language_mode = str(cf.get_value("play", "language_mode", language_mode))
	primary_language = str(cf.get_value("play", "primary_language", primary_language))
	difficulty = str(cf.get_value("play", "difficulty", difficulty))
	session_minutes = float(cf.get_value("play", "session_minutes", session_minutes))
	camera = str(cf.get_value("vision", "camera", camera))
	var vol = cf.get_value("audio", "volume", volume)
	if vol is Dictionary:
		volume.merge(vol, true)


func save_settings() -> void:
	var cf := ConfigFile.new()
	cf.set_value("play", "language_mode", language_mode)
	cf.set_value("play", "primary_language", primary_language)
	cf.set_value("play", "difficulty", difficulty)
	cf.set_value("play", "session_minutes", session_minutes)
	cf.set_value("vision", "camera", camera)
	cf.set_value("audio", "volume", volume)
	cf.save(PATH)


func _parse_args() -> void:
	var args: PackedStringArray = OS.get_cmdline_args()
	args.append_array(OS.get_cmdline_user_args())
	for i in args.size():
		var a: String = args[i]
		if a == "--windowed":
			windowed = true
		elif a == "--deva-test":
			deva_test = true
		elif a == "--debug":
			show_debug = true
		elif a.begins_with("--screen="):
			screen = int(a.get_slice("=", 1))
		elif a.begins_with("--content="):
			content_dir = a.get_slice("=", 1)
		elif a.begins_with("--vision="):
			vision_url = a.get_slice("=", 1)
		elif a.begins_with("--difficulty="):
			var d := a.get_slice("=", 1)
			if d in DIFFICULTIES:
				difficulty = d
		elif a.begins_with("--lang="):
			var l := a.get_slice("=", 1)
			if l in LANGS:
				primary_language = l
		elif a.begins_with("--language-mode="):
			var m := a.get_slice("=", 1)
			if m in LANGUAGE_MODES:
				language_mode = m


func _apply_window() -> void:
	if screen >= 0 and screen < DisplayServer.get_screen_count():
		DisplayServer.window_set_current_screen(screen)
	if windowed:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN


# ---- language helpers ------------------------------------------------------

## primary language first, then the others in LANGS order
func ordered_langs() -> Array:
	var out: Array = [primary_language]
	for l in LANGS:
		if l != primary_language:
			out.append(l)
	return out


## languages a prompt is SPOKEN in for a round
func prompt_langs(round_idx: int) -> Array:
	if language_mode == "rotate":
		var start := LANGS.find(primary_language)
		return [LANGS[(start + round_idx) % LANGS.size()]]
	return [primary_language]


## languages a prompt is SHOWN in (all mode shows every script)
func display_langs(round_idx: int) -> Array:
	if language_mode == "all":
		return ordered_langs()
	return prompt_langs(round_idx)


## languages the learned word is shown/spoken in on success
func word_langs(round_idx: int) -> Array:
	if language_mode == "all":
		return ordered_langs()
	return prompt_langs(round_idx)


func cycle_language_mode() -> String:
	var i := LANGUAGE_MODES.find(language_mode)
	language_mode = LANGUAGE_MODES[(i + 1) % LANGUAGE_MODES.size()]
	save_settings()
	return language_mode


func cycle_primary_language() -> String:
	var i := LANGS.find(primary_language)
	primary_language = LANGS[(i + 1) % LANGS.size()]
	save_settings()
	return primary_language


func toggle_difficulty() -> String:
	difficulty = "kid" if difficulty == "toddler" else "toddler"
	save_settings()
	return difficulty
