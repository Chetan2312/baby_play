extends Control
## Supervisor menu: hold stop (B) 5 s, or the GPIO button 5 s, then enter the 4-digit PIN
## (centre profile supervisor_pin) with the remote. Plain, large, high-contrast;
## Marathi + English. Changes are saved to the device (Centre.gd).
##
## Buttons: next/prev = move (PIN: change digit) · select/long = OK · back = back/close.

signal closed(next: String)   # "" → idle screen · "free_play" → old free-play flow

enum Page { PIN, MENU, USAGE, PRIVACY, STATUS }

const UiKit = preload("res://core/UiKit.gd")
const BG := Color(0.03, 0.04, 0.09)
const FG := Color(1, 1, 1)
const DIM := Color(0.72, 0.75, 0.85)
const HI := Color(1.0, 0.82, 0.2)
const ITEMS := [
	{"id": "landing", "key": "item_landing", "kind": "cycle", "values": ["picker", "session"]},
	{"id": "week", "key": "item_week", "kind": "cycle"},
	{"id": "language_mode", "key": "item_language_mode", "kind": "cycle", "values": ["mr_first", "all_three", "single"]},
	{"id": "primary_language", "key": "item_primary_language", "kind": "cycle", "values": ["mr", "hi", "en"]},
	{"id": "difficulty", "key": "item_difficulty", "kind": "cycle", "values": ["toddler", "kid"]},
	{"id": "session_minutes", "key": "item_session_minutes", "kind": "cycle", "values": [12, 14, 16, 18, 20]},
	{"id": "slots", "key": "item_slots", "kind": "cycle", "values": [1, 2, 3, 4], "not_built": true},
	{"id": "ai_literacy_enabled", "key": "item_ai_literacy", "kind": "cycle", "values": [true, false], "not_built": true},
	{"id": "cap_override", "key": "item_cap_override", "kind": "action"},
	{"id": "usage", "key": "item_usage", "kind": "page"},
	{"id": "export", "key": "item_export", "kind": "action"},
	{"id": "privacy", "key": "item_privacy", "kind": "page"},
	{"id": "status", "key": "item_status", "kind": "page"},
	{"id": "camera_rotation", "key": "item_camera_rotation", "kind": "cycle", "values": ["normal", "right", "inverted", "left"]},
	{"id": "free_play", "key": "item_free_play", "kind": "action"},
	{"id": "exit", "key": "item_exit", "kind": "action"},
]
const ROWS_VISIBLE := 8

var page := Page.PIN
var sel := 0
var pin: Array = [0, 0, 0, 0]
var pin_pos := 0
var _body: VBoxContainer
var _help: Label
var _msg: Label
var _msg_until := 0.0
var _refresh_t := 0.0


func _ready() -> void:
	UiKit.full_rect(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = BG
	UiKit.full_rect(bg)
	add_child(bg)
	var margin := MarginContainer.new()
	UiKit.full_rect(margin)
	var v := get_viewport_rect().size
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, int(v.x * 0.07))
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, int(v.y * 0.06))
	add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	margin.add_child(col)
	var title := UiKit.label(UiKit.ui_both("sup_title"), 56, HI)
	col.add_child(title)
	col.add_child(UiKit.label(str(Centre.value("centre_name")), 30, DIM))
	_body = VBoxContainer.new()
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 10)
	col.add_child(_body)
	_msg = UiKit.label("", 40, HI)
	col.add_child(_msg)
	_help = UiKit.label("", 28, DIM)
	col.add_child(_help)
	_render()


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _flash(key: String) -> void:
	_msg.text = UiKit.ui_both(key)
	_msg_until = _now() + 3.0


func _process(delta: float) -> void:
	_msg.visible = _now() < _msg_until
	if page == Page.STATUS or page == Page.USAGE:
		_refresh_t += delta
		if _refresh_t >= 1.0:
			_refresh_t = 0.0
			_render()


# ---- buttons -------------------------------------------------------------------

