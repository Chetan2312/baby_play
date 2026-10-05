extends Node
## WebSocket client for the vision service. Mirror of vision/takatak_vision/protocol.py:
## keep the two in sync. Games never touch the socket; they get signals via GameManager.
##
## Coordinates arrive normalised 0-1 in display space, already mirrored. Never mirror here.

signal connected_changed(connected: bool)
signal hello_received(info: Dictionary)
signal pose_updated(people: Array)
signal gesture(player: int, gname: String, state: String, conf: float)
signal motion(player: int, mname: String, conf: float, count: int)
signal loudness(db: float, speaking: bool)
signal echo_ready(path: String, duration: float)
signal keyword(word: String, lang: String, conf: float)
signal status_received(info: Dictionary)
signal no_player(seconds: float)
signal button(state: String)          # GPIO worker button edge: "down" | "up" (InputRouter)
signal frame_received(texture: Texture2D)
signal mask_received(texture: Texture2D)
signal protocol_error(text: String)

const PROTOCOL_VERSION := 1
const KIND_FRAME := 1
const KIND_MASK := 2
const RECONNECT_S := 2.0
const DEFAULT_FRAME_SIZE := Vector2(960, 540)

var ws: WebSocketPeer = null
var is_open := false
var info := {}
var hardware := {}     # hello.hardware: boot probe for the status screen
var people: Array = []
var active_people: Array = []
var last_status := {}
var frame_texture: ImageTexture = null
var frame_size := DEFAULT_FRAME_SIZE
var frames_received := 0
var poses_received := 0
var last_pose_ms := 0

var _retry_at := 0.0
var _sub := {"t": "subscribe", "frames": true, "mask": false, "loudness": false, "motion": []}
var _sticky := {}   # set_players / set_camera / set_difficulty, re-sent after reconnect
var _img := Image.new()


func _ready() -> void:
	_connect()


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _connect() -> void:
	ws = WebSocketPeer.new()
	ws.inbound_buffer_size = 8 * 1024 * 1024   # JPEG frames are ~60-120 KB
	ws.max_queued_packets = 4096
	_retry_at = _now() + RECONNECT_S
	var err := ws.connect_to_url(Settings.vision_url)
	if err != OK:
		push_warning("vision connect error %d" % err)


func _process(_delta: float) -> void:
	if ws == null:
		return
	ws.poll()
	var st := ws.get_ready_state()
	if st == WebSocketPeer.STATE_OPEN:
		if not is_open:
			is_open = true
			_on_open()
		var latest_frame := PackedByteArray()
		var latest_pose = null
		while ws.get_available_packet_count() > 0:
			var pkt := ws.get_packet()
			if ws.was_string_packet():
				var msg = JSON.parse_string(pkt.get_string_from_utf8())
				if not (msg is Dictionary):
					continue
				if msg.get("t", "") == "pose":
					latest_pose = msg          # latest-wins
				else:
					_handle(msg)
			elif pkt.size() > 5:
				var kind := pkt.decode_u8(0)
				if kind == KIND_FRAME:
					latest_frame = pkt         # decode only the newest frame
		if latest_pose != null:
			_handle(latest_pose)
		if latest_frame.size() > 0:
			_decode_frame(latest_frame)
	elif st == WebSocketPeer.STATE_CLOSED:
		if is_open:
			is_open = false
			people = []
			active_people = []
			connected_changed.emit(false)
			pose_updated.emit(people)
		if _now() >= _retry_at:
			_connect()


func _on_open() -> void:
	print("[vision] connected to ", Settings.vision_url)
	send(_sub)
	for k in _sticky:
		send(_sticky[k])
	connected_changed.emit(true)


