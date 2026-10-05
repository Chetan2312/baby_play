extends Node
## Per-centre profile: content/centre_profile.yaml (built by content_build.py) plus the
## supervisor menu's changes, kept on the device in user://centre_profile.json.
## Applies language mode, difficulty and session length to Settings.

const USER_PATH := "user://centre_profile.json"
const DEFAULTS := {
	"centre_name": "Demo Centre",
	"language_mode": "mr_first",
	"primary_language": "mr",
	"difficulty": "toddler",
	"landing": "picker",
	"session": "standard_v1",
	"session_minutes": 18,
	"slots": 3,
	"current_week": 3,
	"ai_literacy_enabled": true,
	"sponsor_branding": "none",
	"max_sessions_per_day": 2,
	"max_minutes_per_day": 40,
	"supervisor_pin": "1234",
}

var profile := {}
var _changes := {}


func _ready() -> void:
	reload()


func reload() -> void:
	profile = DEFAULTS.duplicate()
	profile.merge(ContentDB.centre_profile, true)
	_changes = {}
	if FileAccess.file_exists(USER_PATH):
		var f := FileAccess.open(USER_PATH, FileAccess.READ)
		var d = JSON.parse_string(f.get_as_text()) if f != null else null
		if d is Dictionary:
			_changes = d
			profile.merge(d, true)
	apply()


func apply() -> void:
	Settings.apply_centre(profile)


func value(key: String):
	return profile.get(key, DEFAULTS.get(key))


func int_value(key: String) -> int:
	return int(value(key))


func set_value(key: String, v) -> void:
	profile[key] = v
	_changes[key] = v
	var f := FileAccess.open(USER_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(_changes, " "))
	apply()


func week() -> int:
	var w := int_value("current_week")
	if ContentDB.week(w).is_empty() and not ContentDB.weeks.is_empty():
		return int(ContentDB.weeks[0].get("week", 1))
	return w
