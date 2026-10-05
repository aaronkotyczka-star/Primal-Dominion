class_name Settlements
extends RefCounted
## Builds villages, camps and story locations with props, stations and NPCs.

static func _poi(id: String) -> Vector3:
	return WorldData.poi_pos(id)


static func _ground(p: Vector3) -> Vector3:
	return Vector3(p.x, WorldData.height_at(p.x, p.z), p.z)


static func _prop(w: Node3D, kind: String, pos: Vector3, rot: float = 0.0, collide: bool = true) -> Node3D:
	var root := StaticBody3D.new()
	root.collision_layer = 8 if collide else 0
	w.add_child(root)
	root.global_position = _ground(pos)
	root.rotation.y = rot
	root.add_child(BuildingVisuals.make(kind))
	if collide:
		for sh in BuildingVisuals.collision_shapes(kind):
			var cs := CollisionShape3D.new()
			cs.shape = sh[0]
			cs.position = sh[1]
			root.add_child(cs)
	return root


static func _station(w: Node3D, kind: String, station: String, pos: Vector3, rot: float = 0.0) -> void:
	var n := _prop(w, kind, pos, rot)
	n.add_to_group("village_stations")
	n.set_meta("station", station)
	var it := Interactable.new()
	it.radius = 2.8
	it.position = Vector3(0, 0.8, 0)
	n.add_child(it)
	var label: String = DB.building(kind).get("name", kind)
	it.prompt = "E: %s benutzen" % label
	it.on_interact = func(_p):
		var ui := w.get_tree().get_first_node_in_group("ui")
		if station == "research":
			ui.open_research(true)
		else:
			ui.open_crafting(station)


static func _npc(w: Node3D, id: String, pos: Vector3, hostile: bool = false) -> NPC:
	var def := DB.npc(id)
	var n := NPC.new()
	w.actors.add_child(n)
	n.setup(id, def, _ground(pos) + Vector3(0, 0.2, 0), hostile)
	return n


static func _ring(w: Node3D, center: Vector3, r: float, gate_angle: float) -> void:
	var seg := int(TAU * r / 4.0)
	for i in seg:
		var a := TAU * i / seg
		if absf(wrapf(a - gate_angle, -PI, PI)) < 0.12:
			if absf(wrapf(a - gate_angle, -PI, PI)) < 0.06:
				_prop(w, "palisade_gate", center + Vector3(cos(a), 0, sin(a)) * r, -a + PI * 0.5)
			continue
		_prop(w, "palisade", center + Vector3(cos(a), 0, sin(a)) * r, -a + PI * 0.5)


static func build(w: Node3D) -> void:
	_morgengrau(w)
	_moosfell(w)
	_knochenbrecher(w)
	_fischerkap(w)
	_alte_warte(w)
	_schrein(w)
	_rift(w)
	_tarpit(w)
	_volcano(w)
	_temple(w)
	_citadel(w)
	_oasis(w)
	for id in ["wurzelhoehle", "weisszahn_hoehle"]:
		_cave_mouth(w, id)
	var ad := _poi("adlerhorst")
	pickup(w, ad + Vector3(3, 0, -2), "journal_page_3", 1, "page3", "Tagebuchseite aufheben")
	pickup(w, ad + Vector3(-4, 0, 3), "ancient_tablet", 1, "adler_tablet")
	pickup(w, ad + Vector3(0, 0, 6), "elemental_essence", 4, "adler_essence")


static func _morgengrau(w: Node3D) -> void:
	var c := _poi("morgengrau")
	var to_start := (_poi("start_beach") - c)
	to_start.y = 0
	var gate := atan2(to_start.z, to_start.x)
	_ring(w, c, 34.0, gate)
	for k in 6:
		var a := k * TAU / 6.0 + 0.4
		if absf(wrapf(a - gate, -PI, PI)) < 0.5:
			continue
		_prop(w, "hut", c + Vector3(cos(a), 0, sin(a)) * 22.0, -a)
	_prop(w, "campfire", c + Vector3(0, 0, 0))
	_station(w, "campfire", "campfire", c + Vector3(0.2, 0, 0.2))
	_station(w, "workbench", "workbench", c + Vector3(-8, 0, 6), 0.4)
	_station(w, "forge", "forge", c + Vector3(-12, 0, 0), 1.2)
	_station(w, "research_table", "research", c + Vector3(7, 0, -5), -0.6)
	_station(w, "alchemy_table", "alchemy", c + Vector3(9, 0, 1), -1.2)
	for k in 6:
		var a2 := k * TAU / 6.0
		_prop(w, "torch_post", c + Vector3(cos(a2), 0, sin(a2)) * 15.0, 0.0, false)
	_prop(w, "banner", c + Vector3(3, 0, 3), 0.0, false)
	_npc(w, "ilsa", c + Vector3(4, 0, -3))
	_npc(w, "tomas", c + Vector3(-10, 0, 3))
	_npc(w, "siedler", c + Vector3(-4, 0, -10))
	_npc(w, "siedlerin", c + Vector3(12, 0, 8))
	_npc(w, "siedler", c + Vector3(16, 0, -14))


