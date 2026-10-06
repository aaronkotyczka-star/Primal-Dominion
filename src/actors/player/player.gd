class_name Player
extends CharacterBody3D
## The player character. Reads intents from PlayerInput; state lives in GameState.player.

const WALK := 2.6
const RUN := 5.4
const SPRINT := 8.2
const CROUCH := 2.0
const SWIM := 2.8

var input: PlayerInput
var rig: CameraRig
var visual: CreatureVisual
var combatant: Combatant
var combat: PlayerCombat
var ability_cd := {}
var stamina := 100.0
var max_stamina := 100.0
var breath := 30.0
var max_breath := 30.0
var crouching := false
var swimming := false
var underwater := false
var climbing := false
var dodge_t := 0.0
var dodge_dir := Vector3.ZERO
var knock := Vector3.ZERO
var dash_vel := Vector3.ZERO
var dash_t := 0.0
var mount: Creature = null
var controlled: Creature = null
var interact_target: Node = null
var interact_prompt := ""
var _scan_t := 0.0
var _hunger_warn := 100.0
var _foot_t := 0.0
var _temp_t := 0.0
var demon_form := false
var dead := false
var ui_blocking := false
var _fall_speed := 0.0
var _regen_block := 0.0
var _env_hint_t := 0.0
var last_safe_pos := Vector3.ZERO
var wheel_open := false


func _ready() -> void:
	add_to_group("player")
	add_to_group("player_side")
	add_to_group("combat_actors")
	collision_layer = 2
	collision_mask = 1 | 4 | 8 | 64
	floor_max_angle = deg_to_rad(46)
	floor_snap_length = 0.4
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.32
	cap.height = 1.75
	cs.shape = cap
	cs.position = Vector3(0, 0.875, 0)
	cs.name = "Shape"
	add_child(cs)
	input = PlayerInput.new()
	input.name = "Input"
	add_child(input)
	combatant = Combatant.new()
	combatant.name = "Combatant"
	add_child(combatant)
	combatant.setup(self, 100.0, 0.0, "player")
	combatant.died.connect(_on_died)
	combatant.damaged.connect(_on_damaged)
	rig = CameraRig.new()
	rig.name = "CameraRig"
	add_child(rig)
	rig.top_level = true
	combat = PlayerCombat.new()
	combat.name = "Combat"
	add_child(combat)
	combat.setup(self)
	build_visual()
	recalc_stats()
	var p := GameState.player()
	combatant.hp = clampf(float(p["hp"]), 1.0, combatant.max_hp)
	stamina = float(p["stamina"])
	rig.yaw = float(p.get("yaw", 0.0))
	rig.first_person = p.get("camera_fp", false)
	EventBus.equipment_changed.connect(_on_equipment_changed)


func build_visual() -> void:
	if visual:
		visual.queue_free()
	visual = CreatureVisual.new()
	visual.name = "Visual"
	add_child(visual)
	var p := GameState.player()
	var ph: Dictionary
	if demon_form:
		var form: Dictionary = p["demon"]["forms"][int(p["demon"].get("active_form", 0))]
		var parts := []
		if form.get("horns", "") != "":
			parts.append({"id": form["horns"], "socket": "head_top", "size": 0.55})
		if form.get("tail", false):
			parts.append({"id": "tail_demon", "socket": "tail_tip", "size": 0.9})
		if form.get("wings", false):
			parts.append({"id": "wing_membrane", "socket": "shoulder_L", "size": 0.7, "mirror": true, "align": "body"})
			parts.append({"id": "wing_membrane", "socket": "shoulder_R", "size": 0.7, "align": "body"})
		if form.get("spikes", false):
			parts.append({"id": "spikes_back", "socket": "back", "size": 0.5})
		ph = {"rig": "demon", "scale": 1.0, "parts": parts, "colors": {"color_main": form.get("skin", [0.25, 0.08, 0.07]), "color_belly": form.get("skin", [0.25, 0.08, 0.07]),
			"top_color": form.get("skin", [0.25, 0.08, 0.07]), "bottom_color": [0.1, 0.05, 0.05], "boots_color": [0.08, 0.05, 0.05]},
			"pattern_type": 4, "corruption": 0.8, "glow": 1.0, "glow_color": form.get("glow", [1, 0.3, 0.05]), "use_wrinkle": 1.0}
	else:
		var cols := GearFactory.armor_colors(p["equipment"])
		cols["color_main"] = [0.62, 0.48, 0.38]
		cols["color_belly"] = [0.65, 0.52, 0.42]
		if not cols.has("hair_color"):
			cols["hair_color"] = [0.16, 0.11, 0.07]
		cols["boots_color"] = [0.2, 0.14, 0.09]
		cols["eye_color"] = [0.12, 0.09, 0.07]
		ph = {"rig": p.get("body", "human_m"), "scale": 1.0, "parts": [], "colors": cols, "pattern_type": 0, "use_wrinkle": 1.0, "tex_scale": 6.0, "bump_height": 0.002}
	visual.setup(ph)
	visual.animator.run_speed = RUN
	visual.set_shadow_only(rig.first_person if rig else false)
	combat.refresh_gear()


