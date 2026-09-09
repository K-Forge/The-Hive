@tool
class_name PlatformMesh
extends RefCounted

## Origin at deck-top center; deck at Y=0, columns extend to Y=-height.
## Surfaces: 0=deck, 1=railings, 2=columns.

const RAILING_HEIGHT: float = 1.07        # 42 inches OSHA standard
const MID_RAIL_HEIGHT: float = 0.54       # 21 inches OSHA standard
const TOE_BOARD_HEIGHT: float = 0.10      # 4 inches OSHA standard
const POST_SIZE: float = 0.04
const RAIL_SIZE: float = 0.032
const COLUMN_SIZE: float = 0.10
const MAX_POST_SPACING: float = 2.4       # 8 feet OSHA max
const MAX_COLUMN_SPACING: float = 2.4
const DECK_THICKNESS: float = 0.006
const BEAM_HEIGHT: float = 0.15
const BEAM_THICKNESS: float = 0.006

static var _metal_texture: Texture2D = preload("res://assets/3DModels/Textures/Metal.png")


static func create(length: float, height: float, width: float,
		railing_openings: Array = [], deck_holes: Array = [],
		include_railings: bool = true,
		include_middle_supports: bool = true) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	_add_deck_surface(mesh, length, width, deck_holes)
	if include_railings:
		_add_railing_surface(mesh, length, width, railing_openings)
	_add_column_surface(mesh, length, height, width, include_middle_supports)
	return mesh


static func create_material_deck() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://src/Conveyor/structure_floor_shader.gdshader")
	mat.set_shader_parameter("base_color_texture", preload("res://assets/3DModels/WallsAndRoof/Textures/BuildingPart_Floor_A_BaseColor.png"))
	mat.set_shader_parameter("normal_texture", preload("res://assets/3DModels/WallsAndRoof/Textures/BuildingPart_Floor_A_Normal.png"))
	mat.set_shader_parameter("orm_texture", preload("res://assets/3DModels/WallsAndRoof/Textures/BuildingPart_Floor_A_ORM.png"))
	return mat


static func create_material_yellow() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://src/Conveyor/conveyor_frame_shader.gdshader")
	mat.set_shader_parameter("metal_texture", _metal_texture)
	mat.set_shader_parameter("color", Color(0.95, 0.74, 0.06))
	mat.set_shader_parameter("metallic_value", 0.0)
	mat.set_shader_parameter("roughness_value", 0.35)
	mat.set_shader_parameter("specular_value", 0.55)
	mat.set_shader_parameter("texture_influence", 0.5)
	return mat


static func create_deck_top_collision_shape(length: float, width: float, holes: Array) -> ConcavePolygonShape3D:
	var hl := length * 0.5
	var hw := width * 0.5
	var deck_poly := PackedVector2Array([
		Vector2(-hl, -hw),
		Vector2(hl, -hw),
		Vector2(hl, hw),
		Vector2(-hl, hw),
	])
	var hole_polys := _collect_hole_polygons(holes, deck_poly)
	var solid_polys := _build_solid_polygons(deck_poly, hole_polys)

	var faces := PackedVector3Array()
	for poly in solid_polys:
		var ccw := _ensure_ccw_polygon(poly)
		var tris: PackedInt32Array = Geometry2D.triangulate_polygon(ccw)
		for i in range(0, tris.size(), 3):
			var p0: Vector2 = ccw[tris[i]]
			var p1: Vector2 = ccw[tris[i + 1]]
			var p2: Vector2 = ccw[tris[i + 2]]
			faces.append(Vector3(p0.x, 0.0, p0.y))
			faces.append(Vector3(p1.x, 0.0, p1.y))
			faces.append(Vector3(p2.x, 0.0, p2.y))

	if faces.is_empty():
		faces.append(Vector3.ZERO)
		faces.append(Vector3(0.001, 0.0, 0.0))
		faces.append(Vector3(0.0, 0.0, 0.001))

	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	return shape


