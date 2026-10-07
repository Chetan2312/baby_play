extends "res://core/BaseGame.gd"
## Finger Math (5–6 years): a question with pictures to count, spoken aloud ("तीन अधिक
## तीन… किती झाले?"). The child ANSWERS WITH FINGERS: all raised fingers of the playing
## child's hands are added up (21-point hand tracking, VisionClient.hands), so 3 + 3 can be
## shown as 5+1, 3+3, 2+4 … An answer locks in when the total stays the same for hold_s.
## Right → +1 and praise. Wrong → −1 with a light red flash and "count again"; the same
## wrong total isn't counted again until the fingers change. No answer → hint (numbered
## pictures), then after round_timeout_s the answer is shown and spoken.
## Perfect game (no wrong answer, no timeout) → fireworks and trophy.
## Levels (content/games/finger_math.yaml): easy = counting 1–5 · medium = counting +
## adding within 5 · hard = adding and subtracting within 10.

const UiKit = preload("res://core/UiKit.gd")
const RoundDotsScript = preload("res://core/RoundDots.gd")
const GameFx = preload("res://core/GameFx.gd")
const GOOD := Color(0.45, 0.95, 0.45)
const BAD := Color(1.0, 0.45, 0.4)
const FLASH_S := 0.45
const FLASH_ALPHA := 0.22
const DEVA := "०१२३४५६७८९"
const HAND_BONES := [[0, 1], [1, 2], [2, 3], [3, 4], [0, 5], [5, 6], [6, 7], [7, 8], [5, 9], [9, 10],
	[10, 11], [11, 12], [9, 13], [13, 14], [14, 15], [15, 16], [13, 17], [17, 18], [18, 19], [19, 20], [0, 17]]

enum St { IDLE, INTRO, PLAY, HINT, CELEBRATE, SUMMARY, DONE }

var st := St.IDLE
var st_time := 0.0
var content: Dictionary = {}
var settings: Dictionary = {}
var level := "easy"
var lvl: Dictionary = {}
var question: Dictionary = {}   # {kind: count|add|sub, a, b, answer}
var pic: Dictionary = {}        # picture item counted this round
var round_idx := 0
var listen_time := 0.0
var score := 0
var correct := 0
var wrong := 0
var missed := 0
var results: Array = []
var perfect := false
var total := -1                 # live finger total (−1 = no hand seen)
var _hold_value := -1
var _hold_t := 0.0
var _last_locked := -1          # a wrong total counts once until the fingers change
var _verdict := ""              # "right" | "wrong" for the answer panel, briefly
var _verdict_t := 0.0
var _flash := 0.0
var _last_try := -100.0
var _photos: Dictionary = {}
var _circle_uv := PackedVector2Array()
var _card: Control = null
var _dots = null
var _last_q := ""
var _firework_t := 0.0
var _t := 0.0
var _no_hands_said := false


func _init() -> void:
	game_id = "finger_math"
	needs_frames = true
	needs_hands = true
	camera_mode = "mirror"
	for i in 32:
		var a := TAU * i / 32.0
		_circle_uv.append(Vector2(0.5 + 0.5 * cos(a), 0.5 + 0.5 * sin(a)))


func setup(cfg: Dictionary) -> void:
	super.setup(cfg)
	content = cfg.get("content", {})
	settings = content.get("settings", {})
	var levels: Dictionary = content.get("levels", {})
	level = str(cfg.get("level", ""))
	if not levels.has(level):
		level = str((content.get("session_level", {}) as Dictionary).get(str(cfg.get("difficulty", "toddler")), "easy"))
	if not levels.has(level) and not levels.is_empty():
		level = str(levels.keys()[0])
	lvl = levels.get(level, {})
	for it in content.get("pictures", []):
		var p := ContentDB.root.path_join(str(it.get("image", ""))) if ContentDB.root != "" else ""
		if p != "" and FileAccess.file_exists(p):
			var img := Image.load_from_file(p)
			if img != null:
				_photos[str(it["id"])] = ImageTexture.create_from_image(img)


