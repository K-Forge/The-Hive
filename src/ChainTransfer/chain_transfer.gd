@tool
class_name ChainTransfer
extends Node3D

const BASE_LENGTH: float = 2.0
const SHAPE_Y_OFFSET: float = -0.094
const SHAPE_HEIGHT: float = 0.2
const SHAPE_EDGE_MARGIN: float = 0.042
const SHAPE_END_CAP: float = 0.25
const LANE_NATIVE_THICKNESS: float = 0.087
const LANE_FIT_THICKNESS: float = 0.04
## Visual Z width at scale.z = 1, calibrated from the scene's 0.575 → 1.524 m belt match.
const SNAP_NATIVE_Z_WIDTH: float = 1.524 / 0.575


func get_snap_features() -> Array:
	var ct_center_offset: float = (chains - 1) * distance / 2.0
	var anchor_kind: StringName = (
		&"chain_transfer_anchor_gap" if chains % 2 == 1
		else &"chain_transfer_anchor_on"
	)
	return [
		{
			"shape": ConveyorSnapFeatures.Shape.POINT,
			"kind": anchor_kind,
			"local_pos": Vector3(ct_center_offset, 0, 0),
			"local_outward": Vector3(0, 1, 0),
			"target_local_y": ConveyorSnapFeatures.CHAIN_TRANSFER_TARGET_LOCAL_Y,
			"track_extent": ct_center_offset,
			"match_step_property": &"distance",
			"step_array_count": chains,
			# Loose threshold so drops near a roller conveyor still catch.
			"visible_threshold": 2.0,
			"auto_fit_target_width": true,
			"native_z_width": SNAP_NATIVE_Z_WIDTH,
		},
	]


## Number of chain lanes (1-10).
@export var chains: int = 5:
	set(value):
		chains = clamp(value, 1, 10)
		_sync_chain_count()

## Distance between chain lanes in meters.
@export_range(0.03, 5.0, 0.01, "suffix:m") var distance: float = 0.33:
	set(value):
		distance = clamp(value, 0.03, 5.0)
		_position_bases()
		_update_simple_shape()

## Speed of the chains in meters per second.
@export_custom(PROPERTY_HINT_NONE, "suffix:m/s") var speed: float = 2.0

## When true, chains are raised to lift products off the main conveyor.
@export var popup_chains: bool = false:
	set(value):
		popup_chains = value
		if chain_transfer_bases:
			for base: ChainTransferBase in chain_transfer_bases.get_children():
				base.active = popup_chains

@export_category("Communications")
## Enable communication with external PLC/control systems.
@export var enable_comms: bool = false
@export var speed_tag_group_name: String
## The tag group for reading speed values from external systems.
@export_custom(0, "tag_group_enum") var speed_tag_groups: String:
	set(value):
		speed_tag_group_name = value
		speed_tag_groups = value
## The tag name for the speed value in the selected tag group.[br]Datatype: [code]REAL[/code] (32-bit float)[br][br]Format varies by protocol:[br][b]EIP:[/b] CIP tag names[br][b]Modbus:[/b] prefix+number (e.g. [code]hr0[/code])[br][b]OPC UA:[/b] full NodeId (e.g. [code]ns=2;s=MyVariable[/code] or [code]ns=2;i=12345[/code]).
@export var speed_tag_name: String = ""
@export var popup_tag_group_name: String
## The tag group for reading popup state from external systems.
@export_custom(0, "tag_group_enum") var popup_tag_groups: String:
	set(value):
		popup_tag_group_name = value
		popup_tag_groups = value
## The tag name for the popup state in the selected tag group.[br]Datatype: [code]BOOL[/code][br][br]Format varies by protocol:[br][b]EIP:[/b] CIP tag names[br][b]Modbus:[/b] prefix+number (e.g. [code]co0[/code])[br][b]OPC UA:[/b] full NodeId (e.g. [code]ns=2;s=MyVariable[/code] or [code]ns=2;i=12345[/code]).
@export var popup_tag_name: String = ""

var _prev_scale: Vector3 = Vector3.ONE
var _speed_tag := OIPCommsTag.new()
var _popup_tag := OIPCommsTag.new()
var _chain_transfer_base_scene: PackedScene = load("res://src/ChainTransfer/Base.tscn")

var chain_transfer_bases: Node3D:
	get:
		return get_node_or_null("ChainBases")

func _init() -> void:
	set_notify_local_transform(true)

func _notification(what: int) -> void:
	if what == NOTIFICATION_LOCAL_TRANSFORM_CHANGED:
		if scale != _prev_scale:
			_lock_scale_to_z_axis()

func _ready() -> void:
	_sync_chain_count()
	_lock_scale_to_z_axis()

func _enter_tree() -> void:
	if has_meta("is_preview"):
		return
	Simulation.started.connect(_on_simulation_started)
	Simulation.stopped.connect(_on_simulation_ended)
	speed_tag_group_name = OIPCommsSetup.default_tag_group(speed_tag_group_name)
	popup_tag_group_name = OIPCommsSetup.default_tag_group(popup_tag_group_name)
	OIPCommsSetup.connect_comms(self, _tag_group_initialized, _tag_group_polled)

