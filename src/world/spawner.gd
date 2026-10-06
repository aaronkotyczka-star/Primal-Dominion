class_name Spawner
extends Node
## Keeps a living population of wild creatures around the player based on regions, time and weather.

var world: Node3D
var target_count := 18
var _t := 0.0
var _herd_seq := 1
var _event_t := 600.0
var rng := RandomNumberGenerator.new()
const SOCIAL_GROUP := {"herd": [3, 6], "pack": [2, 4], "flock": [3, 5], "pod": [2, 3], "solitary": [1, 1]}


func setup(w: Node3D, quality: int) -> void:
	world = w
	rng.randomize()
	target_count = [10, 15, 20, 26][clampi(quality, 0, 3)]


func _process(delta: float) -> void:
	if world == null or world.player == null:
		return
	_t -= delta
	_event_t -= delta
	if _event_t <= 0.0:
		_event_t = rng.randf_range(900.0, 1500.0)
		_migration_event()
	if _t > 0.0:
		return
	_t = 1.5
	var pp: Vector3 = world.player.global_position
	var n := 0
	for c in get_tree().get_nodes_in_group("creatures"):
		if not c.wild:
			continue
		var d: float = c.global_position.distance_to(pp)
		if d > 320.0 and not c.is_boss and c.quest_tag == "" and c.nest_guard == Vector3.INF:
			c.queue_free()
		elif d < 230.0:
			n += 1
	if n < target_count:
		_spawn_group(pp)


func _spawn_group(pp: Vector3) -> void:
	var sky: SkyWeather = world.sky
	for attempt in 6:
		var a := rng.randf() * TAU
		var r := rng.randf_range(95.0, 190.0)
		var p := pp + Vector3(cos(a) * r, 0, sin(a) * r)
		if absf(p.x) > 980 or absf(p.z) > 980:
			continue
		if world.is_no_spawn(p):
			continue
		var reg := WorldData.region_at(p.x, p.z)
		if reg.is_empty():
			continue
		var spawns: Dictionary = reg["spawns"].duplicate()
		# night & storms: demons wander further
		if sky and (sky.weather == "demon_storm" or (sky.is_night() and rng.randf() < 0.15)) and not reg.get("water", false):
			spawns["hellhound"] = 2 if sky.weather == "demon_storm" else 1
		var sp_id := _weighted(spawns)
		if sp_id == "":
			continue
		var sp := DB.species(sp_id)
		var h := WorldData.height_at(p.x, p.z)
		var is_aquatic: bool = sp.get("family", "") in ["marine", "fish"]
		if is_aquatic and h > -4.0:
			continue
		if not is_aquatic and h < 0.5:
			continue
		if not is_aquatic and WorldData.normal_at(p.x, p.z).y < 0.7:
			continue
		var lv: Array = reg["levels"]
		var grp: Array = SOCIAL_GROUP.get(sp.get("social", "solitary"), [1, 1])
		var count := rng.randi_range(int(grp[0]), int(grp[1]))
		var herd := 0
		if count > 1:
			herd = _herd_seq
			_herd_seq += 1
		var leader: Creature = null
		var corrupted := WorldData.biome_at(p.x, p.z) == 10 or (sky and sky.weather == "demon_storm" and rng.randf() < 0.4)
		for i in count:
			var q := p + Vector3(rng.randf_range(-8, 8), 0, rng.randf_range(-8, 8))
			var level := rng.randi_range(int(lv[0]), int(lv[1]))
			var variant := {}
			if rng.randf() < 0.025 and int(lv[1]) >= 8 and i == 0:
				variant["alpha"] = true
				level = mini(level + 5, 60)
			if corrupted and not sp.get("temper", "") == "demonic" and rng.randf() < 0.5:
				variant["corrupted"] = true
			var c: Creature = world.spawn_wild(sp_id, level, q, variant)
			if c:
				c.herd_id = herd
				if leader == null:
					leader = c
				else:
					c.ai.leader = leader
		return


func _weighted(d: Dictionary) -> String:
	var total := 0.0
	for k in d:
		total += float(d[k])
	if total <= 0.0:
		return ""
	var r := rng.randf() * total
	for k in d:
		r -= float(d[k])
		if r <= 0.0:
			return k
	return d.keys()[0]


func _migration_event() -> void:
	var pp: Vector3 = world.player.global_position
	var reg := WorldData.region_at(pp.x, pp.z)
	if reg.is_empty() or reg.get("water", false):
		return
	var species := "parasaurolophus"
	if reg["id"] in ["knochenebene", "glutsand"]:
		species = "brontosaurus" if rng.randf() < 0.5 else "triceratops"
	elif reg["id"] == "weisszahn":
		species = "mammoth"
	var a := rng.randf() * TAU
	var start := pp + Vector3(cos(a), 0, sin(a)) * 160.0
	var goal := pp - Vector3(cos(a), 0, sin(a)) * 220.0
	if WorldData.height_at(start.x, start.z) < 1.0:
		return
	var herd := _herd_seq
	_herd_seq += 1
	var leader: Creature = null
	for i in rng.randi_range(4, 7):
		var q := start + Vector3(rng.randf_range(-12, 12), 0, rng.randf_range(-12, 12))
		var c: Creature = world.spawn_wild(species, rng.randi_range(int(reg["levels"][0]), int(reg["levels"][1])), q, {})
		if c:
			c.herd_id = herd
			c.ai.home = goal
			c.ai.wander_to = goal
			c.ai._go("wander", 120.0)
			if leader == null:
				leader = c
			else:
				c.ai.leader = leader
	EventBus.notify.emit("Kreaturenwanderung: Eine Herde %s zieht durch %s." % [DB.species(species)["name"], reg["name"]], "info")
