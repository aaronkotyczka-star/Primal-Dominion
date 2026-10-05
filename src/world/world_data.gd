class_name WorldData
extends RefCounted
## Static access to generated world data: heights, biomes, POIs, regions.

const SEA_LEVEL := 0.0
static var loaded := false
static var n := 1025
static var extent := 1024.0
static var cell := 2.0
static var heights := PackedFloat32Array()
static var biome_img: Image
static var info: Dictionary = {}
static var biome_names: Array = []


static func ensure_loaded() -> void:
	if loaded:
		return
	var f := FileAccess.open("res://assets/world/world.json", FileAccess.READ)
	info = JSON.parse_string(f.get_as_text())
	n = int(info["size"])
	extent = float(info["extent"])
	cell = float(info["cell"])
	biome_names = info["biome_names"]
	var hf := FileAccess.open("res://assets/world/height.f32", FileAccess.READ)
	heights = hf.get_buffer(hf.get_length()).to_float32_array()
	var bt: Texture2D = load("res://assets/world/biome.png")
	biome_img = bt.get_image()
	if biome_img.is_compressed():
		biome_img.decompress()
	loaded = true


static func height_at(x: float, z: float) -> float:
	var fx := clampf((x + extent) / cell, 0.0, n - 1.001)
	var fz := clampf((z + extent) / cell, 0.0, n - 1.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var i0 := iz * n + ix
	var a := lerpf(heights[i0], heights[i0 + 1], tx)
	var b := lerpf(heights[i0 + n], heights[i0 + n + 1], tx)
	return lerpf(a, b, tz)


static func normal_at(x: float, z: float) -> Vector3:
	var e := cell
	var hx := height_at(x + e, z) - height_at(x - e, z)
	var hz := height_at(x, z + e) - height_at(x, z - e)
	return Vector3(-hx, 2.0 * e, -hz).normalized()


static func biome_at(x: float, z: float) -> int:
	var w := biome_img.get_width()
	var px := clampi(int((x + extent) / (2.0 * extent) * w), 0, w - 1)
	var pz := clampi(int((z + extent) / (2.0 * extent) * w), 0, w - 1)
	return int(round(biome_img.get_pixel(px, pz).r * 255.0))


static func biome_name(x: float, z: float) -> String:
	return biome_names[biome_at(x, z)]


static func poi(id: String) -> Dictionary:
	return info["pois"].get(id, {})


static func poi_pos(id: String) -> Vector3:
	var p := poi(id)
	if p.is_empty():
		return Vector3.ZERO
	return Vector3(p["x"], height_at(p["x"], p["z"]), p["z"])


static func region_at(x: float, z: float) -> Dictionary:
	## Best matching land region (smallest containing), water regions if in sea.
	var best := {}
	var best_r := 1e9
	var in_water := height_at(x, z) < -1.0
	for r in info["regions"]:
		var is_water: bool = r.get("water", false)
		if is_water != in_water:
			continue
		if is_water and r.get("deep", false) != (height_at(x, z) < -30.0):
			continue
		var d := Vector2(x - r["x"], z - r["z"]).length()
		if d < r["r"] and r["r"] < best_r:
			best = r
			best_r = r["r"]
	return best


static func is_water(x: float, z: float) -> bool:
	return height_at(x, z) < SEA_LEVEL - 0.3
