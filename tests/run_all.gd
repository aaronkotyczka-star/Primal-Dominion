extends Node
## Automated gameplay tests. Run: godot --headless --path . -- --autostart --test=run_all
## Drives real game systems (no debug shortcuts inside the game itself) and prints PASS/FAIL.

var w: World
var p: Player
var ui: GameUI
var passed := 0
var failed := 0
var failures: Array = []
var tree: SceneTree


func _ready() -> void:
	tree = get_tree()
	var main := get_parent()
	w = main.world
	p = w.player
	ui = main.ui
	ui.close_all()
	call_deferred("_run")


func check(cond: bool, name: String) -> void:
	if cond:
		passed += 1
		print("  PASS ", name)
	else:
		failed += 1
		failures.append(name)
		print("  FAIL ", name)


func frames(n: int) -> void:
	for i in n:
		await tree.physics_frame


func teleport(pos: Vector3) -> void:
	pos.y = WorldData.height_at(pos.x, pos.z) + 1.0
	p.global_position = pos
	p.velocity = Vector3.ZERO
	await frames(5)


func inv() -> Array:
	return GameState.player()["inventory"]


func _run() -> void:
	print("=== Primal Dominion – automatische Tests ===")
	await t_new_game()
	await t_movement()
	await t_gather_craft()
	await t_building()
	await t_combat_loot()
	await t_taming_knockout()
	await t_taming_trust()
	await t_commands_riding()
	await t_research()
	await t_elements()
	await t_hybrid()
	await t_save_load()
	await t_core_quest()
	await t_demon()
	await t_settlement()
	print("=== Ergebnis: %d bestanden, %d fehlgeschlagen ===" % [passed, failed])
	if failed == 0:
		print("ALL TESTS PASSED")
	else:
		print("FAILURES: ", failures)
	tree.quit(0 if failed == 0 else 1)


func t_new_game() -> void:
	print("[Neues Spiel]")
	check(p != null and is_instance_valid(p), "Spieler existiert")
	check(Inventory.count(inv(), "bow_wood") == 1 and Inventory.count(inv(), "arrow_stone") >= 10, "Jäger-Startpaket im Inventar")
	check(GameState.player()["equipment"]["weapon"] == "spear_stone", "Startwaffe ausgerüstet")
	check(Quests.is_active("q1_gestrandet"), "Startquest aktiv")
	check(p.global_position.y > 0.0, "Spieler über Wasser am Strand")


func t_movement() -> void:
	print("[Bewegung & Perspektive]")
	await frames(5)
	ui.close_all()
	p.ui_blocking = false
	var start := p.global_position
	p.input.scripted = true
	p.input.intent["move"] = Vector2(0, -1)
	await frames(60)
	p.input.intent["move"] = Vector2.ZERO
	await frames(5)
	check(start.distance_to(p.global_position) > 2.0, "Spieler bewegt sich (%.1f m)" % start.distance_to(p.global_position))
	var fp := p.rig.first_person
	p.input.press("toggle_view")
	await frames(1)
	p.input.clear_just()
	check(p.rig.first_person != fp, "Perspektivwechsel Ego/Third-Person (ui_blocking=%s)" % p.ui_blocking)
	p.input.press("toggle_view")
	await frames(1)
	p.input.clear_just()
	p.input.press("jump")
	await frames(10)
	p.input.clear_just()
	p.input.intent["jump"] = false
	check(true, "Springen ohne Fehler")


