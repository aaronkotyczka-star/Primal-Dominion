class_name AbilityRunner
extends RefCounted
## Executes abilities for any actor (player, creatures, NPCs). Actors must provide:
##   combatant: Combatant, play_action(anim, dur), get_forward() -> Vector3,
##   ability_cd: Dictionary, spend_stamina(n) -> bool, get_attack_value() -> float, team via combatant

const MASK_ACTORS := 2 | 4


static func ready(actor: Node, ability_id: String) -> bool:
	return float(actor.ability_cd.get(ability_id, 0.0)) <= 0.0


static func cd_left(actor: Node, ability_id: String) -> float:
	return float(actor.ability_cd.get(ability_id, 0.0))


static func execute(actor: Node3D, ability_id: String, ctx: Dictionary = {}) -> bool:
	var ab := DB.ability(ability_id)
	if ab.is_empty():
		return false
	if not ready(actor, ability_id):
		return false
	var stam := float(ab.get("stamina", 10)) * float(ctx.get("stamina_mult", 1.0))
	if not actor.spend_stamina(stam):
		if actor.is_in_group("player"):
			EventBus.notify.emit("Nicht genug Ausdauer.", "warn")
		return false
	actor.ability_cd[ability_id] = float(ab.get("cooldown", 3.0)) * float(ctx.get("cd_mult", 1.0))
	var anim: String = ab.get("anim", "bite")
	var dur := 0.7
	if anim in ["roar", "heal", "cast"]:
		dur = 0.9
	actor.play_action(anim, dur)
	var elements: Array = []
	var el = ab.get("element", "")
	if el == "slot":
		elements = ctx.get("element_slot", [])
		if elements.is_empty():
			elements = ["fire"]
	elif el != "":
		elements = [el]
	var potency := 1.0
	if elements.size() > 1:
		potency = float(DB.t("mixture").get(str(elements.size()), {}).get("potency", 0.5))
	var atk := float(ctx.get("atk", actor.get_attack_value()))
	var amount = atk * float(ab.get("dmg", 1.0)) * actor.combatant.dmg_mult() * randf_range(0.9, 1.1)
	if ab.has("base_dmg"):
		amount = float(ab["base_dmg"]) * float(ctx.get("spell_power", 1.0)) * (1.0 + 0.1 * GameState.skill_rank("elemental_affinity") if ctx.get("from_player", false) else 1.0)
	var hit := {"amount": amount, "elements": elements, "potency": potency, "source": actor, "statuses": [],
		"from_player": ctx.get("from_player", false), "armor_pierce": float(ab.get("armor_pierce", 0.0)), "melee": ab["kind"] in ["melee", "aoe", "move"]}
	if ab.has("status"):
		hit["statuses"].append(ab["status"])
	if ab.has("status2"):
		hit["statuses"].append(ab["status2"])
	if ab.has("knockback"):
		hit["knockback"] = ab["knockback"]
	var target: Node3D = ctx.get("target", null)
	var delay := 0.35
	match ab["kind"]:
		"melee":
			_delayed(actor, delay, func(): _melee(actor, hit, ab, ctx))
		"aoe":
			_delayed(actor, delay, func(): _aoe(actor, hit, ab, ctx))
		"ranged":
			_delayed(actor, 0.3, func(): _ranged(actor, hit, ab, ctx, target))
		"move":
			_move(actor, hit, ab, ctx, target)
		"buff":
			_buff(actor, ab, ctx)
		"spell":
			_spell(actor, hit, ab, ctx, target)
		"utility":
			if ab.get("harvest", false) and actor.has_method("harvest_nearby"):
				_delayed(actor, delay, func(): actor.harvest_nearby(3.0))
			if ab.has("reveal"):
				EventBus.notify.emit("Sonar: Kreaturen in %d m werden angezeigt." % int(ab["reveal"]), "info")
				actor.get_tree().call_group("creatures", "reveal", actor.global_position, float(ab["reveal"]))
	if ab.has("ally_buff"):
		_ally_buff(actor, ab)
	if ab.has("ally_heal"):
		for a in allies_near(actor, float(ab.get("radius", 15.0))):
			var c: Combatant = a.combatant
			c.heal(c.max_hp * float(ab["ally_heal"]))
	Audio.play_ability(ability_id, actor)
	return true


