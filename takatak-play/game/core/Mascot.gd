extends Node2D
## PLACEHOLDER mascot: a round creature drawn in code. The public API (play, demo,
## look_at_point, home/spotlight) is what games use, so a real rig (Skeleton2D or
## AnimatedSprite2D) can replace this file without touching games.
##
## States: idle, idle_bored, talk (automatic while a voice line plays), cheer,
## big_cheer, clap, point, wave_hello, wave_bye, sleep, wake, think, listen,
## surprised, giggle.
## Demos (hints): touch_nose, touch_head, touch_ear, hands_up, touch_tummy,
## shoulders, knees, clap, left_hand_up, hop, flap, stomp, freeze, wave, crouch,
## jump, brush_teeth, wash_hands.
## "left" in demos is the CHILD's left: the mascot is shown as a mirror, so it
## raises its screen-left hand.

const BODY := Color(1.0, 0.62, 0.22)
const BELLY := Color(1.0, 0.86, 0.6)
const LINE := Color(0.24, 0.12, 0.06)
const CHEEK := Color(1.0, 0.45, 0.45, 0.55)
const DURATIONS := {"cheer": 2.0, "big_cheer": 2.5, "clap": 2.0, "point": 2.5, "wave_hello": 2.2,
	"wave_bye": 2.2, "wake": 1.5, "think": 2.5, "surprised": 1.0, "giggle": 1.6}

var R := 110.0
var state := "idle"
var demo_name := ""
var looking := false
var look_target := Vector2.ZERO

var _t := 0.0
var _state_t := 0.0
var _state_until := -1.0
var _demo_t := 0.0
var _blink_at := 2.5
var _blink_t := -1.0
var _hands := [Vector2(-0.95, 0.5), Vector2(0.95, 0.5)]   # [screen-left, screen-right], units of R
var _offset := Vector2.ZERO
var _squash := 1.0
var _mouth := 0.0
var _eyes := "open"                                          # open | closed | wide | happy
var _move_tween: Tween = null


func play(s: String, duration := -1.0) -> void:
	state = s
	demo_name = ""
	_state_t = 0.0
	_state_until = duration if duration > 0.0 else float(DURATIONS.get(s, -1.0))


func demo(dname: String) -> void:
	demo_name = dname
	state = "demo"
	_demo_t = 0.0
	_state_until = -1.0


func stop_demo() -> void:
	if state == "demo":
		play("idle")


func look_at_point(global_pos: Vector2) -> void:
	look_target = global_pos
	looking = true


## corner position (bottom right, inside TV-safe area)
func go_home(animated := true) -> void:
	var view := get_viewport_rect().size
	_move_to(Vector2(view.x * 0.86, view.y * 0.70), view.y / 1080.0, animated)


## bigger, more central: used for demos, greetings, finish
func go_spotlight(animated := true) -> void:
	var view := get_viewport_rect().size
	_move_to(Vector2(view.x * 0.78, view.y * 0.56), view.y / 1080.0 * 1.45, animated)


func go_center(animated := true) -> void:
	var view := get_viewport_rect().size
	_move_to(Vector2(view.x * 0.5, view.y * 0.6), view.y / 1080.0 * 1.6, animated)


func _move_to(pos: Vector2, s: float, animated: bool) -> void:
	if _move_tween != null:
		_move_tween.kill()
	if not animated:
		position = pos
		scale = Vector2(s, s)
		return
	_move_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_move_tween.tween_property(self, "position", pos, 0.6)
	_move_tween.tween_property(self, "scale", Vector2(s, s), 0.6)


func _ready() -> void:
	go_home(false)


func _process(delta: float) -> void:
	_t += delta
	_state_t += delta
	_demo_t += delta
	if _state_until > 0.0 and _state_t >= _state_until:
		play("idle")
	# blink every 2-5 s
	if _blink_t < 0.0 and _t >= _blink_at:
		_blink_t = 0.0
	if _blink_t >= 0.0:
		_blink_t += delta
		if _blink_t > 0.14:
			_blink_t = -1.0
			_blink_at = _t + randf_range(2.0, 5.0)
	# mouth: voice bus level, or a fake flap while a line has no audio yet
	var level := AudioDirector.voice_level()
	if AudioDirector.fake_talk:
		level = 0.5 + 0.5 * sin(_t * 18.0)
	_mouth = lerpf(_mouth, level, 1.0 - exp(-20.0 * delta))
	var pose := _pose()
	var k := 1.0 - exp(-12.0 * delta)
	_hands[0] = _hands[0].lerp(pose["l"], k)
	_hands[1] = _hands[1].lerp(pose["r"], k)
	_offset = _offset.lerp(pose["offset"], k * 1.5)
	_squash = lerpf(_squash, pose["squash"], k)
	_eyes = pose["eyes"]
	queue_redraw()


