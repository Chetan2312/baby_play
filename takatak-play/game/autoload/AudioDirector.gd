extends Node
## Buses: Master, Music, Voice, SFX, Echo. Voice ducks Music.
## say() queues lines (never overlapping) and can be awaited:
##     await AudioDirector.say("simon_nose", ["mr"])
## A line without a voice file still "plays" for an estimated duration, so game
## timing and the mascot's mouth work before any recording exists.

signal line_started(line_id: String, lang: String, text: String)
signal line_finished(line_id: String)

const BUSES := ["Music", "Voice", "SFX", "Echo"]
const RECENT_N := 3

var voice: AudioStreamPlayer
var music: AudioStreamPlayer
var fake_talk := false            # true while a line without audio is "spoken"
var current_text := ""

var _sfx_players: Array = []
var _sfx_next := 0
var _sfx: Dictionary = {}
var _stream_cache: Dictionary = {}
var _queue_tail := 0
var _serving := 0
var _gen := 0
var _pending := 0
var _recent: Dictionary = {}
var _duck_tween: Tween = null


func _ready() -> void:
	_ensure_buses()
	voice = AudioStreamPlayer.new()
	voice.bus = "Voice"
	add_child(voice)
	music = AudioStreamPlayer.new()
	music.bus = "Music"
	add_child(music)
	for i in 4:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_sfx_players.append(p)
	_build_sfx()


func _ensure_buses() -> void:
	for b in BUSES:
		if AudioServer.get_bus_index(b) == -1:
			AudioServer.add_bus()
			var idx := AudioServer.get_bus_count() - 1
			AudioServer.set_bus_name(idx, b)
			AudioServer.set_bus_send(idx, "Master")
	for b in Settings.volume:
		var idx := AudioServer.get_bus_index(str(b))
		if idx != -1:
			AudioServer.set_bus_volume_db(idx, float(Settings.volume[b]))


# ---- voice ---------------------------------------------------------------------

func is_speaking() -> bool:
	return _pending > 0


## Stop the current line and drop everything queued.
func stop_voice() -> void:
	_gen += 1
	voice.stop()
	fake_talk = false


func say(line_id: String, langs: Array = [], with_name := false) -> void:
	if not ContentDB.has_line(line_id):
		push_warning("unknown line " + line_id)
		return
	var ticket := _queue_tail
	_queue_tail += 1
	var gen := _gen
	_pending += 1
	_set_duck(true)
	while _serving != ticket:
		await get_tree().process_frame
	if gen == _gen:
		if langs.is_empty():
			langs = [Settings.primary_language]
		var variant := ContentDB.pick_variant(line_id)
		var name_path := ContentDB.name_clip_path()
		var use_name := with_name and name_path != "" and ContentDB.uses_name(line_id) \
				and randf() < float(ContentDB.session["name_chance"])
		for lang in langs:
			if gen != _gen:
				break
			if use_name:
				await _play_path(name_path, 0.6, gen)
			var text := str(variant.get("text", {}).get(lang, ""))
			current_text = text
			line_started.emit(line_id, str(lang), text)
			await _play_path(ContentDB.voice_path(variant, str(lang)), _estimate(text), gen)
			await _wait(float(ContentDB.session["language_gap_s"]), gen)
		line_finished.emit(line_id)
	_serving += 1
	_pending -= 1
	if _pending == 0:
		current_text = ""
		_set_duck(false)


func praise(langs: Array = []) -> void:
	await say(pick_line("praise"), langs)


func encourage(langs: Array = []) -> void:
	await say(pick_line("encourage"), langs)


func hint(game_id: String, langs: Array = []) -> void:
	var prefix := ""
	var g := ContentDB.game(game_id)
	if g.has("hint_prefix"):
		prefix = str(g["hint_prefix"])
	var lid := pick_line("hint", prefix)
	if lid == "":
		lid = pick_line("hint")
	await say(lid, langs)


## Random line of a category, never one of the last RECENT_N used.
func pick_line(category: String, prefix := "") -> String:
	var pool := ContentDB.lines_in(category, prefix)
	if pool.is_empty():
		return ""
	var recent: Array = _recent.get(category, [])
	var fresh: Array = []
	for lid in pool:
		if not (lid in recent):
			fresh.append(lid)
	if fresh.is_empty():
		fresh = pool
	var pick: String = str(fresh.pick_random())
	recent.append(pick)
	while recent.size() > RECENT_N:
		recent.pop_front()
	_recent[category] = recent
	return pick


