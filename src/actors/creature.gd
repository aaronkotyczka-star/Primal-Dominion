class_name Creature
extends CharacterBody3D
## Any creature (wild or tamed). Movement (ground/swim/fly), combat hooks, taming state.
## Brain: CreatureAI (wild/companion) or a controller (rider / direct control) writes `intent`.

signal tamed_signal(uid: int)

const WATER := 0.0

var rec: Dictionary = {} # creature record (tamed: same dict as in GameState)
var uid := 0
var wild := true
var species_id := ""
var sp: Dictionary = {}
var stats: Dictionary = {}
var visual: CreatureVisual
var combatant: Combatant
var ai: CreatureAI
var meta: Dictionary = {}
var scale_f := 1.0
var body_len := 2.0
var body_h := 1.0
var hip_h := 1.0
var mount_type := "ground" # ground, fly, swim, amphibious
var mode := "ground"
var aquatic := false
var can_fly := false
var can_swim := true
var glider := false
var stamina := 100.0
var ability_cd := {}
var intent := {"move": Vector3.ZERO, "run": false, "sprint": false, "jump": false, "ascend": 0.0, "look": Vector3.ZERO}
var rider: Node3D = null
var direct_controller: Node3D = null
var knock := Vector3.ZERO
var dash_vel := Vector3.ZERO
var dash_t := 0.0
var corpse_t := -1.0
var looted := false
var lod_far := false
var _lod_timer := 0.0
var _foot_t := 0.0
var _idle_voice_t := 5.0
var level := 1
var is_boss := false
var boss_id := ""
var quest_tag := ""
# taming
var tame_progress := 0.0
var tame_needed := 100.0
var wariness := 0.0
var trust := 0.0
var feedings := 0
var feed_cd := 0.0
var distrust := 0.0
var in_need := "" # rescue scenario: "tar", "trap"
var nest_guard: Vector3 = Vector3.INF
var bind_cd := 0.0
var herd_id := 0
var revealed_t := 0.0
var alpha := false


func setup_wild(species: String, lvl: int, genes: Dictionary = {}, variant: Dictionary = {}) -> void:
	species_id = species
	sp = DB.species(species)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var g: Dictionary = genes if not genes.is_empty() else Genetics.random_genes(species, rng, variant)
	rec = Creatures.make_record(0, species, lvl, g, {"status": "wild"})
	rec["name"] = sp.get("name", species)
	wild = true
	alpha = "alpha" in g.get("mutations", [])
	_build()


func setup_tamed(record: Dictionary) -> void:
	rec = record
	uid = int(rec["uid"])
	wild = false
	species_id = rec["genes"].get("body_species", rec["species"]) if rec["species"] == "hybrid" else rec["species"]
	sp = Creatures.species_def(rec)
	_build()


