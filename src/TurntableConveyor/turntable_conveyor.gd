@tool
class_name TurntableConveyor
extends ResizableNode3D

signal speed_changed(new_speed: float)
signal roller_override_material_changed(material: Material)

const _LEG_INSET: float = 0.15
const _LEG_HALF_WIDTH: float = 0.15
const _ROLLER_RIM: float = 0.06
const _PLATE_FACTOR: float = 1.5
const _PLATE_TOP_FACTOR: float = 1.8
const _FRAME_TOP_FACTOR: float = 0.3
const _FRAME_EMBED: float = 0.01
const _BRACKET_LEN: float = 0.06
const _ANGLE_EPSILON: float = 0.05

@export var roller_class: RollerSpec.DutyClass = RollerSpec.DutyClass.HEAVY:
	set(value):
		if roller_class == value:
			return
		roller_class = value
		_apply_roller_class()

## Roller lane width (the roller length across the middle). The round plate sizes
## itself to this; rollers taper to the plate edge toward the front/back.
@export_range(0.1, 5.0, 0.01, "or_greater", "suffix:m") var width: float = 1.524:
	set(value):
		var d: float = maxf(0.1, value) * _PLATE_FACTOR
		size = Vector3(d, size.y, d)
	get:
		return size.x / _PLATE_FACTOR

@export_range(0.05, 5.0, 0.01, "or_greater", "suffix:m") var height: float = 0.5:
	set(value):
		size = Vector3(size.x, value, size.x)
	get:
		return size.y

@export_custom(PROPERTY_HINT_NONE, "suffix:m/s") var speed: float = 1.0:
	set(value):
		if value == speed:
			return
		speed = value
		speed_changed.emit(value)
		_update_conveyor_velocity()

## Physics material applied to the deck surface body.
@export var physics_material: PhysicsMaterial = preload("res://parts/RollerSurfaceMaterial.tres"):
	set(value):
		physics_material = value
		_apply_physics_material()


@export_group("Rotation")
## Setpoint the deck rotates toward while the simulation runs. In the editor it
## previews the deck orientation immediately.
@export_range(-180.0, 180.0, 0.1, "or_greater", "or_less", "degrees") var target_angle: float = 0.0:
	set(value):
		target_angle = value
		if not _simulating():
			current_angle = value

## Slew rate of the deck while rotating toward the target.
@export_range(1.0, 360.0, 1.0, "or_greater", "degrees") var rotation_speed: float = 45.0

var current_angle: float = 0.0:
	set(value):
		current_angle = value
		_apply_pivot_rotation()


@export_group("Legs")
## Support legs spaced evenly around the plate, reaching from under the deck down to
## [member floor_plane]. They stay fixed while the deck rotates above them.
@export var legs_enabled: bool = true:
	set(value):
		if legs_enabled == value:
			return
		legs_enabled = value
		_request_legs_refresh()

## Number of legs evenly spaced around the turntable.
@export_range(0, 12, 1) var leg_count: int = 4:
	set(value):
		var clamped: int = maxi(0, value)
		if leg_count == clamped:
			return
		leg_count = clamped
		_request_legs_refresh()

## World-space plane the legs reach down to. Independent of the node's transform.
@export var floor_plane: Plane = Plane(Vector3.UP, -2.0):
	set(value):
		if floor_plane.is_equal_approx(value):
			return
		floor_plane = value
		_request_legs_refresh()

@export var leg_model_scene: PackedScene = preload("res://parts/StraightLeg.tscn"):
	set(value):
		leg_model_scene = value
		_request_legs_refresh()


@export_category("Communications")
@export var enable_comms: bool = false
@export var speed_tag_group_name: String
@export_custom(0, "tag_group_enum") var speed_tag_groups: String:
	set(value):
		speed_tag_group_name = value
		speed_tag_groups = value
## The tag name for the roller speed in the selected tag group.[br]Datatype: [code]REAL[/code] (32-bit float)[br][br]Format varies by protocol:[br][b]EIP:[/b] CIP tag names[br][b]Modbus:[/b] prefix+number (e.g. [code]hr0[/code])[br][b]OPC UA:[/b] full NodeId (e.g. [code]ns=2;s=MyVariable[/code] or [code]ns=2;i=12345[/code]).
@export var speed_tag_name: String = ""
@export var target_angle_tag_group_name: String
@export_custom(0, "tag_group_enum") var target_angle_tag_groups: String:
	set(value):
		target_angle_tag_group_name = value
		target_angle_tag_groups = value