func recalc_stats() -> void:
	var p := GameState.player()
	var lvl := int(p["level"])
	var hp := 100.0 + (lvl - 1) * 8.0 + 15.0 * GameState.skill_rank("def_vitality")
	var arm := 0.0
	for slot in ["head", "chest", "legs", "offhand", "trinket"]:
		var id: String = p["equipment"].get(slot, "")
		if id != "":
			arm += float(DB.item(id).get("stats", {}).get("armor", 0.0))
	arm *= 1.0 + 0.06 * GameState.skill_rank("def_armor")
	if demon_form:
		var dl := int(p["demon"].get("level", 1))
		hp *= 1.5 + 0.05 * dl
		arm = arm * 0.5 + 20.0 + dl * 2.0
		arm *= 1.0 + 0.1 * int(p["demon"]["skills"].get("d_hide", 0))
	combatant.max_hp = hp
	combatant.hp = minf(combatant.hp, hp)
	combatant.armor = arm
	max_stamina = 100.0 + (lvl - 1) * 4.0
	max_breath = 30.0 * (1.0 + 0.5 * GameState.skill_rank("exp_swim"))
	combatant.dmg_taken_mult = float(GameState.rule("dmg_taken"))
	if demon_form:
		floor_max_angle = deg_to_rad(55)


func _on_equipment_changed() -> void:
	recalc_stats()
	if not demon_form:
		var cols := GearFactory.armor_colors(GameState.player()["equipment"])
		for k in cols:
			visual.pheno["colors"][k] = cols[k]
		visual.apply_colors()
	combat.refresh_gear()


# ------------------------------------------------------------------ queries used by AI/combat
func get_forward() -> Vector3:
	return -global_transform.basis.z


func get_body_radius() -> float:
	return 0.4


func get_body_height() -> float:
	return 1.8 if not demon_form else 2.3


func get_aim_point() -> Vector3:
	return global_position + Vector3(0, 1.3, 0)


func get_reach() -> float:
	return combat.reach()


func get_attack_value() -> float:
	return combat.attack_value()


func get_muzzle() -> Vector3:
	return global_position + Vector3(0, 1.45, 0) + get_forward() * 0.5


func get_mount() -> Creature:
	return mount


func is_crouching() -> bool:
	return crouching and mount == null


func is_moving_fast() -> bool:
	return Vector3(velocity.x, 0, velocity.z).length() > RUN * 0.9 or (mount != null and mount.velocity.length() > 4.0)


func is_demon_form() -> bool:
	return demon_form


func has_buff(id: String) -> bool:
	return combatant.buffs.has(id)


func spend_stamina(n: float) -> bool:
	if stamina < n * 0.6:
		return false
	stamina = maxf(0.0, stamina - n)
	_regen_block = 0.8
	return true


func play_action(anim: String, dur: float) -> void:
	visual.animator.play(anim, dur)


func apply_knockback(v: Vector3) -> void:
	if mount:
		return
	knock += v * 0.6


func dash(dir: Vector3, dist: float, t: float) -> void:
	dash_vel = dir.normalized() * dist / t
	dash_t = t


