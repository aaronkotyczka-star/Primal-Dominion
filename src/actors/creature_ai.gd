class_name CreatureAI
extends Node
## Brain for creatures. Wild: graze/wander/herd/hunt/flee/rest/territory.
## Companion: follow/wait/defend/attack/ability/retreat with hazard avoidance (no teleporting).

var c: Creature
var state := "idle"
var state_t := 0.0
var target: Node3D = null
var home := Vector3.ZERO
var wander_to := Vector3.INF
var leader: Creature = null
var sleeping := false
var wants_fly := false
var fly_alt := 40.0
var swim_y := -6.0
var command := "follow" # follow, wait, defend, attack, retreat, ability
var command_target: Node3D = null
var command_ability := ""
var wait_pos := Vector3.ZERO
var follow_slot := Vector3.ZERO
var stuck_t := 0.0
var last_pos := Vector3.ZERO
var lost_warned := false
var _perceive_t := 0.0
var _hunt_cd := 0.0
var _rng := RandomNumberGenerator.new()
var temper := "passive"
var aggro_r := 20.0
var flee_hp := 0.2
var threat_memory := {}


func setup(cr: Creature) -> void:
	c = cr
	_rng.randomize()
	home = c.global_position
	temper = c.sp.get("temper", "passive")
	aggro_r = float(c.sp.get("aggro", 15))
	flee_hp = float(Creatures.PERSONALITIES.get(c.rec.get("personality", ""), {}).get("flee", 0.2))
	if temper in ["skittish"]:
		flee_hp = 1.0
	swim_y = -_rng.randf_range(3.0, 10.0)
	fly_alt = _rng.randf_range(25.0, 60.0)
	follow_slot = Vector3(_rng.randf_range(-4, 4), 0, _rng.randf_range(2.0, 6.0))
	last_pos = c.global_position


func swim_depth_target() -> float:
	if target and is_instance_valid(target) and state in ["chase", "attack"]:
		return target.global_position.y
	if not c.wild and c.get_tree().get_first_node_in_group("player"):
		var p: Node3D = c.get_tree().get_first_node_in_group("player")
		return minf(p.global_position.y, -1.0)
	return swim_y


func _player() -> Node3D:
	return c.get_tree().get_first_node_in_group("player")


func _go(s: String, t: float = 0.0) -> void:
	state = s
	state_t = t


func think(delta: float) -> void:
	state_t -= delta
	_perceive_t -= delta
	_hunt_cd -= delta
	var intent: Dictionary = c.intent
	intent["move"] = Vector3.ZERO
	intent["run"] = false
	intent["sprint"] = false
	intent["jump"] = false
	intent["ascend"] = 0.0
	intent["look"] = Vector3.ZERO
	if c.combatant.unconscious or c.in_need != "":
		return
	if c.combatant.is_stunned():
		return
	if c.wild:
		_think_wild(delta)
	else:
		_think_companion(delta)
	_avoid_hazards()
	_check_stuck(delta)


