@tool
class_name StraightLeg
extends Node3D

const POST_HALF_LEN: float = 0.0987
const POST_DEPTH: float = 0.149
const POST_EDGE_OVERHANG: float = 0.003
const MIN_POST_GAP: float = 0.04

const BRACE_HALF_LEN: float = 0.074
const BRACE_HALF_HEIGHT: float = 0.056
const BRACE_SPACING: float = 1.0
const BRACE_POST_OVERLAP: float = 0.02

const COLLAR_HEIGHT: float = 0.06
const COLLAR_OVERHANG: float = 0.02
const COLLAR_RISE: float = 0.02
const COLLAR_EMBED: float = 0.005

const CLAMP_HALF_LEN: float = 0.128
const CLAMP_THICKNESS: float = 0.022
const CLAMP_FRAME_OFFSET: float = 0.023
const CLAMP_DROP: float = 0.05
const CLAMP_RISE: float = 0.12
const CLAMP_EMBED: float = 0.006

const FOOT_PLATE_HALF_LEN: float = 0.23
const FOOT_PLATE_HALF_DEPTH: float = 0.1
const FOOT_PLATE_THICKNESS: float = 0.014
const FOOT_FLOOR_GAP: float = 0.003

const SLEEVE_HEIGHT: float = 0.18
const SLEEVE_MARGIN: float = 0.022
const SLEEVE_EMBED: float = 0.005

const BOLT_RADIUS: float = 0.018
const BOLT_HEIGHT: float = 0.011
const BOLT_INSET: float = 0.035
const CLAMP_BOLT_X: float = 0.05

const MIN_DIM: float = 1.0e-3

@export var clamp_enabled: bool = true:
	set(value):
		if clamp_enabled == value:
			return
		clamp_enabled = value
		if is_node_ready():
			_built_height = -1.0
			_apply_scale()

@export var single_post: bool = false:
	set(value):
		if single_post == value:
			return
		single_post = value
		if is_node_ready():
			_built_height = -1.0
			_apply_scale()

var _height: float = 0.0
var _half_width: float = 0.0
var _built_height: float = -1.0
var _built_half_width: float = -1.0

var _inner: Node3D
var _structure: MeshInstance3D
var _material: Material
var _bolt_material: Material


func _init() -> void:
	set_notify_local_transform(true)


func _ready() -> void:
	_inner = get_node_or_null("Inner") as Node3D
	_structure = get_node_or_null("Inner/Structure") as MeshInstance3D
	_ensure_material()
	_built_height = -1.0
	_apply_scale()


func _notification(what: int) -> void:
	if what == NOTIFICATION_LOCAL_TRANSFORM_CHANGED:
		_apply_scale()


# The conveyor sizes the leg via scale; cancel it on the inner holder so geometry renders at
# true size, and read the requested dimensions back off it.
func _apply_scale() -> void:
	if _inner == null:
		return
	var s: Vector3 = scale
	var h: float = maxf(s.y, MIN_DIM)
	var hw: float = maxf(absf(s.z), MIN_DIM)
	_inner.scale = Vector3(1.0 / maxf(absf(s.x), MIN_DIM), 1.0 / h, 1.0 / hw)
	if not is_equal_approx(h, _built_height) or not is_equal_approx(hw, _built_half_width):
		_height = h
		_half_width = hw
		_rebuild()


func _ensure_material() -> void:
	if _material != null:
		return
	var src := load("res://assets/3DModels/Materials/LegsStandMaterial.tres") as ShaderMaterial
	if src == null:
		return
	_material = src.duplicate() as ShaderMaterial
	(_material as ShaderMaterial).set_shader_parameter("Scale", 1.0)

	var bolt := src.duplicate() as ShaderMaterial
	bolt.set_shader_parameter("Scale", 1.0)
	bolt.set_shader_parameter("Color", Color(0.9, 0.91, 0.93))
	bolt.set_shader_parameter("Metallic", 0.85)
	bolt.set_shader_parameter("Roughness", 0.28)
	bolt.set_shader_parameter("Specular", 0.85)
	_bolt_material = bolt


