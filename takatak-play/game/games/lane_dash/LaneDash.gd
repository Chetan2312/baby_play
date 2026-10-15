extends "res://core/BaseGame.gd"
## Ninja Dash: a reaction + rhythm game (like a rhythm slasher, for 3–6 year olds).
## Two lanes run from the horizon towards the child. On the beat of an original,
## synthesized song (BeatSynth: kick, clap, hi-hat, bass), circles and squares come down
## the lanes. The child steps left / right — which half of the screen the body (hips and
## shoulders; a little ahead, from its speed, so a step counts as it starts) is in picks the
## lane. Hits have a fair window (hit_grace_s) around the arrival:
##   circle reaches your lane → smash: +1, stars
##   square reaches your lane → crash: −1 life, red flash, shake; no lives left = game over
##   square in the other lane → whoosh, dodged
## Fair patterns: never squares in both lanes at once, at least min_gap_beats to switch.
## The song speeds up as it goes. Finish it to win; win without a crash or a missed circle
## = perfect (fireworks + trophy). Reaction time: a square appears in your lane → you leave
## the lane; the fastest and average are shown at the end.
## Non-stop level (endless: true): no song end, no score limit. Tempo, squares and pairs
## keep ramping up (to bpm_max / *_max) until the lives run out; the class best score is
## kept (Stats.best). Every life_every_points points a heart drops in one lane: catch it
## = +1 life (up to max_lives, 0 = no limit), miss it = nothing.
## Tunables: content/games/lane_dash.yaml.

const UiKit = preload("res://core/UiKit.gd")
const GameFx = preload("res://core/GameFx.gd")
const BeatSynth = preload("res://core/BeatSynth.gd")
const GOOD := Color(0.45, 0.95, 0.45)
const BAD := Color(1.0, 0.35, 0.3)
const HEART := Color(1.0, 0.35, 0.6)
const LANE_COLS := [Color(0.25, 0.6, 1.0), Color(1.0, 0.55, 0.15)]   # left blue · right orange
const HUD_HEARTS := 5           # more lives than this: one heart + "×n"
const FLASH_S := 0.5
const BASS := [130.81, 130.81, 220.0, 220.0, 174.61, 174.61, 196.0, 196.0]   # C C A A F F G G

enum St { IDLE, COUNTDOWN, PLAY, SUMMARY, DONE }

var st := St.IDLE
var st_time := 0.0
var content: Dictionary = {}
var settings: Dictionary = {}
var level := "easy"
var lvl: Dictionary = {}
var bpm := 80.0
var beat_pos := 0.0             # continuous song position in beats (countdown included)
var _half_beat := -1            # last half-beat a music step was played for
var objects: Array = []         # {kind: circle|square|heart, lane, arrive (beat), spawned_ms, threat, reacted}
var lane := 0                   # the child's lane: 0 left · 1 right (screen sides)
var _lane_since_ms := 0
var score := 0
var lives := 3
var crashes := 0
var missed := 0
var dodged := 0
var reactions: Array = []       # seconds
var game_over := false
var perfect := false
var _flash := 0.0
var _shake := 0.0
var _pulse := 0.0               # beat pulse on the hit line, 1 → 0
var _last_square := [-100.0, -100.0]   # arrival beat of the last square per lane
var _players: Array = []        # music players (own pool: the SFX pool stays free)
var _player_i := 0
var _snd := {}
var _bursts: Array = []         # smash rings {pos, r, t, color}
var _t := 0.0
var endless := false
var _ramp_steps := 0            # tempo ramps so far (non-stop level difficulty)
var _last_heart := [-100.0, -100.0]
var _heart_pending := false
var _next_life_at := 0          # score that drops the next heart; 0 = no hearts
var lives_won := 0
var best := 0
var new_best := false
var _body_x := -1.0             # last body x (display), its speed (per s) and when it arrived
var _body_vel := 0.0
var _body_at := 0.0
var _body_seq := -1
var _marker_x := -1.0           # the ninja star glides between lanes (fraction of width)
var _lane_flash := 0.0          # the new lane flashes after a switch, 1 → 0