static func _moosfell(w: Node3D) -> void:
	var c := _poi("moosfell")
	for k in 8:
		var a := k * TAU / 8.0
		var hut := _prop(w, "hut", c + Vector3(cos(a), 0, sin(a)) * (18.0 + (k % 2) * 7.0), -a)
		hut.scale = Vector3(0.75, 0.75, 0.75)
	_prop(w, "campfire", c)
	_station(w, "campfire", "campfire", c + Vector3(0.3, 0, 0.3))
	_station(w, "alchemy_table", "alchemy", c + Vector3(-6, 0, 5), 0.8)
	for k in 5:
		var a2 := k * TAU / 5.0 + 0.3
		var t := _prop(w, "banner", c + Vector3(cos(a2), 0, sin(a2)) * 12.0, a2, false)
	_npc(w, "grukk", c + Vector3(3, 0, 0))
	_npc(w, "nixa", c + Vector3(-5, 0, 4))
	for k in 4:
		_npc(w, "moosfell_goblin", c + Vector3(cos(k * 1.6) * 10.0, 0, sin(k * 1.6) * 10.0))


static func _knochenbrecher(w: Node3D) -> void:
	var c := _poi("knochenbrecher")
	for k in 7:
		var a := k * TAU / 7.0
		var hut := _prop(w, "hut", c + Vector3(cos(a), 0, sin(a)) * 20.0, -a)
		hut.scale = Vector3(0.8, 0.9, 0.8)
		# bone arches
		var arch := Node3D.new()
		w.add_child(arch)
		arch.global_position = _ground(c + Vector3(cos(a + 0.45), 0, sin(a + 0.45)) * 26.0)
		for s in [-1, 1]:
			BuildingVisuals.cyl(arch, 0.05, 0.25, 4.0, Vector3(s * 1.2, 1.8, 0), BuildingVisuals.plain("bone", Color(0.85, 0.82, 0.72), 0.6), Vector3(0, 0, -s * 0.35))
	_prop(w, "campfire", c)
	_station(w, "workbench", "workbench", c + Vector3(6, 0, -4), 0.5)
	var sk := _npc(w, "skarza", c + Vector3(0, 0, -6))
	sk.boss_id = "skarza"
	w.set_meta("skarza", sk)
	for k in 5:
		_npc(w, "knochenbrecher_krieger", c + Vector3(cos(k * 1.3) * 12.0, 0, sin(k * 1.3) * 12.0))


static func _fischerkap(w: Node3D) -> void:
	var c := _poi("fischerkap")
	for k in 4:
		var a := k * TAU / 4.0 + 0.3
		var t := _prop(w, "infirmary", c + Vector3(cos(a), 0, sin(a)) * 10.0, -a)
		t.scale = Vector3(0.8, 0.7, 0.8)
	_prop(w, "campfire", c)
	_station(w, "forge", "forge", c + Vector3(-5, 0, 6), 0.3)
	_prop(w, "banner", c + Vector3(2, 0, -2), 0.0, false)
	_npc(w, "brannoc", c + Vector3(3, 0, 3))
	_npc(w, "soeldner", c + Vector3(-6, 0, -3))
	_npc(w, "soeldner", c + Vector3(7, 0, -6))


static func _readable(w: Node3D, pos: Vector3, text_id: String, title: String, flag: String = "", research: String = "") -> void:
	var stone := Node3D.new()
	w.add_child(stone)
	stone.global_position = _ground(pos)
	BuildingVisuals.box(stone, Vector3(1.2, 1.8, 0.35), Vector3(0, 0.9, 0), BuildingVisuals.stone())
	var it := Interactable.new()
	it.prompt = "E: %s lesen" % title
	it.radius = 2.5
	it.position = Vector3(0, 1, 0)
	stone.add_child(it)
	it.on_interact = func(_p):
		var ui := w.get_tree().get_first_node_in_group("ui")
		ui.show_text(title, DB.t("texts").get(text_id, "…"))
		if flag != "":
			GameState.set_flag(flag, true)
		if research != "":
			Research.unlock_source(research)
			EventBus.notify.emit("Neues Wissen: %s im Forschungsbuch verfügbar." % DB.research(research).get("name", ""), "good")


