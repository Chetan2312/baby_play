extends Node2D
## Finish: trophy, the star count, confetti, "Great job!". No failure language.

const UiKit = preload("res://core/UiKit.gd")

var stars := 0
var _t := 0.0
var _done := false


func setup_finish(n: int) -> void:
	stars = n
	var rows := UiKit.line_rows("finish_01", Settings.ordered_langs(), 84)
	rows.insert(0, ["★ %d" % stars, 140, UiKit.GOLD])
	UiKit.bottom_center(GameManager.game_ui, UiKit.card(rows))
	GameManager.praise.rain(140)
	GameManager.mascot.go_spotlight()
	GameManager.mascot.play("big_cheer", 3.0)
	AudioDirector.sfx("success")
	_sequence()


func _sequence() -> void:
	await AudioDirector.say("finish_01", Settings.prompt_langs(0), true)
	if not is_inside_tree():
		return
	await get_tree().create_timer(1.0).timeout
	if not is_inside_tree():
		return
	GameManager.mascot.play("wave_bye")
	await AudioDirector.say("goodbye_01", Settings.prompt_langs(0), true)


func _process(delta: float) -> void:
	_t += delta
	if randf() < 0.25:
		GameManager.praise.rain(2)
	if not _done and _t >= GameManager.s("finish_s") and not AudioDirector.is_speaking():
		_done = true
		GameManager.go_attract()
	queue_redraw()


func _draw() -> void:
	var view := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, view), Color(0, 0, 0, 0.35))
	var s := view.y / 1080.0 * (1.3 + 0.03 * sin(_t * 3.0))
	var c := Vector2(view.x / 2.0, view.y * 0.3)
	var gold := UiKit.GOLD
	for side in [-1, 1]:
		draw_arc(c + Vector2(side * 120, -60) * s, 50 * s, 0, TAU, 32, gold, 16 * s, true)
	var cup := PackedVector2Array([c + Vector2(-110, -120) * s, c + Vector2(110, -120) * s,
		c + Vector2(85, 10) * s, c + Vector2(30, 50) * s, c + Vector2(-30, 50) * s, c + Vector2(-85, 10) * s])
	draw_colored_polygon(cup, gold)
	draw_rect(Rect2(c + Vector2(-18, 45) * s, Vector2(36, 60) * s), gold)
	draw_rect(Rect2(c + Vector2(-80, 100) * s, Vector2(160, 40) * s), Color(0.78, 0.55, 0.08))
	draw_colored_polygon(UiKit.star_points(c + Vector2(0, -50) * s, 45 * s), Color.WHITE)