func _init() -> void:
	game_id = "lane_dash"
	needs_frames = true
	camera_mode = "mirror"


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
	bpm = float(d("bpm", 80))
	lives = int(d("lives", 3))
	endless = bool(d("endless", false))
	_next_life_at = int(d("life_every_points", 0))
	if endless:
		best = Stats.best(_best_key())
	_snd = {"kick": BeatSynth.kick(), "hat": BeatSynth.hat(), "clap": BeatSynth.clap()}
	for f in BASS:
		if not _snd.has(f):
			_snd[f] = BeatSynth.pluck(f)
	for i in 6:
		var p := AudioStreamPlayer.new()
		p.bus = "Music"
		p.volume_db = float(d("music_volume_db", -6.0))
		add_child(p)
		_players.append(p)


func d(key: String, fallback = 0.0):
	return lvl.get(key, settings.get(key, fallback))


## A setting that grows on the non-stop level: key + key_ramp per tempo ramp, up to key_max.
func dr(key: String, fallback := 0.0) -> float:
	var v := float(d(key, fallback))
	if endless:
		v = minf(v + float(d(key + "_ramp", 0.0)) * _ramp_steps, float(d(key + "_max", 1.0)))
	return v


func _best_key() -> String:
	return game_id + ":" + level


## Beats needed to switch sides: min_gap_beats, but never less than min_gap_s seconds.
func _gap() -> float:
	return maxf(float(d("min_gap_beats", 2)), float(d("min_gap_s", 0.0)) * bpm / 60.0)


func start() -> void:
	super.start()
	GameManager.mascot.play("wave_hello")
	var intro := str(content.get("intro_line", ""))
	if intro != "":
		await AudioDirector.say(intro, Settings.prompt_langs(0))
	if not is_inside_tree() or st == St.DONE:
		return
	st = St.COUNTDOWN
	st_time = 0.0
	beat_pos = -float(d("countdown_beats", 4))   # the song starts at beat 0, after 3 · 2 · 1 · GO
	_half_beat = floori(beat_pos * 2.0) - 1


# ---- music ---------------------------------------------------------------------

func _play(key) -> void:
	var p: AudioStreamPlayer = _players[_player_i]
	_player_i = (_player_i + 1) % _players.size()
	p.stream = _snd[key]
	p.play()


## One step per half beat: kick on 1 & 3, clap on 2 & 4, hi-hat on the off-beats,
## bass every beat. During the countdown only the kick (a click track).
func _music_step(half: int) -> void:
	var on_beat := half % 2 == 0
	var b := half / 2
	if beat_pos < 0.0:
		if on_beat:
			_play("kick")
		return
	if on_beat:
		_play("kick" if b % 2 == 0 else "clap")
		_play(BASS[b % BASS.size()])
		_pulse = 1.0
	else:
		_play("hat")


# ---- spawning ------------------------------------------------------------------

## What drops on beat n (arriving travel_beats later): [] or [{kind, lane}, …].
## Fair: never squares in both lanes together, min_gap_beats between squares in different
## lanes, and a square never arrives together with a square in the other lane. A pending
## heart replaces the next drop, in a lane with no square near it.
func plan_spawn(n: int) -> Array:
	var every := maxi(1, int(d("spawn_every_beats", 2)))
	if endless and n >= int(d("dense_after_beats", 1 << 30)):
		every = 1
	var song := int(d("song_beats", 64))
	var travel := float(d("travel_beats", 4))
	if n % every != 0 or (not endless and n + travel > song):
		return []
	var arrive := n + travel
	var out: Array = []
	var l := randi() % 2
	if _heart_pending:
		for k in 2:
			var hl := (l + k) % 2
			if absf(arrive - float(_last_square[hl])) >= _gap():
				_heart_pending = false
				_last_heart[hl] = arrive
				return [{"kind": "heart", "lane": hl}]
	var kind := "square" if randf() < dr("square_share", 0.3) else "circle"
	if kind == "square" and not _square_ok(l, arrive):
		kind = "circle"
	out.append({"kind": kind, "lane": l})
	if kind == "square" and randf() < dr("pair_share", 0.0):
		out.append({"kind": "circle", "lane": 1 - l})   # dodge INTO a circle
	for o in out:
		if o["kind"] == "square":
			_last_square[o["lane"]] = arrive
	return out