func _exit_tree() -> void:
	if has_meta("is_preview"):
		return
	Simulation.started.disconnect(_on_simulation_started)
	Simulation.stopped.disconnect(_on_simulation_ended)
	OIPCommsSetup.disconnect_comms(self, _tag_group_initialized, _tag_group_polled)

func _validate_property(property: Dictionary) -> void:
	if OIPCommsSetup.validate_tag_property(property, "speed_tag_group_name", "speed_tag_groups", "speed_tag_name"):
		return
	OIPCommsSetup.validate_tag_property(property, "popup_tag_group_name", "popup_tag_groups", "popup_tag_name")


func _get_property_list() -> Array[Dictionary]:
	var props: Array[Dictionary] = [{
		"name": "lane_length",
		"type": TYPE_FLOAT,
		"usage": PROPERTY_USAGE_EDITOR,
		"hint": PROPERTY_HINT_RANGE,
		"hint_string": "0.5,3.0,0.05,suffix:m",
	}]
	return props


func _get(property: StringName) -> Variant:
	if property == &"lane_length":
		return scale.z * SNAP_NATIVE_Z_WIDTH
	return null


func _set(property: StringName, value: Variant) -> bool:
	if property == &"lane_length":
		scale.z = maxf(0.01, float(value) / SNAP_NATIVE_Z_WIDTH)
		_lock_scale_to_z_axis()
		return true
	return false

func use() -> void:
	popup_chains = not popup_chains

func _lock_scale_to_z_axis() -> void:
	_prev_scale = Vector3(1, 1, scale.z)
	scale = _prev_scale
	_update_simple_shape()

func _position_bases() -> void:
	if not chain_transfer_bases:
		return
	# Base-local Z maps to the conveyor flow axis; scaling it thins each lane.
	var lane_scale: float = LANE_FIT_THICKNESS / LANE_NATIVE_THICKNESS
	var base_basis: Basis = Basis(Vector3(0, 0, -1), Vector3(0, 1, 0), Vector3(lane_scale, 0, 0))
	for base: ChainTransferBase in chain_transfer_bases.get_children():
		base.transform = Transform3D(base_basis, Vector3(distance * base.get_index(), 0, 0))

func _sync_chain_count() -> void:
	var bases := chain_transfer_bases
	if not bases:
		return
	while bases.get_child_count() > chains:
		var extra := bases.get_child(bases.get_child_count() - 1)
		bases.remove_child(extra)
		extra.queue_free()
	while bases.get_child_count() < chains:
		var chain_base := _chain_transfer_base_scene.instantiate() as ChainTransferBase
		bases.add_child(chain_base, true)
		chain_base.active = popup_chains
		if Simulation.is_running():
			chain_base.turn_on()
	_position_bases()
	_update_simple_shape()

func _on_simulation_started() -> void:
	if chain_transfer_bases:
		for base: ChainTransferBase in chain_transfer_bases.get_children():
			base.turn_on()

	if enable_comms:
		_speed_tag.register(speed_tag_group_name, speed_tag_name, OIPComms.TAG_TYPE_FLOAT32)
		_popup_tag.register(popup_tag_group_name, popup_tag_name, OIPComms.TAG_TYPE_BOOL)

func _on_simulation_ended() -> void:
	if chain_transfer_bases:
		for base: ChainTransferBase in chain_transfer_bases.get_children():
			base.turn_off()

func _get_custom_preview_node() -> Node3D:
	var preview_scene := load("res://parts/ChainTransfer.tscn") as PackedScene
	var preview_node := preview_scene.instantiate(PackedScene.GEN_EDIT_STATE_DISABLED) as Node3D
	preview_node.set_meta("is_preview", true)

	_disable_collisions_recursive(preview_node)

	var chain_bases_node := preview_node.get_node_or_null("ChainBases")
	if chain_bases_node:
		for base in chain_bases_node.get_children():
			base.set_process_mode(Node.PROCESS_MODE_DISABLED)

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


func _update_simple_shape() -> void:
	var simple_conveyor_shape_body := get_node_or_null("SimpleConveyorShape") as Node3D
	if not simple_conveyor_shape_body:
		return
	var simple_conveyor_shape_node := simple_conveyor_shape_body.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if not simple_conveyor_shape_node:
		return
	simple_conveyor_shape_node.position = Vector3((chains - 1) * distance / 2.0, SHAPE_Y_OFFSET, 0)
	var simple_conveyor_shape := simple_conveyor_shape_node.shape as BoxShape3D
	if simple_conveyor_shape:
		simple_conveyor_shape.size = Vector3(
			(chains - 1) * distance + SHAPE_EDGE_MARGIN * 2.0,
			SHAPE_HEIGHT,
			BASE_LENGTH + SHAPE_END_CAP / scale.z,
		)

func _tag_group_initialized(tag_group_name_param: String) -> void:
	_speed_tag.on_group_initialized(tag_group_name_param)
	_popup_tag.on_group_initialized(tag_group_name_param)

func _tag_group_polled(tag_group_name_param: String) -> void:
	if not enable_comms:
		return

	if _speed_tag.matches_group(tag_group_name_param):
		speed = _speed_tag.read_float32()
	if _popup_tag.matches_group(tag_group_name_param):
		popup_chains = _popup_tag.read_bit()
