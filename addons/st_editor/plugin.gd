@tool
extends EditorPlugin


const DockScript := preload("res://addons/st_editor/st_editor_dock.gd")
const DOCK_NAME: String = "ST"

var _dock: VBoxContainer = null
var _editor_dock: EditorDock = null


func _enter_tree() -> void:
	_dock = DockScript.new()
	_editor_dock = EditorDock.new()
	_editor_dock.name = DOCK_NAME
	_editor_dock.default_slot = EditorDock.DOCK_SLOT_BOTTOM
	_editor_dock.available_layouts = EditorDock.DOCK_LAYOUT_ALL
	_editor_dock.add_child(_dock)
	add_dock(_editor_dock)
	scene_changed.connect(_on_scene_changed)
	_on_scene_changed(EditorInterface.get_edited_scene_root())


func _exit_tree() -> void:
	if scene_changed.is_connected(_on_scene_changed):
		scene_changed.disconnect(_on_scene_changed)
	if _editor_dock != null:
		remove_dock(_editor_dock)
		_editor_dock.queue_free()
		_editor_dock = null
		_dock = null


func _on_scene_changed(scene_root: Node) -> void:
	if _dock != null:
		_dock.call("set_scene_root", scene_root)