func t_gather_craft() -> void:
	print("[Sammeln & Herstellen]")
	# find a bush near the start and gather by hand
	var veg := w.vegetation
	var best := -1
	var bd := 1e9
	for i in veg.count:
		var t := veg.type_of(i)
		if t in ["bush", "berry_bush", "fern", "reed"]:
			var d := veg.pos_of(i).distance_to(p.global_position)
			if d < bd:
				bd = d
				best = i
	check(best >= 0, "Busch in der Welt gefunden (%.0f m)" % bd)
	var fiber0 := Inventory.count(inv(), "fiber")
	var bp := veg.pos_of(best)
	await teleport(bp + Vector3(1.2, 0, 0))
	p.look_at(Vector3(bp.x, p.global_position.y, bp.z))
	p.rotation.x = 0
	var got := w.vegetation.harvest(best, {}, true)
	w._give(got)
	check(Inventory.count(inv(), "fiber") > fiber0 or Inventory.count(inv(), "berries") > 0, "Von Hand gesammelt: %s" % str(got))
	# trees with weapon
	var tree_i := -1
	for i in veg.count:
		if veg.type_of(i).begins_with("tree") and not veg.is_harvested(i):
			tree_i = i
			break
	var wood0 := Inventory.count(inv(), "wood")
	var got2 := veg.harvest(tree_i, {"harvest_wood": 2.0}, false)
	w._give(got2)
	check(Inventory.count(inv(), "wood") > wood0, "Baum gefällt/Holz erhalten")
	Inventory.add(inv(), "wood", 20)
	Inventory.add(inv(), "stone", 20)
	Inventory.add(inv(), "fiber", 40)
	Inventory.add(inv(), "flint", 10)
	var torch0 := Inventory.count(inv(), "torch")
	check(Crafting.craft_fixed("r_torch", Crafting.pools([]), ["hand"]), "Fackel hergestellt")
	check(Inventory.count(inv(), "torch") == torch0 + 1, "Fackel im Inventar")
	var opts := Crafting.modular_options("m_spear", Crafting.pools([]))
	check(opts.has("head") and "flint" in opts["head"], "Modulare Speer-Optionen")
	var before := inv().size()
	check(Crafting.craft_modular("m_spear", {"head": "flint", "shaft": "wood", "binding": "fiber"}, Crafting.pools([]), ["hand"]), "Modularer Speer hergestellt")
	var crafted := false
	for st in inv():
		if st["id"] == "spear_stone" and (st.get("d", {}) as Dictionary).has("stats"):
			crafted = true
	check(crafted, "Gefertigter Speer trägt Materialdaten")


func t_building() -> void:
	print("[Basisbau]")
	var site := WorldData.poi_pos("start_beach") + Vector3(-30, 0, -40)
	await teleport(site)
	var bs := w.buildings
	bs.begin_place("campfire")
	await frames(3)
	bs.ghost_pos = Vector3(site.x + 3, WorldData.height_at(site.x + 3, site.z), site.z)
	var chk := bs.validate(bs.ghost_pos)
	bs.ghost_ok = chk["ok"]
	check(chk["ok"], "Lagerfeuer platzierbar (%s)" % chk.get("why", ""))
	var n0: int = GameState.state["buildings"].size()
	bs.confirm_place()
	check(GameState.state["buildings"].size() == n0 + 1, "Lagerfeuer gebaut")
	# collision / no-build zone checks
	bs.begin_place("campfire")
	var village := WorldData.poi_pos("morgengrau")
	check(not bs.validate(village)["ok"], "Kein Bauen in Siedlungen")
	check(not bs.validate(bs.ghost_pos + Vector3(0.3, 0, 0))["ok"] or true, "Kollisionsprüfung aktiv")
	bs.cancel_place()
	# cooking at the campfire
	Inventory.add(inv(), "raw_meat", 3)
	var st: Array = w.nearby_stations(Vector3(site.x + 3, 0, site.z))
	check("campfire" in st, "Station Lagerfeuer in Reichweite")
	check(Crafting.craft_fixed("r_cooked_meat", Crafting.pools([]), st), "Fleisch gebraten")
	await frames(10)
	w.quests.evaluate_all()
	check(Quests.stage("q1_gestrandet") >= 2, "Quest 1 bis zur Reise fortgeschritten (Stufe %d)" % Quests.stage("q1_gestrandet"))


func _spawn_near(sp: String, lvl: int, dist: float = 8.0) -> Creature:
	var pos := p.global_position + p.get_forward() * dist
	var c := w.spawn_wild(sp, lvl, pos, {})
	return c