func _square_ok(l: int, arrive: float) -> bool:
	return absf(arrive - float(_last_square[1 - l])) >= _gap() and absf(arrive - float(_last_heart[l])) >= _gap()


func spawn_object(kind: String, l: int, arrive: float) -> Dictionary:
	var o := {"kind": kind, "lane": l, "arrive": arrive, "spawned_ms": Time.get_ticks_msec(),
		"threat": kind == "square" and l == lane, "reacted": false}
	objects.append(o)
	return o


# ---- the child's lane ------------------------------------------------------------

## Display x of the body centre: mean of the hip and shoulder midpoints that are seen
## (shoulders lead when a child leans into a step, hips when they step); −1 when nobody is seen.
static func body_x(person: Dictionary) -> float:
	var kp: Dictionary = person.get("kp", {})
	var sum := 0.0
	var n := 0
	for pair in [["l_hip", "r_hip"], ["l_shoulder", "r_shoulder"]]:
		var a = kp.get(pair[0], null)
		var b = kp.get(pair[1], null)
		if a != null and b != null and float(a[2]) > 0.3 and float(b[2]) > 0.3:
			sum += (float(a[0]) + float(b[0])) / 2.0
			n += 1
	return sum / n if n > 0 else -1.0


## Lane from body x with a dead zone around the middle (keeps the current lane there).
static func lane_of(x: float, current: int, margin: float) -> int:
	if x < 0.0:
		return current
	if x < 0.5 - margin:
		return 0
	if x > 0.5 + margin:
		return 1
	return current


## Body x a moment ahead (lane_lookahead_s) from its speed between pose updates, so a step
## switches the lane as it starts, not when the body has crossed the middle. The lead is
## capped (lane_lookahead_max) and only used while the pose is fresh.
func _predicted_body_x() -> float:
	var x := body_x(VisionClient.active_people[0])
	var now := Time.get_ticks_msec() / 1000.0
	if x < 0.0:
		_body_x = -1.0
		return -1.0
	if VisionClient.poses_received != _body_seq:
		if _body_x >= 0.0:
			var dt := maxf(0.01, now - _body_at)
			_body_vel = lerpf(_body_vel, (x - _body_x) / dt, 0.5)
		_body_x = x
		_body_at = now
		_body_seq = VisionClient.poses_received
	if now - _body_at > 0.15:          # stale pose: no guessing
		return x
	var cap := float(d("lane_lookahead_max", 0.08))
	return x + clampf(_body_vel * float(d("lane_lookahead_s", 0.08)), -cap, cap)


func _update_lane() -> void:
	if VisionClient.active_people.is_empty():
		return
	var new_lane := lane_of(_predicted_body_x(), lane, float(d("lane_margin", 0.04)))
	if new_lane == lane:
		return
	var now := Time.get_ticks_msec()
	for o in objects:   # reaction time: left the lane a square was coming down
		if o["threat"] and not o["reacted"] and int(o["lane"]) == lane:
			o["reacted"] = true
			reactions.append((now - int(o["spawned_ms"])) / 1000.0)
	lane = new_lane
	_lane_since_ms = now
	_lane_flash = 1.0


# ---- loop ----------------------------------------------------------------------

func _process(delta: float) -> void:
	_t += delta
	_flash = maxf(0.0, _flash - delta / FLASH_S)
	_shake = maxf(0.0, _shake - delta)
	_pulse = maxf(0.0, _pulse - delta * 3.0)
	_lane_flash = maxf(0.0, _lane_flash - delta * 4.0)
	var target := _lane_x(lane, 1.0)   # star glides to the lane: ~90 % of the way in 0.12 s
	_marker_x = target if _marker_x < 0.0 else lerpf(_marker_x, target, 1.0 - exp(-delta * 19.0))
	for r in _bursts:
		r["t"] += delta
	_bursts = _bursts.filter(func(r): return float(r["t"]) < 0.45)
	if paused or st == St.IDLE or st == St.DONE:
		queue_redraw()
		return
	st_time += delta
	match st:
		St.COUNTDOWN, St.PLAY:
			_advance(delta)
		St.SUMMARY:
			if perfect:
				_fireworks(delta)
			var hold := float(d("perfect_s", 7.0)) if perfect else float(d("summary_s", 5.0))
			if st_time >= hold and not AudioDirector.is_speaking():
				_finish_game()
	queue_redraw()


