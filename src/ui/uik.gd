class_name UIK
extends RefCounted
## UI kit: theme and widget helpers (all UI is built in code).

const GOLD := Color(0.86, 0.68, 0.36)
const TEXT := Color(0.9, 0.86, 0.78)
const DIM := Color(0.62, 0.58, 0.52)
const BG := Color(0.07, 0.065, 0.06, 0.94)
const BG2 := Color(0.12, 0.105, 0.09, 0.96)
const RED := Color(0.85, 0.28, 0.22)
const GREEN := Color(0.45, 0.8, 0.4)
const BLUE := Color(0.4, 0.62, 0.95)
const CAT_COLORS := {"weapon": Color(0.75, 0.35, 0.25), "armor": Color(0.45, 0.5, 0.65), "ammo": Color(0.6, 0.55, 0.35),
	"tool": Color(0.55, 0.45, 0.3), "saddle": Color(0.5, 0.35, 0.2), "consumable": Color(0.35, 0.65, 0.4), "food": Color(0.7, 0.5, 0.25),
	"essence": Color(0.65, 0.3, 0.7), "rune": Color(0.35, 0.55, 0.85), "material": Color(0.45, 0.42, 0.38), "trap": Color(0.5, 0.5, 0.3),
	"special": Color(0.85, 0.7, 0.3), "quest": Color(0.9, 0.8, 0.4)}

static var theme: Theme


static func get_theme() -> Theme:
	if theme:
		return theme
	theme = Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Georgia", "Palatino Linotype", "DejaVu Serif", "Liberation Serif", "serif"])
	theme.default_font = font
	theme.default_font_size = 17
	var sb := StyleBoxFlat.new()
	sb.bg_color = BG
	sb.border_color = Color(0.45, 0.36, 0.22)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(12)
	sb.shadow_size = 8
	sb.shadow_color = Color(0, 0, 0, 0.5)
	theme.set_stylebox("panel", "PanelContainer", sb)
	theme.set_stylebox("panel", "Panel", sb)
	var b := StyleBoxFlat.new()
	b.bg_color = Color(0.17, 0.145, 0.115)
	b.border_color = Color(0.4, 0.32, 0.2)
	b.set_border_width_all(1)
	b.set_corner_radius_all(3)
	b.set_content_margin_all(6)
	var bh := b.duplicate()
	bh.bg_color = Color(0.27, 0.21, 0.14)
	bh.border_color = GOLD
	var bp := b.duplicate()
	bp.bg_color = Color(0.35, 0.26, 0.15)
	var bd := b.duplicate()
	bd.bg_color = Color(0.1, 0.09, 0.08)
	bd.border_color = Color(0.2, 0.18, 0.15)
	theme.set_stylebox("normal", "Button", b)
	theme.set_stylebox("hover", "Button", bh)
	theme.set_stylebox("pressed", "Button", bp)
	theme.set_stylebox("disabled", "Button", bd)
	theme.set_stylebox("focus", "Button", bh)
	theme.set_color("font_color", "Button", TEXT)
	theme.set_color("font_hover_color", "Button", Color(1, 0.92, 0.75))
	theme.set_color("font_disabled_color", "Button", Color(0.45, 0.42, 0.38))
	theme.set_color("font_color", "Label", TEXT)
	theme.set_color("default_color", "RichTextLabel", TEXT)
	var le := b.duplicate()
	le.bg_color = Color(0.05, 0.045, 0.04)
	theme.set_stylebox("normal", "LineEdit", le)
	theme.set_stylebox("focus", "LineEdit", bh)
	theme.set_color("font_color", "LineEdit", TEXT)
	var tab_sel := b.duplicate()
	tab_sel.bg_color = Color(0.3, 0.22, 0.13)
	tab_sel.border_color = GOLD
	theme.set_stylebox("tab_selected", "TabBar", tab_sel)
	theme.set_stylebox("tab_unselected", "TabBar", b)
	theme.set_stylebox("tab_hovered", "TabBar", bh)
	theme.set_stylebox("tab_selected", "TabContainer", tab_sel)
	theme.set_stylebox("tab_unselected", "TabContainer", b)
	theme.set_stylebox("tab_hovered", "TabContainer", bh)
	var pan2 := sb.duplicate()
	pan2.bg_color = BG2
	pan2.set_border_width_all(1)
	pan2.shadow_size = 0
	theme.set_stylebox("panel", "TabContainer", pan2)
	theme.set_color("font_selected_color", "TabContainer", Color(1, 0.9, 0.7))
	theme.set_color("font_unselected_color", "TabContainer", DIM)
	var pbg := StyleBoxFlat.new()
	pbg.bg_color = Color(0.05, 0.05, 0.05, 0.8)
	pbg.set_corner_radius_all(2)
	theme.set_stylebox("background", "ProgressBar", pbg)
	var tt := sb.duplicate()
	tt.set_content_margin_all(8)
	theme.set_stylebox("panel", "TooltipPanel", tt)
	theme.set_color("font_color", "TooltipLabel", TEXT)
	return theme