# ------------------------------------------------------------------ wild
func _think_wild(delta: float) -> void:
	var p := _player()
	if _perceive_t <= 0.0:
		_perceive_t = 0.5 + _rng.randf() * 0.3
		_perceive(p)
	var night: bool = GameState.get_hour() < 5.0 or GameState.get_hour() > 21.0
	match state:
		"idle", "graze":
			sleeping = false
			if state_t <= 0.0:
				var r := _rng.randf()
				if night and temper in ["passive", "skittish", "territorial"] and r < 0.5:
					_go("rest", _rng.randf_range(20, 60))
				elif r < 0.55:
					_pick_wander()
					_go("wander", _rng.randf_range(6, 16))
				else:
					_go("graze", _rng.randf_range(4, 10))
					if c.visual.animator.action == "" and c.mode == "ground":
						c.visual.animator.play("eat", 3.0)
			if c.can_fly and c.mode != "fly" and _rng.randf() < 0.002:
				_go("fly", _rng.randf_range(20, 50))
		"wander":
			if leader and is_instance_valid(leader) and leader != c and not leader.combatant.dead:
				var off := leader.global_position + (c.global_position - leader.global_position).normalized() * 6.0
				_move_to(off, false)
			elif wander_to != Vector3.INF:
				if _move_to(wander_to, false) < 2.0:
					_go("idle", _rng.randf_range(2, 6))
			if state_t <= 0.0:
				_go("idle", _rng.randf_range(2, 6))
		"rest":
			sleeping = true
			if state_t <= 0.0 or not night:
				sleeping = false
				_go("idle", 2.0)
		"fly":
			wants_fly = true
			c.intent["ascend"] = 1.0 if c.global_position.y < WorldData.height_at(c.global_position.x, c.global_position.z) + fly_alt else 0.0
			if wander_to == Vector3.INF or c.global_position.distance_to(Vector3(wander_to.x, c.global_position.y, wander_to.z)) < 10.0:
				_pick_wander(160.0)
			_move_to(wander_to, true)
			if state_t <= 0.0:
				_go("land", 30.0)
		"land":
			c.intent["ascend"] = -1.0
			_move_to(c.global_position + c.get_forward() * 5.0, false)
			if c.is_on_floor() or c.mode != "fly":
				wants_fly = false
				_go("idle", 3.0)
		"flee":
			sleeping = false
			if target and is_instance_valid(target):
				var away := c.global_position - target.global_position
				away.y = 0
				_move_dir(away.normalized(), true, true)
				if c.can_fly and away.length() < 15.0:
					wants_fly = true
					c.intent["ascend"] = 1.0
				if away.length() > aggro_r * 3.0 + 30.0:
					_go("idle", 3.0)
			if state_t <= 0.0:
				_go("idle", 2.0)
		"warn":
			if target and is_instance_valid(target):
				_face(target)
				if state_t <= 0.0:
					var d := c.global_position.distance_to(target.global_position)
					if d < aggro_r * 0.6:
						_go("chase", 20.0)
					else:
						_go("idle", 2.0)
		"chase", "attack":
			sleeping = false
			_combat(delta, true)
		"ambush":
			if target and is_instance_valid(target):
				_face(target)
				if c.global_position.distance_to(target.global_position) < aggro_r * 0.5:
					_go("chase", 20.0)
				elif c.global_position.distance_to(target.global_position) > aggro_r * 1.5:
					_go("idle", 1.0)
		"guard_nest":
			if c.global_position.distance_to(c.nest_guard) > 25.0:
				_move_to(c.nest_guard, true)
			else:
				_go("idle", 2.0)
	if state in ["idle", "graze", "wander"] and c.nest_guard != Vector3.INF and c.global_position.distance_to(c.nest_guard) > 40.0:
		_go("guard_nest", 10.0)
	# territory leash
	if state in ["chase", "attack"] and c.global_position.distance_to(home) > 160.0 and not c.is_boss:
		target = null
		_go("wander", 10.0)
		wander_to = home