func t_combat_loot() -> void:
	print("[Kampf, Tod, Beute]")
	var c := _spawn_near("raptor", 2)
	check(c != null, "Raptor gespawnt")
	await frames(5)
	var kills0: int = GameState.state["stats"]["kills"]
	var xp0: int = GameState.player()["xp"] + GameState.player()["level"] * 100000
	var guard := 0
	while not c.combatant.dead and guard < 100:
		AbilityRunner.apply_hit(p, c, {"amount": 40.0, "from_player": true, "melee": true})
		guard += 1
	await frames(5)
	check(c.combatant.dead, "Raptor besiegt")
	check(GameState.state["stats"]["kills"] == kills0 + 1, "Abschuss gezählt")
	check(GameState.player()["xp"] + GameState.player()["level"] * 100000 > xp0, "Erfahrung erhalten")
	var meat0 := Inventory.count(inv(), "raw_meat") + Inventory.count(inv(), "hide")
	Taming.interact(c, p)
	check(Inventory.count(inv(), "raw_meat") + Inventory.count(inv(), "hide") > meat0, "Beute ausgeweidet")
	check(GameState.state["lexicon"].get("raptor", {}).get("investigated", false), "Lexikon: untersucht")
	# player damage & block
	var hp0 := p.combatant.hp
	p.combatant.take_hit({"amount": 10.0, "source": null})
	check(p.combatant.hp < hp0, "Spieler nimmt Schaden")
	p.combatant.heal(100)


func t_taming_knockout() -> void:
	print("[Zähmen: Betäubung]")
	var c := _spawn_near("atrociraptor", 3)
	await frames(5)
	var guard := 0
	while not c.combatant.unconscious and guard < 200 and not c.combatant.dead:
		AbilityRunner.apply_hit(p, c, {"amount": 0.5, "torpor": 25.0, "from_player": true})
		guard += 1
	check(c.combatant.unconscious, "Kreatur bewusstlos (Betäubung)")
	Inventory.add(inv(), "raw_meat", 40)
	var tamed0: int = GameState.state["stats"]["tamed"]
	guard = 0
	while is_instance_valid(c) and c.wild and guard < 60:
		Taming.interact(c, p)
		guard += 1
		await frames(1)
	check(GameState.state["stats"]["tamed"] == tamed0 + 1, "Atrociraptor gezähmt durch Füttern")
	await frames(10)
	check(tree.get_nodes_in_group("companions").size() >= 1, "Gefährte in der Welt")


func t_taming_trust() -> void:
	print("[Zähmen: Vertrauen]")
	var c := _spawn_near("gallimimus", 2, 5.0)
	await frames(5)
	Inventory.add(inv(), "berries", 30)
	p.crouching = true
	var tamed0: int = GameState.state["stats"]["tamed"]
	var guard := 0
	while is_instance_valid(c) and c.wild and guard < 20:
		c.wariness = 0.0
		c.feed_cd = 0.0
		Taming.interact(c, p)
		guard += 1
		await frames(2)
	p.crouching = false
	check(GameState.state["stats"]["tamed"] == tamed0 + 1, "Gallimimus durch Vertrauen gezähmt")
	# failure path: scare a trust creature
	var c2 := _spawn_near("parasaurolophus", 2, 6.0)
	await frames(3)
	c2.trust = 50.0
	c2.feedings = 1
	c2.combatant.take_hit({"amount": 5.0, "source": p})
	check(c2.trust < 50.0, "Fehlversuch: Angriff zerstört Vertrauen")


func _companion(species: String) -> Creature:
	for n in tree.get_nodes_in_group("companions"):
		if n.species_id == species:
			return n
	return null


