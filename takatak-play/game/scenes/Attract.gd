extends Node2D
## Attract loop: "Come to the magic mat!", pulsing mat, mascot waves (or sleeps when
## nobody has been around for a while). GameManager starts a session when an
## active player has been present for attract_detect_s.

const UiKit = preload("res://core/UiKit.gd")

var _t := 0.0
var _last_call := -100.0
var _last_seen := 0.0
var _sleeping := false


func _ready() -> void:
	var card := UiKit.card(UiKit.line_rows("attract_01", Settings.ordered_langs(), 80))
	UiKit.top_center(GameManager.game_ui, card)
	GameManager.mascot.play("wave_hello")
	_last_seen = _t


func _process(delta: float) -> void:
	_t += delta
	if not VisionClient.people.is_empty():
		_last_seen = _t
		if _sleeping:
			_sleeping = false
			GameManager.mascot.play("wake")
	elif not _sleeping and _t - _last_seen > GameManager.s("sleep_after_s"):
		_sleeping = true
		GameManager.mascot.play("sleep")
	# call out now and then, only if somebody is around but not on the mat yet
	if VisionClient.is_open and not _sleeping and _t - _last_call > GameManager.s("attract_repeat_s"):
		_last_call = _t
		if not VisionClient.people.is_empty() or _t < 1.0:
			AudioDirector.say("attract_01", Settings.prompt_langs(0))
	queue_redraw()


func _draw() -> void:
	var view := get_viewport_rect().size
	var u := view.y / 1080.0
	var pulse := 0.5 + 0.5 * sin(_t * 3.0)
	var c := Vector2(view.x / 2.0, view.y * 0.88)
	draw_set_transform(c, 0.0, Vector2(view.x * 0.22, view.y * 0.06))
	draw_arc(Vector2.ZERO, 1.0, 0.0, TAU, 64, Color(1.0, 0.6 + 0.3 * pulse, 0.25), 0.18, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for i in 3:
		var p := Vector2(view.x / 2.0 + (i - 1) * 140.0 * u, view.y * 0.74 + 25.0 * u * sin(_t * 4.0 + i))
		draw_colored_polygon(UiKit.star_points(p, 34.0 * u, _t), UiKit.GOLD)
