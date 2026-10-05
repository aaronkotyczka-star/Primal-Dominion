class_name ProcAnimator
extends Node
## Procedural skeletal animation shared by all body families.
## Bones have identity rest rotations: +X pitch swings limbs forward, Y = yaw, Z = roll.

var skel: Skeleton3D
var meta: Dictionary
var gait: String = "biped"
var family: String = ""
var hip_h := 1.0
var parts: Dictionary = {}

# --- inputs (set by controller every frame)
var speed := 0.0
var run_speed := 6.0
var mode := "ground" # ground, swim, fly, glide
var state := "idle" # idle, move, dead, sleep, sit, stunned
var turn := 0.0
var look_local := Vector3.ZERO # target direction in local space (zero = none)
var aim_pitch := 0.0
var vspeed := 0.0
var block := false
var crouch := false
var aiming := false
var hold_pose := "" # humanoid upper-body hold: "", "bow", "spear", "staff", "torch"

# --- internal
var phase := 0.0
var t_idle := 0.0
var action := ""
var action_t := 0.0
var action_dur := 1.0
var dead_t := 0.0
var sleep_t := 0.0
var _bones := {}
var _chains := {}
var _rest_pos := {}
var _idle_look := Vector2.ZERO
var _idle_look_target := Vector2.ZERO
var _idle_timer := 0.0
var _smooth_speed := 0.0
var _smooth_turn := 0.0
var _flap := 0.0
var rng := RandomNumberGenerator.new()


func setup(s: Skeleton3D, m: Dictionary, part_nodes: Dictionary = {}) -> void:
	skel = s
	meta = m
	parts = part_nodes
	gait = m.get("gait", "biped")
	family = m.get("family", "")
	hip_h = maxf(0.1, float(m.get("hip_height", 1.0)))
	for i in skel.get_bone_count():
		_bones[skel.get_bone_name(i)] = i
		_rest_pos[i] = skel.get_bone_rest(i).origin
	var ch: Dictionary = m.get("chains", {})
	for k in ch:
		var arr: Array = []
		for bn in ch[k]:
			arr.append(_bones.get(bn, -1))
		_chains[k] = arr
	rng.seed = hash(m.get("id", "")) + randi()
	phase = rng.randf()


func play(act: String, duration: float = 0.8) -> void:
	action = act
	action_t = 0.0
	action_dur = maxf(0.05, duration)


func is_playing() -> bool:
	return action != ""


func _b(name: String) -> int:
	return _bones.get(name, -1)


func _rot(bi: int, pitch: float, yaw: float = 0.0, roll: float = 0.0) -> void:
	if bi < 0:
		return
	skel.set_bone_pose_rotation(bi, Quaternion.from_euler(Vector3(pitch, yaw, roll)))


func _pos(bi: int, offset: Vector3) -> void:
	if bi < 0:
		return
	skel.set_bone_pose_position(bi, _rest_pos[bi] + offset)


func _chain(name: String) -> Array:
	return _chains.get(name, [])


func _process(delta: float) -> void:
	if skel == null or not is_instance_valid(skel):
		return
	if not skel.is_visible_in_tree():
		return
	delta = minf(delta, 0.05)
	t_idle += delta
	_smooth_speed = lerpf(_smooth_speed, speed, minf(1.0, delta * 6.0))
	_smooth_turn = lerpf(_smooth_turn, turn, minf(1.0, delta * 4.0))
	if action != "":
		action_t += delta / action_dur
		if action_t >= 1.0:
			action = ""
			action_t = 0.0
	if state == "dead":
		dead_t = minf(1.0, dead_t + delta * 1.4)
	else:
		dead_t = maxf(0.0, dead_t - delta * 2.0)
	if state == "sleep":
		sleep_t = minf(1.0, sleep_t + delta * 0.8)
	else:
		sleep_t = maxf(0.0, sleep_t - delta * 1.5)
	# idle look-around
	_idle_timer -= delta
	if _idle_timer <= 0.0:
		_idle_timer = rng.randf_range(1.5, 4.5)
		_idle_look_target = Vector2(rng.randf_range(-0.6, 0.6), rng.randf_range(-0.25, 0.2))
	_idle_look = _idle_look.lerp(_idle_look_target, minf(1.0, delta * 1.5))
	var rf := clampf(_smooth_speed / maxf(0.5, run_speed), 0.0, 1.4)
	var stride := hip_h * lerpf(1.6, 3.2, clampf(rf, 0.0, 1.0))
	if gait == "human":
		stride = hip_h * lerpf(1.5, 2.6, clampf(rf, 0.0, 1.0))
	elif gait in ["swim", "serpent"]:
		stride = maxf(1.0, float(meta.get("length", 4.0)) * 0.6)
	if mode in ["swim", "fly", "glide"] or gait in ["swim", "serpent"]:
		phase = fmod(phase + delta * (0.35 + _smooth_speed / stride), 1.0)
	else:
		phase = fmod(phase + delta * (_smooth_speed / stride), 1.0)
	match gait:
		"biped", "wyvern":
			_anim_biped(rf, delta)
		"quad":
			_anim_quad(rf, delta)
		"flyer":
			_anim_flyer(rf, delta)
		"swim":
			_anim_swim(rf, delta)
		"serpent":
			_anim_serpent(rf, delta)
		"spider":
			_anim_spider(rf, delta)
		"human":
			_anim_human(rf, delta)
	_apply_death_and_sleep()


