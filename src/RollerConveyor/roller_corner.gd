@tool
class_name RollerCorner
extends Node3D

const MODEL_BASE_LENGTH: float = 2.0

## Length of the corner roller in meters.
@export_custom(PROPERTY_HINT_NONE, "suffix:m") var length: float = MODEL_BASE_LENGTH:
	set(value):
		length = value
		if _mesh_instance:
			_update_mesh_length()

var radial_scale: float = RollerSpec.radial_scale(RollerSpec.DutyClass.HEAVY):
	set(value):
		radial_scale = value
		if _mesh_instance:
			_update_mesh_length()

var angular_speed: float = 0.0
var _prev_global_basis: Basis = Basis.IDENTITY

@onready var _mesh_instance: MeshInstance3D = $MeshInstance3D


func _init() -> void:
	set_notify_transform(true)


func _ready() -> void:
	if _mesh_instance:
		_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_update_mesh_length()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and is_inside_tree():
		if _prev_global_basis == global_basis:
			return
		_prev_global_basis = global_basis


func get_material() -> Material:
	return _mesh_instance.mesh.surface_get_material(0)


func set_override_material(material: Material) -> void:
	_mesh_instance.set_surface_override_material(0, material)


func _update_mesh_length() -> void:
	_mesh_instance.scale = Vector3(radial_scale, radial_scale, length / MODEL_BASE_LENGTH)