## The tag name for the commanded deck angle (degrees) in the selected tag group.[br]Datatype: [code]REAL[/code] (32-bit float)[br][br]Format varies by protocol:[br][b]EIP:[/b] CIP tag names[br][b]Modbus:[/b] prefix+number (e.g. [code]hr0[/code])[br][b]OPC UA:[/b] full NodeId (e.g. [code]ns=2;s=MyVariable[/code] or [code]ns=2;i=12345[/code]).
@export var target_angle_tag_name: String = ""


var _pivot: Node3D
var _deck: Node3D
var _rollers: AbstractRollerContainer
var _simple_conveyor_shape: AnimatableBody3D
var _frame_l: MeshInstance3D
var _frame_r: MeshInstance3D
var _plate: MeshInstance3D
var _base_mesh: MeshInstance3D
var _base_body: StaticBody3D
var _roller_material: BaseMaterial3D
var _plate_material: ShaderMaterial
var _guard_material: ShaderMaterial
var _motor_material: StandardMaterial3D
var _flow_arrow: Node3D
var _last_size: Vector3 = Vector3.ZERO
var _legs_state: Dictionary = {}
var _legs_refresh_pending: bool = false
var _speed_tag := OIPCommsTag.new()
var _target_angle_tag := OIPCommsTag.new()


func _init() -> void:
	super._init()
	size_default = Vector3(2.286, 0.5, 2.286)


func _enter_tree() -> void:
	super._enter_tree()
	speed_tag_group_name = OIPCommsSetup.default_tag_group(speed_tag_group_name)
	target_angle_tag_group_name = OIPCommsSetup.default_tag_group(target_angle_tag_group_name)
	if not Simulation.started.is_connected(_on_simulation_started):
		Simulation.started.connect(_on_simulation_started)
	if not Simulation.stopped.is_connected(_on_simulation_ended):
		Simulation.stopped.connect(_on_simulation_ended)
	OIPCommsSetup.connect_comms(self, _tag_group_initialized, _tag_group_polled)
	ConveyorSnapping.notify_contacts_rebuild(self)


func _exit_tree() -> void:
	ConveyorSnapping.notify_contacts_rebuild(self)
	if is_instance_valid(_flow_arrow):
		FlowDirectionArrow.unregister(_flow_arrow)
	if Simulation.started.is_connected(_on_simulation_started):
		Simulation.started.disconnect(_on_simulation_started)
	if Simulation.stopped.is_connected(_on_simulation_ended):
		Simulation.stopped.disconnect(_on_simulation_ended)
	OIPCommsSetup.disconnect_comms(self, _tag_group_initialized, _tag_group_polled)
	super._exit_tree()


func _ready() -> void:
	_reset_preview_holder_transform()
	_resolve_nodes()
	_setup_material()
	_setup_conveyor_physics()
	_setup_roller_initialization()
	_last_size = Vector3.ZERO
	_on_size_changed()
	current_angle = target_angle
	_rebuild_legs()
	_legs_state = LegFooting.capture_leg_state(self)


func _validate_property(property: Dictionary) -> void:
	var prop_name: String = property["name"]
	if prop_name in ["width", "height"]:
		property["usage"] = PROPERTY_USAGE_EDITOR
		return
	if prop_name == "size":
		property["usage"] = PROPERTY_USAGE_STORAGE
		return
	if OIPCommsSetup.validate_tag_property(property, "speed_tag_group_name", "speed_tag_groups", "speed_tag_name"):
		return
	OIPCommsSetup.validate_tag_property(property, "target_angle_tag_group_name", "target_angle_tag_groups", "target_angle_tag_name")


func _notification(what: int) -> void:
	super._notification(what)
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		_update_conveyor_velocity()
		_request_legs_refresh()
		ConveyorSnapping.notify_contacts_rebuild(self)


func _get_scale_warning_text() -> String:
	return "Use `width` / `height` instead of scale."


func _get_resize_local_bounds(for_size: Vector3) -> AABB:
	return AABB(Vector3(-for_size.x * 0.5, -for_size.y, -for_size.z * 0.5), for_size)


