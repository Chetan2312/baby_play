extends Node2D
## Celebration layer: star bursts, confetti rain, and the learned word in 3 scripts.

const UiKit = preload("res://core/UiKit.gd")
const COLORS := [Color(1.0, 0.8, 0.16), Color(1.0, 0.43, 0.7), Color(0.35, 0.78, 1.0),
	Color(0.47, 0.9, 0.47), Color(1.0, 0.6, 0.24), Color(1, 1, 1)]
const MAX_PARTICLES := 900

var _parts: Array = []        # [pos, vel, life, size, color, rot, spin]
var _word_box: Control = null
var _word_tween: Tween = null


func burst(at: Vector2, n := 80, speed := 900.0) -> void:
	var u := get_viewport_rect().size.y / 1080.0
	for i in n:
		if _parts.size() >= MAX_PARTICLES:
			break
		var a := randf() * TAU
		var v := Vector2(cos(a), sin(a)) * randf_range(0.3, 1.0) * speed * u + Vector2(0, -300 * u)
		_parts.append([at, v, randf_range(1.2, 2.2), randf_range(18, 40) * u, COLORS.pick_random(),
			randf() * TAU, randf_range(-4, 4)])


func rain(n := 120) -> void:
	var view := get_viewport_rect().size
	var u := view.y / 1080.0
	for i in n:
		if _parts.size() >= MAX_PARTICLES:
			break
		_parts.append([Vector2(randf() * view.x, -40 - randf() * 300), Vector2(randf_range(-60, 60), randf_range(150, 400)) * u,
			4.0, randf_range(14, 30) * u, COLORS.pick_random(), randf() * TAU, randf_range(-3, 3)])


## rows: [[text, lang], ...]; first row is the biggest
func show_word(rows: Array, seconds := 2.5) -> void:
	hide_word()
	var view := get_viewport_rect().size
	var u := view.y / 1080.0
	# top-left side column (same place as the prompt it replaces), centre stays on the child
	var w := view.x * UiKit.SIDE_FRAC
	var card_rows: Array = []
	for i in rows.size():
		card_rows.append([str(rows[i][0]), int((96 if i == 0 else 60) * u), UiKit.lang_color(str(rows[i][1]))])
	var box := VBoxContainer.new()
	box.position = Vector2(view.x * 0.05, view.y * 0.05)   # TV-safe margin
	box.custom_minimum_size.x = w
	box.pivot_offset = Vector2(w / 2.0, 80.0 * u)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(UiKit.card(card_rows, 0.45, w))
	add_child(box)
	_word_box = box
	box.scale = Vector2(0.6, 0.6)
	box.modulate.a = 0.0
	_word_tween = create_tween()
	_word_tween.set_parallel(true)
	_word_tween.tween_property(box, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_word_tween.tween_property(box, "modulate:a", 1.0, 0.2)
	_word_tween.chain().tween_interval(seconds)
	_word_tween.chain().tween_property(box, "modulate:a", 0.0, 0.3)
	_word_tween.chain().tween_callback(box.queue_free)


func hide_word() -> void:
	if _word_tween != null:
		_word_tween.kill()
		_word_tween = null
	if _word_box != null and is_instance_valid(_word_box):
		_word_box.queue_free()
	_word_box = null


func clear() -> void:
	_parts.clear()
	hide_word()


func _process(delta: float) -> void:
	if _parts.is_empty():
		return
	var g := 900.0 * get_viewport_rect().size.y / 1080.0
	var alive: Array = []
	for p in _parts:
		p[0] += p[1] * delta
		p[1].y += g * delta
		p[2] -= delta
		p[5] += p[6] * delta
		if p[2] > 0.0:
			alive.append(p)
	_parts = alive
	queue_redraw()


func _draw() -> void:
	for p in _parts:
		var r: float = float(p[3]) * minf(1.0, float(p[2]) * 2.0)
		if r > 2.0:
			draw_colored_polygon(UiKit.star_points(p[0], r, float(p[5])), p[4])
