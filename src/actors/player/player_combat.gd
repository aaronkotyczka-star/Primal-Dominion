class_name PlayerCombat
extends Node
## Weapons, combos, blocking/parry, ranged aiming, throwing, traps, hotbar and player abilities.

var p: Player
var aiming := false
var blocking := false
var combo := 0
var combo_t := 0.0
var attack_t := 0.0
var hold_t := 0.0
var draw_t := 0.0
var reload_t := 0.0
var ammo_sel := {} # wtype -> ammo id
var throw_item := ""
var trap_item := ""
var next_shot_mult := 1.0
var fp_view: Node3D = null


func setup(player: Player) -> void:
	p = player


func equipped_stack(slot: String = "weapon") -> Dictionary:
	var e: Dictionary = GameState.player()["equipment"]
	var id: String = e.get(slot, "")
	if id == "":
		return {}
	var ed: Dictionary = GameState.player().get("equipment_data", {})
	if ed.has(slot) and ed[slot].get("id", "") == id:
		return ed[slot]
	return {"id": id, "n": 1, "q": 1.0, "d": {}}


func wtype() -> String:
	if throw_item != "":
		return "throw"
	if trap_item != "":
		return "trap"
	if p.demon_form:
		return "claws"
	var st := equipped_stack()
	if st.is_empty():
		return "unarmed"
	return DB.item(st["id"]).get("wtype", "unarmed")


func weapon_stats() -> Dictionary:
	if p.demon_form:
		var dl := int(GameState.player()["demon"].get("level", 1))
		return {"dmg": 28.0 + dl * 3.0, "kind": "cut", "speed": 1.15, "stam": 9, "reach": 2.6, "torpor": 0}
	var st := equipped_stack()
	if st.is_empty():
		return {"dmg": 6.0, "kind": "blunt", "speed": 1.2, "stam": 6, "reach": 1.6, "torpor": 5.0}
	return Inventory.stats_of(st)


func reach() -> float:
	return float(weapon_stats().get("reach", 2.0))


func attack_value() -> float:
	var s := weapon_stats()
	var dmg := float(s.get("dmg", 6.0))
	var w := wtype()
	if w in ["bow", "crossbow", "gun", "blowpipe"]:
		dmg *= 1.0 + 0.08 * GameState.skill_rank("ranged_aim")
	else:
		dmg *= 1.0 + 0.08 * GameState.skill_rank("melee_power")
	if p.demon_form:
		dmg *= 1.0 + 0.1 * int(GameState.player()["demon"]["skills"].get("d_might", 0))
	return dmg * float(GameState.rule("dmg_dealt")) * p.combatant.dmg_mult()


func attacking() -> bool:
	return attack_t > 0.0


func rider_weapon_allowed(c: Creature) -> bool:
	var allowed: Array = c.sp.get("rider_weapons", [])
	var w := wtype()
	if w in ["unarmed", "claws"]:
		return false
	if w == "throw":
		return "throw" in allowed
	return w in allowed or GameState.skill_rank("beast_mount") >= 2


func refresh_gear() -> void:
	if p.visual == null:
		return
	if p.demon_form:
		p.visual.set_gear("hand_R", null)
		p.visual.set_gear("hand_L", null)
		_set_fp_view(null)
		return
	var st := equipped_stack()
	var wt = DB.item(st.get("id", "")).get("wtype", "") if not st.is_empty() else ""
	var node: Node3D = null
	if throw_item != "":
		node = GearFactory.make_weapon({"id": throw_item, "n": 1})
	elif not st.is_empty():
		node = GearFactory.make_weapon(st)
	if wt == "bow":
		p.visual.set_gear("hand_R", null)
		p.visual.set_gear("hand_L", node)
	else:
		p.visual.set_gear("hand_R", node)
		var off := equipped_stack("offhand")
		p.visual.set_gear("hand_L", GearFactory.make_weapon(off) if not off.is_empty() else null)
	p.visual.animator.hold_pose = {"bow": "bow", "spear": "spear", "staff": "staff", "torch": "torch"}.get(wt, "")
	_set_fp_view(GearFactory.make_weapon(st if throw_item == "" else {"id": throw_item, "n": 1}) if not st.is_empty() or throw_item != "" else null)


func _set_fp_view(node: Node3D) -> void:
	if fp_view:
		fp_view.queue_free()
		fp_view = null
	if node == null or p.rig == null:
		return
	fp_view = Node3D.new()
	p.rig.cam.add_child(fp_view)
	fp_view.position = Vector3(0.28, -0.32, -0.55)
	fp_view.rotation_degrees = Vector3(-60, 8, 0)
	fp_view.add_child(node)
	fp_view.visible = p.rig.first_person


