class_name HUD
extends Control
## Heads-up display: vitals, hotbar/abilities, target & danger info, quest tracker, companions, notifications.

var player: Player
var hp_bar: ProgressBar
var st_bar: ProgressBar
var hu_bar: ProgressBar
var br_bar: ProgressBar
var xp_bar: ProgressBar
var lvl_label: Label
var status_label: Label
var time_label: Label
var region_label: Label
var compass: Label
var prompt: Label
var crosshair: Label
var target_box: VBoxContainer
var target_name: Label
var target_bar: ProgressBar
var target_info: Label
var tracker: VBoxContainer
var comp_box: VBoxContainer
var notes: VBoxContainer
var hotbar: HBoxContainer
var abil_bar: HBoxContainer
var mount_box: VBoxContainer
var mount_hp: ProgressBar
var mount_st: ProgressBar
var mount_label: Label
var build_hint: Label
var amber_label: Label
var _t := 0.0
var _region_name := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UIK.get_theme()
	# vitals
	var vit := UIK.vbox(4)
	UIK.anchor(vit, 0, 0, 24, 20)
	add_child(vit)
	var top := UIK.hbox(10)
	lvl_label = UIK.label("Stufe 1", 18, UIK.GOLD)
	amber_label = UIK.label("", 16, Color(0.95, 0.7, 0.3))
	top.add_child(lvl_label)
	top.add_child(amber_label)
	vit.add_child(top)
	hp_bar = _vbar(vit, "Leben", UIK.RED)
	st_bar = _vbar(vit, "Ausdauer", Color(0.75, 0.75, 0.3))
	hu_bar = _vbar(vit, "Hunger", Color(0.85, 0.55, 0.2))
	br_bar = _vbar(vit, "Atem", UIK.BLUE)
	xp_bar = UIK.bar(Color(0.6, 0.5, 0.85), 230, 6)
	vit.add_child(xp_bar)
	status_label = UIK.label("", 14, Color(0.85, 0.75, 0.6))
	vit.add_child(status_label)
	# top center
	var tc := UIK.vbox(2)
	UIK.anchor(tc, 0.5, 0, -220, 10, 440, 0)
	add_child(tc)
	compass = UIK.label("", 18, UIK.TEXT)
	compass.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tc.add_child(compass)
	time_label = UIK.label("", 14, UIK.DIM)
	time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tc.add_child(time_label)
	# target
	target_box = UIK.vbox(2)
	UIK.anchor(target_box, 0.5, 0, -200, 70, 400, 0)
	add_child(target_box)
	target_name = UIK.label("", 19, UIK.TEXT)
	target_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	target_box.add_child(target_name)
	target_bar = UIK.bar(UIK.RED, 400, 10)
	target_box.add_child(target_bar)
	target_info = UIK.label("", 14, UIK.DIM)
	target_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	target_box.add_child(target_info)
	# region banner
	region_label = UIK.label("", 34, UIK.GOLD)
	UIK.anchor(region_label, 0.5, 0, -300, 150, 600, 0)
	region_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	region_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	region_label.add_theme_constant_override("outline_size", 6)
	region_label.modulate.a = 0.0
	add_child(region_label)
	# crosshair & prompt
	crosshair = UIK.label("+", 22, Color(1, 1, 1, 0.75))
	UIK.anchor(crosshair, 0.5, 0.5, -7, -16)
	add_child(crosshair)
	prompt = UIK.label("", 19, Color(1, 0.95, 0.8))
	UIK.anchor(prompt, 0.5, 0.5, -300, 40, 600, 0)
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	prompt.add_theme_constant_override("outline_size", 5)
	add_child(prompt)
	build_hint = UIK.label("", 16, Color(0.7, 1.0, 0.7))
	UIK.anchor(build_hint, 0.5, 0.5, -300, 80, 600, 0)
	build_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(build_hint)
	# tracker
	tracker = UIK.vbox(3)
	UIK.anchor(tracker, 1, 0, -430, 20, 410, 0)
	add_child(tracker)
	# companions
	comp_box = UIK.vbox(3)
	UIK.anchor(comp_box, 0, 0.5, 24, -60)
	add_child(comp_box)
	# mount
	mount_box = UIK.vbox(2)
	UIK.anchor(mount_box, 0.5, 1, -150, -160, 300, 0)
	add_child(mount_box)
	mount_label = UIK.label("", 16, UIK.GOLD)
	mount_box.add_child(mount_label)
	mount_hp = UIK.bar(UIK.RED, 300, 10)
	mount_box.add_child(mount_hp)
	mount_st = UIK.bar(Color(0.75, 0.75, 0.3), 300, 6)
	mount_box.add_child(mount_st)
	mount_box.visible = false
	# hotbar & abilities
	var bottom := UIK.hbox(24)
	UIK.anchor(bottom, 0.5, 1, -330, -88)
	add_child(bottom)
	hotbar = UIK.hbox(4)
	bottom.add_child(hotbar)
	abil_bar = UIK.hbox(4)
	bottom.add_child(abil_bar)
	for i in 6:
		hotbar.add_child(_slot(str(i + 1)))
	for k in ["R", "F", "G", "Z"]:
		abil_bar.add_child(_slot(k))
	# notifications
	notes = UIK.vbox(4)
	UIK.anchor(notes, 1, 1, -520, -400, 500, 0)
	add_child(notes)
	EventBus.notify.connect(_on_notify)
	EventBus.region_entered.connect(_on_region)


