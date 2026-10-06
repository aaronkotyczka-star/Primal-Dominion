class_name Combatant
extends Node
## Health, armor, torpor, status effects and elemental reactions for any actor.

signal died(killer: Node)
signal damaged(amount: float, hit: Dictionary)
signal knocked_out()
signal woke_up()
signal reaction(name: String)

var max_hp := 100.0
var hp := 100.0
var armor := 0.0 # flat; reduction = armor / (armor + 50)
var torpor := 0.0
var max_torpor := 0.0 # 0 = cannot be knocked out
var unconscious := false
var dead := false
var team := "wild"
var demonic := false
var affinity: Dictionary = {} # element -> strength (resist own, weak to weak_to)
var statuses: Dictionary = {} # id -> {t, stacks, src}
var shield := 0.0
var invulnerable := 0.0
var blocking := false
var block_power := 0.0
var parry_window := 0.0
var dmg_taken_mult := 1.0
var buffs: Dictionary = {} # id -> {t, data}
var last_attacker: WeakRef
var actor: Node3D
var in_combat_t := 0.0
var _tick := 0.0


func setup(owner_actor: Node3D, hp_max: float, arm: float, tm: String) -> void:
	actor = owner_actor
	max_hp = hp_max
	hp = hp_max
	armor = arm
	team = tm


func is_alive() -> bool:
	return not dead


func hp_frac() -> float:
	return hp / maxf(1.0, max_hp)


func has_status(id: String) -> bool:
	return statuses.has(id)


func is_stunned() -> bool:
	for s in statuses:
		if DB.get_entry("status", s).get("stun", false):
			return true
	return unconscious


func is_rooted() -> bool:
	for s in statuses:
		if DB.get_entry("status", s).get("root", false):
			return true
	if buffs.has("shell_up"):
		return true
	return false


func speed_mult() -> float:
	var m := 1.0
	for s in statuses:
		m *= 1.0 - float(DB.get_entry("status", s).get("slow", 0.0))
	for b in buffs:
		m *= float(buffs[b]["data"].get("speed", 1.0))
	return m


func dmg_mult() -> float:
	var m := 1.0
	for s in statuses:
		m *= float(DB.get_entry("status", s).get("dmg_mult", 1.0))
	for b in buffs:
		m *= float(buffs[b]["data"].get("dmg", 1.0))
	return m


func miss_chance() -> float:
	var m := 0.0
	for s in statuses:
		m = maxf(m, float(DB.get_entry("status", s).get("miss", 0.0)))
	return m


func add_buff(id: String, data: Dictionary) -> void:
	buffs[id] = {"t": float(data.get("dur", 8.0)), "data": data}


