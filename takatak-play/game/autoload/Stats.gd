extends Node
## Anonymous usage counters → <usage dir>/YYYY-MM.json, one entry per day:
##   {"date", "sessions", "minutes", "steps_completed": {step: n},
##    "games": {game: {"rounds", "successes"}}, "movement_minutes", "uptime_minutes",
##    "faults": [{"name", "count"}], "cap_override"}
## Counts only. No images, no audio, no names, nothing per child: "successes" are per
## round, not per child.
## Best scores (whole class, all time) → <usage dir>/bests.json: {"lane_dash:endless": 42}.
##
## Usage dir: --usage-dir=PATH, else /var/lib/takatak/usage when writable (install.sh
## creates it), else user://usage. Clock before MIN_VALID_YEAR (no RTC battery, no
## network) → counters go to date-unknown.json and the daily cap counts since boot.

const MIN_VALID_YEAR := 2026
const SYSTEM_DIR := "/var/lib/takatak/usage"
const FALLBACK_DIR := "user://usage"
const UNKNOWN := "date-unknown"
const HOT_C := 80.0

var dir := ""
var _month_key := ""
var _month := {}
var _session_start_ms := -1
var _boot := {"sessions": 0, "minutes": 0.0, "cap_override": false}
var _uptime_s := 0.0
var _was_connected := false
var _had_errors := false
var _hot := false


func _ready() -> void:
	dir = _pick_dir()
	print("[usage] counters in %s (clock %s)" % [dir, "ok" if clock_ok() else "UNKNOWN"])
	VisionClient.connected_changed.connect(_on_vision_connected)
	VisionClient.status_received.connect(_on_vision_status)


func _pick_dir() -> String:
	if Settings.usage_dir != "":
		DirAccess.make_dir_recursive_absolute(Settings.usage_dir)
		return Settings.usage_dir
	if DirAccess.dir_exists_absolute(SYSTEM_DIR):
		var probe := SYSTEM_DIR.path_join(".write_test")
		var f := FileAccess.open(probe, FileAccess.WRITE)
		if f != null:
			f.close()
			DirAccess.remove_absolute(probe)
			return SYSTEM_DIR
	DirAccess.make_dir_recursive_absolute(FALLBACK_DIR)
	return FALLBACK_DIR


# ---- dates ---------------------------------------------------------------------

func clock_ok() -> bool:
	return int(Time.get_date_dict_from_system().get("year", 0)) >= MIN_VALID_YEAR


func today() -> String:
	return Time.get_date_string_from_system() if clock_ok() else UNKNOWN


func _month_of(day: String) -> String:
	return UNKNOWN if day == UNKNOWN else day.substr(0, 7)


func _path(month_key: String) -> String:
	return dir.path_join(month_key + ".json")


func _load_month(month_key: String) -> void:
	if month_key == _month_key:
		return
	_month_key = month_key
	_month = {"month": month_key, "days": {}}
	var p := _path(month_key)
	if FileAccess.file_exists(p):
		var f := FileAccess.open(p, FileAccess.READ)
		var d = JSON.parse_string(f.get_as_text()) if f != null else null
		if d is Dictionary and d.get("days") is Dictionary:
			_month = d


func day_entry(day := "") -> Dictionary:
	if day == "":
		day = today()
	_load_month(_month_of(day))
	var days: Dictionary = _month["days"]
	if not days.has(day):
		days[day] = {"date": day, "sessions": 0, "minutes": 0.0, "steps_completed": {}, "games": {},
			"movement_minutes": 0.0, "uptime_minutes": 0, "faults": [], "cap_override": false}
	return days[day]


func _save() -> void:
	if _month_key == "":
		return
	var p := _path(_month_key)
	var tmp := p + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_warning("usage: cannot write " + p)
		return
	f.store_string(JSON.stringify(_month, " "))
	f.close()
	DirAccess.rename_absolute(tmp, p)