func _get_editor_rotation_lock() -> int:
	return (1 << 0) | (1 << 2)


# Keep the footprint square (X == Z) so the deck stays circular; a handle drag on
# either axis sets the diameter.
func _get_constrained_size(new_size: Vector3) -> Vector3:
	var d: float
	if not is_equal_approx(new_size.x, size.x):
		d = new_size.x
	elif not is_equal_approx(new_size.z, size.z):
		d = new_size.z
	else:
		d = maxf(new_size.x, new_size.z)
	d = maxf(0.3, d)
	return Vector3(d, new_size.y, d)


var local_bbox: AABB:
	get:
		return _get_resize_local_bounds(size)


func _get_active_resize_handle_ids() -> PackedInt32Array:
	return PackedInt32Array([0, 1, 4, 5])


func _simulating() -> bool:
	return Simulation.is_running() and not Simulation.is_paused()


func _roller_radius() -> float:
	return RollerSpec.radius(roller_class)


func _roller_pitch() -> float:
	return RollerSpec.pitch(roller_class)


func _resolve_nodes() -> void:
	_pivot = get_node_or_null("Pivot") as Node3D
	_deck = get_node_or_null("Pivot/Deck") as Node3D
	_rollers = get_node_or_null("Pivot/Deck/Rollers") as AbstractRollerContainer
	_frame_l = get_node_or_null("Pivot/Deck/SideFrameL") as MeshInstance3D
	_frame_r = get_node_or_null("Pivot/Deck/SideFrameR") as MeshInstance3D
	_simple_conveyor_shape = get_node_or_null("Pivot/Deck/SimpleConveyorShape") as AnimatableBody3D
	_plate = get_node_or_null("Pivot/Plate") as MeshInstance3D
	_base_mesh = get_node_or_null("Base") as MeshInstance3D
	_base_body = get_node_or_null("Base/BaseBody") as StaticBody3D


func _setup_material() -> void:
	# Object-space triplanar so the metal grain doesn't stretch around the round plate.
	_plate_material = (ConveyorFrameMesh.create_material().duplicate()) as ShaderMaterial
	if _plate_material:
		_plate_material.set_shader_parameter("triplanar", true)
		_plate_material.set_shader_parameter("triplanar_scale", 1.0)
	_guard_material = SideGuardMesh.create_material()
	_motor_material = StandardMaterial3D.new()
	_motor_material.albedo_color = Color(0.62, 0.64, 0.68)
	_motor_material.albedo_texture = load("res://assets/3DModels/Textures/Metal.png")
	_motor_material.uv1_triplanar = true
	_motor_material.uv1_scale = Vector3(4.0, 4.0, 4.0)
	_motor_material.metallic = 0.55
	_motor_material.roughness = 0.42


func _setup_conveyor_physics() -> void:
	if _simple_conveyor_shape == null:
		return
	var cs := _simple_conveyor_shape.get_node_or_null("CollisionShape3D") as CollisionShape3D
	# The packed-scene shape is resource-cached across instances; give each its own.
	if cs and cs.shape:
		cs.shape = cs.shape.duplicate() as Shape3D
	_apply_physics_material()
	_update_conveyor_velocity()


func _setup_roller_initialization() -> void:
	var roller_material := load("res://assets/3DModels/Materials/Metall2.tres").duplicate(true) as Material
	set_roller_override_material(roller_material)
	if _rollers:
		_setup_roller_container(_rollers)


func _setup_roller_container(container: AbstractRollerContainer) -> void:
	if container is MultiMeshRollers:
		var mm := container as MultiMeshRollers
		roller_override_material_changed.connect(mm.set_roller_override_material)
		mm.set_roller_override_material(_roller_material)
	container.roller_radius = _roller_radius()
	container.roller_pitch = _roller_pitch()
	container.setup_existing_rollers()
	container.set_roller_skew_angle(0.0)
	container.set_width(size.z)
	container.set_length(size.x)


func set_roller_override_material(material: Material) -> void:
	_roller_material = material as BaseMaterial3D
	roller_override_material_changed.emit(material)


func _apply_roller_class() -> void:
	if not is_inside_tree():
		return
	if _rollers:
		_rollers.set_roller_radius(_roller_radius())
		_rollers.set_roller_pitch(_roller_pitch())
	_update_component_positions()
	ConveyorSnapping.notify_contacts_rebuild(self)
	if Engine.is_editor_hint():
		update_gizmos()


