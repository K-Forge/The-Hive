@tool
extends Node

## Overrides selected.global_transform during live preview to dodge xform cascade.
static var selected_xform_override: Variant = null
## Overrides target.global_transform during live preview.
static var target_xform_override: Variant = null

static var live_snap_enabled: bool = true

## Live-preview ghost (drag-from-library). Lives under the editor's preview holder, outside
## the edited scene, so geometry scans must be told about it explicitly (see [method _candidates_near]).
static var preview_ghost: Node3D = null

## Live-snap memoization, keyed by instance_id; empty in the manual snap path.
static var live_type_cache: Dictionary = {}
static var live_end_info_cache: Dictionary = {}

## Broadphase spatial hash (XZ uniform grid) over port nodes, kept current incrementally via
## [method grid_update] — called on every move AND every geometry rebuild, so a stationary
## conveyor's footprint can't lag its length. Stale entries (a removed/freed node lingering)
## are evicted on the next query in [method _candidates_near]; the dangerous false negative (a
## moved node at the wrong cell) can't happen because every move re-places the mover
## synchronously before its contacts derive.
const _GRID_CELL_SIZE: float = 4.0
static var _grid: Dictionary = {}            # Vector2i -> Array[Node3D]
static var _node_cells: Dictionary = {}      # instance_id -> Array[Vector2i]
static var _grid_built: bool = false

static func get_selected_xform(selected: Node3D) -> Transform3D:
	if selected_xform_override != null:
		return selected_xform_override
	return selected.global_transform


static func get_target_xform(target: Node3D) -> Transform3D:
	if target_xform_override != null:
		return target_xform_override
	return target.global_transform


func _enter_tree() -> void:
	if not Engine.is_editor_hint():
		return

	var editor_settings := EditorInterface.get_editor_settings()
	var snap_shortcut := Shortcut.new()
	var snap_key := InputEventKey.new()
	snap_key.keycode = KEY_C
	snap_key.ctrl_pressed = true
	snap_key.shift_pressed = true
	snap_shortcut.events.append(snap_key)
	editor_settings.add_shortcut("Open Industry Project/Snap Conveyor", snap_shortcut)

	# Path-loaded: autoloads parse before sibling class_names register.
	var live_snap_script: GDScript = load("res://addons/oip_ui/Autoload/ConveyorLiveSnap.gd")
	var live_snap: Node = live_snap_script.new()
	live_snap.name = "ConveyorLiveSnap"
	add_child(live_snap)


func _input(event: InputEvent) -> void:
	if not Engine.is_editor_hint():
		return

	var editor_settings := EditorInterface.get_editor_settings()
	if editor_settings.is_shortcut("Open Industry Project/Snap Conveyor", event) and event.is_pressed() and not event.is_echo():
		if _selection_has_structures():
			StructureSnapping.snap_selected_structures()
		else:
			snap_selected_conveyors()


static func _selection_has_structures() -> bool:
	for node in EditorInterface.get_selection().get_selected_nodes():
		if node is Platform or node is Stairs or node is GuardRail:
			return true
	return false


static func snap_selected_conveyors() -> void:
	# Clear any leak from a live-preview call.
	selected_xform_override = null

	var selection := EditorInterface.get_selection()
	var selected_conveyors: Array[Node3D] = []
	var target_conveyor := EditorInterface.get_active_node_3d()
	
	if not target_conveyor:
		EditorInterface.get_editor_toaster().push_toast("No active node found - please click on a target conveyor first", EditorToaster.SEVERITY_WARNING)
		return
	
	if not _is_conveyor(target_conveyor):
		EditorInterface.get_editor_toaster().push_toast("Active node is not a conveyor - please select a conveyor as target", EditorToaster.SEVERITY_WARNING)
		return
	
	for node in selection.get_selected_nodes():
		if (_is_conveyor(node) or _is_diverter(node) or _is_chain_transfer(node) or _is_blade_stop(node) or _is_sensor(node)) and node != target_conveyor:
			selected_conveyors.append(node as Node3D)

	if selected_conveyors.is_empty():
		EditorInterface.get_editor_toaster().push_toast("No valid conveyors selected for snapping (target conveyor excluded)", EditorToaster.SEVERITY_WARNING)
		return

	for node in selected_conveyors:
		if (_is_chain_transfer(node) or _is_blade_stop(node)) and not _is_roller_conveyor(target_conveyor):
			var label := "Chain transfers" if _is_chain_transfer(node) else "Blade stops"
			EditorInterface.get_editor_toaster().push_toast("%s can only be snapped onto a roller conveyor" % label, EditorToaster.SEVERITY_WARNING)
			return
	
	var undo_redo := EditorInterface.get_editor_undo_redo()

	var has_curved := false
	var has_side_guards := false
	var has_diverter := false
	var has_chain_transfer := false
	var has_blade_stop := false
	var has_sensor := false

	for conveyor in selected_conveyors:
		if _is_curved_conveyor(conveyor) or _is_curved_conveyor(target_conveyor):
			has_curved = true
		if _has_side_guards(conveyor) or _has_side_guards(target_conveyor):
			has_side_guards = true
		if _is_diverter(conveyor):
			has_diverter = true
		if _is_chain_transfer(conveyor):
			has_chain_transfer = true
		if _is_blade_stop(conveyor):
			has_blade_stop = true
		if _is_sensor(conveyor):
			has_sensor = true

	var action_name: String
	if has_blade_stop:
		action_name = "Snap Blade Stop Between Rollers"
	elif has_chain_transfer:
		action_name = "Snap Chain Transfer Between Rollers"
	elif has_sensor:
		action_name = "Snap Sensor to Side Guard"
	elif has_diverter:
		action_name = "Snap Diverter with Side Guard Openings" if has_side_guards else "Snap Diverter"
	elif has_curved and has_side_guards:
		action_name = "Snap Curved Conveyors with Side Guard Openings"
	elif has_curved:
		action_name = "Snap Curved Conveyors"
	elif has_side_guards:
		action_name = "Snap Conveyors with Side Guard Openings"
	else:
		action_name = "Snap Conveyors"
	
	undo_redo.create_action(action_name)

	for conveyor in selected_conveyors:
		var original_transform := conveyor.global_transform
		var snap_result := _calculate_snap_transform(conveyor, target_conveyor)
		if snap_result.is_empty():
			continue
		var snap_transform: Transform3D = snap_result.transform
		undo_redo.add_do_property(conveyor, "global_transform", snap_transform)
		undo_redo.add_undo_property(conveyor, "global_transform", original_transform)

		if snap_result.get("needs_reverse", false):
			var reverse_prop := get_reverse_property_name(conveyor)
			if reverse_prop != &"":
				var current_reverse: bool = bool(conveyor.get(reverse_prop))
				undo_redo.add_do_property(conveyor, reverse_prop, not current_reverse)
				undo_redo.add_undo_property(conveyor, reverse_prop, current_reverse)

		var overrides: Dictionary = snap_result.get("property_overrides", {})
		for prop: String in overrides:
			undo_redo.add_do_property(conveyor, prop, overrides[prop])
			undo_redo.add_undo_property(conveyor, prop, conveyor.get(prop))

	undo_redo.commit_action()


