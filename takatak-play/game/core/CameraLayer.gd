extends Node2D
## Camera feed, full screen, cover-scaled. The frame arrives pre-mirrored.
## Modes: mirror (feed), cutout (P6: feed × person mask over art; falls back to mirror),
## hidden (background only).

var mode := "mirror"
var dim := 0.0
var background := Color(0.07, 0.09, 0.19)
var _tex: Texture2D = null


func _ready() -> void:
	VisionClient.frame_received.connect(_on_frame)
	get_viewport().size_changed.connect(queue_redraw)


func _on_frame(tex: Texture2D) -> void:
	_tex = tex
	queue_redraw()


func set_mode(m: String) -> void:
	mode = m
	queue_redraw()


func _draw() -> void:
	var view := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, view), background)
	if mode != "hidden" and _tex != null and VisionClient.is_open:
		draw_texture_rect(_tex, VisionClient.cover_rect(view), false)
	if dim > 0.0:
		draw_rect(Rect2(Vector2.ZERO, view), Color(0, 0, 0, dim))