func _apply_physics_material() -> void:
	if _simple_conveyor_shape:
		_simple_conveyor_shape.physics_material_override = physics_material


func _apply_pivot_rotation() -> void:
	if _pivot:
		_pivot.rotation.y = deg_to_rad(current_angle)


func _on_size_changed() -> void:
	if _last_size == size:
		return
	_last_size = size
	_update_component_positions()
	_update_base()
	_update_motor()
	_rebuild_legs()
	_update_flow_arrow()
	ConveyorSnapping.notify_contacts_rebuild(self)
	if Engine.is_editor_hint():
		update_gizmos()


func _update_component_positions() -> void:
	var len_x: float = size.x
	var w: float = size.z
	var h: float = size.y
	var radius: float = _roller_radius()
	if _deck:
		_deck.position = Vector3(-len_x * 0.5, 0.0, 0.0)
	if _rollers:
		_rollers.position = Vector3(0.0, -radius, 0.0)
		if _rollers is MultiMeshRollers:
			var mm := _rollers as MultiMeshRollers
			mm.set_clip_override(_circular_clip)
			mm.set_clip_span(_ROLLER_RIM, len_x - _ROLLER_RIM)
		_rollers.set_width(w)
		_rollers.set_length(len_x)
	_update_side_frames()
	_update_roller_brackets()
	if _simple_conveyor_shape:
		_simple_conveyor_shape.position = Vector3(len_x * 0.5, -h * 0.5, 0.0)
		var cs := _simple_conveyor_shape.get_node_or_null("CollisionShape3D") as CollisionShape3D
		if cs and cs.shape is BoxShape3D:
			(cs.shape as BoxShape3D).size = Vector3(size.x, size.y, _lane_width())


# Each roller is shortened to the chord of the deck circle at its X (long across the
# center, short toward the ends), but capped at the lane half-width so the middle stays
# a constant-width lane and only the outer rollers taper to the rim.
func _circular_clip(x: float) -> Vector3:
	var r_bed: float = maxf(0.0, size.x * 0.5 - _ROLLER_RIM)
	var dx: float = x - size.x * 0.5
	var half_sq: float = r_bed * r_bed - dx * dx
	if half_sq <= 0.0:
		return Vector3.ZERO
	var half: float = minf(_lane_width() * 0.5, sqrt(half_sq))
	return Vector3(-half, half, 2.0 * half)


func _lane_width() -> float:
	return size.x / _PLATE_FACTOR


func _plate_top_y() -> float:
	return -_PLATE_TOP_FACTOR * _roller_radius()


func _plate_bottom_y() -> float:
	return -size.y


func _update_side_frames() -> void:
	var lane: float = _lane_width()
	var half_lane: float = lane * 0.5
	var r_bed: float = maxf(0.0, size.x * 0.5 - _ROLLER_RIM)
	var rail_len: float = 2.0 * sqrt(maxf(0.0, r_bed * r_bed - half_lane * half_lane))
	var wt: float = ConveyorFrameMesh.WALL_THICKNESS
	var deck_center_x: float = size.x * 0.5
	var base_y: float = _plate_top_y() - _FRAME_EMBED
	var frame_top: float = -_FRAME_TOP_FACTOR * _roller_radius()
	var rail_h: float = maxf(0.02, frame_top - base_y)
	_reconcile_side_frame(_frame_l, rail_len, rail_h, deck_center_x, base_y, -half_lane - wt, false)
	_reconcile_side_frame(_frame_r, rail_len, rail_h, deck_center_x, base_y, half_lane + wt, true)


func _reconcile_side_frame(mi: MeshInstance3D, rail_len: float, rail_h: float,
		x: float, y: float, z: float, flipped: bool) -> void:
	if mi == null:
		return
	if rail_len < 0.05:
		mi.visible = false
		return
	mi.visible = true
	var mesh := ConveyorFrameMesh.create(rail_len, rail_h, true, true, true)
	if _guard_material:
		mesh.surface_set_material(0, _guard_material)
	mi.mesh = mesh
	mi.position = Vector3(x, y, z)
	mi.rotation = Vector3(0.0, PI if flipped else 0.0, 0.0)