static func _add_deck_surface(mesh: ArrayMesh, length: float, width: float, holes: Array) -> void:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	var hl := length / 2.0
	var hw := width / 2.0
	var dt := DECK_THICKNESS

	var deck_poly := PackedVector2Array([
		Vector2(-hl, -hw),
		Vector2(hl, -hw),
		Vector2(hl, hw),
		Vector2(-hl, hw),
	])
	var hole_polys := _collect_hole_polygons(holes, deck_poly)
	var solid_polys := _build_solid_polygons(deck_poly, hole_polys)

	for poly in solid_polys:
		_add_polygon_face(verts, norms, uvs, indices, poly, 0.0, Vector3.UP, false)
		_add_polygon_face(verts, norms, uvs, indices, poly, -dt, Vector3.DOWN, true)

	_add_quad(verts, norms, uvs, indices,
		Vector3(hl, 0, -hw), Vector3(hl, 0, hw),
		Vector3(hl, -dt, hw), Vector3(hl, -dt, -hw), Vector3(1, 0, 0))
	_add_quad(verts, norms, uvs, indices,
		Vector3(-hl, 0, hw), Vector3(-hl, 0, -hw),
		Vector3(-hl, -dt, -hw), Vector3(-hl, -dt, hw), Vector3(-1, 0, 0))
	_add_quad(verts, norms, uvs, indices,
		Vector3(hl, 0, hw), Vector3(-hl, 0, hw),
		Vector3(-hl, -dt, hw), Vector3(hl, -dt, hw), Vector3(0, 0, 1))
	_add_quad(verts, norms, uvs, indices,
		Vector3(-hl, 0, -hw), Vector3(hl, 0, -hw),
		Vector3(hl, -dt, -hw), Vector3(-hl, -dt, -hw), Vector3(0, 0, -1))

	for hole_poly in hole_polys:
		_add_hole_polygon_walls(verts, norms, uvs, indices, hole_poly, dt)

	var arrays := _pack_arrays(verts, norms, uvs, indices)
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)


static func _add_polygon_face(
		verts: PackedVector3Array, norms: PackedVector3Array,
		uvs: PackedVector2Array, indices: PackedInt32Array,
		poly: PackedVector2Array, y: float, normal: Vector3, flip_winding: bool) -> void:
	var ccw := _ensure_ccw_polygon(poly)
	var tris: PackedInt32Array = Geometry2D.triangulate_polygon(ccw)
	for i in range(0, tris.size(), 3):
		var i0: int = tris[i]
		var i1: int = tris[i + 1]
		var i2: int = tris[i + 2]
		if flip_winding:
			var tmp := i1
			i1 = i2
			i2 = tmp

		var p0: Vector2 = ccw[i0]
		var p1: Vector2 = ccw[i1]
		var p2: Vector2 = ccw[i2]
		var base := verts.size()
		verts.append_array([
			Vector3(p0.x, y, p0.y),
			Vector3(p1.x, y, p1.y),
			Vector3(p2.x, y, p2.y),
		])
		norms.append_array([normal, normal, normal])
		uvs.append_array([p0, p1, p2])
		indices.append_array([base, base + 1, base + 2])


static func _add_hole_polygon_walls(
		verts: PackedVector3Array, norms: PackedVector3Array,
		uvs: PackedVector2Array, indices: PackedInt32Array,
		hole_poly: PackedVector2Array, dt: float) -> void:
	if hole_poly.size() < 3:
		return

	for i in range(hole_poly.size()):
		var p0_2d: Vector2 = hole_poly[i]
		var p1_2d: Vector2 = hole_poly[(i + 1) % hole_poly.size()]
		var edge := p1_2d - p0_2d
		if edge.length() < 0.001:
			continue
		var n2 := Vector2(-edge.y, edge.x).normalized()
		var normal := Vector3(n2.x, 0.0, n2.y)

		var p0 := Vector3(p0_2d.x, 0.0, p0_2d.y)
		var p1 := Vector3(p1_2d.x, 0.0, p1_2d.y)
		var p2 := Vector3(p1_2d.x, -dt, p1_2d.y)
		var p3 := Vector3(p0_2d.x, -dt, p0_2d.y)

		# Double-sided wall so shading/culling stays correct independent of winding.
		_add_quad(verts, norms, uvs, indices, p0, p1, p2, p3, normal)
		_add_quad(verts, norms, uvs, indices, p1, p0, p3, p2, -normal)


