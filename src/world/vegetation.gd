class_name Vegetation
extends Node3D
## Chunked MultiMesh vegetation with LODs, harvesting and on-demand colliders near the player.

const CHUNK := 128.0
const TYPES_HARVEST := {
	"tree_conifer": {"hp": 100, "yield": [["wood", 3], ["fiber", 1]], "tool": "wood"},
	"tree_broad": {"hp": 100, "yield": [["wood", 3], ["fiber", 1]], "tool": "wood"},
	"tree_palm": {"hp": 70, "yield": [["wood", 2], ["fiber", 2]], "tool": "wood"},
	"tree_jungle": {"hp": 160, "yield": [["wood", 3], ["hardwood", 1]], "tool": "wood"},
	"tree_swamp": {"hp": 90, "yield": [["wood", 2], ["fiber", 2]], "tool": "wood"},
	"tree_dead": {"hp": 50, "yield": [["wood", 2]], "tool": "wood"},
	"bush": {"hp": 20, "yield": [["fiber", 3], ["berries", 1]], "tool": "hand"},
	"berry_bush": {"hp": 25, "yield": [["berries", 4], ["narcoberry", 1], ["fiber", 1]], "tool": "hand", "rare": ["rare_flower", 0.06]},
	"fern": {"hp": 10, "yield": [["fiber", 3]], "tool": "hand", "rare": ["herb_healing", 0.25]},
	"reed": {"hp": 10, "yield": [["fiber", 3], ["thatch", 1]], "tool": "hand"},
	"cactus": {"hp": 30, "yield": [["fiber", 3]], "tool": "hand"},
	"rock_small": {"hp": 60, "yield": [["stone", 3], ["flint", 1]], "tool": "stone"},
	"rock_large": {"hp": 220, "yield": [["stone", 4], ["flint", 2]], "tool": "stone", "rare": ["metal_ore", 0.2]},
	"crystal_corrupt": {"hp": 80, "yield": [["rift_shard", 1], ["demon_essence", 1]], "tool": "stone"},
	"tree_broad_b": {"hp": 130, "yield": [["wood", 4], ["fiber", 1]], "tool": "wood"},
	"tree_broad_c": {"hp": 80, "yield": [["wood", 3], ["fiber", 1]], "tool": "wood"},
	"tree_conifer_b": {"hp": 150, "yield": [["wood", 4], ["fiber", 1]], "tool": "wood"},
	"tree_conifer_c": {"hp": 60, "yield": [["wood", 2], ["fiber", 1]], "tool": "wood"},
	"rock_small_b": {"hp": 45, "yield": [["stone", 2], ["flint", 1]], "tool": "stone"},
	"rock_medium": {"hp": 130, "yield": [["stone", 4], ["flint", 1]], "tool": "stone", "rare": ["metal_ore", 0.1]},
	"log": {"hp": 70, "yield": [["wood", 4]], "tool": "wood", "rare": ["mushroom", 0.3]},
	"stump": {"hp": 50, "yield": [["wood", 2]], "tool": "wood", "rare": ["mushroom", 0.2]},
}
## approximate footprint radius (m, at scale 1) for interaction and colliders
const RADIUS := {"rock_small": 0.75, "rock_small_b": 0.55, "rock_medium": 1.7, "rock_large": 3.6, "rock_spire": 2.6,
	"boulder": 7.5, "tree_jungle": 0.85, "tree_broad_b": 0.6, "tree_broad_c": 0.3, "tree_conifer_b": 0.5,
	"tree_conifer_c": 0.22, "stump": 0.55, "log": 0.45, "cactus": 0.4, "crystal_corrupt": 0.8}
const LOD := {
	"tree_conifer": [70.0, 900.0], "tree_broad": [70.0, 900.0], "tree_palm": [60.0, 700.0], "tree_jungle": [80.0, 1000.0],
	"tree_swamp": [60.0, 700.0], "tree_dead": [50.0, 500.0], "bush": [40.0, 160.0], "berry_bush": [40.0, 160.0],
	"fern": [30.0, 90.0], "reed": [30.0, 90.0], "cactus": [50.0, 400.0], "rock_small": [50.0, 260.0],
	"rock_large": [90.0, 1200.0], "crystal_corrupt": [60.0, 400.0],
	"tree_broad_b": [70.0, 900.0], "tree_broad_c": [70.0, 900.0], "tree_conifer_b": [80.0, 1100.0],
	"tree_conifer_c": [60.0, 600.0], "rock_medium": [70.0, 600.0], "rock_small_b": [40.0, 200.0],
	"rock_spire": [120.0, 1500.0], "boulder": [150.0, 1600.0], "log": [50.0, 300.0], "stump": [40.0, 220.0],
}

var types: Array = []
var records := PackedFloat32Array()
var count := 0
var chunk_map := {} # "cx,cz" -> {type -> [indices]}
var mm_lookup := {} # idx -> [mmi0, mmi1, local]
var hp := {} # idx -> hp left
var col_chunks := {} # key -> StaticBody3D
var _col_center := Vector2i(999999, 999999)
var quality := 2
var view_mult := 1.0