func on_action(a: String) -> void:
	match page:
		Page.PIN:
			_pin_action(a)
		Page.MENU:
			match a:
				"next":
					sel = (sel + 1) % ITEMS.size()
				"prev":
					sel = (sel - 1 + ITEMS.size()) % ITEMS.size()
				"select", "long":
					_activate(ITEMS[sel])
				"back":
					closed.emit("")
					return
		_:
			if a in ["back", "select", "long"]:
				page = Page.MENU
	_render()


func _pin_action(a: String) -> void:
	match a:
		"next":
			pin[pin_pos] = (int(pin[pin_pos]) + 1) % 10
		"prev":
			pin[pin_pos] = (int(pin[pin_pos]) + 9) % 10
		"select", "long":
			pin_pos += 1
			if pin_pos >= 4:
				var entered := "".join(PackedStringArray(pin.map(func(d): return str(d))))
				if entered == str(Centre.value("supervisor_pin")):
					page = Page.MENU
				else:
					_flash("pin_wrong")
				pin = [0, 0, 0, 0]
				pin_pos = 0
		"back":
			closed.emit("")


func _activate(item: Dictionary) -> void:
	match str(item["kind"]):
		"cycle":
			_cycle(item)
		"page":
			match str(item["id"]):
				"usage":
					page = Page.USAGE
				"privacy":
					page = Page.PRIVACY
				"status":
					page = Page.STATUS
		"action":
			match str(item["id"]):
				"cap_override":
					Stats.override_cap_today()
					_flash("cap_lifted")
				"export":
					var p := Stats.export_csv_to_usb()
					_flash("export_ok" if p != "" else "export_no_usb")
					if p != "":
						print("[usage] exported to ", p)
				"free_play":
					closed.emit("free_play")
				"exit":
					closed.emit("")


func _cycle(item: Dictionary) -> void:
	var id := str(item["id"])
	var values: Array = ContentDB.week_numbers() if id == "week" else item["values"]
	if values.is_empty():
		return
	var key := "current_week" if id == "week" else id
	var cur = Centre.value(key)
	var i := values.find(cur)
	Centre.set_value(key, values[(i + 1) % values.size()])
	VisionClient.set_difficulty(Settings.difficulty)
	if id == "camera_rotation":
		VisionClient.set_rotation(str(Centre.value(id)))


# ---- rendering -----------------------------------------------------------------

func _clear_body() -> void:
	for c in _body.get_children():
		c.queue_free()