## Diverter-only: assumes the snap places the diverter adjacent to exactly one side.
static func _calculate_diverter_intersection_for_transform(snapped_conveyor: Node3D, target_conveyor: Node3D, snapped_transform: Transform3D) -> Dictionary:
	var target_transform := target_conveyor.global_transform
	var snapped_size := _get_conveyor_size(snapped_conveyor)

	var target_inverse := target_transform.affine_inverse()
	var snapped_local_transform := target_inverse * snapped_transform

	var snapped_half_length := snapped_size.x / 2.0
	var snapped_half_width := snapped_size.z / 2.0
	# Path-based targets are origin-at-tail; use real X bounds.
	var t_bounds := _get_conveyor_x_bounds(target_conveyor)

	# Full Vector3 corners: stripping Y misattributes corners on elevated runs.
	var corners: Array[Vector3] = []
	var min_x: float = INF
	var max_x: float = -INF

	for x_sign: int in [-1, 1]:
		for z_sign: int in [-1, 1]:
			var local_corner: Vector3 = snapped_local_transform.origin + snapped_local_transform.basis.x * (x_sign * snapped_half_length) + snapped_local_transform.basis.z * (z_sign * snapped_half_width)
			corners.append(local_corner)
			min_x = min(min_x, local_corner.x)
			max_x = max(max_x, local_corner.x)

	if max_x < t_bounds.x or min_x > t_bounds.y:
		return {}

	var intersections := []
	var side_guard_margin: float = 0.15 if _has_side_guards(snapped_conveyor) else 0.05

	# Resolve the diverter's footprint to an arc-length range on the target.
	if _has_spur_angles(snapped_conveyor):
		var spur_angles := _get_spur_angles(snapped_conveyor)
		var spur_angle: float = spur_angles.downstream
		if abs(spur_angle) > 0.001:
			var left_extent: float = snapped_half_length + tan(spur_angle) * (-snapped_half_width)
			var right_extent: float = snapped_half_length + tan(spur_angle) * snapped_half_width

			var side_guard_thickness: float = 0.1
			var edge_a: Vector3 = snapped_local_transform * Vector3(left_extent, 0, -snapped_half_width - side_guard_thickness)
			var edge_b: Vector3 = snapped_local_transform * Vector3(right_extent, 0, snapped_half_width + side_guard_thickness)
			corners = [edge_a, edge_b]

	var arc_bounds: Vector2 = _get_conveyor_arc_bounds(target_conveyor)
	var arc_min: float = INF
	var arc_max: float = -INF
	for c: Vector3 in corners:
		var arc: float = _local_pos_to_arc(target_conveyor, c)
		arc_min = minf(arc_min, arc)
		arc_max = maxf(arc_max, arc)
	arc_min = maxf(arc_min, arc_bounds.x)
	arc_max = minf(arc_max, arc_bounds.y)
	var opening_position: float = (arc_min + arc_max) / 2.0
	var opening_size: float = (arc_max - arc_min) + side_guard_margin

	var side_str: String = "left" if snapped_local_transform.origin.z < 0.0 else "right"
	intersections.append({
		"side": side_str,
		"position": opening_position,
		"size": opening_size,
	})

	return {"intersections": intersections}


## Derive [param local]'s side-guard openings from geometry: open the guard wherever another
## conveyor's end — or a diverter's push side — physically meets [param local]'s side.
func derive_openings_by_geometry(local: Node3D) -> Array[SideGuardOpening]:
	var result: Array[SideGuardOpening] = []
	if not local.is_inside_tree():
		return result
	for other: Node3D in _candidates_near(local, 0.3):
		if other == local or not is_instance_valid(other) or not other.is_inside_tree():
			continue
		var push_wp: Vector3 = _world_pos_for_port(other, &"push_side")
		if push_wp != Vector3.INF and (
			_world_pos_near_side_plane(push_wp, local, &"left_side", 0.15)
			or _world_pos_near_side_plane(push_wp, local, &"right_side", 0.15)
		):
			var info: Dictionary = _calculate_diverter_intersection_for_transform(other, local, other.global_transform)
			if info.has("intersections"):
				for intersection: Dictionary in info["intersections"]:
					var gap_size: float = intersection["size"]
					if gap_size < 0.01:
						continue
					var gap_center: float = intersection["position"]
					result.append(SideGuardOpening.make(
						gap_center - gap_size * 0.5, gap_center + gap_size * 0.5, intersection["side"]
					))
			continue
		for end_port: StringName in [&"front", &"back"]:
			var wp: Vector3 = _world_pos_for_port(other, end_port)
			if wp == Vector3.INF:
				continue
			for side_port: StringName in [&"left_side", &"right_side"]:
				if not _world_pos_near_side_plane(wp, local, side_port, 0.15):
					continue
				var side_str: String = "left" if side_port == &"left_side" else "right"
				# Contact point feeds _compute_side_snap_geometry's fallback opening, used when
				# the rays miss (e.g. snapping toward the discharge half).
				var contact_local: Vector3 = local.global_transform.affine_inverse() * wp
				var geo: Dictionary = _compute_side_snap_geometry(
					other.global_transform, other, local, side_str, contact_local
				)
				var op: SideGuardOpening = geo.target_opening
				if op != null:
					result.append(op)
	return result


## Spur counterpart of [method derive_openings_by_geometry]: derive [param local]'s frame/guard
## extents by extending its own end to the wall plane of whatever conveyor it lands against.
static func derive_extents_by_geometry(local: Node3D) -> Dictionary:
	var result: Dictionary = {}
	if not local.is_inside_tree():
		return result
	for other: Node3D in _candidates_near(local, 0.3):
		if other == local or not is_instance_valid(other) or not other.is_inside_tree():
			continue
		for end_port: StringName in [&"front", &"back"]:
			var wp: Vector3 = _world_pos_for_port(local, end_port)
			if wp == Vector3.INF:
				continue
			for side_port: StringName in [&"left_side", &"right_side"]:
				if not _world_pos_near_side_plane(wp, other, side_port, 0.15):
					continue
				var side_str: String = "left" if side_port == &"left_side" else "right"
				var geo: Dictionary = _compute_side_snap_geometry(
					local.global_transform, local, other, side_str, Vector3.INF
				)
				var extents: Dictionary = geo.snapped_extents
				for k: String in extents:
					result[k] = extents[k]
	return result


## Returns [param local]'s roller-grid inputs from its butted neighbours: {anchor: world point the
## grid passes through — a curve's end roller, or a collinear straight's inherited anchor, else null
## (world origin); front_butt/back_butt: whether that end abuts a collinear neighbour}.
func resolve_roller_grid(local: Node3D) -> Dictionary:
	var result: Dictionary = {"anchor": null, "front_butt": false, "back_butt": false}
	if not local.is_inside_tree():
		return result
	var local_ends := _get_end_info(local)
	var local_xform := local.global_transform
	var local_axis: Vector3 = local_xform.basis.x.normalized()
	for other: Node3D in _candidates_near(local, 0.3):
		if other == local or not is_instance_valid(other) or not other.is_inside_tree():
			continue
		var is_curve: bool = _is_curved_roller_conveyor(other)
		var is_straight: bool = _is_roller_conveyor(other)
		if not is_curve and not is_straight:
			continue
		var other_xform := other.global_transform
		var collinear: bool = absf(other_xform.basis.x.normalized().dot(local_axis)) > 0.99
		for oe: Dictionary in _get_end_info(other):
			var oe_world: Vector3 = other_xform * (oe.pos as Vector3)
			for le: Dictionary in local_ends:
				if (local_xform * (le.pos as Vector3)).distance_to(oe_world) >= 0.15:
					continue
				if collinear:
					result[String(le.name) + "_butt"] = true
				if is_curve:
					result.anchor = oe_world
				elif collinear and result.anchor == null and other.has_method(&"get_roller_grid_anchor"):
					var a: Variant = other.get_roller_grid_anchor()
					if a != null:
						result.anchor = a
	return result


