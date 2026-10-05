extends "res://core/BaseGame.gd"
## Bubble Pop: bubbles rise from the bottom. The mascot asks for one item ("Pop number 1!");
## children pop bubbles by reaching with their hands. Mixed in: decoys (other items: the
## same pack and/or other packs, by level) and, from Medium on, bees that must NOT be
## popped. Score top right: +1 for the asked item, −1 for a wrong pop (decoy or bee; the
## score can go below 0) with a light red flash. pops_to_win correct pops win the round;
## a big score closes the game.
##
## Level: cfg "level" (easy | medium | hard, chosen on the picker), else the game's
## session_level for the centre's difficulty. Tunables: content/games/bubble_pop.yaml.
##
## One hand pops: each child's pointer is the RAISED hand (wrist above elbow), the higher
## one if both are up; the other hand never pops. Only the fingertip point touches (the
## pose model has no finger points: the tip sits beyond the wrist along the forearm), it
## must be moving, and a small cursor shows it.
## Timeout → hint: bubbles slow down and drift to the children's hands, then move on.
##
## Performance (Pi 5): each bubble look (rim, photo / numeral / bee) is drawn ONCE into a
## texture (SubViewport bake); per frame a bubble is a single draw_texture_rect.
## Until the bake finishes (or with no GPU, e.g. headless tests) bubbles draw as vectors.

const UiKit = preload("res://core/UiKit.gd")
const RoundDotsScript = preload("res://core/RoundDots.gd")
const BAKE_PX := 256            # baked bubble texture size
const BAKE_R := 120.0           # bubble radius inside the baked texture
const GOOD := Color(0.45, 0.95, 0.45)
const BAD := Color(1.0, 0.45, 0.4)
const HAND_BONES := [[0, 1], [1, 2], [2, 3], [3, 4], [0, 5], [5, 6], [6, 7], [7, 8], [5, 9], [9, 10],
	[10, 11], [11, 12], [9, 13], [13, 14], [14, 15], [15, 16], [13, 17], [17, 18], [18, 19], [19, 20], [0, 17]]
const PREDICT_MAX_S := 0.06     # fingertip glides ahead of the last pose by at most this
const FLASH_S := 0.45           # wrong-pop red flash
const FLASH_ALPHA := 0.22

enum St { IDLE, INTRO, PLAY, HINT, CELEBRATE, SUMMARY, DONE }

var st := St.IDLE
var st_time := 0.0
var content: Dictionary = {}
var settings: Dictionary = {}
var level := "easy"
var lvl: Dictionary = {}
var pack := ""
var items: Array = []           # this pack's items (targets come from here)
var decoys_other: Array = []    # items from the other packs
var bee: Dictionary = {}
var target: Dictionary = {}
var round_idx := 0
var attempt := 1
var hits := 0                   # correct pops this round
var correct := 0                # whole game (usage counters)
var wrong := 0
var score := 0                  # shown: correct − wrong
var _flash := 0.0               # red flash after a wrong pop, 1 → 0
var listen_time := 0.0
var successes := 0
var results: Array = []
## bubble: {x0, x, y, r, item, phase, speed}: x/y in fractions of the view, r of its height
var bubbles: Array = []
var _floaters: Array = []       # popped item names rising and fading: {pos, text, color, t}
var _rings: Array = []          # pop rings: {pos, r, t, color}
var _spawn_t := 0.0
var _tips: Dictionary = {}      # pointer key → {pos, vel (px/s), at (s, update arrival), seq, side}
var pointer_mode := "arm"       # finger (21-point hand tracking) | arm (fallback)
var _pointer_side: Dictionary = {}   # player → "l" | "r" (sticky, see pointer_switch_margin)
var _pointers: Array = []       # this frame: [{player, pos (px), moving}]
var _photos: Dictionary = {}    # item id → photo texture
var _baked: Dictionary = {}     # item id → baked bubble texture
var _circle_uv := PackedVector2Array()
var _card: Control = null
var _dots = null
var _last_target := ""
var _last_oops := -100.0
var _t := 0.0


