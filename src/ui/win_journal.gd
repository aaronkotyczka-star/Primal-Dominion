class_name WinJournal
extends UIWindow
## Quest journal, factions & reputation, territories & tactical campaign.

var tab := "quests"
var box: VBoxContainer
var sel_q := ""
var campaign_tid := ""
var campaign_army: Array = []


func _init(start_tab: String = "quests") -> void:
	super._init("Journal", Vector2(1150, 720))
	window_id = "journal"
	tab = start_tab
	var tabs := UIK.hbox(6)
	content.add_child(tabs)
	for t in [["Quests", "quests"], ["Abgeschlossen", "done"], ["Fraktionen", "factions"], ["Gebiete & Feldzug", "territory"], ["Statistik", "stats"]]:
		tabs.add_child(UIK.button(t[0], func():
			tab = t[1]
			refresh()))
	var sc := UIK.scroll(Vector2(1100, 600))
	content.add_child(sc[0])
	box = sc[1]


func refresh() -> void:
	if box == null:
		return
	UIK.clear(box)
	match tab:
		"quests":
			for qid in Quests.tracked():
				var qd := DB.quest(qid)
				box.add_child(UIK.label(("◆ " if qd.get("main", false) else "◇ ") + qd["name"] + "  (Akt %d)" % qd.get("act", 1), 20, UIK.GOLD if qd.get("main", false) else UIK.TEXT))
				box.add_child(UIK.label(qd["desc"], 15, UIK.DIM, true))
				var sd := Quests.current_stage_def(qid)
				box.add_child(UIK.label("→ " + sd.get("text", ""), 15, UIK.TEXT, true))
				var objs: Array = sd.get("obj", [])
				for i in objs.size():
					box.add_child(UIK.label("     " + Quests.objective_text(qid, i, objs[i]), 14, UIK.TEXT))
				box.add_child(UIK.sep())
			if Quests.tracked().is_empty():
				box.add_child(UIK.label("Keine aktiven Quests.", 16, UIK.DIM))
		"done":
			for qid in GameState.state["quests"]:
				if GameState.state["quests"][qid]["state"] == "done":
					box.add_child(UIK.label("✔ " + DB.quest(qid).get("name", qid), 16, UIK.GREEN))
			for e in GameState.state["endings"]:
				box.add_child(UIK.label("Erreichtes Ende: " + str(e), 16, UIK.GOLD))
		"factions":
			for fid in DB.t("factions"):
				var f := DB.faction(fid)
				var r := GameState.rep(fid)
				box.add_child(UIK.label("%s – %s (%+d)" % [f["name"], Factions.rep_label(r), r], 19, UIK.GOLD))
				box.add_child(UIK.label(f["desc"], 14, UIK.DIM, true))
				var reaction: String = {"hostile": "feindselig", "flee": "fliehen voller Angst", "respect": "zeigen Respekt", "ally": "erkennen dich als einen der ihren"}.get(f.get("demon_reaction", ""), "")
				if GameState.player()["demon"].get("unlocked", false):
					box.add_child(UIK.label("Reaktion auf deine Dämonengestalt: " + reaction + (" (haben dich bereits gesehen)" if GameState.player()["demon"]["seen_by"].has(fid) else ""), 13, Color(1.0, 0.5, 0.4), true))
				var bar := UIK.bar(UIK.GREEN if r >= 0 else UIK.RED, 400, 8)
				bar.min_value = -100
				bar.max_value = 100
				bar.value = r
				box.add_child(bar)
			var pth: Dictionary = GameState.state["path"]
			box.add_child(UIK.sep())
			box.add_child(UIK.label("Dein Weg: Beschützer %d · Eroberer %d · Dämon %d" % [pth.get("protector", 0), pth.get("conqueror", 0), pth.get("demon", 0)], 16, UIK.TEXT))
		"territory":
			_territories()
		"stats":
			var s: Dictionary = GameState.state["stats"]
			box.add_child(UIK.label("Erlegt: %d · Gezähmt: %d · Hergestellt: %d · Hybriden: %d · Tode: %d" % [s["kills"], s["tamed"], s["crafted"], s["hybrids"], s["deaths"]], 16))
			box.add_child(UIK.label("Spielzeit: %d min · %s · Schwierigkeit: %s" % [int(GameState.state.get("playtime", 0) / 60), GameState.time_label(), GameState.state["difficulty"]], 16))