func blink_to(p: Vector3, face: Node3D) -> void:
	Fx.burst(global_position + Vector3.UP, Color(0.4, 0.2, 0.6), self, 20, 0.2, 2.0)
	global_position = p
	var to := face.global_position - global_position
	rotation.y = atan2(-to.x, -to.z)


# ------------------------------------------------------------------ main loop
func _physics_process(delta: float) -> void:
	input.poll()
	var it: Dictionary = input.intent
	if not ui_blocking and not wheel_open:
		rig.rotate_input(input.consume_look())
	combatant.process_effects(delta)
	for k in ability_cd.keys():
		ability_cd[k] = float(ability_cd[k]) - delta
	if dead:
		rig.update_rig(delta, global_position, 1.0)
		return
	if not ui_blocking:
		_global_actions(it)
	if controlled:
		_drive_creature(controlled, it, delta, false)
		_update_camera(delta)
		_survival(delta)
		return
	if mount:
		_drive_creature(mount, it, delta, true)
		global_transform = _saddle_transform()
		velocity = Vector3.ZERO
		combat.process_combat(it, delta)
		_update_camera(delta)
		_survival(delta)
		_scan_interact(delta)
		return
	_move(it, delta)
	combat.process_combat(it, delta)
	_survival(delta)
	_scan_interact(delta)
	if it.get("interact_just", false) and not ui_blocking:
		if interact_target and is_instance_valid(interact_target):
			interact_target.interact(self)
		else:
			var world := get_tree().get_first_node_in_group("world")
			if world:
				world.hand_gather(self)
	_update_camera(delta)
	if is_on_floor() and not swimming:
		last_safe_pos = global_position


func _global_actions(it: Dictionary) -> void:
	if it.get("toggle_view_just", false):
		rig.first_person = not rig.first_person
		GameState.player()["camera_fp"] = rig.first_person
		visual.set_shadow_only(rig.first_person and mount == null and controlled == null)
	if it.get("transform_just", false):
		toggle_demon_form()
	if it.get("whistle_just", false):
		for c in get_tree().get_nodes_in_group("companions"):
			if c.rec.get("status", "") == "party":
				c.ai.set_command("follow")
		Audio.play_at("chirp", global_position, 4.0, 1.4)
		EventBus.notify.emit("Pfiff: Alle Gefährten folgen.", "info")
	if it.get("direct_control_just", false):
		toggle_direct_control()