func _rebuild() -> void:
	if _structure == null:
		return
	_built_height = _height
	_built_half_width = _half_width
	if _height <= MIN_DIM:
		_structure.mesh = null
		return

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_post(st, 1.0)
	_add_collar(st, 1.0)
	_add_foot_plate(st, 1.0)
	_add_sleeve(st, 1.0)
	if clamp_enabled:
		_add_clamp(st, 1.0)
	if not single_post:
		_add_post(st, -1.0)
		_add_collar(st, -1.0)
		_add_foot_plate(st, -1.0)
		_add_sleeve(st, -1.0)
		if clamp_enabled:
			_add_clamp(st, -1.0)
		_add_braces(st)
	var mesh := st.commit()
	if _material:
		mesh.surface_set_material(0, _material)

	var sb := SurfaceTool.new()
	sb.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_foot_bolts(sb, 1.0)
	_add_sleeve_bolts(sb, 1.0)
	if clamp_enabled:
		_add_clamp_bolts(sb, 1.0)
	if not single_post:
		_add_foot_bolts(sb, -1.0)
		_add_sleeve_bolts(sb, -1.0)
		if clamp_enabled:
			_add_clamp_bolts(sb, -1.0)
	mesh = sb.commit(mesh)
	if _bolt_material and mesh.get_surface_count() > 1:
		mesh.surface_set_material(1, _bolt_material)

	_structure.mesh = mesh
	_structure.position.z = -(_half_width + POST_EDGE_OVERHANG - _post_depth() * 0.5) if single_post else 0.0


# Shrink the depth on narrow conveyors so the two posts keep a gap instead of merging.
func _post_depth() -> float:
	return minf(POST_DEPTH, maxf(_half_width + POST_EDGE_OVERHANG - MIN_POST_GAP * 0.5, 0.04))


func _add_post(st: SurfaceTool, side: float) -> void:
	var outer_z: float = side * (_half_width + POST_EDGE_OVERHANG)
	var inner_z: float = side * (_half_width + POST_EDGE_OVERHANG - _post_depth())
	var y0: float = FOOT_FLOOR_GAP + FOOT_PLATE_THICKNESS * 0.5
	_add_box(st,
		Vector3(-POST_HALF_LEN, y0, minf(outer_z, inner_z)),
		Vector3(POST_HALF_LEN, _height, maxf(outer_z, inner_z)))


func _add_collar(st: SurfaceTool, side: float) -> void:
	var outer_z: float = side * (_half_width + POST_EDGE_OVERHANG + COLLAR_OVERHANG)
	var embed_z: float = side * (_half_width + POST_EDGE_OVERHANG - COLLAR_EMBED)
	_add_box(st,
		Vector3(-(POST_HALF_LEN - COLLAR_EMBED), maxf(0.0, _height - COLLAR_HEIGHT), minf(outer_z, embed_z)),
		Vector3(POST_HALF_LEN - COLLAR_EMBED, _height + COLLAR_RISE, maxf(outer_z, embed_z)))


func _add_foot_plate(st: SurfaceTool, side: float) -> void:
	var z_c: float = side * (_half_width + POST_EDGE_OVERHANG - _post_depth() * 0.5)
	_add_box(st,
		Vector3(-FOOT_PLATE_HALF_LEN, FOOT_FLOOR_GAP, z_c - FOOT_PLATE_HALF_DEPTH),
		Vector3(FOOT_PLATE_HALF_LEN, FOOT_FLOOR_GAP + FOOT_PLATE_THICKNESS, z_c + FOOT_PLATE_HALF_DEPTH))


func _sleeve_y0() -> float:
	return FOOT_FLOOR_GAP + FOOT_PLATE_THICKNESS - SLEEVE_EMBED