# ------------------------------------------------------------------ per frame
func process_combat(it: Dictionary, delta: float) -> void:
	attack_t = maxf(0.0, attack_t - delta)
	combo_t = maxf(0.0, combo_t - delta)
	reload_t = maxf(0.0, reload_t - delta)
	if combo_t <= 0.0:
		combo = 0
	if fp_view:
		fp_view.visible = p.rig.first_person and p.mount == null
	if p.ui_blocking:
		aiming = false
		blocking = false
		p.combatant.blocking = false
		return
	var w := wtype()
	var ranged = w in ["bow", "crossbow", "gun", "blowpipe", "throw"] or (w == "staff" and DB.item(equipped_stack().get("id", "")).get("stats", {}).has("bolt"))
	if p.mount and not rider_weapon_allowed(p.mount):
		ranged = false
		w = "none"
	# hotbar
	for i in 6:
		if it.get("slot_%d_just" % (i + 1), false):
			use_hotbar(i)
	# target lock
	if it.get("lock_target_just", false):
		_toggle_lock()
	# abilities
	for i in 4:
		if it.get("ability_%d_just" % (i + 1), false) and p.controlled == null and (p.mount == null or false):
			use_loadout(i)
	# block / aim
	var rmb: bool = it.get("block", false)
	if ranged:
		aiming = rmb
		blocking = false
	else:
		aiming = false
		blocking = rmb and w != "none" and attack_t <= 0.0
		if it.get("block_just", false) and w != "none":
			p.combatant.parry_window = 0.22 + 0.05 * GameState.skill_rank("def_parry")
	p.rig.aiming = aiming
	p.combatant.blocking = blocking
	var off := equipped_stack("offhand")
	var bp := 0.35 + (float(Inventory.stats_of(off).get("block", 0.0)) if not off.is_empty() else 0.0) * 0.6
	p.combatant.block_power = clampf(bp * (1.0 + 0.15 * GameState.skill_rank("def_block")), 0.2, 0.92)
	p.visual.animator.block = blocking
	p.visual.animator.aiming = aiming and w == "bow"
	if blocking:
		p.stamina = maxf(0.0, p.stamina - delta * 2.0)
	if w == "none":
		return
	# attacks
	if ranged:
		_ranged(it, delta, w)
	else:
		if it.get("attack", false):
			hold_t += delta
			if hold_t > 0.45 and attack_t <= 0.0 and not blocking:
				_melee(true)
				hold_t = -10.0
		if it.get("attack_released", false):
			if hold_t > 0.0 and hold_t <= 0.45 and attack_t <= 0.0 and not blocking:
				_melee(false)
			hold_t = 0.0


func _melee(heavy: bool) -> void:
	var s := weapon_stats()
	var cost := float(s.get("stam", 10)) * (1.6 if heavy else 1.0)
	if not p.spend_stamina(cost):
		EventBus.notify.emit("Zu erschöpft zum Angreifen.", "warn")
		return
	var speed := float(s.get("speed", 1.0)) * (1.0 + 0.1 * GameState.skill_rank("melee_combo"))
	var anims := ["slash", "slash2", "thrust"]
	if wtype() in ["spear"]:
		anims = ["thrust", "thrust", "slash"]
	elif wtype() in ["club", "axe", "pick"]:
		anims = ["slash", "slash2", "overhead"]
	var max_combo := 3 + (1 if GameState.skill_rank("melee_combo") >= 2 else 0)
	var anim: String = "overhead" if heavy else anims[combo % 3]
	var dur := (0.95 if heavy else 0.62) / speed
	attack_t = dur * 0.85
	p.play_action(anim, dur)
	Audio.play_at("swing", p.global_position, -6.0)
	var mult := 1.0 + 0.12 * combo
	if heavy:
		mult = 1.9
	combo = (combo + 1) % max_combo
	combo_t = dur + 0.6
	var torpor := float(s.get("torpor", 0.0)) * (1.6 if heavy else 1.0)
	var elements: Array = []
	if s.has("element"):
		elements = [s["element"]]
	var stk := equipped_stack()
	if stk.get("d", {}).has("rune"):
		elements = [DB.item(stk["d"]["rune"]).get("element", "fire")]
	var hit := {"amount": attack_value() * mult, "elements": elements, "potency": 1.0 + 0.2 * GameState.skill_rank("craft_runes"),
		"torpor": torpor * (1.0 + 0.2 * GameState.skill_rank("ranged_tranq")), "from_player": true, "melee": true, "statuses": []}
	if p.demon_form and randf() < 0.3:
		hit["statuses"].append("bleeding")
	if heavy:
		hit["knockback"] = 4.0
	p.get_tree().create_timer(dur * 0.45, false).timeout.connect(func(): _melee_impact(hit))