func _move(it: Dictionary, delta: float) -> void:
	var mv2: Vector2 = it["move"]
	var fwd := rig.forward_flat()
	var right := rig.right_flat()
	var dir := (right * mv2.x - fwd * mv2.y)
	if dir.length() > 1.0:
		dir = dir.normalized()
	var water_y := 0.0
	var feet := global_position.y
	underwater = rig.cam.global_position.y < water_y - 0.1
	swimming = feet < water_y - 1.25 and WorldData.height_at(global_position.x, global_position.z) < water_y - 1.3
	if it.get("crouch_just", false) and not swimming:
		crouching = not crouching
	if swimming:
		crouching = false
	var speed := RUN
	if crouching:
		speed = CROUCH
	elif it.get("sprint", false) and mv2.length() > 0.1 and stamina > 3.0:
		speed = SPRINT * (1.15 if demon_form else 1.0)
		stamina -= delta * 11.0 * (1.0 - 0.15 * GameState.skill_rank("exp_sprint"))
		_regen_block = 0.5
	elif mv2.length() < 0.5:
		speed = WALK
	if combat.aiming or combat.blocking:
		speed = minf(speed, WALK)
	var weight := Inventory.weight(GameState.player()["inventory"])
	var cap := carry_capacity()
	if weight > cap:
		speed *= 0.45
		if _env_hint_t <= 0.0:
			_env_hint_t = 20.0
			EventBus.notify.emit("Überladen! (%.0f / %.0f kg)" % [weight, cap], "warn")
	_env_hint_t -= delta
	speed *= combatant.speed_mult()
	if combatant.is_rooted() or combatant.is_stunned():
		speed = 0.0
	# dodge
	if it.get("dodge_just", false) and dodge_t <= 0.0 and not swimming and is_on_floor():
		var cost := 18.0 * (1.0 - 0.15 * GameState.skill_rank("exp_dodge"))
		if spend_stamina(cost):
			dodge_t = 0.5
			dodge_dir = dir if dir.length() > 0.1 else -fwd
			combatant.invulnerable = 0.32 + 0.05 * GameState.skill_rank("exp_dodge")
			visual.animator.play("dodge", 0.5)
	var hv := Vector3(velocity.x, 0, velocity.z)
	if dodge_t > 0.0:
		dodge_t -= delta
		hv = dodge_dir.normalized() * 8.5
	elif dash_t > 0.0:
		dash_t -= delta
		hv = dash_vel
	else:
		var target := dir * speed
		if swimming:
			target = dir * SWIM * (1.0 + 0.15 * GameState.skill_rank("exp_swim")) * (1.5 if it.get("sprint", false) and stamina > 3 else 1.0)
			if it.get("sprint", false):
				stamina -= delta * 6.0
		hv = hv.lerp(target, clampf((12.0 if is_on_floor() or swimming else 2.5) * delta, 0.0, 1.0))
	var vy := velocity.y
	climbing = false
	if swimming:
		var want := 0.0
		if it.get("jump", false):
			want = 2.5
		elif it.get("crouch", false):
			want = -2.5
		else:
			want = clampf((water_y - 1.05 - feet) * 2.0, -1.0, 1.5) if not underwater or breath > 3.0 else 1.5
			if underwater and rig.pitch < -0.3 and mv2.y < -0.1:
				want = rig.pitch * 3.0
		vy = lerpf(vy, want, clampf(4.0 * delta, 0.0, 1.0))
	else:
		if is_on_floor():
			if _fall_speed < -15.0:
				var dmg := (absf(_fall_speed) - 15.0) * 6.0
				if demon_form:
					dmg *= 0.3
				combatant.take_hit({"amount": dmg, "true_damage": true, "unavoidable": true})
				EventBus.notify.emit("Sturzschaden!", "danger")
			vy = -0.5
			if it.get("jump_just", false) and stamina > 8.0 and not combatant.is_rooted():
				vy = 5.2 if not demon_form else 6.5
				stamina -= 8.0
		else:
			var g := 18.0
			# demon wings / glide
			if demon_form and it.get("jump", false) and _demon_wings() > 0:
				if _demon_wings() >= 2 and stamina > 2.0:
					vy = lerpf(vy, 4.0, clampf(3.0 * delta, 0.0, 1.0))
					stamina -= delta * 6.0
					g = 0.0
				else:
					g = 4.0
					vy = maxf(vy, -2.5)
			vy -= g * delta
		# climbing (Erkundung: Kletterer Rang 2)
		if GameState.skill_rank("exp_climb") >= 2 and is_on_wall() and mv2.y < -0.3 and stamina > 2.0:
			climbing = true
			vy = 2.2
			stamina -= delta * 9.0
			_regen_block = 0.5
	_fall_speed = vy
	knock = knock.lerp(Vector3.ZERO, clampf(8.0 * delta, 0.0, 1.0))
	velocity = Vector3(hv.x + knock.x, vy, hv.z + knock.z)
	floor_max_angle = deg_to_rad(46 + 9 * mini(GameState.skill_rank("exp_climb"), 1) + (8 if demon_form else 0))
	move_and_slide()
	# face movement or aim direction
	var face_dir := Vector3.ZERO
	if combat.aiming or combat.blocking or rig.lock_target or rig.first_person or combat.attacking():
		face_dir = fwd
		if rig.lock_target and is_instance_valid(rig.lock_target):
			face_dir = (rig.lock_target.global_position - global_position)
			face_dir.y = 0
	elif hv.length() > 0.3:
		face_dir = hv
	if face_dir.length() > 0.01:
		var yaw := atan2(-face_dir.x, -face_dir.z)
		rotation.y = lerp_angle(rotation.y, yaw, clampf(12.0 * delta, 0.0, 1.0))
	var anim := visual.animator
	anim.speed = Vector3(velocity.x, 0, velocity.z).length()
	anim.mode = "swim" if swimming else "ground"
	anim.crouch = crouching
	anim.state = "move" if anim.speed > 0.2 else "idle"
	anim.aim_pitch = rig.pitch
	# footsteps
	if is_on_floor() and anim.speed > 0.5:
		_foot_t -= delta * anim.speed * 0.55
		if _foot_t <= 0.0:
			_foot_t = 1.0
			Audio.play_at("footstep", global_position, -10.0 if not crouching else -22.0)
	if global_position.y < WorldData.height_at(global_position.x, global_position.z) - 3.0:
		global_position.y = WorldData.height_at(global_position.x, global_position.z) + 0.5
		velocity.y = 0


