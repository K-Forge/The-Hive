@tool
class_name SafetyGateMesh
extends FenceMesh


const LEAF_GAP: float = POST_SIZE * 0.5 + 0.01
const HANDLE_SIZE: float = 0.035
const HANDLE_STANDOFF: float = 0.07
const HANDLE_HEIGHT: float = 1.0
const PLATE_SIZE := Vector3(0.22, 0.14, 0.03)


## Surface 0 = yellow posts; surface 1 = black caps.
static func create_posts(length: float, height: float,
		omit_start_post: bool = false, omit_end_post: bool = false) -> ArrayMesh:
	var mesh := ArrayMesh.new()

	var pv := PackedVector3Array()
	var pn := PackedVector3Array()
	var pu := PackedVector2Array()
	var pi := PackedInt32Array()

	var wv := PackedVector3Array()
	var wn := PackedVector3Array()
	var wu := PackedVector2Array()
	var wi := PackedInt32Array()

	var hl := length / 2.0
	var post_xs := PackedFloat32Array([-hl, hl])
	var omitted := [omit_start_post, omit_end_post]

	for i in range(post_xs.size()):
		if omitted[i]:
			continue
		_add_box_tube(pv, pn, pu, pi,
			Vector3(post_xs[i], 0, 0), Vector3(post_xs[i], height, 0), POST_SIZE)
		_add_box(wv, wn, wu, wi,
			Vector3(post_xs[i], height, 0),
			Vector3(CAP_FOOTPRINT, CAP_HEIGHT, CAP_FOOTPRINT))

	_add_surface(mesh, pv, pn, pu, pi)
	_add_surface(mesh, wv, wn, wu, wi)
	return mesh


## Leaf in hinge-local space (origin at hinge post center, +X toward latch).
## Surface 0 = black frame/mesh; surface 1 = red e-stop handle.
static func create_leaf(span: float, height: float) -> ArrayMesh:
	var mesh := ArrayMesh.new()

	var wv := PackedVector3Array()
	var wn := PackedVector3Array()
	var wu := PackedVector2Array()
	var wi := PackedInt32Array()

	var rv := PackedVector3Array()
	var rn := PackedVector3Array()
	var ru := PackedVector2Array()
	var ri := PackedInt32Array()

	var xa := LEAF_GAP
	var xb := span - LEAF_GAP
	var inset: float = minf(0.08, height * 0.1)
	if xb > xa:
		_add_panel(wv, wn, wu, wi, xa, xb, inset, height - inset)

	var hy := clampf(HANDLE_HEIGHT,
		inset + PLATE_SIZE.y, maxf(inset + PLATE_SIZE.y, height - inset - PLATE_SIZE.y))
	_add_box(wv, wn, wu, wi, Vector3(xb - PLATE_SIZE.x * 0.5, hy, 0), PLATE_SIZE)

	var grip_x0 := xb - PLATE_SIZE.x + HANDLE_SIZE
	var grip_x1 := xb - HANDLE_SIZE
	for side: float in [1.0, -1.0]:
		var z := side * HANDLE_STANDOFF
		_add_box_tube(rv, rn, ru, ri, Vector3(grip_x0, hy, z), Vector3(grip_x1, hy, z), HANDLE_SIZE)
		_add_box_tube(rv, rn, ru, ri, Vector3(grip_x0, hy, side * PLATE_SIZE.z * 0.5), Vector3(grip_x0, hy, z), HANDLE_SIZE)
		_add_box_tube(rv, rn, ru, ri, Vector3(grip_x1, hy, side * PLATE_SIZE.z * 0.5), Vector3(grip_x1, hy, z), HANDLE_SIZE)

	_add_surface(mesh, wv, wn, wu, wi)
	_add_surface(mesh, rv, rn, ru, ri)
	return mesh
