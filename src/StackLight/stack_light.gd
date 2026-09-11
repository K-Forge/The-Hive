@tool
class_name StackLight
extends Node3D


## Number of light segments in the stack (1-10).
const RADIAL: int = 24
const RADIUS: float = 0.035
const STAND_HEIGHT: float = 0.196
const BASE_HEIGHT: float = 0.025
## Vertical span of one lit tier; also the spacing between tiers (STEP).
const SEGMENT_HEIGHT: float = 0.05
const TOP_HEIGHT: float = 0.014
# black seam band straddling each tier seam; a hair wider than the lens
const RING_HEIGHT: float = 0.006
const RING_RADIUS: float = RADIUS + 0.0015
# pale inner core the translucent lenses wrap around
const CORE_RADIUS: float = RADIUS - 0.006
# flat disc foot (rests on the floor) + slender pole making up STAND_HEIGHT
const FOOT_HEIGHT: float = 0.012
const FOOT_RADIUS: float = 0.032
const FOOT_TOP_RADIUS: float = 0.03
const STEM_RADIUS: float = 0.013
const STEM_HEIGHT: float = STAND_HEIGHT - FOOT_HEIGHT
# y of the first lens' bottom: above the stand and the base collar
const LENS_BOTTOM: float = STAND_HEIGHT + BASE_HEIGHT

## Number of light segments in the stack (1-8).
var segments: int = 1:
	set(value):
		var new_value: int = clamp(value, 1, 8)
		if new_value == segments:
			return

		segments = new_value

		if is_inside_tree():
			_data.set_segments(segments)

			var current_child_count := _segments_container.get_child_count()
			var difference := segments - current_child_count

			if difference > 0:
				_spawn_segments(difference)
			elif difference < 0:
				_remove_segments(-difference)

			_init_segments()

			# If segments were removed, mask the light value
			var new_light_value := light_value & ((1 << segments) - 1)
			if new_light_value != light_value:
				light_value = new_light_value
				_update_segment_visuals()

			_rebuild_dynamic()
		notify_property_list_changed()

## Bitmask controlling which segments are lit (bit 0 = segment 1, etc.).
var light_value: int = 0:
	set(value):
		var new_val: int = value % (1 << segments)
		if new_val == light_value:
			return
		light_value = new_val
		_update_segment_visuals()
		notify_property_list_changed()

## Enable communication with external PLC/control systems.
var enable_comms: bool = true
## Internal storage for the selected tag group name.
@export var tag_group_name: String
## The tag group for reading light values from external systems.
var _tag_groups: String:
	set(value):
		tag_group_name = value
		_tag_groups = value

## The tag name for the light value in the selected tag group.[br]Datatype: [code]BYTE[/code] (8-bit)[br][br]Format varies by protocol:[br][b]EIP:[/b] CIP tag names[br][b]Modbus:[/b] prefix+number (e.g. [code]hr0[/code])[br][b]OPC UA:[/b] full NodeId (e.g. [code]ns=2;s=MyVariable[/code] or [code]ns=2;i=12345[/code]).
var tag_name: String = ""

var _segment_scene: PackedScene = load("res://src/StackLight/StackSegment.tscn")
var _data: StackLightData = load("res://src/StackLight/StackLightData.tres")
var _prev_scale: Vector3
var _housing_material: StandardMaterial3D
var _tag := OIPCommsTag.new()
@onready var _foot: MeshInstance3D = get_node("Foot")
@onready var _stem: MeshInstance3D = get_node("Stem")
@onready var _base: MeshInstance3D = get_node("Base")
@onready var _core: MeshInstance3D = get_node("Core")
@onready var _cap: MeshInstance3D = get_node("Cap")
@onready var _segments_container: Node3D = get_node("Segments")
@onready var _rings_container: Node3D = get_node("Rings")


func _get(property: StringName) -> Variant:
	if not is_inside_tree() or not _segments_container:
		return null

	for i in range(segments):
		if property == "Light " + str(i + 1):
			var segment := _segments_container.get_child(i)
			return segment.segment_data
	return null


func _validate_property(property: Dictionary) -> void:
	if property.name == "tag_group_name":
		property.usage = PROPERTY_USAGE_STORAGE


