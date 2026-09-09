@tool
class_name DockDoorLeaf
extends Node3D

const _INTERACT_LAYER := 2
const _AUTO_LEVELER_SCENE := preload("res://assets/3DModels/DockDoor/AutoLeveler.tscn")

var travel_height: float = 4.5
var door_width: float = 3.0
var open_speed: float = 4.0

var door_scene: PackedScene
var door_z_offset: float = 0.39
var door_collision_depth: float = 0.18

var open: bool = false:
	set(value):
		open = value
		_target_y = travel_height if value else 0.0
		if not value:
			_retract_leveler()

var _panel: AnimatableBody3D
var _leveler: Node3D
var _leveler_deployed: bool = false
var _target_y: float = 0.0


func build() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()

	var h := travel_height
	var w := door_width
	var panel_depth := door_collision_depth

	_panel = AnimatableBody3D.new()
	_panel.name = "Panel"
	_panel.sync_to_physics = false
	_panel.collision_layer = 1 << 0
	_panel.collision_mask = 0
	add_child(_panel)

	if door_scene:
		var door_instance := door_scene.instantiate() as Node3D
		if door_instance:
			door_instance.name = "Leaf"
			door_instance.position = Vector3.ZERO
			_panel.add_child(door_instance)

			if Engine.is_editor_hint():
				var edited_root := get_tree().edited_scene_root
				if edited_root:
					door_instance.owner = edited_root

	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3(w * 0.98, h, panel_depth)
	shape.shape = box_shape
	shape.position = Vector3(0.0, h * 0.5, door_z_offset)
	_panel.add_child(shape)

	var interact := StaticBody3D.new()
	interact.name = "Interact"
	interact.collision_layer = 1 << (_INTERACT_LAYER - 1)
	interact.collision_mask = 0
	add_child(interact)

	var interact_shape := CollisionShape3D.new()
	var interact_box := BoxShape3D.new()
	interact_box.size = Vector3(w * 0.98, h, panel_depth)
	interact_shape.shape = interact_box
	interact_shape.position = Vector3(0.0, h * 0.5, door_z_offset)
	interact.add_child(interact_shape)

	_leveler = _AUTO_LEVELER_SCENE.instantiate() as Node3D
	_leveler.name = "AutoLeveler"
	_leveler_deployed = false
	add_child(_leveler)
	if Engine.is_editor_hint():
		var edited_root := get_tree().edited_scene_root
		if edited_root:
			_leveler.owner = edited_root

	_target_y = h if open else 0.0
	_panel.position.y = _target_y
	set_process(true)


func use() -> void:
	open = not open


func _process(delta: float) -> void:
	if _panel == null:
		return

	var current := _panel.position.y
	if not is_equal_approx(current, _target_y):
		_panel.position.y = move_toward(current, _target_y, open_speed * delta)
		return

	if open and not _leveler_deployed:
		_deploy_leveler()


func _deploy_leveler() -> void:
	_leveler_deployed = true
	if is_instance_valid(_leveler) and _leveler.has_method(&"run_cycle"):
		_leveler.call(&"run_cycle")


func _retract_leveler() -> void:
	_leveler_deployed = false
	if is_instance_valid(_leveler) and _leveler.has_method(&"reset_pose"):
		_leveler.call(&"reset_pose")