static func _collect_hole_polygons(holes: Array, deck_poly: PackedVector2Array) -> Array[PackedVector2Array]:
	var collected: Array[PackedVector2Array] = []
	for entry: Variant in holes:
		var raw_poly := _hole_entry_to_polygon(entry)
		if raw_poly.size() < 3:
			continue
		var clipped: Array = Geometry2D.intersect_polygons(deck_poly, raw_poly)
		if clipped.is_empty():
			# Fully-contained hole polygons may report no intersection; keep them.
			if _polygon_inside_polygon(raw_poly, deck_poly):
				var inside_poly := _sanitize_polygon(raw_poly)
				if inside_poly.size() >= 3 and absf(_polygon_signed_area(inside_poly)) > 0.0001:
					collected.append(inside_poly)
			continue
		for poly_variant: Variant in clipped:
			var pv: PackedVector2Array = poly_variant
			var poly := _sanitize_polygon(pv)
			if poly.size() >= 3 and absf(_polygon_signed_area(poly)) > 0.0001:
				collected.append(poly)
	return collected


static func _build_solid_polygons(
		deck_poly: PackedVector2Array, hole_polys: Array[PackedVector2Array]) -> Array[PackedVector2Array]:
	var deck := _sanitize_polygon(deck_poly)
	if hole_polys.is_empty():
		return [deck]

	var bounds := _polygon_bounds(deck)
	var x_pts: Array[float] = [bounds.position.x, bounds.end.x]
	var z_pts: Array[float] = [bounds.position.y, bounds.end.y]
	for hole in hole_polys:
		for p in hole:
			_insert_breakpoint(x_pts, p.x)
			_insert_breakpoint(z_pts, p.y)
	x_pts.sort()
	z_pts.sort()

	var solids: Array[PackedVector2Array] = []
	for xi in range(x_pts.size() - 1):
		for zi in range(z_pts.size() - 1):
			var x0: float = x_pts[xi]
			var x1: float = x_pts[xi + 1]
			var z0: float = z_pts[zi]
			var z1: float = z_pts[zi + 1]
			if x1 - x0 < 0.001 or z1 - z0 < 0.001:
				continue

			var cell := PackedVector2Array([
				Vector2(x0, z0),
				Vector2(x1, z0),
				Vector2(x1, z1),
				Vector2(x0, z1),
			])
			var pieces: Array[PackedVector2Array] = []
			if _polygon_inside_polygon(cell, deck):
				pieces.append(cell)
			else:
				var inside_deck := Geometry2D.intersect_polygons(cell, deck)
				if inside_deck.is_empty():
					continue
				for v in inside_deck:
					var p := _sanitize_polygon(v as PackedVector2Array)
					if p.size() >= 3 and absf(_polygon_signed_area(p)) > 0.0001:
						pieces.append(p)

			for hole in hole_polys:
				var next_pieces: Array[PackedVector2Array] = []
				for piece in pieces:
					var clipped := Geometry2D.clip_polygons(piece, hole)
					if clipped.is_empty():
						var overlap := Geometry2D.intersect_polygons(piece, hole)
						if overlap.is_empty():
							next_pieces.append(piece)
						continue
					for cv in clipped:
						var cp := _sanitize_polygon(cv as PackedVector2Array)
						if cp.size() >= 3 and absf(_polygon_signed_area(cp)) > 0.0001:
							next_pieces.append(cp)
				pieces = next_pieces
				if pieces.is_empty():
					break

			for piece in pieces:
				solids.append(piece)

	return solids


