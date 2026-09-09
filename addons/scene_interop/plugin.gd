@tool
extends EditorPlugin


const _IMPORT_LABEL := "Import Web Scene (scene.json)..."
const _EXPORT_LABEL := "Export Web Scene (scene.json)..."

var _import_dialog: EditorFileDialog
var _export_dialog: EditorFileDialog


func _enter_tree() -> void:
	add_tool_menu_item(_IMPORT_LABEL, _on_import_pressed)
	add_tool_menu_item(_EXPORT_LABEL, _on_export_pressed)


func _exit_tree() -> void:
	remove_tool_menu_item(_IMPORT_LABEL)
	remove_tool_menu_item(_EXPORT_LABEL)
	if is_instance_valid(_import_dialog):
		_import_dialog.queue_free()
	if is_instance_valid(_export_dialog):
		_export_dialog.queue_free()


func _on_import_pressed() -> void:
	if EditorInterface.get_edited_scene_root() == null:
		_warn("Open a scene first, then import — the imported scene replaces its contents.")
		return
	if _import_dialog == null:
		_import_dialog = _make_dialog(EditorFileDialog.FILE_MODE_OPEN_FILE, "Import Web Scene")
		_import_dialog.file_selected.connect(_do_import)
	_import_dialog.popup_centered_ratio(0.6)


func _do_import(path: String) -> void:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		_warn("No edited scene to import into.")
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		_warn("Cannot read '%s'." % path)
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		_warn("'%s' is not a valid scene.json (expected a JSON object)." % path)
		return
	var doc: Dictionary = parsed
	var created: Array[Node] = OipSceneIO.import_scene(doc, root)
	if created.is_empty():
		_warn("Nothing imported - no recognized parts in '%s'." % path.get_file())
		return
	var imported := {}
	for node: Node in created:
		imported[node] = true
	var old_children: Array[Node] = []
	for child: Node in root.get_children():
		if not imported.has(child):
			old_children.append(child)

	var ur := get_undo_redo()
	ur.create_action("Import Web Scene (replace open scene)")
	for child: Node in old_children:
		root.remove_child(child)
		ur.add_do_method(root, "remove_child", child)
		ur.add_undo_reference(child)
		ur.add_undo_method(child, "set_owner", root)
		ur.add_undo_method(root, "add_child", child)
	for node: Node in created:
		node.owner = root
		ur.add_do_reference(node)
	for node: Node in created:
		if node.get_parent() != root:
			continue
		ur.add_do_method(root, "add_child", node)
		ur.add_undo_method(root, "remove_child", node)
	for node: Node in created:
		ur.add_do_method(node, "set_owner", root)
	ur.commit_action(false)
	EditorInterface.edit_node(created[0])
	print("scene_interop: imported %d part(s) from %s (replaced %d existing node(s))" % [
		created.size(), path, old_children.size()])


func _on_export_pressed() -> void:
	if EditorInterface.get_edited_scene_root() == null:
		_warn("Open a scene first, then export it.")
		return
	if _export_dialog == null:
		_export_dialog = _make_dialog(EditorFileDialog.FILE_MODE_SAVE_FILE, "Export Web Scene")
		_export_dialog.file_selected.connect(_do_export)
	_export_dialog.current_file = "scene.json"
	_export_dialog.popup_centered_ratio(0.6)


func _do_export(path: String) -> void:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		_warn("No edited scene to export.")
		return
	var doc: Dictionary = OipSceneIO.export_scene(root)
	var parts: Array = doc.get("parts", [])
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		_warn("Cannot write '%s'." % path)
		return
	f.store_string(JSON.stringify(doc, "\t"))
	f.close()
	print("scene_interop: exported %d part(s) to %s" % [parts.size(), path])


func _make_dialog(file_mode: EditorFileDialog.FileMode, dialog_title: String) -> EditorFileDialog:
	var dialog := EditorFileDialog.new()
	dialog.file_mode = file_mode
	dialog.access = EditorFileDialog.ACCESS_FILESYSTEM
	dialog.title = dialog_title
	dialog.add_filter("*.json", "Web scene (scene.json)")
	EditorInterface.get_base_control().add_child(dialog)
	return dialog


func _warn(message: String) -> void:
	push_warning("scene_interop: " + message)
	var dialog := AcceptDialog.new()
	dialog.title = "Web Scene Bridge"
	dialog.dialog_text = message
	EditorInterface.get_base_control().add_child(dialog)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered()