# ------------------------------------------------------------------ helpers
func _look_angles() -> Vector2:
	var yaw := _idle_look.x * 0.6
	var pitch := _idle_look.y * 0.5
	if look_local.length_squared() > 0.01:
		var d := look_local.normalized()
		yaw = clampf(atan2(-d.x, -d.z), -1.1, 1.1)
		pitch = clampf(asin(clampf(d.y, -1.0, 1.0)), -0.6, 0.6)
	return Vector2(yaw, pitch)


func _act(name: String) -> float:
	return action_t if action == name else -1.0


func _bell(t: float, a: float, b: float) -> float:
	## 0 outside [a,b], smooth 1 peak in the middle
	if t < a or t > b:
		return 0.0
	var x := (t - a) / (b - a)
	return sin(x * PI)


func _env(t: float, rise: float, fall: float) -> float:
	## ramps up until `rise`, holds, falls after `fall`
	if t < 0.0:
		return 0.0
	if t < rise:
		return smoothstep(0.0, rise, t)
	if t > fall:
		return 1.0 - smoothstep(fall, 1.0, t)
	return 1.0


func _tail(sway: float, droop: float, extra_yaw: float = 0.0, extra_pitch: float = 0.0) -> void:
	var tail := _chain("tail")
	var n := tail.size()
	for i in n:
		var k := float(i + 1) / float(n)
		var w := sin(t_idle * 1.3 - i * 0.6) * 0.06 + sin(phase * TAU - i * 0.7) * sway
		_rot(tail[i], droop * k * 0.3 + extra_pitch * k, w + extra_yaw * k * 0.5 - _smooth_turn * 0.12 * k, 0.0)


func _neck(look: Vector2, pitch_add: float = 0.0, yaw_add: float = 0.0) -> void:
	var neck := _chain("neck")
	var n := neck.size()
	if n == 0:
		return
	for i in n:
		var w := 1.0 / n
		var p := (-look.y + pitch_add) * w
		var y := (look.x + yaw_add) * w
		if i == n - 1:
			_rot(neck[i], p, y, 0.0)
		else:
			_rot(neck[i], p, y, 0.0)


func _jaw(open: float) -> void:
	_rot(_b("jaw"), clampf(open, 0.0, 1.0) * 0.55, 0.0, 0.0)