func _init() -> void:
	game_id = "bubble_pop"
	needs_frames = true
	needs_hands = true
	camera_mode = "mirror"
	for i in 40:
		var a := TAU * i / 40.0
		_circle_uv.append(Vector2(0.5 + 0.5 * cos(a), 0.5 + 0.5 * sin(a)))


func setup(cfg: Dictionary) -> void:
	super.setup(cfg)
	content = cfg.get("content", {})
	settings = content.get("settings", {})
	var levels: Dictionary = content.get("levels", {})
	level = str(cfg.get("level", ""))
	if not levels.has(level):
		var by_dif: Dictionary = content.get("session_level", {})
		level = str(by_dif.get(str(cfg.get("difficulty", "toddler")), "easy"))
	if not levels.has(level) and not levels.is_empty():
		level = str(levels.keys()[0])
	lvl = levels.get(level, {})
	var packs: Dictionary = content.get("packs", {})
	pack = str(cfg.get("pack", ""))
	if not packs.has(pack):
		pack = str(content.get("default_pack", ""))
	if not packs.has(pack) and not packs.is_empty():
		pack = str(packs.keys()[0])
	items = packs.get(pack, [])
	for pk in packs:
		if pk != pack:
			decoys_other.append_array(packs[pk])
	bee = content.get("bee", {})
	for pk in packs:
		for it in packs[pk]:
			_load_photo(it)


func _load_photo(it: Dictionary) -> void:
	if not it.has("image") or ContentDB.root == "":
		return
	var p := ContentDB.root.path_join(str(it["image"]))
	if FileAccess.file_exists(p):
		var img := Image.load_from_file(p)
		if img != null:
			_photos[str(it["id"])] = ImageTexture.create_from_image(img)


## level value, then a shared setting
func d(key: String, fallback = 0.0):
	return lvl.get(key, settings.get(key, fallback))


func bees_on() -> bool:
	return not bee.is_empty() and float(d("bee_share", 0.0)) > 0.0


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
	_bake_all()
	GameManager.mascot.play("wave_hello")
	var intro := str(content.get("intro_line", ""))
	if intro != "":
		await AudioDirector.say(intro, Settings.prompt_langs(0))
	if bees_on() and str(content.get("bee_intro_line", "")) != "" and is_inside_tree():
		await AudioDirector.say(str(content["bee_intro_line"]), Settings.prompt_langs(0))
	var finger_line := str(content.get("finger_intro_line", ""))
	if finger_line != "" and str(d("pointer", "finger")) == "finger" and VisionClient.hands_fresh() and is_inside_tree():
		await AudioDirector.say(finger_line, Settings.prompt_langs(0))
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
		_summary()
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
	_update_effects(delta)
	if st != St.SUMMARY:
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
		St.SUMMARY:
			if st_time >= float(d("summary_s", 4.5)) and not AudioDirector.is_speaking():
				_finish_game()
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


## Final scoreboard in the centre, then finish.
func _summary() -> void:
	st = St.SUMMARY
	st_time = 0.0
	_hide_card()
	bubbles.clear()
	GameManager.mascot.go_spotlight()
	GameManager.mascot.play("big_cheer", 3.0)
	GameManager.praise.rain(90)
	AudioDirector.sfx("success")
	AudioDirector.say("bubble_well_done", Settings.prompt_langs(0))


func _record(result: String) -> void:
	results.append(result)
	Stats.record_round(game_id, {"round": round_idx, "item": str(target.get("id", "")), "pack": pack,
		"level": level, "result": result, "attempt": attempt})
	_dots.refresh(int(d("rounds", 8)), results, round_idx)


func _finish_game() -> void:
	st = St.DONE
	_hide_card()
	bubbles.clear()
	finish({"game": game_id, "rounds": round_idx, "successes": successes, "results": results,
		"correct": correct, "wrong": wrong, "score": score, "level": level, "pack": pack})


# ---- bubbles -------------------------------------------------------------------

func _playing() -> bool:
	return st == St.INTRO or st == St.PLAY or st == St.HINT


func _decoy_pool() -> Array:
	var same: Array = items.filter(func(x): return x["id"] != target["id"])
	match str(d("distractors", "all")):
		"other_packs":
			return decoys_other if not decoys_other.is_empty() else same
		"same_pack":
			return same
	return same + decoys_other


