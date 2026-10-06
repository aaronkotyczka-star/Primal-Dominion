class_name UIWindow
extends PanelContainer
## Base class for modal-ish game windows (title, close button, content area, refresh()).

var ui: Node
var content: VBoxContainer
var title_label: Label
var window_id := ""


func _init(t: String = "", min_size: Vector2 = Vector2(900, 620)) -> void:
	custom_minimum_size = min_size
	var outer := UIK.vbox(8)
	add_child(outer)
	var head := UIK.hbox(8)
	outer.add_child(head)
	title_label = UIK.title(t)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title_label)
	var close := UIK.button("✕ Schließen (Esc)", func(): close_window(), "", 0)
	head.add_child(close)
	outer.add_child(UIK.sep())
	content = UIK.vbox(8)
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(content)


func _ready() -> void:
	theme = UIK.get_theme()
	UIK.center_window(self)
	refresh()
	UIK.focus_for_gamepad.call_deferred(self)


func refresh() -> void:
	pass


func close_window() -> void:
	if ui:
		ui.close(self)
	else:
		queue_free()
