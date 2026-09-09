@tool
class_name FloorMarking
extends ResizableNode3D


enum Style { SOLID, HAZARD, DASHED, BORDER, STRIPES }

const _SHADER_PATH := "res://src/FloorMarking/floor_marking.gdshader"

@export var style: Style = Style.HAZARD:
	set(value):
		style = value
		_apply_material()

@export var primary_color: Color = Color("f2b705"):
	set(value):
		primary_color = value
		_apply_material()

@export var secondary_color: Color = Color("1a1a1a"):
	set(value):
		secondary_color = value
		_apply_material()

## Stripe / dash period.
@export_range(0.05, 2.0, 0.05, "suffix:m") var stripe_size: float = 0.3:
	set(value):
		stripe_size = value
		_apply_material()

## Band width for the BORDER style.
@export_range(0.02, 1.0, 0.01, "suffix:m") var border_width: float = 0.1:
	set(value):
		border_width = value
		_apply_material()

## Lift above the floor to avoid z-fighting.
@export_range(0.001, 0.5, 0.001, "suffix:m") var height_offset: float = 0.01:
	set(value):
		height_offset = value
		if _mesh_instance:
			_mesh_instance.position.y = height_offset

var _mesh_instance: MeshInstance3D
var _plane_mesh: PlaneMesh
var _material: ShaderMaterial

static var instances: Array[FloorMarking] = []


func _init() -> void:
	super._init()
	size_default = Vector3(2.0, 0.02, 8.0)
	size_min = Vector3(0.1, 0.01, 0.1)


func _enter_tree() -> void:
	super._enter_tree()
	if has_meta("is_preview"):
		return
	if not instances.has(self):
		instances.append(self)


func _exit_tree() -> void:
	super._exit_tree()
	instances.erase(self)


func _ready() -> void:
	_ensure_nodes()
	_apply_material()
	_rebuild()


# Flat in Y: only the X and Z edge handles resize a marking.
func _get_active_resize_handle_ids() -> PackedInt32Array:
	return PackedInt32Array([0, 1, 4, 5])


func _ensure_nodes() -> void:
	if _mesh_instance == null:
		_mesh_instance = get_node_or_null(^"MarkingMesh")
	if _mesh_instance == null:
		_mesh_instance = MeshInstance3D.new()
		_mesh_instance.name = "MarkingMesh"
		_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_mesh_instance, false)
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = load(_SHADER_PATH)
	_mesh_instance.material_override = _material


func _on_size_changed() -> void:
	_rebuild()


func _rebuild() -> void:
	if _mesh_instance == null:
		return
	if _plane_mesh == null:
		_plane_mesh = PlaneMesh.new()
		_mesh_instance.mesh = _plane_mesh
	_plane_mesh.size = Vector2(size.x, size.z)
	_mesh_instance.position.y = height_offset
	if _material:
		_material.set_shader_parameter("marking_size", _plane_mesh.size)


func _apply_material() -> void:
	if _material == null:
		return
	_material.set_shader_parameter("primary_color", primary_color)
	_material.set_shader_parameter("secondary_color", secondary_color)
	_material.set_shader_parameter("style", int(style))
	_material.set_shader_parameter("stripe_size", stripe_size)
	_material.set_shader_parameter("border_width", border_width)