func _get_property_list() -> Array[Dictionary]:
	var properties: Array[Dictionary] = []
	properties.append({
		"name": "light_value",
		"type": TYPE_INT,
		"usage": PROPERTY_USAGE_DEFAULT
	})
	properties.append({
		"name": "segments",
		"type": TYPE_INT,
		"usage": PROPERTY_USAGE_DEFAULT
	})
	properties.append({
		"name": "_data",
		"type": TYPE_OBJECT,
		"usage": PROPERTY_USAGE_NO_EDITOR
	})
	for i in range(segments - 1, -1, -1):
		properties.append({
			"name": "Light " + str(i + 1),
			"class_name": "StackSegmentData",
			"type": TYPE_OBJECT,
			"usage": PROPERTY_USAGE_DEFAULT | PROPERTY_USAGE_READ_ONLY
		})
	properties.append({
		"name": "Communications",
		"type": TYPE_NIL,
		"usage": PROPERTY_USAGE_CATEGORY
	})
	properties.append({
		"name": "enable_comms",
		"type": TYPE_BOOL,
		"usage": PROPERTY_USAGE_DEFAULT if OIPComms.get_enable_comms() else PROPERTY_USAGE_STORAGE
	})
	properties.append({
		"name": "tag_groups",
		"type": 0,
		"usage": PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_NO_INSTANCE_STATE if OIPComms.get_enable_comms() else PROPERTY_USAGE_NONE,
		"hint": 0,
		"hint_string": "tag_group_enum"
	})
	properties.append({
		"name": "tag_name",
		"type": TYPE_STRING,
		"usage": PROPERTY_USAGE_DEFAULT if OIPComms.get_enable_comms() else PROPERTY_USAGE_STORAGE
	})
	return properties


func _enter_tree() -> void:
	Simulation.started.connect(_on_simulation_started)
	tag_group_name = OIPCommsSetup.default_tag_group(tag_group_name)
	OIPCommsSetup.connect_comms(self, Callable(), _tag_group_polled)


func _ready() -> void:
	set_notify_transform(true)
	_data = _data.duplicate(true)
	_data.init_segments(segments)

	_build_housing()

	var current_child_count := _segments_container.get_child_count()
	var difference := segments - current_child_count

	if difference > 0:
		_spawn_segments(difference)
	elif difference < 0:
		for i in range(-difference):
			var child_to_remove_index := current_child_count - 1 - i
			if child_to_remove_index >= 0:
				var child_node := _segments_container.get_child(child_to_remove_index)
				child_node.queue_free()

	_fix_segment_positions()
	_init_segments()
	_rebuild_dynamic()
	_update_segment_visuals()
	_prev_scale = scale
	_rescale()


func _exit_tree() -> void:
	Simulation.started.disconnect(_on_simulation_started)
	OIPCommsSetup.disconnect_comms(self, Callable(), _tag_group_polled)
	if _segments_container:
		for i in range(_segments_container.get_child_count()):
			var segment_node := _segments_container.get_child(i)
			if segment_node.active_state_changed.is_connected(_on_segment_state_changed):
				segment_node.active_state_changed.disconnect(_on_segment_state_changed)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		if scale != _prev_scale:
			_rescale()
			_prev_scale = scale


func use() -> void:
	light_value += 1


# Procedural geometry never distorts: force a single uniform scale (driven by X).
func _rescale() -> void:
	scale = Vector3(scale.x, scale.x, scale.x)


func _build_housing() -> void:
	_housing_material = StandardMaterial3D.new()
	# StackLight.glb housing baseColorFactor is black; lifted a hair off pure black.
	_housing_material.albedo_color = Color8(23, 24, 27)
	_housing_material.metallic = 0.25
	_housing_material.roughness = 0.5

	var core_material := StandardMaterial3D.new()
	# pale core (GLB "Stack-light" mesh, linear factor); convert to sRGB for albedo
	core_material.albedo_color = Color(0.792, 0.819, 0.933).linear_to_srgb()
	core_material.metallic = 0.1
	core_material.roughness = 0.5

	_foot.mesh = _cylinder(FOOT_TOP_RADIUS, FOOT_RADIUS, FOOT_HEIGHT)
	_foot.material_override = _housing_material
	_foot.position = Vector3(0, FOOT_HEIGHT * 0.5, 0)

	_stem.mesh = _cylinder(STEM_RADIUS, STEM_RADIUS, STEM_HEIGHT)
	_stem.material_override = _housing_material
	_stem.position = Vector3(0, FOOT_HEIGHT + STEM_HEIGHT * 0.5, 0)

	_base.mesh = _cylinder(RADIUS, RADIUS, BASE_HEIGHT)
	_base.material_override = _housing_material
	_base.position = Vector3(0, STAND_HEIGHT + BASE_HEIGHT * 0.5, 0)

	# core height/position is set per tier count in _rebuild_dynamic
	_core.mesh = _cylinder(CORE_RADIUS, CORE_RADIUS, SEGMENT_HEIGHT)
	_core.material_override = core_material

	# cap is a near-cylinder with only a slight top bevel (top radius 0.9 R)
	_cap.mesh = _cylinder(RADIUS * 0.9, RADIUS, TOP_HEIGHT)
	_cap.material_override = _housing_material


