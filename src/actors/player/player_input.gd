class_name PlayerInput
extends Node
## Converts local device input into an intent dictionary. The Player only reads `intent`,
## so another source (network peer, AI, test script) can drive a Player later.

var intent := {}
var look_delta := Vector2.ZERO
var enabled := true
var scripted := false # tests can set intent directly
var _pressed_cache := {}

const BUTTONS := ["jump", "sprint", "crouch", "dodge", "attack", "block", "interact", "command_wheel",
	"ability_1", "ability_2", "ability_3", "ability_4", "slot_1", "slot_2", "slot_3", "slot_4", "slot_5", "slot_6",
	"lock_target", "toggle_view", "direct_control", "build_mode", "transform", "whistle", "quicksave", "quickload", "rotate_build"]


func _ready() -> void:
	_reset()


func _reset() -> void:
	intent = {"move": Vector2.ZERO}
	for b in BUTTONS:
		intent[b] = false
		intent[b + "_just"] = false
		intent[b + "_released"] = false


func _unhandled_input(event: InputEvent) -> void:
	if scripted or not enabled:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		look_delta += event.relative


func poll() -> void:
	if scripted:
		return
	if not enabled or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not _ui_allows_movement():
		var keep_move := false
		for b in BUTTONS:
			intent[b] = false
			intent[b + "_just"] = false
			intent[b + "_released"] = _pressed_cache.get(b, false)
			_pressed_cache[b] = false
		if not keep_move:
			intent["move"] = Vector2.ZERO
		look_delta = Vector2.ZERO
		return
	intent["move"] = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	for b in BUTTONS:
		var now := Input.is_action_pressed(b)
		var was: bool = _pressed_cache.get(b, false)
		intent[b] = now
		intent[b + "_just"] = now and not was
		intent[b + "_released"] = was and not now
		_pressed_cache[b] = now


func _ui_allows_movement() -> bool:
	return false


func consume_look() -> Vector2:
	var d := look_delta
	look_delta = Vector2.ZERO
	return d


func press(action: String) -> void:
	## for scripted tests
	intent[action] = true
	intent[action + "_just"] = true


func clear_just() -> void:
	for b in BUTTONS:
		intent[b + "_just"] = false
		intent[b + "_released"] = false