func _perceive(p: Node3D) -> void:
	if state in ["flee"] and state_t > 0.0:
		return
	var best: Node3D = null
	var best_d := 1e9
	var stealth := 1.0
	if p and p.has_method("is_crouching") and p.is_crouching():
		stealth = 0.55 - 0.08 * GameState.skill_rank("hunt_stealth")
	if p and p.has_method("has_buff") and p.has_buff("moschus") and c.body_h < 2.0:
		stealth = 0.0
	for n in c.get_tree().get_nodes_in_group("combat_actors"):
		if n == c or not is_instance_valid(n) or n.combatant.dead:
			continue
		var d := c.global_position.distance_to(n.global_position)
		if d > aggro_r * 1.6:
			continue
		var team: String = n.combatant.team
		var hostile := false
		if temper == "demonic":
			hostile = team != "demon"
			if n.is_in_group("player") and n.has_method("is_demon_form") and n.is_demon_form():
				hostile = false
		elif team in ["player", "demon", "hostile"]:
			hostile = temper in ["predator", "territorial", "ambusher"]
		elif temper == "predator" and n is Creature and n.species_id != c.species_id and n.body_h < c.body_h * 0.8 and _hunt_cd <= 0.0 and not n.wild == false:
			hostile = _rng.randf() < 0.15
		var eff_r := aggro_r * (stealth if n.is_in_group("player") else 1.0)
		if temper == "territorial":
			eff_r *= 0.6
		if threat_memory.has(n.get_instance_id()):
			eff_r = aggro_r * 2.0
			hostile = true
		if hostile and d < eff_r and d < best_d:
			best = n
			best_d = d
	# skittish creatures flee from fast approaching player
	if temper in ["skittish", "passive", "curious"] and p and is_instance_valid(p):
		var d := c.global_position.distance_to(p.global_position)
		var fast: bool = p.has_method("is_moving_fast") and p.is_moving_fast()
		var wary_add := 0.0
		if d < 25.0:
			if fast:
				wary_add = 30.0
			elif p.has_method("is_crouching") and not p.is_crouching() and d < 10.0:
				wary_add = 12.0
			elif d < 4.0 and not p.is_crouching():
				wary_add = 6.0
		if c.sp.get("tame", {}).get("method", "") == "trust":
			wary_add *= 1.0 - 0.25 * GameState.skill_rank("tame_trust")
		c.wariness = clampf(c.wariness + wary_add - 6.0, 0.0, 120.0)
		if c.wariness >= 100.0 and temper != "curious":
			target = p
			_go("flee", _rng.randf_range(8, 14))
			_alarm_herd(p)
			if c.trust > 0.0:
				c.trust = maxf(0.0, c.trust - 20.0)
				EventBus.notify.emit("%s ist erschrocken geflohen – Vertrauen verloren." % c.sp.get("name", ""), "warn")
			return
	if best:
		if temper in ["skittish", "passive", "curious"]:
			if best.combatant.team != "neutral":
				target = best
				_go("flee", 10.0)
				_alarm_herd(best)
			return
		if state in ["chase", "attack"] and target == best:
			return
		target = best
		if temper == "territorial" and best.is_in_group("player_side") and not threat_memory.has(best.get_instance_id()):
			_go("warn", 2.5)
			c.play_action("roar", 1.4)
		elif temper == "ambusher" and state != "chase":
			_go("ambush", 10.0)
		else:
			_go("chase", 25.0)
			if _rng.randf() < 0.4:
				c.play_action("roar", 1.2)
			_alarm_herd(best, true)


func _alarm_herd(threat: Node3D, join_attack: bool = false) -> void:
	if c.herd_id == 0:
		return
	for n in c.get_tree().get_nodes_in_group("creatures"):
		if n != c and n.wild and n.herd_id == c.herd_id and not n.combatant.dead and n.global_position.distance_to(c.global_position) < 50.0:
			var a: CreatureAI = n.ai
			if a.state in ["flee", "chase", "attack"]:
				continue
			a.target = threat
			if join_attack or a.temper in ["territorial", "predator"]:
				a._go("chase", 20.0)
			else:
				a._go("flee", 10.0)


func on_attacked(src: Node, amount: float) -> void:
	if not is_instance_valid(src) or src == c:
		return
	threat_memory[src.get_instance_id()] = 30.0
	if c.wild:
		sleeping = false
		if c.combatant.hp_frac() < flee_hp or temper in ["skittish"]:
			target = src
			_go("flee", 12.0)
			_alarm_herd(src)
		else:
			target = src
			_go("chase", 25.0)
			_alarm_herd(src, true)
	else:
		if command in ["follow", "defend"] and c.rec.get("aggression", "defensive") != "passive":
			command_target = src
			if state not in ["attack"]:
				_go("attack", 15.0)
				target = src


