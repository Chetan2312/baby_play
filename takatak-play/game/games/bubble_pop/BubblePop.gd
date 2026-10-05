extends "res://core/BaseGame.gd"
## Bubble Pop: bubbles rise from the bottom, each holding an item from the week's pack
## (local fruit photos, numbers १–५). The mascot asks for one item ("Pop the mango
## bubble!"); children pop bubbles with their hands. Popping the asked item counts; any
## other bubble still pops and shows its name: nothing is ever "wrong".
## pops_to_win pops of the asked item → praise + the word in 3 scripts → next round.
## Only a moving hand pops a bubble (reaching), so bubbles rising past hands resting at the
## hips don't pop by themselves.
## Timeout → hint: bubbles slow down and drift to the children's hands, then a gentle move on.
## Everything tunable lives in content/games/bubble_pop.yaml ({toddler: x, kid: y} values).
##
## Layout: prompt card + a big picture of the asked bubble in the left column, bubbles
## rise through the middle (where the children are), round dots bottom left.

const UiKit = preload("res://core/UiKit.gd")
const RoundDotsScript = preload("res://core/RoundDots.gd")

enum St { IDLE, INTRO, PLAY, HINT, CELEBRATE, DONE }

var st := St.IDLE
var st_time := 0.0
var content: Dictionary = {}
var settings: Dictionary = {}
var difficulty := "toddler"
var pack := ""
var items: Array = []
var target: Dictionary = {}
var round_idx := 0
var attempt := 1
var hits := 0                 # pops of the asked item this round
var listen_time := 0.0
var successes := 0
var results: Array = []
## bubble: {x0, x, y, r, item, phase, speed}: x/y in fractions of the view, r of its height
var bubbles: Array = []
var _floaters: Array = []     # popped item names rising and fading: {pos, text, color, t}
var _rings: Array = []        # pop rings: {pos, r, t}
var _spawn_t := 0.0
var _hand_prev: Dictionary = {}   # "player_side" → [pos, smoothed speed px/s]
var _textures: Dictionary = {}
var _circle_uv := PackedVector2Array()
var _card: Control = null
var _dots = null
var _last_target := ""
var _t := 0.0


func _init() -> void:
	game_id = "bubble_pop"
	needs_frames = true
	camera_mode = "mirror"
	for i in 40:
		var a := TAU * i / 40.0
		_circle_uv.append(Vector2(0.5 + 0.5 * cos(a), 0.5 + 0.5 * sin(a)))


func setup(cfg: Dictionary) -> void:
	super.setup(cfg)
	content = cfg.get("content", {})
	settings = content.get("settings", {})
	difficulty = str(cfg.get("difficulty", "toddler"))
	var packs: Dictionary = content.get("packs", {})
	pack = str(cfg.get("pack", ""))
	if not packs.has(pack):
		pack = str(content.get("default_pack", ""))
	if not packs.has(pack) and not packs.is_empty():
		pack = str(packs.keys()[0])
	items = packs.get(pack, [])
	for it in items:
		if it.has("image") and ContentDB.root != "":
			var p := ContentDB.root.path_join(str(it["image"]))
			if FileAccess.file_exists(p):
				var img := Image.load_from_file(p)
				if img != null:
					_textures[str(it["id"])] = ImageTexture.create_from_image(img)


## setting for the current difficulty ({toddler: x, kid: y}) or a plain value
func d(key: String, fallback = 0.0):
	var v = settings.get(key, fallback)
	if v is Dictionary:
		return v.get(difficulty, v.get("toddler", fallback))
	return v


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func start() -> void:
	super.start()
	_dots = RoundDotsScript.new()
	_dots.refresh(int(d("rounds", 8)), results, 0)
	_dots.grow_vertical = Control.GROW_DIRECTION_BEGIN
	GameManager.game_ui.add_child(_dots)
	_dots.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_dots.offset_top = -_dots.custom_minimum_size.y
	_dots.offset_bottom = 0.0
	if items.is_empty():
		push_warning("bubble_pop: no items in pack " + pack)
		finish({"game": game_id, "rounds": 0, "successes": 0, "results": []})
		return
	GameManager.mascot.play("wave_hello")
	var intro := str(content.get("intro_line", ""))
	if intro != "":
		await AudioDirector.say(intro, Settings.prompt_langs(0))
	if st == St.DONE or not is_inside_tree():
		return
	_next_round()


# ---- rounds --------------------------------------------------------------------

func _pick_target() -> Dictionary:
	var pool: Array = items.filter(func(it): return str(it["id"]) != _last_target)
	if pool.is_empty():
		pool = items
	var t: Dictionary = pool.pick_random()
	_last_target = str(t["id"])
	return t


