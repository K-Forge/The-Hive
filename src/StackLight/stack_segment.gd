@tool
class_name StackSegment
extends Node3D

signal active_state_changed(index: int, active: bool)

## The data resource controlling this segment's active state and color.
@export var segment_data: StackSegmentData:
	set(value):
		if segment_data:
			segment_data.active_changed.disconnect(_on_active_changed)
			segment_data.color_changed.disconnect(_on_color_changed)

		segment_data = value as StackSegmentData

		if _material != null and segment_data != null:
			_set_active(segment_data.active)
			_set_segment_color(segment_data.segment_color)

		segment_data.active_changed.connect(_on_active_changed)
		segment_data.color_changed.connect(_on_color_changed)

var index: int = -1
@onready var _mesh_instance: MeshInstance3D = $LightMesh
var _material: StandardMaterial3D

func _ready() -> void:
	var lens := CylinderMesh.new()
	lens.top_radius = StackLight.RADIUS
	lens.bottom_radius = StackLight.RADIUS
	lens.height = StackLight.SEGMENT_HEIGHT
	lens.radial_segments = StackLight.RADIAL
	lens.rings = 1
	_mesh_instance.mesh = lens

	_material = StandardMaterial3D.new()
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.roughness = 0.5
	_material.metallic = 0.0
	_material.emission_enabled = true
	_material.emission_energy_multiplier = 0.0
	_material.albedo_color = Color(0.7, 0.7, 0.7, 1.0)
	_mesh_instance.set_surface_override_material(0, _material)

	if segment_data:
		segment_data.active_changed.disconnect(_on_active_changed)
		segment_data.color_changed.disconnect(_on_color_changed)

		_set_active(segment_data.active)
		_set_segment_color(segment_data.segment_color)

		segment_data.active_changed.connect(_on_active_changed)
		segment_data.color_changed.connect(_on_color_changed)

func _set_active(new_value: bool) -> void:
	if _material == null:
		return
	
	if new_value:
		_material.emission_energy_multiplier = 1.0
		var opaque_color := Color(segment_data.segment_color.r, segment_data.segment_color.g, segment_data.segment_color.b, 235.0/255.0)
		_material.albedo_color = opaque_color
		_material.emission = Color(segment_data.segment_color.r, segment_data.segment_color.g, segment_data.segment_color.b, 1.0)
	else:
		_material.emission_energy_multiplier = 0.0
		_material.albedo_color = Color(0.7, 0.7, 0.7, 1.0)
		_material.emission = Color(0.0, 0.0, 0.0, 1.0)

func _set_segment_color(new_value: Color) -> void:
	if _material and segment_data and segment_data.active:
		var albedo_color := Color(new_value.r, new_value.g, new_value.b, 235.0/255.0)
		var emission_color := Color(new_value.r, new_value.g, new_value.b, 1.0)
		_material.albedo_color = albedo_color
		_material.emission = emission_color

func _on_active_changed(new_active: bool) -> void:
	_set_active(new_active)
	active_state_changed.emit(index, new_active)

func _on_color_changed(new_color: Color) -> void:
	_set_segment_color(new_color)