func _handle(msg: Dictionary) -> void:
	var t := str(msg.get("t", ""))
	match t:
		"hello":
			info = msg
			hardware = msg.get("hardware", {})
			if int(msg.get("version", 0)) != PROTOCOL_VERSION:
				protocol_error.emit("vision protocol v%s, game expects v%d" % [str(msg.get("version")), PROTOCOL_VERSION])
			hello_received.emit(msg)
		"pose":
			people = msg.get("people", [])
			active_people = []
			for p in people:
				if p.get("active", false):
					active_people.append(p)
			poses_received += 1
			last_pose_ms = Time.get_ticks_msec()
			pose_updated.emit(people)
		"gesture":
			gesture.emit(int(msg.get("player", -1)), str(msg.get("name", "")), str(msg.get("state", "")), float(msg.get("confidence", 0.0)))
		"motion":
			motion.emit(int(msg.get("player", -1)), str(msg.get("name", "")), float(msg.get("confidence", 0.0)), int(msg.get("count", 0)))
		"loudness":
			loudness.emit(float(msg.get("db", -90.0)), bool(msg.get("speaking", false)))
		"echo_ready":
			echo_ready.emit(str(msg.get("path", "")), float(msg.get("duration", 0.0)))
		"keyword":
			keyword.emit(str(msg.get("word", "")), str(msg.get("lang", "")), float(msg.get("confidence", 0.0)))
		"status":
			last_status = msg
			status_received.emit(msg)
		"no_player":
			no_player.emit(float(msg.get("seconds", 0.0)))
		"button":
			button.emit(str(msg.get("state", "")))
		"error":
			protocol_error.emit(str(msg.get("text", "")))
		"pong":
			pass


func _decode_frame(pkt: PackedByteArray) -> void:
	var err := _img.load_jpg_from_buffer(pkt.slice(5))
	if err != OK:
		return
	var size := Vector2(_img.get_width(), _img.get_height())
	if frame_texture == null or frame_texture.get_size() != size:
		frame_texture = ImageTexture.create_from_image(_img)
	else:
		frame_texture.update(_img)
	frame_size = size
	frames_received += 1
	frame_received.emit(frame_texture)


# ---- game → vision -------------------------------------------------------------

func send(msg: Dictionary) -> void:
	if is_open and ws != null:
		ws.send_text(JSON.stringify(msg))


func subscribe(frames := true, mask := false, loud := false, motions: Array = []) -> void:
	_sub = {"t": "subscribe", "frames": frames, "mask": mask, "loudness": loud, "motion": motions}
	send(_sub)


func set_players(mode: String) -> void:
	_sticky["set_players"] = {"t": "set_players", "mode": mode}
	send(_sticky["set_players"])


func set_camera(camera: String) -> void:
	_sticky["set_camera"] = {"t": "set_camera", "camera": camera}
	send(_sticky["set_camera"])


func set_difficulty(difficulty: String) -> void:
	_sticky["set_difficulty"] = {"t": "set_difficulty", "difficulty": difficulty}
	send(_sticky["set_difficulty"])


func mic_listen_start(purpose: String, max_s: float) -> void:
	send({"t": "mic_listen_start", "purpose": purpose, "max_s": max_s})


func mic_listen_stop() -> void:
	send({"t": "mic_listen_stop"})


func ping() -> void:
	send({"t": "ping"})


## Dev helper: tools/mock_server.py's synthetic child performs this gesture.
## The real vision service accepts and ignores it.
func mock_expect(gname: String) -> void:
	send({"t": "mock_expect", "name": gname})


# ---- coordinates ---------------------------------------------------------------

## Rect the camera frame covers on screen (fills the view, crops overflow).
func cover_rect(view: Vector2) -> Rect2:
	var fs := frame_size
	if fs.x <= 0.0 or fs.y <= 0.0:
		fs = DEFAULT_FRAME_SIZE
	var s := maxf(view.x / fs.x, view.y / fs.y)
	var size := fs * s
	return Rect2((view - size) * 0.5, size)


func to_screen(n: Vector2, view: Vector2) -> Vector2:
	var r := cover_rect(view)
	return r.position + n * r.size


## keypoint as Vector3(x, y, conf) in normalised display space
func kp(person: Dictionary, kp_name: String) -> Vector3:
	var d: Dictionary = person.get("kp", {})
	var a = d.get(kp_name, null)
	if a == null or a.size() < 3:
		return Vector3.ZERO
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


func person_by_id(pid: int) -> Dictionary:
	for p in people:
		if int(p.get("id", -1)) == pid:
			return p
	return {}