# ------------------------------------------------------------------ biped (theropod / ornithopod / wyvern)
func _anim_biped(rf: float, delta: float) -> void:
	var moving := _smooth_speed > 0.15
	var amp := clampf(rf, 0.0, 1.0)
	var s := sin(phase * TAU)
	var look := _look_angles()
	var breath := sin(t_idle * 1.6) * 0.02
	var crouch_amt := 0.0
	var lean := 0.0
	var neck_pitch := 0.0
	var jaw := 0.0
	var tail_yaw := 0.0
	var spine_yaw := 0.0
	# actions
	var t := _act("bite")
	if t >= 0.0:
		var wind := _bell(t, 0.0, 0.45)
		var lunge := _bell(t, 0.35, 0.8)
		neck_pitch += -wind * 0.35 + lunge * 0.55
		lean += lunge * 0.12
		jaw = maxf(_env(t, 0.3, 0.5) * (1.0 if t < 0.55 else 0.0), _bell(t, 0.2, 0.55))
	t = _act("roar")
	if t >= 0.0:
		var e := _env(t, 0.2, 0.75)
		neck_pitch -= e * 0.5
		jaw = e
		look = Vector2(look.x + sin(t_idle * 25.0) * 0.04 * e, look.y)
	t = _act("tail_swipe")
	if t >= 0.0:
		var sw := sin(t * TAU) * _env(t, 0.15, 0.8)
		tail_yaw = sw * 1.6
		spine_yaw = -sw * 0.35
	t = _act("claw")
	if t >= 0.0:
		lean += _bell(t, 0.1, 0.8) * 0.15
	t = _act("hurt")
	if t >= 0.0:
		neck_pitch -= _bell(t, 0.0, 1.0) * 0.4
		lean -= _bell(t, 0.0, 1.0) * 0.1
	t = _act("eat")
	if t >= 0.0:
		var e := _env(t, 0.2, 0.8)
		neck_pitch += e * 1.1
		lean += e * 0.25
		jaw = e * (sin(t_idle * 9.0) * 0.5 + 0.5) * 0.7
		crouch_amt += e * 0.2
	t = _act("spit")
	if t >= 0.0:
		neck_pitch += -_bell(t, 0.0, 0.5) * 0.4 + _bell(t, 0.4, 0.8) * 0.3
		jaw = _bell(t, 0.3, 0.9)
	# legs
	var A1 := lerpf(0.25, 0.55, amp)
	var K := lerpf(0.5, 1.0, amp)
	for side in ["L", "R"]:
		var leg := _chain("leg_" + side)
		if leg.size() < 4:
			continue
		var ph := phase + (0.0 if side == "L" else 0.5)
		var ls := sin(ph * TAU)
		var lc := cos(ph * TAU)
		var th := 0.0
		var sh := 0.0
		var mt := 0.0
		var to := 0.0
		if moving and mode == "ground":
			th = A1 * ls
			var lift := maxf(0.0, lc)
			sh = -K * lift * 0.9 - 0.1 * amp
			mt = K * lift * 0.8 + 0.08 * amp
			to = -th - sh - mt + lift * 0.4
		elif mode in ["fly", "glide"]:
			th = 0.6
			sh = -0.9
			mt = 1.0
			to = 0.3
		elif mode == "swim":
			th = sin(ph * TAU) * 0.6
			sh = -0.5
			mt = 0.4
		th += crouch_amt * 0.4
		sh -= crouch_amt * 0.8
		mt += crouch_amt * 0.5
		_rot(leg[0], th, 0.0, 0.0)
		_rot(leg[1], sh, 0.0, 0.0)
		_rot(leg[2], mt, 0.0, 0.0)
		_rot(leg[3], to, 0.0, 0.0)
	# arms
	for side in ["L", "R"]:
		var arm := _chain("arm_" + side)
		if arm.size() < 3:
			continue
		var cl := _act("claw")
		var reach := _bell(cl, 0.1, 0.7) if cl >= 0.0 else 0.0
		var sgn := -1.0 if side == "L" else 1.0
		_rot(arm[0], 0.2 + sin(phase * TAU + (0.0 if side == "L" else PI)) * 0.1 * amp + reach * 0.9 + breath, 0.0, sgn * 0.1)
		_rot(arm[1], 0.5 - reach * 0.4, 0.0, 0.0)
		_rot(arm[2], 0.2, 0.0, 0.0)
	# body
	var bob := -absf(s) * 0.04 * hip_h * amp if moving else breath * hip_h * 0.3
	_pos(_b("pelvis"), Vector3(0, bob - crouch_amt * hip_h * 0.15, 0))
	_rot(_b("pelvis"), lean + breath * 0.5, spine_yaw * 0.5 + sin(phase * TAU) * 0.05 * amp, sin(phase * TAU) * 0.03 * amp)
	_rot(_b("spine"), breath, spine_yaw * 0.5 + _smooth_turn * 0.1, 0.0)
	_neck(look, neck_pitch - lean, 0.0)
	_jaw(jaw + (sin(t_idle * 0.7) * 0.5 + 0.5) * 0.05)
	_tail(0.08 * amp + 0.02, lean * 0.0, tail_yaw, -lean * 0.5)
	if gait == "wyvern":
		_wings(mode, rf, delta)


