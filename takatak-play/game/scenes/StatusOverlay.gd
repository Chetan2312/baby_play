extends Control
## Top-most overlay: friendly "getting ready…" while vision isn't connected,
## tester-facing errors, short toasts, and the D debug line.

const UiKit = preload("res://core/UiKit.gd")

var show_debug := false
var _ready_box: Control = null
var _toast: Label = null
var _toast_until := 0.0
var _debug: Label = null
var _errors: Label = null
var _frames_last := 0
var _frames_t := 0.0
var _feed_fps := 0.0


func _ready() -> void:
	UiKit.full_rect(self)
	show_debug = Settings.show_debug
	_debug = UiKit.label("", 26, Color.WHITE, 6)
	_debug.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_debug.position = Vector2(16, 10)
	add_child(_debug)
	_errors = UiKit.label("", 28, Color(1.0, 0.8, 0.6), 6)
	_errors.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	add_child(_errors)
	_toast = UiKit.label("", 40, Color.WHITE, 8)
	add_child(_toast)
	VisionClient.connected_changed.connect(func(_c: bool) -> void: _update_ready())
	_update_ready()


func toast(text: String, seconds := 2.5) -> void:
	print("[toast] ", text)
	_toast.text = text
	_toast_until = Time.get_ticks_msec() / 1000.0 + seconds


func _update_ready() -> void:
	var need := not VisionClient.is_open
	if need and _ready_box == null:
		var rows: Array = []
		if ContentDB.has_line("ready_01"):
			rows = UiKit.line_rows("ready_01", Settings.ordered_langs(), 80)
		else:
			rows = [["Getting ready…", 80, Color.WHITE]]
		if ContentDB.error != "":
			rows.append([ContentDB.error, 34, Color(1.0, 0.8, 0.6)])
		rows.append(["(waiting for vision service at %s)" % Settings.vision_url, 26, Color(0.8, 0.8, 0.9)])
		var bg := ColorRect.new()
		bg.color = Color(0.07, 0.09, 0.19, 0.92)
		UiKit.full_rect(bg)
		add_child(bg)
		move_child(bg, 0)
		UiKit.center(bg, UiKit.card(rows, 0.0))
		_ready_box = bg
	elif not need and _ready_box != null:
		_ready_box.queue_free()
		_ready_box = null


func _process(delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	_toast.visible = now < _toast_until
	if _toast.visible:
		_toast.size = Vector2(size.x, 60)
		_toast.position = Vector2(0, size.y * 0.86)
	# errors reported by the vision service (camera missing, HAT missing, ...)
	var errs: Array = VisionClient.last_status.get("errors", VisionClient.info.get("errors", []))
	_errors.text = "\n".join(PackedStringArray(errs)) if VisionClient.is_open else ""
	_errors.position = Vector2(20, size.y - 60 - 34 * errs.size())
	_frames_t += delta
	if _frames_t >= 1.0:
		_feed_fps = (VisionClient.frames_received - _frames_last) / _frames_t
		_frames_last = VisionClient.frames_received
		_frames_t = 0.0
	_debug.visible = show_debug
	if show_debug:
		var st: Dictionary = VisionClient.last_status
		_debug.text = "game %d fps · feed %.1f fps · vision %s · temp %s °C · camera %s · %s · session %s · week %d · %s/%s/%s · people %d" % [
			Engine.get_frames_per_second(), _feed_fps, str(st.get("fps", {})), str(st.get("temp_c", "?")),
			str(VisionClient.info.get("camera", "?")), GameManager.Phase.keys()[GameManager.phase],
			SessionDirector.state_name(), Centre.week(),
			Settings.difficulty, Settings.language_mode, Settings.primary_language, VisionClient.people.size()]
