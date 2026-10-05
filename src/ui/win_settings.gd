class_name WinSettings
extends UIWindow
## Graphics, audio, controls (incl. key rebinding) and gameplay options.

var tab := "graphics"
var box: VBoxContainer
var waiting_action := ""


func _init() -> void:
	super._init("Einstellungen", Vector2(980, 720))
	window_id = "settings"
	var tabs := UIK.hbox(6)
	content.add_child(tabs)
	for t in [["Grafik", "graphics"], ["Audio", "audio"], ["Steuerung", "controls"], ["Tastenbelegung", "keys"], ["Spiel", "game"]]:
		tabs.add_child(UIK.button(t[0], func():
			tab = t[1]
			refresh()))
	var sc := UIK.scroll(Vector2(940, 600))
	content.add_child(sc[0])
	box = sc[1]


func _slider(label: String, key: String, mn: float, mx: float, step: float, apply_now: bool = true) -> void:
	var row := UIK.hbox(8)
	var l := UIK.label(label, 15)
	l.custom_minimum_size = Vector2(260, 0)
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = mn
	s.max_value = mx
	s.step = step
	s.value = float(Settings.get_v(key))
	s.custom_minimum_size = Vector2(360, 24)
	var vl := UIK.label("%.2f" % s.value, 15, UIK.DIM)
	s.value_changed.connect(func(v):
		vl.text = "%.2f" % v
		Settings.set_v(key, v, apply_now))
	row.add_child(s)
	row.add_child(vl)
	box.add_child(row)


func _choice(label: String, key: String, opts: Array) -> void:
	var row := UIK.hbox(6)
	var l := UIK.label(label, 15)
	l.custom_minimum_size = Vector2(260, 0)
	row.add_child(l)
	for o in opts:
		var cur = Settings.get_v(key)
		row.add_child(UIK.button(("● " if cur == o[1] else "○ ") + o[0], func():
			Settings.set_v(key, o[1])
			var sky := get_tree().get_first_node_in_group("sky_weather")
			if key == "quality" and sky:
				sky.apply_quality(int(o[1]))
			refresh()))
	box.add_child(row)


func _toggle(label: String, key: String) -> void:
	var cb := CheckButton.new()
	cb.text = label
	cb.button_pressed = bool(Settings.get_v(key))
	cb.toggled.connect(func(v): Settings.set_v(key, v))
	box.add_child(cb)


func refresh() -> void:
	if box == null:
		return
	UIK.clear(box)
	match tab:
		"graphics":
			var res := [["1280×720", Vector2i(1280, 720)], ["1600×900", Vector2i(1600, 900)], ["1920×1080", Vector2i(1920, 1080)], ["2560×1440", Vector2i(2560, 1440)], ["3840×2160", Vector2i(3840, 2160)]]
			_choice("Auflösung (Fenster)", "resolution", res)
			_choice("Anzeigemodus", "window_mode", [["Fenster", 0], ["Vollbild (randlos)", 1], ["Exklusiv", 2]])
			_choice("Grafikqualität", "quality", [["Niedrig", 0], ["Mittel", 1], ["Hoch", 2], ["Ultra", 3]])
			_toggle("VSync", "vsync")
			_choice("Bildratenlimit", "fps_limit", [["Aus", 0], ["30", 30], ["60", 60], ["120", 120], ["144", 144]])
			_slider("Renderauflösung (FSR 2 unter 1,0)", "render_scale", 0.5, 1.0, 0.05)
			_slider("Sichtweite Vegetation", "view_distance", 0.5, 1.5, 0.1, false)
			box.add_child(UIK.label("Empfehlung für RTX 4060 Ti: Hoch, Renderauflösung 1,0 bei 1080p/1440p, Ultra je nach Bildrate. Qualität, Vegetation und Gras werden teils erst nach dem Neuladen eines Spielstands voll übernommen.", 13, UIK.DIM, true))
		"audio":
			_slider("Gesamtlautstärke", "vol_master", 0.0, 1.0, 0.05)
			_slider("Musik", "vol_music", 0.0, 1.0, 0.05)
			_slider("Effekte", "vol_sfx", 0.0, 1.0, 0.05)
			_slider("Umgebung", "vol_ambience", 0.0, 1.0, 0.05)
			_slider("Oberfläche", "vol_ui", 0.0, 1.0, 0.05)
		"controls":
			_slider("Mausempfindlichkeit", "mouse_sens", 0.05, 1.0, 0.01)
			_toggle("Y-Achse umkehren", "invert_y")
			_slider("Sichtfeld (FOV)", "fov", 55.0, 110.0, 1.0)
		"keys":
			box.add_child(UIK.label("Klicke eine Aktion und drücke dann die neue Taste/Maustaste.", 14, UIK.DIM))
			box.add_child(UIK.button("Standardbelegung wiederherstellen", func():
				Settings.reset_bindings()
				refresh()))
			for a in Settings.ACTIONS:
				var row := UIK.hbox(8)
				var l := UIK.label(Settings.ACTIONS[a][0], 15)
				l.custom_minimum_size = Vector2(320, 0)
				row.add_child(l)
				var b := UIK.button("… Taste drücken …" if waiting_action == a else Settings.binding_label(a), func():
					waiting_action = a
					refresh(), "", 220)
				row.add_child(b)
				box.add_child(row)
		"game":
			_toggle("Schadenszahlen anzeigen", "show_damage_numbers")
			_toggle("Kamerawackeln", "camera_shake")
			_toggle("Tutorial-Hinweise", "tutorial_hints")


func _input(event: InputEvent) -> void:
	if waiting_action == "":
		return
	if (event is InputEventKey and event.pressed) or (event is InputEventMouseButton and event.pressed):
		if event is InputEventKey and event.physical_keycode == KEY_ESCAPE:
			waiting_action = ""
		else:
			Settings.set_binding(waiting_action, Settings.event_to_binding(event))
			waiting_action = ""
		get_viewport().set_input_as_handled()
		refresh()
