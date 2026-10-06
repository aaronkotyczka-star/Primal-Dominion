class_name GameUI
extends CanvasLayer
## Window manager & simple dialogs: opens windows from input, handles mouse capture, pause, death, popups.

var hud: HUD
var root: Control
var windows: Array = []
var player: Player
var world: World
var wheel: Control
var wheel_sel := -1
var dimmer: ColorRect
var tutorial_t := 3.0


func _ready() -> void:
	add_to_group("ui")
	layer = 10
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UIK.get_theme()
	add_child(root)
	hud = HUD.new()
	root.add_child(hud)
	dimmer = ColorRect.new()
	dimmer.color = Color(0, 0, 0, 0.45)
	dimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dimmer.visible = false
	dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(dimmer)
	process_mode = Node.PROCESS_MODE_ALWAYS


func bind(p: Player, w: World) -> void:
	player = p
	world = w
	hud.player = p
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	EventBus.player_died.connect(_on_died)


func is_open() -> bool:
	return not windows.is_empty()


func _open(win: Control) -> Control:
	for w in windows:
		if w.get("window_id") == win.get("window_id") and win.get("window_id") != "":
			close(w)
			break
	win.set("ui", self)
	root.add_child(win)
	windows.append(win)
	dimmer.visible = true
	root.move_child(dimmer, root.get_child_count() - 2)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if player:
		player.ui_blocking = true
	Audio.play_ui("ui_open")
	return win


func close(win: Control) -> void:
	windows.erase(win)
	if is_instance_valid(win):
		win.queue_free()
	if windows.is_empty():
		dimmer.visible = false
		if get_tree().paused:
			get_tree().paused = false
		if player and not player.dead:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			player.ui_blocking = false


func close_all() -> void:
	for w in windows.duplicate():
		close(w)


func _unhandled_input(event: InputEvent) -> void:
	if player == null:
		return
	if event.is_action_pressed("pause"):
		if world and world.buildings.is_placing():
			world.buildings.cancel_place()
		elif is_open():
			close(windows[-1])
		else:
			open_pause()
		get_viewport().set_input_as_handled()
		return
	if player.dead:
		return
	var map := {"inventory": "open_inventory", "journal": "open_journal", "skills": "open_skills", "map": "open_map",
		"lexicon": "open_lexicon", "research": "open_research", "creatures": "open_creatures", "crafting": "open_crafting_hand"}
	for a in map:
		if event.is_action_pressed(a):
			var already := false
			for w in windows:
				if w.get("window_id") == a or (a == "crafting" and w.get("window_id") == "crafting"):
					close(w)
					already = true
					break
			if not already and (not is_open() or windows[-1].get("window_id") != ""):
				call(map[a])
			get_viewport().set_input_as_handled()
			return
	if is_open():
		return
	if event.is_action_pressed("build_mode"):
		if world.buildings.is_placing():
			world.buildings.cancel_place()
		else:
			open_build()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("quicksave"):
		var chk := SaveSystem.can_manual_save()
		if chk["ok"]:
			SaveSystem.save_slot("quick")
		else:
			EventBus.notify.emit(chk["why"], "warn")
	elif event.is_action_pressed("quickload"):
		if SaveSystem.has_slot("quick"):
			get_tree().get_first_node_in_group("main").load_game("quick")
	if world and world.buildings.is_placing():
		if event.is_action_pressed("attack"):
			world.buildings.confirm_place()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("block"):
			world.buildings.cancel_place()
			get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if player == null:
		return
	# command wheel (hold Q)
	if not is_open() and not player.dead:
		if Input.is_action_just_pressed("command_wheel"):
			_show_wheel()
		elif Input.is_action_just_released("command_wheel") and wheel:
			_apply_wheel()
		if wheel:
			_update_wheel()
	if world and world.buildings.is_placing():
		player.input.intent["attack"] = false
	_tutorial(delta)


# ------------------------------------------------------------------ open helpers
func open_inventory() -> void:
	_open(WinInventory.new())


func open_crafting(station: String) -> void:
	_open(WinCrafting.new(station))


func open_crafting_hand() -> void:
	open_crafting("hand")


func open_journal() -> void:
	_open(WinJournal.new())


func open_skills() -> void:
	_open(WinSkills.new())


func open_map() -> void:
	_open(WinMap.new())


func open_lexicon() -> void:
	_open(WinLexicon.new())


func open_research(at_table: bool = false) -> void:
	_open(WinResearch.new(at_table))