static func _delayed(actor: Node, t: float, f: Callable) -> void:
	var wr: WeakRef = weakref(actor)
	actor.get_tree().create_timer(t, false).timeout.connect(func():
		var a = wr.get_ref()
		if a != null and a.combatant and not a.combatant.dead:
			f.call())


static func reach_of(actor: Node3D) -> float:
	if actor.has_method("get_reach"):
		return actor.get_reach()
	return 2.0


static func _melee(actor: Node3D, hit: Dictionary, ab: Dictionary, ctx: Dictionary) -> void:
	var fwd: Vector3 = actor.get_forward()
	if ab.get("rear", false):
		fwd = -fwd
	var arc := float(ab.get("arc", 90.0))
	var hits := cone_targets(actor, actor.global_position, fwd, reach_of(actor) * (1.3 if ab.get("rear", false) else 1.0), arc, 3)
	for t in hits:
		apply_hit(actor, t, hit)


static func _aoe(actor: Node3D, hit: Dictionary, ab: Dictionary, ctx: Dictionary) -> void:
	var r := float(ab.get("radius", 1.0))
	if not ab.get("radius_abs", false):
		r *= reach_of(actor) * 1.4
	if hit["amount"] <= 0.0 and hit["statuses"].is_empty():
		return
	for t in cone_targets(actor, actor.global_position, actor.get_forward(), r, 360.0, 12):
		var h := hit.duplicate()
		if hit["amount"] <= 0.01:
			h["amount"] = 0.0
		apply_hit(actor, t, h)


static func _ranged(actor: Node3D, hit: Dictionary, ab: Dictionary, ctx: Dictionary, target: Node3D) -> void:
	var origin: Vector3 = actor.get_muzzle() if actor.has_method("get_muzzle") else actor.global_position + Vector3.UP
	var dir: Vector3 = ctx.get("aim_dir", actor.get_forward())
	if target and is_instance_valid(target):
		dir = (target_point(target) - origin).normalized()
	if ab.get("cone", false):
		var rng := float(ab.get("range", 12.0))
		for t in cone_targets(actor, origin, dir, rng, 50.0, 10):
			apply_hit(actor, t, hit)
		Fx.cone_breath(actor, origin, dir, rng, hit["elements"])
		return
	var n := int(ab.get("multishot", 1))
	for i in n:
		var d := dir
		if n > 1:
			d = dir.rotated(Vector3.UP, deg_to_rad((i - (n - 1) * 0.5) * 7.0))
		Projectile.spawn(actor, origin, d * 45.0, hit, ab.get("projectile", "bolt"), float(ab.get("range", 40.0)))


static func _move(actor: Node3D, hit: Dictionary, ab: Dictionary, ctx: Dictionary, target: Node3D) -> void:
	var dist := float(ab.get("range", 10.0))
	var dir: Vector3 = actor.get_forward()
	if target and is_instance_valid(target):
		var to := target.global_position - actor.global_position
		to.y = 0
		dist = minf(dist, to.length())
		dir = to.normalized()
	if ab.get("blink", false) and target and is_instance_valid(target):
		var behind := target.global_position - dir * 2.5
		behind.y = WorldData.height_at(behind.x, behind.z) + 0.2
		if actor.has_method("blink_to"):
			actor.blink_to(behind, target)
		_delayed(actor, 0.15, func(): apply_hit(actor, target, hit))
		return
	if actor.has_method("dash"):
		actor.dash(dir, dist, 0.35)
	_delayed(actor, 0.35, func():
		for t in cone_targets(actor, actor.global_position, actor.get_forward(), reach_of(actor) * 1.2, 120.0, 3):
			apply_hit(actor, t, hit))


static func _buff(actor: Node3D, ab: Dictionary, ctx: Dictionary) -> void:
	if ab.has("buff"):
		actor.combatant.add_buff(ab.get("name", "buff"), ab["buff"])


static func _ally_buff(actor: Node3D, ab: Dictionary) -> void:
	for a in allies_near(actor, float(ab.get("radius", 15.0))):
		a.combatant.add_buff(ab["name"], ab["ally_buff"])


