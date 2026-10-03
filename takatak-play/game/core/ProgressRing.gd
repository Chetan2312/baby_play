extends Control
## Hold-progress ring (0..1). No failure colours: empty is just dim.

var value := 0.0:
	set(v):
		value = clampf(v, 0.0, 1.0)
		queue_redraw()


func _init() -> void:
	custom_minimum_size = Vector2(170, 170)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var c := size / 2.0
	var r := minf(size.x, size.y) / 2.0 - 14.0
	draw_circle(c, r + 12.0, Color(0, 0, 0, 0.45))
	draw_arc(c, r, 0.0, TAU, 64, Color(0.5, 0.5, 0.65, 0.6), 10.0, true)
	if value > 0.0:
		draw_arc(c, r, -PI / 2.0, -PI / 2.0 + TAU * value, 64, Color(1.0, 0.8, 0.16), 18.0, true)
