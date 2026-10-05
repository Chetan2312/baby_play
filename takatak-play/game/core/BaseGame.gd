extends Node2D
## Game interface. Every game scene's root script extends this file:
##     extends "res://core/BaseGame.gd"
## GameManager reads the export flags to subscribe to vision data and routes
## vision signals to the on_* methods. Games never touch the WebSocket or raw keys.
##
## SessionDirector runs games for a fixed time: when the step's time is up it calls
## request_finish(); the game finishes at its next round boundary (never mid-round).
## "repeat" on the remote calls repeat_prompt().
##
## Shared services: AudioDirector (voice/sfx), GameManager.mascot, GameManager.praise,
## GameManager.game_ui (full-screen Control inside TV-safe margins; cleared between games).

signal finished(result: Dictionary)   # {rounds, successes, duration_s, events: []}

@export var game_id := ""
@export var needs_frames := true
@export var needs_mask := false
@export var needs_mic := false
@export var motions: PackedStringArray = []
@export var camera_mode := "mirror"   # mirror | cutout | hidden
@export var movement := true          # counts towards movement_minutes (usage counters)

var config: Dictionary = {}
var paused := false
var started_ms := 0
var finish_requested := false


func setup(cfg: Dictionary) -> void:
	config = cfg


func start() -> void:
	started_ms = Time.get_ticks_msec()


func on_pose(_people: Array) -> void:
	pass


func on_gesture(_player: int, _gname: String, _state: String, _conf: float) -> void:
	pass


func on_motion(_player: int, _mname: String, _conf: float, _count: int) -> void:
	pass


func on_loudness(_db: float, _speaking: bool) -> void:
	pass


func on_no_player(_seconds: float) -> void:
	pass


func pause() -> void:
	paused = true


func resume() -> void:
	paused = false


## Dev key (X): skip the current round.
func skip() -> void:
	pass


## The session step's time is up: finish at the next round boundary.
func request_finish() -> void:
	finish_requested = true


## Remote "repeat" (Page Up): say the current prompt again.
func repeat_prompt() -> void:
	pass


func duration_s() -> float:
	return (Time.get_ticks_msec() - started_ms) / 1000.0


func finish(result: Dictionary) -> void:
	result["duration_s"] = duration_s()
	result["movement"] = movement
	finished.emit(result)