func _advance(delta: float) -> void:
	_update_lane()
	beat_pos += delta * bpm / 60.0
	var half := floori(beat_pos * 2.0)
	if half > _half_beat:
		for h in range(_half_beat + 1, half + 1):   # spawning never skips a beat …
			if h % 2 == 0:
				_on_beat(h / 2)
		_music_step(half)                           # … the music plays the current step only
		_half_beat = half
	if st == St.COUNTDOWN and beat_pos >= 0.0:
		st = St.PLAY
		AudioDirector.say(str(content.get("go_line", "")), Settings.prompt_langs(0))
	_resolve()
	if st == St.PLAY and not endless and beat_pos >= float(d("song_beats", 64)) and objects.is_empty():
		_summary(false)


func _on_beat(b: int) -> void:
	if b < 0:
		return
	var every := int(d("ramp_every_beats", 16))
	if b > 0 and every > 0 and b % every == 0:
		bpm = minf(bpm + float(d("bpm_ramp", 0)), float(d("bpm_max", 1000)))
		_ramp_steps += 1
	for o in plan_spawn(b):
		spawn_object(o["kind"], o["lane"], b + float(d("travel_beats", 4)))


## Objects at the hit line: smash, crash or dodge, with a fair window of hit_grace_s around
## the arrival: a circle / heart counts as soon as the child is in its lane inside the
## window; a square only crashes if the child is still in its lane when the window ends.
func _resolve() -> void:
	var view := get_viewport_rect().size
	var grace := float(d("hit_grace_s", 0.12)) * bpm / 60.0   # in beats
	var i := 0
	while i < objects.size():
		var o: Dictionary = objects[i]
		var mine := int(o["lane"]) == lane
		var early: bool = o["kind"] != "square" and mine and beat_pos >= float(o["arrive"]) - grace
		if not early and beat_pos < float(o["arrive"]) + grace:
			i += 1
			continue
		objects.remove_at(i)
		var pos := Vector2(_lane_x(int(o["lane"]), 1.0) * view.x, float(d("hit_y", 0.86)) * view.y)
		if o["kind"] == "heart":
			if mine:
				_extra_life(pos)
		elif o["kind"] == "circle":
			if mine:
				score += 1
				AudioDirector.sfx("pop")
				AudioDirector.sfx("sparkle")
				GameManager.praise.burst(pos, 26, 600.0)
				_bursts.append({"pos": pos, "r": view.y * 0.08, "t": 0.0, "color": GOOD})
				_check_life_drop()
			else:
				missed += 1
		elif mine:
			_crash(pos)
			if game_over:
				return
		else:
			dodged += 1
			AudioDirector.sfx("whoosh")


## Every life_every_points points: a heart drops next (not when lives are already at max).
func _check_life_drop() -> void:
	if _next_life_at <= 0 or score < _next_life_at:
		return
	_next_life_at += int(d("life_every_points", 0))
	var cap := int(d("max_lives", 0))
	if cap <= 0 or lives < cap:
		_heart_pending = true


func _extra_life(pos: Vector2) -> void:
	var cap := int(d("max_lives", 0))
	if cap > 0 and lives >= cap:
		return                       # already full (a heart that dropped before the cap was reached)
	lives += 1
	lives_won += 1
	AudioDirector.sfx("success")
	GameManager.praise.burst(pos, 40, 750.0)
	_bursts.append({"pos": pos, "r": get_viewport_rect().size.y * 0.1, "t": 0.0, "color": HEART})
	AudioDirector.say(str(content.get("life_line", "")), Settings.prompt_langs(0))


func _crash(pos: Vector2) -> void:
	crashes += 1
	lives -= 1
	_flash = 1.0
	_shake = 0.45
	AudioDirector.sfx("try_again")
	GameManager.mascot.play("surprised", 1.2)
	_bursts.append({"pos": pos, "r": get_viewport_rect().size.y * 0.1, "t": 0.0, "color": BAD})
	if lives <= 0:
		_summary(true)
	else:
		AudioDirector.say(str(content.get("crash_line", "")), Settings.prompt_langs(0))