func _demon_wings() -> int:
	var d: Dictionary = GameState.player()["demon"]
	var form: Dictionary = d["forms"][int(d.get("active_form", 0))]
	if not form.get("wings", false):
		return 0
	return maxi(1, int(d["skills"].get("d_wings", 0)))


func carry_capacity() -> float:
	return 60.0 + GameState.player()["level"] * 3.0 + (40.0 if demon_form else 0.0)


func _update_camera(delta: float) -> void:
	var follow: Node3D = self
	var h := 1.6
	rig.extra_len = 0.0
	if controlled:
		follow = controlled
		h = controlled.body_h * 0.9 + 0.4
		rig.extra_len = controlled.body_len * 0.7
	elif mount:
		follow = mount
		h = mount.body_h + 1.2
		rig.extra_len = mount.body_len * 0.55
	elif crouching:
		h = 1.0
	elif swimming:
		h = 1.2
	rig.fp_height = 1.65 if not demon_form else 2.1
	if (mount or controlled) and rig.first_person:
		rig.fp_height = h
	rig.update_rig(delta, follow.global_position, h)
	var sky := get_tree().get_first_node_in_group("sky_weather")
	if sky:
		sky.camera = rig.cam
		var uw := rig.cam.global_position.y < -0.05
		if uw != sky.underwater:
			sky.underwater = uw
			Audio.set_underwater(uw)


# ------------------------------------------------------------------ survival
func _survival(delta: float) -> void:
	var p := GameState.player()
	# stamina regen
	_regen_block -= delta
	if _regen_block <= 0.0:
		var mult := 2.0 if combatant.buffs.has("ausdauer") else 1.0
		stamina = minf(max_stamina, stamina + delta * 16.0 * mult)
	# hunger
	var hrate := 100.0 / (75.0 * 60.0) * float(GameState.rule("hunger")) * (1.0 - 0.15 * GameState.skill_rank("surv_hunger"))
	if combatant.buffs.has("satt"):
		hrate *= 0.5
	if demon_form:
		hrate *= 1.3
	p["hunger"] = maxf(0.0, float(p["hunger"]) - hrate * delta)
	var hg := float(p["hunger"])
	if hg < 25.0 and _hunger_warn >= 25.0:
		EventBus.notify.emit("Du bist hungrig. Iss bald etwas!", "warn")
	if hg < 10.0 and _hunger_warn >= 10.0:
		EventBus.notify.emit("Du verhungerst! Ohne Nahrung verlierst du Leben.", "danger")
	_hunger_warn = hg
	if hg <= 0.0 and GameState.rule("hunger_lethal"):
		combatant.take_hit({"amount": 1.5 * delta * 60.0 / 60.0 * 2.0, "true_damage": true, "unavoidable": true})
	# regeneration
	if combatant.in_combat_t <= 0.0 and hg > 20.0:
		var rr := 0.6 * (1.0 + 0.5 * GameState.skill_rank("surv_regen"))
		if combatant.buffs.has("ausgeruht"):
			rr *= 1.5
		combatant.heal(rr * delta)
	# breath
	if underwater and mount == null:
		breath -= delta
		if breath <= 0.0:
			breath = 0.0
			combatant.take_hit({"amount": 8.0 * delta, "true_damage": true, "unavoidable": true})
			if int(Time.get_ticks_msec() / 1000) % 3 == 0 and _temp_t <= 0.0:
				_temp_t = 3.0
				EventBus.notify.emit("Du ertrinkst! Tauche auf!", "danger")
	else:
		breath = minf(max_breath, breath + delta * 8.0)
	if mount and mount.mount_type == "swim" and "air_bubble" in mount.sp.get("passives", []):
		breath = max_breath
	# temperature (simple biome check)
	_temp_t -= delta
	var biome := WorldData.biome_at(global_position.x, global_position.z)
	var cold := 0.0
	for slot in ["head", "chest", "legs"]:
		var id: String = p["equipment"].get(slot, "")
		if id != "":
			cold += float(DB.item(id).get("stats", {}).get("cold", 0.0))
	cold *= 1.0 + 0.3 * GameState.skill_rank("surv_climate")
	var sky := get_tree().get_first_node_in_group("sky_weather")
	var night: bool = sky != null and sky.is_night()
	if biome == 7 and cold < (18.0 if night else 10.0) and not demon_form:
		combatant.take_hit({"amount": 0.8 * delta, "true_damage": true, "unavoidable": true})
		if _temp_t <= 0.0:
			_temp_t = 25.0
			EventBus.notify.emit("Eisige Kälte! Pelzkleidung oder ein Feuer hilft.", "warn")
	elif biome == 8 and global_position.y > 150.0 and not demon_form and _temp_t <= 0.0:
		_temp_t = 30.0
		EventBus.notify.emit("Gluthitze – meide den Krater, Lava ist tödlich.", "warn")
	if biome == 8 and global_position.distance_to(WorldData.poi_pos("vulkan_krater")) < 40.0 and global_position.y < WorldData.poi_pos("vulkan_krater").y + 3.0:
		combatant.take_hit({"amount": 40.0 * delta, "elements": ["fire"], "true_damage": true, "unavoidable": true})
	if biome == 10 and not demon_form and _temp_t <= 0.0 and p["equipment"].get("trinket", "") != "trinket_rift":
		_temp_t = 40.0
		EventBus.notify.emit("Die Verderbnis zehrt an dir (kein Rissamulett).", "warn")
	if biome == 10 and not demon_form and p["equipment"].get("trinket", "") != "trinket_rift":
		combatant.take_hit({"amount": 0.25 * delta, "true_damage": true, "unavoidable": true})
	p["hp"] = combatant.hp
	p["stamina"] = stamina
	p["pos"] = [global_position.x, global_position.y, global_position.z]
	p["yaw"] = rig.yaw