func open_creatures() -> void:
	_open(WinCreatures.new())


func open_creature(uid: int) -> void:
	_open(WinCreatures.new(uid))


func open_genelab() -> void:
	_open(WinGeneLab.new())


func open_dialogue(npc_id: String) -> void:
	_open(WinDialogue.new(npc_id))


func open_storage(b: Dictionary) -> void:
	_open(WinStorage.new(b))


func open_base() -> void:
	_open(WinBase.new())


func open_settings() -> void:
	_open(WinSettings.new())


func show_text(title: String, text: String) -> void:
	var w := UIWindow.new(title, Vector2(760, 380))
	var r := UIK.rich(text, 17)
	r.custom_minimum_size = Vector2(720, 0)
	w.content.add_child(r)
	w.content.add_child(UIK.button("Weiter", func(): close(w)))
	_open(w)


func show_choice(title: String, text: String, opts: Array) -> void:
	var w := UIWindow.new(title, Vector2(800, 420))
	var r := UIK.rich(text, 17)
	r.custom_minimum_size = Vector2(760, 0)
	w.content.add_child(r)
	for o in opts:
		var b := UIK.button(o["text"], func():
			close(w)
			o["cb"].call())
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		w.content.add_child(b)
	_open(w)


func open_pause() -> void:
	var w := UIWindow.new("Pause", Vector2(520, 520))
	w.window_id = "pause"
	get_tree().paused = true
	var v := w.content
	v.add_child(UIK.button("Fortsetzen", func(): close(w)))
	v.add_child(UIK.button("Speichern …", func(): open_saveload(true)))
	v.add_child(UIK.button("Laden …", func(): open_saveload(false)))
	v.add_child(UIK.button("Einstellungen", func(): open_settings()))
	v.add_child(UIK.button("Steuerung anzeigen", func(): show_text("Steuerung", Help.controls_text())))
	v.add_child(UIK.button("Zum Hauptmenü", func():
		get_tree().paused = false
		get_tree().get_first_node_in_group("main").to_menu()))
	v.add_child(UIK.button("Spiel beenden", func(): get_tree().quit()))
	_open(w)


func open_saveload(saving: bool) -> void:
	var w := UIWindow.new("Speichern" if saving else "Laden", Vector2(760, 560))
	if saving:
		var chk := SaveSystem.can_manual_save()
		if not chk["ok"]:
			w.content.add_child(UIK.label(chk["why"] + " (Automatische Speicherstände entstehen regelmäßig.)", 15, UIK.RED, true))
	for slot in SaveSystem.SLOTS:
		if saving and slot == "auto":
			continue
		var info := SaveSystem.slot_info(slot)
		var txt := "%s – %s" % [SaveSystem.SLOT_NAMES[slot], ("%s, Stufe %d, Tag %d, %s (%s)" % [info.get("name", "?"), info.get("level", 1), info.get("day", 1), info.get("quest", ""), info.get("time", "")]) if not info.is_empty() else "leer"]
		var b := UIK.button(txt, func():
			if saving:
				if SaveSystem.can_manual_save()["ok"] or slot == "quick":
					SaveSystem.save_slot(slot)
					close(w)
			else:
				if SaveSystem.has_slot(slot):
					get_tree().paused = false
					get_tree().get_first_node_in_group("main").load_game(slot))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.disabled = (saving and not SaveSystem.can_manual_save()["ok"]) or (not saving and info.is_empty())
		w.content.add_child(b)
	_open(w)


func _on_died() -> void:
	close_all()
	var w := UIWindow.new("Du bist gestorben", Vector2(700, 360))
	w.window_id = "death"
	if GameState.rule("player_permadeath"):
		w.content.add_child(UIK.label("Permanenter Tod ist aktiviert. Dein Abenteuer endet hier. Der Spielstand wurde gelöscht.", 17, UIK.RED, true))
		w.content.add_child(UIK.button("Zum Hauptmenü", func(): get_tree().get_first_node_in_group("main").to_menu()))
	else:
		var txt := "Du erwachst an deinem letzten Wiedereinstiegspunkt."
		if GameState.rule("drop_on_death"):
			txt += " Dein Inventar liegt an deinem Todesort (auf der Karte mit ✝ markiert)."
		w.content.add_child(UIK.label(txt, 17, UIK.TEXT, true))
		w.content.add_child(UIK.button("Wiederbeleben", func():
			close(w)
			player.respawn()))
		w.content.add_child(UIK.button("Letzten Spielstand laden", func(): open_saveload(false)))
	_open(w)