func _vbar(parent: Node, name: String, col: Color) -> ProgressBar:
	var h := UIK.hbox(6)
	var l := UIK.label(name, 13, UIK.DIM)
	l.custom_minimum_size = Vector2(70, 0)
	h.add_child(l)
	var b := UIK.bar(col, 230, 12)
	h.add_child(b)
	parent.add_child(h)
	b.set_meta("row", h)
	return b


func _slot(key: String) -> PanelContainer:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(58, 58)
	var ic := TextureRect.new()
	ic.name = "Icon"
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(ic)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	p.add_child(v)
	var k := UIK.label(key, 12, UIK.GOLD)
	v.add_child(k)
	var n := UIK.label("", 11, UIK.TEXT)
	n.name = "N"
	n.clip_text = true
	n.custom_minimum_size = Vector2(52, 0)
	v.add_child(n)
	var c := UIK.label("", 12, UIK.DIM)
	c.name = "C"
	v.add_child(c)
	return p


func _on_notify(text: String, kind: String) -> void:
	var col = {"info": UIK.TEXT, "warn": Color(1.0, 0.75, 0.35), "danger": Color(1.0, 0.4, 0.35), "good": UIK.GREEN, "quest": UIK.GOLD,
		"whisper": Color(0.85, 0.35, 0.45), "region": UIK.GOLD}.get(kind, UIK.TEXT)
	if kind == "region":
		return
	var l := UIK.label(text, 16, col, true)
	l.custom_minimum_size = Vector2(500, 0)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 4)
	if kind == "whisper":
		l.add_theme_font_size_override("font_size", 18)
	notes.add_child(l)
	while notes.get_child_count() > 7:
		notes.get_child(0).queue_free()
		notes.remove_child(notes.get_child(0))
	var tw := l.create_tween()
	tw.tween_interval(6.0 if kind != "quest" else 9.0)
	tw.tween_property(l, "modulate:a", 0.0, 1.0)
	tw.tween_callback(l.queue_free)
	if kind == "danger":
		Audio.play_ui("ui_error")


func _on_region(rid: String) -> void:
	var reg := {}
	for r in WorldData.info["regions"]:
		if r["id"] == rid:
			reg = r
	if reg.is_empty() or reg.get("water", false):
		return
	region_label.text = reg["name"]
	var tw := region_label.create_tween()
	tw.tween_property(region_label, "modulate:a", 1.0, 0.8)
	tw.tween_interval(2.5)
	tw.tween_property(region_label, "modulate:a", 0.0, 1.5)


