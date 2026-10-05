extends Node
## User settings (graphics, audio, controls) persisted in user://settings.cfg.

signal changed()

const PATH := "user://settings.cfg"
# action -> [label, default binding]; bindings: "k:<physical keycode>" or "m:<mouse button>"
const ACTIONS := {
	"move_forward": ["Vorwärts", "k:87"], "move_back": ["Rückwärts", "k:83"],
	"move_left": ["Links", "k:65"], "move_right": ["Rechts", "k:68"],
	"jump": ["Springen / Steigen", "k:32"], "sprint": ["Sprinten", "k:4194325"],
	"crouch": ["Ducken / Sinken", "k:4194326"], "dodge": ["Ausweichen", "k:67"],
	"attack": ["Angriff", "m:1"], "block": ["Blocken / Zielen", "m:2"],
	"interact": ["Interagieren / Aufsteigen", "k:69"], "command_wheel": ["Befehlsrad (halten)", "k:81"],
	"ability_1": ["Fähigkeit 1", "k:82"], "ability_2": ["Fähigkeit 2", "k:70"],
	"ability_3": ["Fähigkeit 3", "k:71"], "ability_4": ["Fähigkeit 4", "k:90"],
	"slot_1": ["Schnellleiste 1", "k:49"], "slot_2": ["Schnellleiste 2", "k:50"],
	"slot_3": ["Schnellleiste 3", "k:51"], "slot_4": ["Schnellleiste 4", "k:52"],
	"slot_5": ["Schnellleiste 5", "k:53"], "slot_6": ["Schnellleiste 6", "k:54"],
	"lock_target": ["Zielerfassung", "k:84"], "toggle_view": ["Perspektive wechseln", "k:86"],
	"direct_control": ["Kreatur direkt steuern", "k:88"], "build_mode": ["Baumodus", "k:66"],
	"inventory": ["Inventar", "k:73"], "journal": ["Questjournal", "k:74"],
	"skills": ["Fähigkeiten", "k:75"], "map": ["Karte", "k:77"], "lexicon": ["Kreaturenlexikon", "k:76"],
	"research": ["Forschungsbuch", "k:80"], "creatures": ["Kreaturen", "k:72"],
	"crafting": ["Herstellen", "k:85"], "transform": ["Gestalt wechseln", "k:78"],
	"quicksave": ["Schnellspeichern", "k:4194336"], "quickload": ["Schnellladen", "k:4194340"],
	"pause": ["Pause / Menü", "k:4194305"], "whistle": ["Pfeifen (alle folgen)", "k:4194306"],
	"rotate_build": ["Bauteil drehen", "k:82"],
}

var data := {
	"resolution": Vector2i(1920, 1080), "window_mode": 0, "vsync": true, "fps_limit": 0,
	"quality": 2, "render_scale": 1.0, "fov": 75.0, "mouse_sens": 0.25, "invert_y": false,
	"vol_master": 0.8, "vol_music": 0.5, "vol_sfx": 0.8, "vol_ambience": 0.7, "vol_ui": 0.7,
	"show_damage_numbers": true, "camera_shake": true, "tutorial_hints": true, "view_distance": 1.0,
	"bindings": {},
}


func _ready() -> void:
	_load()
	_apply_bindings()
	apply()


func _load() -> void:
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return
	for k in data:
		if cf.has_section_key("s", k):
			data[k] = cf.get_value("s", k)


func save() -> void:
	var cf := ConfigFile.new()
	for k in data:
		cf.set_value("s", k, data[k])
	cf.save(PATH)


func get_v(k: String) -> Variant:
	return data.get(k)


func set_v(k: String, v: Variant, apply_now: bool = true) -> void:
	data[k] = v
	if apply_now:
		apply()
	save()
	changed.emit()


func apply() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var mode: int = data["window_mode"]
	match mode:
		0:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_size(data["resolution"])
		1:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		2:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if data["vsync"] else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = int(data["fps_limit"])
	var vp := get_viewport()
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2 if float(data["render_scale"]) < 0.99 else Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = clampf(float(data["render_scale"]), 0.5, 1.0)
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if int(data["quality"]) < 2 else Viewport.SCREEN_SPACE_AA_SMAA
	vp.use_taa = false
	_apply_audio()


func _apply_audio() -> void:
	for bus in [["Master", "vol_master"], ["Music", "vol_music"], ["SFX", "vol_sfx"], ["Ambience", "vol_ambience"], ["UI", "vol_ui"]]:
		var idx := AudioServer.get_bus_index(bus[0])
		if idx >= 0:
			var v: float = data[bus[1]]
			AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v, 0.0001)))
			AudioServer.set_bus_mute(idx, v <= 0.001)


func binding(action: String) -> String:
	var b: Dictionary = data["bindings"]
	if b.has(action):
		return b[action]
	return ACTIONS[action][1]


func set_binding(action: String, bind: String) -> void:
	data["bindings"][action] = bind
	_apply_bindings()
	save()


func reset_bindings() -> void:
	data["bindings"] = {}
	_apply_bindings()
	save()


func _apply_bindings() -> void:
	for action in ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.2)
		InputMap.action_erase_events(action)
		var ev := _event_from(binding(action))
		if ev:
			InputMap.action_add_event(action, ev)
	# secondary defaults
	_add_extra("lock_target", "m:3")


func _add_extra(action: String, bind: String) -> void:
	var ev := _event_from(bind)
	if ev and InputMap.has_action(action):
		InputMap.action_add_event(action, ev)


func _event_from(b: String) -> InputEvent:
	if b.begins_with("k:"):
		var code := int(b.substr(2))
		var e := InputEventKey.new()
		e.physical_keycode = code
		return e
	if b.begins_with("m:"):
		var m := InputEventMouseButton.new()
		m.button_index = int(b.substr(2))
		return m
	return null


func binding_label(action: String) -> String:
	var b := binding(action)
	if b.begins_with("k:"):
		var code := int(b.substr(2))
		return OS.get_keycode_string(DisplayServer.keyboard_get_keycode_from_physical(code))
	if b.begins_with("m:"):
		return ["", "Linke Maustaste", "Rechte Maustaste", "Mittlere Maustaste", "Mausrad hoch", "Mausrad runter"][clampi(int(b.substr(2)), 0, 5)]
	return "?"


func event_to_binding(ev: InputEvent) -> String:
	if ev is InputEventKey:
		return "k:%d" % ev.physical_keycode
	if ev is InputEventMouseButton:
		return "m:%d" % ev.button_index
	return ""