static func _hole_entry_to_polygon(entry: Variant) -> PackedVector2Array:
	if entry is Rect2:
		var rect: Rect2 = entry
		return PackedVector2Array([
			rect.position,
			Vector2(rect.end.x, rect.position.y),
			rect.end,
			Vector2(rect.position.x, rect.end.y),
		])

	if entry is Dictionary:
		var d: Dictionary = entry
		if d.has("polygon"):
			var raw: Variant = d.get("polygon")
			if raw is PackedVector2Array:
				var rawp: PackedVector2Array = raw
				return _sanitize_polygon(rawp)
			if raw is Array:
				var pts := PackedVector2Array()
				for v: Variant in raw:
					if v is Vector2:
						var vv: Vector2 = v
						pts.append(vv)
				return _sanitize_polygon(pts)

	return PackedVector2Array()


static func _sanitize_polygon(poly: PackedVector2Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for i in range(poly.size()):
		var p: Vector2 = poly[i]
		if result.is_empty() or result[result.size() - 1].distance_to(p) > 0.0001:
			result.append(p)
	if result.size() > 1 and result[0].distance_to(result[result.size() - 1]) <= 0.0001:
		result.remove_at(result.size() - 1)
	return result


static func _polygon_inside_polygon(inner: PackedVector2Array, outer: PackedVector2Array) -> bool:
	if inner.size() < 3 or outer.size() < 3:
		return false
	for p in inner:
		if not _point_in_polygon_or_near_edge(p, outer, 0.001):
			return false
	return true


static func _point_in_polygon_or_near_edge(point: Vector2, poly: PackedVector2Array, tol: float) -> bool:
	if Geometry2D.is_point_in_polygon(point, poly):
		return true
	for i in range(poly.size()):
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		if _distance_point_to_segment(point, a, b) <= tol:
			return true
	return false


static func _distance_point_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var denom := ab.length_squared()
	if denom < 0.000001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / denom, 0.0, 1.0)
	var closest := a + ab * t
	return p.distance_to(closest)


static func _polygon_bounds(poly: PackedVector2Array) -> Rect2:
	var min_x := INF
	var min_y := INF
	var max_x := -INF
	var max_y := -INF
	for p in poly:
		min_x = minf(min_x, p.x)
		min_y = minf(min_y, p.y)
		max_x = maxf(max_x, p.x)
		max_y = maxf(max_y, p.y)
	return Rect2(Vector2(min_x, min_y), Vector2(max_x - min_x, max_y - min_y))


static func _insert_breakpoint(arr: Array[float], val: float) -> void:
	for existing in arr:
		if absf(existing - val) < 0.0001:
			return
	arr.append(val)


static func _ensure_ccw_polygon(poly: PackedVector2Array) -> PackedVector2Array:
	var sanitized := _sanitize_polygon(poly)
	if _polygon_signed_area(sanitized) < 0.0:
		sanitized = _reversed_polygon(sanitized)
	return sanitized


static func _polygon_signed_area(poly: PackedVector2Array) -> float:
	if poly.size() < 3:
		return 0.0
	var area := 0.0
	for i in range(poly.size()):
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % poly.size()]
		area += a.x * b.y - b.x * a.y
	return area * 0.5


static func _reversed_polygon(poly: PackedVector2Array) -> PackedVector2Array:
	var reversed := PackedVector2Array()
	for i in range(poly.size() - 1, -1, -1):
		reversed.append(poly[i])
	return reversed


