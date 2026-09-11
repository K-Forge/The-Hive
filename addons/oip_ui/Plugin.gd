@tool
class_name OIPUIPlugin
extends EditorPlugin

const ICON: Texture2D = preload("res://assets/png/OIP-LOGO-RGB_ICON.svg")

const LIVE_SNAP_SHORTCUT_PATH := "Open Industry Project/Toggle Live Snap"
const SETTING_LIVE_SNAP := "open_industry_project/live_snap_enabled"

var _editor_node: Node
var _create_root_vbox: VBoxContainer
var _selected_nodes: Array[Node]
var _live_snap_button: Button
var _live_snap_shortcut: Shortcut


func _enter_tree() -> void:
	_editor_node = get_tree().root.get_child(0)
	_editor_node.editor_layout_loaded.connect(_editor_layout_loaded)

	var editor_settings := EditorInterface.get_editor_settings()
	var use_shortcut := Shortcut.new()
	var key_stroke := InputEventKey.new()
	key_stroke.keycode = KEY_C
	use_shortcut.events.append(key_stroke)
	editor_settings.add_shortcut("Open Industry Project/Use", use_shortcut)

	_live_snap_button = Button.new()
	_live_snap_button.flat = true
	_live_snap_button.toggle_mode = true
	_live_snap_button.icon = EditorInterface.get_editor_theme().get_icon("SnapGrid", "EditorIcons")
	_live_snap_button.toggled.connect(_on_live_snap_toggle)
	add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, _live_snap_button)

	if not editor_settings.has_setting(SETTING_LIVE_SNAP):
		editor_settings.set_setting(SETTING_LIVE_SNAP, true)
	editor_settings.set_initial_value(SETTING_LIVE_SNAP, true, false)
	_live_snap_button.button_pressed = editor_settings.get_setting(SETTING_LIVE_SNAP)
	ConveyorSnapping.live_snap_enabled = _live_snap_button.button_pressed

	_live_snap_shortcut = Shortcut.new()
	var live_snap_key := InputEventKey.new()
	live_snap_key.keycode = KEY_N
	_live_snap_shortcut.events.append(live_snap_key)
	editor_settings.add_shortcut(LIVE_SNAP_SHORTCUT_PATH, _live_snap_shortcut)
	_live_snap_shortcut = editor_settings.get_shortcut(LIVE_SNAP_SHORTCUT_PATH)
	_live_snap_shortcut.changed.connect(_update_live_snap_tooltip)
	_update_live_snap_tooltip()

	EditorInterface.get_selection().selection_changed.connect(_on_selection_changed)


func _editor_layout_loaded() -> void:
	_create_root_vbox = _editor_node.find_child("BeginnerNodeShortcuts", true, false)

	if _create_root_vbox:
		var button := Button.new()
		button.text = "New Simulation"
		button.icon = ICON
		button.pressed.connect(self._new_simulation_btn_pressed)
		_create_root_vbox.add_child(button)
		_create_root_vbox.move_child(button, 0)
		_create_root_vbox.move_child(_create_root_vbox.get_child(1), 2)

	if get_tree().edited_scene_root == null:
		_create_new_simulation()
		EditorInterface.mark_scene_as_saved()


func _process(_delta: float) -> void:
	for node: Node in _selected_nodes:
		if not node:
			return
		if node.has_method("selected"):
			node.call("selected")


func _shortcut_input(event: InputEvent) -> void:
	var editor_settings := EditorInterface.get_editor_settings()
	if editor_settings.is_shortcut("Open Industry Project/Use", event) and event.is_pressed() and not event.is_echo():
		for node: Node in EditorInterface.get_selection().get_selected_nodes():
			if node.has_method("use"):
				node.call("use")
	if editor_settings.is_shortcut(LIVE_SNAP_SHORTCUT_PATH, event) and event.is_pressed() and not event.is_echo():
		_live_snap_button.button_pressed = not _live_snap_button.button_pressed


func _exit_tree() -> void:
	if _live_snap_shortcut and _live_snap_shortcut.changed.is_connected(_update_live_snap_tooltip):
		_live_snap_shortcut.changed.disconnect(_update_live_snap_tooltip)
	if _live_snap_button:
		remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, _live_snap_button)
		_live_snap_button.queue_free()


func _on_live_snap_toggle(pressed: bool) -> void:
	EditorInterface.get_editor_settings().set_setting(SETTING_LIVE_SNAP, pressed)
	ConveyorSnapping.live_snap_enabled = pressed


func _update_live_snap_tooltip() -> void:
	if not _live_snap_button:
		return
	var shortcut_text := _live_snap_shortcut.get_as_text() if _live_snap_shortcut else ""
	var title := "Toggle Live Snap"
	if not shortcut_text.is_empty() and shortcut_text != "None":
		title += " (" + shortcut_text + ")"
	_live_snap_button.tooltip_text = title + "\nWhen on, parts snap to neighbours during gizmo drags and drop hover.\nHold Alt to escape snap for a single drag."


func _on_selection_changed() -> void:
	_selected_nodes = EditorInterface.get_selection().get_selected_nodes()


func _new_simulation_btn_pressed() -> void:
	get_undo_redo().create_action("Create New Simulation")
	get_undo_redo().add_do_method(self, "_create_new_simulation")
	get_undo_redo().add_undo_method(self, "_remove_new_simulation")
	get_undo_redo().commit_action()


func _create_new_simulation() -> void:
	var scene := Node3D.new()
	scene.name = "Simulation"
	var building: Node3D = load("res://parts/Building.tscn").instantiate()
	EditorInterface.add_root_node(scene)
	get_tree().edited_scene_root.add_child(building)
	building.owner = scene


func _remove_new_simulation() -> void:
	EditorInterface.remove_root_node()