func eat(item_id: String) -> bool:
	var it := DB.item(item_id)
	var p := GameState.player()
	if it.has("food"):
		p["hunger"] = minf(100.0, float(p["hunger"]) + float(it["food"]))
		if randf() < float(it.get("sick", 0.0)):
			combatant.apply_status("poisoned", 6.0)
			EventBus.notify.emit("Roh gegessen – dir ist übel.", "warn")
	if it.has("heal"):
		combatant.heal(float(it["heal"]) * (1.0 + 0.2 * GameState.skill_rank("surv_alchemy")))
		combatant.statuses.erase("bleeding")
	if it.has("buff"):
		var b: String = it["buff"]
		combatant.add_buff(b, {"dur": 180.0 if b != "ausdauer" else 60.0, "dmg": 1.1 if b == "stark" else 1.0})
	if it.get("cure", "") == "poison":
		combatant.statuses.erase("poisoned")
	if it.has("research"):
		p["research_points"] = int(p["research_points"]) + int(it["research"])
		EventBus.notify.emit("+%d Forschungspunkte" % it["research"], "good")
	if it.get("respec", false):
		Skills.respec(true)
	Inventory.remove(p["inventory"], item_id, 1)
	Audio.play_at("eat", global_position)
	visual.animator.play("eat", 0.8)
	EventBus.inventory_changed.emit()
	return true


# ------------------------------------------------------------------ interaction
func _scan_interact(delta: float) -> void:
	_scan_t -= delta
	if _scan_t > 0.0:
		return
	_scan_t = 0.1
	var best: Node = null
	var best_score := 1e9
	var fwd := rig.forward_flat()
	var origin := global_position + Vector3.UP
	for n in get_tree().get_nodes_in_group("interactables"):
		if not is_instance_valid(n) or not n is Node3D:
			continue
		var r: float = n.interact_radius() if n.has_method("interact_radius") else 3.0
		var to: Vector3 = (n as Node3D).global_position - global_position
		var d := Vector3(to.x, 0, to.z).length()
		if d > r + 0.5 or absf(to.y) > maxf(4.0, r):
			continue
		var facing := fwd.dot(Vector3(to.x, 0, to.z).normalized()) if d > 0.3 else 1.0
		if facing < -0.2 and d > 1.5:
			continue
		var score := d / maxf(r, 0.5) - facing * 0.5
		if score < best_score and (not n.has_method("can_interact") or n.can_interact(self)):
			best_score = score
			best = n
	interact_target = best
	interact_prompt = best.get_prompt(self) if best and best.has_method("get_prompt") else ""


