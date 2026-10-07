extends Node2D
## "Choose a game" (free play): one card per built game, across the top half of the
## screen where raised hands reach. Hold a hand on a card: a ring fills around its
## picture; full ring (DWELL_S) starts that game. Moving away drains the ring, so nobody
## picks by accident.
##
## The pose model has no finger points, so there's no fist/grab gesture: dwell is the
## select. Only a RAISED hand counts (wrist above its elbow): a child standing with arms
## hanging in front of a card doesn't pick it. Single button / remote: next = move the highlight, select or long = start the
## highlighted game, back = leave free play (stays here when the picker is the start screen).
## The "session" card (first) starts today's fixed session. A game with levels (Bubble Pop)
## opens a second page: Easy / Medium / Hard (back = return to the games).

const UiKit = preload("res://core/UiKit.gd")
const DWELL_S := 1.5
const DRAIN := 2.0              # the ring empties this many times faster than it fills
const CALL_EVERY_S := 20.0      # mascot repeats "hold your hand on a picture"
const PAGE_COOLDOWN_S := 1.2    # after switching page, hands must settle before a new dwell

var games: Array = []
var sel := 0                    # highlighted card (button control)
var dwell: Array = []           # 0..1 per card
var fake_hands: Array = []      # tests: [{pos: Vector2}] used instead of the camera
var _picked := false
var page := "games"             # games | levels
var _game_cards: Array = []
var _game_sel := 0
var _chosen := ""               # card whose level is being chosen
var _last_level := ""
var _cooldown := 0.0
var _title_label: Label = null
var _t := 0.0
var _last_call := -100.0


## last: the card played last time, highlighted first · last_level: on the level page
func setup_picker(ids: Array, last := "", last_level := "") -> void:
	_game_cards = ids
	_last_level = last_level
	_show_page("games", ids, maxi(0, ids.find(last)))
	var ui: Control = GameManager.game_ui
	var title := UiKit.card([[UiKit.ui_both("picker_title"), 52, UiKit.GOLD]], 0.45)
	_title_label = title.get_child(0).get_child(0)
	UiKit.top_center(ui, title)
	UiKit.bottom_center(ui, UiKit.card([[UiKit.ui_both("picker_help"), 28, Color(0.9, 0.9, 0.95)]], 0.4))
	GameManager.mascot.go_home()
	GameManager.mascot.play("point", 2.5)


## Card rectangles in screen pixels: a row across the top half, centred.
func _show_page(p: String, cards: Array, select: int) -> void:
	page = p
	games = cards
	sel = clampi(select, 0, maxi(0, cards.size() - 1))
	dwell = []
	for i in games.size():
		dwell.append(0.0)
	_cooldown = PAGE_COOLDOWN_S
	if _title_label != null:
		_title_label.text = UiKit.ui_both("level_title" if p == "levels" else "picker_title")


func card_rects() -> Array:
	var view := get_viewport_rect().size
	var n := maxi(1, games.size())
	var gap := view.x * 0.04
	var w := minf(view.x * 0.26, (view.x * 0.84 - gap * (n - 1)) / n)
	var h := view.y * 0.36
	var x0 := (view.x - (w * n + gap * (n - 1))) / 2.0
	var out: Array = []
	for i in n:
		out.append(Rect2(x0 + i * (w + gap), view.y * 0.18, w, h))
	return out


func _hands() -> Array:
	if not fake_hands.is_empty():
		return fake_hands
	var out: Array = []
	for h in (GameManager.avatar.hands() if GameManager.avatar != null else []):
		if _raised(h):
			out.append(h)
	return out


## Wrist above its elbow (forearm up): reaching, not hanging.
func _raised(h: Dictionary) -> bool:
	var p := VisionClient.person_by_id(int(h["player"]))
	var w := VisionClient.kp(p, str(h["side"]) + "_wrist")
	var e := VisionClient.kp(p, str(h["side"]) + "_elbow")
	if w.z < 0.3 or e.z < 0.3:
		return false
	return w.y < e.y + 0.01


func _process(delta: float) -> void:
	_t += delta
	_cooldown = maxf(0.0, _cooldown - delta)
	if games.is_empty() or _picked:
		queue_redraw()
		return
	if VisionClient.is_open and _t - _last_call > CALL_EVERY_S and not AudioDirector.is_speaking():
		_last_call = _t
		AudioDirector.say("picker_choose", Settings.prompt_langs(0))
	var rects := card_rects()
	var hands: Array = _hands() if _cooldown <= 0.0 else []
	for i in games.size():
		var hovered := false
		var r: Rect2 = rects[i]
		for h in hands:
			var grow := float(h.get("radius", 0.0)) * 0.3
			if r.grow(grow).has_point(h["pos"]):
				hovered = true
				break
		if hovered:
			sel = i
			dwell[i] = minf(1.0, float(dwell[i]) + delta / DWELL_S)
		else:
			dwell[i] = maxf(0.0, float(dwell[i]) - delta * DRAIN / DWELL_S)
		if dwell[i] >= 1.0:
			pick(i)
			return
	queue_redraw()


