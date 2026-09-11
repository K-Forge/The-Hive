@tool
extends EditorPlugin

signal pilot_mode_entered
signal pilot_mode_exited

const SPAWN_Y_OFFSET: float = 1.5
const FOCUS_RETURN_DELAY: float = 0.05
const SHORTCUT_PATH: String = "Pilot Mode/Toggle Pilot Mode"
const INTERACT_SHORTCUT_PATH: String = "Pilot Mode/Interact"
const MOVE_FORWARD_PATH: String = "Pilot Mode/Move Forward"
const MOVE_BACK_PATH: String = "Pilot Mode/Move Back"
const MOVE_LEFT_PATH: String = "Pilot Mode/Move Left"
const MOVE_RIGHT_PATH: String = "Pilot Mode/Move Right"
const JUMP_PATH: String = "Pilot Mode/Jump"
const SETTING_PATH: String = "addons/pilot_mode/scene/path"
const DEFAULT_SCENE: String = "res://addons/editor-pilot-mode/default_character.tscn"

var pilot_active: bool = false
var pilot_node: Node3D
var was_in_pilot_mode: bool = false
var overlay: Control
var _editor_camera: Camera3D
var _canvas_viewport: Viewport
var _node3d_viewport: Viewport
var _pilot_button: Button

var _last_camera: Camera3D
var _last_canvas_viewport: Viewport
var _last_node3d_viewport: Viewport
var _cursor_position_before_pilot: Vector2i

var _active_viewport_ui: Dictionary = {}


func _enter_tree() -> void:
	var editor_settings := EditorInterface.get_editor_settings()

	var toggle_shortcut := Shortcut.new()
	var key_stroke := InputEventKey.new()
	key_stroke.keycode = KEY_R
	key_stroke.shift_pressed = true
	toggle_shortcut.events.append(key_stroke)
	editor_settings.add_shortcut(SHORTCUT_PATH, toggle_shortcut)

	_register_key_shortcut(editor_settings, INTERACT_SHORTCUT_PATH, KEY_E)

	var scene_path: String = ProjectSettings.get_setting(SETTING_PATH, DEFAULT_SCENE)
	if scene_path == DEFAULT_SCENE and ResourceLoader.exists(DEFAULT_SCENE):
		_register_key_shortcut(editor_settings, MOVE_FORWARD_PATH, KEY_W)
		_register_key_shortcut(editor_settings, MOVE_BACK_PATH, KEY_S)
		_register_key_shortcut(editor_settings, MOVE_LEFT_PATH, KEY_A)
		_register_key_shortcut(editor_settings, MOVE_RIGHT_PATH, KEY_D)
		_register_key_shortcut(editor_settings, JUMP_PATH, KEY_SPACE)

	if not ProjectSettings.has_setting(SETTING_PATH):
		ProjectSettings.set_setting(SETTING_PATH, DEFAULT_SCENE)

	ProjectSettings.set_initial_value(SETTING_PATH, DEFAULT_SCENE)
	ProjectSettings.set_as_basic(SETTING_PATH, true)
	ProjectSettings.add_property_info({
		"name": SETTING_PATH,
		"type": TYPE_STRING,
		"hint": PROPERTY_HINT_FILE,
		"hint_string": "*.tscn",
	})
	set_input_event_forwarding_always_enabled()

	_pilot_button = Button.new()
	_pilot_button.flat = true
	_pilot_button.toggle_mode = true
	var icon := EditorInterface.get_editor_theme().get_icon("CharacterBody3D", "EditorIcons")
	var img := icon.get_image().duplicate()
	for x in img.get_width():
		for y in img.get_height():
			var pixel: Color = img.get_pixel(x, y)
			if pixel.a > 0.0:
				img.set_pixel(x, y, Color(1.0, 1.0, 1.0, pixel.a))
	_pilot_button.icon = ImageTexture.create_from_image(img)
	_pilot_button.toggled.connect(_on_pilot_button_toggled)
	add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, _pilot_button)

	var pilot_shortcut := editor_settings.get_shortcut(SHORTCUT_PATH)
	if pilot_shortcut:
		pilot_shortcut.changed.connect(_update_pilot_tooltip)
	_update_pilot_tooltip()

	overlay = Control.new()
	overlay.name = "FullscreenOverlay"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.draw.connect(_on_overlay_draw)