# ------------------------------------------------------------------ build menu
func open_build() -> void:
	var w := UIWindow.new("Bauen", Vector2(1050, 700))
	w.window_id = "build"
	var sc := UIK.scroll(Vector2(1000, 600))
	w.content.add_child(sc[0])
	var box: VBoxContainer = sc[1]
	var pool := Crafting.pools(world.nearby_storages(player.global_position, 25.0))
	box.add_child(UIK.label("Baue fast überall – nicht in Siedlungen und an wichtigen Quest-Orten. Materialien aus Vorratskisten in 25 m werden mitgenutzt.", 14, UIK.DIM, true))
	var cats := {"facility": "Einrichtungen", "structure": "Bauteile (Raster 4 m)", "defense": "Verteidigung", "decor": "Dekoration"}
	for cat in cats:
		box.add_child(UIK.label(cats[cat], 20, UIK.GOLD))
		var flow := HFlowContainer.new()
		box.add_child(flow)
		for bid in DB.t("buildings"):
			var bd := DB.building(bid)
			if bd.get("cat", "") != cat:
				continue
			var cost := []
			var afford := true
			for it in bd["cost"]:
				cost.append("%d %s" % [bd["cost"][it], DB.item_name(it)])
				if Inventory.pooled_count(pool, it) < int(bd["cost"][it]):
					afford = false
			var unlocked := Research.building_unlocked(bid)
			var tip := "%s\nKosten: %s%s" % [bd.get("desc", ""), ", ".join(cost), "" if unlocked else "\nForschung: " + DB.research(bd["research"]).get("name", "")]
			var b := UIK.button(bd["name"] + ("" if unlocked else " 🔒"), func():
				close(w)
				world.buildings.begin_place(bid), tip, 180)
			if not afford or not unlocked:
				b.add_theme_color_override("font_color", UIK.DIM)
			flow.add_child(b)
	box.add_child(UIK.label("Vorlagen", 20, UIK.GOLD))
	var tf := HFlowContainer.new()
	box.add_child(tf)
	for tid in DB.t("templates"):
		var td: Dictionary = DB.get_entry("templates", tid)
		tf.add_child(UIK.button(td["name"], func():
			close(w)
			world.buildings.begin_place("", tid), "Mehrere Bauteile auf einmal", 180))
	_open(w)


# ------------------------------------------------------------------ incubator / sleep / pact / demon
func open_incubator(b: Dictionary) -> void:
	var w := UIWindow.new("Brutstätte", Vector2(760, 520))
	if not b.has("data"):
		b["data"] = {}
	var d: Dictionary = b["data"]
	if d.has("egg"):
		var left := float(d["egg"]["ready_at"]) - (GameState.get_day() * 24.0 + GameState.get_hour())
		w.content.add_child(UIK.label("Brütet: %s – schlüpft in %.1f Spielstunden (Schlafen beschleunigt)." % [d["egg"].get("name", "Ei"), maxf(left, 0.0)], 16, UIK.TEXT, true))
	else:
		var inv: Array = GameState.player()["inventory"]
		var any := false
		for i in inv.size():
			var st: Dictionary = inv[i]
			if st["id"] != "egg":
				continue
			any = true
			w.content.add_child(UIK.button("%s einlegen" % st.get("d", {}).get("name", "Ei"), func():
				var eg := Inventory.remove_at(inv, i, 1)
				var ed: Dictionary = eg.get("d", {})
				var sp: String = ed.get("species", "raptor")
				var size: String = DB.species(ed.get("genes", {}).get("body_species", sp) if sp == "hybrid" else sp).get("size", "medium")
				var hours = {"small": 3.0, "medium": 5.0, "large": 8.0, "huge": 12.0}.get(size, 5.0)
				for bb in GameState.state["buildings"]:
					if bb["type"] in ["campfire", "kitchen"] and Vector3(bb["pos"][0], 0, bb["pos"][2]).distance_to(Vector3(b["pos"][0], 0, b["pos"][2])) < 10.0:
						hours *= 0.75
				d["egg"] = {"genes": ed.get("genes", {}), "name": ed.get("name", "Ei"), "parents": ed.get("parents", []), "parent_names": ed.get("parent_names", []),
					"dud": ed.get("dud", false), "ready_at": GameState.get_day() * 24.0 + GameState.get_hour() + hours}
				EventBus.notify.emit("Ei eingelegt. Es schlüpft in etwa %d Spielstunden (%d Minuten Echtzeit oder durch Schlafen)." % [hours, int(hours * GameState.HOUR_SECONDS / 60.0)], "good")
				EventBus.inventory_changed.emit()
				close(w)))
		if not any:
			w.content.add_child(UIK.label("Du trägst keine Eier. Eier erhältst du aus Nestern oder dem Genlabor.", 15, UIK.DIM, true))
	_open(w)