static func label(text: String, size: int = 17, col: Color = TEXT, wrap: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


static func title(text: String) -> Label:
	var l := label(text, 26, GOLD)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	l.add_theme_constant_override("outline_size", 4)
	return l


static func rich(text: String, size: int = 16) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.text = text
	r.add_theme_font_size_override("normal_font_size", size)
	r.add_theme_font_size_override("bold_font_size", size)
	r.custom_minimum_size = Vector2(200, 0)
	return r


static func button(text: String, cb: Callable, tip: String = "", min_w: float = 0.0) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.custom_minimum_size = Vector2(min_w, 34)
	if cb.is_valid():
		b.pressed.connect(func():
			Audio.play_ui("ui_click")
			cb.call())
	b.focus_mode = Control.FOCUS_NONE
	return b


static func vbox(sep: int = 6) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func hbox(sep: int = 6) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


static func scroll(min_size: Vector2 = Vector2(300, 300)) -> Array:
	## returns [ScrollContainer, VBoxContainer]
	var s := ScrollContainer.new()
	s.custom_minimum_size = min_size
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := vbox(4)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.add_child(v)
	return [s, v]


static func bar(col: Color, w: float = 200.0, h: float = 14.0) -> ProgressBar:
	var p := ProgressBar.new()
	p.custom_minimum_size = Vector2(w, h)
	p.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = col
	fill.set_corner_radius_all(2)
	p.add_theme_stylebox_override("fill", fill)
	p.max_value = 100
	return p


static func sep() -> HSeparator:
	var s := HSeparator.new()
	s.add_theme_constant_override("separation", 8)
	return s


static func clear(n: Node) -> void:
	for c in n.get_children():
		n.remove_child(c)
		c.queue_free()


static func item_badge(item_id: String, size: float = 34.0) -> Control:
	var it := DB.item(item_id)
	var cat: String = it.get("cat", "material")
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = CAT_COLORS.get(cat, Color(0.4, 0.4, 0.4)).darkened(0.35)
	sb.border_color = CAT_COLORS.get(cat, Color(0.4, 0.4, 0.4))
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size = Vector2(size, size)
	var l := Label.new()
	var nm: String = it.get("name", item_id)
	var words := nm.split(" ")
	l.text = (words[0].substr(0, 2) if words.size() == 1 else words[0].substr(0, 1) + words[-1].substr(0, 1)).to_upper()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", int(size * 0.38))
	p.add_child(l)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


static func item_tooltip(st: Dictionary) -> String:
	var it := DB.item(st["id"])
	var lines := [Inventory.display_name(st)]
	if it.get("cat", "") in ["weapon", "armor", "tool"]:
		lines.append("Qualität: " + Inventory.quality_label(float(st.get("q", 1.0))))
	if it.get("desc", "") != "":
		lines.append(it["desc"])
	var stats := Inventory.stats_of(st)
	var names := {"dmg": "Schaden", "armor": "Rüstung", "torpor": "Betäubung", "reach": "Reichweite", "block": "Blocken", "spell_power": "Zauberkraft", "cold": "Kälteschutz", "harvest_wood": "Holzertrag", "harvest_stone": "Steinertrag"}
	for k in names:
		if stats.has(k) and float(stats[k]) != 0.0:
			lines.append("%s: %.1f" % [names[k], float(stats[k])])
	if stats.has("element"):
		lines.append("Element: " + DB.element(stats["element"]).get("name", ""))
	if it.has("food"):
		lines.append("Nahrung: +%d" % it["food"])
	if it.has("heal"):
		lines.append("Heilung: +%d" % it["heal"])
	lines.append("Gewicht: %.1f kg   Wert: %d Bernstein" % [float(it.get("weight", 0.5)), int(it.get("value", 1))])
	return "\n".join(lines)


static func center_window(c: Control) -> void:
	c.set_anchors_preset(Control.PRESET_CENTER)
	c.grow_horizontal = Control.GROW_DIRECTION_BOTH
	c.grow_vertical = Control.GROW_DIRECTION_BOTH


static func anchor(c: Control, ax: float, ay: float, ox: float, oy: float, w: float = 0.0, h: float = 0.0) -> void:
	c.anchor_left = ax
	c.anchor_right = ax
	c.anchor_top = ay
	c.anchor_bottom = ay
	c.offset_left = ox
	c.offset_top = oy
	c.offset_right = ox + w
	c.offset_bottom = oy + h
