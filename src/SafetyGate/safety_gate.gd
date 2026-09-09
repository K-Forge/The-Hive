@tool
class_name SafetyGate
extends Fence


## Color of the emergency stop handle.
@export var handle_color: Color = Color(0.79, 0.09, 0.09):
	set(value):
		handle_color = value
		_update_material_color()

## Current open state of the gate.
@export var open: bool = false:
	set(value):
		open = value
		_update_output()

## Swing angle when open. Negative swings the opposite way.
@export_range(-180.0, 180.0, 1.0, "suffix:°") var open_angle: float = 110.0

## Swing speed in degrees per second.
@export var open_speed: float = 180.0

## When true, output is inverted (true while closed, safety-circuit style).
@export var normally_closed: bool = false:
	set(value):
		normally_closed = value
		_update_output()

## Final output signal after applying normally_closed logic (read-only).
@export var output: bool = false:
	set(value):
		if _gate_tag.is_ready() and value != output:
			_gate_tag.write_bit(value)
		output = value

var _handle_material: ShaderMaterial
var _gate_tag := OIPCommsTag.new()

@onready var _leaf: Node3D = $Leaf
@onready var _leaf_mesh: MeshInstance3D = $Leaf/MeshInstance3D
@onready var _leaf_collision_shape: CollisionShape3D = $Leaf/LeafBody/CollisionShape3D

@export_category("Communications")
## Enable communication with external PLC/control systems.
@export var enable_comms: bool = false
@export var gate_tag_group_name: String
## The tag group for writing the gate output state.
@export_custom(0, "tag_group_enum") var gate_tag_groups: String:
	set(value):
		gate_tag_group_name = value
		gate_tag_groups = value
## The tag name for the gate output in the selected tag group.[br]Datatype: [code]BOOL[/code][br][br]Format varies by protocol:[br][b]EIP:[/b] CIP tag names[br][b]Modbus:[/b] prefix+number (e.g. [code]co0[/code])[br][b]OPC UA:[/b] full NodeId (e.g. [code]ns=2;s=MyVariable[/code] or [code]ns=2;i=12345[/code]).
@export var gate_tag_name: String = ""


func _init() -> void:
	super._init()
	size_default = Vector3(1.0, FenceMesh.FENCE_HEIGHT, FenceMesh.POST_SIZE)


func _validate_property(property: Dictionary) -> void:
	if property.name == "output":
		property.usage = PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY
	else:
		OIPCommsSetup.validate_tag_property(property, "gate_tag_group_name", "gate_tag_groups", "gate_tag_name")


func _enter_tree() -> void:
	super._enter_tree()
	gate_tag_group_name = OIPCommsSetup.default_tag_group(gate_tag_group_name)
	Simulation.started.connect(_on_simulation_started)
	OIPCommsSetup.connect_comms(self, _tag_group_initialized)


func _exit_tree() -> void:
	super._exit_tree()
	Simulation.started.disconnect(_on_simulation_started)
	OIPCommsSetup.disconnect_comms(self, _tag_group_initialized)


func _ready() -> void:
	if _leaf_collision_shape and _leaf_collision_shape.shape:
		_leaf_collision_shape.shape = _leaf_collision_shape.shape.duplicate() as BoxShape3D
	super._ready()
	if _leaf:
		_leaf.rotation.y = _target_angle()


func _setup_material() -> void:
	super._setup_material()
	_handle_material = FenceMesh.create_material(handle_color)


func _update_material_color() -> void:
	super._update_material_color()
	if _handle_material:
		_handle_material.set_shader_parameter("color", handle_color)


func _rebuild() -> void:
	if not is_instance_valid(_mesh_instance) or not is_instance_valid(_leaf_mesh):
		return

	var length := size.x
	var height := size.y

	_mesh_instance.mesh = SafetyGateMesh.create_posts(length, height, omit_post_start, omit_post_end)
	if _mesh_instance.mesh and _mesh_instance.mesh.get_surface_count() >= 2:
		_mesh_instance.set_surface_override_material(0, _post_material)
		_mesh_instance.set_surface_override_material(1, _mesh_material)

	_leaf.position = Vector3(-length / 2.0, 0, 0)
	_leaf_mesh.mesh = SafetyGateMesh.create_leaf(length, height)
	if _leaf_mesh.mesh and _leaf_mesh.mesh.get_surface_count() >= 2:
		_leaf_mesh.set_surface_override_material(0, _mesh_material)
		_leaf_mesh.set_surface_override_material(1, _handle_material)

	var leaf_span := length - SafetyGateMesh.LEAF_GAP * 2.0
	if _leaf_collision_shape and _leaf_collision_shape.shape is BoxShape3D:
		(_leaf_collision_shape.shape as BoxShape3D).size = Vector3(
			leaf_span, height, FenceMesh.POST_SIZE)
		_leaf_collision_shape.position = Vector3(
			SafetyGateMesh.LEAF_GAP + leaf_span / 2.0, height / 2.0, 0)

	if _collision_shape and _collision_shape.shape is BoxShape3D:
		(_collision_shape.shape as BoxShape3D).size = Vector3(length, height, 0.3)
		_collision_shape.position = Vector3(0, height / 2.0, 0)


func _process(delta: float) -> void:
	if not is_instance_valid(_leaf):
		return
	var target := _target_angle()
	if is_equal_approx(_leaf.rotation.y, target):
		return
	_leaf.rotation.y = move_toward(_leaf.rotation.y, target, deg_to_rad(open_speed) * delta)


func _target_angle() -> float:
	return deg_to_rad(open_angle) if open else 0.0


func use() -> void:
	open = not open


func _update_output() -> void:
	output = not open if normally_closed else open


func _on_simulation_started() -> void:
	if enable_comms:
		_gate_tag.register(gate_tag_group_name, gate_tag_name, OIPComms.TAG_TYPE_BOOL)


func _tag_group_initialized(tag_group_name_param: String) -> void:
	if _gate_tag.on_group_initialized(tag_group_name_param):
		_gate_tag.write_bit(output)


func _get_custom_preview_node() -> Node3D:
	var preview_scene := load("res://parts/SafetyGate.tscn") as PackedScene
	var preview_node := preview_scene.instantiate(PackedScene.GEN_EDIT_STATE_DISABLED) as Node3D
	preview_node.set_meta("is_preview", true)
	_disable_collisions_recursive(preview_node)
	return preview_node
