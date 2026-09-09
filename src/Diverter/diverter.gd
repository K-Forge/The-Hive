@tool
class_name Diverter
extends Node3D

## Button to toggle the diverter in the editor.
@export_tool_button("Toggle Divert") var divert_action: Callable = toggle_divert
## Time in seconds for the diverter to extend or retract.
@export_custom(PROPERTY_HINT_NONE, "suffix:s") var divert_time: float = 0.25
## Distance the diverter arm travels when extended.
@export_custom(PROPERTY_HINT_NONE, "suffix:m") var divert_distance: float = 0.75

var size: Vector3 = Vector3(0.722, 1.2, 2.127)

var _diverted: bool = false
var _tag := OIPCommsTag.new()
@onready var _diverter_animator: DiverterAnimator = $DiverterAnimator

@export_category("Communications")
## Enable communication with external PLC/control systems.
@export var enable_comms: bool = false
@export var tag_group_name: String
## The tag group for reading divert commands from external systems.
@export_custom(0, "tag_group_enum") var tag_groups: String:
	set(value):
		tag_group_name = value
		tag_groups = value
## The tag name for the divert trigger in the selected tag group.[br]Datatype: [code]BOOL[/code][br][br]Format varies by protocol:[br][b]EIP:[/b] CIP tag names[br][b]Modbus:[/b] prefix+number (e.g. [code]co0[/code])[br][b]OPC UA:[/b] full NodeId (e.g. [code]ns=2;s=MyVariable[/code] or [code]ns=2;i=12345[/code]).
@export var tag_name: String = ""

func _validate_property(property: Dictionary) -> void:
	OIPCommsSetup.validate_tag_property(property)

func _ready() -> void:
	if has_meta("is_preview"):
		return
	set_notify_transform(true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		ConveyorSnapping.notify_contacts_rebuild(self)

func _enter_tree() -> void:
	if has_meta("is_preview"):
		return
	tag_group_name = OIPCommsSetup.default_tag_group(tag_group_name)
	Simulation.started.connect(_on_simulation_started)
	OIPCommsSetup.connect_comms(self, _tag_group_initialized, _tag_group_polled)
	ConveyorSnapping.notify_contacts_rebuild(self)

func _exit_tree() -> void:
	if has_meta("is_preview"):
		return
	ConveyorSnapping.notify_contacts_rebuild(self)
	Simulation.started.disconnect(_on_simulation_started)
	OIPCommsSetup.disconnect_comms(self, _tag_group_initialized, _tag_group_polled)

func get_snap_features() -> Array:
	return [
		{
			"shape": ConveyorSnapFeatures.Shape.POINT,
			"kind": &"diverter_push_side",
			"local_pos": Vector3(0, 0, -size.z / 2.0),
			"local_outward": Vector3(0, 0, -1),
			"y_offset": ConveyorSnapFeatures.DIVERTER_Y_OFFSET,
			"outward_offset": ConveyorSnapFeatures.DIVERTER_SIDE_OFFSET,
			"end_name": &"push_side",
		},
	]


func _get_custom_preview_node() -> Node3D:
	var preview_scene := load("res://parts/Diverter.tscn") as PackedScene
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

func use() -> void:
	divert()

## Extend the diverter and hold it across the lane until retracted.
func divert() -> void:
	_diverted = true

## Retract the diverter back to its home position.
func retract() -> void:
	_diverted = false

func toggle_divert() -> void:
	_diverted = not _diverted

func _physics_process(_delta: float) -> void:
	_diverter_animator.set_target(_diverted, divert_time, divert_distance)

func _on_simulation_started() -> void:
	if enable_comms:
		_tag.register(tag_group_name, tag_name, OIPComms.TAG_TYPE_BOOL)

func _tag_group_initialized(tag_group_name_param: String) -> void:
	if _tag.on_group_initialized(tag_group_name_param):
		_tag.write_bit(_diverted)

func _tag_group_polled(tag_group_name_param: String) -> void:
	if not enable_comms or not _tag.matches_group(tag_group_name_param):
		return
	_diverted = _tag.read_bit()