func _next_round() -> void:
	if finish_requested or round_idx >= int(d("rounds", 8)):
		_finish_game()
		return
	round_idx += 1
	attempt = 1
	hits = 0
	target = _pick_target()
	_intro()


func _intro() -> void:
	st = St.INTRO
	st_time = 0.0
	listen_time = 0.0
	GameManager.mascot.go_home()
	GameManager.mascot.play("point")
	_show_card()
	_dots.refresh(int(d("rounds", 8)), results, round_idx)
	AudioDirector.say(str(target["line"]), Settings.prompt_langs(round_idx - 1), true)


func _show_card() -> void:
	_hide_card()
	_card = UiKit.side_card(GameManager.game_ui,
		UiKit.prompt_rows(str(target["line"]), Settings.display_langs(round_idx - 1)))


func _hide_card() -> void:
	if _card != null and is_instance_valid(_card):
		_card.queue_free()
	_card = null


func _process(delta: float) -> void:
	_t += delta
	if paused or st == St.IDLE or st == St.DONE:
		queue_redraw()
		return
	st_time += delta
	_update_bubbles(delta)
	match st:
		St.INTRO:
			if st_time >= float(d("intro_arm_s", 0.8)):
				st = St.PLAY
				VisionClient.mock_expect("hands_up")   # only the mock server acts on this
		St.PLAY, St.HINT:
			if not AudioDirector.is_speaking():
				listen_time += delta
			if listen_time >= float(d("prompt_timeout_s", 14.0)):
				listen_time = 0.0
				if attempt <= int(d("hint_attempts", 1)):
					attempt += 1
					_hint()
				else:
					_record("timeout")
					AudioDirector.encourage(Settings.prompt_langs(round_idx - 1))
					_next_round()
		St.CELEBRATE:
			if st_time >= float(d("celebrate_s", 2.2)) and not AudioDirector.is_speaking():
				_next_round()
	queue_redraw()


func _hint() -> void:
	st = St.HINT
	GameManager.mascot.go_spotlight()
	GameManager.mascot.play("point", 3.0)
	var langs := Settings.prompt_langs(round_idx - 1)
	AudioDirector.hint(game_id, langs)
	AudioDirector.say(str(target["line"]), langs, false)


func _success() -> void:
	st = St.CELEBRATE
	st_time = 0.0
	successes += 1
	_record("success")
	_hide_card()
	GameManager.mascot.go_home()
	GameManager.mascot.play("cheer")
	AudioDirector.stop_voice()
	AudioDirector.sfx("success")
	var langs := Settings.word_langs(round_idx - 1)
	var rows: Array = []
	for lang in langs:
		rows.append([ContentDB.text(str(target["word"]), str(lang)), str(lang)])
	GameManager.praise.show_word(rows, float(d("celebrate_s", 2.2)))
	AudioDirector.praise(Settings.prompt_langs(round_idx - 1))
	AudioDirector.say(str(target["word"]), langs)


func _record(result: String) -> void:
	results.append(result)
	Stats.record_round(game_id, {"round": round_idx, "item": str(target.get("id", "")), "pack": pack,
		"result": result, "attempt": attempt})
	_dots.refresh(int(d("rounds", 8)), results, round_idx)


func _finish_game() -> void:
	st = St.DONE
	_hide_card()
	bubbles.clear()
	finish({"game": game_id, "rounds": round_idx, "successes": successes, "results": results})


# ---- bubbles -------------------------------------------------------------------

func _playing() -> bool:
	return st == St.INTRO or st == St.PLAY or st == St.HINT


func _spawn() -> void:
	if target.is_empty():
		return
	var has_target := bubbles.any(func(b): return b["item"]["id"] == target["id"])
	var it: Dictionary = target
	if has_target and items.size() > 1 and randf() >= float(d("target_share", 1.0)):
		it = items.filter(func(x): return x["id"] != target["id"]).pick_random()
	var r: float = float(d("bubble_radius", 0.08)) * randf_range(0.9, 1.1)
	var xr: Array = settings.get("spawn_x", [0.22, 0.82])
	var x0 := randf_range(float(xr[0]), float(xr[1]))
	bubbles.append({"x0": x0, "x": x0, "y": 1.0 + r, "r": r, "item": it, "phase": randf() * TAU,
		"speed": float(d("rise_speed", 0.08)) * randf_range(0.85, 1.15)})


