class_name Encounters
extends RefCounted
## Dynamic story & world encounters: nests, rescues, quest fights, rift assault, bosses, demon path.

static var _active := {}


static func _near(w: World, poi: String, r: float) -> bool:
	return w.player.global_position.distance_to(WorldData.poi_pos(poi)) < r


static func _alive(key: String) -> bool:
	var n = _active.get(key)
	return n != null and is_instance_valid(n) and not n.combatant.dead


static func update(w: World) -> void:
	_nests(w)
	_tarpit(w)
	_wolf(w)
	_zibbel(w)
	_skarza(w)
	_rift(w)
	_herald(w)
	_whispers(w)


# ------------------------------------------------------------------ nests & eggs
static func _nests(w: World) -> void:
	for id in ["raptor_nest_1", "raptor_nest_2", "dilo_nest", "wyvern_nest"]:
		var poi := WorldData.poi(id)
		if not _near(w, id, 170.0):
			continue
		var key = "nest_" + id
		if not _active.has(key):
			_active[key] = true
			_build_nest(w, id, poi)


static func _build_nest(w: World, id: String, poi: Dictionary) -> void:
	var c := WorldData.poi_pos(id)
	var species: String = poi["species"]
	var nest := Node3D.new()
	w.fx_root.add_child(nest)
	nest.global_position = c
	for k in 14:
		var a := k * TAU / 14.0
		BuildingVisuals.cyl(nest, 0.05, 0.07, 2.2, Vector3(cos(a) * 1.3, 0.2, sin(a) * 1.3), BuildingVisuals.wood(), Vector3(PI * 0.5, a + 0.6, 0.2))
	var st: Dictionary = GameState.state["world"]["nests"].get(id, {})
	var day := GameState.get_day()
	var eggs := 0 if int(st.get("taken_day", -99)) + 3 > day else 2
	for e in eggs:
		var egg := Node3D.new()
		nest.add_child(egg)
		egg.position = Vector3(-0.35 + e * 0.7, 0.3, 0)
		var sm := SphereMesh.new()
		sm.radius = 0.2 if species != "wyvern" else 0.35
		sm.height = sm.radius * 2.6
		var mi := MeshInstance3D.new()
		mi.mesh = sm
		mi.material_override = BuildingVisuals.plain("egg_" + species, Color(0.82, 0.78, 0.65) if species != "wyvern" else Color(0.55, 0.15, 0.08), 0.5, 0.0, 0.0 if species != "wyvern" else 0.4)
		egg.add_child(mi)
		var it := Interactable.new()
		it.prompt = "E: %s-Ei nehmen" % DB.species(species)["name"]
		it.radius = 2.5
		egg.add_child(it)
		it.on_interact = func(_p):
			var rng := RandomNumberGenerator.new()
			rng.randomize()
			var variant := {}
			if species == "wyvern":
				variant["element"] = ["fire", "poison", "lightning"][rng.randi() % 3]
			var genes := Genetics.random_genes(species, rng, variant)
			Inventory.add(GameState.player()["inventory"], "egg", 1, 1.0, {"name": "%s-Ei" % DB.species(species)["name"], "genes": genes, "species": species})
			GameState.state["world"]["nests"][id] = {"taken_day": GameState.get_day()}
			EventBus.notify.emit("Ei genommen! Bring es zu einer Brutstätte. Die Eltern sind wütend!", "warn")
			EventBus.inventory_changed.emit()
			for cr in w.get_tree().get_nodes_in_group("creatures"):
				if cr.wild and cr.species_id == species and cr.global_position.distance_to(c) < 60.0:
					cr.ai.target = w.player
					cr.ai.threat_memory[w.player.get_instance_id()] = 60.0
					cr.ai._go("chase", 30.0)
			egg.queue_free()
	# guardians
	var n := 3 if species == "raptor" else (2 if species == "dilophosaurus" else 1)
	var lv: int = 5 if species == "raptor" else (8 if species == "dilophosaurus" else 30)
	for k in n:
		var g := w.spawn_wild(species, lv + k, c + Vector3(cos(k * 2.0) * 8.0, 0, sin(k * 2.0) * 8.0))
		if g:
			g.nest_guard = c
			g.ai.home = c
			g.ai.aggro_r = 30.0
			g.ai.temper = "territorial" if species != "raptor" else "predator"