static func _add_railing_surface(mesh: ArrayMesh, length: float, width: float, openings: Array) -> void:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	var hl := length / 2.0
	var hw := width / 2.0

	# All edges must run in the POSITIVE direction of their parallel axis so opening
	# coordinates map correctly to edge-local space.
	var edges := [
		[Vector3(hl, 0, -hw), Vector3(hl, 0, hw), 0, Vector3(1, 0, 0)],
		[Vector3(-hl, 0, -hw), Vector3(-hl, 0, hw), 1, Vector3(-1, 0, 0)],
		[Vector3(-hl, 0, hw), Vector3(hl, 0, hw), 2, Vector3(0, 0, 1)],
		[Vector3(-hl, 0, -hw), Vector3(hl, 0, -hw), 3, Vector3(0, 0, -1)],
	]

	for edge_data: Array in edges:
		var start: Vector3 = edge_data[0]
		var end: Vector3 = edge_data[1]
		var edge_id: int = edge_data[2]
		var outward: Vector3 = edge_data[3]

		var edge_openings: Array = []
		for opening: Dictionary in openings:
			if opening["edge"] == edge_id:
				edge_openings.append(opening)

		_generate_railing_edge(verts, norms, uvs, indices,
			start, end, outward, edge_openings)

	if verts.is_empty():
		verts.append_array([Vector3.ZERO, Vector3.ZERO, Vector3.ZERO])
		norms.append_array([Vector3.UP, Vector3.UP, Vector3.UP])
		uvs.append_array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
		indices.append_array([0, 1, 2])

	var arrays := _pack_arrays(verts, norms, uvs, indices)
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)


static func _generate_railing_edge(
	verts: PackedVector3Array, norms: PackedVector3Array,
	uvs: PackedVector2Array, indices: PackedInt32Array,
	start: Vector3, end: Vector3, outward: Vector3,
	openings: Array
) -> void:
	var edge_vec := end - start
	var edge_length := edge_vec.length()
	if edge_length < 0.01:
		return
	var edge_dir := edge_vec.normalized()

	var rh := RAILING_HEIGHT
	var mrh := MID_RAIL_HEIGHT
	var tbh := TOE_BOARD_HEIGHT
	var rs := RAIL_SIZE
	var ps := POST_SIZE

	var offset := outward * (ps / 2.0)
	var half_edge := edge_length / 2.0

	var open_ranges: Array = []
	for opening: Dictionary in openings:
		var raw_start: float = opening["start"]
		var raw_end: float = opening["end"]
		var o_start: float = clampf(raw_start + half_edge, 0.0, edge_length)
		var o_end: float = clampf(raw_end + half_edge, 0.0, edge_length)
		if o_start > o_end:
			var tmp := o_start
			o_start = o_end
			o_end = tmp
		if o_end - o_start > 0.01:
			open_ranges.append(Vector2(o_start, o_end))

	open_ranges.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)

	var solid_segments: Array[Vector2] = []
	var cursor: float = 0.0
	for r_idx in range(open_ranges.size()):
		var r: Vector2 = open_ranges[r_idx]
		if r.x > cursor + 0.01:
			solid_segments.append(Vector2(cursor, r.x))
		cursor = r.y
	if cursor < edge_length - 0.01:
		solid_segments.append(Vector2(cursor, edge_length))

	for seg in solid_segments:
		var seg_start: float = seg.x
		var seg_end: float = seg.y
		var seg_length: float = seg_end - seg_start

		var num_spans := maxi(1, ceili(seg_length / MAX_POST_SPACING))
		var span_length := seg_length / float(num_spans)

		for span_idx in range(num_spans):
			var t0: float = seg_start + float(span_idx) * span_length
			var t1: float = seg_start + float(span_idx + 1) * span_length
			var sp0 := start + edge_dir * t0 + offset
			var sp1 := start + edge_dir * t1 + offset

			_add_box_tube(verts, norms, uvs, indices,
				sp0, sp0 + Vector3(0, rh, 0), ps)
			if span_idx == num_spans - 1:
				_add_box_tube(verts, norms, uvs, indices,
					sp1, sp1 + Vector3(0, rh, 0), ps)

			_add_box_tube(verts, norms, uvs, indices,
				sp0 + Vector3(0, rh, 0), sp1 + Vector3(0, rh, 0), rs)
			_add_box_tube(verts, norms, uvs, indices,
				sp0 + Vector3(0, mrh, 0), sp1 + Vector3(0, mrh, 0), rs)

			_add_quad(verts, norms, uvs, indices,
				sp0, sp1,
				sp1 + Vector3(0, tbh, 0), sp0 + Vector3(0, tbh, 0),
				outward)
			var tb_in := -outward * (ps * 0.5)
			_add_quad(verts, norms, uvs, indices,
				sp1 + tb_in, sp0 + tb_in,
				sp0 + tb_in + Vector3(0, tbh, 0), sp1 + tb_in + Vector3(0, tbh, 0),
				-outward)