func _build() -> void:
	add_to_group("creatures")
	add_to_group("combat_actors")
	add_to_group("interactables")
	level = int(rec["level"])
	stats = Creatures.stats(rec)
	var ph := Genetics.phenotype(rec["genes"])
	scale_f = float(ph["scale"]) * lerpf(0.35, 1.0, clampf(float(rec.get("growth", 1.0)), 0.0, 1.0))
	ph["scale"] = scale_f
	meta = RigLibrary.load_meta(ph["rig"])
	var aabb: Array = meta["aabb"]
	body_len = (aabb[1][2] - aabb[0][2]) * scale_f
	body_h = (aabb[1][1] - maxf(aabb[0][1], 0.0)) * scale_f
	hip_h = float(meta.get("hip_height", 1.0)) * scale_f
	mount_type = sp.get("mount", "ground") if sp.get("mount", "") != "" else ("swim" if sp.get("family", "") in ["marine", "fish"] else "ground")
	aquatic = sp.get("family", "") in ["marine", "fish"]
	can_fly = float(stats.get("fly", 0.0)) > 0.0
	can_swim = true
	for p in rec["genes"].get("parts", []):
		if "glider" in DB.part(p["id"]).get("traits", []):
			glider = true
	visual = CreatureVisual.new()
	visual.name = "Visual"
	add_child(visual)
	visual.setup(ph)
	if meta["family"] in ["marine", "fish", "serpent"]:
		var ymin: float = aabb[0][1]
		visual.position.y = -ymin * scale_f if meta["family"] == "serpent" else 0.0
	# apply body proportion genes as bone scales
	var body: Dictionary = ph.get("body", {})
	for bn_key in [["neck1", "neck"], ["tail1", "tail"], ["head", "head"]]:
		var bi := visual.skeleton.find_bone(bn_key[0])
		if bi >= 0 and body.has(bn_key[1]):
			visual.skeleton.set_bone_pose_scale(bi, Vector3.ONE * float(body[bn_key[1]]))
	visual.animator.run_speed = float(stats["spd"])
	# collision: horizontal capsule along body
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	var rad := clampf(minf(body_h * 0.42, body_len * 0.25), 0.15, 3.5)
	cap.radius = rad
	cap.height = maxf(body_len * 0.55, rad * 2.0 + 0.01)
	cs.shape = cap
	cs.rotation_degrees = Vector3(90, 0, 0)
	if aquatic:
		cs.position = Vector3(0, 0, 0)
	else:
		cs.position = Vector3(0, maxf(rad, hip_h * 0.9), 0)
	add_child(cs)
	collision_layer = 4
	collision_mask = 1 | 2 | 4 | 8 | 64
	floor_max_angle = deg_to_rad(50)
	floor_snap_length = 0.6
	safe_margin = 0.05
	combatant = Combatant.new()
	combatant.name = "Combatant"
	add_child(combatant)
	var team := "wild" if wild else "player"
	if sp.get("temper", "") in ["passive", "skittish", "curious"] and wild:
		team = "neutral"
	if sp.get("temper", "") == "demonic" and wild:
		team = "demon"
	combatant.setup(self, stats["hp"], stats["deff"], team)
	combatant.demonic = "demonic" in sp.get("passives", []) or "korrumpiert" in rec["genes"].get("mutations", [])
	combatant.affinity = rec["genes"].get("elements", {})
	if not wild and float(rec.get("hp", -1.0)) > 0.0:
		combatant.hp = minf(float(rec["hp"]), combatant.max_hp)
	var tm: Dictionary = sp.get("tame", {})
	combatant.max_torpor = stats["hp"] * 0.8 * float(tm.get("torpor", 300)) / 300.0 if tm.get("method", "") in ["knockout"] else 0.0
	if wild and tm.get("method", "") == "magic":
		combatant.max_torpor = stats["hp"] * 1.2
	combatant.died.connect(_on_died)
	combatant.knocked_out.connect(_on_knocked_out)
	combatant.woke_up.connect(_on_woke_up)
	combatant.damaged.connect(_on_damaged)
	stamina = stats["stam"]
	tame_needed = (40.0 + level * 6.0) * float(tm.get("difficulty", 1.0)) / float(GameState.rule("taming"))
	ai = CreatureAI.new()
	ai.name = "AI"
	add_child(ai)
	ai.setup(self)
	if not wild:
		add_to_group("player_side")
		add_to_group("companions")
		_apply_saddle()


func _apply_saddle() -> void:
	if visual == null:
		return
	if rec.get("saddle", false) and not visual.part_nodes.has("saddle"):
		var n := RigLibrary.attach_part(visual.inst, "saddle", "saddle", 0.55 if meta["family"] != "humanoid" else 0.4)
		if n:
			visual.part_nodes["saddle"] = n
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(0.32, 0.2, 0.12)
			mat.roughness = 0.7
			(n.get_node("Pivot/Mesh") as MeshInstance3D).material_override = mat


func refresh_from_record() -> void:
	stats = Creatures.stats(rec)
	combatant.max_hp = stats["hp"]
	combatant.armor = stats["deff"]
	_apply_saddle()


func get_prompt(p: Node) -> String:
	return Taming.prompt(self, p)


func can_interact(p: Node) -> bool:
	return Taming.can_interact(self, p)


func interact(p: Node) -> void:
	Taming.interact(self, p)


func interact_radius() -> float:
	return clampf(body_len * 0.55, 2.2, 8.0)


func is_wild() -> bool:
	return wild


func get_forward() -> Vector3:
	return -global_transform.basis.z


func get_body_radius() -> float:
	return clampf(body_len * 0.3, 0.3, 6.0)


func get_body_height() -> float:
	return body_h


func get_aim_point() -> Vector3:
	return global_position + Vector3(0, body_h * 0.6, 0)


func get_reach() -> float:
	return clampf(body_len * 0.45, 1.5, 9.0)


func get_attack_value() -> float:
	var a: float = stats["atk"]
	if not wild:
		a *= 1.0 + 0.08 * GameState.skill_rank("beast_tactics")
		if rider:
			a *= 1.0 + 0.15 * GameState.skill_rank("beast_mount")
	return a * float(GameState.rule("dmg_dealt") if not wild else 1.0)