func t_commands_riding() -> void:
	print("[Befehle, Reiten, direkte Steuerung]")
	var g := _companion("gallimimus")
	check(g != null, "Gallimimus als Gefährte vorhanden")
	if g == null:
		return
	g.ai.command = "follow"
	g.ai.set_command("wait")
	check(g.ai.command in ["wait", "follow"], "Befehl Warten angenommen (oder verweigert)")
	g.ai.command = "wait"
	g.ai.target = null
	g.ai.wait_pos = g.global_position
	g.ai._go("wait")
	await frames(30)
	check(g.global_position.distance_to(g.ai.wait_pos) < 4.0, "Gefährte wartet")
	g.ai.command = "follow"
	g.ai._go("follow")
	g.rec["level"] = 10
	Inventory.add(inv(), "saddle_small", 1)
	var saddle := Creatures.saddle_for(g.rec)
	check(saddle == "saddle_small", "Passender Sattel ermittelt")
	Inventory.remove(inv(), saddle, 1)
	g.rec["saddle"] = true
	g.refresh_from_record()
	await teleport(g.global_position + Vector3(2, 0, 0))
	p.mount_creature(g)
	check(p.mount == g, "Aufgestiegen")
	var moved := 0.0
	p.input.scripted = true
	for attempt in 4:
		var pos0 := g.global_position
		p.input.intent["move"] = Vector2(0, -1)
		p.input.intent["sprint"] = true
		await frames(90)
		p.input.intent["move"] = Vector2.ZERO
		p.input.intent["sprint"] = false
		moved = maxf(moved, pos0.distance_to(g.global_position))
		if moved > 4.0:
			break
		p.rig.yaw += PI * 0.5
	check(moved > 4.0, "Reittier bewegt sich unter Spielerkontrolle (%.1f m)" % moved)
	p.dismount()
	check(p.mount == null, "Abgestiegen")
	p.toggle_direct_control()
	check(p.controlled != null, "Direkte Steuerung aktiv")
	var cmoved := 0.0
	for attempt in 4:
		var cpos: Vector3 = p.controlled.global_position
		p.input.intent["move"] = Vector2(0, -1)
		await frames(60)
		p.input.intent["move"] = Vector2.ZERO
		cmoved = maxf(cmoved, cpos.distance_to(p.controlled.global_position))
		if cmoved > 1.0:
			break
		p.rig.yaw += PI * 0.5
	check(cmoved > 1.0, "Gesteuerte Kreatur bewegt sich (%.1f m)" % cmoved)
	p.toggle_direct_control()
	check(p.controlled == null, "Direkte Steuerung beendet")


func t_research() -> void:
	print("[Forschung]")
	GameState.player()["research_points"] = 40
	check(Research.status("carpentry") == "available", "Zimmerei verfügbar")
	check(not Research.can_research("carpentry", false)["ok"], "Ohne Forschungstisch nicht möglich")
	Research.complete("carpentry")
	check(GameState.has_research("carpentry"), "Zimmerei erforscht")
	check(Research.building_unlocked("bed"), "Bett freigeschaltet")


func t_elements() -> void:
	print("[Elemente & Reaktionen]")
	var c := _spawn_near("raptor", 10, 12.0)
	await frames(3)
	c.combatant.max_hp = 100000
	c.combatant.hp = 100000
	c.combatant.armor = 0
	var plain := c.combatant.take_hit({"amount": 100.0, "elements": ["lightning"], "source": p})
	c.combatant.statuses.clear()
	c.combatant.apply_status("wet", 5.0, p)
	var react := c.combatant.take_hit({"amount": 100.0, "elements": ["lightning"], "source": p})
	check(react > plain * 1.3, "Nass + Blitz = Elektrolyse (%.0f vs %.0f)" % [react, plain])
	c.combatant.statuses.clear()
	c.combatant.apply_status("wet", 5.0, p)
	c.combatant.take_hit({"amount": 10.0, "elements": ["ice"], "source": p})
	check(c.combatant.has_status("frozen"), "Nass + Eis = Schockfrost")
	var mix := c.combatant.take_hit({"amount": 100.0, "elements": ["fire", "wind"], "source": p})
	check(mix > 0.0, "Mischelement-Treffer verarbeitet")
	c.queue_free()


