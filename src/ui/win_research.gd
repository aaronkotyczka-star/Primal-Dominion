class_name WinResearch
extends UIWindow
## Research book: categories, requirements, sources, completion at a research table.

var at_table := false
var box: VBoxContainer
var search := ""


func _init(table: bool = false) -> void:
	super._init("Forschungsbuch", Vector2(1100, 720))
	window_id = "research"
	at_table = table
	var top := UIK.hbox(8)
	content.add_child(top)
	var le := LineEdit.new()
	le.placeholder_text = "Suchen …"
	le.custom_minimum_size = Vector2(220, 0)
	le.text_changed.connect(func(t):
		search = t.to_lower()
		refresh())
	top.add_child(le)
	var sc := UIK.scroll(Vector2(1060, 580))
	content.add_child(sc[0])
	box = sc[1]


func refresh() -> void:
	if box == null:
		return
	UIK.clear(box)
	var p := GameState.player()
	box.add_child(UIK.label("Forschungspunkte: %d   ·   %s" % [p["research_points"], "Am Forschungstisch – Forschung möglich." if at_table else "Nur Ansicht. Forschen am Forschungstisch (Lager oder Morgengrau)."], 16, UIK.GOLD if at_table else UIK.DIM, true))
	box.add_child(UIK.label("Punkte erhältst du durch Untersuchen von Kreaturen (Ausweiden), Entdecken von Orten und Ruinen, Quests, Herstellen von Hybriden und Notizen/Tafeln.", 13, UIK.DIM, true))
	var cats := {}
	for id in DB.t("research"):
		var r := DB.research(id)
		if search != "" and not (r["name"].to_lower().contains(search) or r["desc"].to_lower().contains(search)):
			continue
		var c: String = r.get("cat", "Sonstiges")
		if not cats.has(c):
			cats[c] = []
		cats[c].append(id)
	for c in cats:
		box.add_child(UIK.label(c, 20, UIK.GOLD))
		for id in cats[c]:
			var r := DB.research(id)
			var stt := Research.status(id)
			var row := UIK.hbox(8)
			var mark = {"done": "✔", "available": "◆", "locked": "✖"}[stt]
			var col: Color = {"done": UIK.GREEN, "available": UIK.TEXT, "locked": UIK.DIM}[stt]
			var l := UIK.label("%s %s (%d FP) – %s" % [mark, r["name"], r["cost"], r["desc"]], 15, col, true)
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(l)
			if stt == "locked":
				var why := []
				for req in r.get("req", []):
					if not GameState.has_research(req):
						why.append("benötigt " + DB.research(req).get("name", req))
				if not Research.source_met(id):
					why.append(Research.source_hint(id))
				row.add_child(UIK.label(", ".join(why), 13, Color(0.8, 0.6, 0.4)))
			elif stt == "available":
				var chk := Research.can_research(id, at_table)
				var b := UIK.button("Erforschen", func():
					Research.complete(id)
					refresh(), chk.get("why", ""))
				b.disabled = not chk["ok"]
				row.add_child(b)
			box.add_child(row)