func _spawn() -> void:
	if target.is_empty():
		return
	var has_target := bubbles.any(func(b): return b["item"]["id"] == target["id"])
	var it: Dictionary = target
	var roll := randf()
	var bee_share := float(d("bee_share", 0.0)) if bees_on() else 0.0
	if has_target and roll < bee_share:
		it = bee
	elif has_target and roll >= bee_share + float(d("target_share", 0.5)):
		var pool := _decoy_pool()
		if not pool.is_empty():
			it = pool.pick_random()
	var r: float = float(d("bubble_radius", 0.08)) * randf_range(0.9, 1.1)
	var xr: Array = settings.get("spawn_x", [0.36, 0.82])
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
	_pointers = _find_pointers(delta, view)
	var hands := _pointers
	var tip_r := float(d("pointer_radius", 0.018)) * view.y
	var hinting := st == St.HINT
	var slow := 0.45 if hinting else 1.0
	var drift := float(d("hint_drift", 0.25)) * delta
	var popped: Array = []
	var i := 0
	while i < bubbles.size():
		var b: Dictionary = bubbles[i]
		b["y"] -= float(b["speed"]) * slow * delta
		b["phase"] += delta
		if hinting and b["item"]["id"] == target["id"] and not hands.is_empty():
			var h: Vector2 = _nearest_hand(hands, Vector2(b["x"] * view.x, b["y"] * view.y))
			b["x0"] = move_toward(float(b["x0"]), h.x / view.x, drift)
			b["y"] = move_toward(float(b["y"]), h.y / view.y, drift * 0.6)
		b["x"] = float(b["x0"]) + sin(float(b["phase"]) * 1.3) * 0.02
		if float(b["y"]) < -float(b["r"]):
			bubbles.remove_at(i)        # floated away
			continue
		var c := Vector2(b["x"] * view.x, b["y"] * view.y)
		var rpx := float(b["r"]) * view.y
		for h in hands:
			if h["moving"] and (h["pos"] as Vector2).distance_squared_to(c) < pow(rpx + tip_r, 2):
				popped.append(b)
				break
		i += 1
	for b in popped:
		pop_bubble(b)


func _update_effects(delta: float) -> void:
	_flash = maxf(0.0, _flash - delta / FLASH_S)
	var lift := 70.0 * delta * get_viewport_rect().size.y / 1080.0
	var n := 0
	for f in _floaters:
		f["t"] += delta
		if float(f["t"]) < 1.3:
			f["pos"].y -= lift
			_floaters[n] = f
			n += 1
	_floaters.resize(n)
	n = 0
	for r in _rings:
		r["t"] += delta
		if float(r["t"]) < 0.4:
			_rings[n] = r
			n += 1
	_rings.resize(n)


## The popping points this frame: [{player, pos (screen px), moving}], one per child.
## pointer: finger (default) → the index fingertip of a hand showing POINT (21-point hand
## tracking from the vision service); when hand tracking isn't running (not installed,
## no model) it falls back to the arm pointer. pointer: arm → always the arm pointer.
## Smoothing happens once, in the vision service (One Euro). Here the tip only glides
## between updates with its velocity, so it moves every frame.
func _find_pointers(_delta: float, view: Vector2) -> Array:
	var finger: bool = str(d("pointer", "finger")) == "finger" and VisionClient.hands_fresh()
	pointer_mode = "finger" if finger else "arm"
	var out := _finger_pointers(view) if finger else _arm_pointers(view)
	var seen := {}
	for h in out:
		seen[h["key"]] = true
	for k in _tips.keys():
		if not seen.has(k):
			_tips.erase(k)
	return out