func _melee_impact(hit: Dictionary) -> void:
	if not is_instance_valid(p) or p.dead:
		return
	var origin := p.global_position
	var fwd := p.get_forward()
	if p.mount:
		origin = p.mount.global_position
	var targets := AbilityRunner.cone_targets(p, origin, fwd, reach() + (p.mount.get_body_radius() if p.mount else 0.0), 110.0, 3)
	var any := false
	for t in targets:
		if t.combatant.hp > 0:
			var h := hit.duplicate()
			if float(GameState.skill_rank("melee_execute")) > 0 and t.combatant.hp_frac() < 0.3:
				h["amount"] = float(h["amount"]) * (1.0 + 0.25 * GameState.skill_rank("melee_execute"))
			AbilityRunner.apply_hit(p, t, h)
			Audio.play_at("hit_flesh", t.global_position, -2.0)
			any = true
			if t is Creature and t.wild:
				GameState.lexicon_mark(t.species_id, "seen")
	if not any:
		var world := p.get_tree().get_first_node_in_group("world")
		if world and world.has_method("harvest_hit"):
			world.harvest_hit(p, origin + Vector3.UP, fwd, reach() + 0.6, weapon_stats())
	if any:
		p.rig.shake(0.08)


func _ranged(it: Dictionary, delta: float, w: String) -> void:
	if w == "throw":
		if it.get("attack_just", false) and attack_t <= 0.0:
			_throw()
		return
	if w == "staff":
		if it.get("attack_just", false) and attack_t <= 0.0 and aiming:
			_staff_bolt()
		elif it.get("attack_just", false) and attack_t <= 0.0:
			_melee(false)
		return
	var ammo := current_ammo(w)
	if w == "bow":
		if it.get("attack", false) and aiming:
			draw_t = minf(1.0, draw_t + delta * 1.3 * (1.0 + 0.12 * GameState.skill_rank("ranged_draw")))
		if it.get("attack_released", false) and draw_t > 0.15:
			if ammo == "":
				EventBus.notify.emit("Keine passende Munition.", "warn")
			else:
				_fire(ammo, w, lerpf(0.35, 1.0, draw_t))
			draw_t = 0.0
		if not aiming:
			draw_t = 0.0
		return
	if it.get("attack_just", false) and reload_t <= 0.0:
		if ammo == "":
			EventBus.notify.emit("Keine passende Munition.", "warn")
			return
		_fire(ammo, w, 1.0)
		var spd := float(weapon_stats().get("speed", 1.0)) * (1.0 + 0.12 * GameState.skill_rank("ranged_draw"))
		reload_t = 1.6 / spd if w != "blowpipe" else 0.7


func current_ammo(w: String) -> String:
	var allowed: Array = weapon_stats().get("ammo", [])
	var inv: Array = GameState.player()["inventory"]
	var sel: String = ammo_sel.get(w, "")
	if sel != "" and sel in allowed and Inventory.count(inv, sel) > 0:
		return sel
	for a in allowed:
		if Inventory.count(inv, a) > 0:
			return a
	return ""


func cycle_ammo() -> void:
	var w := wtype()
	var allowed: Array = weapon_stats().get("ammo", [])
	var inv: Array = GameState.player()["inventory"]
	var avail := allowed.filter(func(a): return Inventory.count(inv, a) > 0)
	if avail.is_empty():
		return
	var cur := current_ammo(w)
	var i := avail.find(cur)
	ammo_sel[w] = avail[(i + 1) % avail.size()]
	EventBus.notify.emit("Munition: " + DB.item_name(ammo_sel[w]), "info")


