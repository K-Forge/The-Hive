@tool
extends EditorPlugin


const _TOGGLE_KEY := KEY_C


func _handles(object: Object) -> bool:
	return _resolve_leaf(object as Node) != null


func _forward_3d_gui_input(_camera: Camera3D, event: InputEvent) -> int:
	if event is InputEventKey and event.is_pressed() and not event.is_echo() and event.keycode == _TOGGLE_KEY:
		var leaves := _selected_leaves()
		if leaves.is_empty():
			return AfterGUIInput.AFTER_GUI_INPUT_PASS
		for leaf in leaves:
			leaf.use()
		return AfterGUIInput.AFTER_GUI_INPUT_STOP
	return AfterGUIInput.AFTER_GUI_INPUT_PASS


func _selected_leaves() -> Array[DockDoorLeaf]:
	var leaves: Array[DockDoorLeaf] = []
	for node in EditorInterface.get_selection().get_selected_nodes():
		var leaf := _resolve_leaf(node)
		if leaf and leaf not in leaves:
			leaves.append(leaf)
	return leaves


func _resolve_leaf(node: Node) -> DockDoorLeaf:
	while node:
		if node is DockDoorLeaf:
			return node as DockDoorLeaf
		if node is DockDoor:
			return (node as DockDoor).get_first_leaf()
		node = node.get_parent()
	return null