static func pickup(w: Node3D, pos: Vector3, item_id: String, n: int, once_key: String, label: String = "") -> void:
	if once_key != "" and once_key in GameState.state["world"]["looted"]:
		return
	var node := Node3D.new()
	w.add_child(node)
	node.global_position = _ground(pos) + Vector3(0, 0.1, 0)
	var is_page := item_id.begins_with("journal")
	if is_page:
		BuildingVisuals.box(node, Vector3(0.3, 0.02, 0.4), Vector3(0, 0.02, 0), BuildingVisuals.plain("paper", Color(0.85, 0.8, 0.65), 0.9))
	else:
		BuildingVisuals.box(node, Vector3(0.8, 0.5, 0.55), Vector3(0, 0.25, 0), BuildingVisuals.wood())
	Fx.glow_light(node, Color(1.0, 0.85, 0.5), 3.5, 0.5).position = Vector3(0, 0.6, 0)
	var it := Interactable.new()
	it.prompt = "E: " + (label if label != "" else "%s aufheben" % DB.item_name(item_id))
	it.radius = 2.4
	node.add_child(it)
	it.on_interact = func(_p):
		Inventory.add(GameState.player()["inventory"], item_id, n)
		if once_key != "":
			GameState.state["world"]["looted"].append(once_key)
		EventBus.notify.emit("Gefunden: %d× %s" % [n, DB.item_name(item_id)], "good")
		EventBus.inventory_changed.emit()
		Audio.play_ui("pickup")
		if is_page:
			Quests.start("sq_ewald")
			GameState.set_flag("read_" + item_id, true)
			var ui := w.get_tree().get_first_node_in_group("ui")
			ui.show_text(DB.item_name(item_id), DB.t("texts").get(item_id, ""))
		node.queue_free()


static func _alte_warte(w: Node3D) -> void:
	var c := _poi("alte_warte")
	var tower := Node3D.new()
	w.add_child(tower)
	tower.global_position = _ground(c)
	for k in 10:
		var a := k * TAU / 10.0
		var h := 3.0 + 6.0 * absf(sin(k * 1.7))
		BuildingVisuals.box(tower, Vector3(2.6, h, 1.0), Vector3(cos(a) * 5.0, h * 0.5, sin(a) * 5.0), BuildingVisuals.stone(), Vector3(0, -a, 0))
	var body := StaticBody3D.new()
	body.collision_layer = 8
	tower.add_child(body)
	for k in 10:
		var a2 := k * TAU / 10.0
		if k == 3:
			continue
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(2.6, 6.0, 1.0)
		cs.shape = bs
		cs.position = Vector3(cos(a2) * 5.0, 3.0, sin(a2) * 5.0)
		cs.rotation.y = -a2
		body.add_child(cs)
	_readable(w, c + Vector3(1.5, 0, 0), "inscription_warte", "Inschrift der Alten Warte", "read_warte")
	pickup(w, c + Vector3(-1.5, 0, 1.0), "journal_page_1", 1, "page1", "Tagebuchseite aufheben")
	pickup(w, c + Vector3(0, 0, -2.5), "ancient_tablet", 1, "warte_tablet")


static func _schrein(w: Node3D) -> void:
	var c := _poi("schrein")
	var sh := Node3D.new()
	w.add_child(sh)
	sh.global_position = _ground(c)
	BuildingVisuals.box(sh, Vector3(4, 0.6, 4), Vector3(0, 0.3, 0), BuildingVisuals.stone())
	BuildingVisuals.cyl(sh, 0.5, 0.7, 2.4, Vector3(0, 1.8, 0), BuildingVisuals.stone())
	for s in [-1, 1]:
		var horn := BuildingVisuals.cyl(sh, 0.0, 0.25, 1.6, Vector3(s * 0.6, 3.4, 0), BuildingVisuals.plain("horn_dark", Color(0.12, 0.08, 0.07), 0.4), Vector3(0, 0, -s * 0.6), 6)
	for k in 6:
		var a := k * TAU / 6.0
		BuildingVisuals.cyl(sh, 0.2, 0.3, 1.6 + (k % 2), Vector3(cos(a) * 4.5, 0.8, sin(a) * 4.5), BuildingVisuals.stone())
	Fx.glow_light(sh, Color(0.8, 0.15, 0.1), 7.0, 0.6).position = Vector3(0, 3.0, 0)
	_readable(w, c + Vector3(3, 0, 2.5), "inscription_schrein", "Inschrift des Schreins", "read_schrein", "pact_lore")
	var it := Interactable.new()
	it.radius = 3.0
	it.position = Vector3(0, 1.2, 0)
	sh.add_child(it)
	it.prompt_fn = func(_p): return Encounters.shrine_prompt()
	it.on_interact = func(p): Encounters.shrine_ritual(w, p)