func _territories() -> void:
	box.add_child(UIK.label("Gebiete liefern täglich Ressourcen in dein Lager. Gewinne sie durch Bündnis, Handel oder Eroberung. Eroberte Gebiete können zurückerobert werden – Wachen schützen sie.", 14, UIK.DIM, true))
	for tid in Settlement.TERRITORIES:
		var t: Dictionary = Settlement.TERRITORIES[tid]
		var owner := Settlement.territory_owner(tid)
		var owner_name = "Du" if owner == "player" else (DB.faction(owner).get("name", "niemand") if owner != "" else "niemand (wild)")
		var row := UIK.hbox(8)
		var y := []
		for k in t["yield"]:
			if int(t["yield"][k]) > 0:
				y.append("%d %s" % [t["yield"][k], DB.item_name(k)])
		var l := UIK.label("%s – Besitzer: %s · Ertrag/Tag: %s" % [t["name"], owner_name, ", ".join(y)], 15, UIK.GREEN if owner == "player" else UIK.TEXT, true)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		if owner != "player":
			for opt in Settlement.claim_options(tid):
				var b := UIK.button(opt["how"], func():
					match opt["how"]:
						"Bündnis":
							Settlement.claim(tid, "Bündnis")
						"Handelsabkommen":
							GameState.add_amber(-300)
							Settlement.claim(tid, "Handel")
							if owner != "":
								GameState.change_rep(owner, 5)
						"Eroberung":
							campaign_tid = tid
							campaign_army = []
					refresh(), opt.get("why", ""))
				b.disabled = not opt["ok"]
				row.add_child(b)
		box.add_child(row)
	if campaign_tid != "":
		box.add_child(UIK.sep())
		box.add_child(UIK.label("Taktische Karte: Feldzug gegen %s" % Settlement.TERRITORIES[campaign_tid]["name"], 20, UIK.GOLD))
		box.add_child(UIK.label("Wähle Kreaturen aus Lager/Gefolge. Stärke deiner Armee: %d · Verteidiger: %d" % [Settlement.army_power(campaign_army) + Settlement.defense_value() * 0.5, Settlement.defender_power(campaign_tid)], 15, UIK.TEXT, true))
		var flow := HFlowContainer.new()
		for c in GameState.all_creatures():
			if c["status"] in ["base", "party"]:
				var on: bool = int(c["uid"]) in campaign_army
				flow.add_child(UIK.button(("✔ " if on else "") + "%s (St.%d)" % [c["name"], c["level"]], func():
					if on:
						campaign_army.erase(int(c["uid"]))
					elif campaign_army.size() < 8:
						campaign_army.append(int(c["uid"]))
					refresh()))
		box.add_child(flow)
		box.add_child(UIK.label("Gleichzeitig simulierte Truppen sind auf 8 Kreaturen begrenzt. Selbst mitkämpfen: Reise zum Gebiet und besiege die Wächter – oder lass die Schlacht automatisch auflösen.", 13, UIK.DIM, true))
		var hb := UIK.hbox(6)
		hb.add_child(UIK.button("Schlacht automatisch auflösen", func():
			if campaign_army.is_empty():
				return
			var res := Settlement.resolve_campaign(campaign_tid, campaign_army)
			ui.show_text("Feldzug", ("SIEG! " if res["win"] else "Niederlage. ") + "Kräfteverhältnis %.2f.\nVerluste: %s" % [res["ratio"], ", ".join(res["losses"]) if not res["losses"].is_empty() else "keine"])
			campaign_tid = ""
			refresh()))
		hb.add_child(UIK.button("Mitkämpfen (Wegmarke setzen)", func():
			GameState.set_flag("campaign_target", campaign_tid)
			EventBus.notify.emit("Ziehe zu %s. Besiege dort die Verteidiger, um das Gebiet zu erobern." % Settlement.TERRITORIES[campaign_tid]["name"], "quest")
			ui.close(self)))
		hb.add_child(UIK.button("Abbrechen", func():
			campaign_tid = ""
			refresh()))
		box.add_child(hb)