## Main entry: apply a hit. Returns actual damage dealt.
func take_hit(hit: Dictionary) -> float:
	if dead:
		return 0.0
	in_combat_t = 6.0
	var src: Node = hit.get("source", null)
	if src and is_instance_valid(src):
		last_attacker = weakref(src)
	if invulnerable > 0.0 and not hit.get("unavoidable", false):
		return 0.0
	var amount := float(hit.get("amount", 0.0))
	var elements: Array = hit.get("elements", [])
	var potency := float(hit.get("potency", 1.0))
	# parry / block (frontal only)
	if hit.get("melee", false) and (blocking or parry_window > 0.0) and src is Node3D and actor:
		var to_src := ((src as Node3D).global_position - actor.global_position)
		to_src.y = 0
		var fwd := -actor.global_transform.basis.z
		if to_src.length() > 0.01 and fwd.dot(to_src.normalized()) > 0.3:
			if parry_window > 0.0:
				parry_window = 0.0
				Audio.play_at("parry", actor.global_position)
				if src.has_node("Combatant"):
					var sc: Combatant = src.get_node("Combatant")
					sc.apply_status("stunned", 1.2, src)
				if actor.is_in_group("player"):
					EventBus.notify.emit("Parade!", "good")
				return 0.0
			amount *= 1.0 - block_power
			Audio.play_at("block", actor.global_position)
			if actor.has_method("on_blocked"):
				actor.on_blocked(hit)
	# elemental affinity & reactions
	var true_dmg: bool = hit.get("true_damage", false)
	var react_mult := 1.0
	var reaction_names := []
	for e in elements:
		var ed := DB.element(e)
		if affinity.has(e):
			amount *= 1.0 - 0.3 * float(affinity[e])
		for a in affinity:
			if e in DB.element(a).get("weak_to", []):
				amount *= 1.0 + 0.25 * float(affinity[a])
		if demonic and ed.has("vs_demonic"):
			amount *= float(ed["vs_demonic"])
		for r in DB.t("reactions"):
			if r["element"] == e and statuses.has(r["status"]):
				react_mult *= float(r.get("dmg_mult", 1.0)) * (1.0 + 0.2 * GameState.skill_rank("elemental_mastery") if hit.get("from_player", false) else 1.0)
				if r.get("true_damage", false):
					true_dmg = true
				if r.has("apply"):
					apply_status(r["apply"], float(DB.get_entry("status", r["apply"]).get("dur", 3.0)) * float(r.get("dur_mult", 1.0)), src)
				if r.get("consume", false):
					statuses.erase(r["status"])
				if r.has("aoe") and actor:
					_reaction_aoe(r, hit)
				if r.has("lifesteal") and src and src.has_node("Combatant"):
					(src.get_node("Combatant") as Combatant).heal(amount * float(r["lifesteal"]))
				reaction_names.append(r["name"])
	amount *= react_mult
	# mixed-element internal reactions (rule based: two components in one hit)
	if elements.size() >= 2:
		for r in DB.t("reactions"):
			var st_el := _element_for_status(r["status"])
			if st_el != "" and st_el in elements and r["element"] in elements and not r["name"] in reaction_names:
				amount *= 1.0 + (float(r.get("dmg_mult", 1.0)) - 1.0) * 0.6
				reaction_names.append(r["name"])
	for rn in reaction_names:
		reaction.emit(rn)
		if actor and hit.get("from_player", false):
			EventBus.notify.emit("Reaktion: " + rn, "info")
	if not true_dmg:
		var arm := armor * (1.0 - float(hit.get("armor_pierce", 0.0)))
		if statuses.has("shaken"):
			arm *= 0.7
		amount *= 50.0 / (50.0 + maxf(arm, 0.0))
	amount *= dmg_taken_mult
	for b in buffs:
		amount *= float(buffs[b]["data"].get("dmg_taken", 1.0))
		amount /= float(buffs[b]["data"].get("armor", 1.0))
	if shield > 0.0:
		var absorbed := minf(shield, amount)
		shield -= absorbed
		amount -= absorbed
	amount = maxf(0.0, amount)
	# torpor
	var tp := float(hit.get("torpor", 0.0))
	if tp > 0.0 and max_torpor > 0.0 and not dead:
		torpor = minf(max_torpor, torpor + tp)
		if torpor >= max_torpor and not unconscious:
			unconscious = true
			knocked_out.emit()
	# statuses from hit
	for e in elements:
		var st: String = DB.element(e).get("status", "")
		if st != "":
			var sd := DB.get_entry("status", st)
			if randf() < float(sd.get("chance", 1.0)) * clampf(potency, 0.2, 1.5):
				apply_status(st, float(sd.get("dur", 3.0)) * clampf(potency, 0.3, 1.5), src)
	for st2 in hit.get("statuses", []):
		apply_status(st2, float(DB.get_entry("status", st2).get("dur", 3.0)), src)
	hp -= amount
	damaged.emit(amount, hit)
	if hp <= 0.0:
		hp = 0.0
		dead = true
		died.emit(src)
	return amount


static var _status_el := {}


static func _element_for_status(st: String) -> String:
	if _status_el.is_empty():
		for e in DB.t("elements"):
			_status_el[DB.element(e).get("status", "")] = e
	return _status_el.get(st, "")