func _sleeve_y1() -> float:
	return _sleeve_y0() + minf(SLEEVE_HEIGHT, maxf(_height - 0.05, 0.02))


func _add_sleeve(st: SurfaceTool, side: float) -> void:
	var depth: float = _post_depth()
	var z_c: float = side * (_half_width + POST_EDGE_OVERHANG - depth * 0.5)
	var half_len: float = POST_HALF_LEN + SLEEVE_MARGIN
	var half_dep: float = depth * 0.5 + SLEEVE_MARGIN
	_add_box(st,
		Vector3(-half_len, _sleeve_y0(), z_c - half_dep),
		Vector3(half_len, _sleeve_y1(), z_c + half_dep))


func _add_sleeve_bolts(st: SurfaceTool, side: float) -> void:
	var z_face: float = side * (_half_width + POST_EDGE_OVERHANG + SLEEVE_MARGIN)
	var axis := Vector3(0.0, 0.0, side)
	var y_mid: float = (_sleeve_y0() + _sleeve_y1()) * 0.5
	var z0: float = z_face - side * BOLT_HEIGHT * 0.4
	_add_hex(st, Vector3(0.0, y_mid, z0), axis, BOLT_RADIUS, BOLT_HEIGHT)


func _add_foot_bolts(st: SurfaceTool, side: float) -> void:
	var z_c: float = side * (_half_width + POST_EDGE_OVERHANG - _post_depth() * 0.5)
	var y_base: float = FOOT_FLOOR_GAP + FOOT_PLATE_THICKNESS
	var dx: float = FOOT_PLATE_HALF_LEN - BOLT_INSET
	var dz: float = FOOT_PLATE_HALF_DEPTH - BOLT_INSET
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_add_hex(st, Vector3(sx * dx, y_base, z_c + sz * dz), Vector3.UP, BOLT_RADIUS, BOLT_HEIGHT)


func _add_clamp(st: SurfaceTool, side: float) -> void:
	var face: float = side * (_half_width + CLAMP_FRAME_OFFSET)
	var inner: float = face - side * CLAMP_EMBED
	var outer: float = face + side * CLAMP_THICKNESS
	_add_box(st,
		Vector3(-CLAMP_HALF_LEN, maxf(0.0, _height - CLAMP_DROP), minf(inner, outer)),
		Vector3(CLAMP_HALF_LEN, _height + CLAMP_RISE, maxf(inner, outer)))


func _add_clamp_bolts(st: SurfaceTool, side: float) -> void:
	var outer: float = side * (_half_width + CLAMP_FRAME_OFFSET + CLAMP_THICKNESS)
	var axis := Vector3(0.0, 0.0, side)
	var y_mid: float = _height + CLAMP_RISE * 0.5
	var z0: float = outer - side * BOLT_HEIGHT * 0.4
	for sx: float in [-1.0, 1.0]:
		_add_hex(st, Vector3(sx * CLAMP_BOLT_X, y_mid, z0), axis, BOLT_RADIUS, BOLT_HEIGHT)


# Hex prism along `axis` with explicit outward normals (cap + radial sides); winding matches
# the box faces below.
func _add_hex(st: SurfaceTool, base_centre: Vector3, axis: Vector3, radius: float, height: float) -> void:
	var n: Vector3 = axis.normalized()
	var u: Vector3 = n.cross(Vector3.UP)
	if u.length_squared() < 1.0e-6:
		u = n.cross(Vector3.RIGHT)
	u = u.normalized()
	var v: Vector3 = n.cross(u)
	var dirs: Array[Vector3] = []
	var bottom: Array[Vector3] = []
	var top: Array[Vector3] = []
	for i in 6:
		var a: float = float(i) * (TAU / 6.0)
		var d: Vector3 = u * cos(a) + v * sin(a)
		dirs.append(d)
		bottom.append(base_centre + d * radius)
		top.append(base_centre + d * radius + n * height)
	var centre_top := base_centre + n * height
	for i in 6:
		var j: int = (i + 1) % 6
		_add_tri(st, centre_top, top[i], top[j], n)
		var side_n: Vector3 = (dirs[i] + dirs[j]).normalized()
		_add_tri(st, bottom[i], bottom[j], top[j], side_n)
		_add_tri(st, bottom[i], top[j], top[i], side_n)