# ------------------------------------------------------------------ rescue scenarios
static func _tarpit(w: World) -> void:
	if GameState.flag("stego_rescued", false) or not _near(w, "teergrube", 160.0):
		return
	if _alive("tar_stego"):
		return
	if _active.has("tar_stego"):
		return
	var c := WorldData.poi_pos("teergrube")
	var st := w.spawn_wild("stegosaurus", 9, c + Vector3(1, 0, 1))
	if st == null:
		return
	st.in_need = "tar"
	st.global_position.y = c.y - 0.7
	st.combatant.team = "neutral"
	_active["tar_stego"] = st
	Quests.start("sq_teer")
	for k in 2:
		var r := w.spawn_wild("raptor", 6, c + Vector3(18 + k * 4, 0, -10))
		if r:
			r.ai.target = st
			r.ai._go("chase", 30.0)
			r.quest_tag = "tar_predator"


static func _wolf(w: World) -> void:
	if GameState.flag("wolf_rescued", false) or not _near(w, "wolfsschlucht", 140.0):
		return
	if _active.has("wolf"):
		return
	var c := WorldData.poi_pos("wolfsschlucht")
	var wolf := w.spawn_wild("direwolf", 7, c)
	if wolf == null:
		return
	wolf.in_need = "trap"
	wolf.combatant.team = "neutral"
	wolf.combatant.hp = wolf.combatant.max_hp * 0.35
	BuildingVisuals.cyl(wolf, 0.6, 0.65, 0.12, Vector3(0, 0.06, 0), BuildingVisuals.plain("trapm", Color(0.35, 0.3, 0.25), 0.7, 0.3))
	_active["wolf"] = wolf
	Quests.start("sq_wolf")
	EventBus.notify.emit("Ein klägliches Jaulen hallt durch die Schlucht …", "info")


static func _zibbel(w: World) -> void:
	var stg := Quests.stage("q4_moosfell")
	if not Quests.is_active("q4_moosfell") or stg < 1 or stg > 2:
		return
	if not _near(w, "teergrube", 150.0):
		return
	var c := WorldData.poi_pos("teergrube")
	if not _active.has("zibbel") or not is_instance_valid(_active["zibbel"]):
		var z := Settlements._npc(w, "zibbel", c + Vector3(12, 0, 8))
		_active["zibbel"] = z
	if stg == 1 and not _active.has("zibbel_hounds"):
		_active["zibbel_hounds"] = true
		for k in 3:
			var h := w.spawn_wild("hellhound", 6 + k, c + Vector3(16 + cos(k * 2.1) * 6.0, 0, 12 + sin(k * 2.1) * 6.0))
			if h:
				h.quest_tag = "hellhound"
				h.ai.home = c
				h.nest_guard = c + Vector3(12, 0, 8)
		EventBus.notify.emit("Höllenhunde umkreisen den Goblin-Jäger!", "danger")


static func _skarza(w: World) -> void:
	if not GameState.flag("skarza_duel", false) or GameState.flag("skarza_defeated", false):
		return
	var sk = w.get_meta("skarza") if w.has_meta("skarza") else null
	if sk == null or not is_instance_valid(sk):
		return
	if not sk.hostile_npc:
		sk.hostile_npc = true
		sk.combatant.team = "hostile"
		sk.remove_from_group("interactables")
		sk.quest_tag = "skarza"
		sk.combatant.died.connect(func(_k):
			GameState.set_flag("skarza_defeated", true)
			w.drop_loot(sk.global_position, [["ward_key", 1], ["amber_coin", 60]])
			GameState.change_rep("knochenbrecher", 35, "Häuptling im Zweikampf besiegt – sie respektieren dich")
			GameState.state["territories"]["knochenebene"] = {"owner": "player", "since": GameState.get_day(), "how": "erobert"}
			EventBus.notify.emit("Die Knochenebene gehört nun dir! Der Stamm akzeptiert dich als Stärksten.", "quest"))
		EventBus.notify.emit("Skarza nimmt die Herausforderung an! Nur er kämpft – besiege ihn.", "danger")


# ------------------------------------------------------------------ rift assault (act 1 finale)
static func open_seal(w: World) -> void:
	if Inventory.count(GameState.player()["inventory"], "ward_key") <= 0:
		return
	GameState.set_flag("seal_opened", true)
	var seal: Node3D = w.get_meta("seal")
	if seal:
		var b := seal.get_node_or_null("Barrier")
		if b:
			b.queue_free()
		var wall := seal.get_node_or_null("WardWall")
		if wall:
			wall.queue_free()
	Fx.burst(seal.global_position + Vector3.UP * 3, Color(0.6, 0.3, 1.0), w, 80, 0.4, 8.0, 1.5)
	Audio.play_at("explosion", seal.global_position)
	EventBus.notify.emit("Das Siegel bricht! Der Narbenschlund liegt offen.", "quest")
	w.quests.evaluate_all()