func _summary(over: bool) -> void:
	st = St.SUMMARY
	st_time = 0.0
	game_over = over
	objects.clear()
	perfect = not endless and not over and crashes == 0 and missed == 0 and score > 0
	if endless:
		new_best = Stats.submit_best(_best_key(), score)
		best = maxi(best, score)
	GameManager.mascot.go_spotlight()
	GameManager.mascot.play("big_cheer" if not over else "clap", float(d("perfect_s", 7.0)) if perfect else 3.0)
	if not over or new_best:
		GameManager.praise.rain(220 if perfect or new_best else 100)
		AudioDirector.sfx("success")
	var line := "game_over_line" if over else ("perfect_line" if perfect else "win_line")
	if new_best:
		line = "best_line"
	elif endless and not over:
		line = "game_over_line"   # stopped early on the non-stop level: no "song finished"
	AudioDirector.say(str(content.get(line, "")), Settings.prompt_langs(0))
	Stats.record_round(game_id, {"result": "game_over" if over else "success", "level": level, "score": score,
		"crashes": crashes, "missed": missed, "lives_won": lives_won})


var _firework_t := 0.0


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


func _finish_game() -> void:
	st = St.DONE
	for p in _players:
		p.stop()
	finish({"game": game_id, "rounds": 1, "successes": 0 if game_over else 1, "score": score, "crashes": crashes,
		"missed": missed, "dodged": dodged, "game_over": game_over, "perfect": perfect, "level": level,
		"lives_won": lives_won, "best": best, "new_best": new_best,
		"reaction_fastest_s": reactions.min() if not reactions.is_empty() else -1.0})


# ---- drawing -------------------------------------------------------------------

## Lane centre x (fraction of width) at depth p (0 = horizon, 1 = hit line).
func _lane_x(l: int, p: float) -> float:
	var top: Array = d("lane_x_top", [0.4, 0.6])
	var bot: Array = d("lane_x_bottom", [0.27, 0.73])
	return lerpf(float(top[l]), float(bot[l]), p)


func _depth_y(p: float, view: Vector2) -> float:
	return lerpf(float(d("horizon_y", 0.2)), float(d("hit_y", 0.86)), p) * view.y


## Depth for an object: 0 when it drops, 1 when it arrives; eased so it speeds up as it nears.
func _depth(o: Dictionary) -> float:
	var travel := float(d("travel_beats", 4))
	var k := clampf(1.0 - (float(o["arrive"]) - beat_pos) / travel, 0.0, 1.06)   # a little past the line
	return k * k


func _draw() -> void:
	var view := get_viewport_rect().size
	var u := view.y / 1080.0
	if _shake > 0.0:
		draw_set_transform(Vector2(randf_range(-1, 1), randf_range(-1, 1)) * 18.0 * u * (_shake / 0.45))
	if st == St.COUNTDOWN or st == St.PLAY:
		_draw_track(view, u)
		var sorted := objects.duplicate()
		sorted.sort_custom(func(a, b): return _depth(a) < _depth(b))
		for o in sorted:
			_draw_object(o, view, u)
		_draw_player(view, u)
	for r in _bursts:
		var k := float(r["t"]) / 0.45
		draw_arc(r["pos"], float(r["r"]) * (1.0 + k * 1.5), 0.0, TAU, 40, Color(r["color"], 1.0 - k), 10.0 * u)
	draw_set_transform(Vector2.ZERO)
	if _flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, view), Color(1.0, 0.1, 0.05, 0.3 * _flash))
	var font := UiKit.font()
	if st == St.COUNTDOWN:
		var n := ceili(-beat_pos)
		var txt := str(n) if n > 0 else ContentDB.text(str(content.get("go_line", "")), Settings.primary_language)
		var fs := int(220 * u * (1.0 + 0.3 * fmod(-beat_pos, 1.0)))
		draw_string_outline(font, Vector2(0, view.y * 0.5), txt, HORIZONTAL_ALIGNMENT_CENTER, view.x, fs, int(16 * u), UiKit.OUTLINE)
		draw_string(font, Vector2(0, view.y * 0.5), txt, HORIZONTAL_ALIGNMENT_CENTER, view.x, fs, UiKit.GOLD)
	if st == St.COUNTDOWN or st == St.PLAY:
		_draw_hud(view, u, font)
	if st == St.SUMMARY:
		_draw_summary(view, u, font)
	if st != St.IDLE and st != St.DONE:
		GameFx.draw_score(self, view, u, score, _flash, st == St.SUMMARY)