func _fire(ammo: String, w: String, power: float) -> void:
	var s := weapon_stats()
	if not p.spend_stamina(float(s.get("stam", 5))):
		return
	var am = DB.item(ammo).get("stats", {})
	Inventory.remove(GameState.player()["inventory"], ammo, 1)
	EventBus.inventory_changed.emit()
	var ray := p.rig.aim_ray(float(s.get("reach", 60)) * 2.0, [p.get_rid()] + ([p.mount.get_rid()] if p.mount else []))
	var origin := p.get_muzzle()
	if p.mount:
		origin = p.mount.global_position + Vector3(0, p.mount.body_h + 1.3, 0)
	var dir: Vector3 = (ray["point"] - origin).normalized()
	var spread := (1.0 - power) * 0.04 / (1.0 + GameState.skill_rank("ranged_aim") * 0.3)
	dir = (dir + Vector3(randf_range(-spread, spread), randf_range(-spread, spread), randf_range(-spread, spread))).normalized()
	var dmg := attack_value() * float(am.get("dmg_mult", 1.0)) * power * next_shot_mult
	var elements: Array = [am["element"]] if am.has("element") else []
	var hit := {"amount": dmg, "elements": elements, "torpor": float(am.get("torpor", 0.0)) * power * (1.0 + 0.2 * GameState.skill_rank("ranged_tranq")),
		"from_player": true, "headshot_bonus": 0.5, "armor_pierce": 0.5 if next_shot_mult > 1.0 else 0.0}
	next_shot_mult = 1.0
	var speed := 55.0 * power if w == "bow" else 80.0
	var kind := "arrow" if w in ["bow", "crossbow", "blowpipe"] else ("bolt" if ammo == "rune_charge" else "bullet")
	if ammo == "rune_charge":
		var els := ["fire", "lightning", "ice"]
		hit["elements"] = [els[randi() % 3]]
	Projectile.spawn(p, origin, dir * speed, hit, kind, float(s.get("reach", 60)))
	p.play_action("bow_release" if w == "bow" else "thrust", 0.3)
	Audio.play_at("bow_shot" if w in ["bow", "crossbow", "blowpipe"] else "gun_shot", p.global_position, 0.0 if w != "gun" else 6.0, 1.0, 1.0 if w != "gun" else 3.0)
	if w == "gun":
		p.rig.shake(0.3)
		# loud: alerts predators
		for c in p.get_tree().get_nodes_in_group("creatures"):
			if c.wild and c.global_position.distance_to(p.global_position) < 70.0 and c.ai.temper in ["predator", "territorial"]:
				c.ai.target = p
				c.ai._go("chase", 15.0)


func _staff_bolt() -> void:
	var s := weapon_stats()
	if not p.spend_stamina(14.0):
		return
	attack_t = 0.5
	p.play_action("cast", 0.5)
	var ray := p.rig.aim_ray(80.0, [p.get_rid()])
	var origin := p.get_muzzle()
	var dir: Vector3 = (ray["point"] - origin).normalized()
	var st := equipped_stack()
	var el := "lightning"
	if st.get("d", {}).has("rune"):
		el = DB.item(st["d"]["rune"]).get("element", el)
	var hit := {"amount": float(s.get("bolt", 20.0)) * float(s.get("spell_power", 1.0)) * (1.0 + 0.1 * GameState.skill_rank("elemental_affinity")), "elements": [el], "from_player": true}
	Projectile.spawn(p, origin, dir * 40.0, hit, "bolt", 60.0)
	Audio.play_at("spell_cast", p.global_position)


func _throw() -> void:
	var inv: Array = GameState.player()["inventory"]
	if Inventory.count(inv, throw_item) <= 0:
		throw_item = ""
		refresh_gear()
		return
	if not p.spend_stamina(10.0):
		return
	var s: Dictionary = DB.item(throw_item).get("stats", {})
	Inventory.remove(inv, throw_item, 1)
	EventBus.inventory_changed.emit()
	attack_t = 0.6
	p.play_action("throw", 0.6)
	var ray := p.rig.aim_ray(60.0, [p.get_rid()])
	var origin := p.get_muzzle() + Vector3(0, 0.3, 0)
	var dir: Vector3 = (ray["point"] - origin).normalized()
	dir.y += 0.08
	var hit := {"amount": float(s.get("dmg", 5.0)) * (1.0 + 0.25 * GameState.skill_rank("hunt_bola")), "elements": [s["element"]] if s.has("element") else [], "from_player": true}
	if s.has("entangle"):
		hit["entangle"] = float(s["entangle"]) * (1.0 + 0.25 * GameState.skill_rank("hunt_bola"))
	if s.has("aoe"):
		hit["aoe"] = s["aoe"]
	var kind := "javelin" if throw_item == "javelin" else ("bola" if throw_item == "bola" else "bomb")
	var pr := Projectile.spawn(p, origin, dir.normalized() * 26.0, hit, kind, 40.0)
	pr.gravity = 9.8
	var thrown := throw_item
	if Inventory.count(inv, throw_item) <= 0:
		throw_item = ""
		refresh_gear()