## Index fingertips of hands showing POINT; if a child points with both, the higher one.
func _finger_pointers(view: Vector2) -> Array:
	var active := {}
	for p in VisionClient.active_people:
		active[int(p.get("id", -1))] = true
	var best := {}
	for h in VisionClient.hands:
		var pid := int(h.get("player", -1))
		if str(h.get("gesture", "")) != "point" or not active.has(pid):
			continue
		if not best.has(pid) or float(h["tip"][1]) < float(best[pid]["tip"][1]):
			best[pid] = h
	var out: Array = []
	var min_speed := float(d("min_hand_speed", 0.12)) * view.y
	var needs_motion := bool(d("finger_needs_motion", false))
	for pid in best:
		var h: Dictionary = best[pid]
		var raw := VisionClient.to_screen(Vector2(float(h["tip"][0]), float(h["tip"][1])), view)
		var tp := _glide("f%d" % pid, raw, VisionClient.hands_received, str(h["side"]))
		out.append({"player": pid, "key": "f%d" % pid, "pos": tp[0],
			"moving": (not needs_motion) or (tp[1] as Vector2).length() >= min_speed})
	return out


## Arm pointer (no finger tracking): the raised hand (wrist above elbow), the clearly
## higher one if both are up; the tip sits beyond the wrist along the forearm.
func _arm_pointers(view: Vector2) -> Array:
	var out: Array = []
	var reach := float(d("pointer_reach", 0.35))
	var margin := float(d("pointer_switch_margin", 0.06))
	var min_speed := float(d("min_hand_speed", 0.12)) * view.y
	for p in VisionClient.active_people:
		var pid := int(p.get("id", -1))
		var tips := {}
		for side in ["l", "r"]:
			var w := VisionClient.kp(p, side + "_wrist")
			var e := VisionClient.kp(p, side + "_elbow")
			if w.z >= 0.3 and e.z >= 0.3 and w.y < e.y + 0.01:   # raised: forearm pointing up/out
				tips[side] = Vector2(w.x, w.y) + (Vector2(w.x, w.y) - Vector2(e.x, e.y)) * reach
		if tips.is_empty():
			_pointer_side.erase(pid)
			continue
		var side: String = _pointer_side.get(pid, "")
		if not tips.has(side):
			side = "l" if tips.has("l") else "r"
		var other := "r" if side == "l" else "l"
		if tips.has(other) and tips[other].y < tips[side].y - margin:
			side = other            # clearly higher: it takes over
		_pointer_side[pid] = side
		var raw := VisionClient.to_screen(tips[side], view)
		var tp := _glide("a%d" % pid, raw, VisionClient.poses_received, side)
		out.append({"player": pid, "key": "a%d" % pid, "pos": tp[0], "moving": (tp[1] as Vector2).length() >= min_speed})
	return out


## Velocity glide between updates → [position now, velocity px/s]. seq: the update counter
## the raw point comes from (a new value = a new measurement).
func _glide(key: String, raw: Vector2, seq: int, side: String) -> Array:
	var now := Time.get_ticks_msec() / 1000.0
	var tp: Dictionary = _tips.get(key, {})
	if tp.is_empty() or str(tp.get("side", "")) != side:
		tp = {"pos": raw, "vel": Vector2.ZERO, "at": now, "seq": seq, "side": side}
	elif int(tp["seq"]) != seq:
		var dt := maxf(0.005, now - float(tp["at"]))
		tp["vel"] = (tp["vel"] as Vector2).lerp((raw - (tp["pos"] as Vector2)) / dt, 0.5)
		tp["pos"] = raw
		tp["at"] = now
		tp["seq"] = seq
	_tips[key] = tp
	var age := minf(now - float(tp["at"]), PREDICT_MAX_S)
	return [tp["pos"] + (tp["vel"] as Vector2) * age, tp["vel"]]


func _nearest_hand(hands: Array, p: Vector2) -> Vector2:
	var best: Vector2 = hands[0]["pos"]
	for h in hands:
		if (h["pos"] as Vector2).distance_squared_to(p) < best.distance_squared_to(p):
			best = h["pos"]
	return best