static func _collect_port_nodes(local: Node3D) -> Array[Node3D]:
	var nodes: Array[Node3D] = []
	var root: Node = null
	var tree := local.get_tree()
	if tree != null:
		root = tree.get_current_scene()
	if root == null:
		root = local.owner
	if root == null:
		root = local
	_gather_port_nodes(root, nodes)
	# The ghost lives outside the edited scene, so the walk above misses it.
	if preview_ghost != null and is_instance_valid(preview_ghost) \
			and preview_ghost.is_inside_tree() and not nodes.has(preview_ghost):
		nodes.append(preview_ghost)
	return nodes


static func _gather_port_nodes(node: Node, out: Array[Node3D]) -> void:
	if node is Node3D and (node.has_method(&"_openings_for_side") or node.has_method(&"get_snap_features")):
		out.append(node)
	for child: Node in node.get_children():
		_gather_port_nodes(child, out)


## One-time seed for nodes already in the tree before this autoload observed their enter
## (plugin reload / editor restart). Only adds untracked nodes — never clears, so it can't
## discard the incremental data that enters already populate.
static func _grid_seed_existing(local: Node3D) -> void:
	for n: Node3D in _collect_port_nodes(local):
		if is_instance_valid(n) and n.is_inside_tree() and not _node_cells.has(n.get_instance_id()):
			_grid_insert(n)
	_grid_built = true


## The ghost is never gridded (it's appended live in [method _candidates_near]), so skip it.
static func _grid_insert(node: Node3D) -> void:
	if node == preview_ghost:
		return
	var cells: Array[Vector2i] = _cells_for_aabb(_world_aabb(node).grow(0.3))
	_node_cells[node.get_instance_id()] = cells
	for cell: Vector2i in cells:
		if not _grid.has(cell):
			_grid[cell] = [] as Array[Node3D]
		(_grid[cell] as Array[Node3D]).append(node)


static func _grid_remove(id: int) -> void:
	var cells: Array = _node_cells.get(id, [])
	for cell: Vector2i in cells:
		if not _grid.has(cell):
			continue
		var arr: Array[Node3D] = _grid[cell]
		for i: int in range(arr.size() - 1, -1, -1):
			# Untyped read: arr[i] may be a freed instance; a typed bind would throw here.
			var e = arr[i]
			if not is_instance_valid(e) or e.get_instance_id() == id:
				arr.remove_at(i)
		if arr.is_empty():
			_grid.erase(cell)
	_node_cells.erase(id)


## Re-places a single port node after it moved/entered/left. An exit/free leaves it removed
## (insert is gated on tree).
static func grid_update(node: Node3D) -> void:
	if node == preview_ghost:
		return
	_grid_remove(node.get_instance_id())
	if is_instance_valid(node) and node.is_inside_tree() and not node.is_queued_for_deletion():
		_grid_insert(node)


static func _cells_for_aabb(aabb: AABB) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var min_cx: int = int(floor(aabb.position.x / _GRID_CELL_SIZE))
	var max_cx: int = int(floor((aabb.position.x + aabb.size.x) / _GRID_CELL_SIZE))
	var min_cz: int = int(floor(aabb.position.z / _GRID_CELL_SIZE))
	var max_cz: int = int(floor((aabb.position.z + aabb.size.z) / _GRID_CELL_SIZE))
	for cx: int in range(min_cx, max_cx + 1):
		for cz: int in range(min_cz, max_cz + 1):
			out.append(Vector2i(cx, cz))
	return out


static func _candidates_near(node: Node3D, grow: float) -> Array[Node3D]:
	if not _grid_built:
		_grid_seed_existing(node)
	var out: Array[Node3D] = []
	var seen: Dictionary = {}
	var stale: Array[int] = []
	for cell: Vector2i in _cells_for_aabb(_world_aabb(node).grow(grow)):
		# Untyped: a freed node may linger in the grid (a free that bypassed grid_update);
		# binding it to a Node3D-typed loop var throws before is_instance_valid can skip it.
		for n in _grid.get(cell, [] as Array[Node3D]):
			if not is_instance_valid(n):
				continue
			var id: int = n.get_instance_id()
			if not (n as Node3D).is_inside_tree():
				if not stale.has(id):
					stale.append(id)
				continue
			if seen.has(id):
				continue
			seen[id] = true
			out.append(n)
	for id: int in stale:
		_grid_remove(id)
	# Ghost is never gridded (it moves every frame without a transform notify) — append it directly.
	if preview_ghost != null and is_instance_valid(preview_ghost) and preview_ghost.is_inside_tree() \
			and not seen.has(preview_ghost.get_instance_id()):
		out.append(preview_ghost)
	return out


## Last-known near-neighbor set per mover (instance_id -> Array[Node3D]), so a part
## dragged out of contact can still ping the neighbor it left.
static var _contact_neighbors: Dictionary = {}

static var _leg_overlap_neighbors: Dictionary = {}


## Ping every port-node near [param mover] — plus those it was near last call — to re-derive
## from current contact.
func notify_contacts_rebuild(mover: Node3D) -> void:
	var id: int = mover.get_instance_id()
	# Re-place the mover before pinging, so its new cell is live for neighbors deriving this
	# frame — what keeps multi-move frames stale-free.
	grid_update(mover)
	var near: Array[Node3D] = []
	var crossers: Array[Node3D] = []
	# is_inside_tree() avoids the error get_tree() logs when the mover is out of tree.
	if mover.is_inside_tree():
		var candidates: Array[Node3D] = _candidates_near(mover, 0.3)
		var m_aabb: AABB = _world_aabb(mover).grow(0.3)
		near = _find_near_port_nodes(mover, m_aabb, candidates)
		crossers = _xz_overlapping_conveyors(mover, m_aabb, candidates)
	_ping_changed_neighbors(_contact_neighbors, id, near, _ping_rebuild)
	_ping_changed_neighbors(_leg_overlap_neighbors, id, crossers, _queue_leg_recheck)


static func _ping_changed_neighbors(store: Dictionary, id: int, current: Array[Node3D], ping: Callable) -> void:
	var prev: Array = store.get(id, [])
	for n: Node3D in current:
		ping.call(n)
	for n: Variant in prev:
		if is_instance_valid(n) and n is Node3D and not current.has(n):
			ping.call(n)
	if current.is_empty():
		store.erase(id)
	else:
		store[id] = current


static var _pending_leg_rechecks: Dictionary = {}
static var _leg_recheck_flush_queued: bool = false


func _queue_leg_recheck(n: Node3D) -> void:
	if not is_instance_valid(n) or not n.is_inside_tree() or n.is_queued_for_deletion():
		return
	_pending_leg_rechecks[n.get_instance_id()] = n
	if _leg_recheck_flush_queued:
		return
	_leg_recheck_flush_queued = true
	get_tree().physics_frame.connect(_flush_leg_rechecks, CONNECT_ONE_SHOT)


func _flush_leg_rechecks() -> void:
	_leg_recheck_flush_queued = false
	var pending: Dictionary = _pending_leg_rechecks
	_pending_leg_rechecks = {}
	for n: Variant in pending.values():
		if is_instance_valid(n) and n is Node3D and (n as Node3D).is_inside_tree() \
				and not (n as Node3D).is_queued_for_deletion():
			(n as Node3D).call(&"_request_legs_recheck")


static func _xz_overlapping_conveyors(mover: Node3D, m_aabb: AABB, candidates: Array[Node3D]) -> Array[Node3D]:
	var result: Array[Node3D] = []
	for other: Node3D in candidates:
		if other == mover or not is_instance_valid(other) or not other.is_inside_tree():
			continue
		if not other.has_method(&"_request_legs_recheck"):
			continue
		var o: AABB = _world_aabb(other)
		if m_aabb.position.x < o.end.x and m_aabb.end.x > o.position.x \
				and m_aabb.position.z < o.end.z and m_aabb.end.z > o.position.z:
			result.append(other)
	return result