## Lane corners at depth 0 (horizon) and the bottom edge (just below the hit line).
func _lane_poly(l: int, view: Vector2, u: float) -> PackedVector2Array:
	var w_top := float(d("lane_w_top", 0.1))
	var w_bot := float(d("lane_w_bottom", 0.34))
	var yb := _depth_y(1.0, view) + 60.0 * u
	return PackedVector2Array([
		Vector2((_lane_x(l, 0.0) - w_top / 2.0) * view.x, _depth_y(0.0, view)),
		Vector2((_lane_x(l, 0.0) + w_top / 2.0) * view.x, _depth_y(0.0, view)),
		Vector2((_lane_x(l, 1.0) + w_bot / 2.0) * view.x, yb),
		Vector2((_lane_x(l, 1.0) - w_bot / 2.0) * view.x, yb)])


## Two clearly separate lanes over the camera picture: a dark road under both, each lane
## in its own colour (left blue, right orange), the child's lane bright with a thick edge
## (and a flash when they switch), a dashed divider in the middle, ◀ ▶ at the bottom.
func _draw_track(view: Vector2, u: float) -> void:
	var a := _lane_poly(0, view, u)
	var b := _lane_poly(1, view, u)
	var pad := 14.0 * u
	draw_colored_polygon(PackedVector2Array([a[0] + Vector2(-pad, 0), b[1] + Vector2(pad, 0),
		b[2] + Vector2(pad, 0), a[3] + Vector2(-pad, 0)]), Color(0.03, 0.04, 0.1, 0.45))
	for l in 2:
		var pts := _lane_poly(l, view, u)
		var col: Color = LANE_COLS[l]
		var mine := l == lane
		var fill := 0.34 + 0.3 * _lane_flash if mine else 0.1
		draw_colored_polygon(pts, Color(col, fill))
		var edge := PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]])
		draw_polyline(edge, Color(col.lightened(0.3), 1.0 if mine else 0.45), (8.0 if mine else 3.0) * u, true)
		# ◀ ▶ under the hit line, towards each lane's outer edge (clear of the ninja star)
		var dir := -1.0 if l == 0 else 1.0
		var c := Vector2((_lane_x(l, 1.0) + dir * float(d("lane_w_bottom", 0.34)) * 0.3) * view.x,
			_depth_y(1.0, view) + 36.0 * u)
		var s := 26.0 * u
		draw_colored_polygon(PackedVector2Array([c + Vector2(dir * s, 0), c + Vector2(-dir * 0.6 * s, -0.8 * s),
			c + Vector2(-dir * 0.6 * s, 0.8 * s)]), Color(col.lightened(0.4), 0.95 if mine else 0.5))
	# dashed divider down the middle, scrolling with the beat
	for k in 10:
		var p0 := fmod(float(k) / 10.0 + fmod(beat_pos, 1.0) / 10.0, 1.0)
		var p1 := minf(p0 + 0.05, 1.0)
		var y0 := _depth_y(p0 * p0, view)
		var y1 := _depth_y(p1 * p1, view)
		draw_line(Vector2(view.x * 0.5, y0), Vector2(view.x * 0.5, y1), Color(1, 1, 1, 0.35 + 0.45 * p0), (3.0 + 7.0 * p0) * u)
	# lane stripes scrolling with the beat: the track moves to the music
	for k in 6:
		var p := fmod(float(k) / 6.0 + fmod(beat_pos, 1.0) / 6.0, 1.0)
		p = p * p
		var y := _depth_y(p, view)
		for l in 2:
			var x := _lane_x(l, p) * view.x
			var w := 10.0 * u * (0.3 + 1.5 * p)
			draw_line(Vector2(x - w, y), Vector2(x + w, y), Color(1, 1, 1, 0.2 + 0.3 * p), 3.0 * u)
	# hit line per lane, pulsing on the beat
	var hy := _depth_y(1.0, view)
	for l in 2:
		var w := float(d("lane_w_bottom", 0.34)) * 0.5 * view.x * 0.95
		var x := _lane_x(l, 1.0) * view.x
		draw_line(Vector2(x - w, hy), Vector2(x + w, hy), Color(1, 1, 1, 0.35 + 0.5 * _pulse), (4.0 + 6.0 * _pulse) * u)
	# where the body really is (the lane switches when it crosses the middle): instant feedback
	if _body_x >= 0.0 and not VisionClient.active_people.is_empty():
		var bx := VisionClient.to_screen(Vector2(body_x(VisionClient.active_people[0]), 0.5), view).x
		var by := _depth_y(1.0, view) + 80.0 * u
		draw_circle(Vector2(bx, by), 12.0 * u, Color(LANE_COLS[0 if bx < view.x * 0.5 else 1] as Color, 0.95))
		draw_arc(Vector2(bx, by), 12.0 * u, 0.0, TAU, 24, Color.WHITE, 3.0 * u, true)