func build(q: int, view: float = 1.0) -> void:
	quality = q
	view_mult = view
	WorldData.ensure_loaded()
	types = WorldData.info["vegetation_types"]
	var f := FileAccess.open("res://assets/world/veg.bin", FileAccess.READ)
	records = f.get_buffer(f.get_length()).to_float32_array()
	count = records.size() / 6
	var harvested: Dictionary = GameState.state["world"]["harvested"]
	for i in count:
		var t := int(records[i * 6])
		var key := _ck(records[i * 6 + 1], records[i * 6 + 3])
		if not chunk_map.has(key):
			chunk_map[key] = {}
		var cm: Dictionary = chunk_map[key]
		if not cm.has(t):
			cm[t] = []
		cm[t].append(i)
	for key in chunk_map:
		for t in chunk_map[key]:
			_build_mm(key, t, chunk_map[key][t])
	for k in harvested.keys():
		if _respawned(harvested[k]):
			harvested.erase(k)
		else:
			_hide(int(k))


func _ck(x: float, z: float) -> String:
	return "%d,%d" % [int(floor(x / CHUNK)), int(floor(z / CHUNK))]


func _xf(i: int) -> Transform3D:
	var o := i * 6
	var s := records[o + 5]
	var b := Basis(Vector3.UP, records[o + 4]).scaled(Vector3(s, s, s))
	return Transform3D(b, Vector3(records[o + 1], records[o + 2] - 0.15 * s, records[o + 3]))


func _build_mm(key: String, t: int, idxs: Array) -> void:
	var tname: String = types[t]
	var ranges: Array = LOD.get(tname, [60.0, 400.0])
	var far: float = ranges[1] * view_mult * (0.7 if quality == 0 else 1.0)
	var near: float = ranges[0] * (0.7 if quality == 0 else (1.3 if quality >= 3 else 1.0))
	var mmis := []
	for lod in 2:
		var mesh := FloraLibrary.mesh(tname, lod)
		if mesh == null:
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = idxs.size()
		for j in idxs.size():
			mm.set_instance_transform(j, _xf(idxs[j]))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.visibility_range_begin = 0.0 if lod == 0 else near
		mmi.visibility_range_end = near if lod == 0 else far
		mmi.visibility_range_begin_margin = 0.0
		mmi.visibility_range_end_margin = 8.0
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		var big := tname.begins_with("tree") or tname == "rock_large"
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if (lod == 0 or (big and quality >= 2)) else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if tname in ["fern", "reed", "bush"] and quality < 2:
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)
		mmis.append(mmi)
	for j in idxs.size():
		mm_lookup[idxs[j]] = [mmis, j]


func type_of(i: int) -> String:
	return types[int(records[i * 6])]


func pos_of(i: int) -> Vector3:
	return Vector3(records[i * 6 + 1], records[i * 6 + 2], records[i * 6 + 3])


func scale_of(i: int) -> float:
	return records[i * 6 + 5]


func _hide(i: int) -> void:
	if not mm_lookup.has(i):
		return
	var e: Array = mm_lookup[i]
	for mmi in e[0]:
		(mmi as MultiMeshInstance3D).multimesh.set_instance_transform(e[1], Transform3D(Basis().scaled(Vector3.ONE * 0.0001), Vector3(0, -500, 0)))
	_col_center = Vector2i(999999, 999999)


func _show(i: int) -> void:
	if not mm_lookup.has(i):
		return
	var e: Array = mm_lookup[i]
	for mmi in e[0]:
		(mmi as MultiMeshInstance3D).multimesh.set_instance_transform(e[1], _xf(i))
	_col_center = Vector2i(999999, 999999)


func _respawned(h: Dictionary) -> bool:
	var day := GameState.get_day() + GameState.get_hour() / 24.0
	return day >= float(h.get("respawn", 0.0))


func is_harvested(i: int) -> bool:
	return GameState.state["world"]["harvested"].has(str(i))


func nearest(pos: Vector3, dir: Vector3, rng: float, filter_hand: bool = false) -> int:
	var best := -1
	var bd := 1e9
	var cx := int(floor(pos.x / CHUNK))
	var cz := int(floor(pos.z / CHUNK))
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var key := "%d,%d" % [cx + dx, cz + dz]
			if not chunk_map.has(key):
				continue
			for t in chunk_map[key]:
				var tname: String = types[t]
				if not TYPES_HARVEST.has(tname):
					continue
				if filter_hand and TYPES_HARVEST[tname]["tool"] != "hand" and not tname.begins_with("tree"):
					continue
				for i in chunk_map[key][t]:
					if is_harvested(i):
						continue
					var p := pos_of(i)
					var to := p - pos
					to.y = 0
					var r := float(RADIUS.get(tname, 0.5)) * 0.7 * scale_of(i)
					var d := to.length() - r
					if d > rng:
						continue
					if dir != Vector3.ZERO and to.length() > 0.5 and dir.dot(to.normalized()) < 0.2:
						continue
					if d < bd:
						bd = d
						best = i
	return best