# End brackets for the tapered outer rollers that the straight side frames don't reach:
# one short L-profile segment at each end of each such roller, following the bed circle.
func _update_roller_brackets() -> void:
	if _deck == null or not (_rollers is MultiMeshRollers):
		return
	var node := _deck.get_node_or_null("RollerBrackets") as MultiMeshInstance3D
	if node == null:
		node = MultiMeshInstance3D.new()
		node.name = "RollerBrackets"
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		_deck.add_child(node, false, Node.INTERNAL_MODE_FRONT)
	var mm := node.multimesh
	if mm == null:
		mm = MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		node.multimesh = mm
	var base_y: float = _plate_top_y() - _FRAME_EMBED
	var frame_top: float = -_FRAME_TOP_FACTOR * _roller_radius()
	var rail_h: float = maxf(0.02, frame_top - base_y)
	var bracket_mesh := ConveyorFrameMesh.create(_BRACKET_LEN, rail_h)
	if _guard_material:
		bracket_mesh.surface_set_material(0, _guard_material)
	mm.mesh = bracket_mesh
	var lane_half: float = _lane_width() * 0.5
	var wt: float = ConveyorFrameMesh.WALL_THICKNESS
	var flip := Basis(Vector3.UP, PI)
	var xforms: Array[Transform3D] = []
	for p: Dictionary in (_rollers as MultiMeshRollers).get_roller_placements():
		var half: float = float(p["length"]) * 0.5
		if half >= lane_half - 0.01:
			continue  # full-lane roller, already held by the side frames
		var lx: float = float(p["x"])
		var cz: float = float(p["z"])
		xforms.append(Transform3D(Basis.IDENTITY, Vector3(lx, base_y, cz - half - wt)))
		xforms.append(Transform3D(flip, Vector3(lx, base_y, cz + half + wt)))
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])


func _update_base() -> void:
	var plate_radius: float = size.x * 0.5
	var plate_top: float = _plate_top_y()
	var plate_bottom: float = _plate_bottom_y()
	var plate_height: float = maxf(0.02, plate_top - plate_bottom)
	if _plate:
		var plate_mesh := CylinderMesh.new()
		plate_mesh.top_radius = plate_radius
		plate_mesh.bottom_radius = plate_radius
		plate_mesh.height = plate_height
		_plate.mesh = plate_mesh
		if _plate_material:
			_plate.set_surface_override_material(0, _plate_material)
		_plate.position = Vector3(0.0, (plate_top + plate_bottom) * 0.5, 0.0)
	if _base_mesh:
		_base_mesh.mesh = null
	if _base_body:
		var bcs := _base_body.get_node_or_null("CollisionShape3D") as CollisionShape3D
		if bcs:
			bcs.shape = null
	_update_plate_bolts()


func _update_plate_bolts() -> void:
	if _pivot == null:
		return
	var node := _pivot.get_node_or_null("PlateBolts") as MultiMeshInstance3D
	if node == null:
		node = MultiMeshInstance3D.new()
		node.name = "PlateBolts"
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		_pivot.add_child(node, false, Node.INTERNAL_MODE_FRONT)
	var mm := node.multimesh
	if mm == null:
		mm = MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		node.multimesh = mm
	var hex := mm.mesh as CylinderMesh
	if hex == null:
		hex = CylinderMesh.new()
		hex.radial_segments = 6
		mm.mesh = hex
	hex.top_radius = ConveyorFrameMesh.FRAME_BOLT_RADIUS
	hex.bottom_radius = ConveyorFrameMesh.FRAME_BOLT_RADIUS
	hex.height = ConveyorFrameMesh.FRAME_BOLT_HEIGHT
	hex.material = ConveyorFrameMesh.create_bolt_material()
	var plate_radius: float = size.x * 0.5
	var bolt_y: float = _plate_top_y() - 0.06
	var count: int = maxi(8, int(round(TAU * plate_radius / 0.25)))
	var r_b: float = plate_radius + ConveyorFrameMesh.FRAME_BOLT_HEIGHT * 0.5
	mm.instance_count = count
	for i in count:
		var ang: float = TAU * float(i) / float(count)
		# Bolt base seated on the cylinder surface, head pointing radially outward.
		var radial := Vector3(cos(ang), 0.0, sin(ang))
		var bx := Vector3.UP.cross(radial).normalized()
		var bz := bx.cross(radial).normalized()
		var center := Vector3(radial.x * r_b, bolt_y, radial.z * r_b)
		mm.set_instance_transform(i, Transform3D(Basis(bx, radial, bz), center))