func _draw_object(o: Dictionary, view: Vector2, u: float) -> void:
	var p := _depth(o)
	var c := Vector2(_lane_x(int(o["lane"]), p) * view.x, _depth_y(p, view))
	var r := lerpf(0.012, 0.075, p) * view.y
	if o["kind"] == "heart":
		draw_circle(c, r * 1.4, Color(HEART, 0.3 + 0.15 * sin(_t * 10.0)))
		_draw_heart(c, r / 22.0 * (1.0 + 0.1 * sin(_t * 8.0)), HEART)
		return
	if o["kind"] == "circle":
		draw_circle(c, r * 1.25, Color(GOOD, 0.25))
		draw_circle(c, r, Color(0.3, 0.85, 0.4))
		draw_arc(c, r, 0.0, TAU, 32, Color.WHITE, maxf(2.0, r * 0.12), true)
		draw_colored_polygon(UiKit.star_points(c, r * 0.6, _t * 2.0), UiKit.GOLD)
	else:
		var rect := Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0)
		draw_rect(rect.grow(r * 0.2), Color(BAD, 0.25))
		draw_rect(rect, Color(0.85, 0.15, 0.15))
		draw_rect(rect, Color.WHITE, false, maxf(2.0, r * 0.12))
		draw_line(c + Vector2(-r, -r) * 0.55, c + Vector2(r, r) * 0.55, Color.WHITE, maxf(2.0, r * 0.18))
		draw_line(c + Vector2(r, -r) * 0.55, c + Vector2(-r, r) * 0.55, Color.WHITE, maxf(2.0, r * 0.18))


## The child's marker: a spinning ninja star at the hit line of their lane.
func _draw_player(view: Vector2, u: float) -> void:
	var c := Vector2((_marker_x if _marker_x >= 0.0 else _lane_x(lane, 1.0)) * view.x, _depth_y(1.0, view))
	var r := 46.0 * u * (1.0 + 0.15 * _pulse + 0.25 * _lane_flash)
	draw_circle(c, r * 1.3, Color(LANE_COLS[lane] as Color, 0.35))
	var pts := PackedVector2Array()
	for k in 8:
		var a := _t * 6.0 + k * PI / 4.0
		pts.append(c + Vector2(cos(a), sin(a)) * (r if k % 2 == 0 else r * 0.4))
	draw_colored_polygon(pts, Color(0.92, 0.92, 1.0))
	draw_circle(c, r * 0.18, UiKit.OUTLINE)


## A heart centred on c; s = scale (1 → ~44 px wide).
func _draw_heart(c: Vector2, s: float, col: Color) -> void:
	draw_circle(c + Vector2(-9, -6) * s, 13.0 * s, col)
	draw_circle(c + Vector2(9, -6) * s, 13.0 * s, col)
	draw_colored_polygon(PackedVector2Array([c + Vector2(-21, -2) * s, c + Vector2(21, -2) * s, c + Vector2(0, 22) * s]), col)