## Pop one bubble (hand touch). Public so tests can pop without a camera.
func pop_bubble(b: Dictionary) -> void:
	var idx := bubbles.find(b)
	if idx < 0:
		return
	bubbles.remove_at(idx)
	var view := get_viewport_rect().size
	var c := Vector2(b["x"] * view.x, b["y"] * view.y)
	var it: Dictionary = b["item"]
	var is_target: bool = _playing() and it["id"] == target["id"]
	var col := GOOD if is_target else BAD
	_rings.append({"pos": c, "r": float(b["r"]) * view.y, "t": 0.0, "color": col})
	_floaters.append({"pos": c, "text": ContentDB.text(str(it["word"]), Settings.primary_language),
		"color": col, "t": 0.0})
	if _playing():
		_floaters.append({"pos": c - Vector2(0, float(b["r"]) * view.y * 0.9), "text": "+1" if is_target else "−1",
			"color": col, "t": 0.0})
	if not _playing():
		AudioDirector.sfx("pop")
		return
	if is_target:
		correct += 1
		score += 1
		hits += 1
		AudioDirector.sfx("pop")
		AudioDirector.sfx("sparkle")
		GameManager.praise.burst(c, 14, 420.0)
		if hits >= int(d("pops_to_win", 2)):
			_success()
		elif not AudioDirector.is_speaking():
			AudioDirector.say(str(it["word"]), Settings.prompt_langs(round_idx - 1))
		return
	wrong += 1
	score -= 1
	_flash = 1.0
	AudioDirector.sfx("try_again")
	if bool(it.get("avoid", false)):
		GameManager.mascot.play("surprised", 1.0)
		var line := str(content.get("bee_oops_line", ""))
		if line != "" and _t - _last_oops >= float(d("bee_oops_every_s", 8.0)) and not AudioDirector.is_speaking():
			_last_oops = _t
			AudioDirector.say(line, Settings.prompt_langs(round_idx - 1))


# ---- baking (one texture per bubble look) -----------------------------------------

func _bake_all() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var all: Array = items + decoys_other
	if not bee.is_empty():
		all.append(bee)
	var vps: Array = []
	for it in all:
		var vp := SubViewport.new()
		vp.size = Vector2i(BAKE_PX, BAKE_PX)
		vp.transparent_bg = true
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		var painter := Node2D.new()
		painter.draw.connect(_draw_bubble_on.bind(painter, Vector2(BAKE_PX, BAKE_PX) / 2.0, BAKE_R, it))
		vp.add_child(painter)
		add_child(vp)
		vps.append([vp, str(it["id"])])
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	for pair in vps:
		var vp: SubViewport = pair[0]
		if is_instance_valid(vp):
			var img := vp.get_texture().get_image()
			if img != null and not img.is_empty():
				_baked[pair[1]] = ImageTexture.create_from_image(img)
			vp.queue_free()


# ---- drawing -------------------------------------------------------------------

func _item_color(it: Dictionary) -> Color:
	var c: Array = it.get("color", [0.6, 0.8, 1.0])
	return Color(float(c[0]), float(c[1]), float(c[2]))


func _draw() -> void:
	var view := get_viewport_rect().size
	var u := view.y / 1080.0
	if _flash > 0.0:   # light, see-through red over the whole picture
		draw_rect(Rect2(Vector2.ZERO, view), Color(1.0, 0.15, 0.1, FLASH_ALPHA * _flash))
	for b in bubbles:
		_draw_bubble(Vector2(b["x"] * view.x, b["y"] * view.y), float(b["r"]) * view.y, b["item"])
	for r in _rings:
		var k := float(r["t"]) / 0.4
		draw_arc(r["pos"], float(r["r"]) * (1.0 + k), 0.0, TAU, 32, Color(r["color"], 1.0 - k), 6.0 * u)
	var font := UiKit.font()
	for f in _floaters:
		var a := 1.0 - float(f["t"]) / 1.3
		var size := int(52 * u)
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
		_draw_bubble(c, r * (1.0 + 0.06 * sin(_t * 4.0)), target)
		if bees_on():   # small "don't pop" bee with a cross over it
			var bc := c + Vector2(0, r * 1.75)
			_draw_bubble(bc, r * 0.5, bee)
			draw_line(bc + Vector2(-r, -r) * 0.45, bc + Vector2(r, r) * 0.45, BAD, 7.0 * u)
			draw_line(bc + Vector2(r, -r) * 0.45, bc + Vector2(-r, r) * 0.45, BAD, 7.0 * u)
	if _playing() and pointer_mode == "finger":   # what the machine sees: the tracked hands
		for h in VisionClient.hands:
			var kp: Array = h.get("kp", [])
			if kp.size() < 21:
				continue
			var pts := PackedVector2Array()
			for q in kp:
				pts.append(VisionClient.to_screen(Vector2(float(q[0]), float(q[1])), view))
			var pointing := str(h.get("gesture", "")) == "point"
			var col := Color(UiKit.GOLD, 0.8) if pointing else Color(1, 1, 1, 0.45)
			for c2 in HAND_BONES:
				draw_line(pts[c2[0]], pts[c2[1]], col, (4.0 if pointing else 3.0) * u)
			if pointing:   # the popping finger, bold
				draw_line(pts[5], pts[8], UiKit.GOLD, 7.0 * u)
	if _playing():   # fingertip cursors: the only spots that pop
		var tip_r := float(d("pointer_radius", 0.018)) * view.y
		for h in _pointers:
			draw_circle(h["pos"], tip_r * 1.6, Color(UiKit.GOLD, 0.35))
			draw_circle(h["pos"], tip_r * 0.7, Color.WHITE)
			draw_arc(h["pos"], tip_r * 1.6, 0.0, TAU, 24, UiKit.GOLD, 3.0 * u)
	if st != St.IDLE and st != St.DONE:
		_draw_score(view, u, st == St.SUMMARY)