func get_muzzle() -> Vector3:
	return visual.get_socket_global("mouth")


func spend_stamina(n: float) -> bool:
	if stamina < n * 0.5:
		return false
	stamina = maxf(0.0, stamina - n)
	return true


func play_action(anim: String, dur: float) -> void:
	visual.animator.play(anim, dur)
	if anim in ["bite", "gore", "claw"] and randf() < 0.4:
		Audio.play_creature(self, "attack", sp.get("sounds", "grunt"), body_h)
	if anim == "roar":
		Audio.play_creature(self, "roar", sp.get("sounds", "roar_mid"), body_h)


func apply_knockback(v: Vector3) -> void:
	var mass_f := clampf(body_h * body_len, 0.5, 60.0)
	knock += v * clampf(6.0 / mass_f, 0.05, 1.2)


func dash(dir: Vector3, dist: float, t: float) -> void:
	dash_vel = dir.normalized() * dist / t
	dash_t = t


func blink_to(p: Vector3, face: Node3D) -> void:
	Fx.burst(global_position + Vector3.UP, Color(0.4, 0.2, 0.6), self, 20, 0.2, 2.0)
	global_position = p
	_face(face.global_position)


func _face(p: Vector3) -> void:
	var to := p - global_position
	to.y = 0
	if to.length() > 0.01:
		rotation.y = atan2(-to.x, -to.z)


func reveal(from: Vector3, rng: float) -> void:
	if global_position.distance_to(from) < rng:
		revealed_t = 15.0


# ------------------------------------------------------------------ physics
func _physics_process(delta: float) -> void:
	if combatant == null:
		return
	combatant.process_effects(delta)
	feed_cd = maxf(0.0, feed_cd - delta)
	bind_cd = maxf(0.0, bind_cd - delta)
	revealed_t = maxf(0.0, revealed_t - delta)
	for k in ability_cd.keys():
		ability_cd[k] = float(ability_cd[k]) - delta
	if combatant.dead:
		_dead_process(delta)
		return
	# LOD: far creatures tick slowly
	var cam_pos: Vector3 = Audio.listener_pos
	var dist := global_position.distance_to(cam_pos)
	lod_far = dist > 110.0 and rider == null and direct_controller == null
	if lod_far:
		_lod_timer -= delta
		if _lod_timer > 0.0:
			return
		delta = 0.25
		_lod_timer = 0.25 + randf() * 0.1
	if rider == null and direct_controller == null:
		ai.think(delta)
	_move(delta)
	# stamina regen
	var regen := float(stats["stam"]) * 0.06 * float(Creatures.PERSONALITIES.get(rec.get("personality", ""), {}).get("stam_regen", 1.0))
	stamina = minf(float(stats["stam"]), stamina + regen * delta)
	if not wild and combatant.in_combat_t <= 0.0:
		combatant.heal(combatant.max_hp * 0.006 * delta)
	if not wild:
		rec["hp"] = combatant.hp
		rec["stamina"] = stamina
	_idle_voice_t -= delta
	if _idle_voice_t <= 0.0:
		_idle_voice_t = randf_range(12.0, 40.0)
		if dist < 60.0 and not combatant.unconscious:
			Audio.play_creature(self, "idle", sp.get("sounds", "grunt"), body_h * 0.7)


