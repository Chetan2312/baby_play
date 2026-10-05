extends Node
## Persistent settings (user://settings.cfg) + the centre profile (Centre.gd) + command-line
## overrides (command line wins).
## Command line (after "--"): --windowed --screen=N --content=/path --vision=ws://host:port
##   --deva-test --debug --difficulty=toddler|kid --lang=mr|hi|en
##   --language-mode=all|all_three|single|rotate --free-play --usage-dir=/path
##
## Build: "field" (default; anganwadi kits) or "dev" (TAKATAK_BUILD=dev). A packaged field
## build has res://BUILD_FIELD and ignores the environment. Field builds: no tester keys,
## no child-name clips, vision service on localhost only.

const PATH := "user://settings.cfg"
const LANGS := ["mr", "hi", "en"]
## all: spoken in the primary language, shown in all 3 · all_three: spoken and shown in all 3
## single: one language throughout · rotate: language changes every round (dev)
const LANGUAGE_MODES := ["all", "all_three", "single", "rotate"]
const DIFFICULTIES := ["toddler", "kid"]
const LOCAL_VISION_URL := "ws://127.0.0.1:8765"

var language_mode := "all"
var primary_language := "mr"
var difficulty := "toddler"
var session_minutes := 18.0
var camera := ""              # "" = the vision service's profile default (dev C key sets it)
var volume := {"Master": 0.0, "Music": -6.0, "Voice": 0.0, "SFX": -4.0, "Echo": 0.0}
var playlist: Array = ["simon_says"]   # free-play flow only (supervisor menu)

# runtime only (not saved)
var build := "field"
var windowed := false
var screen := -1
var vision_url := LOCAL_VISION_URL
var content_dir := ""
var usage_dir := ""
var deva_test := false
var show_debug := false
var free_play := false
var _arg_overrides := {}


func _ready() -> void:
	build = _detect_build()
	load_settings()
	_parse_args()
	_apply_window()
	print("[settings] build=%s" % build)


func _detect_build() -> String:
	if FileAccess.file_exists("res://BUILD_FIELD"):
		return "field"
	var b := OS.get_environment("TAKATAK_BUILD").strip_edges().to_lower()
	return "dev" if b == "dev" else "field"


func is_field() -> bool:
	return build == "field"


func is_dev() -> bool:
	return build == "dev"


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
		elif a == "--free-play":
			free_play = true
		elif a.begins_with("--usage-dir="):
			usage_dir = a.get_slice("=", 1)
		elif a.begins_with("--vision="):
			if is_field():
				push_warning("field build: --vision ignored, the vision service is local only")
			else:
				vision_url = a.get_slice("=", 1)
		elif a.begins_with("--difficulty="):
			var d := a.get_slice("=", 1)
			if d in DIFFICULTIES:
				_arg_overrides["difficulty"] = d
		elif a.begins_with("--lang="):
			var l := a.get_slice("=", 1)
			if l in LANGS:
				_arg_overrides["primary_language"] = l
		elif a.begins_with("--language-mode="):
			var m := a.get_slice("=", 1)
			if m in LANGUAGE_MODES:
				_arg_overrides["language_mode"] = m
	_reapply_args()


func _reapply_args() -> void:
	for k in _arg_overrides:
		set(k, _arg_overrides[k])


## Centre profile (Centre.gd) → play settings. The command line still wins.
func apply_centre(p: Dictionary) -> void:
	var lang := str(p.get("primary_language", "mr"))
	primary_language = lang if lang in LANGS else "mr"
	match str(p.get("language_mode", "mr_first")):
		"all_three":
			language_mode = "all_three"
		"single":
			language_mode = "single"
		_:  # mr_first: spoken in Marathi, shown in all three scripts
			language_mode = "all"
			primary_language = "mr"
	var d := str(p.get("difficulty", difficulty))
	difficulty = d if d in DIFFICULTIES else "toddler"
	session_minutes = float(p.get("session_minutes", session_minutes))
	_reapply_args()


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
	if language_mode == "all_three":
		return ordered_langs()
	return [primary_language]


## languages a prompt is SHOWN in (all / all_three show every script)
func display_langs(round_idx: int) -> Array:
	if language_mode in ["all", "all_three"]:
		return ordered_langs()
	return prompt_langs(round_idx)


## languages the learned word is shown/spoken in on success
func word_langs(round_idx: int) -> Array:
	if language_mode in ["all", "all_three"]:
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