func open_sleep(b: Dictionary) -> void:
	var w := UIWindow.new("Schlafen", Vector2(600, 360))
	w.content.add_child(UIK.label("Wiedereinstiegspunkt gesetzt. Schlafen ist optional und gewährt den Bonus „Ausgeruht“ (+50% Regeneration, 10 Minuten).", 15, UIK.TEXT, true))
	for h in [2, 4, 8]:
		w.content.add_child(UIK.button("%d Stunden schlafen" % h, func():
			for n in get_tree().get_nodes_in_group("creatures"):
				if n.wild and n.ai.target == player:
					EventBus.notify.emit("Du kannst nicht schlafen, während du verfolgt wirst!", "danger")
					return
			GameState.skip_hours(h)
			player.combatant.heal(player.combatant.max_hp)
			player.combatant.add_buff("ausgeruht", {"dur": 600.0 if b["type"] == "bed" else 420.0})
			GameState.player()["hunger"] = maxf(10.0, float(GameState.player()["hunger"]) - h * 2.0)
			close(w)
			EventBus.notify.emit("Du fühlst dich ausgeruht.", "good")))
	if SaveSystem.can_manual_save()["ok"]:
		w.content.add_child(UIK.button("Spiel speichern", func(): open_saveload(true)))
	_open(w)


func open_pact() -> void:
	var w := UIWindow.new("Rissaltar – Pakt", Vector2(820, 560))
	w.content.add_child(UIK.label("Ein Pakt bindet ein Monster an dich. Kosten: 1 Paktsiegel + 4 Dämonenessenz + Blutzoll (30% deines Lebens). Pakt-Monster behalten Zustand und Identität – auch ihr Tod ist endgültig.", 15, UIK.TEXT, true))
	var inv: Array = GameState.player()["inventory"]
	for sid in DB.t("species"):
		var sp := DB.species(sid)
		if sp.get("tame", {}).get("method", "") != "pact":
			continue
		var known: bool = GameState.state["lexicon"].get(sid, {}).get("investigated", false)
		var b := UIK.button("Pakt mit: %s%s" % [sp["name"], "" if known else " (unbekannt – erst untersuchen)"], func():
			if Inventory.count(inv, "pact_sigil") < 1 or Inventory.count(inv, "demon_essence") < 4:
				EventBus.notify.emit("Benötigt Paktsiegel und 4 Dämonenessenz.", "warn")
				return
			Inventory.remove(inv, "pact_sigil", 1)
			Inventory.remove(inv, "demon_essence", 4)
			player.combatant.take_hit({"amount": player.combatant.max_hp * 0.3, "true_damage": true, "unavoidable": true})
			var chance := 0.55 + 0.12 * GameState.skill_rank("tame_magic")
			if randf() < chance:
				var uid := GameState.create_creature(sid, int(GameState.player()["level"]) + randi_range(-2, 2), {"method": "pact", "bond": 20.0})
				GameState.set_creature_status(uid, "base" if GameState.has_base() else "party")
				if GameState.creature(uid)["status"] == "party":
					world.spawn_companion(uid, player.global_position + player.get_forward() * 5.0)
				GameState.add_path("demon", 1)
				EventBus.notify.emit("Der Pakt ist besiegelt: %s dient dir." % sp["name"], "good")
			else:
				var c := world.spawn_wild(sid, int(GameState.player()["level"]) + 2, player.global_position + player.get_forward() * 8.0, {})
				if c:
					c.ai.target = player
					c.ai._go("chase", 30.0)
				EventBus.notify.emit("Der Pakt scheitert – das Monster bricht hervor!", "danger")
			EventBus.inventory_changed.emit()
			close(w))
		b.disabled = not known
		w.content.add_child(b)
	_open(w)


