@tool
class_name LaserSensor
extends Node3D

## Maximum detection range of the laser sensor in meters.
@export_custom(PROPERTY_HINT_NONE, "suffix:m") var max_range: float = 1.524:
	set(value):
		value = clamp(value, 0, 100)
		max_range = value

## Toggle visibility of the laser beam visualization.
@export var show_beam: bool = true:
	set(value):
		show_beam = value
		if _instance:
			RenderingServer.instance_set_visible(_instance, show_beam)
			if show_beam:
				_beam_needs_update = true

## Current measured distance to detected object (read-only).
@export_custom(PROPERTY_HINT_NONE, "suffix:m") var distance: float = max_range:
	set(value):
		if _tag.is_ready() and value != distance:
			_tag.write_float32(value)
		distance = value

var _mesh: ImmediateMesh
static var _beam_material: StandardMaterial3D = preload("uid://ntmcfd25jgpm")
var _instance: RID
var _scenario: RID
var _ray_query: PhysicsRayQueryParameters3D
var _tag := OIPCommsTag.new()
var _last_distance: float = -1.0
var _last_beam_color: Color = Color.TRANSPARENT
var _last_transform: Transform3D
var _beam_needs_update: bool = true

@export_category("Communications")
## Enable communication with external PLC/control systems.
@export var enable_comms: bool = false
@export var tag_group_name: String
## The tag group for writing distance values to external systems.
@export_custom(0, "tag_group_enum") var tag_groups: String:
	set(value):
		tag_group_name = value
		tag_groups = value
## The tag name for the distance value in the selected tag group.[br]Datatype: [code]REAL[/code] (32-bit float)[br][br]Format varies by protocol:[br][b]EIP:[/b] CIP tag names[br][b]Modbus:[/b] prefix+number (e.g. [code]hr0[/code])[br][b]OPC UA:[/b] full NodeId (e.g. [code]ns=2;s=MyVariable[/code] or [code]ns=2;i=12345[/code]).
@export var tag_name: String = ""


func _validate_property(property: Dictionary) -> void:
	if property.name == "distance":
		property.usage = PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY
	else:
		OIPCommsSetup.validate_tag_property(property)


func _enter_tree() -> void:
	_instance = RenderingServer.instance_create()
	_scenario = get_world_3d().scenario
	_mesh = ImmediateMesh.new()

	RenderingServer.instance_set_scenario(_instance, _scenario)
	RenderingServer.instance_set_base(_instance, _mesh)
	RenderingServer.instance_set_visible(_instance, show_beam)
	_beam_needs_update = true

	_ray_query = PhysicsRayQueryParameters3D.new()
	_ray_query.collision_mask = 8

	tag_group_name = OIPCommsSetup.default_tag_group(tag_group_name)
	Simulation.started.connect(_on_simulation_started)
	OIPCommsSetup.connect_comms(self, _tag_group_initialized)


func _exit_tree() -> void:
	RenderingServer.free_rid(_instance)
	SensorBeamCache.clear_beam(get_instance_id())
	Simulation.started.disconnect(_on_simulation_started)
	OIPCommsSetup.disconnect_comms(self, _tag_group_initialized)


func _physics_process(_delta: float) -> void:
	var start_pos := global_position
	var dir := global_transform.basis.z.normalized()
	var end_pos := start_pos + dir * max_range

	_ray_query.from = start_pos
	_ray_query.to = end_pos
	var space_state := get_world_3d().direct_space_state
	var result := space_state.intersect_ray(_ray_query)

	var new_distance: float
	var beam_color: Color
	if result.size() > 0:
		new_distance = start_pos.distance_to(result["position"])
		beam_color = Color.RED
	else:
		new_distance = max_range
		beam_color = Color.GREEN

	if new_distance != distance:
		distance = new_distance
	
	var current_transform := global_transform
	var beam_end := start_pos + dir * max_range
	if _beam_needs_update or new_distance != _last_distance or beam_color != _last_beam_color or current_transform != _last_transform:
		if show_beam:
			_update_beam_mesh(start_pos, new_distance, beam_color)
		SensorBeamCache.set_beam(get_instance_id(), start_pos, beam_end)
		_last_distance = new_distance
		_last_beam_color = beam_color
		_last_transform = current_transform
		_beam_needs_update = false


func _update_beam_mesh(start_pos: Vector3, beam_distance: float, beam_color: Color) -> void:
	_mesh.clear_surfaces()
	_mesh.surface_begin(Mesh.PRIMITIVE_LINES, _beam_material)
	_mesh.surface_set_color(beam_color)
	_mesh.surface_add_vertex(start_pos)
	_mesh.surface_set_color(beam_color)
	_mesh.surface_add_vertex(start_pos + global_transform.basis.z.normalized() * beam_distance)
	_mesh.surface_end()


func use() -> void:
	show_beam = not show_beam


func get_snap_features() -> Array:
	return [
		{
			"shape": ConveyorSnapFeatures.Shape.POINT,
			"kind": &"sensor_beam_mount",
			"local_pos": Vector3.ZERO,
			"local_outward": Vector3(0, 0, 1),
			"face_inward": true,
			"y_offset": -ConveyorSnapFeatures.SENSOR_GUARD_LIFT,
			"outward_offset": ConveyorSnapFeatures.SENSOR_GUARD_OFFSET,
			"auto_fit_range": true,
			"end_name": &"sensor",
		},
	]


func _get_custom_preview_node() -> Node3D:
	var preview_scene := load("res://parts/LaserSensor.tscn") as PackedScene
	var preview_node := preview_scene.instantiate(PackedScene.GEN_EDIT_STATE_DISABLED) as Node3D
	preview_node.set_meta("is_preview", true)
	_disable_collisions_recursive(preview_node)
	return preview_node


static func _disable_collisions_recursive(node: Node) -> void:
	if node is CollisionShape3D:
		(node as CollisionShape3D).disabled = true
	if node is CollisionObject3D:
		var body := node as CollisionObject3D
		body.collision_layer = 0
		body.collision_mask = 0
	for child in node.get_children():
		_disable_collisions_recursive(child)


func _on_simulation_started() -> void:
	if enable_comms:
		_tag.register(tag_group_name, tag_name, OIPComms.TAG_TYPE_FLOAT32)


func _tag_group_initialized(tag_group_name_param: String) -> void:
	if _tag.on_group_initialized(tag_group_name_param):
		_tag.write_float32(distance)