func pick(i: int) -> void:
	if _picked or i < 0 or i >= games.size():
		return
	var card := str(games[i])
	if page == "games":
		_game_sel = i
		var levels := GameManager.card_levels(card)
		if not levels.is_empty():     # → Easy / Medium / Hard
			_chosen = card
			AudioDirector.sfx("whoosh")
			var cards: Array = levels.map(func(l): return "level:" + str(l))
			_show_page("levels", cards, maxi(0, levels.find(_last_level)))
			queue_redraw()
			return
	_picked = true
	sel = i
	dwell[i] = 1.0
	AudioDirector.stop_voice()
	AudioDirector.sfx("success")
	var r: Rect2 = card_rects()[i]
	GameManager.praise.burst(r.get_center(), 70, 800.0)
	GameManager.mascot.play("big_cheer", 1.5)
	queue_redraw()
	await get_tree().create_timer(0.9).timeout
	if is_inside_tree():
		if page == "levels":
			GameManager.pick_game(_chosen, card.get_slice(":", 1))
		else:
			GameManager.pick_game(card)


func on_action(a: String) -> void:
	if _picked or games.is_empty():
		return
	match a:
		"next":
			sel = (sel + 1) % games.size()
			AudioDirector.sfx("pop")
		"prev":
			sel = (sel - 1 + games.size()) % games.size()
			AudioDirector.sfx("pop")
		"select", "long":
			pick(sel)
		"back":
			if page == "levels":
				_show_page("games", _game_cards, _game_sel)
			elif not GameManager.landing_picker():
				GameManager.exit_free_play()
	queue_redraw()


# ---- drawing -------------------------------------------------------------------

func _draw() -> void:
	var view := get_viewport_rect().size
	var u := view.y / 1080.0
	draw_rect(Rect2(Vector2.ZERO, view), Color(0.04, 0.06, 0.14, 0.35))
	var rects := card_rects()
	var font := UiKit.font()
	for i in games.size():
		var r: Rect2 = rects[i]
		var gid := str(games[i])
		var hi := i == sel
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.06, 0.07, 0.16, 0.6)   # see-through: children still see themselves
		sb.set_corner_radius_all(int(28 * u))
		sb.border_color = UiKit.GOLD if hi else Color(1, 1, 1, 0.5)
		sb.set_border_width_all(int((8 if hi else 3) * u))
		var bob := Vector2(0, (sin(_t * 2.0 + i) * 6.0 if not _picked else 0.0) * u)
		sb.draw(get_canvas_item(), Rect2(r.position + bob, r.size))
		# picture + dwell ring
		var c := r.position + bob + Vector2(r.size.x / 2.0, r.size.y * 0.36)
		var pr := minf(r.size.x, r.size.y) * 0.25
		draw_circle(c, pr * 1.18, Color(1, 1, 1, 0.08))
		_draw_icon(gid, c, pr)
		draw_arc(c, pr * 1.3, 0.0, TAU, 64, Color(1, 1, 1, 0.25), 10.0 * u, true)
		var f := float(dwell[i])
		if f > 0.0:
			draw_arc(c, pr * 1.3, -PI / 2.0, -PI / 2.0 + TAU * f, 64, UiKit.GOLD, 16.0 * u, true)
		# name: primary language big, the others smaller
		var title := _title(gid)
		var langs := Settings.ordered_langs()
		var y := r.position.y + bob.y + r.size.y * 0.76
		for li in langs.size():
			var size := int((46 if li == 0 else 30) * u)
			var col := UiKit.lang_color(langs[li])
			var p := Vector2(r.position.x, y)
			draw_string_outline(font, p, str(title.get(langs[li], gid)), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, size,
				int(6 * u), UiKit.OUTLINE)
			draw_string(font, p, str(title.get(langs[li], gid)), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, size, col)
			y += size * 1.25
	# hand cursors (the avatar's sparkles also show the hands; this makes them obvious here)
	for h in _hands():
		var p: Vector2 = h["pos"]
		draw_circle(p, 26.0 * u, Color(UiKit.GOLD, 0.35))
		draw_arc(p, 26.0 * u, 0.0, TAU, 32, UiKit.GOLD, 4.0 * u, true)


func _title(card: String) -> Dictionary:
	var e = null
	if card == GameManager.SESSION_CARD:
		e = ContentDB.ui.get("picker_session", {})
	elif card.begins_with("level:"):
		e = ContentDB.ui.get("level_" + card.get_slice(":", 1), {})
	elif card.contains("@"):
		for entry in ContentDB.game(card.get_slice("@", 0)).get("picker", []):
			if str(entry.get("pack", "")) == card.get_slice("@", 1):
				e = entry.get("title", {})
	else:
		e = ContentDB.game(card).get("title", {})
	return e if e is Dictionary else {}