# ------------------------------------------------------------------ quadruped
func _anim_quad(rf: float, delta: float) -> void:
	var moving := _smooth_speed > 0.15
	var amp := clampf(rf, 0.0, 1.0)
	var look := _look_angles()
	var breath := sin(t_idle * 1.3) * 0.015
	var neck_pitch := 0.0
	var jaw := 0.0
	var tail_yaw := 0.0
	var spine_yaw := 0.0
	var front_lift := 0.0
	var head_down := 0.0
	var t := _act("bite")
	if t >= 0.0:
		neck_pitch += -_bell(t, 0.0, 0.45) * 0.3 + _bell(t, 0.35, 0.8) * 0.45
		jaw = _bell(t, 0.15, 0.6)
	t = _act("gore")
	if t >= 0.0:
		head_down = _env(t, 0.25, 0.6) * 0.5
		neck_pitch += -_bell(t, 0.55, 0.9) * 0.6
	t = _act("roar")
	if t >= 0.0:
		var e := _env(t, 0.2, 0.75)
		neck_pitch -= e * 0.45
		jaw = e
	t = _act("tail_swipe")
	if t >= 0.0:
		var sw := sin(t * TAU) * _env(t, 0.15, 0.8)
		tail_yaw = sw * 1.7
		spine_yaw = -sw * 0.25
	t = _act("stomp")
	if t >= 0.0:
		front_lift = _bell(t, 0.0, 0.7)
	t = _act("eat")
	if t >= 0.0:
		var e := _env(t, 0.2, 0.8)
		head_down = e * 0.9
		jaw = e * (sin(t_idle * 8.0) * 0.5 + 0.5) * 0.6
	t = _act("hurt")
	if t >= 0.0:
		neck_pitch -= _bell(t, 0.0, 1.0) * 0.35
	var trot := amp > 0.55
	var offs := {"leg_L": 0.0, "arm_L": 0.25, "leg_R": 0.5, "arm_R": 0.75}
	if trot:
		offs = {"leg_L": 0.0, "arm_R": 0.0, "leg_R": 0.5, "arm_L": 0.5}
	var A1 := lerpf(0.22, 0.5, amp)
	var K := lerpf(0.45, 0.9, amp)
	var mammal := family in ["mammal"]
	for ch in offs:
		var c := _chain(ch)
		if c.size() < 4:
			continue
		var ph: float = phase + offs[ch]
		var ls := sin(ph * TAU)
		var lift := maxf(0.0, cos(ph * TAU))
		var is_front: bool = ch.begins_with("arm")
		var a0 := 0.0
		var a1 := 0.0
		var a2 := 0.0
		var a3 := 0.0
		if moving and mode == "ground":
			a0 = A1 * ls
			if is_front:
				a1 = K * lift * 0.9
				a2 = -K * lift * 0.5
				a3 = -a0 - a1 - a2 + lift * 0.3
			else:
				a1 = -K * lift * (0.9 if mammal else 0.6)
				a2 = K * lift * (0.8 if mammal else 0.4)
				a3 = -a0 - a1 - a2 + lift * 0.3
		elif mode == "swim":
			a0 = sin(ph * TAU) * 0.5
			a1 = -0.3 if not is_front else 0.3
		if is_front and front_lift > 0.0:
			a0 += front_lift * 0.8
			a1 += front_lift * 0.6
		_rot(c[0], a0, 0.0, 0.0)
		_rot(c[1], a1, 0.0, 0.0)
		_rot(c[2], a2, 0.0, 0.0)
		_rot(c[3], a3, 0.0, 0.0)
	var bob := -absf(sin(phase * TAU * 2.0)) * 0.025 * hip_h * amp if moving else breath * hip_h * 0.2
	_pos(_b("pelvis"), Vector3(0, bob + front_lift * hip_h * 0.05, 0))
	_rot(_b("pelvis"), -front_lift * 0.25 + breath * 0.3, spine_yaw * 0.5, sin(phase * TAU) * 0.025 * amp)
	_rot(_b("spine"), breath, spine_yaw * 0.5 + _smooth_turn * 0.08, 0.0)
	_neck(look, neck_pitch + head_down, 0.0)
	_jaw(jaw)
	_tail(0.06 * amp + 0.02, 0.0, tail_yaw, 0.0)


# ------------------------------------------------------------------ wings (flyer & wyvern)
func _wings(m: String, rf: float, delta: float) -> void:
	var flying := m in ["fly", "glide"]
	var tgt := 1.0 if flying else 0.0
	_flap = lerpf(_flap, tgt, minf(1.0, delta * 3.0))
	var flap_speed := 2.2 + clampf(vspeed, 0.0, 6.0) * 0.4
	var f := 0.0
	if m == "fly":
		f = sin(t_idle * TAU * flap_speed * 0.5) * 0.75
	elif m == "glide":
		f = sin(t_idle * 1.3) * 0.05 + 0.08
	var wb := _act("wing_buffet")
	if wb >= 0.0:
		f = sin(wb * TAU * 2.0) * 0.9
	for side in ["L", "R"]:
		var w := _chain("wing_" + side)
		if w.size() < 4:
			continue
		var sg := -1.0 if side == "L" else 1.0
		var fold := 1.0 - _flap
		if wb >= 0.0:
			fold = 0.0
		# folded: wing1 down/back, wing2 folds back hard, wing3/4 fold forward
		_rot(w[0], 0.0, sg * (-0.6 * fold), sg * (f * _flap - 0.9 * fold))
		_rot(w[1], 0.0, sg * (1.9 * fold) + sg * f * 0.15, sg * (f * 0.25))
		_rot(w[2], 0.0, sg * (-2.3 * fold), 0.0)
		_rot(w[3], 0.0, sg * (0.4 * fold) - sg * f * 0.1, sg * f * 0.2)
	# hybrid wing parts (rigid) flap via attachment pivots
	for sock in ["shoulder_L", "shoulder_R"]:
		if parts.has(sock):
			var pv: Node3D = parts[sock].get_node_or_null("Pivot")
			if pv:
				var sg2 := -1.0 if sock.ends_with("L") else 1.0
				var fold2 := 1.0 - _flap
				pv.rotation = Vector3(0.0, sg2 * 0.9 * fold2, sg2 * (f * _flap * 1.2 - 0.6 * fold2))


