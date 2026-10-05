class_name Taming
extends RefCounted
## Interaction logic between player and creatures: taming methods, corpses, companions.

static func prompt(c: Creature, p: Player) -> String:
	if c.combatant.dead:
		return "" if c.looted else "E: Ausweiden / Untersuchen"
	if not c.wild:
		if p.mount == c:
			return ""
		var ride := Creatures.can_ride(c.rec)
		if ride["ok"]:
			return "E: %s reiten" % c.rec["name"]
		return "E: %s (Gefährte)" % c.rec["name"]
	var m: String = c.sp.get("tame", {}).get("method", "")
	if c.in_need == "tar":
		return "E: %s aus dem Teer ziehen" % c.sp["name"]
	if c.in_need == "trap":
		return "E: %s aus der Falle befreien (Verband nötig)" % c.sp["name"]
	if c.combatant.unconscious:
		return "E: Füttern (Zähmung %d%%)" % int(c.tame_progress / c.tame_needed * 100.0)
	if m == "trust" and c.ai.state != "flee":
		if c.wariness > 60.0:
			return "%s ist misstrauisch – ducke dich und nähere dich langsam" % c.sp["name"]
		return "E: Futter anbieten (Vertrauen %d/%d)" % [c.feedings, int(c.sp["tame"].get("feedings", 3))]
	if m == "magic" and c.combatant.hp_frac() < 0.3:
		return "E: Bindungsrune einsetzen" if Inventory.count(GameState.player()["inventory"], "binding_rune") > 0 else "Bindungsrune nötig (Alchemie)"
	return ""


static func can_interact(c: Creature, p: Player) -> bool:
	return prompt(c, p) != "" and not prompt(c, p).ends_with("langsam") and not prompt(c, p).begins_with("Bindungsrune nötig")


static func interact(c: Creature, p: Player) -> void:
	var inv: Array = GameState.player()["inventory"]
	if c.combatant.dead:
		var loot := c.loot_corpse(p)
		p.play_action("gather", 0.8)
		var names := []
		for l in loot:
			Inventory.add(inv, l[0], int(l[1]))
			names.append("%d× %s" % [l[1], DB.item_name(l[0])])
		if c.wild:
			Research.add_points(1)
		EventBus.notify.emit("Erbeutet: " + (", ".join(names) if not names.is_empty() else "nichts"), "info")
		EventBus.inventory_changed.emit()
		Audio.play_at("hit_flesh", c.global_position)
		return
	if not c.wild:
		if Creatures.can_ride(c.rec)["ok"] and p.mount == null:
			p.mount_creature(c)
		else:
			var ui := p.get_tree().get_first_node_in_group("ui")
			if ui:
				ui.open_creature(c.uid)
		return
	if c.in_need == "tar":
		_rescue_tar(c, p)
		return
	if c.in_need == "trap":
		if Inventory.count(inv, "bandage") <= 0:
			EventBus.notify.emit("Du brauchst einen Verband, um die Wunde zu versorgen.", "warn")
			return
		Inventory.remove(inv, "bandage", 1)
		c.in_need = ""
		GameState.set_flag("wolf_rescued", true)
		c.become_tamed("rescue", 55.0)
		return
	var m: String = c.sp.get("tame", {}).get("method", "")
	if c.combatant.unconscious:
		_feed_unconscious(c, p)
	elif m == "trust":
		_offer_trust(c, p)
	elif m == "magic" and c.combatant.hp_frac() < 0.3:
		_bind(c, p)


static func _best_food(c: Creature) -> String:
	var inv: Array = GameState.player()["inventory"]
	var best := ""
	var bv := 0.0
	for st in inv:
		var v := c.food_value(st["id"])
		if v > bv:
			bv = v
			best = st["id"]
	return best