func d(key: String, fallback = 0.0):
	return lvl.get(key, settings.get(key, fallback))


func start() -> void:
	super.start()
	_dots = RoundDotsScript.new()
	_dots.refresh(int(d("rounds", 6)), results, 0)
	_dots.grow_vertical = Control.GROW_DIRECTION_BEGIN
	GameManager.game_ui.add_child(_dots)
	_dots.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_dots.offset_top = -_dots.custom_minimum_size.y
	_dots.offset_bottom = 0.0
	GameManager.mascot.play("wave_hello")
	var intro := str(content.get("intro_line", ""))
	if intro != "":
		await AudioDirector.say(intro, Settings.prompt_langs(0))
	if st == St.DONE or not is_inside_tree():
		return
	_next_round()


# ---- questions -----------------------------------------------------------------

## kind: count | add | sub · answers between lo and hi (inclusive).
func make_question(kind: String, lo: int, hi: int) -> Dictionary:
	lo = maxi(1, lo)
	hi = maxi(lo, hi)
	match kind:
		"add":
			var ans := randi_range(maxi(2, lo), maxi(2, hi))
			var a := randi_range(1, ans - 1)
			return {"kind": "add", "a": a, "b": ans - a, "answer": ans}
		"sub":
			var a := randi_range(lo + 1, maxi(lo + 1, hi))
			var b := randi_range(1, a - lo)
			return {"kind": "sub", "a": a, "b": b, "answer": a - b}
	var n := randi_range(lo, hi)
	return {"kind": "count", "a": n, "b": 0, "answer": n}


func _next_round() -> void:
	if finish_requested or round_idx >= int(d("rounds", 6)):
		_summary()
		return
	round_idx += 1
	var kinds: Array = d("kinds", ["count"])
	for i in 10:   # don't ask the same question twice in a row
		question = make_question(str(kinds.pick_random()), int(d("min_answer", 1)), int(d("max_answer", 5)))
		var key := "%s%d%d" % [question["kind"], question["a"], question["b"]]
		if key != _last_q:
			_last_q = key
			break
	var pics: Array = content.get("pictures", [])
	pic = pics.pick_random() if not pics.is_empty() else {}
	_intro()


func _intro() -> void:
	st = St.INTRO
	st_time = 0.0
	listen_time = 0.0
	_hold_value = -1
	_hold_t = 0.0
	_last_locked = -1
	GameManager.mascot.go_home()
	GameManager.mascot.play("point")
	_show_card()
	_dots.refresh(int(d("rounds", 6)), results, round_idx)
	_say_question(Settings.prompt_langs(round_idx - 1))


func digits(n: int, lang: String) -> String:
	var s := str(n)
	if lang == "en":
		return s
	var out := ""
	for ch in s:
		out += DEVA[int(ch)]
	return out


func equation_text(lang: String) -> String:
	match str(question.get("kind", "")):
		"add":
			return "%s + %s = ?" % [digits(question["a"], lang), digits(question["b"], lang)]
		"sub":
			return "%s − %s = ?" % [digits(question["a"], lang), digits(question["b"], lang)]
	return "?"


func _q_line() -> String:
	return str(content.get({"add": "q_add_line", "sub": "q_sub_line"}.get(str(question["kind"]), "q_count_line"), ""))


func number_word(n: int) -> String:
	var words: Array = content.get("number_words", [])
	return str(words[n - 1]) if n >= 1 and n <= words.size() else ""


## "तीन अधिक तीन… किती झाले? बोटांनी दाखव!" (numbers in the first language only, so a
## three-language mode doesn't interleave them).
func _say_question(langs: Array) -> void:
	var first := [langs[0]] if not langs.is_empty() else []
	if str(question["kind"]) != "count":
		AudioDirector.say(number_word(question["a"]), first)
		AudioDirector.say(str(content.get("plus_line" if question["kind"] == "add" else "minus_line", "")), first)
		AudioDirector.say(number_word(question["b"]), first)
	AudioDirector.say(_q_line(), langs)