func _estimate(text: String) -> float:
	return clampf(0.5 + text.length() * 0.07, 0.8, 4.0)


func _play_path(path: String, fallback_s: float, gen: int) -> void:
	var stream: AudioStream = _load_stream(path)
	if stream == null:
		fake_talk = true
		await _wait(fallback_s, gen)
		fake_talk = false
		return
	voice.stream = stream
	voice.play()
	await get_tree().process_frame
	while voice.playing and gen == _gen:
		await get_tree().process_frame


func _wait(seconds: float, gen: int) -> void:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end and gen == _gen:
		await get_tree().process_frame


func _load_stream(path: String) -> AudioStream:
	if path == "":
		return null
	if _stream_cache.has(path):
		return _stream_cache[path]
	var s: AudioStream = null
	if FileAccess.file_exists(path):
		if path.ends_with(".ogg"):
			s = AudioStreamOggVorbis.load_from_file(path)
	_stream_cache[path] = s
	return s


func _set_duck(on: bool) -> void:
	var idx := AudioServer.get_bus_index("Music")
	if idx == -1:
		return
	var base := float(Settings.volume.get("Music", 0.0))
	var target := base + (float(ContentDB.session["duck_db"]) if on else 0.0)
	if _duck_tween != null:
		_duck_tween.kill()
	_duck_tween = create_tween()
	_duck_tween.tween_method(func(v: float) -> void: AudioServer.set_bus_volume_db(idx, v),
			AudioServer.get_bus_volume_db(idx), target, 0.25)


## 0..1 loudness of the voice bus (drives the mascot mouth)
func voice_level() -> float:
	var idx := AudioServer.get_bus_index("Voice")
	if idx == -1:
		return 0.0
	var db := maxf(AudioServer.get_bus_peak_volume_left_db(idx, 0), AudioServer.get_bus_peak_volume_right_db(idx, 0))
	return clampf((db + 42.0) / 30.0, 0.0, 1.0)


# ---- sfx -----------------------------------------------------------------------

func sfx(sfx_name: String) -> void:
	var stream: AudioStream = null
	var res_path := "res://assets/sfx/%s.ogg" % sfx_name
	if ResourceLoader.exists(res_path):
		stream = load(res_path) as AudioStream
	elif _sfx.has(sfx_name):
		stream = _sfx[sfx_name]
	if stream == null:
		return
	var p: AudioStreamPlayer = _sfx_players[_sfx_next]
	_sfx_next = (_sfx_next + 1) % _sfx_players.size()
	p.stream = stream
	p.play()


## Gentle synthesized placeholders until real SFX land in res://assets/sfx/.
func _build_sfx() -> void:
	_sfx["success"] = _tones([[523.25, 0.12], [659.25, 0.12], [783.99, 0.12], [1046.5, 0.45]])
	_sfx["start"] = _tones([[659.25, 0.12], [987.77, 0.35]])
	_sfx["try_again"] = _tones([[587.33, 0.2], [523.25, 0.3]], 0.25)
	_sfx["pop"] = _tones([[880.0, 0.08]], 0.3)
	_sfx["sparkle"] = _tones([[1318.5, 0.06], [1567.98, 0.06], [2093.0, 0.15]], 0.18)
	_sfx["whoosh"] = _tones([[220.0, 0.08], [330.0, 0.08], [440.0, 0.1]], 0.2)


func _tones(notes: Array, vol := 0.35) -> AudioStreamWAV:
	var rate := 22050
	var total := 0
	for n in notes:
		total += int(rate * float(n[1]))
	var data := PackedByteArray()
	data.resize(total * 2)
	var off := 0
	for n in notes:
		var f := float(n[0])
		var dur := float(n[1])
		var count := int(rate * dur)
		for i in count:
			var t := float(i) / rate
			var env := minf(1.0, t / 0.01) * exp(-3.5 * t / dur)
			var v := env * (sin(TAU * f * t) + 0.3 * sin(2.0 * TAU * f * t)) * vol
			data.encode_s16(off, int(clampf(v, -1.0, 1.0) * 32767.0))
			off += 2
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	return w
