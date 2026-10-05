class_name SkyWeather
extends Node3D
## Day/night cycle, sky, lighting, fog and regional weather (incl. demonic storms).

signal weather_changed(kind: String)
signal lightning_strike(pos: Vector3)

const WEATHER_NAMES := {
	"clear": "Klar", "cloudy": "Bewölkt", "rain": "Regen", "storm": "Gewitter", "fog": "Nebel",
	"snow": "Schneefall", "ashfall": "Ascheregen", "sandstorm": "Sandsturm", "demon_storm": "Dämonischer Sturm",
}
# weather probabilities per island kind
const TABLES := {
	"core": {"clear": 4, "cloudy": 3, "rain": 2, "storm": 1, "fog": 1},
	"snow": {"clear": 2, "cloudy": 2, "snow": 4, "fog": 1},
	"volcano": {"clear": 1, "cloudy": 2, "ashfall": 4, "storm": 1},
	"desert": {"clear": 5, "sandstorm": 2, "cloudy": 1},
	"corrupted": {"cloudy": 2, "demon_storm": 3, "fog": 2},
}

var env: Environment
var world_env: WorldEnvironment
var sun: DirectionalLight3D
var moon: DirectionalLight3D
var sky_mat: ShaderMaterial
var rain: GPUParticles3D
var snow: GPUParticles3D
var ash: GPUParticles3D
var weather := "clear"
var weather_t := 0.0 # blend to target
var target := {}
var cur := {"cloud": 0.3, "dark": 0.0, "fog": 0.002, "rain": 0.0, "snow": 0.0, "ash": 0.0, "demon": 0.0, "wet": 0.0, "wind": 0.3}
var next_change_hours := 6.0
var lightning_timer := 0.0
var flash := 0.0
var camera: Camera3D
var region_kind := "core"
var underwater := false
var in_cave := false
var quality := 2
var rng := RandomNumberGenerator.new()


func setup(q: int) -> void:
	quality = q
	rng.randomize()
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = load("res://shaders/sky.gdshader")
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 0.7
	env.ambient_light_color = Color(0.55, 0.6, 0.68)
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.0
	env.tonemap_white = 6.0
	env.fog_enabled = true
	env.fog_light_color = Color(0.55, 0.6, 0.65)
	env.fog_density = 0.0015
	env.fog_sky_affect = 0.35
	env.fog_height = 30.0
	env.fog_height_density = 0.004
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.2
	env.adjustment_enabled = true
	env.adjustment_saturation = 0.92
	env.adjustment_contrast = 1.05
	apply_quality(q)
	world_env = WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 220.0 if q >= 2 else 140.0
	sun.shadow_blur = 1.2
	sun.light_angular_distance = 0.6
	add_child(sun)
	moon = DirectionalLight3D.new()
	moon.name = "Moon"
	moon.light_color = Color(0.55, 0.65, 0.9)
	moon.shadow_enabled = q >= 2
	moon.directional_shadow_max_distance = 100.0
	moon.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	add_child(moon)
	rain = _make_particles(Color(0.7, 0.75, 0.85, 0.45), Vector3(0.02, 0.7, 0.02), 9000 if q >= 2 else 4000, 28.0, false)
	snow = _make_particles(Color(0.95, 0.95, 1.0, 0.9), Vector3(0.06, 0.06, 0.06), 5000, 3.0, true)
	ash = _make_particles(Color(0.15, 0.12, 0.1, 0.9), Vector3(0.05, 0.05, 0.05), 4000, 2.0, true)
	_pick_target(true)


func apply_quality(q: int) -> void:
	quality = q
	if env == null:
		return
	env.ssao_enabled = q >= 1
	env.ssao_radius = 1.5
	env.ssao_intensity = 1.1
	env.ssil_enabled = q >= 3
	env.sdfgi_enabled = false
	env.volumetric_fog_enabled = q >= 2
	env.volumetric_fog_density = 0.008
	env.volumetric_fog_length = 120.0
	env.volumetric_fog_anisotropy = 0.6
	env.volumetric_fog_ambient_inject = 0.3
	env.ssr_enabled = q >= 3
	if sun:
		sun.directional_shadow_max_distance = [90.0, 140.0, 220.0, 320.0][clampi(q, 0, 3)]
		sun.shadow_enabled = true
	if moon:
		moon.shadow_enabled = q >= 2