## Returns list of [item, n] harvested
func harvest(i: int, tool_stats: Dictionary, by_hand: bool) -> Array:
	var tname := type_of(i)
	var hd: Dictionary = TYPES_HARVEST.get(tname, {})
	if hd.is_empty():
		return []
	var tool: String = hd["tool"]
	var power := 1.0
	match tool:
		"wood":
			power = float(tool_stats.get("harvest_wood", 0.6 if not by_hand else 0.35))
		"stone":
			power = float(tool_stats.get("harvest_stone", 0.5 if not by_hand else 0.0))
		"hand":
			power = 1.5
	if power <= 0.0:
		EventBus.notify.emit("Dafür brauchst du ein Werkzeug (Spitzhacke oder Axt).", "warn")
		return []
	if not hp.has(i):
		hp[i] = float(hd["hp"]) * scale_of(i)
	hp[i] -= 25.0 * power
	var out := []
	var gather := 1.0 + 0.25 * GameState.skill_rank("surv_forage")
	for y in hd["yield"]:
		var n := int(round(y[1] * power * gather * randf_range(0.6, 1.2)))
		if tname.begins_with("tree") and y[0] == "wood" and not by_hand:
			n = maxi(n, 1)
		if n > 0:
			out.append([y[0], n])
	if hd.has("rare") and randf() < float(hd["rare"][1]) * power:
		out.append([hd["rare"][0], 1])
	if tool == "stone" and float(tool_stats.get("harvest_ore", 0.0)) > 0.0 and WorldData.biome_at(pos_of(i).x, pos_of(i).z) in [6, 7, 8] and randf() < 0.35:
		out.append(["metal_ore", 1])
	var p := pos_of(i)
	Audio.play_at("chop" if tool == "wood" else ("mine" if tool == "stone" else "pickup"), p + Vector3.UP, -2.0)
	Fx.burst(p + Vector3.UP * (1.2 if tool != "hand" else 0.6), Color(0.45, 0.35, 0.22) if tool == "wood" else (Color(0.5, 0.5, 0.48) if tool == "stone" else Color(0.3, 0.5, 0.2)), self, 10, 0.08, 2.0)
	if hp[i] <= 0.0:
		hp.erase(i)
		var days := 1.5 if tool == "hand" else (3.0 if tool == "wood" else 4.0)
		GameState.state["world"]["harvested"][str(i)] = {"respawn": GameState.get_day() + GameState.get_hour() / 24.0 + days}
		_hide(i)
		if tname.begins_with("tree"):
			Audio.play_at("footstep_heavy", p, 2.0, 0.7, 2.0)
	return out


func process_respawns() -> void:
	var harvested: Dictionary = GameState.state["world"]["harvested"]
	for k in harvested.keys():
		if _respawned(harvested[k]):
			harvested.erase(k)
			_show(int(k))


func update_colliders(center: Vector3) -> void:
	var c := Vector2i(int(floor(center.x / CHUNK)), int(floor(center.z / CHUNK)))
	if c == _col_center:
		return
	_col_center = c
	var want := {}
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			want["%d,%d" % [c.x + dx, c.y + dz]] = true
	for k in col_chunks.keys():
		col_chunks[k].queue_free()
		col_chunks.erase(k)
	for k in want:
		if not chunk_map.has(k):
			continue
		var body := StaticBody3D.new()
		body.collision_layer = 64
		body.collision_mask = 0
		add_child(body)
		col_chunks[k] = body
		for t in chunk_map[k]:
			var tname: String = types[t]
			if not (tname.begins_with("tree") or tname.begins_with("rock") or tname in ["cactus", "crystal_corrupt", "boulder", "log", "stump"]):
				continue
			for i in chunk_map[k][t]:
				if is_harvested(i):
					continue
				var cs := CollisionShape3D.new()
				var s := scale_of(i)
				var rad: float = float(RADIUS.get(tname, 0.38)) * s
				if tname.begins_with("rock") or tname == "boulder":
					var sh := SphereShape3D.new()
					sh.radius = rad
					cs.shape = sh
					cs.position = pos_of(i) + Vector3(0, rad * (1.6 if tname == "rock_spire" else 0.35), 0)
				elif tname == "log":
					var cap := CapsuleShape3D.new()
					cap.radius = rad
					cap.height = 7.0 * s
					cs.shape = cap
					cs.rotation = Vector3(PI * 0.5, records[i * 6 + 4], 0)
					cs.position = pos_of(i) + Vector3(0, rad, 0)
				else:
					var cy := CylinderShape3D.new()
					cy.radius = rad
					cy.height = (1.0 if tname == "stump" else 6.0) * s
					cs.shape = cy
					cs.position = pos_of(i) + Vector3(0, cy.height * 0.5, 0)
				body.add_child(cs)