func _row(text: String, size := 40, color := FG, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := UiKit.label(text, size, color, 4)
	l.horizontal_alignment = align
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(l)
	return l


func _render() -> void:
	_clear_body()
	match page:
		Page.PIN:
			_render_pin()
		Page.MENU:
			_render_menu()
		Page.USAGE:
			_render_usage()
		Page.PRIVACY:
			_render_privacy()
		Page.STATUS:
			_render_status()


func _render_pin() -> void:
	_row(UiKit.ui_both("pin_title"), 48, FG, HORIZONTAL_ALIGNMENT_CENTER)
	var boxes := PackedStringArray()
	for i in 4:
		if i < pin_pos:
			boxes.append("•")
		elif i == pin_pos:
			boxes.append("[%d]" % int(pin[i]))
		else:
			boxes.append("_")
	_row("   ".join(boxes), 96, HI, HORIZONTAL_ALIGNMENT_CENTER)
	_help.text = UiKit.ui_both("pin_help")


func _value_text(item: Dictionary) -> String:
	var id := str(item["id"])
	match id:
		"week":
			var w := ContentDB.week(Centre.week())
			var t: Dictionary = w.get("title", {})
			return "%d · %s / %s" % [Centre.week(), str(t.get("mr", "")), str(t.get("en", ""))]
		"language_mode", "difficulty", "landing":
			return UiKit.ui_both("val_" + str(Centre.value(id)))
		"camera_rotation":
			return UiKit.ui_both("val_rot_" + str(Centre.value(id)))
		"primary_language":
			return UiKit.ui_both("lang_" + str(Centre.value(id)))
		"session_minutes", "slots":
			var s := str(Centre.value(id))
			return s + ("  " + UiKit.ui_both("val_not_built") if item.get("not_built", false) else "")
		"ai_literacy_enabled":
			var on := UiKit.ui_both("val_on" if bool(Centre.value(id)) else "val_off")
			return on + "  " + UiKit.ui_both("val_not_built")
	return ""


func _render_menu() -> void:
	var first := clampi(sel - ROWS_VISIBLE / 2, 0, maxi(0, ITEMS.size() - ROWS_VISIBLE))
	for i in range(first, mini(first + ROWS_VISIBLE, ITEMS.size())):
		var item: Dictionary = ITEMS[i]
		var text := ("▶ " if i == sel else "   ") + UiKit.ui_both(str(item["key"]))
		var val := _value_text(item)
		if val != "":
			text += "  ‹ " + val + " ›"
		elif item["kind"] == "page":
			text += "  ›"
		_row(text, 40 if i == sel else 36, HI if i == sel else FG)
	_help.text = UiKit.ui_both("sup_help")


func _render_usage() -> void:
	_row(UiKit.ui_both("usage_title"), 48, HI)
	for pair in [["usage_today", Stats.day_totals()], ["usage_month", Stats.month_totals()]]:
		var t: Dictionary = pair[1]
		_row(UiKit.ui_both(pair[0]) + (" (" + Stats.today() + ")" if pair[0] == "usage_today" else ""), 38, FG)
		_row("   %s: %d    %s: %.0f    %s: %.0f" % [UiKit.ui_both("usage_sessions"), t["sessions"],
			UiKit.ui_both("usage_minutes"), t["minutes"], UiKit.ui_both("usage_movement"), t["movement_minutes"]], 32, DIM)
		_row("   %s: %d    %s: %d" % [UiKit.ui_both("usage_rounds"), t["rounds"],
			UiKit.ui_both("usage_successes"), t["successes"]], 32, DIM)
	_row(UiKit.ui_both("usage_note"), 32, FG)
	_help.text = UiKit.ui_both("back_hint")


func _render_privacy() -> void:
	_row(UiKit.ui_both("privacy_title"), 48, HI, HORIZONTAL_ALIGNMENT_CENTER)
	for i in 4:
		var key := "privacy_%d" % (i + 1)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 28)
		var icon := PrivacyIcon.new()
		icon.kind = i
		icon.custom_minimum_size = Vector2(110, 110)
		h.add_child(icon)
		var texts := VBoxContainer.new()
		texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for r in [[ContentDB.ui_text(key, "mr"), 42, FG], [ContentDB.ui_text(key, "en"), 30, DIM]]:
			var l := UiKit.label(str(r[0]), int(r[1]), r[2], 4)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			texts.add_child(l)
		h.add_child(texts)
		_body.add_child(h)
	_help.text = UiKit.ui_both("back_hint")