static func _add_column_surface(mesh: ArrayMesh, length: float, height: float, width: float,
		include_middle_supports: bool = true) -> void:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	var hl := length / 2.0
	var hw := width / 2.0
	var cs := COLUMN_SIZE

	var x_positions := _compute_support_positions(length, MAX_COLUMN_SPACING)
	var z_positions := _compute_support_positions(width, MAX_COLUMN_SPACING)

	var x_first := x_positions[0]
	var x_last := x_positions[x_positions.size() - 1]
	var z_first := z_positions[0]
	var z_last := z_positions[z_positions.size() - 1]

	for x in x_positions:
		var is_x_edge := is_equal_approx(x, x_first) or is_equal_approx(x, x_last)
		for z in z_positions:
			var is_z_edge := is_equal_approx(z, z_first) or is_equal_approx(z, z_last)
			if not include_middle_supports and not (is_x_edge and is_z_edge):
				continue
			var top := Vector3(x, -DECK_THICKNESS, z)
			var bottom := Vector3(x, -height, z)
			_add_box_tube(verts, norms, uvs, indices, top, bottom, cs)
			_add_base_plate(verts, norms, uvs, indices, bottom, cs * 2.0)

	for z in z_positions:
		if not include_middle_supports and not (is_equal_approx(z, z_first) or is_equal_approx(z, z_last)):
			continue
		_add_box_tube(verts, norms, uvs, indices,
			Vector3(-hl, -DECK_THICKNESS - BEAM_HEIGHT / 2.0, z),
			Vector3(hl, -DECK_THICKNESS - BEAM_HEIGHT / 2.0, z),
			Vector3(BEAM_THICKNESS, BEAM_HEIGHT, BEAM_THICKNESS))

	for x in x_positions:
		if not include_middle_supports and not (is_equal_approx(x, x_first) or is_equal_approx(x, x_last)):
			continue
		_add_box_tube(verts, norms, uvs, indices,
			Vector3(x, -DECK_THICKNESS - BEAM_HEIGHT / 2.0, -hw),
			Vector3(x, -DECK_THICKNESS - BEAM_HEIGHT / 2.0, hw),
			Vector3(BEAM_THICKNESS, BEAM_HEIGHT, BEAM_THICKNESS))

	if verts.is_empty():
		verts.append_array([Vector3.ZERO, Vector3.ZERO, Vector3.ZERO])
		norms.append_array([Vector3.UP, Vector3.UP, Vector3.UP])
		uvs.append_array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
		indices.append_array([0, 1, 2])

	var arrays := _pack_arrays(verts, norms, uvs, indices)
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)


static func _compute_support_positions(total_length: float, max_spacing: float) -> Array[float]:
	var hl := total_length / 2.0
	var positions: Array[float] = []
	var num_spans := maxi(1, ceili(total_length / max_spacing))
	for i in range(num_spans + 1):
		positions.append(-hl + float(i) * total_length / float(num_spans))
	return positions


static func _add_base_plate(
	verts: PackedVector3Array, norms: PackedVector3Array,
	uvs: PackedVector2Array, indices: PackedInt32Array,
	center: Vector3, plate_size: float
) -> void:
	var hs := plate_size / 2.0
	var pt := 0.008
	_add_quad(verts, norms, uvs, indices,
		center + Vector3(-hs, pt, -hs), center + Vector3(hs, pt, -hs),
		center + Vector3(hs, pt, hs), center + Vector3(-hs, pt, hs), Vector3.UP)
	_add_quad(verts, norms, uvs, indices,
		center + Vector3(-hs, 0, hs), center + Vector3(hs, 0, hs),
		center + Vector3(hs, 0, -hs), center + Vector3(-hs, 0, -hs), Vector3.DOWN)


