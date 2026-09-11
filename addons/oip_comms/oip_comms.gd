@tool
class_name OIPCommsPlugin
extends EditorPlugin

const DOCK_SCENE = preload("res://addons/oip_comms/controls/dock.tscn")
const DOCK_NAME: String = "Comms"

var _comms_dock: _OIPCommsDock
var _editor_dock: EditorDock


func _enter_tree() -> void:
	_comms_dock = DOCK_SCENE.instantiate()
	_editor_dock = EditorDock.new()
	_editor_dock.name = DOCK_NAME
	_editor_dock.default_slot = EditorDock.DOCK_SLOT_BOTTOM
	_editor_dock.available_layouts = EditorDock.DOCK_LAYOUT_HORIZONTAL | EditorDock.DOCK_LAYOUT_FLOATING
	_editor_dock.add_child(_comms_dock)
	add_dock(_editor_dock)
	
	_comms_dock.save_changes.connect(save_changes)
	
	scene_saved.connect(_scene_saved)


func _exit_tree() -> void:
	remove_dock(_editor_dock)
	_editor_dock.queue_free()


func save_changes(value: bool) -> void:
	if value:
		_editor_dock.name = DOCK_NAME + "(*)"
	else:
		_editor_dock.name = DOCK_NAME


func _scene_saved(filepath: String) -> void:
	_comms_dock.save_all()