func on_knocked_out() -> void:
	sleeping = true
	target = null
	_go("idle", 1.0)


func on_woke_up() -> void:
	sleeping = false
	var p := _player()
	if c.wild and p and c.tame_progress > 0.0:
		target = p
		threat_memory[p.get_instance_id()] = 60.0
		_go("chase", 30.0)


# ------------------------------------------------------------------ combat
func _combat(delta: float, wild_mode: bool) -> void:
	if target == null or not is_instance_valid(target) or target.combatant.dead:
		target = null
		_go("idle" if wild_mode else "follow", 2.0)
		return
	if wild_mode and c.combatant.hp_frac() < flee_hp:
		_go("flee", 12.0)
		return
	var d := c.global_position.distance_to(target.global_position)
	var reach: float = c.get_reach() + (target.get_body_radius() if target.has_method("get_body_radius") else 0.5)
	if target.combatant.team in ["neutral"] and wild_mode and not threat_memory.has(target.get_instance_id()):
		_hunt_cd = 30.0
	# flyers dive, swimmers chase in water
	if c.can_fly and c.mode == "fly":
		var tgt_y := target.global_position.y + 1.0
		c.intent["ascend"] = clampf((tgt_y - c.global_position.y) * 0.3, -1.0, 1.0)
		if d < 4.0 + reach:
			wants_fly = false
	if d > reach * 0.9:
		_move_to(target.global_position, true, d > 8.0)
	else:
		_face(target)
	c.intent["look"] = (target.global_position - c.global_position).normalized()
	# choose ability
	if c.visual.animator.action == "" or c.visual.animator.action == "eat":
		var abilities: Array = c.rec.get("abilities", [])
		var choices := []
		for ab_id in abilities:
			if not AbilityRunner.ready(c, ab_id):
				continue
			var ab := DB.ability(ab_id)
			var r := float(ab.get("range", 0.0))
			match ab.get("kind", "melee"):
				"melee", "aoe":
					if d <= reach * (1.4 if ab.get("rear", false) else 1.1):
						choices.append(ab_id)
				"ranged", "move":
					if d <= r and d > reach * 0.8:
						choices.append(ab_id)
				"buff":
					if c.combatant.hp_frac() < 0.7 or _rng.randf() < 0.1:
						choices.append(ab_id)
		if not choices.is_empty():
			var pick: String = choices[_rng.randi() % choices.size()]
			if command == "ability" and command_ability in choices:
				pick = command_ability
				command = "defend"
			var ctx := {"target": target, "element_slot": c.rec.get("element_slots", [[]])[0] if not c.rec.get("element_slots", [[]]).is_empty() else []}
			var es := ctx["element_slot"] as Array
			if es.size() > 1:
				ctx["stamina_mult"] = float(DB.t("mixture").get(str(es.size()), {}).get("stamina", 1.0))
			AbilityRunner.execute(c, pick, ctx)


func _face(t: Node3D) -> void:
	var to := t.global_position - c.global_position
	to.y = 0
	if to.length() > 0.1:
		c.intent["move"] = to.normalized() * 0.06
		c.intent["look"] = to.normalized()


func _move_to(p: Vector3, run: bool, sprint: bool = false) -> float:
	var to := p - c.global_position
	var flat := Vector3(to.x, 0, to.z)
	var d := flat.length()
	if d > 0.5:
		_move_dir(flat / d, run, sprint)
	return d


func _move_dir(dir: Vector3, run: bool, sprint: bool = false) -> void:
	c.intent["move"] = dir
	c.intent["run"] = run
	c.intent["sprint"] = sprint


func _pick_wander(radius: float = 40.0) -> void:
	for i in 6:
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(radius * 0.3, radius)
		var p := home + Vector3(cos(a) * r, 0, sin(a) * r)
		var h := WorldData.height_at(p.x, p.z)
		var ok: bool = (h < -1.5) if c.aquatic else (h > 0.3 or c.can_fly)
		if ok:
			wander_to = Vector3(p.x, h, p.z)
			return
	wander_to = home