func _process(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	var p := GameState.player()
	hp_bar.max_value = player.combatant.max_hp
	hp_bar.value = player.combatant.hp
	st_bar.max_value = player.max_stamina
	st_bar.value = player.stamina
	hu_bar.value = float(p["hunger"])
	br_bar.max_value = player.max_breath
	br_bar.value = player.breath
	br_bar.get_meta("row").visible = player.breath < player.max_breath - 0.1
	xp_bar.max_value = GameState.xp_for_level(p["level"])
	xp_bar.value = p["xp"]
	lvl_label.text = "Stufe %d%s" % [p["level"], "   [Dämon %d]" % p["demon"]["level"] if player.demon_form else ""]
	amber_label.text = "◆ %d Bernstein" % GameState.amber()
	var stx := player.combatant.status_text()
	var buffs := []
	for b in player.combatant.buffs:
		if not b.ends_with("_cd"):
			buffs.append(b.capitalize())
	if float(p["hunger"]) < 25.0:
		buffs.append("HUNGRIG")
	if player.crouching:
		buffs.append("geduckt")
	status_label.text = ("Zustände: " + stx + "  " if stx != "" else "") + ("  ".join(buffs))
	_t -= delta
	if _t <= 0.0:
		_t = 0.25
		_slow_update()
	# prompt & crosshair
	prompt.text = player.interact_prompt
	crosshair.visible = not player.ui_blocking
	_target_update()
	var w := get_tree().get_first_node_in_group("world") as World
	if w and w.buildings.is_placing():
		build_hint.text = "LMB: Platzieren   R: Drehen   RMB/B: Abbrechen   (Shift halten: mehrfach)\n" + ("Platzierung möglich" if w.buildings.ghost_ok else w.buildings.ghost_reason)
		build_hint.add_theme_color_override("font_color", Color(0.7, 1.0, 0.7) if w.buildings.ghost_ok else Color(1.0, 0.6, 0.5))
	else:
		build_hint.text = ""
	# mount
	var m: Creature = player.mount if player.mount else player.controlled
	mount_box.visible = m != null
	if m:
		mount_label.text = ("Reitet: " if player.mount else "Steuert: ") + m.rec["name"]
		mount_hp.max_value = m.combatant.max_hp
		mount_hp.value = m.combatant.hp
		mount_st.max_value = m.stats["stam"]
		mount_st.value = m.stamina


func _slow_update() -> void:
	var p := GameState.player()
	var sky: SkyWeather = get_tree().get_first_node_in_group("sky_weather")
	time_label.text = "%s · %s" % [GameState.time_label(), sky.weather_label() if sky else ""]
	var yaw := wrapf(-player.rig.yaw, 0.0, TAU)
	var dirs := ["N", "NO", "O", "SO", "S", "SW", "W", "NW"]
	var idx := int(round(yaw / (TAU / 8.0))) % 8
	var marker := _quest_marker()
	compass.text = "◂  %s  ▸%s" % [dirs[idx], marker]
	# hotbar
	var inv: Array = p["inventory"]
	for i in 6:
		var slot: PanelContainer = hotbar.get_child(i)
		var id: String = p["hotbar"][i]
		var box: Control = slot.get_child(1)
		var n: Label = box.get_child(1)
		var c: Label = box.get_child(2)
		var icon: TextureRect = slot.get_node("Icon")
		var ip := "res://assets/icons/%s.png" % id
		if id == "":
			n.text = ""
			c.text = ""
			icon.texture = null
		else:
			icon.texture = load(ip) if ResourceLoader.exists(ip) else null
			n.text = "" if icon.texture != null else DB.item_name(id)
			slot.tooltip_text = DB.item_name(id)
			var cnt := Inventory.count(inv, id)
			if p["equipment"]["weapon"] == id:
				c.text = "ausgerüstet"
			else:
				c.text = "×%d" % cnt
	var lo: Array = player.combat.loadout()
	for i in 4:
		var slot2: PanelContainer = abil_bar.get_child(i)
		var n2: Label = slot2.get_child(1).get_child(1)
		var c2: Label = slot2.get_child(1).get_child(2)
		var ab: String = lo[i] if i < lo.size() else ""
		if player.mount or player.controlled:
			var cr: Creature = player.mount if player.mount else player.controlled
			var abl: Array = cr.rec.get("abilities", [])
			ab = abl[i] if i < abl.size() else ""
			n2.text = DB.ability(ab).get("name", "") if ab != "" else ""
			c2.text = ("%.0fs" % AbilityRunner.cd_left(cr, ab)) if ab != "" and AbilityRunner.cd_left(cr, ab) > 0 else ""
		else:
			n2.text = DB.ability(ab).get("name", "") if ab != "" else ""
			c2.text = ("%.0fs" % AbilityRunner.cd_left(player, ab)) if ab != "" and AbilityRunner.cd_left(player, ab) > 0 else ""
	# tracker
	UIK.clear(tracker)
	var shown := 0
	for qid in Quests.tracked():
		if shown >= 3:
			break
		var qd := DB.quest(qid)
		var sd := Quests.current_stage_def(qid)
		if sd.is_empty():
			continue
		var t := UIK.label(qd["name"], 17 if shown == 0 else 15, UIK.GOLD if qd.get("main", false) else UIK.TEXT)
		t.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		t.add_theme_constant_override("outline_size", 4)
		tracker.add_child(t)
		if shown == 0:
			var d := UIK.label(sd["text"], 14, UIK.TEXT, true)
			d.custom_minimum_size = Vector2(410, 0)
			d.add_theme_color_override("font_outline_color", Color(0, 0, 0))
			d.add_theme_constant_override("outline_size", 3)
			tracker.add_child(d)
		var objs: Array = sd.get("obj", [])
		for i in objs.size():
			var o := UIK.label("  " + Quests.objective_text(qid, i, objs[i]), 14, UIK.DIM)
			o.add_theme_color_override("font_outline_color", Color(0, 0, 0))
			o.add_theme_constant_override("outline_size", 3)
			tracker.add_child(o)
		shown += 1
	# companions
	UIK.clear(comp_box)
	for c in get_tree().get_nodes_in_group("companions"):
		if c.rec.get("status", "") != "party":
			continue
		var row := UIK.vbox(1)
		var d2: float = c.global_position.distance_to(player.global_position)
		var warn := ""
		if d2 > 80.0:
			warn = "  ⚠ %dm zurück" % int(d2)
		if float(c.rec.get("hunger", 80)) < 20.0:
			warn += "  ⚠ hungrig"
		if c.combatant.hp_frac() < 0.3:
			warn += "  ⚠ schwer verletzt"
		var cmd: String = {"follow": "folgt", "wait": "wartet", "defend": "verteidigt", "attack": "greift an", "retreat": "Rückzug", "ability": "Fähigkeit"}.get(c.ai.command, c.ai.command)
		var l := UIK.label("%s (St. %d) – %s%s" % [c.rec["name"], c.rec["level"], cmd, warn], 14, Color(1.0, 0.6, 0.4) if warn != "" else UIK.TEXT)
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		l.add_theme_constant_override("outline_size", 3)
		row.add_child(l)
		var b := UIK.bar(UIK.GREEN, 200, 6)
		b.max_value = c.combatant.max_hp
		b.value = c.combatant.hp
		row.add_child(b)
		comp_box.add_child(row)


func _quest_marker() -> String:
	for qid in Quests.tracked():
		var sd := Quests.current_stage_def(qid)
		for o in sd.get("obj", []):
			var pos := Vector3.INF
			if o.has("poi"):
				pos = WorldData.poi_pos(o["poi"])
			elif o.has("at"):
				pos = WorldData.poi_pos(o["at"])
			elif o.has("npc"):
				var nd := DB.npc(o["npc"])
				if nd.has("poi"):
					pos = WorldData.poi_pos(nd["poi"])
			if pos != Vector3.INF:
				var to := pos - player.global_position
				var ang := atan2(to.x, -to.z) + player.rig.yaw
				var rel := wrapf(rad_to_deg(ang), -180, 180)
				var arrow := "↑"
				if absf(rel) > 135:
					arrow = "↓"
				elif rel > 45:
					arrow = "→"
				elif rel < -45:
					arrow = "←"
				elif rel > 15:
					arrow = "↗"
				elif rel < -15:
					arrow = "↖"
				return "     Ziel %s %d m" % [arrow, int(Vector2(to.x, to.z).length())]
	return ""


func _target_update() -> void:
	var t: Node3D = player.rig.lock_target
	if t == null:
		var ray := player.rig.aim_ray(60.0, [player.get_rid()])
		if ray["hit"] and ray["hit"]["collider"] is Node3D and (ray["hit"]["collider"] as Node3D).has_node("Combatant"):
			t = ray["hit"]["collider"]
	if t == null or not is_instance_valid(t) or t.combatant.dead:
		target_box.visible = false
		return
	target_box.visible = true
	target_bar.max_value = t.combatant.max_hp
	target_bar.value = t.combatant.hp
	var info := []
	if t is Creature:
		var c: Creature = t
		var plv := int(GameState.player()["level"])
		var diff := c.level - plv
		var danger := "gering"
		var col := UIK.GREEN
		if diff > 12 or c.is_boss:
			danger = "tödlich"
			col = Color(1.0, 0.2, 0.2)
		elif diff > 5:
			danger = "hoch"
			col = Color(1.0, 0.5, 0.3)
		elif diff > 0:
			danger = "mittel"
			col = Color(1.0, 0.85, 0.4)
		if not c.wild:
			col = UIK.BLUE
		var nm: String = c.rec["name"] if not c.wild else c.sp.get("name", c.species_id)
		if c.alpha:
			nm = "Alpha-" + nm
		target_name.text = "%s  (Stufe %d)" % [nm, c.level]
		target_name.add_theme_color_override("font_color", col)
		if c.wild:
			info.append("Gefahr: " + danger)
			var tm: Dictionary = c.sp.get("tame", {})
			var method: String = {"knockout": "Betäuben & füttern", "trust": "Vertrauen (geduckt, Futter)", "rescue": "Rettung", "egg": "Nur aus dem Ei", "magic": "Bindungsrune (<30% LP)", "pact": "Pakt am Rissaltar"}.get(tm.get("method", ""), "nicht zähmbar")
			if GameState.skill_rank("hunt_tracking") > 0 or GameState.state["lexicon"].get(c.species_id, {}).get("investigated", false):
				info.append("Zähmung: " + method)
			if c.combatant.max_torpor > 0.0 and c.combatant.torpor > 0.0:
				info.append("Betäubung %d%%" % int(c.combatant.torpor / c.combatant.max_torpor * 100.0))
			if c.combatant.unconscious:
				info.append("Zähmung %d%%" % int(c.tame_progress / c.tame_needed * 100.0))
			if tm.get("method", "") == "trust":
				info.append("Scheu %d%%" % int(c.wariness))
		else:
			info.append("Bindung: " + Creatures.bond_label(float(c.rec.get("bond", 0))))
	elif t is NPC:
		target_name.text = t.display_name
		target_name.add_theme_color_override("font_color", Color(1.0, 0.45, 0.4) if t.hostile_npc else UIK.TEXT)
	var stx: String = t.combatant.status_text()
	if stx != "":
		info.append(stx)
	target_info.text = "  ·  ".join(info)