static func _find_near_port_nodes(mover: Node3D, m_aabb: AABB, candidates: Array[Node3D]) -> Array[Node3D]:
	var result: Array[Node3D] = []
	# Bounding-box overlap, not center distance: a long thin belt's far (discharge)
	# end is nowhere near its center, so a radius test would miss neighbors there.
	for other: Node3D in candidates:
		if other == mover or not is_instance_valid(other) or not other.is_inside_tree():
			continue
		if m_aabb.intersects(_world_aabb(other)):
			result.append(other)
	return result


static func _world_aabb(node: Node3D) -> AABB:
	if not node.is_inside_tree():
		return AABB()
	var local: AABB = AABB()
	if &"local_bbox" in node:
		local = node.get(&"local_bbox") as AABB
	if local.size == Vector3.ZERO:
		var s: Vector3 = _get_conveyor_size(node)
		local = AABB(-s * 0.5, s)
	var xform: Transform3D = node.global_transform
	var world := AABB(xform * local.position, Vector3.ZERO)
	for i in range(1, 8):
		world = world.expand(xform * (local.position + Vector3(
			local.size.x if (i & 1) else 0.0,
			local.size.y if (i & 2) else 0.0,
			local.size.z if (i & 4) else 0.0)))
	return world


static func _ping_rebuild(n: Node3D) -> void:
	if not is_instance_valid(n) or not n.is_inside_tree() or n.is_queued_for_deletion():
		return
	if n.has_method(&"_request_connection_rebuild"):
		n.call_deferred(&"_request_connection_rebuild")
	elif n.has_method(&"_request_rebuild"):
		n.call_deferred(&"_request_rebuild")


## Side-guard geometry for a snapped conveyor whose end meets [param target_conveyor]'s
## [param side_str]. [param target_contact_local] drives the fallback opening when ray hits
## don't fire; pass Vector3.INF to disable it.
static func _compute_side_snap_geometry(
	snapped_xform: Transform3D, snapped_conveyor: Node3D,
	target_conveyor: Node3D, side_str: String,
	target_contact_local: Vector3
) -> Dictionary:
	var result: Dictionary = {
		"snapped_openings": [] as Array[SideGuardOpening],
		"snapped_extents": {} as Dictionary,
		"target_opening": null,
	}

	var target_xform := target_conveyor.global_transform
	var target_inverse := target_xform.affine_inverse()
	var target_size := _get_conveyor_size(target_conveyor)
	var frame_wt := ConveyorFrameMesh.WALL_THICKNESS
	var target_half_width: float = target_size.z * 0.5

	# Ray target = target's outer wall plane. Spur stops at the belt's outer face so its
	# frame doesn't intrude into the belt's slot interior.
	var side_z_local: float = (target_half_width + frame_wt) if side_str == "right" else -(target_half_width + frame_wt)
	var plane_point: Vector3 = target_xform * Vector3(0, 0, side_z_local)
	var plane_normal: Vector3 = target_xform.basis.z.normalized()
	if side_str == "left":
		plane_normal = -plane_normal

	# dir_sign>0: A's FRONT approaches B's plane (trim front); <0: BACK approaches.
	var snap_x_world: Vector3 = snapped_xform.basis.x.normalized()
	var dir_sign: float = -1.0 if snap_x_world.dot(plane_normal) > 0.0 else 1.0

	var a_width: float = float(snapped_conveyor.get(&"width")) if &"width" in snapped_conveyor else 1.524
	var a_half_w: float = a_width * 0.5
	var a_lateral_offsets := {
		"left": -(a_half_w + frame_wt),
		"right": a_half_w + frame_wt,
	}

	# Full Vector3 hits: stripping Y mis-attributes hits on elevated runs.
	var hits_in_target_local: Array[Vector3] = []
	var snapped_openings: Array[SideGuardOpening] = []
	var snapped_is_spur: bool = &"side_guard_snap_extents" in snapped_conveyor
	var pending_extents: Dictionary = {}
	var end_key_suffix: String = "_front" if dir_sign > 0.0 else "_back"

	var sn_arc_bounds: Vector2 = _get_conveyor_arc_bounds(snapped_conveyor)
	var snapped_arc_leading: float = sn_arc_bounds.y if dir_sign > 0.0 else sn_arc_bounds.x

	for side: String in ["left", "right"]:
		var bounds: Vector2 = _snapped_side_x_bounds(snapped_conveyor, side)
		var trailing_x: float = bounds.x if dir_sign > 0.0 else bounds.y
		var z_off: float = a_lateral_offsets[side]
		var ray_origin_world: Vector3 = snapped_xform * Vector3(trailing_x, 0, z_off)
		var ray_dir: Vector3 = snap_x_world * dir_sign
		var denom: float = ray_dir.dot(plane_normal)
		if absf(denom) < 0.001:
			continue
		var t_hit: float = (plane_point - ray_origin_world).dot(plane_normal) / denom
		if t_hit < 0.01:
			continue
		var hit_world: Vector3 = ray_origin_world + ray_dir * t_hit
		hits_in_target_local.append(target_inverse * hit_world)
		var hit_local: Vector3 = snapped_xform.affine_inverse() * hit_world
		var hit_x: float = hit_local.x
		if snapped_is_spur:
			pending_extents[side + end_key_suffix] = hit_x
		else:
			var hit_arc: float = _local_pos_to_arc(snapped_conveyor, hit_local)
			var open_start: float
			var open_end: float
			if dir_sign > 0.0:
				open_start = hit_arc
				open_end = snapped_arc_leading + 0.001
			else:
				open_start = snapped_arc_leading - 0.001
				open_end = hit_arc
			if open_end - open_start > 0.001:
				snapped_openings.append(SideGuardOpening.make(open_start, open_end, side))

	result.snapped_openings = snapped_openings
	result.snapped_extents = pending_extents

	# Target opening: prefer actual ray hits (matches spur's true footprint); fall back
	# to contact-centered + nominal width when hits don't fire.
	var sg_wt: float = SideGuardMesh.WALL_THICKNESS
	if hits_in_target_local.size() >= 2:
		var arc_min: float = INF
		var arc_max: float = -INF
		for h: Vector3 in hits_in_target_local:
			var arc: float = _local_pos_to_arc(target_conveyor, h)
			arc_min = minf(arc_min, arc)
			arc_max = maxf(arc_max, arc)
		var arc_bounds := _get_conveyor_arc_bounds(target_conveyor)
		var gap_start: float = maxf(arc_min + sg_wt, arc_bounds.x)
		var gap_end: float = minf(arc_max - sg_wt, arc_bounds.y)
		if gap_end - gap_start > 0.01:
			result.target_opening = SideGuardOpening.make(gap_start, gap_end, side_str)
	elif target_contact_local != Vector3.INF and target_conveyor.has_method(&"local_to_arc_length"):
		var center_arc: float = _local_pos_to_arc(target_conveyor, target_contact_local)
		var snapped_width: float = float(snapped_conveyor.get(&"width")) if &"width" in snapped_conveyor else _get_conveyor_size(snapped_conveyor).z
		var half_open: float = snapped_width * 0.5 + frame_wt - sg_wt
		if target_conveyor.has_method(&"tangent_at_local_pos"):
			var tangent_local: Vector3 = target_conveyor.call(&"tangent_at_local_pos", target_contact_local)
			var tangent_world: Vector3 = (target_xform.basis * tangent_local).normalized()
			var snap_z_world: Vector3 = snapped_xform.basis.z.normalized()
			var cos_angle: float = absf(tangent_world.dot(snap_z_world))
			cos_angle = maxf(cos_angle, 0.5)
			half_open = half_open / cos_angle
		var arc_bounds: Vector2 = _get_conveyor_arc_bounds(target_conveyor)
		var gap_start: float = maxf(center_arc - half_open, arc_bounds.x)
		var gap_end: float = minf(center_arc + half_open, arc_bounds.y)
		if gap_end - gap_start > 0.01:
			result.target_opening = SideGuardOpening.make(gap_start, gap_end, side_str)

	return result