# Right-angle drive gearmotor on the deck beside the roller bed (rotates with the deck),
# mounted just outside the side frame with the motor body sticking past the plate edge.
func _update_motor() -> void:
	if _pivot == null:
		return
	var motor := _pivot.get_node_or_null("Motor") as Node3D
	if motor == null:
		motor = Node3D.new()
		motor.name = "Motor"
		_pivot.add_child(motor, false, Node.INTERNAL_MODE_FRONT)
	var lane_half: float = _lane_width() * 0.5
	var cy: float = _plate_top_y() + 0.08 - _FRAME_EMBED
	var frame_outer: float = lane_half + ConveyorFrameMesh.WALL_THICKNESS + ConveyorFrameMesh.FLANGE_WIDTH
	var gbz: float = frame_outer + 0.1
	var x_along := Vector3(0.0, 0.0, PI * 0.5)   # cylinder axis Y → X (along the flow)

	var gearbox := _ensure_motor_part(motor, "Gearbox")
	var gb := BoxMesh.new()
	gb.size = Vector3(0.15, 0.16, 0.13)
	gb.material = _motor_material
	gearbox.mesh = gb
	gearbox.rotation = Vector3.ZERO
	gearbox.position = Vector3(0.0, cy, gbz)

	var housing := _ensure_motor_part(motor, "ShaftHousing")
	var hb := BoxMesh.new()
	hb.size = Vector3(0.09, 0.11, 0.08)
	hb.material = _motor_material
	housing.mesh = hb
	housing.rotation = Vector3.ZERO
	housing.position = Vector3(0.0, cy, frame_outer + 0.045)

	var shaft := _ensure_motor_part(motor, "OutputShaft")
	var sh := CylinderMesh.new()
	sh.top_radius = 0.018
	sh.bottom_radius = 0.018
	sh.height = 0.08
	sh.material = _motor_material
	shaft.mesh = sh
	shaft.rotation = Vector3(PI * 0.5, 0.0, 0.0)
	shaft.position = Vector3(0.0, cy, frame_outer + 0.045)

	var body := _ensure_motor_part(motor, "MotorBody")
	var bm := CylinderMesh.new()
	bm.top_radius = 0.07
	bm.bottom_radius = 0.07
	bm.height = 0.22
	bm.material = _motor_material
	body.mesh = bm
	body.rotation = x_along
	body.position = Vector3(0.185, cy, gbz)

	var fins := _ensure_motor_part(motor, "Fins")
	var fn := CylinderMesh.new()
	fn.top_radius = 0.086
	fn.bottom_radius = 0.086
	fn.height = 0.12
	fn.material = _motor_material
	fins.mesh = fn
	fins.rotation = x_along
	fins.position = Vector3(0.13, cy, gbz)

	var cowl := _ensure_motor_part(motor, "FanCowl")
	var cw := CylinderMesh.new()
	cw.top_radius = 0.078
	cw.bottom_radius = 0.06
	cw.height = 0.05
	cw.material = _motor_material
	cowl.mesh = cw
	cowl.rotation = x_along
	cowl.position = Vector3(0.32, cy, gbz)

	var term := _ensure_motor_part(motor, "Terminal")
	var tb := BoxMesh.new()
	tb.size = Vector3(0.08, 0.05, 0.09)
	tb.material = _motor_material
	term.mesh = tb
	term.position = Vector3(0.14, cy + 0.095, gbz)


func _ensure_motor_part(parent: Node3D, child_name: String) -> MeshInstance3D:
	var n := parent.get_node_or_null(child_name) as MeshInstance3D
	if n == null:
		n = MeshInstance3D.new()
		n.name = child_name
		parent.add_child(n, false, Node.INTERNAL_MODE_FRONT)
	return n


func _update_conveyor_velocity() -> void:
	if _simple_conveyor_shape == null:
		return
	# Hold the rollers until the deck reaches its target: rotate → align → convey.
	if _simulating() and speed != 0.0 and _at_target():
		var forward: Vector3 = _simple_conveyor_shape.global_transform.basis.x.normalized()
		_simple_conveyor_shape.constant_linear_velocity = forward * speed
	else:
		_simple_conveyor_shape.constant_linear_velocity = Vector3.ZERO