## Lives (hearts), then song progress, or on the non-stop level: the way to the next heart
## and the speed. Top left.
func _draw_hud(view: Vector2, u: float, font: Font) -> void:
	var x := view.x * 0.05
	var y := view.y * 0.08
	var slots := maxi(int(d("lives", 3)), lives)
	if slots > HUD_HEARTS:
		_draw_heart(Vector2(x + 24.0 * u, y), u, BAD)
		draw_string_outline(font, Vector2(x + 56.0 * u, y + 16.0 * u), "× %d" % lives, HORIZONTAL_ALIGNMENT_LEFT, -1, int(44 * u), int(6 * u), UiKit.OUTLINE)
		draw_string(font, Vector2(x + 56.0 * u, y + 16.0 * u), "× %d" % lives, HORIZONTAL_ALIGNMENT_LEFT, -1, int(44 * u), Color.WHITE)
	else:
		for k in slots:
			_draw_heart(Vector2(x + k * 64.0 * u + 24.0 * u, y), u, BAD if k < lives else Color(1, 1, 1, 0.25))
	var bar := Rect2(x, y + 36.0 * u, view.x * 0.25, 14.0 * u)
	draw_rect(bar, Color(0, 0, 0, 0.5))
	var every := int(d("life_every_points", 0))
	var f := clampf(beat_pos / float(d("song_beats", 64)), 0.0, 1.0)
	var col := UiKit.GOLD
	if endless and every > 0:
		f = clampf(1.0 - float(_next_life_at - score) / every, 0.0, 1.0)
		col = HEART
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * f, bar.size.y)), col)
	if endless:
		var txt := "%s %d" % [ContentDB.ui_text("speed_title", Settings.primary_language), _ramp_steps + 1]
		var pos := Vector2(bar.end.x + 16.0 * u, bar.end.y + 4.0 * u)
		draw_string_outline(font, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, int(36 * u), int(5 * u), UiKit.OUTLINE)
		draw_string(font, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, int(36 * u), UiKit.GOLD)


func _draw_summary(view: Vector2, u: float, font: Font) -> void:
	if perfect:
		GameFx.draw_trophy(self, view, u, _t)
	elif game_over:
		var title := "%s  %s" % [ContentDB.ui_text("game_over_title", Settings.primary_language), ContentDB.ui_text("game_over_title", "en")]
		var fs := int(96 * u)
		draw_string_outline(font, Vector2(0, view.y * 0.3), title, HORIZONTAL_ALIGNMENT_CENTER, view.x, fs, int(10 * u), UiKit.OUTLINE)
		draw_string(font, Vector2(0, view.y * 0.3), title, HORIZONTAL_ALIGNMENT_CENTER, view.x, fs, BAD)
	if endless:   # class best score, "NEW BEST!" when beaten
		var txt := UiKit.ui_both("new_best") if new_best else "%s: %d" % [UiKit.ui_both("best_score"), best]
		var fs := int((64 if new_best else 44) * u * (1.0 + (0.06 * sin(_t * 6.0) if new_best else 0.0)))
		draw_string_outline(font, Vector2(0, view.y * 0.66), txt, HORIZONTAL_ALIGNMENT_CENTER, view.x, fs, int(7 * u), UiKit.OUTLINE)
		draw_string(font, Vector2(0, view.y * 0.66), txt, HORIZONTAL_ALIGNMENT_CENTER, view.x, fs, UiKit.GOLD)
	if not reactions.is_empty():
		var fastest: float = reactions.min()
		var avg := 0.0
		for r in reactions:
			avg += float(r)
		avg /= reactions.size()
		var txt := "%s %.1f s  ·  %s %.1f s" % [UiKit.ui_both("reaction_fastest"), fastest, UiKit.ui_both("reaction_average"), avg]
		var fs := int(36 * u)
		draw_string_outline(font, Vector2(0, view.y * 0.76), txt, HORIZONTAL_ALIGNMENT_CENTER, view.x, fs, int(6 * u), UiKit.OUTLINE)
		draw_string(font, Vector2(0, view.y * 0.76), txt, HORIZONTAL_ALIGNMENT_CENTER, view.x, fs, Color.WHITE)


# ---- BaseGame hooks ------------------------------------------------------------

func skip() -> void:
	if st == St.COUNTDOWN or st == St.PLAY:
		_summary(false)
	elif st == St.SUMMARY:
		_finish_game()


func pause() -> void:
	super.pause()
	for p in _players:
		p.stream_paused = true


func resume() -> void:
	super.resume()
	for p in _players:
		p.stream_paused = false