func open_demon() -> void:
	var d: Dictionary = GameState.player()["demon"]
	var w := UIWindow.new("Dämonengestalten", Vector2(900, 640))
	var forms: Array = d["forms"]
	var idx := int(d.get("active_form", 0))
	var form: Dictionary = forms[idx]
	var rowf := UIK.hbox(6)
	for i in forms.size():
		rowf.add_child(UIK.button(("● " if i == idx else "○ ") + forms[i]["name"], func():
			d["active_form"] = i
			close(w)
			_refresh_demon_visual()
			open_demon()))
	if forms.size() < 4:
		rowf.add_child(UIK.button("+ Neue Gestalt", func():
			forms.append({"name": "Gestalt %d" % (forms.size() + 1), "horns": "horns_ram", "wings": false, "tail": true, "skin": [0.15, 0.1, 0.12], "glow": [0.6, 0.2, 1.0], "claws": true, "spikes": false})
			close(w)
			open_demon()))
	w.content.add_child(rowf)
	var opts := [["Hörner", "horns", [["Dämonenhörner", "horns_demon"], ["Widderhörner", "horns_ram"], ["Kurzhörner", "horns_short"], ["keine", ""]]],
		["Flügel", "wings", [["ja (Gleiten/Flug)", true], ["nein", false]]], ["Schweif", "tail", [["ja", true], ["nein", false]]],
		["Rückenstacheln", "spikes", [["ja (+Rüstung)", true], ["nein", false]]]]
	for o in opts:
		var row := UIK.hbox(6)
		row.add_child(UIK.label(o[0] + ":", 15))
		for v in o[2]:
			row.add_child(UIK.button(("● " if form.get(o[1]) == v[1] else "○ ") + v[0], func():
				form[o[1]] = v[1]
				close(w)
				_refresh_demon_visual()
				open_demon()))
		w.content.add_child(row)
	var skins := [["Glutrot", [0.3, 0.07, 0.06]], ["Aschgrau", [0.2, 0.19, 0.2]], ["Nachtviolett", [0.15, 0.08, 0.2]], ["Knochenbleich", [0.55, 0.5, 0.45]], ["Moorgrün", [0.12, 0.18, 0.1]]]
	var rs := UIK.hbox(6)
	rs.add_child(UIK.label("Haut:", 15))
	for s in skins:
		rs.add_child(UIK.button(s[0], func():
			form["skin"] = s[1]
			close(w)
			_refresh_demon_visual()
			open_demon()))
	w.content.add_child(rs)
	var glows := [["Höllenfeuer", [1.0, 0.3, 0.05]], ["Schatten", [0.6, 0.2, 1.0]], ["Blut", [0.9, 0.05, 0.1]], ["Frost", [0.4, 0.8, 1.0]], ["Gift", [0.5, 1.0, 0.2]]]
	var rg := UIK.hbox(6)
	rg.add_child(UIK.label("Glühen:", 15))
	for g in glows:
		rg.add_child(UIK.button(g[0], func():
			form["glow"] = g[1]
			close(w)
			_refresh_demon_visual()
			open_demon()))
	w.content.add_child(rg)
	w.content.add_child(UIK.label("Körperteile verleihen Grundfähigkeiten: Flügel = Gleiten (Rang 2 „Schwingen der Tiefe“: Flug), Stacheln = +Rüstung, Hörner = Rammstoß im Sprint. Wechsel jederzeit mit N – ohne Kosten.", 14, UIK.DIM, true))
	w.content.add_child(UIK.button("Dämonische Kräfte lernen", func():
		close(w)
		var ws := WinSkills.new()
		ws.tree_id = "demon"
		_open(ws)))
	_open(w)


func _refresh_demon_visual() -> void:
	if player.demon_form:
		player.build_visual()


# ------------------------------------------------------------------ command wheel
const WHEEL := [["follow", "Folgen"], ["wait", "Warten"], ["defend", "Verteidigen"], ["attack", "Ziel angreifen"], ["ability", "Spezialfähigkeit"], ["retreat", "Rückzug"]]


func _show_wheel() -> void:
	wheel = Control.new()
	UIK.anchor(wheel, 0.5, 0.5, 0, 0)
	root.add_child(wheel)
	for i in WHEEL.size():
		var a := TAU * i / WHEEL.size() - PI * 0.5
		var l := UIK.label(WHEEL[i][1], 20, UIK.TEXT)
		l.position = Vector2(cos(a), sin(a)) * 170.0 - Vector2(60, 12)
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		l.add_theme_constant_override("outline_size", 6)
		wheel.add_child(l)
	var hint := UIK.label("Maus bewegen, Q loslassen", 14, UIK.DIM)
	hint.position = Vector2(-80, 210)
	wheel.add_child(hint)
	wheel.set_meta("acc", Vector2.ZERO)
	player.wheel_open = true
	Engine.time_scale = 0.35


