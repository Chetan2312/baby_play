extends Node
## Session stats → user://stats/session_<time>.json. Outcomes only: no images, no audio.

const DIR := "user://stats"

var session := {}
var _path := ""


func start_session(meta: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var stamp := Time.get_datetime_string_from_system().replace(":", "").replace("-", "")
	_path = "%s/session_%s.json" % [DIR, stamp]
	session = {"started": Time.get_datetime_string_from_system(), "games": []}
	session.merge(meta)
	_write()


func record_round(game_id: String, data: Dictionary) -> void:
	if session.is_empty():
		return
	var g := _game_entry(game_id)
	var row := {"t": Time.get_datetime_string_from_system()}
	row.merge(data)
	g["rounds"].append(row)
	_write()


func end_game(game_id: String, result: Dictionary) -> void:
	if session.is_empty():
		return
	var g := _game_entry(game_id)
	g["result"] = result
	_write()


func end_session(summary: Dictionary = {}) -> void:
	if session.is_empty():
		return
	session["ended"] = Time.get_datetime_string_from_system()
	session.merge(summary, true)
	_write()
	session = {}


func _game_entry(game_id: String) -> Dictionary:
	var games: Array = session["games"]
	if games.is_empty() or games[-1]["game"] != game_id or games[-1].has("result"):
		games.append({"game": game_id, "rounds": []})
	return games[-1]


func _write() -> void:
	var f := FileAccess.open(_path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(session, " "))