func _exit_tree() -> void:
	var pilot_shortcut := EditorInterface.get_editor_settings().get_shortcut(SHORTCUT_PATH)
	if pilot_shortcut and pilot_shortcut.changed.is_connected(_update_pilot_tooltip):
		pilot_shortcut.changed.disconnect(_update_pilot_tooltip)

	if pilot_active:
		exit_pilot_mode(_editor_camera, _canvas_viewport, _node3d_viewport)

	if _pilot_button:
		remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, _pilot_button)
		_pilot_button.queue_free()

	if is_instance_valid(overlay):
		overlay.queue_free()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		handle_focus_lost()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		handle_focus_gained()


func _input(event: InputEvent) -> void:
	if not pilot_active or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return

	if event is InputEventMouse:
		if _canvas_viewport:
			_canvas_viewport.push_input(event)
		get_viewport().set_input_as_handled()
		return

	if not event is InputEventKey:
		return

	var key := event as InputEventKey
	var editor_settings := EditorInterface.get_editor_settings()

	if key.is_pressed() and not key.is_echo():
		if key.keycode == KEY_ESCAPE or editor_settings.is_shortcut(SHORTCUT_PATH, event):
			exit_pilot_mode(_editor_camera, _canvas_viewport, _node3d_viewport)
			get_viewport().set_input_as_handled()
			return
		if editor_settings.is_shortcut("Open Industry Project/Start Simulation", event):
			Simulation.start()
			get_viewport().set_input_as_handled()
			return
		if editor_settings.is_shortcut("Open Industry Project/Toggle Pause Simulation", event):
			Simulation.toggle_pause()
			get_viewport().set_input_as_handled()
			return
		if editor_settings.is_shortcut("Open Industry Project/Stop Simulation", event):
			Simulation.stop()
			get_viewport().set_input_as_handled()
			return

	get_viewport().set_input_as_handled()


func _forward_3d_gui_input(_camera: Camera3D, event: InputEvent) -> int:
	var root := EditorInterface.get_edited_scene_root() as Node3D
	if not root:
		return AfterGUIInput.AFTER_GUI_INPUT_PASS

	var canvas_viewport := root.get_viewport()
	var node3d_viewport := _camera.get_viewport()

	if event is InputEventMouseButton and event.is_pressed():
		_last_camera = _camera
		_last_canvas_viewport = canvas_viewport
		_last_node3d_viewport = node3d_viewport

	var editor_settings := EditorInterface.get_editor_settings()

	if not pilot_active and event.is_pressed() and not event.is_echo() and editor_settings.is_shortcut(SHORTCUT_PATH, event):
		cache_editor_ui(node3d_viewport)
		enter_pilot_mode(_camera, canvas_viewport, node3d_viewport)
		return AfterGUIInput.AFTER_GUI_INPUT_STOP

	if not pilot_active:
		return AfterGUIInput.AFTER_GUI_INPUT_PASS

	canvas_viewport.push_input(event)
	return AfterGUIInput.AFTER_GUI_INPUT_STOP


