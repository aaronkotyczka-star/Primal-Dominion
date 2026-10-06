class_name CameraRig
extends Node3D
## Third-person (spring arm, over-shoulder aim) and first-person camera with shake and target lock.

var yaw := 0.0
var pitch := -0.15
var first_person := false
var arm: SpringArm3D
var cam: Camera3D
var target_node: Node3D
var lock_target: Node3D = null
var aiming := false
var base_len := 3.4
var extra_len := 0.0
var _shake := 0.0
var _height := 1.6
var fp_height := 1.65


func _ready() -> void:
	arm = SpringArm3D.new()
	arm.collision_mask = 1 | 8 | 64
	arm.margin = 0.2
	add_child(arm)
	var sh := SphereShape3D.new()
	sh.radius = 0.25
	arm.shape = sh
	cam = Camera3D.new()
	cam.near = 0.08
	cam.far = 3500.0
	cam.set_script(null)
	arm.add_child(cam)
	cam.current = true
	cam.add_to_group("main_camera")
	cam.set_meta("rig", self)


func shake(amount: float) -> void:
	if Settings.get_v("camera_shake"):
		_shake = minf(1.0, _shake + amount)


func rotate_input(d: Vector2) -> void:
	var sens: float = float(Settings.get_v("mouse_sens")) * 0.01
	yaw -= d.x * sens
	var inv := -1.0 if Settings.get_v("invert_y") else 1.0
	pitch = clampf(pitch - d.y * sens * inv, deg_to_rad(-80), deg_to_rad(70))


func update_rig(delta: float, follow_pos: Vector3, height: float) -> void:
	_height = lerpf(_height, height, clampf(delta * 8.0, 0.0, 1.0))
	if lock_target and is_instance_valid(lock_target) and not lock_target.combatant.dead:
		var to = lock_target.global_position + Vector3.UP * (lock_target.get_body_height() * 0.5 if lock_target.has_method("get_body_height") else 1.0) - (follow_pos + Vector3.UP * _height)
		var want_yaw := atan2(-to.x, -to.z)
		yaw = lerp_angle(yaw, want_yaw, clampf(delta * 6.0, 0.0, 1.0))
		var want_pitch := clampf(atan2(to.y, Vector2(to.x, to.z).length()) - 0.12, -0.8, 0.4)
		pitch = lerpf(pitch, want_pitch, clampf(delta * 4.0, 0.0, 1.0))
	elif lock_target and (not is_instance_valid(lock_target) or lock_target.combatant.dead):
		lock_target = null
	global_position = follow_pos + Vector3(0, fp_height if first_person else _height, 0)
	rotation = Vector3(pitch, yaw, 0)
	cam.fov = lerpf(cam.fov, float(Settings.get_v("fov")) * (0.65 if aiming else 1.0), clampf(delta * 10.0, 0.0, 1.0))
	if first_person:
		arm.spring_length = 0.0
		arm.position = Vector3.ZERO
	else:
		var want_len := (1.7 if aiming else base_len) + extra_len
		arm.spring_length = lerpf(arm.spring_length, want_len, clampf(delta * 8.0, 0.0, 1.0))
		arm.position = arm.position.lerp(Vector3(0.6 if aiming else 0.35, 0.15, 0), clampf(delta * 8.0, 0.0, 1.0))
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - delta * 2.0)
		var s := _shake * _shake * 0.3
		cam.h_offset = randf_range(-s, s)
		cam.v_offset = randf_range(-s, s)
	else:
		cam.h_offset = 0.0
		cam.v_offset = 0.0
	Audio.listener_pos = cam.global_position


func forward_flat() -> Vector3:
	return Vector3(-sin(yaw), 0, -cos(yaw))


func right_flat() -> Vector3:
	return Vector3(cos(yaw), 0, -sin(yaw))


func aim_ray(max_dist: float = 300.0, exclude: Array = []) -> Dictionary:
	var vp := cam.get_viewport()
	var center := vp.get_visible_rect().size * 0.5
	var from := cam.project_ray_origin(center)
	var dir := cam.project_ray_normal(center)
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * max_dist, 1 | 2 | 4 | 8 | 64)
	q.exclude = exclude
	var res := get_world_3d().direct_space_state.intersect_ray(q)
	return {"from": from, "dir": dir, "hit": res, "point": res["position"] if res else from + dir * max_dist}