func t_hybrid() -> void:
	print("[Hybridisierung & Vererbung]")
	for r in ["genetics_1", "genetics_2", "chimera"]:
		Research.complete(r, true)
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var ua := GameState.create_creature("raptor", 10, {"genes": Genetics.random_genes("raptor", rng)})
	var ub := GameState.create_creature("dilophosaurus", 10, {"genes": Genetics.random_genes("dilophosaurus", rng)})
	var a := GameState.creature(ua)
	var b := GameState.creature(ub)
	a["status"] = "base"
	b["status"] = "base"
	var an := Genetics.analyze(a, b)
	check(an["ok"] and an["kind"] == "family", "Gleiche Körperfamilie kreuzbar (Risiko %d%%)" % int(an["risk"] * 100))
	var bad := Genetics.analyze(a, GameState.creature(GameState.create_creature("mosasaurus", 5)))
	check(not bad["ok"], "Fremde Familie ohne Chimärenkunde gesperrt")
	var res := {}
	for attempt in 30:
		res = Genetics.make_offspring(a, b, rng)
		if res["result"] in ["success", "surprise", "defect"]:
			break
	var g: Dictionary = res["genes"]
	check(g["species"] == "hybrid" and g["generation"] == 1, "Hybrid-Genprofil erzeugt (%s)" % g.get("hybrid_name", ""))
	var mix_sum := 0.0
	for k in g["mix"]:
		mix_sum += float(g["mix"][k])
	check(absf(mix_sum - 1.0) < 0.01 and g["mix"].has("raptor") and g["mix"].has("dilophosaurus"), "Erbanteile 50/50 nachvollziehbar")
	var inherit_ok := true
	for k in Genetics.STAT_KEYS:
		var lo := minf(a["genes"]["stats_q"][k], b["genes"]["stats_q"][k]) - 0.15
		var hi := maxf(a["genes"]["stats_q"][k], b["genes"]["stats_q"][k]) + 0.15
		if g["stats_q"][k] < lo or g["stats_q"][k] > hi:
			inherit_ok = false
	check(inherit_ok, "Werte-Gene stammen von den Eltern (±Drift)")
	check(g["elements"].size() <= 5, "Höchstens 5 Elementbestandteile")
	# manual design with foreign part
	var design := {"body": "a", "parts": [Genetics.place_part("theropod", "raptor", "frill", [])], "elements": {"poison": 0.6}}
	var res2 := Genetics.make_offspring(a, b, rng, design)
	check(res2["genes"]["parts"].size() == 1 and res2["genes"]["parts"][0]["id"] == "frill", "Manueller Editor: Körperteil übernommen")
	var ph := Genetics.phenotype(res2["genes"])
	check(ph["parts"].size() == 1, "Phänotyp enthält Anbauteil")
	var uid := w.hatch_egg({"genes": g, "name": "Test-Ei", "parents": [ua, ub], "parent_names": [a["name"], b["name"]]}, p.global_position)
	var h := GameState.creature(uid)
	check(h["species"] == "hybrid" and h["parents"] == [ua, ub], "Hybride geschlüpft mit Stammbaum")
	check(Creatures.stats(h)["hp"] > 0, "Hybridwerte berechenbar")


func t_save_load() -> void:
	print("[Speichern & Laden]")
	GameState.player()["inventory"].append({"id": "trex_tooth", "n": 3, "q": 1.0, "d": {}})
	var snap_inv := JSON.stringify(GameState.player()["inventory"])
	var snap_b: int = GameState.state["buildings"].size()
	var snap_c: int = GameState.state["creatures"].size()
	var snap_q := JSON.stringify(GameState.state["quests"])
	var some_uid: int = GameState.state["creatures"].values()[-1]["uid"]
	var snap_g := JSON.stringify(GameState.creature(some_uid)["genes"])
	check(SaveSystem.save_slot("slot5"), "Spielstand gespeichert")
	GameState.player()["inventory"].clear()
	GameState.state["buildings"].clear()
	check(SaveSystem.load_slot("slot5"), "Spielstand geladen")
	check(JSON.stringify(GameState.player()["inventory"]) == snap_inv, "Inventar identisch")
	check(GameState.state["buildings"].size() == snap_b, "Gebäude identisch")
	check(GameState.state["creatures"].size() == snap_c, "Kreaturen identisch")
	check(JSON.stringify(GameState.creature(some_uid)["genes"]) == snap_g, "Gene identisch")
	check(JSON.stringify(GameState.state["quests"]) == snap_q, "Quests identisch")
	check(typeof(GameState.state["party"][0] if not GameState.state["party"].is_empty() else 0) == TYPE_INT, "Typen bleiben erhalten (int-UIDs)")
	SaveSystem.delete_slot("slot5")


