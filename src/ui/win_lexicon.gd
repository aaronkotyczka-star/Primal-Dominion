class_name WinLexicon
extends UIWindow
## Creature lexicon: seen / investigated / tamed, habitat, taming method, food, abilities and lore.

var sel := ""
var left: VBoxContainer
var right: VBoxContainer
var search := ""


func _init() -> void:
	super._init("Kreaturenlexikon", Vector2(1100, 700))
	window_id = "lexicon"
	var le := LineEdit.new()
	le.placeholder_text = "Suchen …"
	le.custom_minimum_size = Vector2(240, 0)
	le.text_changed.connect(func(t):
		search = t.to_lower()
		refresh())
	content.add_child(le)
	var cols := UIK.hbox(12)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(cols)
	var sc := UIK.scroll(Vector2(320, 560))
	cols.add_child(sc[0])
	left = sc[1]
	var sc2 := UIK.scroll(Vector2(720, 560))
	cols.add_child(sc2[0])
	right = sc2[1]


func refresh() -> void:
	if left == null:
		return
	UIK.clear(left)
	UIK.clear(right)
	var lx: Dictionary = GameState.state["lexicon"]
	var n_seen := 0
	for sid in DB.t("species"):
		var e: Dictionary = lx.get(sid, {})
		if e.get("seen", false):
			n_seen += 1
	left.add_child(UIK.label("Entdeckt: %d / %d" % [n_seen, DB.t("species").size()], 15, UIK.GOLD))
	for sid in DB.t("species"):
		var sp := DB.species(sid)
		var e: Dictionary = lx.get(sid, {})
		var known: bool = e.get("seen", false)
		var nm: String = sp["name"] if known else "???"
		if search != "" and not nm.to_lower().contains(search):
			continue
		var marks := ("👁" if known else "") + (" ⚗" if e.get("investigated", false) else "") + (" ♥" if e.get("tamed", false) else "")
		var b := UIK.button("%s %s" % [nm, marks], func():
			sel = sid
			refresh())
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.disabled = not known
		left.add_child(b)
	if sel == "":
		right.add_child(UIK.label("👁 gesehen   ⚗ untersucht (Kadaver ausweiden)   ♥ gezähmt\nUntersuchen schaltet Details und teils Forschung frei.", 15, UIK.DIM, true))
		return
	var sp2 := DB.species(sel)
	var e2: Dictionary = lx.get(sel, {})
	var inv: bool = e2.get("investigated", false) or e2.get("tamed", false)
	right.add_child(UIK.label(sp2["name"], 26, UIK.GOLD))
	right.add_child(UIK.label(sp2.get("lore", ""), 15, UIK.TEXT, true))
	var fam: String = sp2.get("family", "")
	var size: String = {"small": "klein", "medium": "mittel", "large": "groß", "huge": "riesig"}.get(sp2.get("size", ""), "")
	right.add_child(UIK.label("Körperfamilie: %s · Größe: %s · Lebensraum: %s" % [fam, size, ", ".join(sp2.get("biomes", []))], 14, UIK.DIM, true))
	right.add_child(UIK.label("Verhalten: %s · Sozial: %s · Erlegt: %d" % [sp2.get("temper", ""), sp2.get("social", ""), e2.get("killed", 0)], 14, UIK.DIM))
	if inv:
		var tm: Dictionary = sp2.get("tame", {})
		var method: String = {"knockout": "Betäuben (Keule, Betäubungspfeile) und füttern", "trust": "Vertrauen: geduckt nähern, Futter anbieten", "rescue": "Rettung aus einer Notlage", "egg": "Ei stehlen und ausbrüten", "magic": "Bindungsrune bei <30% Leben (alternativ Ei)", "pact": "Pakt am Rissaltar (Paktsiegel)"}.get(tm.get("method", ""), "?")
		right.add_child(UIK.label("Zähmung: " + method, 16, UIK.TEXT, true))
		right.add_child(UIK.label("Bevorzugtes Futter: " + ", ".join(Array(sp2.get("food", [])).map(func(f): return DB.item_name(f))), 15, UIK.TEXT, true))
		right.add_child(UIK.label("Reitbar: %s%s" % ["ja" if sp2.get("rideable", false) else "nein", (" (%s)" % {"ground": "Land", "fly": "Flug", "swim": "Wasser", "amphibious": "amphibisch"}.get(sp2.get("mount", ""), "")) if sp2.get("rideable", false) else ""], 15))
		var st: Dictionary = sp2.get("stats", {})
		right.add_child(UIK.label("Basiswerte: Leben %d · Angriff %d · Verteidigung %d · Tempo %.1f" % [st.get("hp", 0), st.get("atk", 0), st.get("deff", 0), st.get("spd", 0)], 14, UIK.TEXT))
		right.add_child(UIK.label("Fähigkeiten: " + ", ".join(Array(sp2.get("abilities", [])).map(func(a): return DB.ability(a).get("name", a))), 14, UIK.TEXT, true))
		right.add_child(UIK.label("Beute: " + ", ".join(Array(sp2.get("loot", [])).map(func(l): return DB.item_name(l[0]))), 14, UIK.DIM, true))
	else:
		right.add_child(UIK.label("Untersuche einen Kadaver dieser Art (E), um mehr zu erfahren.", 15, UIK.DIM, true))
