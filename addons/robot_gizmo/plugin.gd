@tool
extends EditorPlugin

const ROBOT_SCRIPT_PATH := "res://src/SixAxisRobot/six_axis_robot.gd"

var gizmo_plugin: EditorNode3DGizmoPlugin
var _last_selected_robots: Array[Node3D] = []


func _enter_tree() -> void:
	gizmo_plugin = preload("res://addons/robot_gizmo/robot_gizmo_plugin.gd").new()
	add_node_3d_gizmo_plugin(gizmo_plugin)
	var selection := EditorInterface.get_selection()
	if not selection.selection_changed.is_connected(_on_selection_changed):
		selection.selection_changed.connect(_on_selection_changed)


func _exit_tree() -> void:
	var selection := EditorInterface.get_selection()
	if selection.selection_changed.is_connected(_on_selection_changed):
		selection.selection_changed.disconnect(_on_selection_changed)
	_last_selected_robots.clear()
	if gizmo_plugin:
		remove_node_3d_gizmo_plugin(gizmo_plugin)
		gizmo_plugin = null


func _on_selection_changed() -> void:
	var now_selected: Array[Node3D] = []
	for n in EditorInterface.get_selection().get_selected_nodes():
		if n is Node3D and _is_robot(n):
			now_selected.append(n)

	var to_update: Array[Node3D] = []
	for n in _last_selected_robots:
		if is_instance_valid(n):
			to_update.append(n)
	for n in now_selected:
		if n not in to_update:
			to_update.append(n)

	_last_selected_robots = now_selected
	for n in to_update:
		n.update_gizmos()


func _is_robot(node: Node) -> bool:
	var script := node.get_script()
	return script != null and script.resource_path == ROBOT_SCRIPT_PATH