func _make_particles(col: Color, size: Vector3, amount: int, speed: float, drift: bool) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = 2.2 if not drift else 6.0
	p.visibility_aabb = AABB(Vector3(-40, -40, -40), Vector3(80, 80, 80))
	p.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(35, 2, 35)
	pm.direction = Vector3(0.1, -1, 0)
	pm.spread = 4.0 if not drift else 25.0
	pm.initial_velocity_min = speed * 0.9
	pm.initial_velocity_max = speed * 1.1
	pm.gravity = Vector3(0, -2 if drift else -9.0, 0)
	if drift:
		pm.turbulence_enabled = true
		pm.turbulence_noise_strength = 1.5
	p.process_material = pm
	var mesh := QuadMesh.new()
	mesh.size = Vector2(size.x, size.y)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y if not drift else BaseMaterial3D.BILLBOARD_ENABLED
	mesh.material = mat
	p.draw_pass_1 = mesh
	p.emitting = false
	add_child(p)
	return p


func _pick_target(immediate: bool = false) -> void:
	var table: Dictionary = TABLES.get(region_kind, TABLES["core"])
	if GameState.flag("force_weather") != null and GameState.flag("force_weather") != "":
		weather = GameState.flag("force_weather")
	else:
		var total := 0
		for k in table:
			total += table[k]
		var r := rng.randi_range(1, total)
		for k in table:
			r -= table[k]
			if r <= 0:
				weather = k
				break
	target = _params_for(weather)
	next_change_hours = rng.randf_range(4.0, 10.0)
	if immediate:
		cur = target.duplicate()
	weather_changed.emit(weather)
	EventBus.weather_changed.emit(weather)


func force_weather(kind: String) -> void:
	weather = kind
	target = _params_for(kind)
	next_change_hours = rng.randf_range(3.0, 6.0)
	weather_changed.emit(weather)
	EventBus.weather_changed.emit(weather)


func _params_for(w: String) -> Dictionary:
	var p := {"cloud": 0.25, "dark": 0.0, "fog": 0.0012, "rain": 0.0, "snow": 0.0, "ash": 0.0, "demon": 0.0, "wet": 0.0, "wind": 0.3}
	match w:
		"cloudy":
			p.merge({"cloud": 0.65, "dark": 0.35, "fog": 0.0022, "wind": 0.5}, true)
		"rain":
			p.merge({"cloud": 0.9, "dark": 0.7, "fog": 0.004, "rain": 1.0, "wet": 1.0, "wind": 0.7}, true)
		"storm":
			p.merge({"cloud": 1.0, "dark": 0.95, "fog": 0.005, "rain": 1.0, "wet": 1.0, "wind": 1.0}, true)
		"fog":
			p.merge({"cloud": 0.6, "dark": 0.3, "fog": 0.018, "wind": 0.1, "wet": 0.3}, true)
		"snow":
			p.merge({"cloud": 0.85, "dark": 0.4, "fog": 0.006, "snow": 1.0, "wind": 0.5}, true)
		"ashfall":
			p.merge({"cloud": 0.9, "dark": 0.8, "fog": 0.008, "ash": 1.0, "wind": 0.4}, true)
		"sandstorm":
			p.merge({"cloud": 0.4, "dark": 0.2, "fog": 0.03, "wind": 1.0}, true)
		"demon_storm":
			p.merge({"cloud": 1.0, "dark": 0.9, "fog": 0.006, "rain": 0.6, "demon": 1.0, "wet": 0.7, "wind": 0.9}, true)
	return p


