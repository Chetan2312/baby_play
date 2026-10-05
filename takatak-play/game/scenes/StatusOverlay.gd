extends Control
## Top-most overlay: friendly "getting ready…" while vision isn't connected,
## tester-facing errors, short toasts, the D debug line, and the hold ring that shows
## how long the worker button is held (2 s = stop / OK, 5 s = supervisor menu).

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
	var ring := HoldRing.new()
	ring.name = "HoldRing"
	add_child(ring)


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


## Bottom-centre ring while the worker button is held: fills to 5 s, with a mark at 2 s.
class HoldRing extends Control:
	const SHOW_AFTER_S := 0.3

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var t := InputRouter.hold_seconds()
		if t < SHOW_AFTER_S:
			return
		var u := size.y / 1080.0
		var c := Vector2(size.x / 2.0, size.y * 0.84)
		var r := 54.0 * u
		var long_s := InputRouter.LONG_S
		var sup_s := InputRouter.SUPERVISOR_HOLD_S
		draw_circle(c, r + 16.0 * u, Color(0, 0, 0, 0.55))
		draw_arc(c, r, 0.0, TAU, 64, Color(1, 1, 1, 0.25), 12.0 * u, true)
		var f := clampf(t / sup_s, 0.0, 1.0)
		var col := Color(1.0, 0.8, 0.16) if t >= long_s else Color(0.6, 0.85, 1.0)
		draw_arc(c, r, -PI / 2.0, -PI / 2.0 + TAU * f, 64, col, 12.0 * u, true)
		var mark := -PI / 2.0 + TAU * long_s / sup_s
		draw_line(c + Vector2(cos(mark), sin(mark)) * (r - 14.0 * u), c + Vector2(cos(mark), sin(mark)) * (r + 14.0 * u),
			Color.WHITE, 4.0 * u, true)
		var k := r * 0.38   # what releasing now does: ▶ next · ■ stop/OK · ☰ menu
		if t < long_s:
			draw_colored_polygon(PackedVector2Array([c + Vector2(-k * 0.7, -k), c + Vector2(k, 0), c + Vector2(-k * 0.7, k)]), Color.WHITE)
		elif t < sup_s:
			draw_rect(Rect2(c - Vector2(k, k) * 0.85, Vector2(k, k) * 1.7), Color.WHITE)
		else:
			for i in 3:
				draw_line(c + Vector2(-k, (i - 1) * k * 0.7), c + Vector2(k, (i - 1) * k * 0.7), Color.WHITE, 6.0 * u, true)
