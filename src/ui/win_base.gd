class_name WinBase
extends UIWindow
## Camp management: capacity, residents (jobs, needs, loyalty, recruitment), expeditions.

var box: VBoxContainer
var exp_region := ""
var exp_res: Array = []
var exp_cr: Array = []
var exp_hours := 6.0


func _init() -> void:
	super._init("Lager & Siedlung", Vector2(1150, 720))
	window_id = "base"
	var sc := UIK.scroll(Vector2(1100, 620))
	content.add_child(sc[0])
	box = sc[1]


func refresh() -> void:
	if box == null:
		return
	UIK.clear(box)
	box.add_child(UIK.label("Kreaturen im Lager: %.1f / %.1f Platz · Gefolge %d/%d · Bewohner %d/%d · Verteidigung %d" % [GameState.base_used(), GameState.base_capacity(), GameState.state["party"].size(), GameState.party_limit(), Settlement.residents().size(), Settlement.capacity(), Settlement.defense_value()], 16, UIK.GOLD, true))
	box.add_child(UIK.label("Große Tiere belegen mehr Platz (klein 0,5 · mittel 1 · groß 2 · riesig 4). Gehege erhöhen die Kapazität. Lager-Kreaturen fressen aus Vorratskisten.", 13, UIK.DIM, true))
	box.add_child(UIK.button("Kreaturen verwalten", func(): ui.open_creatures()))
	box.add_child(UIK.sep())
	box.add_child(UIK.label("Bewohner", 20, UIK.GOLD))
	for r in Settlement.residents():
		var row := UIK.hbox(6)
		var sk := []
		for k in r["skills"]:
			sk.append("%s %d" % [Settlement.JOBS.get(k, k), r["skills"][k]])
		var l := UIK.label("%s (%s) – %s · Loyalität %d · Hunger %d%% · %s" % [r["name"], "Goblin" if r["race"] == "goblin" else "Mensch", "unterwegs" if r["status"] == "expedition" else Settlement.JOBS.get(r["job"], r["job"]), int(r["loyalty"]), int(r["hunger"]), ", ".join(sk)], 14, UIK.TEXT, true)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		for j in Settlement.JOBS:
			row.add_child(UIK.button(Settlement.JOBS[j].substr(0, 4), func():
				r["job"] = j
				refresh(), "Arbeit: " + Settlement.JOBS[j]))
		box.add_child(row)
	if Settlement.residents().is_empty():
		box.add_child(UIK.label("Noch keine Bewohner. Baue Wohnhütten und werbe in befreundeten Siedlungen an.", 14, UIK.DIM, true))
	var rec := UIK.hbox(6)
	for o in [["morgengrau", "Siedler aus Morgengrau anwerben (Ansehen ≥ 30, 40 ◆)"], ["moosfell", "Moosfell-Goblin anwerben (Ansehen ≥ 40, 30 ◆)"], ["knochenbrecher", "Knochenbrecher anwerben (Ansehen ≥ 30, 50 ◆)"]]:
		var need = {"morgengrau": 30, "moosfell": 40, "knochenbrecher": 30}[o[0]]
		var cost = {"morgengrau": 40, "moosfell": 30, "knochenbrecher": 50}[o[0]]
		var b := UIK.button(o[1], func():
			if GameState.amber() < cost:
				EventBus.notify.emit("Nicht genug Bernstein.", "warn")
				return
			var res := Settlement.recruit(o[0])
			if res["ok"]:
				GameState.add_amber(-cost)
				EventBus.notify.emit("%s schließt sich deinem Lager an." % res["resident"]["name"], "good")
			else:
				EventBus.notify.emit(res["why"], "warn")
			refresh())
		b.disabled = GameState.rep(o[0]) < need
		rec.add_child(b)
	box.add_child(rec)
	box.add_child(UIK.sep())
	box.add_child(UIK.label("Expeditionen", 20, UIK.GOLD))
	for e in GameState.state["settlement"]["expeditions"]:
		var left := float(e["return_at"]) - (GameState.get_day() * 24.0 + GameState.get_hour())
		box.add_child(UIK.label("Unterwegs nach %s – Rückkehr in %.1f Std. (Stärke %d vs. Gefahr %d)" % [e["name"], left, e["power"], e["danger"]], 14))
	var rf := HFlowContainer.new()
	rf.add_child(UIK.label("Ziel:", 14))
	for r2 in WorldData.info["regions"]:
		if r2.get("water", false) or not Settlement._region_known(r2):
			continue
		rf.add_child(UIK.button(("● " if exp_region == r2["id"] else "") + r2["name"], func():
			exp_region = r2["id"]
			refresh()))
	box.add_child(rf)
	var pf := HFlowContainer.new()
	pf.add_child(UIK.label("Teilnehmer:", 14))
	for r3 in Settlement.residents():
		if r3["status"] != "home":
			continue
		var on: bool = int(r3["id"]) in exp_res
		pf.add_child(UIK.button(("✔ " if on else "") + r3["name"], func():
			if on:
				exp_res.erase(int(r3["id"]))
			else:
				exp_res.append(int(r3["id"]))
			refresh()))
	for c in GameState.all_creatures():
		if c["status"] != "base":
			continue
		var on2: bool = int(c["uid"]) in exp_cr
		pf.add_child(UIK.button(("✔ " if on2 else "") + "%s (St.%d)" % [c["name"], c["level"]], func():
			if on2:
				exp_cr.erase(int(c["uid"]))
			else:
				exp_cr.append(int(c["uid"]))
			refresh()))
	box.add_child(pf)
	var hb := UIK.hbox(6)
	for h in [3.0, 6.0, 12.0]:
		hb.add_child(UIK.button(("● " if exp_hours == h else "") + "%d Std." % h, func():
			exp_hours = h
			refresh()))
	hb.add_child(UIK.button("Expedition starten", func():
		var res := Settlement.start_expedition(exp_region, exp_res, exp_cr, exp_hours)
		if res["ok"]:
			EventBus.notify.emit("Expedition aufgebrochen.", "good")
			exp_res = []
			exp_cr = []
		else:
			EventBus.notify.emit(res["why"], "warn")
		refresh()))
	box.add_child(hb)
	box.add_child(UIK.label("Expeditionen bringen Material der Region. Zu schwache Gruppen kehren verletzt zurück. Basisangriffe gibt es nur durch Quests oder provozierte Feinde (z. B. Rückeroberungen).", 13, UIK.DIM, true))