func _move(delta: float) -> void:
	var anim := visual.animator
	var stunned := combatant.is_stunned() or combatant.unconscious or in_need != ""
	var water_y := WATER
	var ground_y := WorldData.height_at(global_position.x, global_position.z)
	var depth := water_y - ground_y
	var submerge := water_y - global_position.y
	# mode selection
	if aquatic:
		mode = "swim"
	elif can_fly and (mode == "fly" or (intent.get("ascend", 0.0) > 0.0 and (rider != null or direct_controller != null or ai.wants_fly))):
		mode = "fly"
	elif depth > hip_h * 1.1 and submerge > hip_h * 0.6:
		mode = "swim"
	else:
		mode = "ground"
	if mode == "fly" and is_on_floor() and intent.get("ascend", 0.0) < 0.0:
		mode = "ground"
	anim.mode = mode if not (mode == "fly" and intent["move"].length() > 0.1 and intent.get("ascend", 0.0) <= 0.0 and velocity.y < -0.5) else "glide"
	var mv: Vector3 = intent["move"]
	mv.y = 0
	var want := 0.0
	if mv.length() > 0.05:
		want = float(stats["walk"]) * 1.4
		if intent.get("run", false):
			want = float(stats["spd"]) * 0.75
		if intent.get("sprint", false) and stamina > 5.0:
			want = float(stats["spd"])
			stamina -= delta * 8.0
	if mode == "swim":
		var sw := float(stats.get("swim", 0.0))
		want = (sw if sw > 0.0 else float(stats["walk"]) * 0.9) * (1.0 if intent.get("run", false) or intent.get("sprint", false) else 0.55) if mv.length() > 0.05 else 0.0
	if mode == "fly":
		want = float(stats["fly"]) * (1.0 if intent.get("sprint", false) else 0.65) if mv.length() > 0.05 else 0.0
	want *= combatant.speed_mult()
	if combatant.is_rooted() or stunned:
		want = 0.0
	if aquatic and depth < 1.6:
		# stranded on shore: crawl very slowly toward water
		want = minf(want, 1.0)
	var hv := Vector3(velocity.x, 0, velocity.z)
	var target_v := mv.normalized() * want
	var accel := 6.0 if mode != "fly" else 3.0
	hv = hv.lerp(target_v, clampf(accel * delta, 0.0, 1.0))
	# turning
	if mv.length() > 0.05 and not stunned:
		var desired_yaw := atan2(-mv.x, -mv.z)
		var turn_rate := clampf(5.0 / maxf(1.0, body_len * 0.35), 0.6, 6.0)
		var dy := wrapf(desired_yaw - rotation.y, -PI, PI)
		var step := clampf(dy, -turn_rate * delta, turn_rate * delta)
		rotation.y += step
		anim.turn = step / maxf(delta, 0.001)
		# big animals cannot strafe: move mostly along facing
		if body_len > 4.0 and mode == "ground":
			var f := get_forward()
			hv = f * hv.length() * maxf(0.0, f.dot(hv.normalized())) if hv.length() > 0.01 else hv
	else:
		anim.turn = 0.0
	var vy := velocity.y
	match mode:
		"ground":
			if is_on_floor():
				vy = -1.0
				if intent.get("jump", false) and not stunned and body_h < 3.0 and stamina > 10.0:
					vy = 5.0 + 2.0 / maxf(body_h, 0.5)
					stamina -= 10.0
			else:
				var g := 22.0 if not glider else 6.0
				vy -= g * delta
				if glider and vy < -3.0:
					vy = -3.0
		"swim":
			var target_y := water_y - hip_h * 0.6
			if aquatic:
				var floor_y := ground_y + body_h * 0.6
				var want_y: float = clampf(global_position.y + intent.get("ascend", 0.0) * 4.0, floor_y, water_y - 0.8)
				if rider == null and direct_controller == null:
					want_y = clampf(ai.swim_depth_target(), floor_y, water_y - 0.8)
				target_y = want_y
			vy = lerpf(vy, (target_y - global_position.y) * 2.0, clampf(4.0 * delta, 0.0, 1.0))
			if not aquatic and intent.get("ascend", 0.0) < 0.0 and float(sp.get("stats", {}).get("swim", 0.0)) > 0.0:
				vy = -2.5
		"fly":
			var asc := float(intent.get("ascend", 0.0))
			vy = lerpf(vy, asc * 8.0 - (1.5 if asc == 0.0 and mv.length() < 0.05 else 0.0), clampf(3.0 * delta, 0.0, 1.0))
			if stamina <= 1.0:
				vy = minf(vy, -4.0)
			stamina -= delta * 1.5
			if global_position.y > 420.0:
				vy = minf(vy, 0.0)
	if dash_t > 0.0:
		dash_t -= delta
		hv = dash_vel
	knock = knock.lerp(Vector3.ZERO, clampf(6.0 * delta, 0.0, 1.0))
	velocity = Vector3(hv.x + knock.x, vy, hv.z + knock.z)
	if lod_far and mode == "ground":
		global_position += Vector3(velocity.x, 0, velocity.z) * delta
		global_position.y = ground_y
		velocity.y = 0
	else:
		move_and_slide()
	if mode == "ground" and is_on_floor():
		# align body pitch to terrain slope (visual only)
		var n := WorldData.normal_at(global_position.x, global_position.z)
		var f := get_forward()
		var pitch := asin(clampf(n.dot(f), -0.6, 0.6))
		visual.rotation.x = lerpf(visual.rotation.x, pitch, clampf(4.0 * delta, 0.0, 1.0))
	else:
		visual.rotation.x = lerpf(visual.rotation.x, 0.0, clampf(3.0 * delta, 0.0, 1.0))
	# safety: never fall through terrain
	if global_position.y < ground_y - 2.0 and mode == "ground":
		global_position.y = ground_y + 0.2
		velocity.y = 0
	anim.speed = Vector3(velocity.x, 0, velocity.z).length()
	anim.vspeed = velocity.y
	anim.state = "stunned" if stunned else ("move" if anim.speed > 0.2 else "idle")
	anim.look_local = (global_transform.basis.inverse() * intent.get("look", Vector3.ZERO)) if intent.get("look", Vector3.ZERO) != Vector3.ZERO else Vector3.ZERO
	if combatant.unconscious or in_need != "":
		anim.state = "sleep"
	elif ai.sleeping:
		anim.state = "sleep"
	# footsteps
	if anim.speed > 0.5 and mode == "ground" and not lod_far:
		_foot_t -= delta * anim.speed / maxf(1.0, hip_h * 1.6)
		if _foot_t <= 0.0:
			_foot_t = 0.5
			if body_h > 2.2:
				Audio.play_at("footstep_heavy", global_position, -4.0 + body_h, clampf(1.2 / sqrt(body_h), 0.5, 1.2), clampf(body_h * 0.6, 1.0, 3.0))
				if body_h > 3.5:
					var cam := get_viewport().get_camera_3d()
					if cam and cam.has_meta("rig") and global_position.distance_to(cam.global_position) < 40.0:
						cam.get_meta("rig").shake(0.15 * body_h / maxf(8.0, global_position.distance_to(cam.global_position)))
			elif randf() < 0.5:
				Audio.play_at("footstep", global_position, -14.0, 1.2)


