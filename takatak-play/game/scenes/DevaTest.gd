extends Node2D
## P2 check: Devanagari shaping (conjuncts, matras) on the real TV.
## Open with --deva-test or F2. Everything here must look correctly joined:
## no dotted circles, no detached matras, conjuncts (क्य, घ्यां, ब्बा) fused.

const UiKit = preload("res://core/UiKit.gd")
const SAMPLES := [["डोक्याला", "mr"], ["गुडघ्यांना", "mr"], ["शाब्बास", "mr"], ["खांद्यावर", "mr"],
	["नाकाला हात लाव!", "mr"], ["बायाँ हाथ ऊपर करो!", "hi"], ["कंधों", "hi"], ["शाबाश!", "hi"],
	["Touch your nose!", "en"]]


func _ready() -> void:
	var grid := VBoxContainer.new()
	grid.add_theme_constant_override("separation", 0)
	for sample in SAMPLES:
		grid.add_child(UiKit.label(str(sample[0]), 74, UiKit.lang_color(str(sample[1]))))
	var info := "F2 = back · content: %s · lines: %d" % [ContentDB.root if ContentDB.root != "" else "NOT FOUND", ContentDB.lines.size()]
	grid.add_child(UiKit.label(info, 26, Color(0.8, 0.8, 0.9), 4))
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.09, 0.19, 0.85)
	UiKit.full_rect(bg)
	GameManager.game_ui.add_child(bg)
	UiKit.center(GameManager.game_ui, grid)
	GameManager.mascot.play("think", 999.0)
	_play_all()


## Speak one line per language so HDMI audio can be checked too.
func _play_all() -> void:
	for lid in ["simon_head", "simon_knees", "praise_01"]:
		for lang in Settings.LANGS:
			if not is_inside_tree():
				return
			await AudioDirector.say(lid, [lang])
