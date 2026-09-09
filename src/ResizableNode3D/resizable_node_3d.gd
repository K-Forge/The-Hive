@tool
@abstract
class_name ResizableNode3D
extends Node3D

signal size_changed

## The axis index and direction of the handle used for the last resize.
## -1 means no specific handle (inspector or programmatic change).
## 0=+X, 1=-X, 2=+Y, 3=-Y, 4=+Z, 5=-Z.
var _resize_handle: int = -1
## The size before the current resize. Only valid during _on_size_changed.
var _resize_old_size: Vector3 = Vector3.ZERO
var _resize_context_active: bool = false

## The dimensions of this node in meters (X=length, Y=height, Z=width).
@export_custom(PROPERTY_HINT_NONE, "suffix:m") var size: Vector3 = Vector3.ZERO:
	set(value):
		if value == Vector3.ZERO:
			if size == Vector3.ZERO:
				size = size_default
				return
			value = size_default
		if not _resize_context_active:
			_resize_handle = -1
			_resize_old_size = size
		_resize_context_active = false
		var clamped_size: Vector3 = size_min.max(value)
		var constrained_size := _get_constrained_size(clamped_size)
		var has_changed := size != constrained_size
		size = constrained_size
		if has_changed:
			update_gizmos()
			_on_size_changed()
			size_changed.emit()


## Resize with explicit handle context. Use this instead of setting size
## directly when the resize is from a specific handle direction.
func resize(new_size: Vector3, handle_id: int) -> void:
	_resize_handle = handle_id
	_resize_old_size = size
	_resize_context_active = true
	size = new_size

var size_min: Vector3 = Vector3(0.01, 0.01, 0.01)
var size_default: Vector3 = Vector3.ONE
var original_size: Vector3 = Vector3.ZERO
var transform_in_progress: bool = false
var _scale_notification_cooldown: bool = false

func _init() -> void:
	set_meta("hijack_scale", true)
	set_notify_transform(true)

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_TRANSFORM_CHANGED:
			if not scale.is_equal_approx(Vector3.ONE) and not transform_in_progress:
				scale = Vector3.ONE

				if Engine.is_editor_hint() and not _scale_notification_cooldown:
					_scale_notification_cooldown = true
					EditorInterface.get_editor_toaster().push_toast(
						_get_scale_warning_text(),
						EditorToaster.SEVERITY_WARNING
					)
					get_tree().create_timer(1.0).timeout.connect(func() -> void:
						_scale_notification_cooldown = false
					)


func _get_scale_warning_text() -> String:
	return "Please use the 'size' property instead of scale."

func _enter_tree() -> void:
	if not Engine.is_editor_hint():
		return
	if not EditorInterface.transform_requested.is_connected(_transform_requested):
		EditorInterface.transform_requested.connect(_transform_requested)
	if not EditorInterface.transform_commited.is_connected(_transform_commited):
		EditorInterface.transform_commited.connect(_transform_commited)

func _exit_tree() -> void:
	if not Engine.is_editor_hint():
		return
	if EditorInterface.transform_requested.is_connected(_transform_requested):
		EditorInterface.transform_requested.disconnect(_transform_requested)
	if EditorInterface.transform_commited.is_connected(_transform_commited):
		EditorInterface.transform_commited.disconnect(_transform_commited)

func _transform_requested(data: Dictionary) -> void:
	if not EditorInterface.get_selection().get_selected_nodes().has(self):
		return

	if data.has("motion"):
		var md: Array = data["motion"]
		var mx: float = md[0]
		var my: float = md[1]
		var mz: float = md[2]
		var motion := Vector3(mx, my, mz)

		if not transform_in_progress:
			original_size = size
			transform_in_progress = true

		var new_size := original_size + motion
		new_size = _get_constrained_size(new_size)
		size = new_size

func _transform_commited() -> void:
	if transform_in_progress:
		if size != original_size:
			var undo_redo := EditorInterface.get_editor_undo_redo()
			undo_redo.create_action("Scale", UndoRedo.MERGE_ALL)
			undo_redo.add_do_property(self, "size", size)
			undo_redo.add_undo_property(self, "size", original_size)
			undo_redo.commit_action()

		transform_in_progress = false

func _on_size_changed() -> void:
	pass

func _get_constrained_size(new_size: Vector3) -> Vector3:
	return new_size

## Returns the local-space handle position for a given resize handle id.
## Override [_get_resize_local_bounds] to customize where handles sit.
func get_resize_handle_local_position(handle_id: int, for_size: Vector3 = size) -> Vector3:
	var bounds := _get_resize_local_bounds(for_size)
	var min_v: Vector3 = bounds.position
	var max_v: Vector3 = bounds.position + bounds.size
	var mid_x: float = (min_v.x + max_v.x) * 0.5
	var mid_y: float = (min_v.y + max_v.y) * 0.5
	var mid_z: float = (min_v.z + max_v.z) * 0.5

	match handle_id:
		0:
			return Vector3(max_v.x, mid_y, mid_z)
		1:
			return Vector3(min_v.x, mid_y, mid_z)
		2:
			return Vector3(mid_x, max_v.y, mid_z)
		3:
			return Vector3(mid_x, min_v.y, mid_z)
		4:
			return Vector3(mid_x, mid_y, max_v.z)
		5:
			return Vector3(mid_x, mid_y, min_v.z)
		_:
			return Vector3.ZERO

## Local bounds used by resize handles and fixed-edge anchoring logic.
## Default behavior assumes geometry centered on the node origin.
func _get_resize_local_bounds(for_size: Vector3) -> AABB:
	return AABB(-for_size * 0.5, for_size)


func _get_active_resize_handle_ids() -> PackedInt32Array:
	return PackedInt32Array([0, 1, 2, 3, 4, 5])