static func _feed_unconscious(c: Creature, p: Player) -> void:
	var inv: Array = GameState.player()["inventory"]
	if Inventory.count(inv, "narcotic") > 0 and c.combatant.torpor < c.combatant.max_torpor * 0.35:
		Inventory.remove(inv, "narcotic", 1)
		c.combatant.torpor = minf(c.combatant.max_torpor, c.combatant.torpor + c.combatant.max_torpor * 0.4)
		EventBus.notify.emit("Betäubungsmittel verabreicht – es schläft weiter.", "info")
		EventBus.inventory_changed.emit()
		return
	var food := _best_food(c)
	if food == "":
		EventBus.notify.emit("Kein passendes Futter. %s frisst: %s" % [c.sp["name"], ", ".join(Array(c.sp.get("food", [])).map(func(f): return DB.item_name(f)))], "warn")
		return
	Inventory.remove(inv, food, 1)
	EventBus.inventory_changed.emit()
	var val := c.food_value(food) * float(DB.item(food).get("food", 10)) * float(DB.item(food).get("tame_bonus", 1.0))
	val *= (1.0 + 0.2 * GameState.skill_rank("tame_knockout")) * float(GameState.rule("taming"))
	val *= 1.0 - clampf(c.distrust / 100.0, 0.0, 0.6)
	c.tame_progress += val
	p.play_action("interact", 0.5)
	Audio.play_at("eat", c.global_position)
	c.combatant.torpor = minf(c.combatant.max_torpor, c.combatant.torpor + c.combatant.max_torpor * 0.03)
	if c.tame_progress >= c.tame_needed:
		var bond := 25.0 + (15.0 if food == "kibble" else 0.0)
		c.become_tamed("knockout", bond)
	else:
		EventBus.notify.emit("%s gefüttert (%s). Zähmung %d%%" % [c.sp["name"], DB.item_name(food), int(c.tame_progress / c.tame_needed * 100.0)], "info")


static func _offer_trust(c: Creature, p: Player) -> void:
	if c.feed_cd > 0.0:
		EventBus.notify.emit("%s frisst noch …" % c.sp["name"], "info")
		return
	if c.wariness > 60.0:
		EventBus.notify.emit("%s ist zu misstrauisch." % c.sp["name"], "warn")
		return
	var food := _best_food(c)
	if food == "":
		EventBus.notify.emit("Kein passendes Futter. %s mag: %s" % [c.sp["name"], ", ".join(Array(c.sp.get("food", [])).map(func(f): return DB.item_name(f)))], "warn")
		return
	var inv: Array = GameState.player()["inventory"]
	Inventory.remove(inv, food, 1)
	EventBus.inventory_changed.emit()
	c.feedings += 1
	c.feed_cd = 6.0 / (1.0 + 0.25 * GameState.skill_rank("tame_trust"))
	c.trust += c.food_value(food) * 20.0
	c.visual.animator.play("eat", 2.0)
	p.play_action("interact", 0.6)
	Audio.play_at("eat", c.global_position)
	var need := maxi(1, int(round(int(c.sp["tame"].get("feedings", 3)) * (1.0 + c.distrust / 100.0) / float(GameState.rule("taming")))))
	if food == "kibble":
		c.feedings += 1
	if c.feedings >= need:
		c.become_tamed("trust", 35.0 + c.trust * 0.1)
	else:
		EventBus.notify.emit("%s nimmt %s an. Vertrauen %d/%d" % [c.sp["name"], DB.item_name(food), c.feedings, need], "good")


static func _bind(c: Creature, p: Player) -> void:
	var inv: Array = GameState.player()["inventory"]
	if c.bind_cd > 0.0:
		return
	if Inventory.count(inv, "binding_rune") <= 0:
		return
	Inventory.remove(inv, "binding_rune", 1)
	EventBus.inventory_changed.emit()
	p.play_action("cast", 1.2)
	var chance := 0.35 + 0.12 * GameState.skill_rank("tame_magic") + (1.0 - c.combatant.hp_frac() / 0.3) * 0.2
	chance -= c.distrust / 200.0
	chance += 0.25 if c.combatant.unconscious else 0.0
	Fx.burst(c.global_position + Vector3.UP * c.body_h * 0.6, Color(0.5, 0.7, 1.0), c, 40, 0.2, 3.0, 1.0)
	if randf() < chance:
		c.become_tamed("magic", 30.0)
	else:
		c.bind_cd = 20.0
		c.distrust += 15.0
		c.combatant.add_buff("wut", {"dmg": 1.3, "speed": 1.15, "dur": 25.0})
		c.ai.on_attacked(p, 0.0)
		EventBus.notify.emit("Die Bindung ist gescheitert! Die Rune zerbricht, %s tobt." % c.sp["name"], "danger")


static func _rescue_tar(c: Creature, p: Player) -> void:
	for n in p.get_tree().get_nodes_in_group("creatures"):
		if n.wild and n != c and not n.combatant.dead and n.ai.temper in ["predator", "demonic"] and n.global_position.distance_to(c.global_position) < 40.0:
			EventBus.notify.emit("Erst die Raubtiere vertreiben!", "warn")
			return
	c.trust += 34.0
	p.play_action("gather", 1.0)
	Audio.play_at("splash", c.global_position)
	if c.trust >= 100.0:
		c.in_need = ""
		GameState.set_flag("stego_rescued", true)
		c.become_tamed("rescue", 60.0)
	else:
		EventBus.notify.emit("Du ziehst – noch ein Stück! (%d%%)" % int(c.trust), "info")