## [back_x, front_x] of side guard in conveyor-local cartesian space.
static func _snapped_side_x_bounds(conveyor: Node3D, side: String) -> Vector2:
	if &"angle_downstream" in conveyor:
		var sn_length: float = float(conveyor.get(&"length")) if &"length" in conveyor else 2.0
		var sn_width: float = float(conveyor.get(&"width")) if &"width" in conveyor else 1.524
		var sn_angle_ds: float = float(conveyor.get(&"angle_downstream"))
		var sn_angle_us: float = float(conveyor.get(&"angle_upstream")) if &"angle_upstream" in conveyor else 0.0
		var inner_z: float = -sn_width * 0.5 if side == "left" else sn_width * 0.5
		var back_x: float = -sn_length * 0.5 + tan(sn_angle_us) * inner_z
		var front_x: float = sn_length * 0.5 + tan(sn_angle_ds) * inner_z
		return Vector2(back_x, front_x)
	if &"local_bbox" in conveyor:
		var bb: AABB = conveyor.get(&"local_bbox")
		if bb.size != Vector3.ZERO:
			return Vector2(bb.position.x, bb.end.x)
	# Fallback for path-based conveyors before _rebuild populates local_bbox.
	if conveyor.has_method(&"arc_bounds"):
		return conveyor.call(&"arc_bounds") as Vector2
	return Vector2(-2.0, 2.0)


static func _has_side_guards(conveyor: Node3D) -> bool:
	return ("right_side_guards_enabled" in conveyor and
			"left_side_guards_enabled" in conveyor)


static func _is_conveyor(node: Node) -> bool:
	var node_script: Script = node.get_script()
	var global_name: String = node_script.get_global_name() if node_script != null else ""
	var node_class := node.get_class()

	var conveyor_types := [
		"BeltSpurConveyor",
		"RollerSpurConveyor",
		"BeltConveyor", "RollerConveyor",
		"CurvedBeltConveyor", "CurvedRollerConveyor",
		"TurntableConveyor",
	]

	return global_name in conveyor_types or node_class in conveyor_types


static func _make_snap_result(snap_transform: Transform3D, snapped_end: Dictionary, target_end: Dictionary) -> Dictionary:
	var end_names := [&"front", &"back", &"head", &"tail"]
	return {
		"transform": snap_transform,
		"snapped_end": snapped_end,
		"target_end": target_end,
		"is_end_to_end": snapped_end.name in end_names and target_end.name in end_names,
	}


static func _calculate_snap_transform(selected_conveyor: Node3D, target_conveyor: Node3D, live_mode: bool = false) -> Dictionary:
	# Sensors snap to a side-guard segment regardless of the target's curvature/spur.
	if _is_sensor(selected_conveyor):
		return ConveyorSnapFeatures.try_snap(selected_conveyor, target_conveyor, live_mode)

	if _is_curved_conveyor(selected_conveyor) or _is_curved_conveyor(target_conveyor):
		return _calculate_curved_snap_transform(selected_conveyor, target_conveyor, live_mode)

	if _has_spur_angles(selected_conveyor):
		return _calculate_spur_snap_transform(selected_conveyor, target_conveyor, live_mode)

	if _has_spur_angles(target_conveyor):
		return _calculate_snap_to_spur_target_transform(selected_conveyor, target_conveyor, live_mode)

	return ConveyorSnapFeatures.try_snap(selected_conveyor, target_conveyor, live_mode)


static func _get_conveyor_size(conveyor: Node3D) -> Vector3:
	if "size" in conveyor:
		return conveyor.size
	return Vector3(4.0, 0.5, 1.524)


## Returns [back_x, front_x] in local space; path-based and centered conveyors handled.
static func _get_conveyor_x_bounds(conveyor: Node3D) -> Vector2:
	if conveyor != null and &"local_bbox" in conveyor:
		var bb: AABB = conveyor.get(&"local_bbox")
		if bb.size != Vector3.ZERO:
			return Vector2(bb.position.x, bb.end.x)
	var s: Vector3 = _get_conveyor_size(conveyor)
	return Vector2(-s.x * 0.5, s.x * 0.5)


## Arc-length bounds (path-based) or cartesian X bounds (legacy).
static func _get_conveyor_arc_bounds(conveyor: Node3D) -> Vector2:
	if conveyor != null and conveyor.has_method(&"arc_bounds"):
		return conveyor.call(&"arc_bounds") as Vector2
	return _get_conveyor_x_bounds(conveyor)


## Conveyor-local 3D point → arc-length on path. Takes full Vector3 (Y matters for elevated runs).
static func _local_pos_to_arc(conveyor: Node3D, local_pos: Vector3) -> float:
	if conveyor != null and conveyor.has_method(&"local_to_arc_length"):
		return float(conveyor.call(&"local_to_arc_length", local_pos))
	return local_pos.x


static func _get_closest_point_on_line_segment(point: Vector3, line_start: Vector3, line_end: Vector3) -> Vector3:
	var line_vector := line_end - line_start
	var line_length_squared := line_vector.length_squared()
	
	if line_length_squared == 0.0:
		return line_start
	
	var point_to_start := point - line_start
	var projection_factor := point_to_start.dot(line_vector) / line_length_squared
	projection_factor = clampf(projection_factor, 0.0, 1.0)
	
	return line_start + projection_factor * line_vector


## [min_x, max_x] where the polygon intersects a horizontal Z line; empty on no intersection.
static func _get_x_range_at_z(corners: Array[Vector3], z_val: float) -> Array[float]:
	var x_values: Array[float] = []
	var n := corners.size()
	for i in range(n):
		var a := corners[i]
		var b := corners[(i + 1) % n]
		if (a.z <= z_val and b.z >= z_val) or (a.z >= z_val and b.z <= z_val):
			if absf(b.z - a.z) < 0.0001:
				x_values.append(a.x)
				x_values.append(b.x)
			else:
				var t := (z_val - a.z) / (b.z - a.z)
				x_values.append(a.x + t * (b.x - a.x))
	if x_values.is_empty():
		return []
	return [x_values.min(), x_values.max()]


static func _get_z_inclination(transform: Transform3D) -> float:
	var forward := transform.basis.x.normalized()
	return atan2(forward.y, Vector2(forward.x, forward.z).length())


static func _apply_inclination_to_basis(basis: Basis, inclination: float) -> Basis:
	var horizontal_forward := Vector3(basis.x.x, 0, basis.x.z).normalized()
	var horizontal_right := Vector3(basis.z.x, 0, basis.z.z).normalized()
	
	var inclined_forward := horizontal_forward * cos(inclination) + Vector3.UP * sin(inclination)
	
	var new_basis := Basis()
	new_basis.x = inclined_forward
	new_basis.z = horizontal_right
	new_basis.y = new_basis.z.cross(new_basis.x).normalized()
	
	return new_basis 



static func _is_curved_conveyor(conveyor: Node3D) -> bool:
	if not live_type_cache.is_empty():
		var f: Variant = live_type_cache.get(conveyor.get_instance_id())
		if f != null:
			return f.is_curved
	var node_script: Script = conveyor.get_script()
	var global_name: String = node_script.get_global_name() if node_script != null else ""
	var node_class := conveyor.get_class()

	var curved_types := [
		"CurvedBeltConveyor", "CurvedRollerConveyor"
	]

	return global_name in curved_types or node_class in curved_types


