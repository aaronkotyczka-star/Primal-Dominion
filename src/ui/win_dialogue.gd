class_name WinDialogue
extends UIWindow
## NPC dialogue (data-driven) with trading view.

var npc_id := ""
var node_id := "start"
var trading := false
var box: VBoxContainer


func _init(id: String = "") -> void:
	super._init(DB.npc(id).get("name", id), Vector2(900, 560))
	window_id = "dialogue"
	npc_id = id
	var sc := UIK.scroll(Vector2(860, 480))
	content.add_child(sc[0])
	box = sc[1]


func refresh() -> void:
	if box == null:
		return
	UIK.clear(box)
	var def := DB.npc(npc_id)
	if trading:
		_trade(def)
		return
	var node := Dialogue.node(npc_id, node_id)
	if node.is_empty():
		node = Dialogue.node(npc_id, "start")
		node_id = "start"
	box.add_child(UIK.label(def.get("role", ""), 14, UIK.DIM))
	box.add_child(UIK.rich("[i]„%s“[/i]" % node.get("text", "…"), 18))
	box.add_child(UIK.sep())
	var opts := Dialogue.options(npc_id, node_id)
	for o in opts:
		var b := UIK.button("» " + o["text"], func(): _choose(o))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		box.add_child(b)
	if opts.is_empty():
		box.add_child(UIK.button("» Leb wohl.", func(): close_window()))


func _choose(o: Dictionary) -> void:
	var res := Dialogue.run(npc_id, o.get("action", ""))
	if res["trade"]:
		trading = true
		refresh()
		return
	if o.has("goto"):
		node_id = o["goto"]
	elif res["goto"] != "":
		node_id = res["goto"]
	if res["end"] and not o.has("goto"):
		close_window()
		return
	refresh()


func _trade(def: Dictionary) -> void:
	var fid: String = def.get("faction", "")
	box.add_child(UIK.label("Handel – du hast %d Bernstein" % GameState.amber(), 18, UIK.GOLD))
	var cols := UIK.hbox(20)
	box.add_child(cols)
	var buy := UIK.vbox(4)
	buy.custom_minimum_size = Vector2(400, 0)
	cols.add_child(buy)
	buy.add_child(UIK.label("Angebot", 16, UIK.GOLD))
	for id in def.get("trades", []):
		var price := Dialogue.price_buy(id, fid)
		var b := UIK.button("%s – %d ◆" % [DB.item_name(id), price], func():
			Dialogue.buy(npc_id, id)
			refresh(), UIK.item_tooltip({"id": id, "q": 1.0, "d": {}}))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		buy.add_child(b)
	var sell := UIK.vbox(4)
	sell.custom_minimum_size = Vector2(400, 0)
	cols.add_child(sell)
	sell.add_child(UIK.label("Verkaufen", 16, UIK.GOLD))
	var inv: Array = GameState.player()["inventory"]
	for i in inv.size():
		var st: Dictionary = inv[i]
		if DB.item(st["id"]).get("cat", "") == "quest":
			continue
		var b2 := UIK.button("%s ×%d – %d ◆" % [Inventory.display_name(st), st["n"], Dialogue.price_sell(st["id"], fid)], func():
			Dialogue.sell(npc_id, i)
			refresh())
		b2.alignment = HORIZONTAL_ALIGNMENT_LEFT
		sell.add_child(b2)
	box.add_child(UIK.button("« Zurück zum Gespräch", func():
		trading = false
		refresh()))