func _show_card() -> void:
	_hide_card()
	var rows: Array = []
	if str(question["kind"]) != "count":
		rows.append([equation_text(Settings.primary_language), 84, UiKit.GOLD])
	rows.append_array(UiKit.prompt_rows(_q_line(), Settings.display_langs(round_idx - 1)))
	_card = UiKit.side_card(GameManager.game_ui, rows)


func _hide_card() -> void:
	if _card != null and is_instance_valid(_card):
		_card.queue_free()
	_card = null


# ---- fingers -------------------------------------------------------------------

## Sum of raised fingers over the active child's tracked hands; −1 when no hand is seen.
static func finger_total(hands: Array, active_ids: Array) -> int:
	var t := -1
	for h in hands:
		if not active_ids.is_empty() and not active_ids.has(int(h.get("player", -1))):
			continue
		t = maxi(t, 0) + int(h.get("count", 0))
	return t


func _active_ids() -> Array:
	var ids: Array = []
	for p in VisionClient.active_people:
		ids.append(int(p.get("id", -1)))
	return ids


func _playing() -> bool:
	return st == St.INTRO or st == St.PLAY or st == St.HINT


func _process(delta: float) -> void:
	_t += delta
	_flash = maxf(0.0, _flash - delta / FLASH_S)
	_verdict_t = maxf(0.0, _verdict_t - delta)
	if paused or st == St.IDLE or st == St.DONE:
		queue_redraw()
		return
	st_time += delta
	total = finger_total(VisionClient.hands, _active_ids()) if VisionClient.hands_fresh() else -1
	match st:
		St.INTRO:
			if st_time >= float(d("intro_arm_s", 0.8)):
				st = St.PLAY
		St.PLAY, St.HINT:
			if not AudioDirector.is_speaking():
				listen_time += delta
			_track_answer(delta)
			if st == St.PLAY and listen_time >= float(d("prompt_timeout_s", 12.0)):
				_hint()
			if _playing() and listen_time >= float(d("round_timeout_s", 30.0)):
				_timeout()
			if not VisionClient.hands_fresh() and not _no_hands_said and listen_time > 3.0:
				_no_hands_said = true      # hand tracking isn't running: say it once
				AudioDirector.say(str(content.get("no_hands_line", "")), Settings.prompt_langs(0))
		St.CELEBRATE:
			if st_time >= float(d("celebrate_s", 2.4)) and not AudioDirector.is_speaking():
				_next_round()
		St.SUMMARY:
			if perfect:
				_fireworks(delta)
			var hold := float(d("perfect_s", 7.0)) if perfect else float(d("summary_s", 4.5))
			if st_time >= hold and not AudioDirector.is_speaking():
				_finish_game()
	queue_redraw()


## Lock an answer when the finger total stays the same for hold_s.
func _track_answer(delta: float) -> void:
	if total != _hold_value:
		_hold_value = total
		_hold_t = 0.0
		if total != _last_locked:
			_last_locked = -1          # fingers changed: the last wrong total may count again later
		return
	_hold_t += delta
	if total >= 1 and _hold_t >= float(d("hold_s", 1.0)) and total != _last_locked:
		_last_locked = total
		if total == int(question["answer"]):
			_success()
		else:
			_wrong()


func hold_fraction() -> float:
	if total < 1 or total == _last_locked:
		return 0.0
	return clampf(_hold_t / maxf(0.01, float(d("hold_s", 1.0))), 0.0, 1.0)


func _hint() -> void:
	st = St.HINT
	GameManager.mascot.go_spotlight()
	GameManager.mascot.play("point", 3.0)
	AudioDirector.hint(game_id, Settings.prompt_langs(round_idx - 1))