static func _is_curved_roller_conveyor(conveyor: Node3D) -> bool:
	if not live_type_cache.is_empty():
		var f: Variant = live_type_cache.get(conveyor.get_instance_id())
		if f != null:
			return f.is_curved_roller
	var node_script: Script = conveyor.get_script()
	var global_name: String = node_script.get_global_name() if node_script != null else ""
	var node_class := conveyor.get_class()

	var curved_roller_types := [
		"CurvedRollerConveyor"
	]

	return global_name in curved_roller_types or node_class in curved_roller_types


static func _is_straight_conveyor_assembly(_conveyor: Node3D) -> bool:
	return false


static func _is_spur_conveyor(conveyor: Node3D) -> bool:
	if not live_type_cache.is_empty():
		var f: Variant = live_type_cache.get(conveyor.get_instance_id())
		if f != null:
			return f.is_spur
	var node_script: Script = conveyor.get_script()
	var global_name: String = node_script.get_global_name() if node_script != null else ""
	var node_class := conveyor.get_class()
	var spur_types := ["BeltSpurConveyor", "RollerSpurConveyor"]
	return global_name in spur_types or node_class in spur_types


static func _get_spur_angles(conveyor: Node3D) -> Dictionary:
	var angle_ds: float = 0.0
	var angle_us: float = 0.0
	if "angle_downstream" in conveyor:
		angle_ds = conveyor.angle_downstream
	if "angle_upstream" in conveyor:
		angle_us = conveyor.angle_upstream
	return {"downstream": angle_ds, "upstream": angle_us}


static func _has_spur_angles(conveyor: Node3D) -> bool:
	if not live_type_cache.is_empty():
		var f: Variant = live_type_cache.get(conveyor.get_instance_id())
		if f != null:
			return f.has_spur
	if not _is_spur_conveyor(conveyor):
		return false
	var angles := _get_spur_angles(conveyor)
	return abs(angles.downstream) > 0.001 or abs(angles.upstream) > 0.001


static func _get_curved_conveyor_angle(conveyor: Node3D) -> float:
	if "conveyor_angle" in conveyor:
		return conveyor.conveyor_angle
	var corner = conveyor.get_node_or_null("ConveyorCorner")
	if corner and "conveyor_angle" in corner:
		return corner.conveyor_angle
	return 90.0


static func _get_curved_conveyor_params(conveyor: Node3D) -> Dictionary:
	var inner_radius := 0.5
	var width := 1.524
	if "inner_radius" in conveyor:
		inner_radius = conveyor.inner_radius
	elif "inner_radius_f" in conveyor:
		inner_radius = conveyor.inner_radius_f
	if "width" in conveyor:
		width = conveyor.width
	var corner = conveyor.get_node_or_null("ConveyorCorner")
	if corner:
		if "inner_radius" in corner:
			inner_radius = corner.inner_radius
		if "width" in corner:
			width = corner.width
	return {"inner_radius": inner_radius, "width": width}


static func _get_curved_end_info(conveyor: Node3D) -> Array[Dictionary]:
	var angle_deg := _get_curved_conveyor_angle(conveyor)
	var angle_rad := deg_to_rad(angle_deg)
	var params := _get_curved_conveyor_params(conveyor)
	var avg_radius: float = params.inner_radius + params.width / 2.0

	var corner = conveyor.get_node_or_null("ConveyorCorner")
	var cc_offset: Vector3 = corner.position if corner else Vector3.ZERO

	var tail_pos: Vector3 = cc_offset + Vector3(0, 0, avg_radius)
	var tail_outward := Vector3(1, 0, 0)

	var head_pos: Vector3 = cc_offset + Vector3(-sin(angle_rad) * avg_radius, 0, cos(angle_rad) * avg_radius)
	var head_outward := Vector3(-cos(angle_rad), 0, -sin(angle_rad))

	return [
		{"pos": tail_pos, "outward": tail_outward, "name": "tail"},
		{"pos": head_pos, "outward": head_outward, "name": "head"},
	]


static func _get_straight_end_info(conveyor: Node3D) -> Array[Dictionary]:
	# Prefer the path-based real 3D end positions; fall back to symmetric X-bounds.
	if conveyor != null and conveyor.has_method(&"get_snap_features"):
		var features: Array = conveyor.call(&"get_snap_features")
		var front: Dictionary = {}
		var back: Dictionary = {}
		for f: Dictionary in features:
			match f.get(&"kind", &""):
				&"straight_end_front":
					front = f
				&"straight_end_back":
					back = f
		if not front.is_empty() and not back.is_empty():
			return [
				{"pos": front.local_pos, "outward": front.get(&"local_outward", Vector3(1, 0, 0)), "name": "front"},
				{"pos": back.local_pos, "outward": back.get(&"local_outward", Vector3(-1, 0, 0)), "name": "back"},
			]
	var x_bounds := _get_conveyor_x_bounds(conveyor)
	return [
		{"pos": Vector3(x_bounds.y, 0, 0), "outward": Vector3(1, 0, 0), "name": "front"},
		{"pos": Vector3(x_bounds.x, 0, 0), "outward": Vector3(-1, 0, 0), "name": "back"},
	]


static func _get_spur_end_info(conveyor: Node3D) -> Array[Dictionary]:
	var size := _get_conveyor_size(conveyor)
	var angles := _get_spur_angles(conveyor)
	var ds_outward := Vector3(cos(angles.downstream), 0, -sin(angles.downstream))
	var us_outward := Vector3(-cos(angles.upstream), 0, sin(angles.upstream))
	return [
		{"pos": Vector3(size.x, 0, 0), "outward": ds_outward, "name": "front"},
		{"pos": Vector3(0, 0, 0), "outward": us_outward, "name": "back"},
	]


static func _get_end_info(conveyor: Node3D) -> Array[Dictionary]:
	if _is_sensor(conveyor):
		var no_ends: Array[Dictionary] = []
		return no_ends
	if not live_end_info_cache.is_empty():
		var cached: Variant = live_end_info_cache.get(conveyor.get_instance_id())
		if cached != null:
			return cached
	if _is_curved_conveyor(conveyor):
		return _get_curved_end_info(conveyor)
	if _has_spur_angles(conveyor):
		return _get_spur_end_info(conveyor)
	return _get_straight_end_info(conveyor)


static func _snap_end_to_end(
	selected_conveyor: Node3D,
	sel_end: Dictionary,
	target_conveyor: Node3D,
	tgt_end: Dictionary,
	gap: float
) -> Transform3D:
	var target_transform := get_target_xform(target_conveyor)
	var tgt_pos: Vector3 = tgt_end.pos
	var tgt_out: Vector3 = tgt_end.outward
	var tgt_end_world: Vector3 = target_transform * tgt_pos
	var tgt_outward_world: Vector3 = (target_transform.basis * tgt_out).normalized()

	var desired_outward: Vector3 = -tgt_outward_world
	var sel_out: Vector3 = sel_end.outward
	var sel_pos_local: Vector3 = sel_end.pos
	var sel_heading := atan2(sel_out.x, sel_out.z)
	var desired_heading := atan2(desired_outward.x, desired_outward.z)
	var y_rotation := desired_heading - sel_heading

	var new_basis := Basis(Vector3.UP, y_rotation)
	var rotated_sel_end: Vector3 = new_basis * sel_pos_local
	var snap_pos: Vector3 = tgt_end_world + tgt_outward_world * gap - rotated_sel_end

	return Transform3D(new_basis, snap_pos)


