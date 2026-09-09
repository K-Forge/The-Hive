@tool
class_name MultiMeshRollers
extends AbstractRollerContainer

@export var roller_scene: PackedScene

var _mm_end_l: MultiMesh
var _mm_end_r: MultiMesh
var _mm_cyl: MultiMesh
var _mesh_end_l: ArrayMesh
var _mesh_end_r: ArrayMesh
var _mesh_cyl: ArrayMesh
var _override_material: Material
var _clip_override: Callable
var _clip_span_start: float = 0.0
var _clip_span_end: float = 0.0
var _grid_anchor: Variant = null
var _nudge_lo: bool = true
var _nudge_hi: bool = true


func setup_existing_rollers() -> void:
	_ensure_multimeshes()
	_rebuild()


func _get_rollers() -> Array[Roller]:
	return []


func set_length(length: float) -> void:
	super(length)
	_rebuild()


func set_width(width: float) -> void:
	super(width)
	_rebuild()


func set_roller_skew_angle(skew_angle_degrees: float) -> void:
	super(skew_angle_degrees)
	_rebuild()


func set_roller_radius(value: float) -> void:
	super(value)
	_rebuild()


func set_roller_pitch(value: float) -> void:
	super(value)
	_rebuild()


func set_roller_override_material(material: Material) -> void:
	_override_material = material
	_ensure_source_meshes()
	_apply_material()


func set_clip_override(provider: Callable) -> void:
	_clip_override = provider
	_rebuild()


func set_clip_span(start_x: float, end_x: float) -> void:
	_clip_span_start = start_x
	_clip_span_end = end_x
	_rebuild()


func set_grid(anchor: Variant, nudge_lo: bool, nudge_hi: bool) -> void:
	_grid_anchor = anchor
	_nudge_lo = nudge_lo
	_nudge_hi = nudge_hi
	_rebuild()


func _ensure_source_meshes() -> void:
	if _mesh_cyl != null or roller_scene == null:
		return
	var sample := roller_scene.instantiate() as Node3D
	var meshes := sample.get_node_or_null("RollerMeshes")
	if meshes:
		_mesh_end_l = _extract_mesh(meshes, "RollerEndL")
		_mesh_end_r = _extract_mesh(meshes, "RollerEndR")
		_mesh_cyl = _extract_mesh(meshes, "RollerLength")
	sample.free()


static func _extract_mesh(meshes: Node, child: String) -> ArrayMesh:
	var mi := meshes.get_node_or_null(child) as MeshInstance3D
	if mi == null or mi.mesh == null:
		return null
	return mi.mesh.duplicate() as ArrayMesh


func _ensure_multimeshes() -> void:
	if not is_inside_tree():
		return
	_ensure_source_meshes()
	_apply_material()
	_mm_end_l = _ensure_mm("MMRollerEndL", _mesh_end_l, _mm_end_l)
	_mm_end_r = _ensure_mm("MMRollerEndR", _mesh_end_r, _mm_end_r)
	_mm_cyl = _ensure_mm("MMRollerCyl", _mesh_cyl, _mm_cyl)


func _ensure_mm(node_name: String, mesh: ArrayMesh, existing: MultiMesh) -> MultiMesh:
	if existing != null:
		return existing
	var mmi := get_node_or_null(NodePath(node_name)) as MultiMeshInstance3D
	if mmi == null:
		mmi = MultiMeshInstance3D.new()
		mmi.name = node_name
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(mmi, false, Node.INTERNAL_MODE_FRONT)
	if owner != null:
		mmi.owner = owner
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mmi.multimesh = mm
	return mm


func _apply_material() -> void:
	if _override_material == null:
		return
	for m: ArrayMesh in [_mesh_end_l, _mesh_end_r, _mesh_cyl]:
		if m and m.get_surface_count() > 0:
			m.surface_set_material(0, _override_material)