func enter_pilot_mode(_camera: Camera3D, canvas_viewport: Viewport, node3d_viewport: Viewport) -> void:
	var scene_path: String = ProjectSettings.get_setting(SETTING_PATH, DEFAULT_SCENE)

	if not ResourceLoader.exists(scene_path):
		push_warning("Pilot Mode: Scene not found at '%s'." % scene_path)
		return

	var packed_scene := load(scene_path) as PackedScene
	if not packed_scene:
		push_warning("Pilot Mode: Failed to load scene at '%s'." % scene_path)
		return

	var instance := packed_scene.instantiate()
	pilot_node = instance as Node3D
	if not pilot_node:
		push_warning("Pilot Mode: Scene root must be a Node3D (or derived type). Got '%s'." % instance.get_class())
		instance.free()
		return

	var cam := get_pilot_camera()
	if not cam:
		push_warning("Pilot Mode: No Camera3D found in the scene.")
		pilot_node.free()
		pilot_node = null
		return

	InputMap.load_from_project_settings()

	var editor_settings := EditorInterface.get_editor_settings()
	_setup_action_from_shortcut(editor_settings, INTERACT_SHORTCUT_PATH, "interact")
	_setup_action_from_shortcut(editor_settings, MOVE_FORWARD_PATH, "pilot_move_forward")
	_setup_action_from_shortcut(editor_settings, MOVE_BACK_PATH, "pilot_move_back")
	_setup_action_from_shortcut(editor_settings, MOVE_LEFT_PATH, "pilot_move_left")
	_setup_action_from_shortcut(editor_settings, MOVE_RIGHT_PATH, "pilot_move_right")
	_setup_action_from_shortcut(editor_settings, JUMP_PATH, "pilot_jump")

	_cursor_position_before_pilot = DisplayServer.mouse_get_position()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	var spawn_transform := _camera.global_transform
	spawn_transform.origin -= spawn_transform.basis.y * SPAWN_Y_OFFSET
	pilot_node.global_transform = spawn_transform

	get_tree().edited_scene_root.add_child(pilot_node)
	pilot_active = true
	_editor_camera = _camera
	_canvas_viewport = canvas_viewport
	_node3d_viewport = node3d_viewport

	RenderingServer.viewport_attach_camera(node3d_viewport.get_viewport_rid(), cam.get_camera_rid())
	set_editor_ui_visible(false)
	_sync_pilot_button(true)
	pilot_mode_entered.emit()


func exit_pilot_mode(_camera: Camera3D, canvas_viewport: Viewport, node3d_viewport: Viewport) -> void:
	if not pilot_active:
		return

	if pilot_node.has_method("release_held_box"):
		pilot_node.release_held_box()
	if pilot_node.has_method("release_held_pallet"):
		pilot_node.release_held_pallet()

	var cam := get_pilot_camera()
	if cam:
		_camera.global_transform = cam.global_transform

	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	DisplayServer.warp_mouse(_cursor_position_before_pilot)
	get_tree().edited_scene_root.remove_child(pilot_node)
	pilot_node.queue_free()
	pilot_node = null
	pilot_active = false
	was_in_pilot_mode = false
	_editor_camera = null
	_canvas_viewport = null
	_node3d_viewport = null

	RenderingServer.viewport_attach_camera(node3d_viewport.get_viewport_rid(), _camera.get_camera_rid())
	set_editor_ui_visible(true)
	_sync_pilot_button(false)
	pilot_mode_exited.emit()


func handle_focus_lost() -> void:
	if not pilot_active or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return

	was_in_pilot_mode = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var main_window := EditorInterface.get_base_control()
	if is_instance_valid(main_window):
		main_window.add_child(overlay)
		overlay.visible = true
		overlay.queue_redraw()


func handle_focus_gained() -> void:
	if not was_in_pilot_mode or not pilot_active:
		return

	await get_tree().process_frame
	if not pilot_active:
		return

	var center := Vector2.ZERO
	var viewport := get_viewport()
	if viewport:
		center = viewport.get_visible_rect().size / 2
		viewport.warp_mouse(center)

	simulate_click(center)

	await get_tree().create_timer(FOCUS_RETURN_DELAY).timeout
	if not pilot_active:
		return

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	reset_camera_input()
	was_in_pilot_mode = false

	var main_window := EditorInterface.get_base_control()
	if is_instance_valid(overlay):
		main_window.remove_child(overlay)
		overlay.visible = false


func get_pilot_camera() -> Camera3D:
	if not pilot_node:
		return null
	var cameras := pilot_node.find_children("*", "Camera3D", true)
	return cameras[0] as Camera3D if cameras.size() > 0 else null