static func _add_box_tube(
	verts: PackedVector3Array, norms: PackedVector3Array,
	uvs: PackedVector2Array, indices: PackedInt32Array,
	from: Vector3, to: Vector3, tube_size: Variant
) -> void:
	var dir := to - from
	var length := dir.length()
	if length < 0.0001:
		return
	dir = dir.normalized()

	var hx: float
	var hz: float
	if tube_size is Vector3:
		hx = tube_size.x / 2.0
		hz = tube_size.y / 2.0
	else:
		var ts: float = tube_size
		hx = ts / 2.0
		hz = hx

	var up := Vector3.UP
	if absf(dir.dot(up)) > 0.99:
		up = Vector3.FORWARD
	var right := dir.cross(up).normalized()
	var local_up := right.cross(dir).normalized()

	var offsets: Array[Vector3] = [
		-right * hx - local_up * hz,
		right * hx - local_up * hz,
		right * hx + local_up * hz,
		-right * hx + local_up * hz,
	]
	var face_normals: Array[Vector3] = [-local_up, right, local_up, -right]

	for face in range(4):
		var i0 := face
		var i1 := (face + 1) % 4
		var v0: Vector3 = from + offsets[i0]
		var v1: Vector3 = from + offsets[i1]
		var v2: Vector3 = to + offsets[i1]
		var v3: Vector3 = to + offsets[i0]
		var n: Vector3 = face_normals[face]
		var edge_len: float = offsets[i0].distance_to(offsets[i1])

		var base := verts.size()
		verts.append_array([v0, v1, v2, v3])
		norms.append_array([n, n, n, n])
		uvs.append_array([
			Vector2(0, 0), Vector2(edge_len, 0),
			Vector2(edge_len, length), Vector2(0, length)])
		indices.append_array([base, base+1, base+2, base, base+2, base+3])

	_add_tube_cap(verts, norms, uvs, indices, from, offsets, -dir)
	_add_tube_cap(verts, norms, uvs, indices, to, offsets, dir)


static func _add_tube_cap(
	verts: PackedVector3Array, norms: PackedVector3Array,
	uvs: PackedVector2Array, indices: PackedInt32Array,
	center: Vector3, offsets: Array[Vector3], normal: Vector3
) -> void:
	var base := verts.size()
	for offset: Vector3 in offsets:
		verts.append(center + offset)
		norms.append(normal)
		uvs.append(Vector2(offset.x, offset.z))
	if normal.dot(Vector3.UP) >= 0 and normal.dot(Vector3.FORWARD) >= 0:
		indices.append_array([base, base+1, base+2, base, base+2, base+3])
	else:
		indices.append_array([base, base+2, base+1, base, base+3, base+2])


static func _add_quad(
	verts: PackedVector3Array, norms: PackedVector3Array,
	uvs: PackedVector2Array, indices: PackedInt32Array,
	v0: Vector3, v1: Vector3, v2: Vector3, v3: Vector3,
	normal: Vector3
) -> void:
	var base := verts.size()
	var w := v0.distance_to(v1)
	var h := v0.distance_to(v3)
	verts.append_array([v0, v1, v2, v3])
	norms.append_array([normal, normal, normal, normal])
	uvs.append_array([Vector2(0, 0), Vector2(w, 0), Vector2(w, h), Vector2(0, h)])
	indices.append_array([base, base+1, base+2, base, base+2, base+3])


static func _pack_arrays(
	verts: PackedVector3Array, norms: PackedVector3Array,
	uvs: PackedVector2Array, indices: PackedInt32Array
) -> Array:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	return arrays