# ------------------------------------------------------------------ flyer (pterosaur, bird)
func _anim_flyer(rf: float, delta: float) -> void:
	var look := _look_angles()
	var neck_pitch := 0.0
	var jaw := 0.0
	var t := _act("bite")
	if t >= 0.0:
		neck_pitch += -_bell(t, 0.0, 0.4) * 0.4 + _bell(t, 0.3, 0.8) * 0.6
		jaw = _bell(t, 0.1, 0.6)
	t = _act("roar")
	if t >= 0.0:
		neck_pitch -= _env(t, 0.2, 0.7) * 0.5
		jaw = _env(t, 0.2, 0.7)
	_wings(mode, rf, delta)
	var flying := mode in ["fly", "glide"]
	var moving := _smooth_speed > 0.15
	var amp := clampf(rf, 0.0, 1.0)
	for side in ["L", "R"]:
		var leg := _chain("leg_" + side)
		if leg.size() < 3:
			continue
		if flying:
			_rot(leg[0], -0.9, 0.0, 0.0)
			_rot(leg[1], -0.4, 0.0, 0.0)
			_rot(leg[2], 0.8, 0.0, 0.0)
		else:
			var ph := phase + (0.0 if side == "L" else 0.5)
			var lift := maxf(0.0, cos(ph * TAU)) if moving else 0.0
			_rot(leg[0], sin(ph * TAU) * 0.4 * amp if moving else 0.0, 0.0, 0.0)
			_rot(leg[1], -lift * 0.7, 0.0, 0.0)
			_rot(leg[2], lift * 0.6, 0.0, 0.0)
	var pitch_body := 0.0
	if flying:
		pitch_body = clampf(-vspeed * 0.04, -0.3, 0.3)
	_rot(_b("pelvis"), pitch_body, 0.0, -_smooth_turn * 0.25 if flying else 0.0)
	_rot(_b("spine"), sin(t_idle * 1.5) * 0.015, 0.0, 0.0)
	_neck(look, neck_pitch + (0.3 if flying else 0.0), 0.0)
	_jaw(jaw)
	_tail(0.03, 0.0)


# ------------------------------------------------------------------ marine
func _anim_swim(rf: float, delta: float) -> void:
	var look := _look_angles()
	var amp := clampf(rf, 0.2, 1.0)
	var neck_pitch := 0.0
	var jaw := 0.0
	var t := _act("bite")
	if t >= 0.0:
		neck_pitch += -_bell(t, 0.0, 0.4) * 0.3 + _bell(t, 0.3, 0.8) * 0.3
		jaw = _bell(t, 0.1, 0.6)
	t = _act("tail_swipe")
	var ty := 0.0
	if t >= 0.0:
		ty = sin(t * TAU) * _env(t, 0.1, 0.8) * 1.4
	var tail := _chain("tail")
	var n := tail.size()
	for i in n:
		var k := float(i + 1) / float(n)
		_rot(tail[i], 0.0, sin(phase * TAU - i * 0.55) * (0.12 + 0.1 * amp) * k + ty * k * 0.5 - _smooth_turn * 0.15 * k, 0.0)
	_rot(_b("pelvis"), 0.0, sin(phase * TAU + 0.8) * 0.05 * amp, 0.0)
	_rot(_b("spine"), 0.0, sin(phase * TAU + 1.6) * 0.04 * amp - _smooth_turn * 0.1, 0.0)
	for side in ["L", "R"]:
		var sg := -1.0 if side == "L" else 1.0
		var arm := _chain("arm_" + side)
		var leg := _chain("leg_" + side)
		var row := sin(phase * TAU * (1.0 if family == "marine" else 0.5) + (0.0 if side == "L" else 0.3))
		if arm.size() >= 2:
			_rot(arm[0], row * 0.35, row * 0.2, sg * row * 0.35)
			_rot(arm[1], 0.0, -row * 0.15, sg * row * 0.15)
		if leg.size() >= 2:
			_rot(leg[0], -row * 0.3, -row * 0.15, sg * row * 0.25)
			_rot(leg[1], 0.0, 0.0, sg * row * 0.1)
	_neck(look, neck_pitch, 0.0)
	_jaw(jaw)