static func _rift(w: World) -> void:
	if not GameState.flag("seal_opened", false) or GameState.flag("rift_choice", false):
		return
	if not _near(w, "riss_narbenschlund", 140.0):
		return
	var c := WorldData.poi_pos("riss_narbenschlund")
	if not GameState.flag("vashrak_dead", false):
		if not _active.has("vashrak"):
			var v := Settlements._npc(w, "vashrak", c + Vector3(0, 0, 22), true)
			v.boss_id = "vashrak"
			v.quest_tag = "vashrak"
			_active["vashrak"] = v
			v.combatant.died.connect(func(_k): GameState.set_flag("vashrak_dead", true))
			for k in 4:
				Settlements._npc(w, "rissbrut", c + Vector3(cos(k * 1.5) * 14.0, 0, 26 + sin(k * 1.5) * 6.0), true)
			EventBus.notify.emit("Vashrak: „Der Gehörnte schickt mir ein Opfer!“", "danger")
		return
	if not GameState.flag("gorrath_dead", false):
		if not _active.has("gorrath"):
			_active["gorrath"] = true
			var bd := DB.get_entry("bosses", "gorrath")
			var g := w.spawn_wild("trex", int(bd.get("level", 30)), c + Vector3(0, 0, -10), {"corrupted": true})
			if g == null:
				return
			g.is_boss = true
			g.boss_id = "gorrath"
			g.quest_tag = "gorrath"
			g.combatant.max_hp *= float(bd.get("hp_mult", 3.0))
			g.combatant.hp = g.combatant.max_hp
			g.stats["atk"] = float(g.stats["atk"]) * float(bd.get("atk_mult", 1.3))
			g.rec["abilities"] = bd.get("abilities", ["heavy_bite", "roar"])
			g.rec["name"] = bd["name"]
			g.ai.aggro_r = 80.0
			g.ai.temper = "demonic"
			g.combatant.team = "demon"
			for p in bd.get("parts", []):
				RigLibrary.attach_part(g.visual.inst, p["id"], p["socket"], p["size"])
			g.visual.pheno["corruption"] = 1.0
			g.visual.pheno["glow"] = 1.0
			g.visual.apply_colors()
			g.scale = Vector3.ONE * float(bd.get("scale", 1.2))
			g.combatant.died.connect(func(_k):
				GameState.set_flag("gorrath_dead", true)
				w.drop_loot(g.global_position, [["demon_heart", 1], ["trex_tooth", 3], ["ancient_tablet", 2], ["amber_coin", 120]])
				EventBus.notify.emit("Gorrath fällt. Am Herz des Risses liegt ein Amulett – Ewalds Amulett.", "quest"))
			g.play_action("roar", 2.0)
			EventBus.notify.emit("Aus dem Riss steigt Gorrath, der Verderbte!", "danger")
		return
	if not _active.has("heart"):
		_active["heart"] = true
		var it := Interactable.make(w, c + Vector3(0, 2.0, 0), "E: Das Herz des Risses – entscheide", func(p): _rift_choice(w), 6.0)


static func _rift_choice(w: World) -> void:
	var ui := w.get_tree().get_first_node_in_group("ui")
	var opts := [
		{"text": "Den Riss versiegeln (Beschützer) – Ilsas Ritual, Ewalds Geist findet Ruhe.", "cb": func(): _end_act1(w, "protector")},
		{"text": "Mein Banner in den Riss rammen (Eroberer) – seine Macht dient meinem Reich.", "cb": func(): _end_act1(w, "conqueror")},
	]
	if GameState.player()["demon"].get("unlocked", false):
		opts.append({"text": "Das Herz verschlingen (Dämon) – Azh'Moraths Stimme wird zu meiner.", "cb": func(): _end_act1(w, "demon")})
	ui.show_choice("Das Herz des Risses", "Ewalds Amulett pulsiert im Takt des Risses. Sein Geist ist hier gefangen – ebenso die Macht, die er beschworen hat. Was tust du?", opts)


