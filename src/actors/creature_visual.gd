class_name CreatureVisual
extends Node3D
## Builds the visible body of a creature/humanoid from a phenotype dictionary:
## {rig, scale, parts:[{id, socket, size, mirror, align}], colors{...}, pattern_type,
##  pattern_scale, corruption, glow, glow_color, tex_scale, use_wrinkle}

var pheno: Dictionary = {}
var inst: Dictionary = {}
var skeleton: Skeleton3D
var meta: Dictionary = {}
var materials: Array = []
var fur_materials: Array = []
var part_nodes: Dictionary = {} # socket -> Node3D
var animator: ProcAnimator
var _hurt := 0.0
var _select := 0.0
var gear_nodes: Dictionary = {}


func setup(p: Dictionary) -> void:
	pheno = p
	for c in get_children():
		c.queue_free()
	part_nodes.clear()
	gear_nodes.clear()
	var holder := Node3D.new()
	holder.name = "Holder"
	add_child(holder)
	var sc: float = p.get("scale", 1.0)
	holder.scale = Vector3.ONE * sc
	inst = RigLibrary.instantiate(p["rig"], holder)
	skeleton = inst["skeleton"]
	meta = inst["meta"]
	materials = inst["materials"]
	fur_materials = inst.get("fur_materials", [])
	for part in p.get("parts", []):
		var node := RigLibrary.attach_part(inst, part["id"], part["socket"], part.get("size", 1.0), part.get("mirror", false))
		if node and part.get("align", "") == "body":
			var pivot: Node3D = node.get_node("Pivot")
			pivot.basis = Basis()
		if node:
			part_nodes[part["socket"]] = node
	apply_colors()
	animator = ProcAnimator.new()
	animator.name = "Animator"
	add_child(animator)
	animator.setup(skeleton, meta, part_nodes)
	# shadows for big creatures; small ones skip for performance
	var mi: MeshInstance3D = inst["mesh_instance"]
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


func apply_colors() -> void:
	var p := pheno
	var col: Dictionary = p.get("colors", {})
	var hh: float = float(meta.get("hip_height", 1.0)) * float(p.get("scale", 1.0))
	var rig_id: String = p.get("rig", "")
	var human := rig_id.begins_with("human")
	for m in materials + fur_materials:
		var sm: ShaderMaterial = m
		sm.set_shader_parameter("human_skin", 1.0 if human else 0.0)
		for k in col:
			var v = col[k]
			if v is Array:
				v = Color(v[0], v[1], v[2])
			elif v is String:
				v = Color(v)
			sm.set_shader_parameter(k, v)
		sm.set_shader_parameter("pattern_type", int(p.get("pattern_type", 1)))
		sm.set_shader_parameter("pattern_scale", float(p.get("pattern_scale", 1.0)))
		sm.set_shader_parameter("corruption", float(p.get("corruption", 0.0)))
		sm.set_shader_parameter("glow", float(p.get("glow", 0.0)))
		if p.has("glow_color"):
			var g = p["glow_color"]
			sm.set_shader_parameter("glow_color", Color(g[0], g[1], g[2]) if g is Array else Color(g))
		sm.set_shader_parameter("tex_scale", float(p.get("tex_scale", 1.6 / sqrt(maxf(0.2, hh)))))
		sm.set_shader_parameter("bump_height", float(p.get("bump_height", 0.006 * sqrt(maxf(0.2, hh)))))
		sm.set_shader_parameter("use_wrinkle", float(p.get("use_wrinkle", 0.0)))
		sm.set_shader_parameter("body_scale", maxf(0.2, hh))
		sm.set_shader_parameter("pupil_slit", 0.0 if rig_id.begins_with("human") or rig_id in ["direwolf", "smilodon", "mammoth", "argentavis"] else 1.0)


func flash_hurt() -> void:
	_hurt = 1.0


func set_selected(v: bool) -> void:
	_select = 0.6 if v else 0.0
	for m in materials + fur_materials:
		m.set_shader_parameter("select_flash", _select)


func _process(delta: float) -> void:
	if _hurt > 0.0:
		_hurt = maxf(0.0, _hurt - delta * 4.0)
		for m in materials + fur_materials:
			m.set_shader_parameter("hurt_flash", _hurt)


## Attach a gear node (weapon/shield) to a socket; replaces existing gear there.
func set_gear(socket: String, node: Node3D, xform: Transform3D = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3.ZERO)) -> void:
	if gear_nodes.has(socket):
		gear_nodes[socket].queue_free()
		gear_nodes.erase(socket)
	if node == null:
		return
	var st := RigLibrary.socket_transform(meta, socket)
	if st.is_empty():
		node.queue_free()
		return
	var att := BoneAttachment3D.new()
	att.bone_name = st["bone"]
	skeleton.add_child(att)
	var pivot := Node3D.new()
	att.add_child(pivot)
	pivot.position = (st["local"] as Transform3D).origin
	if String(node.get_meta("wtype", "")) == "shield":
		# worn on the outside of the forearm, face pointing outward (never through arm or body)
		var sg := -1.0 if socket.ends_with("_L") else 1.0
		xform = Transform3D(Basis(Vector3.UP, sg * PI * 0.5), Vector3(sg * 0.17, -0.02, 0.0))
	node.transform = xform
	pivot.add_child(node)
	gear_nodes[socket] = att


func set_shadow_only(v: bool) -> void:
	for n in find_children("*", "GeometryInstance3D", true, false):
		(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if v else GeometryInstance3D.SHADOW_CASTING_SETTING_ON


func get_socket_global(socket: String) -> Vector3:
	var st := RigLibrary.socket_transform(meta, socket)
	if st.is_empty():
		return global_position
	var bi := skeleton.find_bone(st["bone"])
	var bt := skeleton.global_transform * skeleton.get_bone_global_pose(bi)
	return bt * (st["local"] as Transform3D).origin
