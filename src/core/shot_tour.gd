class_name ShotTour
extends RefCounted
## Automated screenshot tour for visual verification (used by CI/dev: --shots=<dir>).

static func run(main: Node, dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	var w: World = main.world
	var tree := main.get_tree()
	var ui: GameUI = main.ui
	ui.close_all()
	var p := w.player
	p.combatant.dmg_taken_mult = 0.0
	Settings.data["tutorial_hints"] = false
	var showcase := []
	var views := [
		["01_start_tps", p.global_position, -0.2, 0.0, false, 9.0],
		["02_start_fps", p.global_position, -0.05, 2.5, true, 9.0],
		["03_morgengrau", WorldData.poi_pos("morgengrau"), -0.25, 0.0, false, 10.0, [45.0, 90.0]],
		["04_forest", WorldData.poi_pos("alte_warte"), -0.15, 0.0, false, 15.0, [35.0, 80.0]],
		["05_jungle_moosfell", WorldData.poi_pos("moosfell"), -0.2, 0.0, false, 13.0, [50.0, 95.0]],
		["06_mountains", WorldData.poi_pos("adlerhorst"), -0.05, 0.0, false, 7.0, [160.0, 260.0]],
		["07_night", WorldData.poi_pos("morgengrau"), -0.15, 0.0, false, 23.0, [35.0, 70.0]],
		["08_rift", WorldData.poi_pos("riss_narbenschlund"), -0.15, 0.0, false, 21.0, [110.0, 170.0]],
		["09_dinos", WorldData.poi_pos("start_beach") + Vector3(-60, 0, -120), -0.12, 0.6, false, 10.0],
	]
	var sky = w.get("sky")
	if sky:
		sky.force_weather("clear")
	var only := OS.get_environment("SHOTS")
	for v in views:
		if only != "" and not String(v[0]).substr(0, 2) in only.split(","):
			continue
		var pos: Vector3 = v[1]
		if v.size() > 6:
			var vp := _vantage(w, pos, v[6][0], v[6][1])
			pos = vp[0]
			v[3] = vp[1]
		if v[0] == "09_dinos":
			pos = _open_spot(w, pos, 400.0)
		pos.y = WorldData.height_at(pos.x, pos.z) + 1.0
		p.global_position = pos
		p.velocity = Vector3.ZERO
		p.rig.pitch = v[2]
		p.rig.yaw = v[3]
		p.rig.first_person = v[4]
		p.visual.set_shadow_only(v[4])
		GameState.state["time"]["hour"] = v[5]
		for i in 90:
			await tree.process_frame
		# spawn showcase creatures near the camera
		if v[0] == "09_dinos":
			var specs := [["trex", 22.0, -6.0], ["triceratops", 16.0, 7.0], ["stegosaurus", 30.0, 12.0], ["raptor", 9.0, -2.0]]
			for sp in specs:
				var c = w.spawn_wild(sp[0], 8, pos + p.rig.forward_flat() * sp[1] + p.rig.right_flat() * sp[2], {})
				if c:
					c.rotation.y = p.rig.yaw + PI * 0.5
					c.velocity = Vector3.ZERO
					c.set_physics_process(false)
					showcase.append(c)
			for i in 90:
				await tree.process_frame
		if v[0] == "01_start_tps":
			for sp in ["raptor", "triceratops", "parasaurolophus"]:
				showcase.append(w.spawn_wild(sp, 5, pos + p.rig.forward_flat() * (14.0 + randf() * 10.0) + p.rig.right_flat() * randf_range(-8, 8), {}))
			for i in 60:
				await tree.process_frame
		ui.close_all()
		await tree.process_frame
		tree.root.get_texture().get_image().save_png(dir + "/" + v[0] + ".png")
		print("SHOT ", v[0])
		for c in showcase:
			if c and is_instance_valid(c):
				c.queue_free()
		showcase.clear()
	tree.quit()


## Picks an elevated, fairly flat spot on a ring around `target` and the yaw that faces it.
static func _vantage(w: Node, target: Vector3, rmin: float, rmax: float) -> Array:
	var ty := WorldData.height_at(target.x, target.z)
	var best := [target + Vector3(rmin, 0, 0), 0.0]
	var best_score := -1e9
	for ri in 3:
		var r := lerpf(rmin, rmax, ri / 2.0)
		for ai in 24:
			var a := TAU * ai / 24.0
			var p := target + Vector3(cos(a) * r, 0, sin(a) * r)
			var h := WorldData.height_at(p.x, p.z)
			if h < 1.5:
				continue
			var slope := 0.0
			for o in [Vector2(3, 0), Vector2(-3, 0), Vector2(0, 3), Vector2(0, -3)]:
				slope = maxf(slope, absf(WorldData.height_at(p.x + o.x, p.z + o.y) - h) / 3.0)
			var score := (h - ty) * 0.6 - slope * 40.0 - r * 0.05
			# keep the camera line free: no trees/rocks next to the player or behind it
			var d0 := (target - p).normalized()
			for back in [0.0, 4.0, 8.0]:
				if w.vegetation.nearest(p - d0 * back, Vector3.ZERO, 4.0) != -1:
					score -= 25.0
			if score > best_score:
				best_score = score
				var d := target - p
				best = [p, atan2(-d.x, -d.z)]
	return best


## Finds a flat meadow spot without trees/rocks within ~35 m (for creature showcase shots).
static func _open_spot(w: Node, center: Vector3, radius: float) -> Vector3:
	var best := center
	var best_score := -1e9
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 400:
		var p := center + Vector3(rng.randf_range(-radius, radius), 0, rng.randf_range(-radius, radius))
		var h := WorldData.height_at(p.x, p.z)
		if h < 2.0 or WorldData.biome_at(p.x, p.z) != 2:
			continue
		var slope := 0.0
		for o in [Vector2(6, 0), Vector2(-6, 0), Vector2(0, 6), Vector2(0, -6), Vector2(20, 0), Vector2(0, -20)]:
			slope = maxf(slope, absf(WorldData.height_at(p.x + o.x, p.z + o.y) - h) / o.length())
		if slope > 0.18:
			continue
		var clear := 0.0
		for o2 in [Vector3.ZERO, Vector3(0, 0, -15), Vector3(0, 0, -30), Vector3(10, 0, -20), Vector3(-10, 0, -20)]:
			if w.vegetation.nearest(p + o2, Vector3.ZERO, 7.0) == -1:
				clear += 1.0
		var score := clear * 10.0 - slope * 50.0
		if score > best_score:
			best_score = score
			best = p
	return best