func _reaction_aoe(r: Dictionary, hit: Dictionary) -> void:
	var space := actor.get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var sh := SphereShape3D.new()
	sh.radius = float(r["aoe"])
	q.shape = sh
	q.transform = Transform3D(Basis(), actor.global_position)
	q.collision_mask = 2 | 4
	for res in space.intersect_shape(q, 16):
		var n: Node = res["collider"]
		if n == actor or not n.has_node("Combatant"):
			continue
		var c: Combatant = n.get_node("Combatant")
		if c.team == team:
			var h2 := {"amount": float(hit.get("amount", 0)) * 0.4, "elements": [], "source": hit.get("source"), "true_damage": true}
			if r.has("apply"):
				c.apply_status(r["apply"], 2.0, hit.get("source"))
			c.take_hit(h2)


func apply_status(id: String, dur: float, src: Node = null) -> void:
	var sd := DB.get_entry("status", id)
	if sd.is_empty() or dead:
		return
	if statuses.has(id):
		var s: Dictionary = statuses[id]
		s["t"] = maxf(s["t"], dur)
		if sd.has("stacks") or sd.has("stackable"):
			s["stacks"] = int(s.get("stacks", 1)) + 1
			var lim := int(sd.get("stacks", sd.get("stackable", 3)))
			if sd.has("stacks_to") and s["stacks"] >= lim:
				statuses.erase(id)
				apply_status(sd["stacks_to"], float(DB.get_entry("status", sd["stacks_to"]).get("dur", 2.0)), src)
				return
			s["stacks"] = mini(s["stacks"], lim)
	else:
		statuses[id] = {"t": dur, "stacks": 1, "src": weakref(src) if src else null}
	if sd.has("knockback") and actor and src is Node3D and actor.has_method("apply_knockback"):
		var dir := (actor.global_position - (src as Node3D).global_position)
		dir.y = 0
		actor.apply_knockback(dir.normalized() * float(sd["knockback"]))


func clear_negative() -> void:
	statuses.clear()


func heal(amount: float) -> void:
	if dead:
		return
	var m := 1.0
	if statuses.has("septic"):
		m = 0.5
	hp = minf(max_hp, hp + amount * m)


func process_effects(delta: float) -> void:
	if dead:
		return
	invulnerable = maxf(0.0, invulnerable - delta)
	parry_window = maxf(0.0, parry_window - delta)
	in_combat_t = maxf(0.0, in_combat_t - delta)
	for id in statuses.keys():
		var s: Dictionary = statuses[id]
		s["t"] -= delta
		var sd := DB.get_entry("status", id)
		if sd.has("dot"):
			var d := float(sd["dot"]) * max_hp * delta * int(s.get("stacks", 1))
			d = minf(d, 60.0 * delta * int(s.get("stacks", 1)))
			hp -= d
			if sd.has("lifesteal") and s.get("src") and s["src"].get_ref() and s["src"].get_ref().has_node("Combatant"):
				(s["src"].get_ref().get_node("Combatant") as Combatant).heal(d * float(sd["lifesteal"]))
			if hp <= 0.0:
				hp = 0.0
				dead = true
				var killer: Node = s["src"].get_ref() if s.get("src") and s["src"].get_ref() else null
				died.emit(killer)
				return
		if s["t"] <= 0.0:
			statuses.erase(id)
	for b in buffs.keys():
		buffs[b]["t"] -= delta
		if buffs[b]["t"] <= 0.0:
			buffs.erase(b)
	if unconscious:
		torpor -= delta * max_torpor * 0.012
		if torpor <= 0.0:
			torpor = 0.0
			unconscious = false
			woke_up.emit()
	elif torpor > 0.0:
		torpor = maxf(0.0, torpor - delta * max_torpor * 0.03)


func status_text() -> String:
	var parts := []
	for id in statuses:
		parts.append(DB.get_entry("status", id).get("name", id))
	return ", ".join(parts)
