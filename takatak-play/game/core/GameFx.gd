extends RefCounted
## Shared game effects: the score box and the perfect-game trophy.
## Use with:  const GameFx = preload("res://core/GameFx.gd")

const UiKit = preload("res://core/UiKit.gd")
const BAD := Color(1.0, 0.45, 0.4)


## Score: top right (small) while playing, centre (big) on the summary. Star + number;
## red below 0; the box turns red while `flash` (1 → 0) is on.
static func draw_score(ci: CanvasItem, view: Vector2, u: float, score: int, flash: float, big: bool) -> void:
	var s := (2.2 if big else 1.0) * u
	var size := Vector2(250, 112) * s
	var pos := (view - size) / 2.0 if big else Vector2(view.x * 0.95 - size.x, view.y * 0.05)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.3, 0.02, 0.02, 0.55 + 0.3 * flash) if flash > 0.0 else Color(0, 0, 0, 0.6)
	sb.set_corner_radius_all(int(24 * s))
	sb.draw(ci.get_canvas_item(), Rect2(pos, size))
	var font := UiKit.font()
	ci.draw_string(font, pos + Vector2(0, 24) * s, UiKit.ui_both("score_title"), HORIZONTAL_ALIGNMENT_CENTER, size.x,
		int(18 * s), Color(1, 1, 1, 0.75))
	ci.draw_colored_polygon(UiKit.star_points(pos + Vector2(58, 68) * s, 26.0 * s), UiKit.GOLD)
	var col := BAD if score < 0 else Color.WHITE
	ci.draw_string_outline(font, pos + Vector2(100, 90) * s, str(score), HORIZONTAL_ALIGNMENT_LEFT, -1, int(60 * s),
		int(6 * s), UiKit.OUTLINE)
	ci.draw_string(font, pos + Vector2(100, 90) * s, str(score), HORIZONTAL_ALIGNMENT_LEFT, -1, int(60 * s), col)


## Perfect game: a bobbing gold trophy and a pulsing, colour-shifting "PERFECT!". t: seconds.
static func draw_trophy(ci: CanvasItem, view: Vector2, u: float, t: float) -> void:
	var s := u * (1.15 + 0.06 * sin(t * 5.0))
	var c := Vector2(view.x / 2.0, view.y * 0.2 + sin(t * 2.5) * 8.0 * u)
	var gold := UiKit.GOLD
	for side in [-1, 1]:
		ci.draw_arc(c + Vector2(side * 95, -40) * s, 40 * s, 0, TAU, 32, gold, 13 * s, true)
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-90, -100) * s, c + Vector2(90, -100) * s,
		c + Vector2(70, 10) * s, c + Vector2(25, 45) * s, c + Vector2(-25, 45) * s, c + Vector2(-70, 10) * s]), gold)
	ci.draw_rect(Rect2(c + Vector2(-15, 40) * s, Vector2(30, 50) * s), gold)
	ci.draw_rect(Rect2(c + Vector2(-65, 88) * s, Vector2(130, 32) * s), Color(0.78, 0.55, 0.08))
	ci.draw_colored_polygon(UiKit.star_points(c + Vector2(0, -40) * s, 38 * s, t), Color.WHITE)
	var font := UiKit.font()
	var title := "%s  %s" % [ContentDB.ui_text("perfect_title", Settings.primary_language), ContentDB.ui_text("perfect_title", "en")]
	var fs := int(84 * u * (1.0 + 0.08 * sin(t * 6.0)))
	var tp := Vector2(0, view.y * 0.36)
	ci.draw_string_outline(font, tp, title, HORIZONTAL_ALIGNMENT_CENTER, view.x, fs, int(10 * u), UiKit.OUTLINE)
	ci.draw_string(font, tp, title, HORIZONTAL_ALIGNMENT_CENTER, view.x, fs, Color.from_hsv(fmod(t * 0.25, 1.0), 0.45, 1.0))
