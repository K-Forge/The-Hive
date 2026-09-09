@tool
class_name DockDoor
extends Node3D

@export_range(1, 2) var door_count: int = 1:
	set(value):
		door_count = clampi(value, 1, 2)
		notify_property_list_changed()
		_rebuild()

@export var travel_height: float = 4.5:
	set(value):
		travel_height = value
		_rebuild()

@export var door_width: float = 3.0:
	set(value):
		door_width = value
		_rebuild()

@export var open_speed: float = 4.0

@export var door_1_open: bool = false:
	set(value):
		door_1_open = value
		_set_leaf_open(0, value)

@export var door_2_open: bool = false:
	set(value):
		door_2_open = value
		_set_leaf_open(1, value)

@export var wall_a_scene: PackedScene:
	set(value):
		wall_a_scene = value
		_rebuild()

@export var wall_b_scene: PackedScene:
	set(value):
		wall_b_scene = value
		_rebuild()

@export var door_scene: PackedScene:
	set(value):
		door_scene = value
		_rebuild()

@export var door_z_offset: float = 0.39:
	set(value):
		door_z_offset = value
		_rebuild()

@export var door_collision_depth: float = 0.18:
	set(value):
		door_collision_depth = value
		_rebuild()

var _leaves: Array[DockDoorLeaf] = []
var _render_layers: int = 2


func _ready() -> void:
	_rebuild()


func _validate_property(property: Dictionary) -> void:
	if property.name == "door_2_open" and door_count < 2:
		property.usage &= ~PROPERTY_USAGE_EDITOR


func set_render_layer(layers: int) -> void:
	_render_layers = layers
	for mesh in find_children("*", "MeshInstance3D", true):
		(mesh as MeshInstance3D).layers = layers


func get_first_leaf() -> DockDoorLeaf:
	return _leaves[0] if not _leaves.is_empty() else null


func _set_leaf_open(index: int, value: bool) -> void:
	if index < _leaves.size() and _leaves[index]:
		_leaves[index].open = value


func _rebuild() -> void:
	if not is_node_ready():
		return

	for child in get_children():
		remove_child(child)
		child.queue_free()
	_leaves.clear()

	var n := clampi(door_count, 1, 2)

	var wall_instance: Node3D = null
	if n == 1 and wall_a_scene:
		wall_instance = wall_a_scene.instantiate() as Node3D
	elif n == 2 and wall_b_scene:
		wall_instance = wall_b_scene.instantiate() as Node3D

	if wall_instance:
		wall_instance.name = "Surround"
		add_child(wall_instance)

	var opening_centers := [5.0] if n == 1 else [2.75, 7.25]

	for i in range(n):
		var leaf := DockDoorLeaf.new()
		leaf.name = "Door%d" % (i + 1)
		leaf.travel_height = travel_height
		leaf.door_width = door_width
		leaf.open_speed = open_speed
		leaf.door_scene = door_scene
		leaf.door_z_offset = door_z_offset
		leaf.door_collision_depth = door_collision_depth
		leaf.open = door_2_open if i == 1 else door_1_open
		leaf.position = Vector3(opening_centers[i], 0.0, 0.0)
		add_child(leaf)
		leaf.build()
		_leaves.append(leaf)

	set_render_layer(_render_layers)