func _pose() -> Dictionary:
	var rest_l := Vector2(-0.95, 0.5)
	var rest_r := Vector2(0.95, 0.5)
	var bob := sin(_t * 2.2) * 0.03
	var p := {"l": rest_l, "r": rest_r, "offset": Vector2(0, bob), "squash": 1.0, "eyes": "open"}
	var s := _state_t
	match state:
		"idle":
			p["l"] = rest_l + Vector2(0, sin(_t * 2.2) * 0.05)
			p["r"] = rest_r + Vector2(0, sin(_t * 2.2 + 1.0) * 0.05)
		"idle_bored":
			p["offset"] = Vector2(sin(_t * 0.8) * 0.06, bob)
			p["r"] = Vector2(0.55, 0.2)
		"cheer", "big_cheer":
			var big := state == "big_cheer"
			var jump := absf(sin(s * (9.0 if big else 7.0))) * (0.45 if big else 0.25)
			p["offset"] = Vector2(0, -jump)
			p["squash"] = 1.0 + jump * 0.2
			p["l"] = Vector2(-0.8 + sin(s * 12.0) * 0.1, -1.6)
			p["r"] = Vector2(0.8 - sin(s * 12.0) * 0.1, -1.6)
			p["eyes"] = "happy"
		"clap":
			var c := absf(sin(s * 9.0)) * 0.35
			p["l"] = Vector2(-0.12 - c, 0.15)
			p["r"] = Vector2(0.12 + c, 0.15)
			p["eyes"] = "happy"
		"point":
			var dir := Vector2(-1, 0)
			if looking:
				dir = (look_target - global_position).normalized()
			p["r"] = dir * 1.6
		"wave_hello", "wave_bye":
			p["r"] = Vector2(1.1 + sin(s * 10.0) * 0.25, -1.3)
			p["eyes"] = "happy"
		"sleep":
			p["offset"] = Vector2(0, 0.12 + sin(_t * 1.2) * 0.03)
			p["squash"] = 0.94
			p["l"] = Vector2(-0.7, 0.75)
			p["r"] = Vector2(0.7, 0.75)
			p["eyes"] = "closed"
		"wake":
			p["l"] = Vector2(-0.9, -1.5)
			p["r"] = Vector2(0.9, -1.5)
			p["eyes"] = "wide" if s > 0.5 else "closed"
		"think":
			p["r"] = Vector2(0.25, 0.42)
			p["offset"] = Vector2(0.03, bob)
		"listen":
			p["r"] = Vector2(1.08, -0.3)
			p["offset"] = Vector2(0.06, bob)
		"surprised":
			p["l"] = Vector2(-0.9, -1.3)
			p["r"] = Vector2(0.9, -1.3)
			p["offset"] = Vector2(0, -0.15)
			p["eyes"] = "wide"
		"giggle":
			p["offset"] = Vector2(sin(s * 30.0) * 0.04, bob)
			p["l"] = Vector2(-0.25, 0.4)
			p["r"] = Vector2(0.25, 0.4)
			p["eyes"] = "happy"
		"demo":
			_demo_pose(p)
	return p


func _demo_pose(p: Dictionary) -> void:
	var d := _demo_t
	var osc := sin(d * 9.0)
	match demo_name:
		"touch_nose":
			p["r"] = Vector2(0.06, 0.02)
		"touch_head":
			p["r"] = Vector2(0.1, -1.05)
		"touch_ear":
			p["r"] = Vector2(1.02, -0.3)
		"hands_up":
			p["l"] = Vector2(-0.75, -1.75)
			p["r"] = Vector2(0.75, -1.75)
		"touch_tummy":
			p["r"] = Vector2(0.05, 0.58)
		"shoulders":
			p["l"] = Vector2(-0.8, -0.25)
			p["r"] = Vector2(0.8, -0.25)
		"knees":
			p["offset"] = Vector2(0, 0.3)
			p["squash"] = 0.88
			p["l"] = Vector2(-0.45, 1.05)
			p["r"] = Vector2(0.45, 1.05)
		"clap", "wash_hands":
			var c := absf(osc) * 0.3
			p["l"] = Vector2(-0.12 - c, 0.2)
			p["r"] = Vector2(0.12 + c, 0.2)
		"left_hand_up":
			p["l"] = Vector2(-0.75, -1.75)
		"hop", "jump":
			var j := absf(sin(d * (5.0 if demo_name == "hop" else 3.5))) * (0.35 if demo_name == "hop" else 0.6)
			p["offset"] = Vector2(0, -j)
			p["squash"] = 1.0 + j * 0.25
		"flap":
			p["l"] = Vector2(-1.4, -0.2 + osc * 0.5)
			p["r"] = Vector2(1.4, -0.2 + osc * 0.5)
		"stomp":
			p["offset"] = Vector2(0, absf(osc) * 0.08)
			p["squash"] = 1.0 - absf(osc) * 0.05
		"freeze":
			p["l"] = Vector2(-1.2, -0.6)
			p["r"] = Vector2(1.2, -0.6)
			p["eyes"] = "wide"
		"wave":
			p["r"] = Vector2(1.1 + osc * 0.25, -1.3)
		"crouch":
			p["offset"] = Vector2(0, 0.4)
			p["squash"] = 0.8
		"brush_teeth":
			p["r"] = Vector2(0.15 + osc * 0.15, 0.32)


