extends Node
## Entry point: main menu, new game setup, loading screen, starts/stops the World.

var world: World
var ui: GameUI
var menu: Control
var loading: Control
var loading_label: Label
var loading_bar: ProgressBar
var bg_world: Node3D
var _menu_cam: Camera3D


func _ready() -> void:
	add_to_group("main")
	get_tree().root.theme = UIK.get_theme()
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--visual="):
			# visual check scripts (tests/visual/<name>.gd, extends Node) with autoloads but without a world
			var vs = load("res://tests/visual/" + a.substr(9) + ".gd")
			if vs:
				add_child(vs.new())
			return
	if "--autostart" in args:
		var opts := {"name": "Test", "kit": "jaeger", "difficulty": "normal"}
		for a in args:
			if a.begins_with("--kit="):
				opts["kit"] = a.substr(6)
		start_new(opts)
		return
	show_menu()
	for a in args:
		if a.begins_with("--menushot="):
			_menu_shot(a.substr(11))


## Saves screenshots of the main menu and the new-game dialog (visual check of the layout).
func _menu_shot(path: String) -> void:
	for i in 40:
		await get_tree().process_frame
	get_tree().root.get_texture().get_image().save_png(path + "_menu.png")
	_new_game_dialog()
	for i in 20:
		await get_tree().process_frame
	get_tree().root.get_texture().get_image().save_png(path + "_newgame.png")
	get_tree().quit()


# ------------------------------------------------------------------ menu
func show_menu() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Audio.set_music("menu")
	menu = Control.new()
	menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu.theme = UIK.get_theme()
	add_child(menu)
	var bg := TextureRect.new()
	bg.texture = load("res://assets/world/map.png")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.modulate = Color(0.45, 0.4, 0.38)
	menu.add_child(bg)
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.02, 0.02, 0.55)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu.add_child(shade)
	var col := UIK.vbox(10)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	menu.add_child(col)
	UIK.center_window(col)
	var t := UIK.label("PRIMAL DOMINION", 64, UIK.GOLD)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	t.add_theme_constant_override("outline_size", 10)
	col.add_child(t)
	var sub := UIK.label("Bestien. Blut. Herrschaft.", 22, UIK.DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sub)
	col.add_child(Control.new())
	var has_any := false
	for s in SaveSystem.SLOTS:
		if SaveSystem.has_slot(s):
			has_any = true
	if has_any:
		col.add_child(UIK.button("Fortsetzen", func(): _continue(), "Neuester Spielstand", 320))
	col.add_child(UIK.button("Neues Spiel", func(): _new_game_dialog(), "", 320))
	col.add_child(UIK.button("Laden", func(): _load_dialog(), "", 320))
	col.add_child(UIK.button("Einstellungen", func(): _settings(), "", 320))
	col.add_child(UIK.button("Mitwirkende & Lizenzen", func(): _credits(), "", 320))
	col.add_child(UIK.button("Beenden", func(): get_tree().quit(), "", 320))
	var ver := UIK.label("Version %s · Godot %s" % [ProjectSettings.get_setting("application/config/version"), Engine.get_version_info()["string"]], 13, UIK.DIM)
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(ver)
	for b in col.get_children():
		if b is Button:
			b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	UIK.focus_for_gamepad.call_deferred(col)


func _popup(title: String, size: Vector2) -> UIWindow:
	var w := UIWindow.new(title, size)
	menu.add_child(w)
	w.set("ui", null)
	return w


func _settings() -> void:
	var w := WinSettings.new()
	menu.add_child(w)


func _credits() -> void:
	var w := _popup("Mitwirkende & Lizenzen", Vector2(900, 600))
	var f := FileAccess.open("res://CREDITS.md", FileAccess.READ)
	var txt := f.get_as_text() if f else "Siehe CREDITS.md"
	var sc := UIK.scroll(Vector2(860, 500))
	w.content.add_child(sc[0])
	sc[1].add_child(UIK.label(txt, 14, UIK.TEXT, true))


func _continue() -> void:
	var best := ""
	var best_t := ""
	for s in SaveSystem.SLOTS:
		var info := SaveSystem.slot_info(s)
		if not info.is_empty() and str(info.get("time", "")) > best_t:
			best_t = str(info["time"])
			best = s
	if best != "":
		load_game(best)