# ------------------------------------------------------------------ serpent
func _anim_serpent(rf: float, delta: float) -> void:
	var look := _look_angles()
	var amp := clampf(rf, 0.15, 1.0)
	var body := _chain("body")
	var n := body.size()
	var coil := 0.0
	var jaw := 0.0
	var head_pitch := 0.0
	var t := _act("bite")
	if t >= 0.0:
		head_pitch = -_bell(t, 0.0, 0.4) * 0.5 + _bell(t, 0.3, 0.75) * 0.4
		jaw = _bell(t, 0.1, 0.6)
	t = _act("roar")
	if t >= 0.0:
		jaw = _env(t, 0.2, 0.7)
		head_pitch -= _env(t, 0.2, 0.7) * 0.3
	for i in n:
		var k := float(i) / float(n)
		var y := sin(phase * TAU * 1.0 - i * 0.7) * (0.18 + 0.12 * amp) * (0.4 + k)
		var p := 0.0
		if i < 3:
			p = -0.12 * (3 - i) * (1.0 if state != "dead" else 0.0)
		_rot(body[i], p, y, 0.0)
	_rot(_b("head"), -look.y * 0.6 + head_pitch + 0.25, look.x * 0.5, 0.0)
	_jaw(jaw)


# ------------------------------------------------------------------ spider
func _anim_spider(rf: float, delta: float) -> void:
	var moving := _smooth_speed > 0.1
	var amp := clampf(rf, 0.0, 1.0)
	for i in 4:
		for side in ["L", "R"]:
			var c := _chain("spider_%d_%s" % [i, side])
			if c.size() < 3:
				continue
			var grp := (i % 2) ^ (0 if side == "L" else 1)
			var ph := phase + 0.5 * grp
			var lift := maxf(0.0, cos(ph * TAU)) if moving else 0.0
			var sw := sin(ph * TAU) * 0.35 * amp if moving else sin(t_idle * 2.0 + i) * 0.02
			_rot(c[0], 0.0, sw, (-1.0 if side == "L" else 1.0) * lift * 0.4)
			_rot(c[1], 0.0, 0.0, 0.0)
			_rot(c[2], 0.0, 0.0, 0.0)
	var t := _act("bite")
	var lunge := _bell(t, 0.2, 0.8) if t >= 0.0 else 0.0
	_rot(_b("spine"), lunge * 0.2, 0.0, 0.0)
	_rot(_b("abdomen"), sin(t_idle * 1.5) * 0.04, sin(phase * TAU) * 0.05 * amp, 0.0)
	_pos(_b("pelvis"), Vector3(0, -absf(sin(phase * TAU * 2.0)) * 0.02 * hip_h * amp, 0))