func _ellipse(c: Vector2, rx: float, ry: float, col: Color) -> void:
	draw_set_transform(c, 0.0, Vector2(rx, ry))
	draw_circle(Vector2.ZERO, 1.0, col)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw() -> void:
	var o := _offset * R
	var sq := Vector2(1.0 / sqrt(_squash), _squash)
	var outline := maxf(5.0, R * 0.06)
	# shadow + feet
	_ellipse(Vector2(0, R * 1.12), R * 0.85, R * 0.16, Color(0, 0, 0, 0.25))
	for fx in [-0.42, 0.42]:
		_ellipse(Vector2(fx * R, R * 1.0) + Vector2(0, maxf(o.y, 0.0) * 0.3), R * 0.3, R * 0.16, LINE)
		_ellipse(Vector2(fx * R, R * 0.98) + Vector2(0, maxf(o.y, 0.0) * 0.3), R * 0.25, R * 0.12, BODY)
	# ears
	for ex in [-1, 1]:
		var ep := o + Vector2(ex * R * 0.8, -R * 0.78) * sq
		draw_circle(ep, R * 0.24 + outline, LINE)
		draw_circle(ep, R * 0.24, BODY)
	# body
	draw_set_transform(o, 0.0, sq)
	draw_circle(Vector2.ZERO, R + outline, LINE)
	draw_circle(Vector2.ZERO, R, BODY)
	_ellipse(Vector2(0, R * 0.38), R * 0.6, R * 0.48, BELLY)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_face(o, sq)
	# arms + hands in front
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var shoulder := o + Vector2(side * R * 0.72, R * 0.05) * sq
		var hand: Vector2 = o + _hands[i] * R
		draw_line(shoulder, hand, LINE, R * 0.2)
		draw_line(shoulder, hand, BODY, R * 0.13)
		draw_circle(hand, R * 0.17 + outline * 0.6, LINE)
		draw_circle(hand, R * 0.17, BODY)
	if state == "sleep":
		var f := ThemeDB.fallback_font
		for j in 3:
			var ph := fmod(_t * 0.6 + j * 0.33, 1.0)
			draw_string(f, o + Vector2(R * (0.7 + ph * 0.6), -R * (1.0 + ph * 0.9)), "z",
				HORIZONTAL_ALIGNMENT_LEFT, -1, int(R * (0.35 + ph * 0.3)), Color(1, 1, 1, 1.0 - ph))


func _draw_face(o: Vector2, sq: Vector2) -> void:
	var look := Vector2.ZERO
	if looking:
		look = ((look_target - global_position) / maxf(scale.x, 0.01)).limit_length(R * 3.0) / (R * 3.0)
	var closed := _eyes == "closed" or _blink_t >= 0.0
	for ex in [-1, 1]:
		var c := o + Vector2(ex * R * 0.33, -R * 0.25) * sq
		var er := R * (0.25 if _eyes == "wide" else 0.21)
		if closed:
			draw_arc(c, er * 0.8, 0.2, PI - 0.2, 12, LINE, R * 0.06)
		elif _eyes == "happy":
			draw_arc(c + Vector2(0, er * 0.3), er * 0.8, PI + 0.3, TAU - 0.3, 12, LINE, R * 0.07)
		else:
			draw_circle(c, er + R * 0.04, LINE)
			draw_circle(c, er, Color.WHITE)
			draw_circle(c + look * er * 0.45, er * 0.5, LINE)
			draw_circle(c + look * er * 0.45 + Vector2(-er * 0.15, -er * 0.18), er * 0.15, Color.WHITE)
		draw_circle(o + Vector2(ex * R * 0.55, R * 0.02) * sq, R * 0.11, CHEEK)
	var m := o + Vector2(0, R * 0.2) * sq
	if _mouth > 0.08 or _eyes == "wide":
		var h := R * (0.06 + 0.22 * maxf(_mouth, 0.4 if _eyes == "wide" else 0.0))
		_ellipse(m, R * 0.16, h, LINE)
		_ellipse(m + Vector2(0, h * 0.45), R * 0.09, h * 0.4, Color(1.0, 0.45, 0.5))
	else:
		draw_arc(m + Vector2(0, -R * 0.05), R * 0.16, 0.35, PI - 0.35, 16, LINE, R * 0.06)