func _angle_to_target() -> float:
	return wrapf(target_angle - current_angle, -180.0, 180.0)


func _at_target() -> bool:
	return absf(_angle_to_target()) <= _ANGLE_EPSILON


func _update_flow_arrow() -> void:
	if _pivot == null:
		return
	if is_instance_valid(_flow_arrow):
		FlowDirectionArrow.unregister(_flow_arrow)
		_flow_arrow.queue_free()
		_flow_arrow = null
	_flow_arrow = FlowDirectionArrow.create(size)
	_pivot.add_child(_flow_arrow, false, Node.INTERNAL_MODE_FRONT)
	FlowDirectionArrow.register(_flow_arrow)
	if has_meta("is_preview"):
		_flow_arrow.visible = true


func _physics_process(delta: float) -> void:
	if LegFooting.legs_state_changed(self, _legs_state):
		_rebuild_legs()
		_legs_state = LegFooting.capture_leg_state(self)
	if not _simulating():
		return
	# Rotate toward the target by the shortest path, wrapping across ±180°.
	var diff: float = _angle_to_target()
	if absf(diff) > _ANGLE_EPSILON:
		var step: float = rotation_speed * delta
		current_angle = wrapf(current_angle + clampf(diff, -step, step), -180.0, 180.0)
	_update_conveyor_velocity()
	if _at_target() and _roller_material and speed != 0.0:
		var circumference: float = 2.0 * PI * _roller_radius()
		if circumference > 0.0:
			var bands: float = _roller_material.uv1_scale.x
			_roller_material.uv1_offset.x = fmod(
					_roller_material.uv1_offset.x + bands * speed * delta / circumference, 1.0)


func _on_simulation_started() -> void:
	_update_conveyor_velocity()
	if enable_comms:
		_speed_tag.register(speed_tag_group_name, speed_tag_name, OIPComms.TAG_TYPE_FLOAT32)
		_target_angle_tag.register(target_angle_tag_group_name, target_angle_tag_name, OIPComms.TAG_TYPE_FLOAT32)


func _on_simulation_ended() -> void:
	_update_conveyor_velocity()
	if _roller_material:
		_roller_material.uv1_offset = Vector3.ZERO


func _tag_group_initialized(tag_group_name_param: String) -> void:
	_speed_tag.on_group_initialized(tag_group_name_param)
	if _target_angle_tag.on_group_initialized(tag_group_name_param):
		_target_angle_tag.write_float32(target_angle)


func _tag_group_polled(tag_group_name_param: String) -> void:
	if not enable_comms:
		return
	if _speed_tag.matches_group(tag_group_name_param):
		speed = _speed_tag.read_float32()
	if _target_angle_tag.matches_group(tag_group_name_param):
		target_angle = _target_angle_tag.read_float32()


# Features are reported at the deck's HOME (0°) orientation: layouts are built with the
# deck at home and the simulation drives the rotation. Ends and side segments sit on the
# plate perimeter (radius = half the diameter) so conveyors snap to the rim, never inside.
func get_snap_features() -> Array:
	var r: float = size.x * 0.5
	var hx: float = _lane_width() * 0.5
	return [
		{
			"shape": ConveyorSnapFeatures.Shape.POINT,
			"kind": &"straight_end_front",
			"local_pos": Vector3(r, 0, 0),
			"local_outward": Vector3(1, 0, 0),
			"end_name": &"front",
		},
		{
			"shape": ConveyorSnapFeatures.Shape.POINT,
			"kind": &"straight_end_back",
			"local_pos": Vector3(-r, 0, 0),
			"local_outward": Vector3(-1, 0, 0),
			"end_name": &"back",
		},
		{
			"shape": ConveyorSnapFeatures.Shape.SEGMENT,
			"kind": &"straight_sideguard_left",
			"seg_start": Vector3(-hx, 0, -r),
			"seg_end": Vector3(hx, 0, -r),
			"seg_outward_local": Vector3(0, 0, -1),
		},
		{
			"shape": ConveyorSnapFeatures.Shape.SEGMENT,
			"kind": &"straight_sideguard_right",
			"seg_start": Vector3(-hx, 0, r),
			"seg_end": Vector3(hx, 0, r),
			"seg_outward_local": Vector3(0, 0, 1),
		},
	]


