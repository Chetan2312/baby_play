extends Node2D
## Root scene. Builds the persistent layers in code, hands them to GameManager.
##
##   CameraLayer        (world)     camera feed
##   GameRoot           (world)     current game / attract / finish node
##   PlayerAvatar       (world)     hand sparkles, glow, hit areas
##   UI      CanvasLayer 5          TV-safe MarginContainer → GameUI (games add Controls)
##   Mascot  CanvasLayer 6
##   Praise  CanvasLayer 7          stars, confetti, word card
##   Overlay CanvasLayer 10         getting-ready screen, errors, toasts, debug

const CameraLayerScript = preload("res://core/CameraLayer.gd")
const PlayerAvatarScript = preload("res://core/PlayerAvatar.gd")
const MascotScript = preload("res://core/Mascot.gd")
const PraiseBurstScript = preload("res://core/PraiseBurst.gd")
const StatusOverlayScript = preload("res://scenes/StatusOverlay.gd")
const UiKit = preload("res://core/UiKit.gd")
const SAFE_MARGIN := 0.05

var _safe: MarginContainer


func _ready() -> void:
	var cam := CameraLayerScript.new()
	cam.name = "CameraLayer"
	add_child(cam)

	var game_root := Node2D.new()
	game_root.name = "GameRoot"
	add_child(game_root)

	var avatar := PlayerAvatarScript.new()
	avatar.name = "PlayerAvatar"
	add_child(avatar)

	var ui_layer := CanvasLayer.new()
	ui_layer.layer = 5
	add_child(ui_layer)
	_safe = MarginContainer.new()
	UiKit.full_rect(_safe)
	ui_layer.add_child(_safe)
	var game_ui := Control.new()
	game_ui.name = "GameUI"
	game_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_safe.add_child(game_ui)

	var mascot_layer := CanvasLayer.new()
	mascot_layer.layer = 6
	add_child(mascot_layer)
	var mascot := MascotScript.new()
	mascot.name = "Mascot"
	mascot_layer.add_child(mascot)

	var praise_layer := CanvasLayer.new()
	praise_layer.layer = 7
	add_child(praise_layer)
	var praise := PraiseBurstScript.new()
	praise.name = "PraiseBurst"
	praise_layer.add_child(praise)

	var overlay_layer := CanvasLayer.new()
	overlay_layer.layer = 10
	add_child(overlay_layer)
	var overlay := StatusOverlayScript.new()
	overlay.name = "StatusOverlay"
	overlay_layer.add_child(overlay)

	get_viewport().size_changed.connect(_apply_safe_margins)
	_apply_safe_margins()

	GameManager.attach(self, {"camera": cam, "game_root": game_root, "game_ui": game_ui,
		"avatar": avatar, "mascot": mascot, "praise": praise, "overlay": overlay})
	GameManager.boot()


## 5% margins: TVs overscan, projectors keystone.
func _apply_safe_margins() -> void:
	var v := get_viewport().get_visible_rect().size
	var mx := int(v.x * SAFE_MARGIN)
	var my := int(v.y * SAFE_MARGIN)
	_safe.add_theme_constant_override("margin_left", mx)
	_safe.add_theme_constant_override("margin_right", mx)
	_safe.add_theme_constant_override("margin_top", my)
	_safe.add_theme_constant_override("margin_bottom", my)