func _rebuild_dynamic() -> void:
	var stack := segments * SEGMENT_HEIGHT
	var core_mesh := _core.mesh as CylinderMesh
	if core_mesh:
		core_mesh.height = stack
	_core.position = Vector3(0, LENS_BOTTOM + stack * 0.5, 0)
	_cap.position = Vector3(0, LENS_BOTTOM + stack + TOP_HEIGHT * 0.5, 0)
	_rebuild_rings()
	_increase_collision_shape()


func _rebuild_rings() -> void:
	for child in _rings_container.get_children():
		_rings_container.remove_child(child)
		child.queue_free()
	# one ring at every seam: base -> tier 0, between tiers, and tier N-1 -> cap
	var ring_mesh := _cylinder(RING_RADIUS, RING_RADIUS, RING_HEIGHT)
	for i in range(segments + 1):
		var ring := MeshInstance3D.new()
		ring.mesh = ring_mesh
		ring.material_override = _housing_material
		ring.position = Vector3(0, LENS_BOTTOM + i * SEGMENT_HEIGHT, 0)
		_rings_container.add_child(ring)


func _cylinder(top_radius: float, bottom_radius: float, height: float) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top_radius
	mesh.bottom_radius = bottom_radius
	mesh.height = height
	mesh.radial_segments = RADIAL
	mesh.rings = 1
	return mesh


func _tower_height(count: int) -> float:
	return STAND_HEIGHT + BASE_HEIGHT + count * SEGMENT_HEIGHT + TOP_HEIGHT


func _init_segments() -> void:
	for i in range(segments):
		if i >= _segments_container.get_child_count():
			printerr("Mismatch between segments count and child nodes during InitSegments")
			break
		var segment_node := _segments_container.get_child(i)
		segment_node.segment_data = _data.segment_datas[i]
		segment_node.index = i

		if not segment_node.active_state_changed.is_connected(_on_segment_state_changed):
			segment_node.active_state_changed.connect(_on_segment_state_changed)


func _spawn_segments(count: int) -> void:
	if not is_inside_tree():
		return
	var start_index := _segments_container.get_child_count()
	for i in range(count):
		var segment := _segment_scene.instantiate() as Node3D
		_segments_container.add_child(segment, true)
		var current_index := start_index + i
		segment.index = current_index
		segment.position = Vector3(0, LENS_BOTTOM + (current_index + 0.5) * SEGMENT_HEIGHT, 0)

		if current_index < _data.segment_datas.size():
			segment.segment_data = _data.segment_datas[current_index]
		else:
			printerr("Not enough data segments available when spawning segment %d" % current_index)
		segment.active_state_changed.connect(_on_segment_state_changed)


func _remove_segments(count: int) -> void:
	if not is_inside_tree():
		return
	var current_child_count := _segments_container.get_child_count()
	for i in range(count):
		var child_index := current_child_count - 1 - i
		if child_index < 0:
			break
		var segment_node := _segments_container.get_child(child_index)

		if segment_node.active_state_changed.is_connected(_on_segment_state_changed):
			segment_node.active_state_changed.disconnect(_on_segment_state_changed)
		segment_node.queue_free()


func _fix_segment_positions() -> void:
	if not is_inside_tree():
		return
	for i in range(_segments_container.get_child_count()):
		var segment_node := _segments_container.get_child(i)
		segment_node.position = Vector3(0, LENS_BOTTOM + (i + 0.5) * SEGMENT_HEIGHT, 0)


func _increase_collision_shape() -> void:
	var collision_shape: CollisionShape3D = $StaticBody3D/CollisionShape3D
	if collision_shape:
		var h := _tower_height(segments)
		var box := collision_shape.shape as BoxShape3D
		if box:
			box.size = Vector3(2.0 * RING_RADIUS, h, 2.0 * RING_RADIUS)
		collision_shape.position = Vector3(0, h * 0.5, 0)


func _update_segment_visuals() -> void:
	if not is_inside_tree():
		return
	for i in range(segments):
		if i < _data.segment_datas.size():
			var segment_data: StackSegmentData = _data.segment_datas[i]
			var is_active := (light_value >> i) & 1 == 1
			if segment_data.active != is_active:
				segment_data.active = is_active
		else:
			if i < _segments_container.get_child_count():
				var segment_node := _segments_container.get_child(i) as StackSegment
				segment_node._set_active(false)


func _on_segment_state_changed(index: int, active: bool) -> void:
	if index < 0 or index >= segments:
		printerr("Received state change for invalid index: ", index)
		return

	var current_bit := (1 << index)
	var newlight_value: int
	if active:
		newlight_value = light_value | current_bit
	else:
		newlight_value = light_value & ~current_bit

	self.light_value = newlight_value


func _on_simulation_started() -> void:
	if enable_comms:
		_tag.register(tag_group_name, tag_name, OIPComms.TAG_TYPE_UINT8)


func _tag_group_polled(tag_group_name_param: String) -> void:
	if not enable_comms or not _tag.matches_group(tag_group_name_param):
		return
	light_value = _tag.read_uint8()