func _success() -> void:
	st = St.CELEBRATE
	st_time = 0.0
	correct += 1
	score += 1
	_verdict = "right"
	_verdict_t = 2.0
	_record("success")
	_hide_card()
	GameManager.mascot.go_home()
	GameManager.mascot.play("cheer")
	AudioDirector.stop_voice()
	AudioDirector.sfx("success")
	GameManager.praise.burst(_panel_center(get_viewport_rect().size), 70, 800.0)
	_show_answer_word()
	AudioDirector.praise(Settings.prompt_langs(round_idx - 1))
	AudioDirector.say(number_word(question["answer"]), Settings.word_langs(round_idx - 1))


func _wrong() -> void:
	wrong += 1
	score -= 1
	_flash = 1.0
	_verdict = "wrong"
	_verdict_t = 1.2
	AudioDirector.sfx("try_again")
	GameManager.mascot.play("surprised", 1.0)
	var line := str(content.get("try_again_line", ""))
	if line != "" and _t - _last_try >= float(d("try_again_every_s", 5.0)) and not AudioDirector.is_speaking():
		_last_try = _t
		AudioDirector.say(line, Settings.prompt_langs(round_idx - 1))


## No answer in time: show and say the answer, no minus point.
func _timeout() -> void:
	st = St.CELEBRATE
	st_time = 0.0
	missed += 1
	_record("missed")
	_hide_card()
	GameManager.mascot.go_home()
	GameManager.mascot.play("clap")
	_show_answer_word()
	AudioDirector.say(number_word(question["answer"]), Settings.word_langs(round_idx - 1))


func _show_answer_word() -> void:
	var rows: Array = []
	for lang in Settings.word_langs(round_idx - 1):
		var w := ContentDB.text(number_word(question["answer"]), str(lang))
		rows.append(["%s  %s" % [digits(question["answer"], str(lang)), w], str(lang)])
	GameManager.praise.show_word(rows, float(d("celebrate_s", 2.4)))


func _summary() -> void:
	st = St.SUMMARY
	st_time = 0.0
	_hide_card()
	perfect = wrong == 0 and missed == 0 and correct > 0
	GameManager.mascot.go_spotlight()
	GameManager.mascot.play("big_cheer", float(d("perfect_s", 7.0)) if perfect else 3.0)
	GameManager.praise.rain(220 if perfect else 90)
	AudioDirector.sfx("success")
	AudioDirector.say(str(content.get("perfect_line", "")) if perfect else "bubble_well_done", Settings.prompt_langs(0))


func _fireworks(delta: float) -> void:
	_firework_t -= delta
	if _firework_t > 0.0:
		return
	_firework_t = randf_range(0.18, 0.4)
	var view := get_viewport_rect().size
	GameManager.praise.burst(Vector2(randf_range(0.1, 0.9) * view.x, randf_range(0.1, 0.55) * view.y), 45,
		randf_range(650.0, 1000.0))
	if randf() < 0.5:
		AudioDirector.sfx("sparkle")


func _record(result: String) -> void:
	results.append("success" if result == "success" else "timeout")
	Stats.record_round(game_id, {"round": round_idx, "kind": str(question["kind"]), "answer": int(question["answer"]),
		"level": level, "result": result})
	_dots.refresh(int(d("rounds", 6)), results, round_idx)


func _finish_game() -> void:
	st = St.DONE
	_hide_card()
	finish({"game": game_id, "rounds": round_idx, "successes": correct, "results": results, "correct": correct,
		"wrong": wrong, "missed": missed, "score": score, "perfect": perfect, "level": level})


# ---- drawing -------------------------------------------------------------------

func _panel_center(view: Vector2) -> Vector2:
	return Vector2(view.x * 0.86, view.y * 0.36)


