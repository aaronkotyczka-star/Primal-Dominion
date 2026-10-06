extends Node
## Sound playback: 3D one-shots, UI sounds, ambience/weather loops, adaptive music.
## Sounds are procedurally generated WAVs in assets/audio (tools/assetgen/gen_audio.py).

const DIR := "res://assets/audio/"
var _cache := {}
var _variants := {}
var _pool: Array[AudioStreamPlayer3D] = []
var _ui: AudioStreamPlayer
var _amb_wind: AudioStreamPlayer
var _amb_rain: AudioStreamPlayer
var _amb_day: AudioStreamPlayer
var _amb_night: AudioStreamPlayer
var _amb_sea: AudioStreamPlayer
var _amb_demon: AudioStreamPlayer
var _music: AudioStreamPlayer
var _music_state := ""
var combat_level := 0.0
var listener_pos := Vector3.ZERO
var night := 0.0
var near_sea := 0.0
var underwater := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for b in ["Music", "SFX", "Ambience", "UI"]:
		if AudioServer.get_bus_index(b) < 0:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, b)
			AudioServer.set_bus_send(idx, "Master")
	var sfx := AudioServer.get_bus_index("SFX")
	if AudioServer.get_bus_effect_count(sfx) == 0:
		var lp := AudioEffectLowPassFilter.new()
		lp.cutoff_hz = 20000.0
		AudioServer.add_bus_effect(sfx, lp)
		var rv := AudioEffectReverb.new()
		rv.wet = 0.08
		rv.room_size = 0.6
		AudioServer.add_bus_effect(sfx, rv)
	_index_files()
	_ui = AudioStreamPlayer.new()
	_ui.bus = "UI"
	add_child(_ui)
	_amb_wind = _loop("amb_wind", "Ambience")
	_amb_rain = _loop("amb_rain", "Ambience")
	_amb_day = _loop("amb_day", "Ambience")
	_amb_night = _loop("amb_night", "Ambience")
	_amb_sea = _loop("amb_sea", "Ambience")
	_amb_demon = _loop("amb_demon", "Ambience")
	_music = AudioStreamPlayer.new()
	_music.bus = "Music"
	add_child(_music)
	for i in 24:
		var p := AudioStreamPlayer3D.new()
		p.bus = "SFX"
		p.unit_size = 8.0
		p.max_distance = 120.0
		p.attenuation_filter_cutoff_hz = 6000.0
		add_child(p)
		_pool.append(p)
	Settings._apply_audio()


func _index_files() -> void:
	var d := DirAccess.open(DIR)
	if d == null:
		return
	for f in d.get_files():
		var fname := f.trim_suffix(".import")
		if not fname.ends_with(".wav") and not fname.ends_with(".ogg"):
			continue
		var base := fname.get_basename()
		var key := base
		var parts := base.rsplit("_", true, 1)
		if parts.size() == 2 and parts[1].is_valid_int():
			key = parts[0]
		if not _variants.has(key):
			_variants[key] = []
		var path := DIR + fname
		if not path in _variants[key]:
			_variants[key].append(path)


func _stream(name: String) -> AudioStream:
	var list: Array = _variants.get(name, [])
	if list.is_empty():
		return null
	var path: String = list[randi() % list.size()]
	if not _cache.has(path):
		_cache[path] = load(path)
	return _cache[path]


