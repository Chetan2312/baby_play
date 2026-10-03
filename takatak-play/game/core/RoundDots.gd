extends Control
## Round progress: gold star per success, soft dot for moved-on rounds, ring for current.

const UiKit = preload("res://core/UiKit.gd")

var total := 10
var results: Array = []       # "success" | "timeout" | "skipped"
var current := 0              # 1-based current round, 0 = none


func _init() -> void:
	custom_minimum_size = Vector2(600, 60)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func refresh(t: int, res: Array, cur: int) -> void:
	total = t
	results = res
	current = cur
	custom_minimum_size = Vector2(total * 50 + 20, 60)
	queue_redraw()


func _draw() -> void:
	for i in total:
		var c := Vector2(30 + i * 50, size.y / 2.0)
		if i < results.size():
			if results[i] == "success":
				draw_colored_polygon(UiKit.star_points(c, 22.0), UiKit.GOLD)
			else:
				draw_circle(c, 10.0, Color(0.8, 0.8, 0.88))
		elif i == current - 1:
			draw_arc(c, 15.0, 0.0, TAU, 32, Color.WHITE, 5.0, true)
		else:
			draw_circle(c, 7.0, Color(0.5, 0.5, 0.62))
