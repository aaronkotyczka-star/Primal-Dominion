class_name NPC
extends CharacterBody3D
## Humanoid NPC: villagers/traders/quest givers (talk) and hostile goblins (combat AI).

var npc_id := ""
var faction := ""
var display_name := ""
var visual: CreatureVisual
var combatant: Combatant
var ability_cd := {}
var home := Vector3.ZERO
var hostile_npc := false
var target: Node3D = null
var level := 5
var atk := 12.0
var wander_to := Vector3.INF
var state_t := 0.0
var attack_t := 0.0
var talk_cd := 0.0
var quest_tag := ""
var boss_id := ""
var weapon_kind := "spear"
var stamina := 100.0
var rng := RandomNumberGenerator.new()
var flee_from_demon := false
var label: Label3D


func setup(id: String, def: Dictionary, pos: Vector3, hostile: bool = false) -> void:
	npc_id = id
	rng.randomize()
	faction = def.get("faction", "")
	display_name = def.get("name", id)
	hostile_npc = hostile or def.get("hostile", false)
	home = pos
	add_to_group("npcs")
	add_to_group("combat_actors")
	if not hostile_npc:
		add_to_group("interactables")
	collision_layer = 2
	collision_mask = 1 | 4 | 8 | 64
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	var rig: String = def.get("rig", "human_m")
	var h := 1.8 if rig.begins_with("human") else (1.25 if rig == "goblin" else 2.3)
	var sc := float(def.get("boss_scale", 1.0))
	cap.radius = 0.3 * sc
	cap.height = h * sc
	cs.shape = cap
	cs.position = Vector3(0, h * sc * 0.5, 0)
	add_child(cs)
	visual = CreatureVisual.new()
	add_child(visual)
	var cols: Dictionary = def.get("colors", {}).duplicate()
	if not cols.has("color_main"):
		cols["color_main"] = [0.62, 0.48, 0.38]
	if not cols.has("color_belly"):
		cols["color_belly"] = cols["color_main"]
	if not cols.has("eye_color"):
		cols["eye_color"] = [0.9, 0.75, 0.2] if rig == "goblin" else [0.12, 0.09, 0.07]
	visual.setup({"rig": rig, "scale": sc, "parts": def.get("parts", []), "colors": cols, "pattern_type": 0 if rig != "goblin" else 4,
		"use_wrinkle": 1.0, "corruption": float(def.get("corruption", 0.0)), "glow": float(def.get("corruption", 0.0)), "glow_color": [1.0, 0.25, 0.08],
		"tex_scale": 6.0, "bump_height": 0.002})
	visual.animator.run_speed = 5.0
	weapon_kind = def.get("weapon", "spear" if hostile_npc else "")
	if weapon_kind != "":
		visual.set_gear("hand_R", GearFactory.make_weapon({"id": {"spear": "spear_stone", "club": "club_wood", "axe": "axe_stone", "staff": "staff_wood"}.get(weapon_kind, "spear_stone"), "n": 1}))
	combatant = Combatant.new()
	combatant.name = "Combatant"
	add_child(combatant)
	level = int(def.get("level", 6))
	var hp := float(def.get("hp", 120.0 + level * 15.0))
	combatant.setup(self, hp * sc, 6.0 + level, "hostile" if hostile_npc else "neutral")
	if faction == "daemonengoblins":
		combatant.team = "demon"
		combatant.demonic = true
	atk = float(def.get("atk", 8.0 + level * 1.5))
	combatant.died.connect(_on_died)
	combatant.damaged.connect(_on_damaged)
	global_position = pos
	if not hostile_npc:
		label = Label3D.new()
		label.text = "%s\n%s" % [display_name, def.get("role", "")]
		label.font_size = 36
		label.outline_size = 8
		label.pixel_size = 0.004
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.position = Vector3(0, h * sc + 0.45, 0)
		label.modulate = Color(1, 0.95, 0.8)
		label.visibility_range_end = 18.0
		add_child(label)


func get_forward() -> Vector3:
	return -global_transform.basis.z


func get_body_radius() -> float:
	return 0.4


func get_body_height() -> float:
	return 1.6


func get_aim_point() -> Vector3:
	return global_position + Vector3(0, 1.1, 0)


func get_reach() -> float:
	return 2.2


func get_attack_value() -> float:
	return atk * combatant.dmg_mult()


func spend_stamina(n: float) -> bool:
	return true


func play_action(anim: String, dur: float) -> void:
	visual.animator.play(anim, dur)


func apply_knockback(v: Vector3) -> void:
	velocity += v * 0.5


func is_wild() -> bool:
	return false


func get_prompt(_p: Node) -> String:
	if combatant.dead:
		return ""
	var att := Factions.attitude(faction)
	if Factions.npc_reacts_to_demon(faction) in ["hostile", "flee"]:
		return "%s weicht vor dir zurück." % display_name
	if att == "hostile":
		return "%s will nicht mit dir reden." % display_name
	return "E: Mit %s sprechen" % display_name


func can_interact(_p: Node) -> bool:
	return not combatant.dead and Factions.attitude(faction) != "hostile" and not (Factions.npc_reacts_to_demon(faction) in ["hostile", "flee"])


func interact(p: Node) -> void:
	var ui := get_tree().get_first_node_in_group("ui")
	if ui:
		ui.open_dialogue(npc_id)
	EventBus.dialogue_started.emit(npc_id)


func interact_radius() -> float:
	return 3.0


