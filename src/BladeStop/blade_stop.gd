@tool
class_name BladeStop
extends Node3D

## When true, the blade is raised to stop items.
@export var active: bool = false:
	set(value):
		active = value
		if not is_inside_tree():
			return
			
		if active:
			_up()
		else:
			_down()

## Vertical offset for the blade's base position (adjusts mounting height).
@export_custom(PROPERTY_HINT_NONE, "suffix:m") var air_pressure_height: float = 0.15:
	set(value):
		air_pressure_height = value
		if not is_inside_tree():
			return
			
		_blade.position = Vector3(_blade.position.x, air_pressure_height + _active_pos if active else air_pressure_height, _blade.position.z)
		_air_pressure_r.position = Vector3(_air_pressure_r.position.x, air_pressure_height, _air_pressure_r.position.z)
		_air_pressure_l.position = Vector3(_air_pressure_l.position.x, air_pressure_height, _air_pressure_l.position.z)

const SNAP_BLADE_X_OFFSET: float = 0.103
## Visual Z width at scale.z = 1, calibrated from the scene's 0.448 → 1.524 m belt match.
const SNAP_NATIVE_Z_WIDTH: float = 1.524 / 0.448

const NATIVE_BLADE_WIDTH: float = 0.052
const BLADE_FIT_WIDTH: float = 0.022
const BLADE_LOCAL_X: float = 0.1036
const BLADE_CORNER_LOCAL_X: float = 0.1048

var _active_pos: float = 0.24
var _tag := OIPCommsTag.new()
@onready var _blade: StaticBody3D = $Blade
@onready var _air_pressure_r: MeshInstance3D = $Corners/AirPressureR
@onready var _air_pressure_l: MeshInstance3D = $Corners/AirPressureL
@onready var _blade_corner_r: MeshInstance3D = $Corners/AirPressureR/BladeCornerR
@onready var _blade_corner_l: MeshInstance3D = $Corners/AirPressureL/BladeCornerL

@export_category("Communications")
## Enable communication with external PLC/control systems.
@export var enable_comms: bool = false
@export var tag_group_name: String
## The tag group for reading/writing the active state.
@export_custom(0, "tag_group_enum") var tag_groups: String:
	set(value):
		tag_group_name = value
		tag_groups = value
## The tag name for the blade stop state in the selected tag group.[br]Datatype: [code]BOOL[/code][br][br]Format varies by protocol:[br][b]EIP:[/b] CIP tag names[br][b]Modbus:[/b] prefix+number (e.g. [code]co0[/code])[br][b]OPC UA:[/b] full NodeId (e.g. [code]ns=2;s=MyVariable[/code] or [code]ns=2;i=12345[/code]).
@export var tag_name: String = ""


func _validate_property(property: Dictionary) -> void:
	OIPCommsSetup.validate_tag_property(property)


func _get_property_list() -> Array[Dictionary]:
	var props: Array[Dictionary] = [{
		"name": "width",
		"type": TYPE_FLOAT,
		"usage": PROPERTY_USAGE_EDITOR,
		"hint": PROPERTY_HINT_RANGE,
		"hint_string": "0.1,2.0,0.05,suffix:m",
	}]
	return props


func _get(property: StringName) -> Variant:
	if property == &"width":
		return scale.z * SNAP_NATIVE_Z_WIDTH
	return null


func _set(property: StringName, value: Variant) -> bool:
	if property == &"width":
		scale = Vector3(scale.x, scale.y, maxf(0.01, float(value) / SNAP_NATIVE_Z_WIDTH))
		return true
	return false


func get_snap_features() -> Array:
	return [
		{
			"shape": ConveyorSnapFeatures.Shape.POINT,
			"kind": &"blade_anchor",
			"local_pos": Vector3(SNAP_BLADE_X_OFFSET, 0, 0),
			"local_outward": Vector3(0, 1, 0),
			"target_local_y": ConveyorSnapFeatures.BLADE_STOP_TARGET_LOCAL_Y,
			# Loose threshold so drops near a roller conveyor still catch.
			"visible_threshold": 2.0,
			"auto_fit_target_width": true,
			"native_z_width": SNAP_NATIVE_Z_WIDTH,
		},
	]