static func _end_act1(w: World, path: String) -> void:
	GameState.set_flag("rift_choice", true)
	GameState.set_flag("act1_path", path)
	GameState.add_path(path, 5)
	var rift: Node3D = w.get_meta("rift_node") if w.has_meta("rift_node") else null
	var text := ""
	match path:
		"protector":
			GameState.change_rep("morgengrau", 40, "Riss versiegelt")
			GameState.change_rep("moosfell", 30, "Riss versiegelt")
			GameState.state["world"]["rift_state"] = "sealed"
			if rift:
				rift.queue_free()
			text = "Ilsas Worte und deine Kraft schließen die Wunde. Ewalds Geist löst sich mit einem Lächeln auf. Grünkrone atmet auf – doch am Horizont glühen zwei weitere Risse: über dem Aschenkamm und auf der Narbe."
		"conqueror":
			GameState.change_rep("knochenbrecher", 30, "Stärke bewiesen")
			GameState.change_rep("eisenhand", 25, "Machtanspruch")
			GameState.change_rep("morgengrau", -15, "Gefährliche Macht")
			GameState.state["world"]["rift_state"] = "bound"
			GameState.state["territories"]["narbenschlund"] = {"owner": "player", "since": GameState.get_day(), "how": "gebunden"}
			text = "Dein Banner steckt im pulsierenden Fels. Der Riss beugt sich deinem Willen und speist dein Lager mit Dämonenessenz. Ewalds Geist bleibt gebunden – als Wächter deines neuen Reiches. Andere Mächte werden das nicht hinnehmen."
		"demon":
			var d: Dictionary = GameState.player()["demon"]
			d["level"] = int(d["level"]) + 2
			d["points"] = int(d["points"]) + 2
			GameState.change_rep("daemonengoblins", 60, "Erbe des Gehörnten")
			GameState.change_rep("morgengrau", -30, "Die Stimme gewählt")
			GameState.state["world"]["rift_state"] = "devoured"
			if rift:
				rift.queue_free()
			text = "Du greifst in das Herz und es fließt in dich. Ewalds Erinnerungen, Vashraks Hass, Azh'Moraths Hunger – alles wird ein Teil von dir. Die Rissbrut verneigt sich. Ob du ihr Herr bist oder ihr Werkzeug, wird sich zeigen."
	var ui := w.get_tree().get_first_node_in_group("ui")
	ui.show_text("Akt I abgeschlossen: Das Herz des Risses", text + "\n\nDie Kernquest von Grünkrone ist abgeschlossen. Neue Aufgaben warten auf den anderen Inseln (Akt II: Feuer über dem Meer).")
	w.quests.evaluate_all()
	GameState.state["endings"].append("act1_" + path)


static func _herald(w: World) -> void:
	if not Quests.is_active("q10_narbe") or Quests.stage("q10_narbe") != 1:
		return
	if _active.has("herald") or not _near(w, "narbe_zitadelle", 120.0):
		return
	var h := Settlements._npc(w, "herold", WorldData.poi_pos("narbe_zitadelle") + Vector3(0, 0, 25), true)
	h.boss_id = "herald"
	h.quest_tag = "herald"
	_active["herald"] = h
	h.combatant.died.connect(func(_k): _final_choice(w))
	EventBus.notify.emit("Der Herold Azh'Moraths erhebt sich!", "danger")


static func _final_choice(w: World) -> void:
	var p: Dictionary = GameState.state["path"]
	var ui := w.get_tree().get_first_node_in_group("ui")
	var opts := [
		{"text": "Den letzten Riss schließen – die Inseln den Lebenden.", "cb": func(): _final(w, "hueter")},
		{"text": "Die Inseln unter meinem Banner vereinen.", "cb": func(): _final(w, "kriegsherr")},
	]
	if GameState.player()["demon"].get("unlocked", false):
		opts.append({"text": "Azh'Moraths Thron besteigen.", "cb": func(): _final(w, "daemonenfuerst")})
		if int(p.get("conqueror", 0)) >= 5 and int(p.get("demon", 0)) >= 5:
			opts.append({"text": "Herrschen in zwei Gestalten – Mensch am Tag, Dämon in der Nacht.", "cb": func(): _final(w, "schattenregent")})
	ui.show_choice("Das Ende der Narbe", "Der Herold ist gefallen. Vor dir klafft der letzte Riss – und durch ihn blickt Azh'Morath selbst.", opts)


