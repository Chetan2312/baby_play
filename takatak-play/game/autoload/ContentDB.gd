extends Node
## Loads content/build/*.json (made by tools/content_build.py) from the content folder.
## The content folder lives OUTSIDE res:// so voice files can be updated without
## re-exporting. Search order: --content=PATH, <executable dir>/content, <project>/../content.

const SESSION_DEFAULTS := {
	"pause_after_s": 3.0,
	"resume_detect_s": 0.5,
	"abandon_s": 60.0,
	"language_gap_s": 0.3,
	"name_chance": 0.33,
	"duck_db": -12.0,
}

var root := ""
var lines := {}
var categories := {}
var games := {}
var session := SESSION_DEFAULTS.duplicate()
var sessions := {}          # session id → definition (content/sessions/*.yaml)
var weeks: Array = []       # curriculum/weeks.yaml
var centre_profile := {}    # centre_profile.yaml defaults (Centre.gd adds the supervisor's changes)
var ui := {}                # ui/strings.yaml: key → {mr, en}
var content_version := ""
var error := ""


func _ready() -> void:
	reload()


func reload() -> void:
	root = _find_root()
	lines = {}
	categories = {}
	games = {}
	sessions = {}
	weeks = []
	centre_profile = {}
	ui = {}
	content_version = ""
	if root == "":
		error = "Content not found. Run: ./run.sh content"
		push_warning(error)
		return
	error = ""
	var d = _read_json(root.path_join("build/lines.json"))
	if d is Dictionary:
		lines = d.get("lines", {})
		categories = d.get("categories", {})
	var idx = _read_json(root.path_join("build/index.json"))
	if idx is Dictionary:
		content_version = str(idx.get("content_version", ""))
		for gid in idx.get("games", []):
			var g = _read_json(root.path_join("build/games/%s.json" % gid))
			if g is Dictionary:
				games[gid] = g
		for sid in idx.get("sessions", []):
			var sd = _read_json(root.path_join("build/sessions/%s.json" % sid))
			if sd is Dictionary:
				sessions[sid] = sd
	var s = _read_json(root.path_join("build/session.json"))
	if s is Dictionary:
		session.merge(s, true)
	var cur = _read_json(root.path_join("build/curriculum.json"))
	if cur is Dictionary:
		weeks = cur.get("weeks", [])
	var cp = _read_json(root.path_join("build/centre_profile.json"))
	if cp is Dictionary:
		centre_profile = cp
	var u = _read_json(root.path_join("build/ui.json"))
	if u is Dictionary:
		ui = u
	print("[content] %s: %d lines, %d games, %d sessions, %d weeks (version %s)" % [
		root, lines.size(), games.size(), sessions.size(), weeks.size(), content_version])


func _find_root() -> String:
	var cands: Array = []
	if Settings.content_dir != "":
		cands.append(Settings.content_dir)
	cands.append(OS.get_executable_path().get_base_dir().path_join("content"))
	cands.append(ProjectSettings.globalize_path("res://").path_join("../content").simplify_path())
	for c in cands:
		if FileAccess.file_exists(str(c).path_join("build/lines.json")):
			return str(c)
	return ""


func _read_json(path: String):
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	return JSON.parse_string(f.get_as_text())


# ---- lines -------------------------------------------------------------------

func has_line(line_id: String) -> bool:
	return lines.has(line_id)


func variants(line_id: String) -> Array:
	if not lines.has(line_id):
		return []
	return lines[line_id].get("variants", [])


func pick_variant(line_id: String) -> Dictionary:
	var vs := variants(line_id)
	if vs.is_empty():
		return {}
	return vs[randi() % vs.size()]


func uses_name(line_id: String) -> bool:
	return lines.has(line_id) and bool(lines[line_id].get("uses_name", false))


## first-variant text, for on-screen display
func text(line_id: String, lang: String) -> String:
	var vs := variants(line_id)
	if vs.is_empty():
		return line_id
	return str(vs[0].get("text", {}).get(lang, line_id))


func voice_path(variant: Dictionary, lang: String) -> String:
	var rel := str(variant.get("audio", {}).get(lang, ""))
	if rel == "" or root == "":
		return ""
	return root.path_join(rel)


func lines_in(category: String, prefix := "") -> Array:
	var out: Array = []
	for lid in categories.get(category, []):
		if prefix == "" or str(lid).begins_with(prefix):
			out.append(lid)
	return out


func game(game_id: String) -> Dictionary:
	return games.get(game_id, {})


func session_def(session_id: String) -> Dictionary:
	return sessions.get(session_id, {})


## week entry from curriculum/weeks.yaml, {} if there is no such week
func week(n: int) -> Dictionary:
	for w in weeks:
		if int(w.get("week", -1)) == n:
			return w
	return {}


func week_numbers() -> Array:
	var out: Array = []
	for w in weeks:
		out.append(int(w.get("week", 0)))
	return out


## on-screen worker/supervisor text (ui/strings.yaml); the key itself if missing
func ui_text(key: String, lang: String) -> String:
	var e = ui.get(key, null)
	if e is Dictionary and str(e.get(lang, "")) != "":
		return str(e[lang])
	return key


## parent-recorded child name clip (local only, deletable). Disabled in field builds:
## the anganwadi kit keeps no identity of any child.
func name_clip_path() -> String:
	if root == "" or Settings.is_field():
		return ""
	var p := root.path_join("names/child.ogg")
	return p if FileAccess.file_exists(p) else ""