func _card_bottom(view: Vector2, u: float) -> float:
	var top := view.y * 0.3
	if _card != null and is_instance_valid(_card) and _card.get_child_count() > 0 \
			and _card.get_child(0).get_child_count() > 0:
		var panel := _card.get_child(0).get_child(0) as Control
		top = clampf(panel.get_global_rect().end.y + 16.0 * u, view.y * 0.18, view.y * 0.6)
	return top


func _draw() -> void:
	var view := get_viewport_rect().size
	var u := view.y / 1080.0
	var font := UiKit.font()
	if _flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, view), Color(1.0, 0.15, 0.1, FLASH_ALPHA * _flash))
	if _playing() or st == St.CELEBRATE:
		_draw_pictures(view, u, font)
	if _playing():
		_draw_hands(view, u, font)
		_draw_answer_panel(view, u, font)
	elif st == St.CELEBRATE:
		_draw_answer_panel(view, u, font)
	if st == St.SUMMARY and perfect:
		_draw_trophy(view, u, font)
	if st != St.IDLE and st != St.DONE:
		_draw_score(view, u, font, st == St.SUMMARY)


## The pictures to count, under the prompt card: groups for a + b, crossed-out for a − b.
## With the hint on, each picture to count gets its number.
func _draw_pictures(view: Vector2, u: float, font: Font) -> void:
	if question.is_empty():
		return
	var x0 := view.x * 0.05
	var w := view.x * UiKit.SIDE_FRAC
	var r := minf(view.y * 0.042, w / 12.0)
	var gap := r * 2.35
	var y := _card_bottom(view, u) + r
	var kind := str(question["kind"])
	var hint := st == St.HINT or st == St.CELEBRATE
	var groups: Array = [[int(question["a"]), false]]
	if kind == "add":
		groups.append([int(question["b"]), false])
	var number := 1
	for g in groups.size():
		var n: int = groups[g][0]
		for i in n:
			var col_i := i % 5
			var row_i := i / 5
			var c := Vector2(x0 + w / 2.0 + (col_i - 2) * gap, y + row_i * gap)
			var crossed := kind == "sub" and i >= n - int(question["b"])
			_draw_icon(c, r, crossed)
			if crossed:
				draw_line(c + Vector2(-r, -r), c + Vector2(r, r), BAD, 6.0 * u)
				draw_line(c + Vector2(r, -r), c + Vector2(-r, r), BAD, 6.0 * u)
			elif hint:
				var fs := int(r * 1.1)
				draw_string_outline(font, c + Vector2(-r, r * 0.4), digits(number, Settings.primary_language),
					HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, fs, int(6 * u), UiKit.OUTLINE)
				draw_string(font, c + Vector2(-r, r * 0.4), digits(number, Settings.primary_language),
					HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, fs, Color.WHITE)
				number += 1
		y += (ceili(n / 5.0)) * gap
		if g == 0 and groups.size() > 1:   # the "+" between the groups
			var fs := int(64 * u)
			draw_string_outline(font, Vector2(x0, y + fs * 0.1), "+", HORIZONTAL_ALIGNMENT_CENTER, w, fs, int(6 * u),
				UiKit.OUTLINE)
			draw_string(font, Vector2(x0, y + fs * 0.1), "+", HORIZONTAL_ALIGNMENT_CENTER, w, fs, UiKit.GOLD)
			y += fs * 0.6 + r


func _draw_icon(c: Vector2, r: float, dim: bool) -> void:
	var col := Color(1, 1, 1, 0.4 if dim else 1.0)
	var tex: Texture2D = _photos.get(str(pic.get("id", "")), null)
	if tex != null:
		var pts := PackedVector2Array()
		for uv in _circle_uv:
			pts.append(c + (uv - Vector2(0.5, 0.5)) * 2.0 * r)
		draw_colored_polygon(pts, col, _circle_uv, tex)
	else:
		var pc: Array = pic.get("color", [1.0, 0.7, 0.2])
		draw_circle(c, r, Color(float(pc[0]), float(pc[1]), float(pc[2]), col.a))
	draw_arc(c, r, 0.0, TAU, 32, Color(1, 1, 1, 0.8 * col.a), maxf(2.0, r * 0.08), true)