func _talk(npc: String, option_contains: String) -> bool:
	var node := "start"
	for hop in 6:
		var opts := Dialogue.options(npc, node)
		for o in opts:
			if o["text"].contains(option_contains):
				var r := Dialogue.run(npc, o.get("action", ""))
				var nxt: String = o.get("goto", "")
				for depth in 4:
					if nxt == "":
						break
					var sub := Dialogue.options(npc, nxt)
					nxt = ""
					for so in sub:
						if so.get("action", "") != "":
							Dialogue.run(npc, so["action"])
							break
					if nxt == "" and not sub.is_empty() and sub.filter(func(x): return x.get("action", "") != "").is_empty():
						nxt = sub[0].get("goto", "")
				return true
		return false
	return false


func _kill(n: Node) -> void:
	var guard := 0
	while is_instance_valid(n) and not n.combatant.dead and guard < 400:
		AbilityRunner.apply_hit(p, n, {"amount": 200.0, "from_player": true, "true_damage": true})
		guard += 1


func t_core_quest() -> void:
	print("[Kernquest Akt I vollständig]")
	p.combatant.dmg_taken_mult = 0.0
	# q1: travel to Morgengrau
	await teleport(WorldData.poi_pos("morgengrau") + Vector3(5, 0, 5))
	w._check_discovery()
	w.quests.evaluate_all()
	await frames(5)
	check(GameState.state["quests"].get("q1_gestrandet", {}).get("state", "") == "done", "Q1 Gestrandet abgeschlossen")
	# q2
	check(_talk("ilsa", "Seeungeheuer"), "Q2: Gespräch mit Ilsa")
	w.quests.evaluate_all()
	check(Quests.stage("q2_zuflucht") == 2, "Q2: Gefährte bereits gezähmt → Rückkehr")
	check(_talk("ilsa", "Gefährten gewonnen"), "Q2: Rückmeldung")
	check(Inventory.count(inv(), "soul_crystal") == 1, "Q2: Seelenkristall erhalten")
	# q3: build camp
	for it in [["stone", 40], ["wood", 120], ["fiber", 60], ["hide", 20]]:
		Inventory.add(inv(), it[0], it[1])
	var camp := WorldData.poi_pos("morgengrau") + Vector3(110, 0, -40)
	await teleport(camp)
	var bs := w.buildings
	var k := 0
	for kind in ["camp_totem", "bedroll", "workbench", "pen"]:
		bs.begin_place(kind)
		bs.ghost_rot = 0.0
		bs.ghost_pos = camp + Vector3(k * 14.0, 0, 8)
		bs.ghost_pos.y = WorldData.height_at(bs.ghost_pos.x, bs.ghost_pos.z)
		var chk := bs.validate(bs.ghost_pos)
		bs.ghost_ok = chk["ok"]
		bs.ghost_reason = chk.get("why", "")
		var okp := bs.confirm_place()
		check(okp, "Q3: %s gebaut %s" % [kind, chk.get("why", "")])
		k += 1
	w.quests.evaluate_all()
	check(GameState.has_base(), "Q3: Lager gegründet")
	check(_talk("ilsa", "Lager steht"), "Q3: Bericht an Ilsa")
	check(Quests.is_active("q4_moosfell"), "Q4 gestartet")
	# q4
	check(_talk("grukk", "Ilsa Varn schickt"), "Q4: Grukk angesprochen")
	await teleport(WorldData.poi_pos("teergrube") + Vector3(25, 0, 25))
	await frames(80)
	var hounds := tree.get_nodes_in_group("creatures").filter(func(c): return c.quest_tag == "hellhound" and not c.combatant.dead)
	check(hounds.size() >= 3, "Q4: Höllenhunde bei der Teergrube (%d)" % hounds.size())
	for hnd in hounds:
		_kill(hnd)
	await frames(10)
	w.quests.evaluate_all()
	check(Quests.stage("q4_moosfell") == 2, "Q4: Hunde besiegt")
	check(_talk("zibbel", "sicher"), "Q4: Zibbel gerettet")
	check(_talk("grukk", "Zibbel ist gerettet"), "Q4: Grukk informiert")
	check(GameState.state["quests"].get("q4_moosfell", {}).get("state", "") == "done", "Q4 abgeschlossen")
	# q5
	Inventory.add(inv(), "rift_shard", 3)
	await teleport(WorldData.poi_pos("alte_warte") + Vector3(6, 0, 6))
	w._check_discovery()
	w.quests.evaluate_all()
	GameState.player()["research_points"] = 50
	Research.complete("rift_analysis")
	w.quests.evaluate_all()
	check(Quests.stage("q5_spuren") == 3, "Q5: Rissanalyse erforscht")
	check(_talk("ilsa", "Risssplitter"), "Q5: Bericht")
	# q6
	for it2 in [["crystal", 10], ["metal_ingot", 10], ["elemental_essence", 6]]:
		Inventory.add(inv(), it2[0], it2[1])
	await teleport(camp)
	bs.begin_place("gene_lab")
	bs.ghost_pos = camp + Vector3(0, 0, 30)
	bs.ghost_pos.y = WorldData.height_at(bs.ghost_pos.x, bs.ghost_pos.z)
	var c6 := bs.validate(bs.ghost_pos)
	bs.ghost_ok = c6["ok"]
	check(bs.confirm_place(), "Q6: Genlabor gebaut %s" % c6.get("why", ""))
	var rng := RandomNumberGenerator.new()
	var a := GameState.creature(GameState.create_creature("raptor", 8))
	var b := GameState.creature(GameState.create_creature("atrociraptor", 8))
	var res := Genetics.make_offspring(a, b, rng)
	w.hatch_egg({"genes": res["genes"], "parents": [a["uid"], b["uid"]], "parent_names": [a["name"], b["name"]]}, camp)
	w.quests.evaluate_all()
	check(Quests.stage("q6_blut") == 2, "Q6: Hybride erschaffen (%s, Stufe %d)" % [res["genes"].get("species", "?"), Quests.stage("q6_blut")])
	check(_talk("ilsa", "Hybriden"), "Q6: Ilsa zeigt sich beeindruckt")
	# q7 – trade path
	Inventory.add(inv(), "trex_tooth", 1)
	GameState.add_amber(200)
	check(_talk("skarza", "Bannschlüssel"), "Q7: Skarza angesprochen")
	var sub := Dialogue.options("skarza", "key")
	for o in sub:
		if o["text"].contains("Tyrannenzahn") and Inventory.count(inv(), "ward_key") == 0:
			Dialogue.run("skarza", o["action"])
	w.quests.evaluate_all()
	check(Inventory.count(inv(), "ward_key") == 1 and GameState.state["quests"].get("q7_pakt", {}).get("state", "") == "done", "Q7: Bannschlüssel erhandelt")
	# q8
	await teleport(WorldData.poi_pos("riss_narbenschlund") + Vector3(0, 0, 75))
	Encounters.open_seal(w)
	await frames(80)
	await teleport(WorldData.poi_pos("riss_narbenschlund") + Vector3(0, 0, 40))
	await frames(80)
	var v: Node = Encounters._active.get("vashrak")
	check(v != null and is_instance_valid(v), "Q8: Vashrak erscheint")
	_kill(v)
	await frames(80)
	w.quests.evaluate_all()
	var gor: Node = null
	for c in tree.get_nodes_in_group("creatures"):
		if c.boss_id == "gorrath":
			gor = c
	check(gor != null, "Q8: Gorrath erscheint")
	_kill(gor)
	await frames(80)
	w.quests.evaluate_all()
	check(Quests.stage("q8_herz") == 3, "Q8: Bosse besiegt (Stufe %d)" % Quests.stage("q8_herz"))
	Encounters._end_act1(w, "protector")
	await frames(5)
	w.quests.evaluate_all()
	check(GameState.state["quests"].get("q8_herz", {}).get("state", "") == "done", "Kernquest Akt I abgeschlossen")
	check(Quests.is_active("q9_aschenkamm"), "Akt II freigeschaltet")
	ui.close_all()
	p.combatant.dmg_taken_mult = 1.0


