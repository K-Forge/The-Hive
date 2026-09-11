@tool
class_name Roller
extends Node3D

const BASE_LENGTH: float = 2.0
const BASE_CYLINDER_LENGTH: float = 0.935097 * 2.0
## End cap protrusion past its mount, in authored-mesh units (scales with radius).
const END_CAP_PROTRUSION: float = 0.08

## Outer radius in meters; set by the parent container from its duty class.
var radius: float = RollerSpec.radius(RollerSpec.DutyClass.HEAVY)

var _left_end_mesh: MeshInstance3D
var _right_end_mesh: MeshInstance3D
var _cylinder_mesh: MeshInstance3D

func _enter_tree() -> void:
	_ensure_node_references_initialized()

func set_length(length: float) -> void:
	set_length_and_offset(length, 0.0)

func set_length_and_offset(length: float, shaft_offset: float) -> void:
	_ensure_node_references_initialized()
	var rs := radius / RollerSpec.MODEL_RADIUS
	_left_end_mesh.position = Vector3(0, 0, shaft_offset - length / BASE_LENGTH)
	_left_end_mesh.scale = Vector3(rs, rs, rs)
	_right_end_mesh.position = Vector3(0, 0, shaft_offset + length / BASE_LENGTH)
	_right_end_mesh.scale = Vector3(rs, rs, rs)

	var cylinder_margins := (BASE_LENGTH - BASE_CYLINDER_LENGTH) * rs
	var new_cylinder_length := maxf(0.0, length - cylinder_margins)
	_cylinder_mesh.position = Vector3(0, 0, shaft_offset)
	_cylinder_mesh.scale = Vector3(rs, rs, new_cylinder_length / BASE_CYLINDER_LENGTH)

func set_roller_override_material(material: Material) -> void:
	_ensure_node_references_initialized()
	_left_end_mesh.set_surface_override_material(0, material)
	_right_end_mesh.set_surface_override_material(0, material)
	_cylinder_mesh.set_surface_override_material(0, material)

func _ensure_node_references_initialized() -> void:
	if _left_end_mesh == null:
		_left_end_mesh = get_node_or_null("RollerMeshes/RollerEndL") as MeshInstance3D
		if _left_end_mesh:
			_left_end_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	if _right_end_mesh == null:
		_right_end_mesh = get_node_or_null("RollerMeshes/RollerEndR") as MeshInstance3D
		if _right_end_mesh:
			_right_end_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	if _cylinder_mesh == null:
		_cylinder_mesh = get_node_or_null("RollerMeshes/RollerLength") as MeshInstance3D
		if _cylinder_mesh:
			_cylinder_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