func _load_dialog() -> void:
	var w := _popup("Spielstand laden", Vector2(800, 560))
	for slot in SaveSystem.SLOTS:
		var info := SaveSystem.slot_info(slot)
		if info.is_empty():
			continue
		var h := UIK.hbox(6)
		var b := UIK.button("%s – %s, Stufe %d, Tag %d · %s · %s" % [SaveSystem.SLOT_NAMES[slot], info.get("name", ""), info.get("level", 1), info.get("day", 1), info.get("difficulty", ""), info.get("time", "")], func(): load_game(slot))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		h.add_child(b)
		h.add_child(UIK.button("Löschen", func():
			SaveSystem.delete_slot(slot)
			w.queue_free()
			_load_dialog()))
		w.content.add_child(h)


func _new_game_dialog() -> void:
	var w := _popup("Neues Spiel", Vector2(1000, 760))
	var opts := {"name": "Wanderer", "kit": "jaeger", "difficulty": "normal", "body": "human_m", "rules": {}}
	var v := w.content
	var nr := UIK.hbox(8)
	nr.add_child(UIK.label("Name:", 16))
	var le := LineEdit.new()
	le.text = "Wanderer"
	le.custom_minimum_size = Vector2(260, 0)
	nr.add_child(le)
	nr.add_child(UIK.label("Körper:", 16))
	var body_btns := []
	for b in [["Mann", "human_m"], ["Mann (Bart)", "human_m2"], ["Frau", "human_f"], ["Frau (Dutt)", "human_f2"]]:
		var bb := UIK.button(b[0], func():
			opts["body"] = b[1]
			for x in body_btns:
				x.add_theme_color_override("font_color", UIK.TEXT)
			body_btns[["human_m", "human_m2", "human_f", "human_f2"].find(b[1])].add_theme_color_override("font_color", UIK.GOLD))
		body_btns.append(bb)
		nr.add_child(bb)
	body_btns[0].add_theme_color_override("font_color", UIK.GOLD)
	v.add_child(nr)
	v.add_child(UIK.label("Startpaket", 20, UIK.GOLD))
	var kit_btns := {}
	var kit_desc := UIK.label("", 15, UIK.DIM, true)
	var kh := UIK.hbox(6)
	for k in GameState.START_KITS:
		var kd: Dictionary = GameState.START_KITS[k]
		var kb := UIK.button(kd["name"], func():
			opts["kit"] = k
			kit_desc.text = kd["desc"]
			for x in kit_btns:
				kit_btns[x].add_theme_color_override("font_color", UIK.GOLD if x == k else UIK.TEXT), kd["desc"], 160)
		kit_btns[k] = kb
		kh.add_child(kb)
	kit_btns["jaeger"].add_theme_color_override("font_color", UIK.GOLD)
	kit_desc.text = GameState.START_KITS["jaeger"]["desc"]
	v.add_child(kh)
	v.add_child(kit_desc)
	v.add_child(UIK.label("Schwierigkeit", 20, UIK.GOLD))
	var dh := UIK.hbox(6)
	var dif_btns := {}
	var rule_box := UIK.vbox(2)
	for d in [["Leicht", "leicht"], ["Normal", "normal"], ["Schwer", "schwer"], ["Brutal", "brutal"]]:
		var db := UIK.button(d[0], func():
			opts["difficulty"] = d[1]
			opts["rules"] = GameState.DIFFICULTY[d[1]].duplicate()
			for x in dif_btns:
				dif_btns[x].add_theme_color_override("font_color", UIK.GOLD if x == d[1] else UIK.TEXT)
			_rules_ui(rule_box, opts), "", 140)
		dif_btns[d[1]] = db
		dh.add_child(db)
	dif_btns["normal"].add_theme_color_override("font_color", UIK.GOLD)
	opts["rules"] = GameState.DIFFICULTY["normal"].duplicate()
	v.add_child(dh)
	v.add_child(rule_box)
	_rules_ui(rule_box, opts)
	v.add_child(UIK.sep())
	v.add_child(UIK.button("Abenteuer beginnen", func():
		opts["name"] = le.text if le.text.strip_edges() != "" else "Wanderer"
		start_new(opts), "", 300))


func _rules_ui(box: VBoxContainer, opts: Dictionary) -> void:
	UIK.clear(box)
	box.add_child(UIK.label("Individuelle Regeln", 16, UIK.DIM))
	var r: Dictionary = opts["rules"]
	for t in [["player_permadeath", "Permanenter Spielertod"], ["creature_permadeath", "Gezähmte Kreaturen sterben dauerhaft"], ["drop_on_death", "Inventar beim Tod fallen lassen"], ["hunger_lethal", "Verhungern ist tödlich"]]:
		var cb := CheckButton.new()
		cb.text = t[1]
		cb.button_pressed = bool(r.get(t[0], false))
		cb.toggled.connect(func(val): r[t[0]] = val)
		box.add_child(cb)
	for m in [["dmg_taken", "Erlittener Schaden"], ["dmg_dealt", "Verursachter Schaden"], ["hunger", "Hungerrate"], ["taming", "Zähmungsgeschwindigkeit"], ["xp", "Erfahrung"]]:
		var h := UIK.hbox(6)
		var l := UIK.label(m[1], 14)
		l.custom_minimum_size = Vector2(240, 0)
		h.add_child(l)
		var s := HSlider.new()
		s.min_value = 0.25
		s.max_value = 3.0
		s.step = 0.05
		s.value = float(r.get(m[0], 1.0))
		s.custom_minimum_size = Vector2(280, 20)
		var vl := UIK.label("×%.2f" % s.value, 14, UIK.DIM)
		s.value_changed.connect(func(val):
			r[m[0]] = val
			vl.text = "×%.2f" % val)
		h.add_child(s)
		h.add_child(vl)
		box.add_child(h)