func status_lines() -> Array:
	var hw: Dictionary = VisionClient.hardware
	var st: Dictionary = VisionClient.last_status
	var lines: Array = []
	lines.append("Build: %s · content %s" % [Settings.build, ContentDB.content_version])
	if not VisionClient.is_open:
		lines.append("Vision service: NOT CONNECTED")
	var accel := str(hw.get("accelerator", "-"))
	var want := str(hw.get("accelerator_expected", "-"))
	lines.append("Profile: %s · accelerator %s (expected %s) %s" % [str(hw.get("profile", "?")), accel, want,
		"OK" if accel == want else "!!"])
	lines.append("Camera: %s · detected %s · rotation %s" % [str(VisionClient.info.get("camera", "?")),
		", ".join(PackedStringArray(hw.get("cameras", []))), str(VisionClient.last_status.get("rotation", "?"))])
	lines.append("Microphone: %s · audio %s" % ["OK" if hw.get("mic", false) else "not found",
		", ".join(PackedStringArray(hw.get("audio", [])))])
	var scr := DisplayServer.screen_get_size()
	var vis := get_viewport().get_visible_rect().size
	lines.append("Display: %dx%d (view %dx%d)" % [scr.x, scr.y, vis.x, vis.y])
	lines.append("Temperature: %s °C · fps %s" % [str(st.get("temp_c", "?")), str(st.get("fps", {}))])
	var clock := Time.get_datetime_string_from_system().replace("T", " ") if Stats.clock_ok() \
		else UiKit.ui_both("clock_unknown") + " (RTC battery?)"
	lines.append("Clock: " + clock)
	var net := str(hw.get("network", "unknown"))
	lines.append("Network: " + (UiKit.ui_both("net_" + net) if net in ["offline", "online"] else net))
	lines.append("Model: %s" % str(hw.get("model", "?")))
	var d := DirAccess.open(Stats.dir)
	var free_gb := d.get_space_left() / 1073741824.0 if d != null else -1.0
	lines.append("Free disk: %.1f GB · usage in %s" % [free_gb, Stats.dir])
	var faults: Array = Stats.day_entry().get("faults", [])
	var ftxt := PackedStringArray()
	for f in faults:
		ftxt.append("%s×%d" % [str(f.get("name", "")), int(f.get("count", 0))])
	lines.append("Faults today: " + (", ".join(ftxt) if not ftxt.is_empty() else "none"))
	for e in st.get("errors", hw.get("errors", [])):
		lines.append("!! " + str(e))
	return lines


func _render_status() -> void:
	_row(UiKit.ui_both("status_title"), 46, HI)
	for line in status_lines():
		_row(str(line), 28, Color(1.0, 0.75, 0.6) if str(line).begins_with("!!") else FG)
	_help.text = UiKit.ui_both("back_hint")


## Simple drawn icons for the privacy screen: 0 camera sees dots · 1 nothing saved ·
## 2 no internet · 3 counts only.
class PrivacyIcon extends Control:
	var kind := 0

	func _draw() -> void:
		var s := size
		var c := s / 2.0
		var r := minf(s.x, s.y) * 0.42
		var w := Color(1, 1, 1)
		var red := Color(1.0, 0.4, 0.35)
		var gold := Color(1.0, 0.82, 0.2)
		match kind:
			0:   # camera + stick figure dots
				draw_rect(Rect2(c - Vector2(r, r * 0.65), Vector2(r * 2, r * 1.3)), w, false, 5.0)
				draw_circle(c, r * 0.35, w, false, 5.0)
				for p in [Vector2(0, -0.2), Vector2(-0.12, 0.0), Vector2(0.12, 0.0), Vector2(0, 0.15)]:
					draw_circle(c + p * r, 5.0, gold)
			1:   # disk with a cross
				draw_rect(Rect2(c - Vector2(r * 0.8, r), Vector2(r * 1.6, r * 2)), w, false, 5.0)
				draw_rect(Rect2(c - Vector2(r * 0.45, r), Vector2(r * 0.9, r * 0.6)), w, false, 4.0)
				draw_line(c - Vector2(r, r), c + Vector2(r, r), red, 8.0)
			2:   # globe with a cross
				draw_circle(c, r, w, false, 5.0)
				draw_line(c - Vector2(r, 0), c + Vector2(r, 0), w, 3.0)
				draw_arc(c, r * 0.5, -PI / 2, PI / 2, 24, w, 3.0)
				draw_arc(c, r * 0.5, PI / 2, PI * 1.5, 24, w, 3.0)
				draw_line(c - Vector2(r, r), c + Vector2(r, r), red, 8.0)
			3:   # bar chart
				for i in 3:
					var h := r * (0.6 + 0.5 * i)
					draw_rect(Rect2(Vector2(c.x - r + i * r * 0.75, c.y + r - h), Vector2(r * 0.5, h)), gold)
				draw_line(Vector2(c.x - r, c.y + r), Vector2(c.x + r, c.y + r), w, 4.0)