func _add_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3) -> void:
	st.set_normal(n); st.set_uv(Vector2(a.x, a.z)); st.add_vertex(a)
	st.set_normal(n); st.set_uv(Vector2(c.x, c.z)); st.add_vertex(c)
	st.set_normal(n); st.set_uv(Vector2(b.x, b.z)); st.add_vertex(b)


func _add_braces(st: SurfaceTool) -> void:
	var count: int = maxi(floori(_height / BRACE_SPACING), 1)
	var spacing: float = _height / float(count + 1)
	var z_span: float = maxf(_half_width + POST_EDGE_OVERHANG - _post_depth() + BRACE_POST_OVERLAP, BRACE_POST_OVERLAP)
	var sleeve_top: float = _sleeve_y1()
	for i in count:
		var y: float = spacing * (i + 1)
		if y - BRACE_HALF_HEIGHT < sleeve_top:
			continue
		_add_box(st,
			Vector3(-BRACE_HALF_LEN, y - BRACE_HALF_HEIGHT, -z_span),
			Vector3(BRACE_HALF_LEN, y + BRACE_HALF_HEIGHT, z_span))


# Faces wound CCW-from-outside with explicit outward normals — don't run generate_normals
# over this surface, it would fight the winding.
func _add_box(st: SurfaceTool, mn: Vector3, mx: Vector3) -> void:
	var x0: float = mn.x
	var x1: float = mx.x
	var y0: float = mn.y
	var y1: float = mx.y
	var z0: float = mn.z
	var z1: float = mx.z
	_add_quad(st, Vector3(x1, y0, z0), Vector3(x1, y1, z0), Vector3(x1, y1, z1), Vector3(x1, y0, z1), Vector3.RIGHT)
	_add_quad(st, Vector3(x0, y0, z0), Vector3(x0, y0, z1), Vector3(x0, y1, z1), Vector3(x0, y1, z0), Vector3.LEFT)
	_add_quad(st, Vector3(x0, y1, z0), Vector3(x0, y1, z1), Vector3(x1, y1, z1), Vector3(x1, y1, z0), Vector3.UP)
	_add_quad(st, Vector3(x0, y0, z0), Vector3(x1, y0, z0), Vector3(x1, y0, z1), Vector3(x0, y0, z1), Vector3.DOWN)
	_add_quad(st, Vector3(x0, y0, z1), Vector3(x1, y0, z1), Vector3(x1, y1, z1), Vector3(x0, y1, z1), Vector3.BACK)
	_add_quad(st, Vector3(x0, y0, z0), Vector3(x0, y1, z0), Vector3(x1, y1, z0), Vector3(x1, y0, z0), Vector3.FORWARD)


func _add_quad(st: SurfaceTool, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, n: Vector3) -> void:
	var ul: float = (p1 - p0).length()
	var vl: float = (p3 - p0).length()
	st.set_normal(n); st.set_uv(Vector2(0.0, 0.0)); st.add_vertex(p0)
	st.set_normal(n); st.set_uv(Vector2(ul, vl)); st.add_vertex(p2)
	st.set_normal(n); st.set_uv(Vector2(ul, 0.0)); st.add_vertex(p1)
	st.set_normal(n); st.set_uv(Vector2(0.0, 0.0)); st.add_vertex(p0)
	st.set_normal(n); st.set_uv(Vector2(0.0, vl)); st.add_vertex(p3)
	st.set_normal(n); st.set_uv(Vector2(ul, vl)); st.add_vertex(p2)
