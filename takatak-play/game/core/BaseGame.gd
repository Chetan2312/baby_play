extends Node2D
## Game interface. Every game scene's root script extends this file:
##     extends "res://core/BaseGame.gd"
## GameManager reads the export flags to subscribe to vision data and routes
## vision signals to the on_* methods. Games never touch the WebSocket.
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

var config: Dictionary = {}
var paused := false
var started_ms := 0


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


## Tester key (Space): skip the current round.
func skip() -> void:
	pass


func duration_s() -> float:
	return (Time.get_ticks_msec() - started_ms) / 1000.0


func finish(result: Dictionary) -> void:
	result["duration_s"] = duration_s()
	finished.emit(result)