# ------------------------------------------------------------------ humanoid
func _anim_human(rf: float, delta: float) -> void:
	var moving := _smooth_speed > 0.15
	var amp := clampf(rf, 0.0, 1.2)
	var look := _look_angles()
	var breath := sin(t_idle * 1.8) * 0.02
	var s := sin(phase * TAU)
	var spine_yaw := 0.0
	var spine_pitch := 0.0
	var root_pitch := 0.0
	var root_drop := 0.0
	# arm targets: [clav, uarm(pitch,yaw,roll), farm pitch, hand]
	var rU := Vector3(0, 0, 0.12)
	var lU := Vector3(0, 0, -0.12)
	var rF := 0.25
	var lF := 0.25
	var swing := 0.5 * minf(amp, 1.0)
	if moving and mode == "ground":
		rU.x = -s * swing
		lU.x = s * swing
		rF = 0.3 + maxf(0.0, -s) * 0.6 * amp
		lF = 0.3 + maxf(0.0, s) * 0.6 * amp
		spine_pitch = 0.08 * amp
	# hold poses
	match hold_pose:
		"bow":
			if aiming:
				lU = Vector3(1.45 + aim_pitch, 0.25, -0.1)
				lF = 0.0
				rU = Vector3(1.3 + aim_pitch, -0.6, 0.6)
				rF = 2.0
				spine_yaw = 0.5
		"spear", "staff", "torch":
			rU = Vector3(rU.x * 0.5 + 0.3, 0.0, 0.15)
			rF = 1.0
	if block:
		rU = Vector3(1.2, -0.4, 0.3)
		rF = 1.6
		lU = Vector3(1.1, 0.4, -0.3)
		lF = 1.7
	# actions
	var t := _act("slash")
	if t >= 0.0:
		var wind := _env(t, 0.3, 0.35)
		var hit := smoothstep(0.3, 0.6, t)
		var back := 1.0 - smoothstep(0.7, 1.0, t)
		rU = Vector3(lerpf(1.4, 0.6, hit) * back + rU.x * (1.0 - back), lerpf(0.9, -1.2, hit) * back, 0.3)
		rF = lerpf(1.2, 0.2, hit) * back + rF * (1.0 - back)
		spine_yaw = lerpf(0.5, -0.6, hit) * back * wind
	t = _act("slash2")
	if t >= 0.0:
		var hit := smoothstep(0.3, 0.6, t)
		var back := 1.0 - smoothstep(0.7, 1.0, t)
		rU = Vector3(1.3 * back, lerpf(-1.2, 0.8, hit) * back, 0.5)
		rF = 0.4
		spine_yaw = lerpf(-0.6, 0.5, hit) * back
	t = _act("overhead")
	if t >= 0.0:
		var hit := smoothstep(0.4, 0.6, t)
		var back := 1.0 - smoothstep(0.75, 1.0, t)
		var up := _env(t, 0.35, 0.45)
		rU = Vector3(lerpf(2.9, 0.7, hit) * maxf(up, back * hit), -0.3, 0.2)
		lU = Vector3(lerpf(2.7, 0.7, hit) * maxf(up, back * hit), 0.3, -0.2)
		rF = lerpf(0.8, 0.1, hit)
		lF = rF
		spine_pitch = lerpf(-0.25, 0.35, hit) * maxf(up, back)
	t = _act("thrust")
	if t >= 0.0:
		var hit := _bell(t, 0.25, 0.75)
		rU = Vector3(0.6 + hit * 0.9, 0.0, 0.2)
		rF = 1.4 - hit * 1.3
		spine_yaw = -hit * 0.3
		spine_pitch = hit * 0.15
	t = _act("throw")
	if t >= 0.0:
		var hit := smoothstep(0.35, 0.6, t)
		var back := 1.0 - smoothstep(0.7, 1.0, t)
		rU = Vector3(lerpf(2.8, 1.0, hit) * back, 0.2, 0.3)
		rF = lerpf(1.5, 0.1, hit)
		spine_yaw = lerpf(0.5, -0.4, hit) * back
	t = _act("cast")
	if t >= 0.0:
		var e := _env(t, 0.3, 0.75)
		rU = rU.lerp(Vector3(1.4, -0.2, 0.2), e)
		lU = lU.lerp(Vector3(1.4, 0.2, -0.2), e)
		rF = lerpf(rF, 0.2, e)
		lF = lerpf(lF, 0.2, e)
	t = _act("heal")
	if t >= 0.0:
		var e := _env(t, 0.3, 0.7)
		rU = rU.lerp(Vector3(1.0, 0.5, 0.3), e)
		lU = lU.lerp(Vector3(1.0, -0.5, -0.3), e)
		rF = lerpf(rF, 1.4, e)
		lF = lerpf(lF, 1.4, e)
		spine_pitch -= e * 0.1
	t = _act("gather")
	if t >= 0.0:
		var hit := _bell(t, 0.2, 0.8)
		rU = Vector3(lerpf(2.2, 0.5, hit), -0.2, 0.2)
		rF = 0.6
		spine_pitch = hit * 0.4
	t = _act("interact")
	if t >= 0.0:
		var e := _bell(t, 0.0, 1.0)
		rU = rU.lerp(Vector3(1.0, -0.2, 0.2), e)
		rF = lerpf(rF, 0.3, e)
		spine_pitch = e * 0.3
	t = _act("hurt")
	if t >= 0.0:
		spine_pitch -= _bell(t, 0.0, 1.0) * 0.3
	t = _act("dodge")
	if t >= 0.0:
		root_pitch = -t * TAU
		root_drop = _bell(t, 0.0, 1.0) * hip_h * 0.55
	t = _act("eat")
	if t >= 0.0:
		var e := _env(t, 0.2, 0.8)
		rU = rU.lerp(Vector3(1.3, -0.6, 0.3), e)
		rF = lerpf(rF, 2.1, e)
	# legs
	var A := lerpf(0.45, 0.8, minf(amp, 1.0))
	for side in ["L", "R"]:
		var leg := _chain("leg_" + side)
		if leg.size() < 4:
			continue
		var ph := phase + (0.0 if side == "L" else 0.5)
		var ls := sin(ph * TAU)
		var lift := maxf(0.0, cos(ph * TAU))
		var th := 0.0
		var kn := 0.0
		var an := 0.0
		if state == "sit":
			th = 1.45
			kn = -1.5
			an = 0.1
			var sg := -1.0 if side == "L" else 1.0
			_rot(leg[0], th, 0.0, sg * 0.35)
			_rot(leg[1], kn, 0.0, 0.0)
			_rot(leg[2], an, 0.0, 0.0)
			_rot(leg[3], 0.0, 0.0, 0.0)
			continue
		if moving and mode == "ground":
			th = A * ls
			kn = -lift * A * 1.4 - 0.08
			an = -(th + kn) * 0.5 * (1.0 - lift)
		elif mode == "swim":
			th = sin(ph * TAU) * 0.4
			kn = -0.4 - lift * 0.3
		if crouch:
			th += 0.8
			kn -= 1.3
			an += 0.5
		_rot(leg[0], th, 0.0, 0.0)
		_rot(leg[1], kn, 0.0, 0.0)
		_rot(leg[2], an, 0.0, 0.0)
		_rot(leg[3], 0.0, 0.0, 0.0)
	# arms
	var ra := _chain("arm_R")
	var la := _chain("arm_L")
	if ra.size() >= 4:
		_rot(ra[1], rU.x, rU.y, rU.z + 0.05)
		_rot(ra[2], rF, 0.0, 0.0)
	if la.size() >= 4:
		_rot(la[1], lU.x, lU.y, lU.z - 0.05)
		_rot(la[2], lF, 0.0, 0.0)
	if mode == "swim":
		var sw := sin(phase * TAU)
		if ra.size() >= 4:
			_rot(ra[1], 1.5 + sw * 0.6, -0.5, 0.6)
			_rot(la[1], 1.5 - sw * 0.6, 0.5, -0.6)
	var crouch_drop := hip_h * 0.28 if crouch else 0.0
	if state == "sit":
		crouch_drop = 0.0
	var bob := -absf(s) * 0.03 * hip_h * minf(amp, 1.0) if moving else breath * 0.2 * hip_h
	_pos(_b("pelvis"), Vector3(0, bob - crouch_drop, 0))
	_rot(_b("pelvis"), spine_pitch * 0.3 + (0.3 if crouch else 0.0) - (0.6 if mode == "swim" else 0.0), sin(phase * TAU) * 0.08 * minf(amp, 1.0) + spine_yaw * 0.3, 0.0)
	_rot(_b("spine"), spine_pitch * 0.4 + breath * 0.5, spine_yaw * 0.35 - sin(phase * TAU) * 0.08 * minf(amp, 1.0), 0.0)
	_rot(_b("chest"), spine_pitch * 0.3 + (0.6 if mode == "swim" else 0.0), spine_yaw * 0.35, 0.0)
	var lk := look
	if aiming:
		lk = Vector2(-spine_yaw * 0.9, aim_pitch)
	_rot(_b("neck1"), -lk.y * 0.4, lk.x * 0.4, 0.0)
	_rot(_b("head"), -lk.y * 0.6, lk.x * 0.6, 0.0)
	var rb := _b("root")
	if rb >= 0:
		skel.set_bone_pose_rotation(rb, Quaternion.from_euler(Vector3(root_pitch, 0, 0)))
		skel.set_bone_pose_position(rb, Vector3(0, -root_drop * 0.0, 0))