## The child's tracked hands with each hand's finger count.
func _draw_hands(view: Vector2, u: float, font: Font) -> void:
	var ids := _active_ids()
	for h in VisionClient.hands:
		if not ids.is_empty() and not ids.has(int(h.get("player", -1))):
			continue
		var kp: Array = h.get("kp", [])
		if kp.size() < 21:
			continue
		var pts := PackedVector2Array()
		for q in kp:
			pts.append(VisionClient.to_screen(Vector2(float(q[0]), float(q[1])), view))
		for b in HAND_BONES:
			draw_line(pts[b[0]], pts[b[1]], Color(UiKit.GOLD, 0.85), 4.0 * u)
		for i in [4, 8, 12, 16, 20]:
			var up: bool = h.get("fingers", [false, false, false, false, false])[[4, 8, 12, 16, 20].find(i)]
			draw_circle(pts[i], (9.0 if up else 5.0) * u, Color.WHITE if up else Color(1, 1, 1, 0.4))
		var label := digits(int(h.get("count", 0)), Settings.primary_language)
		var top := pts[0]
		for p in pts:
			top.y = minf(top.y, p.y)
		var lp := Vector2(pts[0].x - 60.0 * u, top.y - 20.0 * u)
		draw_string_outline(font, lp, label, HORIZONTAL_ALIGNMENT_CENTER, 120.0 * u, int(56 * u), int(8 * u), UiKit.OUTLINE)
		draw_string(font, lp, label, HORIZONTAL_ALIGNMENT_CENTER, 120.0 * u, int(56 * u), Color.WHITE)


## Right side: the live finger total in a circle, a ring filling while it's held,
## green / red when an answer locks in.
func _draw_answer_panel(view: Vector2, u: float, font: Font) -> void:
	var c := _panel_center(view)
	var r := view.y * 0.1
	var col := Color(0, 0, 0, 0.55)
	if _verdict_t > 0.0:
		col = Color(GOOD, 0.75) if _verdict == "right" else Color(BAD, 0.75)
	draw_circle(c, r, col)
	draw_arc(c, r, 0.0, TAU, 48, Color(1, 1, 1, 0.3), 10.0 * u, true)
	var f := hold_fraction()
	if f > 0.0 and _playing():
		draw_arc(c, r, -PI / 2.0, -PI / 2.0 + TAU * f, 48, UiKit.GOLD, 14.0 * u, true)
	var shown := int(question.get("answer", 0)) if st == St.CELEBRATE else total
	var txt := digits(shown, Settings.primary_language) if shown >= 0 else "?"
	var fs := int(r * 1.15)
	draw_string_outline(font, c + Vector2(-r, fs * 0.36), txt, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, fs, int(8 * u),
		UiKit.OUTLINE)
	draw_string(font, c + Vector2(-r, fs * 0.36), txt, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, fs, Color.WHITE)
	if not VisionClient.hands_fresh():   # hand tracking isn't running
		var note := ContentDB.text(str(content.get("no_hands_line", "")), Settings.primary_language)
		draw_string(font, c + Vector2(-r * 1.6, r + 40.0 * u), note, HORIZONTAL_ALIGNMENT_CENTER, r * 3.2, int(24 * u), BAD)


func _draw_score(view: Vector2, u: float, _font: Font, big: bool) -> void:
	GameFx.draw_score(self, view, u, score, _flash, big)


func _draw_trophy(view: Vector2, u: float, _font: Font) -> void:
	GameFx.draw_trophy(self, view, u, _t)


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
		_say_question(Settings.prompt_langs(round_idx - 1))


func resume() -> void:
	super.resume()
	if _playing():
		_intro()