func _update_wheel() -> void:
	var d := player.input.consume_look()
	var acc: Vector2 = wheel.get_meta("acc") + d
	if acc.length() > 140.0:
		acc = acc.normalized() * 140.0
	wheel.set_meta("acc", acc)
	wheel_sel = -1
	if acc.length() > 40.0:
		var ang := wrapf(atan2(acc.y, acc.x) + PI * 0.5, 0.0, TAU)
		wheel_sel = int(round(ang / (TAU / WHEEL.size()))) % WHEEL.size()
	for i in WHEEL.size():
		(wheel.get_child(i) as Label).add_theme_color_override("font_color", UIK.GOLD if i == wheel_sel else UIK.TEXT)


func _apply_wheel() -> void:
	Engine.time_scale = 1.0
	player.wheel_open = false
	if wheel_sel >= 0:
		var cmd: String = WHEEL[wheel_sel][0]
		var tgt: Node3D = player.rig.lock_target
		if tgt == null:
			var ray := player.rig.aim_ray(120.0, [player.get_rid()])
			if ray["hit"] and ray["hit"]["collider"] is Node3D and ray["hit"]["collider"].has_node("Combatant"):
				tgt = ray["hit"]["collider"]
		if cmd in ["attack", "ability"] and tgt == null:
			EventBus.notify.emit("Kein Ziel anvisiert.", "warn")
		else:
			var n := 0
			for c in get_tree().get_nodes_in_group("companions"):
				if c.rec.get("status", "") == "party":
					var ab := ""
					if cmd == "ability":
						var abl: Array = c.rec.get("abilities", [])
						ab = abl[-1] if not abl.is_empty() else ""
					c.ai.set_command(cmd, tgt, ab)
					n += 1
			EventBus.notify.emit("Befehl an %d Gefährten: %s" % [n, WHEEL[wheel_sel][1]], "info")
	wheel.queue_free()
	wheel = null


# ------------------------------------------------------------------ tutorial (normal, non-spoiler)
func _tutorial(delta: float) -> void:
	if not Settings.get_v("tutorial_hints"):
		return
	tutorial_t -= delta
	if tutorial_t > 0.0:
		return
	tutorial_t = 2.0
	var stage := int(GameState.flag("tutorial_stage", 0))
	var steps := [
		[func(): return true, "Willkommen in Primal Dominion. WASD bewegen, Maus umsehen, V wechselt zwischen Ego- und Third-Person-Ansicht."],
		[func(): return true, "E sammelt an Büschen Fasern und Beeren. Schlage Bäume und Steine mit einer Waffe (Linksklick) – mit Axt und Spitzhacke ergiebiger."],
		[func(): return Inventory.count(GameState.player()["inventory"], "wood") >= 3, "Mit B öffnest du das Baumenü. Baue ein Lagerfeuer, um Fleisch zu braten (E am Feuer)."],
		[func(): return not GameState.state["buildings"].is_empty(), "I: Inventar · U: Herstellen · J: Journal · K: Fähigkeiten · M: Karte · L: Lexikon · P: Forschung · H: Kreaturen."],
		[func(): return Quests.stage("q1_gestrandet") >= 2 or GameState.state["quests"].has("q2_zuflucht"), "Rechtsklick blockt (kurz vor dem Treffer: Parade), C weicht aus, T erfasst Ziele. R/F/G/Z nutzen Fähigkeiten, z. B. Heilung."],
		[func(): return GameState.state["stats"]["tamed"] > 0, "Gefährten: Q halten öffnet das Befehlsrad. E auf ein gesatteltes Reittier steigt auf, X steuert einen Gefährten direkt. Tab pfeift alle herbei."],
		[func(): return GameState.has_base(), "Speichern: F5 an sicheren Orten (Lager, Lagerfeuer, Siedlungen). Automatisches Speichern alle 5 Minuten."],
	]
	if stage >= steps.size():
		return
	if steps[stage][0].call():
		EventBus.notify.emit("Hinweis: " + steps[stage][1], "info")
		GameState.set_flag("tutorial_stage", stage + 1)
		tutorial_t = 14.0