static func _final(w: World, ending: String) -> void:
	GameState.set_flag("final_choice", true)
	GameState.state["endings"].append(ending)
	var texts := {
		"hueter": "Ende: DER HÜTER. Die Risse schließen sich. Dinosaurier und Menschen, Goblins und Bestien teilen sich wieder ein ungebrochenes Archipel. Dein Name wird in Morgengrau an jedem Feuer erzählt.",
		"kriegsherr": "Ende: DER KRIEGSHERR. Mit Hybriden, Söldnern und gezähmten Riesen beherrschst du jede Insel. Frieden herrscht – weil niemand es wagt, dir zu widersprechen.",
		"daemonenfuerst": "Ende: DER DÄMONENFÜRST. Azh'Morath ist nicht besiegt. Er ist ersetzt. Die Risse gehorchen deiner Stimme, und das Archipel kniet in rotem Licht.",
		"schattenregent": "Ende: DER SCHATTENREGENT. Am Tag sprichst du Recht als Mensch, in der Nacht ziehen deine Dämonen über die Inseln. Niemand kennt beide Gesichter – außer dir.",
	}
	var ui := w.get_tree().get_first_node_in_group("ui")
	ui.show_text("Ende", texts.get(ending, "") + "\n\nDu kannst weiterspielen.")
	w.quests.evaluate_all()


# ------------------------------------------------------------------ demon path (secret)
static func shrine_prompt() -> String:
	var d: Dictionary = GameState.player()["demon"]
	if d.get("unlocked", false):
		return "E: Am Schrein meditieren (Dämonengestalt gestalten)"
	return "E: Den gehörnten Schrein berühren"


static func shrine_ritual(w: World, p: Node) -> void:
	var d: Dictionary = GameState.player()["demon"]
	var ui := w.get_tree().get_first_node_in_group("ui")
	if d.get("unlocked", false):
		ui.open_demon()
		return
	var pages := 0
	for i in [1, 2, 3]:
		if GameState.flag("read_journal_page_%d" % i, false):
			pages += 1
	var hour := GameState.get_hour()
	var midnight := hour >= 23.0 or hour < 1.5
	var heart := Inventory.count(GameState.player()["inventory"], "demon_heart") > 0
	if pages < 3:
		ui.show_text("Der gehörnte Schrein", "Der Stein ist warm wie Haut. Etwas lauscht. Doch dir fehlen die Worte – Ewald hat sie aufgeschrieben (%d/3 Seiten gelesen)." % pages)
		return
	if not heart:
		ui.show_text("Der gehörnte Schrein", "Die Worte liegen dir auf der Zunge, doch der Schrein verlangt „ein Herz, das schlägt, wo keines schlagen sollte“.")
		return
	if not midnight:
		ui.show_text("Der gehörnte Schrein", "Das Herz in deiner Tasche pocht im Takt des Steins. „Wenn der Mond über dem Moor steht …“ – es ist noch nicht die Stunde (Mitternacht).")
		return
	Inventory.remove(GameState.player()["inventory"], "demon_heart", 1)
	d["unlocked"] = true
	d["level"] = 1
	d["points"] = 2
	d["skills"] = {"d_claws": 1}
	GameState.add_path("demon", 3)
	p.combatant.take_hit({"amount": p.combatant.hp * 0.5, "true_damage": true, "unavoidable": true})
	Fx.burst(p.global_position + Vector3.UP, Color(1.0, 0.15, 0.05), w, 120, 0.4, 7.0, 1.5)
	Audio.play_at("roar_demon", p.global_position, 4.0)
	EventBus.demon_unlocked.emit()
	ui.show_text("Der Pakt des Gehörnten", "Du sprichst Ewalds Worte. Das Herz zerfällt zu Asche, und der Schrein öffnet dich. Schmerz – dann Klarheit.\n\nDu kannst nun jederzeit zwischen Mensch und Dämon wechseln (Taste N), ohne Kosten oder Abklingzeit. Am Schrein gestaltest du deine Dämonenformen. Achtung: Wer deine Verwandlung sieht, wird sich daran erinnern.")


static func _whispers(w: World) -> void:
	var d: Dictionary = GameState.player()["demon"]
	if d.get("unlocked", false):
		return
	if not w.sky.is_night():
		return
	var near_rift := _near(w, "riss_narbenschlund", 200.0)
	var near_shrine := _near(w, "schrein", 60.0)
	if not (near_rift or near_shrine):
		return
	if randf() > 0.01:
		return
	var lines := ["Eine Stimme flüstert: „Ewald hat es gewagt … wirst du es auch?“",
		"Ein Flüstern im Wind: „Drei Seiten. Ein Herz. Die Stunde des Mondes.“",
		"Du hörst dein eigenes Herz – und ein zweites, fremdes, das im Takt mitschlägt.",
		"Die Stimme: „Der Gehörnte im Moor wartet auf jeden, der stark genug ist.“"]
	EventBus.notify.emit(lines[randi() % lines.size()], "whisper")
	d["hints"]["whisper"] = true