static func _get_snap_gap(selected_conveyor: Node3D, target_conveyor: Node3D) -> float:
	var sel_curved := _is_curved_conveyor(selected_conveyor)
	var tgt_curved := _is_curved_conveyor(target_conveyor)

	if sel_curved and tgt_curved:
		var both_roller := _is_curved_roller_conveyor(selected_conveyor) and _is_curved_roller_conveyor(target_conveyor)
		var both_belt := not _is_curved_roller_conveyor(selected_conveyor) and not _is_curved_roller_conveyor(target_conveyor)
		if both_roller:
			return 0.004
		elif both_belt:
			return 0.5
		return 0.25
	elif sel_curved or tgt_curved:
		var curved := selected_conveyor if sel_curved else target_conveyor
		if _is_curved_roller_conveyor(curved):
			return 0.001
		return 0.25
	return 0.0


static func _find_closest_end_pair(selected_conveyor: Node3D, target_conveyor: Node3D) -> Array[Dictionary]:
	var sel_ends := _get_end_info(selected_conveyor)
	var tgt_ends := _get_end_info(target_conveyor)
	var sel_transform := get_selected_xform(selected_conveyor)
	var tgt_transform := get_target_xform(target_conveyor)

	var best_dist := INF
	var best_sel: Dictionary
	var best_tgt: Dictionary

	for se in sel_ends:
		for te in tgt_ends:
			var se_pos: Vector3 = se.pos
			var te_pos: Vector3 = te.pos
			var sel_world: Vector3 = sel_transform * se_pos
			var tgt_world: Vector3 = tgt_transform * te_pos
			var dist := sel_world.distance_to(tgt_world)
			if dist < best_dist:
				best_dist = dist
				best_sel = se
				best_tgt = te

	return [best_sel, best_tgt]


## Same target end, flipped selected end — mirrors selected's orientation at the attachment.
static func _find_resnap_end_pair(selected_conveyor: Node3D, target_conveyor: Node3D) -> Array[Dictionary]:
	var sel_ends := _get_end_info(selected_conveyor)
	var tgt_ends := _get_end_info(target_conveyor)
	var sel_transform := get_selected_xform(selected_conveyor)
	var tgt_transform := get_target_xform(target_conveyor)

	var best_dist := INF
	var snapped_sel_idx := 0
	var snapped_tgt_idx := 0

	for si in range(sel_ends.size()):
		for ti in range(tgt_ends.size()):
			var se_pos: Vector3 = sel_ends[si].pos
			var te_pos: Vector3 = tgt_ends[ti].pos
			var sel_world: Vector3 = sel_transform * se_pos
			var tgt_world: Vector3 = tgt_transform * te_pos
			var dist := sel_world.distance_to(tgt_world)
			if dist < best_dist:
				best_dist = dist
				snapped_sel_idx = si
				snapped_tgt_idx = ti

	var other_sel_idx := 1 - snapped_sel_idx
	return [sel_ends[other_sel_idx], tgt_ends[snapped_tgt_idx]]



static func _is_output_end(conveyor: Node3D, end_info: Dictionary) -> bool:
	if _is_curved_conveyor(conveyor):
		var prop := get_reverse_property_name(conveyor)
		var reversed: bool = bool(conveyor.get(prop)) if prop != &"" else false
		return (end_info.name == "head") != reversed
	return end_info.name == "front"


static func get_reverse_property_name(conveyor: Node3D) -> StringName:
	if conveyor != null and "reverse" in conveyor:
		return &"reverse"
	return &""


static func _find_closest_free_end_pair(
	selected_conveyor: Node3D, target_conveyor: Node3D, gap: float
) -> Dictionary:
	var sel_ends := _get_end_info(selected_conveyor)
	var tgt_ends := _get_end_info(target_conveyor)
	var sel_transform := get_selected_xform(selected_conveyor)

	var best_pair: Array[Dictionary]
	var best_compatible: bool = false
	var best_dist := INF

	for se_idx in range(sel_ends.size()):
		var se := sel_ends[se_idx]
		var other_se := sel_ends[1 - se_idx]
		var free_end_before: Vector3 = sel_transform * other_se.pos
		var se_is_output := _is_output_end(selected_conveyor, se)

		for te in tgt_ends:
			var snap_t := _snap_end_to_end(selected_conveyor, se, target_conveyor, te, gap)
			var free_end_after: Vector3 = snap_t * other_se.pos
			var dist := free_end_before.distance_to(free_end_after)
			if dist < best_dist:
				best_dist = dist
				best_pair = [se, te]
				best_compatible = se_is_output != _is_output_end(target_conveyor, te)

	return {"pair": best_pair, "needs_reverse": not best_compatible}


static func _calculate_curved_snap_transform(selected_conveyor: Node3D, target_conveyor: Node3D, live_mode: bool = false) -> Dictionary:
	if _is_straight_conveyor(target_conveyor) and _is_straight_conveyor(selected_conveyor):
		return ConveyorSnapFeatures.try_snap(selected_conveyor, target_conveyor, live_mode)

	var gap := _get_snap_gap(selected_conveyor, target_conveyor)

	var info := _find_closest_free_end_pair(selected_conveyor, target_conveyor, gap)
	var pair: Array[Dictionary] = info.pair
	var needs_reverse: bool = info.needs_reverse
	# No-op flip cycles end pair when snap matches current pose; suppressed in live (oscillates).
	if not live_mode:
		var snap_t := _snap_end_to_end(selected_conveyor, pair[0], target_conveyor, pair[1], gap)
		var current := get_selected_xform(selected_conveyor)
		if current.origin.distance_to(snap_t.origin) < 0.01 and current.basis.x.dot(snap_t.basis.x) > 0.999:
			pair = _find_resnap_end_pair(selected_conveyor, target_conveyor)
			var se_is_output := _is_output_end(selected_conveyor, pair[0])
			needs_reverse = se_is_output == _is_output_end(target_conveyor, pair[1])

	var snap_transform := _snap_end_to_end(selected_conveyor, pair[0], target_conveyor, pair[1], gap)
	var result := _make_snap_result(snap_transform, pair[0], pair[1])
	result["needs_reverse"] = needs_reverse
	return result