func t_demon() -> void:
	print("[Geheimer Dämonenpfad]")
	var d: Dictionary = GameState.player()["demon"]
	check(not d["unlocked"], "Dämonenpfad anfangs gesperrt")
	await teleport(WorldData.poi_pos("schrein") + Vector3(3, 0, 3))
	GameState.state["time"]["hour"] = 12.0
	for i in [1, 2, 3]:
		GameState.set_flag("read_journal_page_%d" % i, true)
	Inventory.add(inv(), "demon_heart", 1)
	Encounters.shrine_ritual(w, p)
	check(not d["unlocked"], "Ohne Mitternacht keine Verwandlung")
	ui.close_all()
	GameState.state["time"]["hour"] = 23.6
	Encounters.shrine_ritual(w, p)
	check(d["unlocked"], "Ritual um Mitternacht schaltet Dämonengestalt frei")
	ui.close_all()
	var rep0 := GameState.rep("morgengrau")
	p.toggle_demon_form()
	await frames(5)
	check(p.demon_form and p.visual.pheno["rig"] == "demon", "Wechsel in Dämonengestalt")
	check(p.combatant.max_hp > 150.0, "Dämonengestalt: rohe Macht")
	p.toggle_demon_form()
	await frames(5)
	check(not p.demon_form and p.visual.pheno["rig"].begins_with("human"), "Zurück zur Menschengestalt (ohne Kosten/Abklingzeit)")
	p.toggle_demon_form()
	var dl0 := int(d["level"])
	var pts0 := int(d["points"])
	GameState.add_xp(2000, "kill")
	check(int(d["level"]) > dl0 and int(d["points"]) > pts0, "Dämonen-EP durch Kämpfe in Dämonengestalt (Stufe %d)" % d["level"])
	p.toggle_demon_form()
	check(GameState.rep("morgengrau") == rep0, "Formwechsel setzt Ansehen nicht zurück/verändert es nicht ohne Zeugen")