# ------------------------------------------------------------------ hazards & stuck
func _avoid_hazards() -> void:
	var mv: Vector3 = c.intent["move"]
	if mv.length() < 0.1 or c.mode == "fly":
		return
	var ahead := c.global_position + mv.normalized() * maxf(3.0, c.body_len * 0.6)
	var h := WorldData.height_at(ahead.x, ahead.z)
	var here := WorldData.height_at(c.global_position.x, c.global_position.z)
	var danger := false
	if c.aquatic:
		danger = h > -1.2
	else:
		var swim_ok := float(c.stats.get("swim", 0.0)) > 0.0 or c.mount_type == "amphibious"
		if h < -c.hip_h * 1.4 and not swim_ok and not (c.wild and state == "flee"):
			danger = true
		if here - h > maxf(5.0, c.body_h * 2.0):
			danger = true # cliff drop
		if WorldData.biome_at(ahead.x, ahead.z) == 8 and h > 195.0 and h < 215.0 and ahead.distance_to(WorldData.poi_pos("vulkan_krater")) < 45.0:
			danger = true # lava crater
	if danger:
		# steer sideways (try left/right)
		var left := mv.rotated(Vector3.UP, 1.2)
		var right := mv.rotated(Vector3.UP, -1.2)
		var pl := c.global_position + left * 4.0
		var pr := c.global_position + right * 4.0
		var hl := WorldData.height_at(pl.x, pl.z)
		var hr := WorldData.height_at(pr.x, pr.z)
		if c.aquatic:
			c.intent["move"] = left if hl < hr else right
		else:
			c.intent["move"] = left if hl > hr else right
		if not c.wild and state in ["follow"]:
			c.intent["move"] *= 0.6


func _check_stuck(delta: float) -> void:
	if c.intent["move"].length() < 0.2:
		stuck_t = 0.0
		last_pos = c.global_position
		return
	if c.global_position.distance_to(last_pos) < 0.05 * maxf(1.0, delta * 60.0):
		stuck_t += delta
	else:
		stuck_t = maxf(0.0, stuck_t - delta)
	last_pos = c.global_position
	if stuck_t > 1.0:
		c.intent["jump"] = true
		c.intent["move"] = c.intent["move"].rotated(Vector3.UP, 1.3 if int(stuck_t * 2) % 2 == 0 else -1.3)
	if stuck_t > 5.0 and c.wild:
		_pick_wander()
		_go("wander", 6.0)
		stuck_t = 0.0


# ------------------------------------------------------------------ companion
func set_command(cmd: String, tgt: Node3D = null, ability: String = "") -> void:
	if _rng.randf() > Creatures.obey_chance(c.rec) and cmd != "retreat":
		EventBus.notify.emit("%s zögert …" % c.rec["name"], "warn")
		return
	command = cmd
	command_target = tgt
	command_ability = ability
	match cmd:
		"wait":
			wait_pos = c.global_position
			_go("wait")
		"attack", "ability":
			if tgt:
				target = tgt
				_go("attack", 30.0)
		"retreat":
			target = null
			_go("retreat", 8.0)
		"follow", "defend":
			_go("follow")