static func _spell(actor: Node3D, hit: Dictionary, ab: Dictionary, ctx: Dictionary, target: Node3D) -> void:
	var heal_power := float(ctx.get("heal_power", 1.0))
	if ab.has("projectile"):
		_delayed(actor, 0.35, func(): _ranged(actor, hit, ab, ctx, target))
		return
	var recipients: Array = []
	var tgt_kind: String = ab.get("target", "self")
	if ab.has("radius"):
		recipients = allies_near(actor, float(ab["radius"]))
		recipients.append(actor)
	elif tgt_kind in ["ally_or_self", "ally"]:
		if target and is_instance_valid(target) and target.has_node("Combatant") and (target.get_node("Combatant") as Combatant).team == actor.combatant.team:
			recipients = [target]
		elif tgt_kind == "ally_or_self":
			recipients = [actor]
		else:
			var near := allies_near(actor, 12.0)
			if not near.is_empty():
				near.sort_custom(func(a, b): return a.combatant.hp_frac() < b.combatant.hp_frac())
				recipients = [near[0]]
	for r in recipients:
		var c: Combatant = r.combatant if "combatant" in r else r.get_node("Combatant")
		if ab.has("heal"):
			c.heal(float(ab["heal"]) * heal_power)
			Fx.heal_burst(r)
		if ab.has("shield"):
			c.shield = float(ab["shield"]) * heal_power
			Fx.shield_glow(r)
		if ab.get("cleanse", false):
			c.clear_negative()
			Fx.heal_burst(r)


static func allies_near(actor: Node3D, radius: float) -> Array:
	var out := []
	var team: String = actor.combatant.team
	for n in actor.get_tree().get_nodes_in_group("combat_actors"):
		if n == actor or not is_instance_valid(n):
			continue
		if n.combatant.team == team and not n.combatant.dead and n.global_position.distance_to(actor.global_position) <= radius:
			out.append(n)
	return out


static func target_point(t: Node3D) -> Vector3:
	if t.has_method("get_aim_point"):
		return t.get_aim_point()
	return t.global_position + Vector3.UP


static func cone_targets(actor: Node3D, origin: Vector3, fwd: Vector3, rng: float, arc_deg: float, max_n: int) -> Array:
	var out := []
	var team: String = actor.combatant.team
	var f2 := Vector3(fwd.x, 0, fwd.z).normalized()
	var cos_half := cos(deg_to_rad(arc_deg * 0.5))
	for n in actor.get_tree().get_nodes_in_group("combat_actors"):
		if n == actor or not is_instance_valid(n) or n.combatant.dead:
			continue
		if not is_hostile(team, n.combatant.team, actor, n):
			continue
		var p: Vector3 = n.global_position
		var rad: float = n.get_body_radius() if n.has_method("get_body_radius") else 0.5
		var to := p - origin
		var flat := Vector3(to.x, 0, to.z)
		var d := flat.length() - rad
		if d > rng or absf(to.y) > rng + 4.0:
			continue
		if arc_deg < 359.0 and flat.length() > rad and f2.dot(flat.normalized()) < cos_half:
			continue
		out.append(n)
	out.sort_custom(func(a, b): return a.global_position.distance_squared_to(origin) < b.global_position.distance_squared_to(origin))
	return out.slice(0, max_n)


static func is_hostile(team_a: String, team_b: String, a: Node = null, b: Node = null) -> bool:
	if team_a == team_b:
		return false
	if team_a == "neutral" or team_b == "neutral":
		# neutral creatures only become valid targets when attacking deliberately
		return a != null and a.is_in_group("player_side") and b != null and b.has_method("is_wild") and b.is_wild()
	return true


static func apply_hit(actor: Node3D, target: Node, hit: Dictionary) -> float:
	if not is_instance_valid(target) or not target.has_node("Combatant"):
		return 0.0
	var c: Combatant = target.get_node("Combatant")
	if c.dead:
		return 0.0
	if randf() < actor.combatant.miss_chance():
		Fx.float_text(target, "Verfehlt", Color(0.8, 0.8, 0.8))
		return 0.0
	var h := hit.duplicate()
	h["source"] = actor
	var dealt := c.take_hit(h)
	if dealt > 0.0 or float(h.get("torpor", 0.0)) > 0.0:
		Fx.hit_spark(target, h.get("elements", []))
		if Settings.get_v("show_damage_numbers"):
			Fx.float_text(target, str(int(round(dealt))), Color(1, 0.85, 0.5) if h.get("from_player", false) else Color(1, 0.4, 0.35))
	if h.has("knockback") and target.has_method("apply_knockback"):
		var dir = (target.global_position - actor.global_position)
		dir.y = 0
		target.apply_knockback(dir.normalized() * float(h["knockback"]))
	if target.has_method("on_hit_by"):
		target.on_hit_by(actor, dealt)
	return dealt