# ------------------------------------------------------------------ mounting / direct control
func mount_creature(c: Creature) -> void:
	var ok := Creatures.can_ride(c.rec)
	if not ok["ok"]:
		EventBus.notify.emit(ok["why"], "warn")
		return
	mount = c
	c.rider = self
	collision_layer = 0
	collision_mask = 0
	visual.animator.state = "sit"
	visual.animator.straddle = float(c.visual.meta.get("saddle_half_width", 0.0)) * float(c.visual.pheno.get("scale", 1.0))
	visual.set_shadow_only(false)
	if rig.first_person:
		visual.set_shadow_only(true)
	if c.rec.get("likes", []).has("reiten"):
		Creatures.add_bond(c.rec, 1.0)
	EventBus.notify.emit("Aufgestiegen: %s. (E: Absteigen)" % c.rec["name"], "info")


func dismount() -> void:
	if mount == null:
		return
	var c := mount
	mount = null
	c.rider = null
	visual.animator.straddle = 0.0
	c.intent["move"] = Vector3.ZERO
	collision_layer = 2
	collision_mask = 1 | 4 | 8 | 64
	visual.animator.state = "idle"
	var side := c.global_transform.basis.x * (c.body_len * 0.3 + 1.2)
	var p := c.global_position + side
	p.y = maxf(WorldData.height_at(p.x, p.z), c.global_position.y - 2.0) + 0.3
	if c.mode == "fly":
		p = c.global_position + Vector3(0, -c.body_h, 0)
	global_position = p
	rotation = Vector3(0, rotation.y, 0)


func _saddle_transform() -> Transform3D:
	var p := mount.visual.get_socket_global("saddle")
	var b := Basis(Vector3.UP, mount.rotation.y)
	# hips rest on top of the saddle (its thickness scales with the mount)
	var saddle_h := 0.05 * float(mount.visual.pheno.get("scale", 1.0)) + 0.04
	return Transform3D(b, p - Vector3(0, visual.meta.get("hip_height", 0.95) * 0.95 - saddle_h, 0))


func toggle_direct_control() -> void:
	if controlled:
		controlled.direct_controller = null
		controlled.intent["move"] = Vector3.ZERO
		controlled = null
		visual.set_shadow_only(rig.first_person)
		EventBus.notify.emit("Direkte Steuerung beendet.", "info")
		return
	if mount:
		EventBus.notify.emit("Steige zuerst ab.", "warn")
		return
	# pick: targeted companion (crosshair) or nearest companion
	var best: Creature = null
	var bd := 60.0
	var ray := rig.aim_ray(80.0, [get_rid()])
	if ray["hit"] and ray["hit"]["collider"] is Creature and not ray["hit"]["collider"].wild:
		best = ray["hit"]["collider"]
	else:
		for c in get_tree().get_nodes_in_group("companions"):
			var d := global_position.distance_to(c.global_position)
			if d < bd and c.rec.get("status", "") == "party":
				bd = d
				best = c
	if best == null:
		EventBus.notify.emit("Kein Gefährte in der Nähe für direkte Steuerung.", "warn")
		return
	controlled = best
	best.direct_controller = self
	velocity = Vector3.ZERO
	visual.animator.state = "idle"
	EventBus.notify.emit("Du steuerst %s direkt (X: zurück). Dein Körper bleibt ungeschützt!" % best.rec["name"], "info")


