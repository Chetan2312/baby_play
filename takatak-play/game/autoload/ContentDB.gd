extends Node
## Loads content/build/*.json (made by tools/content_build.py) from the content folder.
## The content folder lives OUTSIDE res:// so voice files can be updated without
## re-exporting. Search order: --content=PATH, <executable dir>/content, <project>/../content.

const SESSION_DEFAULTS := {
	"attract_detect_s": 1.0,
	"pause_after_s": 3.0,
	"resume_detect_s": 0.5,
	"abandon_s": 60.0,
	"finish_s": 7.0,
	"attract_repeat_s": 25.0,
	"sleep_after_s": 60.0,
	"language_gap_s": 0.3,
	"name_chance": 0.33,
	"duck_db": -12.0,
}

var root := ""
var lines := {}
var categories := {}
var games := {}
var session := SESSION_DEFAULTS.duplicate()
var error := ""


func _ready() -> void:
	reload()


func reload() -> void:
	root = _find_root()
	lines = {}
	categories = {}
	games = {}
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
		for gid in idx.get("games", []):
			var g = _read_json(root.path_join("build/games/%s.json" % gid))
			if g is Dictionary:
				games[gid] = g
	var s = _read_json(root.path_join("build/session.json"))
	if s is Dictionary:
		session.merge(s, true)
	print("[content] %s: %d lines, %d games" % [root, lines.size(), games.size()])


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


## parent-recorded child name clip (local only, deletable)
func name_clip_path() -> String:
	if root == "":
		return ""
	var p := root.path_join("names/child.ogg")
	return p if FileAccess.file_exists(p) else ""