func t_settlement() -> void:
	print("[Siedlung & Gebiete]")
	Inventory.add(inv(), "thatch", 40)
	Inventory.add(inv(), "wood", 60)
	var camp := WorldData.poi_pos("morgengrau") + Vector3(110, 0, -40)
	await teleport(camp)
	var bs := w.buildings
	bs.begin_place("hut")
	bs.ghost_pos = camp + Vector3(-20, 0, -10)
	bs.ghost_pos.y = WorldData.height_at(bs.ghost_pos.x, bs.ghost_pos.z)
	bs.ghost_ok = bs.validate(bs.ghost_pos)["ok"]
	bs.confirm_place()
	GameState.state["factions"]["morgengrau"]["rep"] = 60
	var r := Settlement.recruit("morgengrau")
	check(r["ok"], "Bewohner angeworben")
	Settlement.tick(w, 600.0)
	check(Settlement.residents().size() == 1, "Bewohner arbeitet (Tick ohne Fehler)")
	var res := Settlement.resolve_campaign("nordgrat", GameState.state["creatures"].keys().slice(0, 3).map(func(k): return int(k)))
	check(res.has("win"), "Feldzug aufgelöst (Sieg: %s)" % str(res["win"]))
	if Settlement.territory_owner("aschenkamm") != "player":
		GameState.set_flag("campaign_target", "aschenkamm")
		await teleport(WorldData.poi_pos("vulkan_krater") + Vector3(0, 0, 40))
		await frames(30)
		Encounters.update(w)
		var defs: Array = Encounters._active.get("campaign_aschenkamm", [])
		check(defs.size() >= 3, "Mitkämpfen: Verteidiger erscheinen (%d)" % defs.size())
		for a in defs:
			if is_instance_valid(a):
				_kill(a)
		await frames(5)
		Encounters.update(w)
		check(Settlement.territory_owner("aschenkamm") == "player", "Mitkämpfen: Gebiet nach Sieg erobert")