# ------------------------------------------------------------------ death & loot
func _on_died(killer: Node) -> void:
	visual.animator.state = "dead"
	Audio.play_creature(self, "death", sp.get("sounds", "grunt"), body_h)
	collision_layer = 0
	corpse_t = 180.0
	var by_player: bool = killer != null and is_instance_valid(killer) and (killer.is_in_group("player") or killer.is_in_group("player_side"))
	remove_from_group("combat_actors")
	if wild:
		GameState.state["stats"]["kills"] += 1 if by_player else 0
		GameState.lexicon_mark(species_id, "killed")
		var xp := float(sp.get("xp", 20)) * (1.0 + level * 0.08)
		if is_boss:
			xp *= 4.0
		if by_player:
			GameState.add_xp(xp, "kill")
			for c in get_tree().get_nodes_in_group("companions"):
				if c.global_position.distance_to(global_position) < 60.0:
					Creatures.add_xp(c.rec, xp * 0.6)
					if c.rec.get("likes", []).has("kampf"):
						Creatures.add_bond(c.rec, 0.5)
			EventBus.creature_killed.emit(species_id, true, global_position, {"tag": quest_tag, "boss": boss_id, "level": level})
		else:
			EventBus.creature_killed.emit(species_id, false, global_position, {"tag": quest_tag})
	else:
		GameState.kill_creature(uid, "Im Kampf gefallen" if killer else "Gestorben")
		EventBus.notify.emit("%s ist gefallen." % rec["name"], "danger")
		if rider and rider.has_method("dismount"):
			rider.dismount()


func _dead_process(delta: float) -> void:
	corpse_t -= delta
	if not is_on_floor() and mode != "swim":
		velocity.y -= 20.0 * delta
		velocity.x *= 0.9
		velocity.z *= 0.9
		move_and_slide()
	if corpse_t <= 0.0:
		queue_free()