# ---- counters ------------------------------------------------------------------

func start_session(_meta := {}) -> void:
	_session_start_ms = Time.get_ticks_msec()


func end_session(_summary := {}) -> void:
	if _session_start_ms < 0:
		return
	var minutes := (Time.get_ticks_msec() - _session_start_ms) / 60000.0
	_session_start_ms = -1
	var e := day_entry()
	e["sessions"] = int(e["sessions"]) + 1
	e["minutes"] = snappedf(float(e["minutes"]) + minutes, 0.1)
	_boot["sessions"] += 1
	_boot["minutes"] += minutes
	_save()


func step_completed(step_id: String) -> void:
	var steps: Dictionary = day_entry()["steps_completed"]
	steps[step_id] = int(steps.get(step_id, 0)) + 1
	_save()


## One round of a game. Only the outcome counts: data["result"] == "success".
func record_round(game_id: String, data: Dictionary) -> void:
	var g := _game(game_id)
	g["rounds"] = int(g["rounds"]) + 1
	if str(data.get("result", "")) == "success":
		g["successes"] = int(g["successes"]) + 1
	_save()


func end_game(game_id: String, result: Dictionary) -> void:
	_game(game_id)
	if bool(result.get("movement", true)):
		var e := day_entry()
		e["movement_minutes"] = snappedf(float(e["movement_minutes"]) + float(result.get("duration_s", 0.0)) / 60.0, 0.1)
	_save()


## Class best score for key (e.g. "lane_dash:endless"); 0 when none yet.
func best(key: String) -> int:
	return int(_load_bests().get(key, 0))


## Records score as the new best when it beats the old one; true = new best.
func submit_best(key: String, score: int) -> bool:
	var bests := _load_bests()
	if score <= int(bests.get(key, 0)):
		return false
	bests[key] = score
	var p := dir.path_join("bests.json")
	var f := FileAccess.open(p + ".tmp", FileAccess.WRITE)
	if f == null:
		push_warning("usage: cannot write " + p)
		return true
	f.store_string(JSON.stringify(bests, " "))
	f.close()
	DirAccess.rename_absolute(p + ".tmp", p)
	return true


func _load_bests() -> Dictionary:
	var p := dir.path_join("bests.json")
	if not FileAccess.file_exists(p):
		return {}
	var f := FileAccess.open(p, FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text()) if f != null else null
	return d if d is Dictionary else {}


func fault(fault_name: String) -> void:
	print("[usage] fault ", fault_name)
	var faults: Array = day_entry()["faults"]
	for f in faults:
		if f.get("name", "") == fault_name:
			f["count"] = int(f.get("count", 0)) + 1
			_save()
			return
	faults.append({"name": fault_name, "count": 1})
	_save()


func _game(game_id: String) -> Dictionary:
	var games: Dictionary = day_entry()["games"]
	if not games.has(game_id):
		games[game_id] = {"rounds": 0, "successes": 0}
	return games[game_id]


func _process(delta: float) -> void:
	_uptime_s += delta
	if _uptime_s >= 60.0:
		_uptime_s -= 60.0
		var e := day_entry()
		e["uptime_minutes"] = int(e["uptime_minutes"]) + 1
		_save()


func _on_vision_connected(connected: bool) -> void:
	if connected:
		_was_connected = true
	elif _was_connected:
		fault("vision_disconnected")


func _on_vision_status(info: Dictionary) -> void:
	var has_errors: bool = not (info.get("errors", []) as Array).is_empty()
	if has_errors and not _had_errors:
		fault("vision_error")
	_had_errors = has_errors
	var t = info.get("temp_c", null)
	if t != null:
		if float(t) >= HOT_C and not _hot:
			fault("overheat")
		_hot = float(t) >= HOT_C - 5.0 if _hot else float(t) >= HOT_C


# ---- daily cap -----------------------------------------------------------------

