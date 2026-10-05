extends Node
## One-button worker control. Every input becomes an action for the topmost handler
## (SessionDirector by default; the supervisor menu while it is open). Games never
## read raw keys.
##
##   action      USB presenter remote (= keyboard)   GPIO button (vision "button")
##   next        Page Down                           short press (< 2 s)
##   prev        Page Up
##   select      F5 / Shift+F5 / Enter
##   back        B / . / Esc (on release)
##   long                                            held 2–5 s
##   supervisor  back held 5 s, or tapped 5× in 4 s  held 5 s
##
## Session meaning: next/select = start / next step · prev = repeat the prompt ·
## back/long = stop. Menus: next/prev = move · select/long = OK · back = back.
## Dev builds also map Space/→ to next and ← to prev.

signal action(action_name: String)

const LONG_S := 2.0
const SUPERVISOR_HOLD_S := 5.0
const TAPS_FOR_SUPERVISOR := 5
const TAP_WINDOW_S := 4.0

var _handlers: Array = []
var _back_down := -1.0
var _back_sup := false
var _gpio_down := -1.0
var _gpio_sup := false
var _taps: Array = []


func _ready() -> void:
	VisionClient.button.connect(_on_gpio)


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func push_handler(h: Object) -> void:
	_handlers.erase(h)
	_handlers.append(h)


func pop_handler(h: Object) -> void:
	_handlers.erase(h)


func fire(action_name: String) -> void:
	print("[input] ", action_name)
	action.emit(action_name)
	for i in range(_handlers.size() - 1, -1, -1):
		var h = _handlers[i]
		if is_instance_valid(h):
			h.on_action(action_name)
			return


func _input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or k.echo:
		return
	var handled := true
	match k.keycode:
		KEY_PAGEDOWN:
			if k.pressed:
				fire("next")
		KEY_PAGEUP:
			if k.pressed:
				fire("prev")
		KEY_F5, KEY_ENTER, KEY_KP_ENTER:
			if k.pressed:
				fire("select")
		KEY_B, KEY_PERIOD, KEY_ESCAPE:
			_back_key(k.pressed)
		KEY_SPACE, KEY_RIGHT:
			if Settings.is_dev() and k.pressed:
				fire("next")
			handled = Settings.is_dev()
		KEY_LEFT:
			if Settings.is_dev() and k.pressed:
				fire("prev")
			handled = Settings.is_dev()
		_:
			handled = false
	if handled:
		get_viewport().set_input_as_handled()


func _back_key(pressed: bool) -> void:
	if pressed:
		if _back_down < 0.0:
			_back_down = _now()
			_back_sup = false
		return
	if _back_down < 0.0:
		return
	_back_down = -1.0
	if _back_sup:
		return
	fire("back")
	var now := _now()
	_taps.append(now)
	while not _taps.is_empty() and now - float(_taps[0]) > TAP_WINDOW_S:
		_taps.pop_front()
	if _taps.size() >= TAPS_FOR_SUPERVISOR:
		_taps.clear()
		fire("supervisor")


func _on_gpio(state: String) -> void:
	if state == "down":
		_gpio_down = _now()
		_gpio_sup = false
	elif state == "up" and _gpio_down >= 0.0:
		var held := _now() - _gpio_down
		_gpio_down = -1.0
		if _gpio_sup:
			return
		fire("next" if held < LONG_S else "long")


func _process(_delta: float) -> void:
	var now := _now()
	if _back_down >= 0.0 and not _back_sup and now - _back_down >= SUPERVISOR_HOLD_S:
		_back_sup = true
		fire("supervisor")
	if _gpio_down >= 0.0 and not _gpio_sup and now - _gpio_down >= SUPERVISOR_HOLD_S:
		_gpio_sup = true
		fire("supervisor")