## Simple drawn picture per game; unknown games get a star.
func _draw_icon(card: String, c: Vector2, r: float) -> void:
	if card.begins_with("level:"):   # 1 / 2 / 3 stars
		var n: int = {"easy": 1, "medium": 2, "hard": 3}.get(card.get_slice(":", 1), 1)
		for k in n:
			var p := c + Vector2((k - (n - 1) / 2.0) * r * 0.62, sin(_t * 3.0 + k) * r * 0.06)
			draw_colored_polygon(UiKit.star_points(p, r * 0.34), UiKit.GOLD)
		return
	if card == "bubble_pop@numbers_1_5":   # number bubbles
		var font := UiKit.font()
		for b in [[Vector2(-0.38, 0.2), 0.42, "१", Color(1.0, 0.55, 0.3)], [Vector2(0.42, 0.28), 0.34, "२", Color(0.35, 0.75, 1.0)],
				[Vector2(0.05, -0.45), 0.36, "३", Color(0.5, 0.9, 0.45)]]:
			var bc: Vector2 = c + (b[0] as Vector2) * r
			var br: float = float(b[1]) * r
			draw_circle(bc, br, Color(b[3], 0.35))
			draw_arc(bc, br, 0.0, TAU, 32, Color(1, 1, 1, 0.85), maxf(2.0, br * 0.08), true)
			draw_string(font, bc + Vector2(-br, br * 0.3), str(b[2]), HORIZONTAL_ALIGNMENT_CENTER, br * 2.0, int(br * 1.1))
		return
	if card == "finger_math":   # an open hand with "+"
		var skin := Color(1.0, 0.86, 0.7)
		var palm := c + Vector2(0, r * 0.25)
		draw_circle(palm, r * 0.38, skin)
		for k in 5:
			var a := lerpf(-PI * 0.85, -PI * 0.15, k / 4.0)
			var tip := palm + Vector2(cos(a), sin(a)) * r * (0.75 if k > 0 else 0.6)
			draw_line(palm, tip, skin, r * 0.17, true)
			draw_circle(tip, r * 0.085, skin)
		draw_string(UiKit.font(), c + Vector2(r * 0.25, -r * 0.35), "+", HORIZONTAL_ALIGNMENT_LEFT, -1, int(r * 0.9), UiKit.GOLD)
		return
	match card.get_slice("@", 0):
		"session":   # sun: today
			var sun := Color(1.0, 0.75, 0.2)
			for k in 12:
				var a := TAU * k / 12.0 + _t * 0.3
				draw_line(c + Vector2(cos(a), sin(a)) * r * 0.62, c + Vector2(cos(a), sin(a)) * r * 0.92, sun, r * 0.1, true)
			draw_circle(c, r * 0.48, sun)
			draw_circle(c + Vector2(-r * 0.16, -r * 0.08), r * 0.06, UiKit.OUTLINE)
			draw_circle(c + Vector2(r * 0.16, -r * 0.08), r * 0.06, UiKit.OUTLINE)
			draw_arc(c + Vector2(0, r * 0.05), r * 0.22, PI * 0.15, PI * 0.85, 16, UiKit.OUTLINE, r * 0.05, true)
		"simon_says":   # stick figure touching its head
			var skin := Color(1.0, 0.86, 0.7)
			var w := r * 0.12
			draw_circle(c + Vector2(0, -r * 0.55), r * 0.25, skin)
			draw_line(c + Vector2(0, -r * 0.3), c + Vector2(0, r * 0.35), skin, w, true)
			draw_line(c + Vector2(0, r * 0.35), c + Vector2(-r * 0.3, r * 0.85), skin, w, true)
			draw_line(c + Vector2(0, r * 0.35), c + Vector2(r * 0.3, r * 0.85), skin, w, true)
			draw_line(c + Vector2(0, -r * 0.15), c + Vector2(-r * 0.35, -r * 0.45), skin, w, true)
			draw_line(c + Vector2(-r * 0.35, -r * 0.45), c + Vector2(-r * 0.12, -r * 0.75), skin, w, true)
			draw_line(c + Vector2(0, -r * 0.15), c + Vector2(r * 0.55, r * 0.15), skin, w, true)
			draw_colored_polygon(UiKit.star_points(c + Vector2(r * 0.55, -r * 0.6), r * 0.18, _t), UiKit.GOLD)
		"bubble_pop":   # three bubbles
			for b in [[Vector2(-0.35, 0.2), 0.42, Color(1.0, 0.72, 0.2)], [Vector2(0.4, 0.3), 0.32, Color(0.95, 0.3, 0.35)],
					[Vector2(0.05, -0.45), 0.36, Color(0.55, 0.85, 0.35)]]:
				var bc: Vector2 = c + (b[0] as Vector2) * r + Vector2(0, sin(_t * 2.5 + b[1] * 10.0) * r * 0.05)
				var br: float = float(b[1]) * r
				draw_circle(bc, br, Color(b[2], 0.3))
				draw_circle(bc, br * 0.5, b[2])
				draw_arc(bc, br, 0.0, TAU, 32, Color(1, 1, 1, 0.85), maxf(2.0, br * 0.08), true)
				draw_circle(bc + Vector2(-br * 0.4, -br * 0.45), br * 0.14, Color(1, 1, 1, 0.7))
		_:
			draw_colored_polygon(UiKit.star_points(c, r * 0.8, _t * 0.5), UiKit.GOLD)
