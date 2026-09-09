@tool
@abstract
class_name AbstractRollerContainer
extends Node3D

signal width_changed(width: float)
signal length_changed(length: float)
signal roller_rotation_changed(rotation_degrees: Vector3)
signal roller_added(roller: Roller)
signal roller_removed(roller: Roller)

const ROLLERS_START_OFFSET: float = 0.165

var _width: float = 2.0
var _length: float = 1.0
var _roller_length: float = 2.0
var _roller_skew_angle_degrees: float = 0.0
var roller_radius: float = RollerSpec.radius(RollerSpec.DutyClass.HEAVY)
var roller_pitch: float = RollerSpec.pitch(RollerSpec.DutyClass.HEAVY)

func _init() -> void:
	roller_added.connect(self._handle_roller_added)
	roller_removed.connect(self._handle_roller_removed)

# Virtual method to be overridden
func setup_existing_rollers() -> void:
	for roller in _get_rollers():
		roller_added.emit(roller)

func set_width(width: float) -> void:
	var changed := _width != width
	_width = width
	if changed:
		_update_roller_length()
		width_changed.emit(_width)

func set_length(length: float) -> void:
	var changed := _length != length
	_length = length
	if changed:
		length_changed.emit(_length)
		_update_all_roller_lengths()

func set_roller_radius(value: float) -> void:
	if roller_radius == value:
		return
	roller_radius = value
	_update_all_roller_lengths()

func set_roller_pitch(value: float) -> void:
	roller_pitch = value

func set_roller_skew_angle(skew_angle_degrees: float) -> void:
	var changed := fmod(_roller_skew_angle_degrees, 360.0) != fmod(skew_angle_degrees, 360.0)
	_roller_skew_angle_degrees = skew_angle_degrees
	if changed:
		roller_rotation_changed.emit(_get_rotation_from_skew_angle(_roller_skew_angle_degrees))
		_update_roller_length()

func _update_roller_length() -> void:
	if absf(fmod(_roller_skew_angle_degrees, 180.0)) == 90.0:
		return
	var new_length := _width / cos(deg_to_rad(_roller_skew_angle_degrees))
	var changed := new_length != _roller_length
	_roller_length = new_length
	if changed:
		_update_all_roller_lengths()

func _effective_conveyor_half_length() -> float:
	return _length / 2.0 - roller_radius * absf(cos(deg_to_rad(_roller_skew_angle_degrees)))

func _update_all_roller_lengths() -> void:
	for roller in _get_rollers():
		_apply_roller_length(roller)

# Virtual: subclasses override to apply per-roller clipping.
func _apply_roller_length(roller: Roller) -> void:
	roller.radius = roller_radius
	roller.set_length(_roller_length)

# Virtual method to be overridden
func _get_rollers() -> Array[Roller]:
	var rollers: Array[Roller] = []
	for child in get_children():
		if child is Roller:
			rollers.append(child)
	return rollers

func _handle_roller_added(roller: Roller) -> void:
	roller.set_rotation_degrees(_get_rotation_from_skew_angle(_roller_skew_angle_degrees))
	_apply_roller_length(roller)

	# It's possible for this handler to be called multiple times for the same roller:
	# Once when an increase in length adds a Roller and again when instantiation completes (setup_existing_rollers).
	# Check if the signal is already connected to avoid errors.
	if not roller_rotation_changed.is_connected(roller.set_rotation_degrees):
		roller_rotation_changed.connect(roller.set_rotation_degrees)

func _handle_roller_removed(roller: Roller) -> void:
	if roller_rotation_changed.is_connected(roller.set_rotation_degrees):
		roller_rotation_changed.disconnect(roller.set_rotation_degrees)

# Virtual method to be overridden
func _get_rotation_from_skew_angle(angle_degrees: float) -> Vector3:
	return Vector3(0, angle_degrees, 0)

## Clips a roller's length to the rectangular conveyor frame.
## Returns Vector2(clipped_length, center_offset_along_shaft).
## [param roller_x]: roller center X in conveyor frame (0 = conveyor center).
## [param conveyor_half_length]: half the conveyor's total length (frame from -half to +half).
## [param full_length]: unclipped roller length (width / cos(skew)).
## [param skew_angle_rad]: skew angle in radians.
static func calculate_clipped_roller(
	roller_x: float,
	conveyor_half_length: float,
	full_length: float,
	skew_angle_rad: float,
) -> Vector2:
	var sin_a := sin(skew_angle_rad)

	if absf(sin_a) < 1e-6:
		return Vector2(full_length, 0.0)

	var half_len := full_length / 2.0
	var t_bound_pos := (conveyor_half_length - roller_x) / sin_a
	var t_bound_neg := (-conveyor_half_length - roller_x) / sin_a

	var t_min: float
	var t_max: float

	if sin_a > 0.0:
		t_max = minf(half_len, t_bound_pos)
		t_min = maxf(-half_len, t_bound_neg)
	else:
		t_max = minf(half_len, t_bound_neg)
		t_min = maxf(-half_len, t_bound_pos)

	if t_max <= t_min:
		return Vector2(0.0, 0.0)

	return Vector2(t_max - t_min, (t_max + t_min) / 2.0)