static func _rift(w: Node3D) -> void:
	var c := _poi("riss_narbenschlund")
	var rift := Node3D.new()
	rift.name = "Rift"
	w.add_child(rift)
	rift.global_position = _ground(c)
	var m := BuildingVisuals.plain("rift_core", Color(1.0, 0.15, 0.25), 0.1, 0.0, 6.0)
	var crack := BuildingVisuals.box(rift, Vector3(0.6, 14.0, 4.0), Vector3(0, 9.0, 0), m)
	crack.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for k in 12:
		var a := k * TAU / 12.0
		BuildingVisuals.cyl(rift, 0.0, 0.6, 3.0 + (k % 3) * 1.5, Vector3(cos(a) * (9.0 + k % 4), 1.5, sin(a) * (9.0 + k % 3)), BuildingVisuals.plain("rift_crystal", Color(0.9, 0.15, 0.5), 0.2, 0.2, 2.5), Vector3(sin(k) * 0.3, 0, cos(k) * 0.3), 5)
	Fx.glow_light(rift, Color(1.0, 0.2, 0.3), 40.0, 4.0).position = Vector3(0, 8, 0)
	w.set_meta("rift_node", rift)
	# ward seal stone circle at entry
	var seal_pos := c + Vector3(0, 0, 70)
	var seal := Node3D.new()
	w.add_child(seal)
	seal.global_position = _ground(seal_pos)
	for k in 8:
		var a := k * TAU / 8.0
		BuildingVisuals.box(seal, Vector3(1.0, 3.0, 0.6), Vector3(cos(a) * 6.0, 1.5, sin(a) * 6.0), BuildingVisuals.stone(), Vector3(0, -a, 0))
	var barrier := StaticBody3D.new()
	barrier.collision_layer = 8
	barrier.name = "Barrier"
	seal.add_child(barrier)
	var wall_mat := BuildingVisuals.plain("ward", Color(0.6, 0.3, 1.0, 1.0), 0.0, 0.0, 1.5)
	var wall := BuildingVisuals.cyl(seal, 60.0, 60.0, 30.0, Vector3(0, 10, -70), wall_mat, Vector3.ZERO, 48)
	wall.transparency = 0.75
	wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	wall.name = "WardWall"
	# barrier collision ring (only blocks the player while sealed)
	for k in 40:
		var a2 := k * TAU / 40.0
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(10.0, 40.0, 1.0)
		cs.shape = bs
		cs.position = Vector3(cos(a2) * 60.0, 15.0, -70.0 + sin(a2) * 60.0)
		cs.rotation.y = -a2 + PI * 0.5
		barrier.add_child(cs)
	w.set_meta("seal", seal)
	if GameState.flag("seal_opened", false):
		barrier.queue_free()
		wall.queue_free()
	var it := Interactable.new()
	it.radius = 7.0
	it.position = Vector3(0, 1, 0)
	seal.add_child(it)
	it.prompt_fn = func(_p): return "" if GameState.flag("seal_opened", false) else ("E: Siegel mit dem Bannschlüssel öffnen" if Inventory.count(GameState.player()["inventory"], "ward_key") > 0 else "Ein uraltes Siegel. Ein Bannschlüssel wird benötigt.")
	it.condition = func(_p): return not GameState.flag("seal_opened", false) and Inventory.count(GameState.player()["inventory"], "ward_key") > 0
	it.on_interact = func(_p): Encounters.open_seal(w)
	pickup(w, c + Vector3(20, 0, 30), "rift_shard", 2, "rift_shards_a")


static func _tarpit(w: Node3D) -> void:
	var c := _poi("teergrube")
	var pit := Node3D.new()
	w.add_child(pit)
	pit.global_position = _ground(c) + Vector3(0, 0.05, 0)
	var tar := BuildingVisuals.cyl(pit, 9.0, 9.0, 0.1, Vector3(0, 0.0, 0), BuildingVisuals.plain("tar", Color(0.02, 0.02, 0.02), 0.08, 0.2), Vector3.ZERO, 24)
	for k in 5:
		BuildingVisuals.cyl(pit, 0.08, 0.12, 1.6, Vector3(cos(k) * 5.0, 0.5, sin(k * 1.4) * 5.0), BuildingVisuals.plain("bone", Color(0.85, 0.82, 0.72), 0.6), Vector3(0.6, k, 0.3))
	pickup(w, c + Vector3(11, 0, -3), "journal_page_2", 1, "page2", "Tagebuchseite aufheben")