func _process(delta: float) -> void:
	var hour: float = GameState.get_hour()
	var hours_passed: float = GameState.consume_weather_hours()
	next_change_hours -= hours_passed
	if next_change_hours <= 0.0:
		_pick_target()
	for k in cur:
		cur[k] = lerpf(cur[k], target.get(k, cur[k]), minf(1.0, delta * 0.12))
	# sun path
	var sun_angle := (hour - 6.0) / 24.0 * TAU # 6h sunrise, 18h sunset
	var elev := sin(sun_angle)
	sun.rotation = Vector3(-sun_angle, deg_to_rad(30.0), 0)
	var day := clampf(smoothstep(-0.12, 0.25, elev), 0.0, 1.0)
	var cloud_dim = 1.0 - cur["dark"] * 0.65
	sun.light_energy = day * 1.6 * cloud_dim
	sun.visible = elev > -0.1
	sun.light_color = Color(1.0, 0.82, 0.62).lerp(Color(1.0, 0.97, 0.92), smoothstep(0.0, 0.5, elev))
	moon.rotation = Vector3(-(sun_angle + PI) + 0.25, deg_to_rad(-40.0), 0)
	moon.light_energy = (1.0 - day) * 0.28 * (1.0 - cur["cloud"] * 0.5)
	moon.visible = elev < 0.15
	sky_mat.set_shader_parameter("day_factor", day)
	sky_mat.set_shader_parameter("cloud_cover", cur["cloud"])
	sky_mat.set_shader_parameter("cloud_dark", cur["dark"])
	sky_mat.set_shader_parameter("demon_storm", cur["demon"])
	sky_mat.set_shader_parameter("moon_dir", -moon.global_transform.basis.z)
	env.ambient_light_energy = lerpf(0.25, 1.5, day) * (1.0 - cur["dark"] * 0.4)
	env.ambient_light_color = Color(0.55, 0.6, 0.68).lerp(Color(0.08, 0.1, 0.16), 1.0 - day)
	var fog_col := Color(0.5, 0.56, 0.62).lerp(Color(0.04, 0.05, 0.08), 1.0 - day)
	fog_col = fog_col.lerp(Color(0.35, 0.07, 0.05), cur["demon"] * 0.6)
	if weather == "sandstorm":
		fog_col = fog_col.lerp(Color(0.6, 0.45, 0.25), 0.7)
	env.fog_light_color = fog_col
	env.fog_density = cur["fog"]
	env.volumetric_fog_albedo = fog_col
	env.volumetric_fog_density = 0.004 + cur["fog"] * 1.2
	# underwater / cave overrides
	if underwater:
		env.fog_light_color = Color(0.03, 0.12, 0.14)
		env.fog_density = 0.06
		env.volumetric_fog_density = 0.03
		env.volumetric_fog_albedo = Color(0.05, 0.2, 0.22)
	if in_cave:
		sun.light_energy = 0.0
		moon.light_energy = 0.0
		env.ambient_light_energy = 0.08
		env.fog_light_color = Color(0.02, 0.02, 0.025)
		env.fog_density = 0.02
	# lightning
	if (weather == "storm" or weather == "demon_storm") and cur["dark"] > 0.6 and not in_cave:
		lightning_timer -= delta
		if lightning_timer <= 0.0:
			lightning_timer = rng.randf_range(4.0, 14.0)
			flash = 1.0
			var cp := camera.global_position if camera else Vector3.ZERO
			var strike := cp + Vector3(rng.randf_range(-250, 250), 0, rng.randf_range(-250, 250))
			strike.y = WorldData.height_at(strike.x, strike.z)
			lightning_strike.emit(strike)
			Audio.play_thunder(cp.distance_to(strike))
	if flash > 0.0:
		flash = maxf(0.0, flash - delta * 3.0)
		env.ambient_light_energy += flash * 2.5
		sky_mat.set_shader_parameter("cloud_dark", cur["dark"] - flash * 0.8)
	# particles follow camera
	if camera:
		var cpos := camera.global_position
		for p in [rain, snow, ash]:
			p.global_position = cpos + Vector3(0, 18, 0)
	rain.emitting = cur["rain"] > 0.3 and not in_cave and not underwater
	snow.emitting = cur["snow"] > 0.3 and not in_cave and not underwater
	ash.emitting = cur["ash"] > 0.3 and not in_cave and not underwater
	Audio.set_weather_levels(cur["rain"], cur["wind"], cur["demon"])


func is_night() -> bool:
	var h: float = GameState.get_hour()
	return h < 5.5 or h > 19.5


func wetness() -> float:
	return cur["wet"]


func weather_label() -> String:
	return WEATHER_NAMES.get(weather, weather)