func cache_editor_ui(node3d_viewport: Viewport) -> void:
	_active_viewport_ui = {}
	var spatial_editor_viewport := node3d_viewport.get_parent().get_parent()
	if not spatial_editor_viewport:
		return

	var ui: Control
	for child in spatial_editor_viewport.get_children():
		if child.get_class() == "Control" and child.get_child_count() >= 7:
			ui = child
			break

	if not ui:
		push_warning("Pilot Mode: Could not locate editor viewport surface UI.")
		return

	var chrome: Array = []
	for child in ui.get_children():
		if not (child is TextureRect):
			chrome.append(child)

	if chrome.size() < 7:
		push_warning("Pilot Mode: Could not locate editor viewport surface UI.")
		return

	_active_viewport_ui = {
		"rotation_gizmo": chrome[6].get_child(0),
		"menu": chrome[0].get_child(0).get_child(0),
		"right_nav": chrome[5],
		"left_nav": chrome[4],
	}


func set_editor_ui_visible(visible: bool) -> void:
	if _active_viewport_ui.is_empty():
		return

	var show_nav := false
	if visible:
		show_nav = EditorInterface.get_editor_settings().get_setting(
			"editors/3d/navigation/show_viewport_navigation_gizmo"
		)

	_active_viewport_ui["rotation_gizmo"].visible = visible
	_active_viewport_ui["menu"].visible = visible
	_active_viewport_ui["right_nav"].visible = show_nav if visible else false
	_active_viewport_ui["left_nav"].visible = show_nav if visible else false


func _register_key_shortcut(editor_settings: EditorSettings, path: String, key: Key) -> void:
	var shortcut := Shortcut.new()
	var key_event := InputEventKey.new()
	key_event.keycode = key
	shortcut.events.append(key_event)
	editor_settings.add_shortcut(path, shortcut)


func _setup_action_from_shortcut(editor_settings: EditorSettings, shortcut_path: String, action_name: String) -> void:
	var sc := editor_settings.get_shortcut(shortcut_path)
	if sc and sc.events.size() > 0:
		if not InputMap.has_action(action_name):
			InputMap.add_action(action_name)
		else:
			InputMap.action_erase_events(action_name)
		InputMap.action_add_event(action_name, sc.events[0])


func simulate_click(position: Vector2) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = position
	Input.parse_input_event(press)

	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = position
	Input.parse_input_event(release)


func reset_camera_input() -> void:
	if not pilot_node:
		return
	var event := InputEventMouseMotion.new()
	event.relative = Vector2.ZERO
	Input.parse_input_event(event)


func _on_pilot_button_toggled(pressed: bool) -> void:
	if pressed and not pilot_active:
		if not _last_camera:
			_try_cache_default_viewport()
		if not _last_camera:
			push_warning("Pilot Mode: No 3D viewport available. Open a 3D scene first.")
			_sync_pilot_button(false)
			return
		cache_editor_ui(_last_node3d_viewport)
		enter_pilot_mode(_last_camera, _last_canvas_viewport, _last_node3d_viewport)
		if not pilot_active:
			_sync_pilot_button(false)
	elif not pressed and pilot_active:
		exit_pilot_mode(_editor_camera, _canvas_viewport, _node3d_viewport)


func _try_cache_default_viewport() -> void:
	var root := EditorInterface.get_edited_scene_root() as Node3D
	if not root:
		return
	var vp := EditorInterface.get_editor_viewport_3d(0)
	if not vp:
		return
	# The SubViewport's Camera3D child is the editor camera.
	# get_camera_3d() returns the scene's active camera, not the editor's.
	var cameras := vp.find_children("*", "Camera3D", false)
	if cameras.is_empty():
		return
	_last_camera = cameras[0] as Camera3D
	_last_canvas_viewport = root.get_viewport()
	_last_node3d_viewport = vp


func _update_pilot_tooltip() -> void:
	var sc := EditorInterface.get_editor_settings().get_shortcut(SHORTCUT_PATH)
	var shortcut_text := sc.get_as_text() if sc else ""
	var title := "Spawn Pilot Character"
	if not shortcut_text.is_empty() and shortcut_text != "None":
		title += " (" + shortcut_text + ")"
	_pilot_button.tooltip_text = title


func _sync_pilot_button(active: bool) -> void:
	if _pilot_button and _pilot_button.button_pressed != active:
		_pilot_button.set_pressed_no_signal(active)


func _on_overlay_draw() -> void:
	var window_size := get_window().get_size()
	overlay.draw_rect(Rect2(0, 0, window_size.x, window_size.y), Color(0, 0, 0, 0.1))