## Score: top right (small) while playing, centre (big) on the summary. Star + number;
## red when below 0.
func _draw_score(view: Vector2, u: float, big: bool) -> void:
	var s := (2.2 if big else 1.0) * u
	var size := Vector2(250, 112) * s
	var pos := (view - size) / 2.0 if big else Vector2(view.x * 0.95 - size.x, view.y * 0.05)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.3, 0.02, 0.02, 0.55 + 0.3 * _flash) if _flash > 0.0 else Color(0, 0, 0, 0.6)
	sb.set_corner_radius_all(int(24 * s))
	sb.draw(get_canvas_item(), Rect2(pos, size))
	var font := UiKit.font()
	draw_string(font, pos + Vector2(0, 24) * s, UiKit.ui_both("score_title"), HORIZONTAL_ALIGNMENT_CENTER, size.x,
		int(18 * s), Color(1, 1, 1, 0.75))
	draw_colored_polygon(UiKit.star_points(pos + Vector2(58, 68) * s, 26.0 * s), UiKit.GOLD)
	var col := BAD if score < 0 else Color.WHITE
	draw_string_outline(font, pos + Vector2(100, 90) * s, str(score), HORIZONTAL_ALIGNMENT_LEFT, -1, int(60 * s),
		int(6 * s), UiKit.OUTLINE)
	draw_string(font, pos + Vector2(100, 90) * s, str(score), HORIZONTAL_ALIGNMENT_LEFT, -1, int(60 * s), col)


func _draw_bubble(c: Vector2, r: float, it: Dictionary) -> void:
	var tex: Texture2D = _baked.get(str(it["id"]), null)
	if tex != null:
		var half := r * (BAKE_PX / 2.0) / BAKE_R
		draw_texture_rect(tex, Rect2(c - Vector2(half, half), Vector2(half, half) * 2.0), false)
	else:
		_draw_bubble_on(self, c, r, it)


## Vector bubble on any CanvasItem: used live until baked, and to bake.
func _draw_bubble_on(ci: CanvasItem, c: Vector2, r: float, it: Dictionary) -> void:
	var col := _item_color(it)
	ci.draw_circle(c, r, Color(col, 0.25))
	var tex: Texture2D = _photos.get(str(it["id"]), null)
	if tex != null:
		var pts := PackedVector2Array()
		for uv in _circle_uv:
			pts.append(c + (uv - Vector2(0.5, 0.5)) * 2.0 * r * 0.82)
		ci.draw_colored_polygon(pts, Color.WHITE, _circle_uv, tex)
	elif it.has("label"):
		var font := UiKit.font()
		var label := str(it["label"].get(Settings.primary_language, it["label"].get("en", "?")))
		var size := int(r * 1.05)
		ci.draw_string_outline(font, c + Vector2(-r, r * 0.22), label, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, size,
			maxi(4, size / 10), UiKit.OUTLINE)
		ci.draw_string(font, c + Vector2(-r, r * 0.22), label, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, size, Color.WHITE)
		var n := int(it.get("count", 0))
		for i in n:   # dots to count
			ci.draw_circle(c + Vector2((i - (n - 1) / 2.0) * r * 0.26, r * 0.58), r * 0.09, col.lightened(0.4))
	elif str(it.get("shape", "")) == "banana":
		_draw_banana(ci, c, r, col)
	elif bool(it.get("avoid", false)):
		_draw_bee(ci, c, r)
	else:
		ci.draw_circle(c, r * 0.55, col)
	var rim := Color(1.0, 0.5, 0.45, 0.95) if bool(it.get("avoid", false)) else Color(1, 1, 1, 0.85)
	ci.draw_arc(c, r, 0.0, TAU, 48, rim, maxf(3.0, r * 0.06), true)
	ci.draw_circle(c + Vector2(-r * 0.42, -r * 0.45), r * 0.13, Color(1, 1, 1, 0.65))


