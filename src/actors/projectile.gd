class_name Projectile
extends Node3D
## Raycast-stepped projectile (arrows, bolts, spells, spit, webs, thrown items).

var velocity := Vector3.ZERO
var gravity := 9.8
var hit: Dictionary = {}
var shooter: WeakRef
var max_dist := 60.0
var travelled := 0.0
var kind := "arrow"
var team := "player"
var stuck := false
var life := 0.0
var on_impact: Callable


static func spawn(shooter_node: Node3D, origin: Vector3, vel: Vector3, hit_data: Dictionary, kind_id: String = "arrow", rng: float = 60.0) -> Projectile:
	var p := Projectile.new()
	p.velocity = vel
	p.hit = hit_data
	p.shooter = weakref(shooter_node)
	p.kind = kind_id
	p.max_dist = rng * 1.6
	p.team = shooter_node.combatant.team if "combatant" in shooter_node else "player"
	p.gravity = 9.8 if kind_id in ["arrow", "javelin", "bola", "bomb", "spit"] else 0.6
	var root := shooter_node.get_tree().get_first_node_in_group("fx_root")
	(root if root else shooter_node.get_tree().current_scene).add_child(p)
	p.global_position = origin
	p._build_visual()
	return p


func _build_visual() -> void:
	var mi := MeshInstance3D.new()
	var col := Fx.element_color(hit.get("elements", []))
	match kind:
		"arrow", "javelin":
			var cm := CylinderMesh.new()
			cm.top_radius = 0.012 if kind == "arrow" else 0.025
			cm.bottom_radius = cm.top_radius
			cm.height = 0.75 if kind == "arrow" else 1.6
			var m := StandardMaterial3D.new()
			m.albedo_color = Color(0.35, 0.27, 0.18)
			cm.material = m
			mi.mesh = cm
			mi.rotation_degrees = Vector3(90, 0, 0)
			if not hit.get("elements", []).is_empty():
				Fx.glow_light(self, col, 3.0, 1.0)
		"bullet":
			var sm := SphereMesh.new()
			sm.radius = 0.03
			sm.height = 0.06
			mi.mesh = sm
		_:
			var sm2 := SphereMesh.new()
			sm2.radius = 0.15 if kind != "web" else 0.25
			sm2.height = sm2.radius * 2.0
			var m2 := StandardMaterial3D.new()
			m2.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			if kind == "spit":
				col = Color(0.5, 0.9, 0.2)
			elif kind == "web":
				col = Color(0.85, 0.85, 0.8)
			elif kind == "bola":
				col = Color(0.5, 0.4, 0.3)
			m2.albedo_color = col
			m2.emission_enabled = kind == "bolt"
			m2.emission = col
			m2.emission_energy_multiplier = 3.0
			sm2.material = m2
			mi.mesh = sm2
			if kind == "bolt":
				Fx.glow_light(self, col, 5.0, 2.0)
	var holder := Node3D.new()
	holder.name = "Holder"
	add_child(holder)
	holder.add_child(mi)


func _physics_process(delta: float) -> void:
	life += delta
	if stuck:
		if life > 12.0:
			queue_free()
		return
	var from := global_position
	velocity.y -= gravity * delta
	var to := from + velocity * delta
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, to, 1 | 2 | 4 | 8 | 64)
	var sh = shooter.get_ref() if shooter else null
	if sh and sh is CollisionObject3D:
		q.exclude = [sh.get_rid()]
	var res := space.intersect_ray(q)
	if velocity.length() > 0.1:
		var holder := get_node_or_null("Holder")
		if holder:
			holder.look_at(global_position + velocity, Vector3.UP if absf(velocity.normalized().y) < 0.98 else Vector3.RIGHT)
	if res:
		_impact(res)
		return
	if from.y > 0.0 and to.y <= 0.0 and kind in ["bolt", "bomb"]:
		Fx.burst(to, Color(0.6, 0.75, 0.9), self, 8, 0.1, 2.0)
	global_position = to
	travelled += velocity.length() * delta
	if travelled > max_dist or life > 8.0:
		queue_free()


func _impact(res: Dictionary) -> void:
	var col: Node = res["collider"]
	var target: Node = col
	while target and not target.has_node("Combatant") and target.get_parent() and target != get_tree().root:
		target = target.get_parent()
		if target is Window:
			target = null
			break
	var sh = shooter.get_ref() if shooter else null
	if hit.has("aoe"):
		_explode(res["position"])
	elif target and target.has_node("Combatant") and sh and is_instance_valid(sh):
		var c: Combatant = target.get_node("Combatant")
		if AbilityRunner.is_hostile(team, c.team, sh, target) or hit.get("force", false):
			var h := hit.duplicate()
			if hit.get("headshot_bonus", 0.0) > 0.0 and target.has_method("is_headshot") and target.is_headshot(res["position"]):
				h["amount"] = float(h["amount"]) * (1.0 + float(hit["headshot_bonus"]))
				Fx.float_text(target, "Kopftreffer!", Color(1, 0.9, 0.3))
			AbilityRunner.apply_hit(sh, target, h)
			if hit.has("entangle"):
				c.apply_status("entangled", float(hit["entangle"]), sh)
			if hit.has("chain"):
				_chain(target, int(hit["chain"]), sh)
	else:
		Fx.burst(res["position"], Color(0.55, 0.5, 0.42), self, 6, 0.06, 2.0, 0.4)
	if on_impact.is_valid():
		on_impact.call(res)
	if kind in ["arrow", "javelin"] and not (target and target.has_node("Combatant")):
		stuck = true
		global_position = res["position"]
		return
	queue_free()


func _explode(at: Vector3) -> void:
	var sh = shooter.get_ref() if shooter else null
	Fx.burst(at, Fx.element_color(hit.get("elements", [])), self, 40, 0.3, 6.0, 0.8)
	Audio.play_at("explosion", at)
	if not sh or not is_instance_valid(sh):
		return
	for n in get_tree().get_nodes_in_group("combat_actors"):
		if n.global_position.distance_to(at) <= float(hit["aoe"]) and AbilityRunner.is_hostile(team, n.combatant.team, sh, n):
			AbilityRunner.apply_hit(sh, n, hit)


func _chain(from_t: Node3D, n: int, sh: Node3D) -> void:
	var done := [from_t]
	var cur := from_t
	for i in n:
		var best: Node3D = null
		var bd := 12.0
		for t in get_tree().get_nodes_in_group("combat_actors"):
			if t in done or t.combatant.dead or not AbilityRunner.is_hostile(team, t.combatant.team, sh, t):
				continue
			var d := cur.global_position.distance_to(t.global_position)
			if d < bd:
				bd = d
				best = t
		if best == null:
			return
		var h := hit.duplicate()
		h["amount"] = float(h["amount"]) * 0.6
		AbilityRunner.apply_hit(sh, best, h)
		Fx.burst(best.global_position + Vector3.UP, Fx.element_color(hit.get("elements", [])), best, 12, 0.1, 2.0)
		done.append(best)
		cur = best