func _drive_creature(c: Creature, it: Dictionary, delta: float, riding: bool) -> void:
	if not is_instance_valid(c) or c.combatant.dead:
		if riding:
			mount = null
			collision_layer = 2
			collision_mask = 1 | 4 | 8 | 64
		else:
			controlled = null
		return
	var mv2: Vector2 = it["move"]
	var dir := rig.right_flat() * mv2.x - rig.forward_flat() * mv2.y
	c.intent["move"] = dir
	c.intent["run"] = true
	c.intent["sprint"] = it.get("sprint", false)
	c.intent["jump"] = it.get("jump_just", false)
	c.intent["ascend"] = 1.0 if it.get("jump", false) else (-1.0 if it.get("crouch", false) else 0.0)
	c.intent["look"] = rig.aim_ray(60.0)["dir"]
	if riding and it.get("interact_just", false):
		dismount()
		return
	# creature attacks: LMB primary if the rider weapon is unsuitable, abilities via ability keys
	var abilities: Array = c.rec.get("abilities", [])
	for i in 4:
		if it.get("ability_%d_just" % (i + 1), false) and i < abilities.size():
			var tgt: Node3D = rig.lock_target
			AbilityRunner.execute(c, abilities[i], {"target": tgt, "aim_dir": rig.aim_ray(60.0)["dir"], "element_slot": c.rec["element_slots"][0]})
	if not riding or not combat.rider_weapon_allowed(c):
		if it.get("attack_just", false) and abilities.size() > 0:
			AbilityRunner.execute(c, abilities[0], {"target": rig.lock_target, "aim_dir": rig.aim_ray(60.0)["dir"], "element_slot": c.rec["element_slots"][0]})
	if not riding:
		# idle body
		visual.animator.speed = 0.0
		velocity = Vector3(0, velocity.y - 18.0 * delta, 0) if not is_on_floor() else Vector3.ZERO
		move_and_slide()


# ------------------------------------------------------------------ demon form
func toggle_demon_form() -> void:
	var d: Dictionary = GameState.player()["demon"]
	if not d.get("unlocked", false):
		return
	if mount:
		EventBus.notify.emit("Nicht im Sattel möglich.", "warn")
		return
	demon_form = not demon_form
	d["in_form"] = demon_form
	var hpf := combatant.hp_frac()
	build_visual()
	recalc_stats()
	combatant.hp = combatant.max_hp * hpf
	combatant.demonic = demon_form
	Fx.burst(global_position + Vector3.UP, Color(1.0, 0.25, 0.05), self, 50, 0.25, 5.0, 0.8)
	Audio.play_at("roar_demon" if demon_form else "spell_cast", global_position, -4.0)
	EventBus.form_changed.emit(demon_form)
	Factions.on_form_seen(self, demon_form)


# ------------------------------------------------------------------ damage & death
func _on_damaged(amount: float, hit: Dictionary) -> void:
	visual.flash_hurt()
	EventBus.player_damaged.emit(amount)
	if amount > 6.0:
		rig.shake(clampf(amount / combatant.max_hp, 0.05, 0.6))
		visual.animator.play("hurt", 0.35)
	if combatant.hp < combatant.max_hp * 0.2 and GameState.skill_rank("def_second_wind") > 0 and not combatant.buffs.has("zweiter_atem_cd"):
		combatant.heal(combatant.max_hp * 0.3)
		combatant.add_buff("zweiter_atem_cd", {"dur": 120.0})
		EventBus.notify.emit("Zweiter Atem!", "good")


func _on_died(_killer: Node) -> void:
	dead = true
	if mount:
		dismount()
	if controlled:
		toggle_direct_control()
	visual.animator.state = "dead"
	GameState.state["stats"]["deaths"] += 1
	EventBus.player_died.emit()


func respawn() -> void:
	var p := GameState.player()
	var rp: Array = p.get("respawn", [])
	if rp.is_empty():
		var sp := WorldData.poi_pos("start_beach")
		rp = [sp.x, sp.y + 1, sp.z]
	global_position = Vector3(rp[0], rp[1] + 0.5, rp[2])
	velocity = Vector3.ZERO
	dead = false
	combatant.dead = false
	combatant.hp = combatant.max_hp * 0.6
	combatant.statuses.clear()
	stamina = max_stamina
	p["hunger"] = maxf(float(p["hunger"]), 40.0)
	visual.animator.state = "idle"
	visual.animator.dead_t = 0.0