func loot_corpse(player: Node) -> Array:
	## returns list of [item, n]
	if looted:
		return []
	looted = true
	var out := []
	var mult := 1.0 + 0.2 * GameState.skill_rank("hunt_skinning")
	for l in sp.get("loot", []):
		var n := int(round(randf_range(l[1], l[2]) * mult * (1.0 + level * 0.01)))
		if n > 0:
			out.append([l[0], n])
	if species_id == "hellhound" and randf() < (0.35 if alpha else 0.08):
		out.append(["demon_heart", 1])
	if alpha:
		out.append(["rare_flower" if sp.get("diet", "") == "herbivore" else "raw_prime_meat", 2])
	var els: Dictionary = rec["genes"].get("elements", {})
	for e in els:
		if randf() < 0.35 + float(els[e]) * 0.4:
			out.append(["essence_" + e, 1])
	if combatant.demonic:
		if randf() < (0.15 if not is_boss else 1.0):
			out.append(["demon_heart", 1])
		if sp.has("monster") or sp.get("temper", "") == "demonic":
			var ess := "essence_" + species_id
			if not DB.item(ess).is_empty():
				out.append([ess, 1])
	if is_boss and DB.get_entry("bosses", boss_id).has("loot"):
		for l in DB.get_entry("bosses", boss_id)["loot"]:
			out.append(l)
	GameState.lexicon_mark(species_id, "investigated")
	corpse_t = minf(corpse_t, 20.0)
	return out


# ------------------------------------------------------------------ taming hooks
func _on_knocked_out() -> void:
	ai.on_knocked_out()
	if wild:
		EventBus.notify.emit("%s ist bewusstlos! Füttere es (E), um es zu zähmen." % sp.get("name", species_id), "good")


func _on_woke_up() -> void:
	ai.on_woke_up()
	if wild and tame_progress > 0.0:
		EventBus.notify.emit("%s ist erwacht – Zähmung gescheitert! Es ist wütend." % sp.get("name", species_id), "danger")
		tame_progress *= 0.3
		distrust += 25.0
		combatant.add_buff("wut", {"dmg": 1.25, "speed": 1.15, "dur": 30.0})


func _on_damaged(amount: float, hit: Dictionary) -> void:
	visual.flash_hurt()
	if amount > combatant.max_hp * 0.04 and randf() < 0.5:
		visual.animator.play("hurt", 0.4)
		Audio.play_creature(self, "hurt", sp.get("sounds", "grunt"), body_h)
	var src = hit.get("source")
	if src and is_instance_valid(src):
		ai.on_attacked(src, amount)
	if wild and trust > 0.0:
		trust = maxf(0.0, trust - 40.0)
		wariness = 100.0


func on_hit_by(_attacker: Node, _dealt: float) -> void:
	pass


func tame_info() -> Dictionary:
	return {"method": sp.get("tame", {}).get("method", ""), "progress": tame_progress, "needed": tame_needed,
		"torpor": combatant.torpor, "max_torpor": combatant.max_torpor, "trust": trust, "wariness": wariness,
		"feedings": feedings, "need_feedings": int(sp.get("tame", {}).get("feedings", 3))}


func food_value(item_id: String) -> float:
	var foods: Array = sp.get("food", [])
	var it := DB.item(item_id)
	if item_id == "kibble":
		return 3.0
	var i := foods.find(item_id)
	if i == 0:
		return 1.6
	if i > 0:
		return 1.0
	if it.get("cat", "") == "food":
		var diet: String = sp.get("diet", "carnivore")
		var meaty: bool = item_id.contains("meat") or item_id.contains("fish") or item_id == "jerky"
		if (diet in ["carnivore", "piscivore"] and meaty) or (diet == "herbivore" and not meaty) or diet == "omnivore":
			return 0.4
	return 0.0


func become_tamed(method: String, bond: float) -> int:
	var opts := {"name": Genetics.random_name(RandomNumberGenerator.new()), "method": method, "bond": bond}
	var new_uid := GameState.create_creature(species_id, level, {"genes": rec["genes"], "name": opts["name"], "method": method, "bond": bond})
	var r := GameState.creature(new_uid)
	r["hp"] = combatant.hp
	var target := "party" if GameState.state["party"].size() < GameState.party_limit() else ("crystal" if GameState.crystal_used() + Creatures.size_units(r) <= GameState.crystal_capacity() and Inventory.count(GameState.player()["inventory"], "soul_crystal") > 0 else "base")
	if target == "base" and not GameState.has_base():
		target = "party"
	GameState.set_creature_status(new_uid, target)
	EventBus.creature_tamed.emit(new_uid)
	EventBus.notify.emit("%s gezähmt! Name: %s (%s)" % [sp.get("name", species_id), r["name"], Creatures.status_label(target)], "good")
	Audio.play_ui("ui_quest")
	GameState.add_xp(float(sp.get("xp", 20)) * 1.5, "tame")
	# replace wild node by companion node
	var world := get_tree().get_first_node_in_group("world")
	if world and world.has_method("spawn_companion") and target == "party":
		world.spawn_companion(new_uid, global_position, rotation.y)
	queue_free()
	return new_uid
