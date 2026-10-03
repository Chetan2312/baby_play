extends Node2D
## Active players: smoothed hand positions with sparkle trails, a glow around the
## player, and Area2D hit circles on both hands (group "hand") for collision games.

const MIN_CONF := 0.3
const SMOOTH := 20.0          # higher = snappier (1/s)
const FORGET_S := 0.6
const HAND_EXTEND := 0.3      # wrist → hand: extend along the forearm

var show_skeleton := false
var show_glow := true
var players: Dictionary = {}  # id -> state dict


func _ready() -> void:
	VisionClient.pose_updated.connect(_on_pose)


func _on_pose(people: Array) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	for p in people:
		if not p.get("active", false):
			continue
		var pid := int(p.get("id", -1))
		if not players.has(pid):
			players[pid] = _make_player(pid)
		var s: Dictionary = players[pid]
		s["seen"] = now
		s["person"] = p
		var b: Array = p.get("bbox", [0, 0, 0, 0])
		s["bbox_t"] = Rect2(Vector2(b[0], b[1]), Vector2(float(b[2]) - float(b[0]), float(b[3]) - float(b[1])))
		s["scale"] = float(p.get("scale", 0.1))
		for side in ["l", "r"]:
			var w := VisionClient.kp(p, side + "_wrist")
			var e := VisionClient.kp(p, side + "_elbow")
			if w.z >= MIN_CONF:
				var hand := Vector2(w.x, w.y)
				if e.z >= MIN_CONF:
					hand += (Vector2(w.x, w.y) - Vector2(e.x, e.y)) * HAND_EXTEND
				s[side + "_t"] = hand
				s[side + "_ok"] = true
			else:
				s[side + "_ok"] = false


func _make_player(pid: int) -> Dictionary:
	var s := {"id": pid, "seen": 0.0, "person": {}, "scale": 0.1,
		"bbox_t": Rect2(), "bbox": Rect2(), "l_t": Vector2(0.4, 0.5), "r_t": Vector2(0.6, 0.5),
		"l": Vector2(0.4, 0.5), "r": Vector2(0.6, 0.5), "l_ok": false, "r_ok": false}
	for side in ["l", "r"]:
		var parts := _sparkles(Color(1.0, 0.85, 0.3) if side == "l" else Color(0.5, 0.9, 1.0))
		add_child(parts)
		s[side + "_fx"] = parts
		var area := Area2D.new()
		area.add_to_group("hand")
		area.set_meta("player", pid)
		area.set_meta("side", side)
		var shape := CollisionShape2D.new()
		shape.shape = CircleShape2D.new()
		area.add_child(shape)
		add_child(area)
		s[side + "_area"] = area
		s[side + "_shape"] = shape
	return s


func _sparkles(color: Color) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.amount = 40
	p.lifetime = 0.6
	p.local_coords = false
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 14.0
	p.direction = Vector2(0, -1)
	p.spread = 180.0
	p.initial_velocity_min = 20.0
	p.initial_velocity_max = 90.0
	p.gravity = Vector2(0, 120)
	p.scale_amount_min = 4.0
	p.scale_amount_max = 9.0
	var g := Gradient.new()
	g.set_color(0, color)
	g.set_color(1, Color(color.r, color.g, color.b, 0.0))
	p.color_ramp = g
	p.emitting = false
	return p


func _process(delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var view := get_viewport_rect().size
	var k := 1.0 - exp(-SMOOTH * delta)
	for pid in players.keys():
		var s: Dictionary = players[pid]
		if now - float(s["seen"]) > FORGET_S:
			for side in ["l", "r"]:
				s[side + "_fx"].queue_free()
				s[side + "_area"].queue_free()
			players.erase(pid)
			continue
		var bt: Rect2 = s["bbox_t"]
		var bb: Rect2 = s["bbox"]
		s["bbox"] = bt if bb.size == Vector2.ZERO else Rect2(bb.position.lerp(bt.position, k), bb.size.lerp(bt.size, k))
		var radius := maxf(30.0, float(s["scale"]) * view.x * 0.55)
		for side in ["l", "r"]:
			var cur: Vector2 = s[side]
			s[side] = cur.lerp(s[side + "_t"], k)
			var pos := VisionClient.to_screen(s[side], view)
			var fx: CPUParticles2D = s[side + "_fx"]
			fx.position = pos
			fx.emitting = bool(s[side + "_ok"])
			var area: Area2D = s[side + "_area"]
			area.position = pos
			var shape: CollisionShape2D = s[side + "_shape"]
			(shape.shape as CircleShape2D).radius = radius
			area.monitorable = bool(s[side + "_ok"])
	queue_redraw()


## [{player, side, pos (screen px), radius}] for games that don't use Area2D
func hands() -> Array:
	var out: Array = []
	var view := get_viewport_rect().size
	for pid in players:
		var s: Dictionary = players[pid]
		for side in ["l", "r"]:
			if s[side + "_ok"]:
				out.append({"player": pid, "side": side, "pos": VisionClient.to_screen(s[side], view),
					"radius": maxf(30.0, float(s["scale"]) * view.x * 0.55)})
	return out


func _draw() -> void:
	var view := get_viewport_rect().size
	var t := Time.get_ticks_msec() / 1000.0
	for pid in players:
		var s: Dictionary = players[pid]
		var nb: Rect2 = s["bbox"]
		if show_glow and nb.size != Vector2.ZERO:
			var a := VisionClient.to_screen(nb.position, view)
			var b := VisionClient.to_screen(nb.end, view)
			var r := Rect2(a, b - a).grow(24.0)
			var pulse := 0.5 + 0.5 * sin(t * 4.0)
			draw_rect(r.grow(10), Color(1.0, 0.7, 0.2, 0.25 + 0.15 * pulse), false, 14.0)
			draw_rect(r, Color(1.0, 0.85, 0.4, 0.8), false, 5.0 + pulse * 3.0)
		if show_skeleton:
			_draw_skeleton(s["person"], view)


const BONES := [["l_shoulder", "r_shoulder"], ["l_shoulder", "l_elbow"], ["l_elbow", "l_wrist"],
	["r_shoulder", "r_elbow"], ["r_elbow", "r_wrist"], ["l_shoulder", "l_hip"], ["r_shoulder", "r_hip"],
	["l_hip", "r_hip"], ["l_hip", "l_knee"], ["l_knee", "l_ankle"], ["r_hip", "r_knee"], ["r_knee", "r_ankle"],
	["nose", "l_eye"], ["nose", "r_eye"], ["l_eye", "l_ear"], ["r_eye", "r_ear"]]


func _draw_skeleton(person: Dictionary, view: Vector2) -> void:
	if person.is_empty():
		return
	for bone in BONES:
		var a := VisionClient.kp(person, bone[0])
		var b := VisionClient.kp(person, bone[1])
		if a.z >= MIN_CONF and b.z >= MIN_CONF:
			var col := Color(0.35, 0.8, 1.0) if str(bone[0]).begins_with("l_") else Color(1.0, 0.6, 0.25)
			draw_line(VisionClient.to_screen(Vector2(a.x, a.y), view), VisionClient.to_screen(Vector2(b.x, b.y), view), col, 6.0)