# Required so the editor's _sanitize_preview_node doesn't strip the script.
func _get_custom_preview_node() -> Node3D:
	var preview_scene := load("res://parts/BladeStop.tscn") as PackedScene
	var preview_node := preview_scene.instantiate(PackedScene.GEN_EDIT_STATE_DISABLED) as Node3D
	preview_node.set_meta("is_preview", true)
	_disable_collisions_recursive(preview_node)
	return preview_node


func _disable_collisions_recursive(node: Node) -> void:
	if node is CollisionShape3D:
		(node as CollisionShape3D).disabled = true
	if node is CollisionObject3D:
		var body := node as CollisionObject3D
		body.collision_layer = 0
		body.collision_mask = 0
	for child in node.get_children():
		_disable_collisions_recursive(child)


func _enter_tree() -> void:
	if has_meta("is_preview"):
		return
	tag_group_name = OIPCommsSetup.default_tag_group(tag_group_name)
	Simulation.started.connect(_on_simulation_started)
	OIPCommsSetup.connect_comms(self, _tag_group_initialized, _tag_group_polled)


func _exit_tree() -> void:
	if has_meta("is_preview"):
		return
	Simulation.started.disconnect(_on_simulation_started)
	OIPCommsSetup.disconnect_comms(self, _tag_group_initialized, _tag_group_polled)


func _ready() -> void:
	_fit_blade_to_rollers()
	_air_pressure_r.position = Vector3(_air_pressure_r.position.x, air_pressure_height, _air_pressure_r.position.z)
	_air_pressure_l.position = Vector3(_air_pressure_l.position.x, air_pressure_height, _air_pressure_l.position.z)
	var blade_y: float = (air_pressure_height + _active_pos) if active else air_pressure_height
	_blade.position = Vector3(_blade.position.x, blade_y, _blade.position.z)
	var corner_y: float = _active_pos if active else 0.0
	_blade_corner_r.position = Vector3(_blade_corner_r.position.x, corner_y, _blade_corner_r.position.z)
	_blade_corner_l.position = Vector3(_blade_corner_l.position.x, corner_y, _blade_corner_l.position.z)


func _fit_blade_to_rollers() -> void:
	var s: float = BLADE_FIT_WIDTH / NATIVE_BLADE_WIDTH
	_thin_segment_x(_blade, BLADE_LOCAL_X, s)
	_thin_segment_x(_blade_corner_r, BLADE_CORNER_LOCAL_X, s)
	_thin_segment_x(_blade_corner_l, BLADE_CORNER_LOCAL_X, s)


func _thin_segment_x(node: Node3D, local_x: float, s: float) -> void:
	node.scale = Vector3(s, node.scale.y, node.scale.z)
	node.position = Vector3(local_x * (1.0 - s), node.position.y, node.position.z)


func use() -> void:
	active = not active


func _up() -> void:
	var tween := create_tween().set_parallel()
	tween.tween_property(_blade, "position", Vector3(_blade.position.x, air_pressure_height + _active_pos, _blade.position.z), 0.15)
	tween.tween_property(_blade_corner_r, "position", Vector3(_blade_corner_r.position.x, _active_pos, _blade_corner_r.position.z), 0.15)
	tween.tween_property(_blade_corner_l, "position", Vector3(_blade_corner_l.position.x, _active_pos, _blade_corner_l.position.z), 0.15)


func _down() -> void:
	var tween := create_tween().set_parallel()
	tween.tween_property(_blade, "position", Vector3(_blade.position.x, air_pressure_height, _blade.position.z), 0.15)
	tween.tween_property(_blade_corner_r, "position", Vector3(_blade_corner_r.position.x, 0, _blade_corner_r.position.z), 0.15)
	tween.tween_property(_blade_corner_l, "position", Vector3(_blade_corner_l.position.x, 0, _blade_corner_l.position.z), 0.15)


func _on_simulation_started() -> void:
	if enable_comms:
		_tag.register(tag_group_name, tag_name, OIPComms.TAG_TYPE_BOOL)


func _tag_group_initialized(tag_group_name_param: String) -> void:
	if _tag.on_group_initialized(tag_group_name_param):
		_tag.write_bit(active)


func _tag_group_polled(tag_group_name_param: String) -> void:
	if not enable_comms or not _tag.matches_group(tag_group_name_param):
		return
	active = _tag.read_bit()
