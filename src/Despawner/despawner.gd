@tool
class_name Despawner
extends Node3D

## When true, the despawner actively removes objects that enter its area.
@export var monitoring: bool = true:
	set(value):
		if _area_3d:
			_area_3d.monitoring = value
	get:
		return _area_3d.monitoring if _area_3d else true

@onready var _area_3d: Area3D = get_node("Area3D")


func _enter_tree() -> void:
	if _area_3d && not _area_3d.body_entered.is_connected(_body_entered):
		_area_3d.body_entered.connect(_body_entered)


func _ready() -> void:
	_area_3d.body_entered.connect(_body_entered)


func _exit_tree() -> void:
	_area_3d.body_entered.disconnect(_body_entered)


func _body_entered(node: Node) -> void:
	var _parent := node.get_parent()
	if _parent.has_method("selected") and _parent.get("instanced"):
		_parent.queue_free()
