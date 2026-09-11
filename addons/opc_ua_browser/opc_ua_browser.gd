@tool
extends EditorPlugin

var _editor_dock: EditorDock

func _enter_tree() -> void:
	var content := preload("res://addons/opc_ua_browser/browser_dock.tscn").instantiate()
	_editor_dock = EditorDock.new()
	_editor_dock.title = "OPC UA Browser"
	_editor_dock.default_slot = EditorDock.DOCK_SLOT_LEFT_BR
	_editor_dock.available_layouts = EditorDock.DOCK_LAYOUT_VERTICAL | EditorDock.DOCK_LAYOUT_FLOATING
	_editor_dock.add_child(content)
	add_dock(_editor_dock)
	Engine.set_meta("opc_ua_browser_dock", _editor_dock)
	Engine.set_meta("opc_ua_browser_content", content)

func _exit_tree() -> void:
	Engine.remove_meta("opc_ua_browser_dock")
	Engine.remove_meta("opc_ua_browser_content")
	remove_dock(_editor_dock)
	_editor_dock.queue_free()
