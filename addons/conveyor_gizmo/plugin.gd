@tool
extends EditorPlugin

const ConveyorGizmoPlugin = preload("res://addons/conveyor_gizmo/conveyor_gizmo_plugin.gd")
const PathBeltGizmoPlugin = preload("res://addons/conveyor_gizmo/path_belt_gizmo_plugin.gd")
const CurvedConveyorGizmoPlugin = preload("res://addons/conveyor_gizmo/curved_conveyor_gizmo_plugin.gd")

const SHORTCUT_PATH = "Open Industry Project/Toggle Sideguards"
const SETTING_SIDEGUARD = "open_industry_project/sideguard_mode"
const TOOLTIP_TITLE = "Toggle Sideguards"
const TOOLTIP_BODY = "Drag: Resize a guard and create an opening.\nCtrl+Click: Split a guard into two halves.\nShift+Click: Merge with an adjacent guard, or re-anchor to the conveyor edge."

const ARROW_SHORTCUT_PATH = "Open Industry Project/Toggle Flow Arrows"
const SETTING_FLOW_ARROWS = "open_industry_project/flow_arrows_visible"

var gizmo_plugin: ConveyorGizmoPlugin
var path_belt_gizmo_plugin: PathBeltGizmoPlugin
var curved_gizmo_plugin: CurvedConveyorGizmoPlugin
var _toggle_button: Button
var _shortcut: Shortcut
var _arrow_button: Button
var _arrow_shortcut: Shortcut

func _enter_tree():
	gizmo_plugin = ConveyorGizmoPlugin.new()
	add_node_3d_gizmo_plugin(gizmo_plugin)

	path_belt_gizmo_plugin = PathBeltGizmoPlugin.new()
	add_node_3d_gizmo_plugin(path_belt_gizmo_plugin)

	curved_gizmo_plugin = CurvedConveyorGizmoPlugin.new()
	add_node_3d_gizmo_plugin(curved_gizmo_plugin)

	_toggle_button = Button.new()
	_toggle_button.flat = true
	_toggle_button.toggle_mode = true
	_toggle_button.icon = EditorInterface.get_editor_theme().get_icon("MaterialPreviewQuad", "EditorIcons")
	_toggle_button.toggled.connect(_on_sideguard_toggle)
	add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, _toggle_button)

	var editor_settings := EditorInterface.get_editor_settings()

	if not editor_settings.has_setting(SETTING_SIDEGUARD):
		editor_settings.set_setting(SETTING_SIDEGUARD, false)
	editor_settings.set_initial_value(SETTING_SIDEGUARD, false, false)
	_toggle_button.button_pressed = editor_settings.get_setting(SETTING_SIDEGUARD)

	_shortcut = Shortcut.new()
	var key_stroke := InputEventKey.new()
	key_stroke.keycode = KEY_G
	_shortcut.events.append(key_stroke)
	editor_settings.add_shortcut(SHORTCUT_PATH, _shortcut)
	_shortcut = editor_settings.get_shortcut(SHORTCUT_PATH)
	_shortcut.changed.connect(_update_tooltip)
	_update_tooltip()

	_arrow_button = Button.new()
	_arrow_button.flat = true
	_arrow_button.toggle_mode = true
	_arrow_button.icon = EditorInterface.get_editor_theme().get_icon("ArrowRight", "EditorIcons")
	_arrow_button.toggled.connect(_on_flow_arrow_toggle)
	add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, _arrow_button)

	if not editor_settings.has_setting(SETTING_FLOW_ARROWS):
		editor_settings.set_setting(SETTING_FLOW_ARROWS, false)
	editor_settings.set_initial_value(SETTING_FLOW_ARROWS, false, false)
	_arrow_button.button_pressed = editor_settings.get_setting(SETTING_FLOW_ARROWS)

	_arrow_shortcut = Shortcut.new()
	var arrow_key := InputEventKey.new()
	arrow_key.keycode = KEY_PERIOD
	_arrow_shortcut.events.append(arrow_key)
	editor_settings.add_shortcut(ARROW_SHORTCUT_PATH, _arrow_shortcut)
	_arrow_shortcut = editor_settings.get_shortcut(ARROW_SHORTCUT_PATH)
	_arrow_shortcut.changed.connect(_update_arrow_tooltip)
	_update_arrow_tooltip()

func _exit_tree():
	if _shortcut and _shortcut.changed.is_connected(_update_tooltip):
		_shortcut.changed.disconnect(_update_tooltip)
	if _arrow_shortcut and _arrow_shortcut.changed.is_connected(_update_arrow_tooltip):
		_arrow_shortcut.changed.disconnect(_update_arrow_tooltip)
	remove_node_3d_gizmo_plugin(gizmo_plugin)
	if path_belt_gizmo_plugin:
		remove_node_3d_gizmo_plugin(path_belt_gizmo_plugin)
	if curved_gizmo_plugin:
		remove_node_3d_gizmo_plugin(curved_gizmo_plugin)
	if _toggle_button:
		remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, _toggle_button)
		_toggle_button.queue_free()
	if _arrow_button:
		remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, _arrow_button)
		_arrow_button.queue_free()

func _update_tooltip() -> void:
	var shortcut_text := _shortcut.get_as_text() if _shortcut else ""
	var title := TOOLTIP_TITLE
	if not shortcut_text.is_empty() and shortcut_text != "None":
		title += " (" + shortcut_text + ")"
	_toggle_button.tooltip_text = title + "\n" + TOOLTIP_BODY


func _shortcut_input(event: InputEvent) -> void:
	var editor_settings := EditorInterface.get_editor_settings()
	if editor_settings.is_shortcut(SHORTCUT_PATH, event) and event.is_pressed() and not event.is_echo():
		_toggle_button.button_pressed = not _toggle_button.button_pressed
	if editor_settings.is_shortcut(ARROW_SHORTCUT_PATH, event) and event.is_pressed() and not event.is_echo():
		_arrow_button.button_pressed = not _arrow_button.button_pressed


func _on_flow_arrow_toggle(pressed: bool) -> void:
	EditorInterface.get_editor_settings().set_setting(SETTING_FLOW_ARROWS, pressed)
	FlowDirectionArrow.set_all_visible(pressed)


func _update_arrow_tooltip() -> void:
	var shortcut_text := _arrow_shortcut.get_as_text() if _arrow_shortcut else ""
	var title := "Toggle Flow Arrows"
	if not shortcut_text.is_empty() and shortcut_text != "None":
		title += " (" + shortcut_text + ")"
	_arrow_button.tooltip_text = title


func _on_sideguard_toggle(pressed: bool) -> void:
	EditorInterface.get_editor_settings().set_setting(SETTING_SIDEGUARD, pressed)
	gizmo_plugin.sideguard_mode = pressed
	# Suppress path-belt and curved resize handles so they don't fight sideguard handles.
	if path_belt_gizmo_plugin:
		path_belt_gizmo_plugin.sideguard_mode = pressed
	if curved_gizmo_plugin:
		curved_gizmo_plugin.sideguard_mode = pressed
	var selection := EditorInterface.get_selection().get_selected_nodes()
	for node in selection:
		if node is Node3D:
			node.update_gizmos()