func _update_bubbles(delta: float) -> void:
	var view := get_viewport_rect().size
	if _playing():
		_spawn_t -= delta
		if _spawn_t <= 0.0 and bubbles.size() < int(d("max_bubbles", 5)):
			_spawn()
			_spawn_t = float(d("spawn_every_s", 1.0))
	var hands: Array = _moving_hands(GameManager.avatar.hands() if GameManager.avatar != null else [], delta, view)
	var reach := float(d("hand_reach", 0.5))
	var popped: Array = []
	var gone: Array = []
	for b in bubbles:
		var slow := 0.45 if st == St.HINT else 1.0
		b["y"] -= float(b["speed"]) * slow * delta
		b["phase"] += delta
		if st == St.HINT and b["item"]["id"] == target["id"] and not hands.is_empty():
			var h: Vector2 = _nearest_hand(hands, Vector2(b["x"] * view.x, b["y"] * view.y))
			var to := Vector2(h.x / view.x, h.y / view.y)
			var step := float(d("hint_drift", 0.25)) * delta
			b["x0"] = move_toward(float(b["x0"]), to.x, step)
			b["y"] = move_toward(float(b["y"]), to.y, step * 0.6)
		b["x"] = float(b["x0"]) + sin(float(b["phase"]) * 1.3) * 0.02
		var c := Vector2(b["x"] * view.x, b["y"] * view.y)
		var rpx := float(b["r"]) * view.y
		for h in hands:
			if h["moving"] and (h["pos"] as Vector2).distance_to(c) < rpx + float(h["radius"]) * reach:
				popped.append(b)
				break
		if float(b["y"]) < -float(b["r"]):
			gone.append(b)
	for b in gone:
		bubbles.erase(b)
	for b in popped:
		pop_bubble(b)
	for f in _floaters:
		f["t"] += delta
		f["pos"].y -= 70.0 * delta * view.y / 1080.0
	_floaters = _floaters.filter(func(f): return float(f["t"]) < 1.3)
	for r in _rings:
		r["t"] += delta
	_rings = _rings.filter(func(r): return float(r["t"]) < 0.4)


## hands + "moving": smoothed hand speed above min_hand_speed
func _moving_hands(hands: Array, delta: float, view: Vector2) -> Array:
	var min_speed := float(d("min_hand_speed", 0.12)) * view.y
	var seen := {}
	for h in hands:
		var key := "%s_%s" % [str(h["player"]), str(h["side"])]
		seen[key] = true
		var prev = _hand_prev.get(key, null)
		var speed := 0.0
		if prev != null and delta > 0.0:
			var raw := (h["pos"] as Vector2).distance_to(prev[0]) / delta
			speed = lerpf(float(prev[1]), raw, 0.35)
		_hand_prev[key] = [h["pos"], speed]
		h["moving"] = speed >= min_speed
	for key in _hand_prev.keys():
		if not seen.has(key):
			_hand_prev.erase(key)
	return hands


func _nearest_hand(hands: Array, p: Vector2) -> Vector2:
	var best: Vector2 = hands[0]["pos"]
	for h in hands:
		if (h["pos"] as Vector2).distance_to(p) < best.distance_to(p):
			best = h["pos"]
	return best


## Pop one bubble (hand touch). Public so tests can pop without a camera.
func pop_bubble(b: Dictionary) -> void:
	if not bubbles.has(b):
		return
	bubbles.erase(b)
	var view := get_viewport_rect().size
	var c := Vector2(b["x"] * view.x, b["y"] * view.y)
	var it: Dictionary = b["item"]
	_rings.append({"pos": c, "r": float(b["r"]) * view.y, "t": 0.0})
	_floaters.append({"pos": c, "text": ContentDB.text(str(it["word"]), Settings.primary_language),
		"color": _item_color(it).lightened(0.3), "t": 0.0})
	AudioDirector.sfx("pop")
	GameManager.praise.burst(c, 22, 420.0)
	if not _playing() or it["id"] != target["id"]:
		return
	hits += 1
	AudioDirector.sfx("sparkle")
	if hits >= int(d("pops_to_win", 2)):
		_success()
	elif not AudioDirector.is_speaking():
		AudioDirector.say(str(it["word"]), Settings.prompt_langs(round_idx - 1))


# ---- drawing -------------------------------------------------------------------

func _item_color(it: Dictionary) -> Color:
	var c: Array = it.get("color", [0.6, 0.8, 1.0])
	return Color(float(c[0]), float(c[1]), float(c[2]))