static func _volcano(w: Node3D) -> void:
	var c := _poi("vulkan_krater")
	var lava := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 40.0
	pm.bottom_radius = 40.0
	pm.height = 0.5
	lava.mesh = pm
	lava.material_override = BuildingVisuals.plain("lava", Color(1.0, 0.35, 0.05), 0.4, 0.0, 4.0)
	w.add_child(lava)
	lava.global_position = Vector3(c.x, WorldData.height_at(c.x, c.z) + 1.5, c.z)
	Fx.glow_light(lava, Color(1.0, 0.4, 0.1), 60.0, 3.0).position = Vector3(0, 6, 0)
	var nest := _poi("wyvern_nest")
	pickup(w, nest + Vector3(4, 0, 0), "elemental_essence", 3, "wyvern_nest_cache")


static func _temple(w: Node3D) -> void:
	var c := _poi("versunkener_tempel")
	var t := Node3D.new()
	w.add_child(t)
	t.global_position = Vector3(c.x, -28.0, c.z)
	for k in 10:
		var a := k * TAU / 10.0
		var h := 4.0 + 6.0 * absf(sin(k * 2.3))
		BuildingVisuals.cyl(t, 0.9, 1.1, h, Vector3(cos(a) * 14.0, h * 0.5, sin(a) * 14.0), BuildingVisuals.stone())
	BuildingVisuals.box(t, Vector3(10, 1.0, 10), Vector3(0, 0.5, 0), BuildingVisuals.stone())
	Fx.glow_light(t, Color(0.3, 0.8, 1.0), 20.0, 2.0).position = Vector3(0, 4, 0)
	pickup(w, Vector3(c.x + 2, -27.0, c.z), "ancient_tablet", 2, "temple_tablets")
	pickup(w, Vector3(c.x - 3, -27.0, c.z + 2), "essence_light", 2, "temple_light")


static func _citadel(w: Node3D) -> void:
	var c := _poi("narbe_zitadelle")
	var t := Node3D.new()
	w.add_child(t)
	t.global_position = _ground(c)
	var dark := BuildingVisuals.plain("obsidian_wall", Color(0.06, 0.04, 0.06), 0.2, 0.3)
	BuildingVisuals.cyl(t, 3.0, 9.0, 40.0, Vector3(0, 20, 0), dark, Vector3.ZERO, 7)
	for k in 6:
		var a := k * TAU / 6.0
		BuildingVisuals.cyl(t, 0.5, 2.5, 16.0, Vector3(cos(a) * 20.0, 8.0, sin(a) * 20.0), dark, Vector3(sin(a) * 0.2, 0, cos(a) * 0.2), 5)
	Fx.glow_light(t, Color(1.0, 0.1, 0.2), 50.0, 4.0).position = Vector3(0, 42, 0)


static func _oasis(w: Node3D) -> void:
	var c := _poi("oase")
	var pond := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 16.0
	pm.bottom_radius = 16.0
	pm.height = 0.1
	pond.mesh = pm
	pond.material_override = BuildingVisuals.plain("oasis_water", Color(0.1, 0.3, 0.32), 0.05, 0.1)
	w.add_child(pond)
	pond.global_position = _ground(c) + Vector3(0, 0.12, 0)


static func _cave_mouth(w: Node3D, id: String) -> void:
	var c := _poi(id)
	var m := Node3D.new()
	w.add_child(m)
	m.global_position = _ground(c)
	BuildingVisuals.box(m, Vector3(8, 6, 1.0), Vector3(0, 3, 0), BuildingVisuals.plain("cave_dark", Color(0.02, 0.02, 0.02), 1.0))
	for s in [-1, 1]:
		BuildingVisuals.box(m, Vector3(3, 8, 4), Vector3(s * 5.5, 4, 0), BuildingVisuals.stone())
	BuildingVisuals.box(m, Vector3(14, 3, 4), Vector3(0, 8.5, 0), BuildingVisuals.stone())
	var it := Interactable.new()
	it.prompt = "Höhleneingang – die Höhlen sind in dieser Version noch nicht begehbar."
	it.radius = 6.0
	it.position = Vector3(0, 1, 1)
	m.add_child(it)
	it.condition = func(_p): return false
	if id == "wurzelhoehle":
		pickup(w, c + Vector3(4, 0, 6), "crystal", 3, "cave_crystals")
