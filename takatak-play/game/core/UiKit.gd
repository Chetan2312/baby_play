extends RefCounted
## Shared UI helpers. Use with:  const UiKit = preload("res://core/UiKit.gd")
## Fonts: Noto Sans with Noto Sans Devanagari as fallback (system fonts, installed by
## install.sh as fonts-noto-core). Godot's HarfBuzz shaping handles conjuncts/matras.

const LANG_COLORS := {
	"mr": Color(1.0, 0.88, 0.35),
	"hi": Color(0.55, 0.9, 1.0),
	"en": Color(1.0, 1.0, 1.0),
}
const GOLD := Color(1.0, 0.8, 0.16)
const OUTLINE := Color(0.08, 0.06, 0.16)

static var _fonts: Dictionary = {}


static func font(weight := 700) -> Font:
	if _fonts.has(weight):
		return _fonts[weight]
	var deva := SystemFont.new()
	deva.font_names = PackedStringArray(["Noto Sans Devanagari", "Noto Sans Devanagari UI", "Lohit Devanagari", "Mukta"])
	deva.font_weight = weight
	var base := SystemFont.new()
	base.font_names = PackedStringArray(["Noto Sans", "Noto Sans UI", "DejaVu Sans", "sans-serif"])
	base.font_weight = weight
	var fb: Array[Font] = [deva]
	base.fallbacks = fb
	_fonts[weight] = base
	return base


static func lang_color(lang: String) -> Color:
	return LANG_COLORS.get(lang, Color.WHITE)


static func label(text: String, size: int, color := Color.WHITE, outline := -1) -> Label:
	var l := Label.new()
	l.text = text
	var ls := LabelSettings.new()
	ls.font = font()
	ls.font_size = size
	ls.font_color = color
	ls.outline_size = outline if outline >= 0 else maxi(4, size / 8)
	ls.outline_color = OUTLINE
	l.label_settings = ls
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## rows: [[text, size, color], ...] stacked in a rounded translucent panel
static func card(rows: Array, alpha := 0.55) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, alpha)
	sb.set_corner_radius_all(32)
	sb.content_margin_left = 40
	sb.content_margin_right = 40
	sb.content_margin_top = 18
	sb.content_margin_bottom = 22
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(v)
	for r in rows:
		v.add_child(label(str(r[0]), int(r[1]), r[2]))
	return p


## Rows for one line in several languages; the first language is biggest.
static func line_rows(line_id: String, langs: Array, size := 84) -> Array:
	var rows: Array = []
	for i in langs.size():
		var lang: String = langs[i]
		rows.append([ContentDB.text(line_id, lang), size if i == 0 else int(size * 0.75), lang_color(lang)])
	return rows


## Rows for a UI string (ui/strings.yaml): Marathi big, English smaller.
static func ui_rows(key: String, size := 60, color := Color.WHITE) -> Array:
	return [[ContentDB.ui_text(key, "mr"), size, color], [ContentDB.ui_text(key, "en"), int(size * 0.7), color.darkened(0.15)]]


## "मराठी / English" on one line
static func ui_both(key: String) -> String:
	return "%s / %s" % [ContentDB.ui_text(key, "mr"), ContentDB.ui_text(key, "en")]


static func full_rect(c: Control) -> Control:
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## Adds `child` horizontally centred at the top of `parent` (a full-rect Control).
static func top_center(parent: Control, child: Control) -> Control:
	var v := VBoxContainer.new()
	full_rect(v)
	parent.add_child(v)
	var c := CenterContainer.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(child)
	v.add_child(c)
	return v


## Adds `child` centred in `parent`.
static func center(parent: Control, child: Control) -> Control:
	var c := CenterContainer.new()
	full_rect(c)
	parent.add_child(c)
	c.add_child(child)
	return c


## Adds `child` centred at the bottom of `parent`.
static func bottom_center(parent: Control, child: Control) -> Control:
	var v := VBoxContainer.new()
	full_rect(v)
	v.alignment = BoxContainer.ALIGNMENT_END
	parent.add_child(v)
	var c := CenterContainer.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(child)
	v.add_child(c)
	return v


static func star_points(center: Vector2, r: float, rot := 0.0, inner := 0.45) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 10:
		var rr := r if i % 2 == 0 else r * inner
		var a := rot + i * PI / 5.0 - PI / 2.0
		pts.append(center + Vector2(cos(a), sin(a)) * rr)
	return pts