func _draw() -> void:
	var view := get_viewport_rect().size
	var u := view.y / 1080.0
	for b in bubbles:
		_draw_bubble(Vector2(b["x"] * view.x, b["y"] * view.y), float(b["r"]) * view.y, b["item"])
	for r in _rings:
		var k := float(r["t"]) / 0.4
		draw_arc(r["pos"], float(r["r"]) * (1.0 + k), 0.0, TAU, 40, Color(1, 1, 1, 1.0 - k), 6.0 * u, true)
	var font := UiKit.font()
	for f in _floaters:
		var a := 1.0 - float(f["t"]) / 1.3
		var size := int(56 * u)
		var w := 600.0 * u
		var col: Color = f["color"]
		draw_string_outline(font, f["pos"] - Vector2(w / 2.0, 0), str(f["text"]), HORIZONTAL_ALIGNMENT_CENTER, w, size,
			int(8 * u), Color(UiKit.OUTLINE, a))
		draw_string(font, f["pos"] - Vector2(w / 2.0, 0), str(f["text"]), HORIZONTAL_ALIGNMENT_CENTER, w, size,
			Color(col, a))
	# the asked bubble, big, under the prompt card: children who can't read see what to pop
	if not target.is_empty() and _playing():
		var r := view.y * 0.1
		var top := view.y * 0.33
		if _card != null and is_instance_valid(_card) and _card.get_child_count() > 0 \
				and _card.get_child(0).get_child_count() > 0:
			var panel := _card.get_child(0).get_child(0) as Control   # side column → card panel
			top = clampf(panel.get_global_rect().end.y + 20.0 * u, view.y * 0.2, view.y * 0.6)
		var c := Vector2(view.x * (0.05 + UiKit.SIDE_FRAC / 2.0), top + r)
		var pulse := 1.0 + 0.06 * sin(_t * 4.0)
		_draw_bubble(c, r * pulse, target)


func _draw_bubble(c: Vector2, r: float, it: Dictionary) -> void:
	var col := _item_color(it)
	draw_circle(c, r, Color(col, 0.25))
	var tex: Texture2D = _textures.get(str(it["id"]), null)
	if tex != null:
		var pts := PackedVector2Array()
		for uv in _circle_uv:
			pts.append(c + (uv - Vector2(0.5, 0.5)) * 2.0 * r * 0.82)
		draw_colored_polygon(pts, Color.WHITE, _circle_uv, tex)
	elif it.has("label"):
		var font := UiKit.font()
		var label := str(it["label"].get(Settings.primary_language, it["label"].get("en", "?")))
		var size := int(r * 1.05)
		draw_string_outline(font, c + Vector2(-r, r * 0.22), label, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, size,
			maxi(4, size / 10), UiKit.OUTLINE)
		draw_string(font, c + Vector2(-r, r * 0.22), label, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, size, Color.WHITE)
		var n := int(it.get("count", 0))
		for i in n:   # dots to count
			draw_circle(c + Vector2((i - (n - 1) / 2.0) * r * 0.26, r * 0.58), r * 0.09, col.lightened(0.4))
	elif str(it.get("shape", "")) == "banana":
		_draw_banana(c, r, col)
	else:
		draw_circle(c, r * 0.55, col)
	draw_arc(c, r, 0.0, TAU, 48, Color(1, 1, 1, 0.85), maxf(3.0, r * 0.06), true)
	draw_circle(c + Vector2(-r * 0.42, -r * 0.45), r * 0.13, Color(1, 1, 1, 0.65))


## Crescent between two offset arcs, tilted, brown tips.
func _draw_banana(c: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	var rot := -0.45
	var n := 18
	for i in n + 1:   # outer edge
		var t := lerpf(0.12, 0.88, float(i) / n) * PI
		pts.append(c + (Vector2(cos(t), sin(t)) * r * 0.62 + Vector2(0, -r * 0.32)).rotated(rot))
	for i in range(n, -1, -1):   # inner edge, flatter: the crescent is fat in the middle, thin at the tips
		var t := lerpf(0.12, 0.88, float(i) / n) * PI
		pts.append(c + (Vector2(cos(t), sin(t)) * r * 0.62 + Vector2(0, -r * 0.32 - r * 0.34 * sin(t))).rotated(rot))
	draw_colored_polygon(pts, col)
	draw_polyline(pts, col.darkened(0.35), maxf(2.0, r * 0.04), true)
	for t in [0.12 * PI, 0.88 * PI]:
		draw_circle(c + (Vector2(cos(t), sin(t)) * r * 0.62 + Vector2(0, -r * 0.32)).rotated(rot), r * 0.06, Color(0.4, 0.27, 0.1))


# ---- BaseGame hooks ------------------------------------------------------------

func skip() -> void:
	if _playing():
		_record("skipped")
		AudioDirector.stop_voice()
		_next_round()
	elif st == St.CELEBRATE:
		AudioDirector.stop_voice()
		_next_round()


func repeat_prompt() -> void:
	if not paused and _playing():
		AudioDirector.stop_voice()
		AudioDirector.say(str(target["line"]), Settings.prompt_langs(round_idx - 1), true)


func resume() -> void:
	super.resume()
	if _playing():
		_intro()   # say the same item again
