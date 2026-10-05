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
	var views := [
		["01_start_tps", p.global_position, -0.2, 0.0, false, 9.0],
		["02_start_fps", p.global_position, -0.05, 2.5, true, 9.0],
		["03_morgengrau", WorldData.poi_pos("morgengrau") + Vector3(30, 0, 30), -0.25, 0.8, false, 10.0],
		["04_forest", WorldData.poi_pos("alte_warte") + Vector3(-40, 0, 20), -0.15, 2.0, false, 15.0],
		["05_jungle_moosfell", WorldData.poi_pos("moosfell") + Vector3(35, 0, -25), -0.2, -2.2, false, 13.0],
		["06_mountains", Vector3(60, 0, -250), -0.1, 3.14, false, 7.0],
		["07_night", WorldData.poi_pos("morgengrau") + Vector3(-20, 0, 20), -0.15, -0.6, false, 23.0],
		["08_rift", WorldData.poi_pos("riss_narbenschlund") + Vector3(0, 0, 110), -0.15, 0.0, false, 21.0],
		["09_dinos", WorldData.poi_pos("start_beach") + Vector3(-60, 0, -120), -0.12, 0.6, false, 10.0],
	]
	for v in views:
		var pos: Vector3 = v[1]
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
					c.ai.set_physics_process(false)
			for i in 90:
				await tree.process_frame
		if v[0] == "01_start_tps":
			for sp in ["raptor", "triceratops", "parasaurolophus"]:
				w.spawn_wild(sp, 5, pos + p.rig.forward_flat() * (14.0 + randf() * 10.0) + p.rig.right_flat() * randf_range(-8, 8), {})
			for i in 60:
				await tree.process_frame
		ui.close_all()
		await tree.process_frame
		tree.root.get_texture().get_image().save_png(dir + "/" + v[0] + ".png")
		print("SHOT ", v[0])
	tree.quit()