func _request_legs_refresh() -> void:
	if _legs_refresh_pending or not is_inside_tree():
		return
	_legs_refresh_pending = true
	call_deferred("_rebuild_legs")


func _request_legs_recheck() -> void:
	_rebuild_legs()


func _rebuild_legs() -> void:
	_legs_refresh_pending = false
	if not is_inside_tree():
		return
	var keep: Dictionary = {}
	if legs_enabled and leg_model_scene != null and leg_count > 0:
		var leg_radius: float = maxf(0.05, size.x * 0.5 - _LEG_INSET)
		var anchor_y: float = _plate_bottom_y()
		var node_xform: Transform3D = global_transform
		var floor_n: Vector3 = floor_plane.normal
		if floor_n.length_squared() >= 1.0e-6:
			floor_n = floor_n.normalized()
			# Half-step offset keeps the legs off the cardinal axes, clear of the in/out lane.
			var angle_offset: float = PI / float(leg_count)
			for i in leg_count:
				var ang: float = TAU * float(i) / float(leg_count) + angle_offset
				var anchor_local: Vector3 = Vector3(cos(ang) * leg_radius, anchor_y, sin(ang) * leg_radius)
				var anchor_world: Vector3 = node_xform * anchor_local
				var foot_v: Variant = LegFooting.resolve_foot(self, anchor_world, floor_n, floor_plane)
				if foot_v == null:
					continue
				var foot_world: Vector3 = foot_v
				var leg_height: float = (anchor_world - foot_world).dot(floor_n)
				if leg_height <= 0.05:
					continue
				var leg_name: String = "Leg_%d" % i
				var leg := get_node_or_null(NodePath(leg_name)) as Node3D
				if leg == null:
					leg = leg_model_scene.instantiate() as Node3D
					if leg == null:
						continue
					leg.name = leg_name
					add_child(leg, false, Node.INTERNAL_MODE_FRONT)
				if "single_post" in leg:
					leg.set("single_post", true)
				if "clamp_enabled" in leg:
					leg.set("clamp_enabled", false)
				leg.rotation = Vector3(0.0, -ang, 0.0)
				leg.position = node_xform.affine_inverse() * foot_world
				leg.scale = Vector3(1.0, leg_height, _LEG_HALF_WIDTH)
				keep[leg_name] = true
	_remove_orphan_legs(keep)


func _remove_orphan_legs(keep: Dictionary) -> void:
	for child in get_children(true):
		var n: String = String(child.name)
		if not n.begins_with("Leg_"):
			continue
		if keep.has(n):
			continue
		remove_child(child)
		child.queue_free()


# Editor drop hook (Godot fork): adopt the surface as the leg floor plane.
func _collision_repositioned(collision_point: Vector3, collision_normal: Vector3) -> void:
	if collision_normal == Vector3.ZERO:
		return
	var new_plane: Plane = Plane(collision_normal, collision_point)
	if floor_plane.is_equal_approx(new_plane):
		return
	floor_plane = new_plane


func _collision_repositioned_save() -> Variant:
	return floor_plane


func _collision_repositioned_undo(saved: Variant) -> void:
	if saved is Plane:
		floor_plane = saved


func _get_custom_preview_node() -> Node3D:
	var preview_scene := load("res://parts/TurntableConveyor.tscn") as PackedScene
	var preview_node := preview_scene.instantiate(PackedScene.GEN_EDIT_STATE_DISABLED) as Node3D
	preview_node.set_meta("is_preview", true)
	_disable_collisions_recursive(preview_node)
	return preview_node


func _disable_collisions_recursive(node: Node) -> void:
	if node is CollisionShape3D:
		(node as CollisionShape3D).disabled = true
	if node is CollisionObject3D:
		var body := node as CollisionObject3D
		body.collision_layer = 0
		body.collision_mask = 0
	for child in node.get_children():
		_disable_collisions_recursive(child)


func _reset_preview_holder_transform() -> void:
	if not has_meta("is_preview"):
		return
	var holder := get_parent() as Node3D
	if holder == null:
		return
	holder.transform = Transform3D.IDENTITY