func _think_companion(delta: float) -> void:
	var p := _player()
	if p == null:
		return
	sleeping = false
	if c.rec.get("status", "") == "base":
		_think_base(delta)
		return
	var anchor: Node3D = p
	if p.has_method("get_mount") and p.get_mount():
		anchor = p.get_mount()
	var dist := c.global_position.distance_to(anchor.global_position)
	# lost-behind warning (no teleport)
	if dist > 90.0 and not lost_warned:
		lost_warned = true
		EventBus.notify.emit("%s ist zurückgeblieben (%d m). Pfeife (Tab) oder kehre zurück." % [c.rec["name"], int(dist)], "warn")
	elif dist < 40.0:
		lost_warned = false
	if _perceive_t <= 0.0:
		_perceive_t = 0.6
		if command in ["follow", "defend"] and c.rec.get("aggression", "defensive") == "aggressive" and state != "attack":
			for n in c.get_tree().get_nodes_in_group("combat_actors"):
				if n.combatant.team in ["wild", "demon", "hostile"] and not n.combatant.dead and n.global_position.distance_to(c.global_position) < 22.0 and n.combatant.team != "neutral":
					target = n
					_go("attack", 15.0)
					break
		if command in ["follow", "defend"] and state != "attack":
			# defend: engage anything attacking the player
			for n in c.get_tree().get_nodes_in_group("combat_actors"):
				if n is Creature and n.wild and n.ai.target == p and n.ai.state in ["chase", "attack"] and n.global_position.distance_to(c.global_position) < 35.0:
					if c.rec.get("aggression", "defensive") != "passive":
						target = n
						_go("attack", 15.0)
						break
	# fears (visible morale problems)
	if _rng.randf() < 0.002:
		_check_fears()
	match state:
		"wait":
			if c.global_position.distance_to(wait_pos) > 3.0:
				_move_to(wait_pos, false)
		"attack":
			if command == "retreat":
				_go("retreat", 6.0)
				return
			if target == null or not is_instance_valid(target) or target.combatant.dead:
				target = null
				_go("wait" if command == "wait" else "follow")
				return
			if c.global_position.distance_to(p.global_position) > 70.0 and command != "attack":
				target = null
				_go("follow")
				return
			_combat(delta, false)
		"retreat":
			var away_from: Vector3 = p.global_position
			_move_to(away_from + (c.global_position - away_from).normalized() * 3.0, true, true)
			if state_t <= 0.0:
				command = "follow"
				_go("follow")
		_:
			if command == "wait":
				_go("wait")
				return
			# formation slot behind player
			var basis: Basis = anchor.global_transform.basis
			var slot := anchor.global_position + basis * (follow_slot * (1.0 + c.body_len * 0.15))
			var d := c.global_position.distance_to(slot)
			if d > 3.0:
				var run := d > 8.0
				_move_to(slot, run, d > 25.0)
			else:
				c.intent["look"] = (p.global_position - c.global_position).normalized()
			if c.can_fly:
				var py: float = anchor.global_position.y
				if p.has_method("get_mount") and p.get_mount() and p.get_mount().mode == "fly":
					wants_fly = true
					c.intent["ascend"] = clampf((py - c.global_position.y) * 0.3, -1.0, 1.0)
				elif c.mode == "fly":
					c.intent["ascend"] = -1.0
					wants_fly = false


func _think_base(delta: float) -> void:
	var world := c.get_tree().get_first_node_in_group("world")
	if state_t <= 0.0:
		_go("idle", _rng.randf_range(4, 10))
		var bc: Vector3 = world.base_center() if world and world.has_method("base_center") else home
		home = bc
		_pick_wander(14.0)
	if wander_to != Vector3.INF and state == "idle":
		_move_to(wander_to, false)


func _check_fears() -> void:
	var fears: Array = c.rec.get("fears", [])
	var sky := c.get_tree().get_first_node_in_group("sky_weather")
	var afraid := ""
	if "dunkel" in fears and sky and sky.is_night():
		afraid = "der Dunkelheit"
	if "gewitter" in fears and sky and sky.weather in ["storm", "demon_storm"]:
		afraid = "dem Gewitter"
	if "dämonen" in fears and WorldData.biome_at(c.global_position.x, c.global_position.z) == 10:
		afraid = "der Verderbnis"
	if afraid != "":
		c.combatant.add_buff("angst", {"dmg": 0.85, "dur": 30.0})
		EventBus.notify.emit("%s fürchtet sich vor %s (-15%% Schaden)." % [c.rec["name"], afraid], "warn")