## Crescent between two offset arcs, tilted, brown tips.
func _draw_banana(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	var rot := -0.45
	var n := 18
	for i in n + 1:   # outer edge
		var t := lerpf(0.12, 0.88, float(i) / n) * PI
		pts.append(c + (Vector2(cos(t), sin(t)) * r * 0.62 + Vector2(0, -r * 0.32)).rotated(rot))
	for i in range(n, -1, -1):   # inner edge: fat in the middle, thin at the tips
		var t := lerpf(0.12, 0.88, float(i) / n) * PI
		pts.append(c + (Vector2(cos(t), sin(t)) * r * 0.62 + Vector2(0, -r * 0.32 - r * 0.34 * sin(t))).rotated(rot))
	ci.draw_colored_polygon(pts, col)
	ci.draw_polyline(pts, col.darkened(0.35), maxf(2.0, r * 0.04), true)
	for t in [0.12 * PI, 0.88 * PI]:
		ci.draw_circle(c + (Vector2(cos(t), sin(t)) * r * 0.62 + Vector2(0, -r * 0.32)).rotated(rot), r * 0.06,
			Color(0.4, 0.27, 0.1))


## Friendly bee: wings, striped body, head, stinger.
func _draw_bee(ci: CanvasItem, c: Vector2, r: float) -> void:
	var wing := Color(1, 1, 1, 0.85)
	ci.draw_circle(c + Vector2(-r * 0.18, -r * 0.42), r * 0.24, wing)
	ci.draw_circle(c + Vector2(r * 0.2, -r * 0.42), r * 0.24, wing)
	var body := PackedVector2Array()
	for i in 24:
		var a := TAU * i / 24.0
		body.append(c + Vector2(cos(a) * r * 0.55, sin(a) * r * 0.38 + r * 0.05))
	ci.draw_colored_polygon(body, Color(1.0, 0.82, 0.15))
	var black := Color(0.12, 0.1, 0.08)
	for sx in [-0.12, 0.12]:
		ci.draw_line(c + Vector2(sx * r, -r * 0.28), c + Vector2(sx * r, r * 0.4), black, r * 0.11)
	ci.draw_circle(c + Vector2(-r * 0.6, r * 0.05), r * 0.22, black)          # head
	ci.draw_circle(c + Vector2(-r * 0.66, -r * 0.02), r * 0.05, Color.WHITE)  # eye
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(r * 0.52, -r * 0.02), c + Vector2(r * 0.78, r * 0.05),
		c + Vector2(r * 0.52, r * 0.13)]), black)                               # stinger


# ---- BaseGame hooks ------------------------------------------------------------

func skip() -> void:
	if _playing():
		_record("skipped")
		AudioDirector.stop_voice()
		_next_round()
	elif st == St.CELEBRATE:
		AudioDirector.stop_voice()
		_next_round()
	elif st == St.SUMMARY:
		_finish_game()


func repeat_prompt() -> void:
	if not paused and _playing():
		AudioDirector.stop_voice()
		AudioDirector.say(str(target["line"]), Settings.prompt_langs(round_idx - 1), true)


func resume() -> void:
	super.resume()
	if _playing():
		_intro()   # say the same item again