func _toggle_lock() -> void:
	if p.rig.lock_target:
		p.rig.lock_target = null
		return
	var best: Node3D = null
	var best_s := 1e9
	var fwd := p.rig.forward_flat()
	for n in p.get_tree().get_nodes_in_group("combat_actors"):
		if n == p or n.combatant.dead or n.combatant.team == "player":
			continue
		var to: Vector3 = n.global_position - p.global_position
		var d := to.length()
		if d > 35.0:
			continue
		var f := fwd.dot(Vector3(to.x, 0, to.z).normalized())
		if f < 0.3:
			continue
		var sc := d * (2.0 - f)
		if sc < best_s:
			best_s = sc
			best = n
	p.rig.lock_target = best


# ------------------------------------------------------------------ hotbar & loadout
func use_hotbar(i: int) -> void:
	var pl := GameState.player()
	var id: String = pl["hotbar"][i]
	if id == "":
		return
	var it := DB.item(id)
	var cat: String = it.get("cat", "")
	var inv: Array = pl["inventory"]
	throw_item = ""
	trap_item = ""
	if cat in ["weapon", "tool"] and it.has("wtype"):
		if pl["equipment"]["weapon"] == id:
			return
		if Inventory.count(inv, id) <= 0:
			EventBus.notify.emit("%s nicht im Inventar." % it.get("name", id), "warn")
			return
		Equipment.equip_from_inventory(id)
	elif cat == "ammo" and it.get("wtype", "") == "throw":
		if Inventory.count(inv, id) > 0:
			throw_item = id
			EventBus.notify.emit("Wurfwaffe bereit: %s (LMB)" % it["name"], "info")
	elif cat == "ammo":
		ammo_sel[wtype()] = id
		EventBus.notify.emit("Munition: " + it["name"], "info")
	elif cat == "trap":
		if Inventory.count(inv, id) > 0:
			place_trap(id)
	elif cat in ["food", "consumable"]:
		if Inventory.count(inv, id) > 0:
			p.eat(id)
		else:
			EventBus.notify.emit("%s ist aufgebraucht." % it.get("name", id), "warn")
	refresh_gear()


func place_trap(id: String) -> void:
	var pos := p.global_position + p.get_forward() * 2.5
	pos.y = WorldData.height_at(pos.x, pos.z)
	Inventory.remove(GameState.player()["inventory"], id, 1)
	EventBus.inventory_changed.emit()
	var world := p.get_tree().get_first_node_in_group("world")
	if world:
		world.place_trap(id, pos)


func loadout() -> Array:
	var pl := GameState.player()
	if p.demon_form:
		var out := []
		for sk in pl["demon"]["skills"]:
			var dd: Dictionary = DB.get_entry("demon_skills", sk)
			if dd.get("kind", "") == "active" and out.size() < 4:
				out.append(dd["ability"])
		return out
	return pl["loadout"]


func use_loadout(i: int) -> void:
	var lo := loadout()
	if i >= lo.size() or lo[i] == "":
		return
	var ab_id: String = lo[i]
	if ab_id == "aimed_shot":
		if AbilityRunner.ready(p, ab_id) and p.spend_stamina(15.0):
			next_shot_mult = 2.0
			p.ability_cd[ab_id] = 6.0
			EventBus.notify.emit("Gezielter Schuss bereit.", "info")
		return
	var st := weapon_stats()
	var ray := p.rig.aim_ray(80.0, [p.get_rid()])
	var target: Node3D = p.rig.lock_target
	if target == null and ray["hit"] and ray["hit"]["collider"] is Node3D and ray["hit"]["collider"].has_node("Combatant"):
		target = ray["hit"]["collider"]
	var ctx := {"from_player": true, "target": target, "aim_dir": ray["dir"], "atk": attack_value(),
		"spell_power": float(st.get("spell_power", 1.0)) * (1.6 if p.demon_form else 1.0),
		"heal_power": float(st.get("spell_power", 1.0)) * (1.0 + 0.2 * GameState.skill_rank("heal_mend"))}
	if ab_id == "multishot":
		var ammo := current_ammo(wtype())
		if ammo == "":
			EventBus.notify.emit("Keine Pfeile.", "warn")
			return
		Inventory.remove(GameState.player()["inventory"], ammo, 2)
	AbilityRunner.execute(p, ab_id, ctx)