func _loop(name: String, bus: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus
	p.volume_db = -80.0
	var s := _stream(name)
	if s is AudioStreamOggVorbis:
		s = s.duplicate()
		s.loop = true
	p.stream = s
	add_child(p)
	if s:
		p.play()
	return p


func has_sound(name: String) -> bool:
	return _variants.has(name)


func play_at(name: String, pos: Vector3, vol_db: float = 0.0, pitch: float = 1.0, size: float = 1.0) -> void:
	var s := _stream(name)
	if s == null:
		return
	if pos.distance_to(listener_pos) > 140.0 * maxf(1.0, size):
		return
	var best: AudioStreamPlayer3D = null
	for p in _pool:
		if not p.playing:
			best = p
			break
	if best == null:
		best = _pool[randi() % _pool.size()]
	best.stream = s
	best.global_position = pos
	best.volume_db = vol_db
	best.unit_size = 8.0 * size
	best.max_distance = 120.0 * size
	best.pitch_scale = pitch * randf_range(0.94, 1.06)
	best.play()


func play_ui(name: String = "ui_click") -> void:
	var s := _stream(name)
	if s:
		_ui.stream = s
		_ui.play()


func play_creature(actor: Node3D, kind: String, sound_family: String, size: float) -> void:
	var pitch := clampf(1.6 / sqrt(maxf(size, 0.2)), 0.45, 2.2)
	var name := sound_family + "_" + kind
	if not has_sound(name):
		name = {"roar": "roar_mid", "hurt": "hurt_beast", "death": "death_beast", "idle": "grunt", "attack": "bite"}.get(kind, "grunt")
	play_at(name, actor.global_position, 2.0 if kind == "roar" else 0.0, pitch, clampf(size, 0.6, 3.0))


func play_ability(id: String, actor: Node3D) -> void:
	var ab := DB.ability(id)
	var anim: String = ab.get("anim", "")
	if ab.get("player", false) or ab.get("demon", false):
		if anim in ["heal"]:
			play_at("spell_heal", actor.global_position)
		elif anim in ["cast"]:
			play_at("spell_cast", actor.global_position)
		else:
			play_at("swing", actor.global_position)
		return
	if ab.get("element", "") != "" and ab.get("cone", false):
		play_at("breath", actor.global_position, 3.0, 1.0, 2.0)


func play_thunder(dist: float) -> void:
	var s := _stream("thunder")
	if s == null:
		return
	var p := AudioStreamPlayer.new()
	p.bus = "Ambience"
	p.stream = s
	p.volume_db = lerpf(3.0, -14.0, clampf(dist / 300.0, 0.0, 1.0))
	add_child(p)
	get_tree().create_timer(clampf(dist / 340.0, 0.0, 3.0)).timeout.connect(p.play)
	p.finished.connect(p.queue_free)


func set_weather_levels(rain: float, wind: float, demon: float) -> void:
	_fade(_amb_rain, rain * (0.3 if underwater else 1.0), -6.0)
	_fade(_amb_wind, (0.25 + wind * 0.75) * (0.0 if underwater else 1.0), -10.0)
	_fade(_amb_demon, demon, -6.0)
	_fade(_amb_day, (1.0 - night) * (0.0 if underwater else 1.0) * (1.0 - demon * 0.8), -12.0)
	_fade(_amb_night, night * (0.0 if underwater else 1.0), -10.0)
	_fade(_amb_sea, near_sea * (0.4 if underwater else 1.0), -8.0)


func _fade(p: AudioStreamPlayer, level: float, max_db: float) -> void:
	if p == null or p.stream == null:
		return
	var target := lerpf(-60.0, max_db, clampf(level, 0.0, 1.0)) if level > 0.01 else -80.0
	p.volume_db = lerpf(p.volume_db, target, 0.05)


func set_music(state: String) -> void:
	## explore, combat, night, demon, menu, boss
	if state == _music_state:
		return
	_music_state = state
	var s := _stream("music_" + state)
	if s == null:
		return
	if s is AudioStreamOggVorbis:
		s = s.duplicate()
		s.loop = true
	var tw := create_tween()
	tw.tween_property(_music, "volume_db", -40.0, 1.2)
	tw.tween_callback(func():
		_music.stream = s
		_music.play())
	tw.tween_property(_music, "volume_db", -8.0, 2.0)


func set_underwater(v: bool) -> void:
	underwater = v
	var sfx := AudioServer.get_bus_index("SFX")
	var lp := AudioServer.get_bus_effect(sfx, 0) as AudioEffectLowPassFilter
	if lp:
		lp.cutoff_hz = 900.0 if v else 20000.0