func sessions_today() -> int:
	return int(day_entry()["sessions"]) if clock_ok() else int(_boot["sessions"])


func minutes_today() -> float:
	return float(day_entry()["minutes"]) if clock_ok() else float(_boot["minutes"])


func cap_reached(max_sessions: int, max_minutes: int) -> bool:
	var overridden: bool = bool(day_entry()["cap_override"]) if clock_ok() else bool(_boot["cap_override"])
	if overridden:
		return false
	return sessions_today() >= max_sessions or minutes_today() >= max_minutes


## Supervisor menu: today only.
func override_cap_today() -> void:
	_boot["cap_override"] = true
	day_entry()["cap_override"] = true
	_save()


# ---- reading / export ----------------------------------------------------------

func month_totals() -> Dictionary:
	var out := {"sessions": 0, "minutes": 0.0, "movement_minutes": 0.0, "rounds": 0, "successes": 0}
	day_entry()   # loads the current month
	for e in (_month["days"] as Dictionary).values():
		_add_totals(out, e)
	return out


func day_totals() -> Dictionary:
	var out := {"sessions": 0, "minutes": 0.0, "movement_minutes": 0.0, "rounds": 0, "successes": 0}
	_add_totals(out, day_entry())
	return out


func _add_totals(out: Dictionary, e: Dictionary) -> void:
	out["sessions"] += int(e.get("sessions", 0))
	out["minutes"] += float(e.get("minutes", 0.0))
	out["movement_minutes"] += float(e.get("movement_minutes", 0.0))
	for g in (e.get("games", {}) as Dictionary).values():
		out["rounds"] += int(g.get("rounds", 0))
		out["successes"] += int(g.get("successes", 0))


## Every day in every month file as CSV rows: one "ALL" row per day, then one per game.
func to_csv() -> String:
	var rows := PackedStringArray(["date,game,sessions,minutes,movement_minutes,uptime_minutes,rounds,successes,faults"])
	var files: Array = []
	var d := DirAccess.open(dir)
	if d != null:
		for fn in d.get_files():
			if fn.ends_with(".json"):
				files.append(fn)
	files.sort()
	for fn in files:
		var f := FileAccess.open(dir.path_join(fn), FileAccess.READ)
		var m = JSON.parse_string(f.get_as_text()) if f != null else null
		if not (m is Dictionary and m.get("days") is Dictionary):
			continue
		var days: Array = (m["days"] as Dictionary).keys()
		days.sort()
		for day in days:
			var e: Dictionary = m["days"][day]
			var t := {"sessions": 0, "minutes": 0.0, "movement_minutes": 0.0, "rounds": 0, "successes": 0}
			_add_totals(t, e)
			var nf := 0
			for fl in e.get("faults", []):
				nf += int(fl.get("count", 0))
			rows.append("%s,ALL,%d,%.1f,%.1f,%d,%d,%d,%d" % [day, t["sessions"], t["minutes"], t["movement_minutes"],
				int(e.get("uptime_minutes", 0)), t["rounds"], t["successes"], nf])
			var games: Dictionary = e.get("games", {})
			for gid in games:
				rows.append("%s,%s,,,,,%d,%d," % [day, gid, int(games[gid].get("rounds", 0)), int(games[gid].get("successes", 0))])
	return "\n".join(rows) + "\n"


## Write the CSV to the first writable USB stick → its path, or "" if none was found.
func export_csv_to_usb() -> String:
	var user := OS.get_environment("USER")
	var bases: Array = ["/media/%s" % user, "/run/media/%s" % user, "/media", "/mnt"]
	for base in bases:
		var d := DirAccess.open(base)
		if d == null:
			continue
		for sub in d.get_directories():
			var target: String = str(base).path_join(sub).path_join("takatak_usage_%s.csv" % today())
			var f := FileAccess.open(target, FileAccess.WRITE)
			if f != null:
				f.store_string(to_csv())
				f.close()
				return target
	return ""