static func _calculate_spur_snap_transform(selected_conveyor: Node3D, target_conveyor: Node3D, live_mode: bool = false) -> Dictionary:
	var sel_transform := get_selected_xform(selected_conveyor)
	var tgt_transform := target_conveyor.global_transform
	var tgt_size := _get_conveyor_size(target_conveyor)
	var x_bounds := _get_conveyor_x_bounds(target_conveyor)
	var selected_position := sel_transform.origin

	var target_front := tgt_transform.origin + tgt_transform.basis.x * x_bounds.y
	var target_back := tgt_transform.origin + tgt_transform.basis.x * x_bounds.x

	var left_edge_start := tgt_transform.origin - tgt_transform.basis.z * (tgt_size.z / 2.0) + tgt_transform.basis.x * x_bounds.x
	var left_edge_end := tgt_transform.origin - tgt_transform.basis.z * (tgt_size.z / 2.0) + tgt_transform.basis.x * x_bounds.y
	var left_closest := _get_closest_point_on_line_segment(selected_position, left_edge_start, left_edge_end)

	var right_edge_start := tgt_transform.origin + tgt_transform.basis.z * (tgt_size.z / 2.0) + tgt_transform.basis.x * x_bounds.x
	var right_edge_end := tgt_transform.origin + tgt_transform.basis.z * (tgt_size.z / 2.0) + tgt_transform.basis.x * x_bounds.y
	var right_closest := _get_closest_point_on_line_segment(selected_position, right_edge_start, right_edge_end)

	var dist_front := selected_position.distance_to(target_front)
	var dist_back := selected_position.distance_to(target_back)
	var dist_left := selected_position.distance_to(left_closest)
	var dist_right := selected_position.distance_to(right_closest)

	var min_end_dist: float = min(dist_front, dist_back)
	var min_side_dist: float = min(dist_left, dist_right)

	if min_end_dist < min_side_dist:
		return ConveyorSnapFeatures.try_snap(selected_conveyor, target_conveyor, live_mode)

	var side_outward: Vector3
	var side_edge_start: Vector3
	var side_edge_end: Vector3
	if dist_left < dist_right:
		side_outward = Vector3(0, 0, -1)
		side_edge_start = left_edge_start
		side_edge_end = left_edge_end
	else:
		side_outward = Vector3(0, 0, 1)
		side_edge_start = right_edge_start
		side_edge_end = right_edge_end

	var sel_ends := _get_spur_end_info(selected_conveyor)
	var best_sel: Dictionary = sel_ends[0]
	var best_dist := INF
	for se in sel_ends:
		var se_world: Vector3 = sel_transform * (se.pos as Vector3)
		var side_closest := _get_closest_point_on_line_segment(se_world, side_edge_start, side_edge_end)
		var dist := se_world.distance_to(side_closest)
		if dist < best_dist:
			best_dist = dist
			best_sel = se

	var best_sel_world: Vector3 = sel_transform * (best_sel.pos as Vector3)
	var side_contact := _get_closest_point_on_line_segment(best_sel_world, side_edge_start, side_edge_end)
	var side_pos_local: Vector3 = tgt_transform.affine_inverse() * side_contact
	var side_name: StringName = &"left_side" if dist_left < dist_right else &"right_side"
	var side_end := {"pos": side_pos_local, "outward": side_outward, "name": side_name}

	# Belt spurs clear the belt's frame flange (FLANGE_WIDTH * 2). Roller spurs need more
	# room for the end pulley.
	var spur_gap := ConveyorFrameMesh.FLANGE_WIDTH * 2.0
	if not "conveyor_count" in selected_conveyor:
		spur_gap = 0.12

	var snap_transform := _snap_end_to_end(selected_conveyor, best_sel, target_conveyor, side_end, spur_gap)
	return _make_snap_result(snap_transform, best_sel, side_end)


static func _calculate_snap_to_spur_target_transform(selected_conveyor: Node3D, target_spur: Node3D, live_mode: bool = false) -> Dictionary:
	var sel_transform := get_selected_xform(selected_conveyor)
	var tgt_transform := target_spur.global_transform
	var tgt_size := _get_conveyor_size(target_spur)
	var x_bounds := _get_conveyor_x_bounds(target_spur)
	var selected_position := sel_transform.origin

	var tgt_ends := _get_spur_end_info(target_spur)
	var tgt_front_world: Vector3 = tgt_transform * (tgt_ends[0].pos as Vector3)
	var tgt_back_world: Vector3 = tgt_transform * (tgt_ends[1].pos as Vector3)

	var left_edge_start := tgt_transform.origin - tgt_transform.basis.z * (tgt_size.z / 2.0) + tgt_transform.basis.x * x_bounds.x
	var left_edge_end := tgt_transform.origin - tgt_transform.basis.z * (tgt_size.z / 2.0) + tgt_transform.basis.x * x_bounds.y
	var left_closest := _get_closest_point_on_line_segment(selected_position, left_edge_start, left_edge_end)

	var right_edge_start := tgt_transform.origin + tgt_transform.basis.z * (tgt_size.z / 2.0) + tgt_transform.basis.x * x_bounds.x
	var right_edge_end := tgt_transform.origin + tgt_transform.basis.z * (tgt_size.z / 2.0) + tgt_transform.basis.x * x_bounds.y
	var right_closest := _get_closest_point_on_line_segment(selected_position, right_edge_start, right_edge_end)

	var dist_front := selected_position.distance_to(tgt_front_world)
	var dist_back := selected_position.distance_to(tgt_back_world)
	var dist_left := selected_position.distance_to(left_closest)
	var dist_right := selected_position.distance_to(right_closest)

	var min_end_dist: float = min(dist_front, dist_back)
	var min_side_dist: float = min(dist_left, dist_right)

	if min_end_dist > min_side_dist:
		return ConveyorSnapFeatures.try_snap(selected_conveyor, target_spur, live_mode)

	var best_tgt: Dictionary = tgt_ends[0] if dist_front < dist_back else tgt_ends[1]
	var best_tgt_world: Vector3 = tgt_transform * (best_tgt.pos as Vector3)

	var sel_ends := _get_straight_end_info(selected_conveyor)
	var best_sel: Dictionary = sel_ends[0]
	var best_dist := INF
	for se in sel_ends:
		var se_world: Vector3 = sel_transform * (se.pos as Vector3)
		var dist := se_world.distance_to(best_tgt_world)
		if dist < best_dist:
			best_dist = dist
			best_sel = se

	var snap_transform := _snap_end_to_end(selected_conveyor, best_sel, target_spur, best_tgt, 0.0)
	return _make_snap_result(snap_transform, best_sel, best_tgt)


static func _is_straight_conveyor(conveyor: Node3D) -> bool:
	if not live_type_cache.is_empty():
		var f: Variant = live_type_cache.get(conveyor.get_instance_id())
		if f != null:
			return f.is_straight
	var node_script: Script = conveyor.get_script()
	var global_name: String = node_script.get_global_name() if node_script != null else ""
	var node_class := conveyor.get_class()

	var straight_types := [
		"BeltConveyor", "BeltSpurConveyor",
		"RollerConveyor",
		"RollerSpurConveyor",
		"TurntableConveyor",
	]

	return global_name in straight_types or node_class in straight_types


static func _is_diverter(node: Node) -> bool:
	return node is Diverter


static func _is_chain_transfer(node: Node) -> bool:
	return node is ChainTransfer


static func _is_blade_stop(node: Node) -> bool:
	return node is BladeStop


static func _is_sensor(node: Node) -> bool:
	return node is DiffuseSensor or node is LaserSensor or node is ColorSensor


static func _is_roller_conveyor(node: Node) -> bool:
	return node is RollerConveyor


static func _world_pos_for_port(node: Node3D, port: StringName) -> Vector3:
	for end_info: Dictionary in _get_end_info(node):
		if (end_info.name as StringName) == port:
			return node.global_transform * (end_info.pos as Vector3)
	# A diverter's "push_side" lives in get_snap_features(), not _get_end_info.
	if node.has_method(&"get_snap_features"):
		for feature: Dictionary in node.call(&"get_snap_features"):
			if (feature.get(&"end_name", &"") as StringName) == port:
				return node.global_transform * (feature.get(&"local_pos", Vector3.ZERO) as Vector3)
	return Vector3.INF


static func _world_pos_near_side_plane(point: Vector3, node: Node3D, side_port: StringName, tolerance: float) -> bool:
	var xform := node.global_transform
	var size := _get_conveyor_size(node)
	var frame_wt := ConveyorFrameMesh.WALL_THICKNESS
	var half_width: float = size.z * 0.5
	var side_z_local: float = (half_width + frame_wt) if side_port == &"right_side" else -(half_width + frame_wt)
	var plane_point: Vector3 = xform * Vector3(0, 0, side_z_local)
	var plane_normal: Vector3 = xform.basis.z.normalized()
	if side_port == &"left_side":
		plane_normal = -plane_normal
	if absf((point - plane_point).dot(plane_normal)) >= tolerance:
		return false
	# Contact must also land within the side's length. Use the RAW local X, not
	# _local_pos_to_arc — that clamps to the run extent, so it never rejects a point
	# past the belt's end, letting a spur's end falsely match a far conveyor whose
	# infinite side-plane it merely grazes.
	var local_x: float = (xform.affine_inverse() * point).x
	var x_bounds: Vector2 = _get_conveyor_x_bounds(node)
	return local_x >= x_bounds.x - tolerance and local_x <= x_bounds.y + tolerance