## Roller center X positions (node-local) on a shared world-space pitch grid through _grid_anchor
## (else world origin), so collinear conveyors stay continuous across a join.
func _roller_local_xs() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if roller_pitch <= 0.0 or not is_inside_tree():
		return out
	var lo: float = _clip_span_start if _clip_span_end > _clip_span_start else -position.x
	var hi: float = _clip_span_end if _clip_span_end > _clip_span_start else _length - position.x
	if hi <= lo:
		return out
	var axis: Vector3 = global_transform.basis.x
	var axis_len: float = axis.length()
	if axis_len < 1e-6:
		return out
	axis /= axis_len
	var has_anchor: bool = _grid_anchor != null
	var anchor: Vector3 = _grid_anchor if has_anchor else Vector3.ZERO
	var to_anchor: float = (anchor - global_transform.origin).dot(axis)
	var phase: float = fposmod(to_anchor, roller_pitch)
	var x: float = phase + ceil((lo - phase) / roller_pitch) * roller_pitch
	while x < hi:
		if x >= lo and not (has_anchor and absf(x - to_anchor) < roller_pitch * 0.5):
			out.append(x)
		x += roller_pitch
	if not out.is_empty() and roller_radius > 0.0:
		if _nudge_lo:
			out[0] = maxf(out[0], lo + roller_radius)
		if _nudge_hi:
			out[out.size() - 1] = minf(out[out.size() - 1], hi - roller_radius)
	return out


func _rebuild() -> void:
	if not is_inside_tree():
		return
	_ensure_multimeshes()
	if _mm_cyl == null or _mesh_cyl == null:
		return
	var local_xs := _roller_local_xs()
	var count: int = local_xs.size()
	_mm_end_l.instance_count = count
	_mm_end_r.instance_count = count
	_mm_cyl.instance_count = count

	var skew_rad: float = deg_to_rad(_roller_skew_angle_degrees)
	var half_len: float = _effective_conveyor_half_length()
	var rs: float = roller_radius / RollerSpec.MODEL_RADIUS
	var cyl_margin: float = (Roller.BASE_LENGTH - Roller.BASE_CYLINDER_LENGTH) * rs
	var has_clip := _clip_override.is_valid()
	for i in count:
		var local_x: float = local_xs[i]
		var clipped: float
		var offset: float
		if has_clip:
			var clip: Vector3 = _clip_override.call(position.x + local_x)
			clipped = clip.z
			offset = (clip.x + clip.y) * 0.5
			if clipped < 0.01:
				_hide_instance(i)
				continue
		else:
			var conveyor_x: float = position.x + local_x - _length / 2.0
			var result := AbstractRollerContainer.calculate_clipped_roller(
					conveyor_x, half_len, _roller_length, skew_rad)
			clipped = result.x
			offset = result.y
			if clipped <= 0.0:
				_hide_instance(i)
				continue
		var roller_xform := Transform3D(Basis(Vector3.UP, skew_rad), Vector3(local_x, 0.0, 0.0))
		var end_basis := Basis.from_scale(Vector3(rs, rs, rs))
		_mm_end_l.set_instance_transform(i,
				roller_xform * Transform3D(end_basis, Vector3(0, 0, offset - clipped / Roller.BASE_LENGTH)))
		_mm_end_r.set_instance_transform(i,
				roller_xform * Transform3D(end_basis, Vector3(0, 0, offset + clipped / Roller.BASE_LENGTH)))
		var cyl_scale: float = maxf(0.0, clipped - cyl_margin) / Roller.BASE_CYLINDER_LENGTH
		_mm_cyl.set_instance_transform(i,
				roller_xform * Transform3D(Basis.from_scale(Vector3(rs, rs, cyl_scale)), Vector3(0, 0, offset)))


func _hide_instance(i: int) -> void:
	var zero := Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO)
	_mm_end_l.set_instance_transform(i, zero)
	_mm_end_r.set_instance_transform(i, zero)
	_mm_cyl.set_instance_transform(i, zero)


func get_roller_placements() -> Array:
	var out: Array = []
	if not is_inside_tree() or roller_pitch <= 0.0:
		return out
	var local_xs := _roller_local_xs()
	var skew_rad: float = deg_to_rad(_roller_skew_angle_degrees)
	var half_len: float = _effective_conveyor_half_length()
	var has_clip: bool = _clip_override.is_valid()
	for i in local_xs.size():
		var local_x: float = local_xs[i]
		var clipped: float
		var offset: float
		if has_clip:
			var clip: Vector3 = _clip_override.call(position.x + local_x)
			clipped = clip.z
			offset = (clip.x + clip.y) * 0.5
			if clipped < 0.01:
				continue
		else:
			var conveyor_x: float = position.x + local_x - _length / 2.0
			var result: Vector2 = AbstractRollerContainer.calculate_clipped_roller(
					conveyor_x, half_len, _roller_length, skew_rad)
			clipped = result.x
			offset = result.y
			if clipped <= 0.0:
				continue
		out.append({"x": local_x, "z": offset, "length": clipped})
	return out
