class_name Interactable
extends Node3D
## Generic interaction point (pickups, stations, POI objects). Configure via callables.

var prompt := "E: Benutzen"
var radius := 3.0
var on_interact: Callable
var prompt_fn: Callable
var condition: Callable
var data: Dictionary = {}


static func make(parent: Node, pos: Vector3, prompt_text: String, cb: Callable, r: float = 3.0) -> Interactable:
	var it := Interactable.new()
	it.prompt = prompt_text
	it.on_interact = cb
	it.radius = r
	parent.add_child(it)
	it.global_position = pos
	return it


func _ready() -> void:
	add_to_group("interactables")


func get_prompt(p: Node) -> String:
	if prompt_fn.is_valid():
		return prompt_fn.call(p)
	return prompt


func can_interact(p: Node) -> bool:
	if condition.is_valid():
		return condition.call(p)
	return true


func interact(p: Node) -> void:
	if on_interact.is_valid():
		on_interact.call(p)


func interact_radius() -> float:
	return radius