func _physics_process(delta: float) -> void:
	combatant.process_effects(delta)
	for k in ability_cd.keys():
		ability_cd[k] = float(ability_cd[k]) - delta
	if combatant.dead:
		if not is_on_floor():
			velocity.y -= 18.0 * delta
			move_and_slide()
		return
	var p := get_tree().get_first_node_in_group("player") as Node3D
	if p == null:
		return
	var dist := global_position.distance_to(p.global_position)
	if dist > 160.0:
		return
	state_t -= delta
	attack_t -= delta
	var mv := Vector3.ZERO
	var run := false
	var demon_react := Factions.npc_reacts_to_demon(faction)
	var aggressive := hostile_npc or Factions.attitude(faction) == "hostile" or demon_react == "hostile"
	if aggressive and combatant.team == "neutral":
		combatant.team = "hostile"
	if aggressive and (target == null or not is_instance_valid(target) or target.combatant.dead):
		if dist < 28.0 and not (faction == "daemonengoblins" and p.is_demon_form()):
			target = p
		else:
			for c in get_tree().get_nodes_in_group("companions"):
				if c.global_position.distance_to(global_position) < 20.0:
					target = c
					break
	if demon_react == "flee" and dist < 25.0:
		mv = (global_position - p.global_position)
		mv.y = 0
		run = true
	elif aggressive and target and is_instance_valid(target) and not target.combatant.dead:
		var to := target.global_position - global_position
		to.y = 0
		var d := to.length()
		if d > 2.0:
			mv = to.normalized()
			run = true
		elif attack_t <= 0.0 and not combatant.is_stunned():
			attack_t = 1.3 + rng.randf() * 0.6
			play_action(["thrust", "slash", "overhead"][rng.randi() % 3], 0.8)
			var hit := {"amount": get_attack_value() * rng.randf_range(0.85, 1.15), "melee": true, "elements": ["shadow"] if combatant.demonic and rng.randf() < 0.3 else []}
			get_tree().create_timer(0.4, false).timeout.connect(func():
				if is_instance_valid(self) and is_instance_valid(target) and not combatant.dead and global_position.distance_to(target.global_position) < 3.2:
					AbilityRunner.apply_hit(self, target, hit))
		_face_dir(to)
		if global_position.distance_to(home) > 60.0:
			target = null
	else:
		if not hostile_npc and dist < 6.0:
			var to2 := p.global_position - global_position
			to2.y = 0
			_face_dir(to2)
		elif state_t <= 0.0:
			state_t = rng.randf_range(4, 10)
			if rng.randf() < 0.5:
				var a := rng.randf() * TAU
				wander_to = home + Vector3(cos(a), 0, sin(a)) * rng.randf_range(2, 9)
			else:
				wander_to = Vector3.INF
		if wander_to != Vector3.INF and dist >= 6.0:
			var to3 := wander_to - global_position
			to3.y = 0
			if to3.length() > 0.8:
				mv = to3.normalized() * 0.5
	if combatant.is_stunned() or combatant.is_rooted():
		mv = Vector3.ZERO
	var speed := (5.0 if run else 1.6) * combatant.speed_mult()
	var hv := Vector3(velocity.x, 0, velocity.z).lerp(mv.normalized() * speed * minf(mv.length() * 2.0, 1.0), clampf(8.0 * delta, 0.0, 1.0))
	var vy := velocity.y - 18.0 * delta if not is_on_floor() else -0.5
	velocity = Vector3(hv.x, vy, hv.z)
	if mv.length() > 0.05:
		_face_dir(mv)
	move_and_slide()
	visual.animator.speed = hv.length()
	visual.animator.state = "move" if hv.length() > 0.2 else "idle"
	if global_position.y < WorldData.height_at(global_position.x, global_position.z) - 2.0:
		global_position.y = WorldData.height_at(global_position.x, global_position.z) + 0.3


func _face_dir(d: Vector3) -> void:
	if d.length() > 0.05:
		rotation.y = lerp_angle(rotation.y, atan2(-d.x, -d.z), 0.15)


func _on_damaged(amount: float, hit: Dictionary) -> void:
	visual.flash_hurt()
	var src = hit.get("source")
	if src and is_instance_valid(src) and src.is_in_group("player_side"):
		target = src
		if not hostile_npc and faction != "":
			if talk_cd <= 0.0:
				GameState.change_rep(faction, -10, "Angriff")
				talk_cd = 5.0
			hostile_npc = GameState.rep(faction) < -40
			if hostile_npc:
				combatant.team = "hostile"
				remove_from_group("interactables")


func _on_died(killer: Node) -> void:
	visual.animator.state = "dead"
	collision_layer = 0
	remove_from_group("combat_actors")
	remove_from_group("interactables")
	if label:
		label.queue_free()
	var by_player: bool = killer != null and is_instance_valid(killer) and (killer.is_in_group("player") or killer.is_in_group("player_side"))
	if by_player:
		GameState.add_xp(30 + level * 8, "kill")
		if faction != "" and faction != "daemonengoblins":
			GameState.change_rep(faction, -15, "Stammesmitglied getötet")
	EventBus.creature_killed.emit(npc_id, by_player, global_position, {"tag": quest_tag if quest_tag != "" else npc_id, "boss": boss_id})
	# drops
	var world := get_tree().get_first_node_in_group("world")
	if world:
		var loot := [["amber_coin", rng.randi_range(2, 8)]]
		if faction == "daemonengoblins":
			loot.append(["demon_essence", rng.randi_range(1, 2)])
			if rng.randf() < 0.3:
				loot.append(["rift_shard", 1])
		if npc_id == "vashrak":
			loot.append(["demon_heart", 1])
			loot.append(["ancient_tablet", 1])
		world.drop_loot(global_position, loot)
	get_tree().create_timer(60.0).timeout.connect(queue_free)