# ------------------------------------------------------------------ death / sleep overlays
func _apply_death_and_sleep() -> void:
	var rb := _b("root")
	if rb < 0:
		return
	if gait == "human" and action == "dodge":
		return
	var d := smoothstep(0.0, 1.0, dead_t)
	var sl := smoothstep(0.0, 1.0, sleep_t)
	if d <= 0.0 and sl <= 0.0:
		if gait != "human":
			skel.set_bone_pose_rotation(rb, Quaternion.IDENTITY)
			skel.set_bone_pose_position(rb, Vector3.ZERO)
		return
	if gait in ["swim", "serpent"]:
		skel.set_bone_pose_rotation(rb, Quaternion.from_euler(Vector3(0, 0, PI * d)))
		return
	var roll := d * 1.45
	var drop := hip_h * (0.55 * d + 0.45 * sl)
	if gait == "human":
		skel.set_bone_pose_rotation(rb, Quaternion.from_euler(Vector3(-d * 1.5, 0, 0)))
		skel.set_bone_pose_position(rb, Vector3(0, d * hip_h * 0.15, 0))
		return
	skel.set_bone_pose_rotation(rb, Quaternion.from_euler(Vector3(0, 0, roll)))
	skel.set_bone_pose_position(rb, Vector3(0, -drop * (1.0 - d * 0.6), 0))
	# fold legs when sleeping
	if sl > 0.0:
		for side in ["L", "R"]:
			var leg := _chain("leg_" + side)
			if leg.size() >= 4:
				_rot(leg[0], 0.9 * sl, 0, 0)
				_rot(leg[1], -1.6 * sl, 0, 0)
				_rot(leg[2], 1.2 * sl, 0, 0)
			var arm := _chain("arm_" + side)
			if arm.size() >= 4 and gait == "quad":
				_rot(arm[0], -0.6 * sl, 0, 0)
				_rot(arm[1], 1.5 * sl, 0, 0)
		var neck := _chain("neck")
		for bi in neck:
			_rot(bi, 0.25 * sl, 0.15 * sl, 0)
