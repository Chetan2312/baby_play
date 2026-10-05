extends Node2D
## Idle screen between sessions (no attract loop: the worker starts a session).
##   ready     boot: this week's theme, mascot waves, small "press ▶" hint for the worker
##   tomorrow  after a session: "See you tomorrow!" (the goodbye line was just spoken)
##   rest      daily cap reached: mascot says it is resting, then sleeps
## Sponsor logo (centre profile sponsor_branding) would go here only; ships as "none".

const UiKit = preload("res://core/UiKit.gd")

var variant := "ready"
var _t := 0.0


func setup_idle(v: String) -> void:
	variant = v
	var ui: Control = GameManager.game_ui
	var m = GameManager.mascot
	match variant:
		"rest":
			UiKit.top_center(ui, UiKit.card(UiKit.line_rows("session_rest", Settings.ordered_langs(), 90)))
			m.go_spotlight()
			m.play("wave_hello", 2.0)
			_rest_sequence()
		"tomorrow":
			UiKit.top_center(ui, UiKit.card(UiKit.line_rows("session_tomorrow", Settings.ordered_langs(), 96)))
			m.go_home()
			m.play("wave_bye")
		_:
			var w := ContentDB.week(Centre.week())
			var rows: Array = UiKit.ui_rows("idle_week", 40, Color(0.85, 0.88, 1.0))
			var title: Dictionary = w.get("title", {})
			var langs := Settings.ordered_langs()
			for i in langs.size():
				rows.append([str(title.get(langs[i], "")), 92 if i == 0 else 64, UiKit.lang_color(langs[i])])
			UiKit.top_center(ui, UiKit.card(rows))
			m.go_home()
			m.play("wave_hello")
	var hint := UiKit.card([["▶  " + UiKit.ui_both("idle_hint"), 34, Color(0.9, 0.9, 0.95)]], 0.4)
	UiKit.bottom_center(ui, hint)


func _rest_sequence() -> void:
	await AudioDirector.say("session_rest", Settings.prompt_langs(0))
	if is_inside_tree():
		GameManager.mascot.go_home()
		GameManager.mascot.play("sleep")


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var view := get_viewport_rect().size
	var u := view.y / 1080.0
	draw_rect(Rect2(Vector2.ZERO, view), Color(0.05, 0.07, 0.16, 0.55))
	if variant == "rest":
		for i in 3:   # drifting "z"s
			var p := Vector2(view.x * 0.82 + i * 40.0 * u, view.y * 0.45 - fmod(_t * 30.0 + i * 50.0, 150.0) * u)
			draw_string(UiKit.font(), p, "z", HORIZONTAL_ALIGNMENT_LEFT, -1, int((36 + i * 10) * u), Color(1, 1, 1, 0.7))
		return
	for i in 5:
		var p := Vector2(view.x * (0.2 + 0.15 * i), view.y * 0.62 + 18.0 * u * sin(_t * 1.5 + i))
		draw_colored_polygon(UiKit.star_points(p, 26.0 * u, _t * 0.3 + i), Color(UiKit.GOLD, 0.8))