# ------------------------------------------------------------------ game lifecycle
func start_new(opts: Dictionary) -> void:
	WorldData.ensure_loaded()
	GameState.new_game(opts)
	_start_world()


func load_game(slot: String) -> void:
	_teardown()
	WorldData.ensure_loaded()
	if not SaveSystem.load_slot(slot):
		show_menu()
		return
	_start_world()
	EventBus.game_loaded.emit()


func _start_world() -> void:
	_teardown()
	if menu:
		menu.queue_free()
		menu = null
	Encounters._active = {}
	loading = Control.new()
	loading.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	loading.theme = UIK.get_theme()
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.03, 0.03)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	loading.add_child(bg)
	var v := UIK.vbox(10)
	v.custom_minimum_size = Vector2(600, 0)
	loading.add_child(v)
	UIK.center_window(v)
	loading_label = UIK.label("Lade …", 22, UIK.GOLD)
	loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(loading_label)
	loading_bar = UIK.bar(UIK.GOLD, 600, 12)
	v.add_child(loading_bar)
	var tips := ["Tipp: Ducken (Strg) macht dich für scheue Tiere weniger bedrohlich.", "Tipp: Velociraptoren lassen sich nur aus dem Ei aufziehen.",
		"Tipp: Nasse Gegner sind anfällig für Blitz – Elemente reagieren miteinander.", "Tipp: Gefährten teleportieren nicht. Pfeife (Tab), wenn sie zurückbleiben.",
		"Tipp: Vorratskisten in der Nähe werden beim Herstellen automatisch genutzt.", "Tipp: Hybride werden mächtig – doch fremde Körper machen das Blut instabil."]
	var tip := UIK.label(tips[randi() % tips.size()], 15, UIK.DIM, true)
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(tip)
	add_child(loading)
	world = World.new()
	world.name = "World"
	add_child(world)
	world.loading_progress.connect(func(t, f):
		loading_label.text = t
		loading_bar.value = f * 100.0)
	await world.build_world(int(Settings.get_v("quality")))
	ui = GameUI.new()
	add_child(ui)
	ui.bind(world.player, world)
	loading.queue_free()
	loading = null
	print("WORLD READY day=%d hour=%.2f creatures=%d" % [GameState.get_day(), GameState.get_hour(), get_tree().get_nodes_in_group("creatures").size()])
	Audio.set_music("explore")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			ShotTour.run(self, a.substr(8))
		if a.begins_with("--test="):
			get_tree().create_timer(1500.0, true, false, true).timeout.connect(func():
				print("TEST TIMEOUT")
				get_tree().quit(2))
			var scr = load("res://tests/" + a.substr(7) + ".gd")
			if scr == null or not scr.can_instantiate():
				print("TEST SCRIPT FAILED TO LOAD")
				get_tree().quit(3)
				return
			add_child(scr.new())
	if GameState.get_day() == 1 and GameState.get_hour() < 8.6 and Settings.get_v("tutorial_hints"):
		ui.show_text("Gestrandet", "Ein Mosasaurus hat dein Schiff in Stücke gerissen. Salzwasser brennt in deinen Augen, als du am Strand der Insel Grünkrone erwachst.\n\nIrgendwo im Westen steigt Rauch auf. Doch zuerst brauchst du Werkzeug, Feuer und etwas zu essen.\n\n[b]I[/b] Inventar · [b]J[/b] Journal · [b]B[/b] Bauen · [b]Esc[/b] Menü")


func _teardown() -> void:
	if ui:
		ui.queue_free()
		ui = null
	if world:
		world.queue_free()
		world = null
	Engine.time_scale = 1.0
	get_tree().paused = false


func to_menu() -> void:
	if world and not GameState.player().get("dead", false):
		SaveSystem.save_slot("auto")
	_teardown()
	GameState.running = false
	show_menu()
