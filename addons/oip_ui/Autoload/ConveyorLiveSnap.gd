@tool
class_name ConveyorLiveSnap
extends Node

## Live snap for conveyors during gizmo drags and drop-hover. Hold Alt to escape.

const SEARCH_RADIUS: float = 3.0
const VISIBLE_THRESHOLD: float = 0.3
const FACING_PRESERVED_DOT: float = 0.85
const SNAP_DISABLE_MODIFIER: Key = KEY_ALT
const _DEBUG_SNAP: bool = false
const _NO_SNAP_FLOOR_LIFT: float = 2.0
const _NO_SNAP_SURFACE_TOLERANCE: float = 0.25
const _BASELINE_REVERSE_META := &"_snap_baseline_reverse"
const _BASELINE_FLOOR_META := &"_snap_baseline_floor_plane"
const _FLIP_DECISION_META := &"_snap_flip_decision"

var _selected: Node3D = null
var _snap_result: Dictionary = {}
var _pre_snap_transform: Variant = null
var _pre_snap_reverse: Variant = null
var _flip_locked: bool = false
var _active_snap: bool = false
var _committing: bool = false
var _candidate_cache: Array[Dictionary] = []
var _candidate_cache_node: Node3D = null
var _cache_sel_features: Variant = null
var _cache_sel_end_info: Array = []
var _active_preview_count: int = 0
var _preview_snap_pending: Dictionary = {}
var _preview_target: Node3D = null
var _candidate_excludes: Dictionary = {}
var _floor_request: Dictionary = {}
var _floor_cache: Dictionary = {}

static var instance: ConveyorLiveSnap


func _enter_tree() -> void:
	if not Engine.is_editor_hint():
		return
	instance = self
	set_process(true)
	set_physics_process(true)
	EditorInterface.get_editor_undo_redo().history_changed.connect(_on_undo_history_changed)
	get_tree().node_added.connect(_on_node_added_for_preview)


func _exit_tree() -> void:
	if not Engine.is_editor_hint():
		return
	var undo_redo := EditorInterface.get_editor_undo_redo()
	if undo_redo.history_changed.is_connected(_on_undo_history_changed):
		undo_redo.history_changed.disconnect(_on_undo_history_changed)
	if get_tree() and get_tree().node_added.is_connected(_on_node_added_for_preview):
		get_tree().node_added.disconnect(_on_node_added_for_preview)


func _process(_delta: float) -> void:
	if not Engine.is_editor_hint():
		return
	_ensure_hook()


func _physics_process(_delta: float) -> void:
	if not Engine.is_editor_hint() or _floor_request.is_empty():
		return
	var req := _floor_request
	_floor_request = {}
	var node: Node3D = req.get("node")
	if not is_instance_valid(node):
		return
	var plane := _detect_floor_below(node, req.origin, req.exclude_rids)
	_floor_cache[node.get_instance_id()] = plane


func _request_floor_below(node: Node3D, origin: Vector3, exclude_rids: Array) -> Variant:
	_floor_request = {"node": node, "origin": origin, "exclude_rids": exclude_rids}
	if _floor_cache.has(node.get_instance_id()):
		return _floor_cache[node.get_instance_id()]
	return null


func _on_undo_history_changed() -> void:
	if _committing:
		return
	if _active_snap and _pre_snap_transform != null:
		_commit()
	if not _preview_snap_pending.is_empty():
		var pending := _preview_snap_pending
		_preview_snap_pending = {}
		_commit_preview_snap_guards.call_deferred(pending)
	_reset()


func _on_node_added_for_preview(node: Node) -> void:
	if not Engine.is_editor_hint():
		return
	if not (node is Node3D) or not _is_snappable(node as Node3D):
		return
	var edited_root := EditorInterface.get_edited_scene_root()
	if edited_root == null:
		return
	if edited_root == node or edited_root.is_ancestor_of(node):
		return
	_preview_snap_pending = {}
	_active_preview_count += 1
	node.set_meta(&"_snap_transform", _on_preview_snap.bind(node))
	node.tree_exiting.connect(_on_preview_exiting.bind(node), CONNECT_ONE_SHOT)


func _on_preview_exiting(node: Node) -> void:
	_active_preview_count = maxi(0, _active_preview_count - 1)
	if ConveyorSnapping.preview_ghost == node:
		ConveyorSnapping.preview_ghost = null
	if _preview_target != null:
		ConveyorSnapping._ping_rebuild(_preview_target)
		_preview_target = null
	_clear_preview_pending_if_match.call_deferred(node)
	_floor_cache.erase(node.get_instance_id())


func _clear_preview_pending_if_match(node: Variant) -> void:
	if not is_instance_valid(node):
		return
	if _preview_snap_pending.get("preview") == node:
		_preview_snap_pending = {}


func _on_preview_snap(proposed: Transform3D, node: Node3D) -> Variant:
	_snapshot_baselines(node)
	var snap_disabled := not ConveyorSnapping.live_snap_enabled or Input.is_physical_key_pressed(SNAP_DISABLE_MODIFIER)
	var found: Dictionary = {} if snap_disabled else _find_snap(node, proposed)
	if _DEBUG_SNAP:
		print("[snap] preview node=", node.name, " sensor=", ConveyorSnapping._is_sensor(node),
				" proposed=", proposed.origin, " disabled=", snap_disabled,
				" candidates=", _candidate_cache.size(), " found=", not found.is_empty())

	if found.is_empty():
		ConveyorSnapping.preview_ghost = null
		if _preview_target != null:
			ConveyorSnapping._ping_rebuild(_preview_target)
			_preview_target = null
		var no_snap_xform: Variant = _try_no_snap_floor_drop(node, proposed)
		if no_snap_xform is Transform3D:
			return no_snap_xform
		_preview_snap_pending = {}
		_restore_preview_state(node)
		return null

	if found.result.has("scale"):
		var target_scale: Vector3 = found.result.scale
		if not node.scale.is_equal_approx(target_scale):
			node.scale = target_scale
	if found.result.has("property_overrides"):
		var overrides: Dictionary = found.result.property_overrides
		for prop: String in overrides:
			if not is_equal_approx(float(node.get(prop)), float(overrides[prop])):
				node.set(prop, overrides[prop])
	_apply_preview_reverse_flip(node, found.result)
	_apply_preview_floor(node, found.result.transform, found.target)
	found["preview"] = node
	_preview_snap_pending = found
	ConveyorSnapping.preview_ghost = node
	# The ghost's preview bbox is degenerate, so it can't ping neighbors itself — ping the target.
	var tgt: Node3D = found.target
	if _preview_target != null and _preview_target != tgt:
		ConveyorSnapping._ping_rebuild(_preview_target)
	_preview_target = tgt
	if tgt != null:
		ConveyorSnapping._ping_rebuild(tgt)
	return found.result.transform


static func _snapshot_baselines(node: Node3D) -> void:
	var reverse_prop := ConveyorSnapping.get_reverse_property_name(node)
	if reverse_prop != &"" and not node.has_meta(_BASELINE_REVERSE_META):
		node.set_meta(_BASELINE_REVERSE_META, bool(node.get(reverse_prop)))
	if &"floor_plane" in node and not node.has_meta(_BASELINE_FLOOR_META):
		node.set_meta(_BASELINE_FLOOR_META, node.get(&"floor_plane"))


static func _apply_preview_reverse_flip(node: Node3D, result: Dictionary) -> void:
	var prop := ConveyorSnapping.get_reverse_property_name(node)
	if prop == &"":
		return
	if not node.has_meta(_FLIP_DECISION_META):
		node.set_meta(_FLIP_DECISION_META, bool(result.get("needs_reverse", false)))
	var baseline: bool = bool(node.get_meta(_BASELINE_REVERSE_META))
	var should_flip: bool = bool(node.get_meta(_FLIP_DECISION_META))
	var target_value: bool = (not baseline) if should_flip else baseline
	if bool(node.get(prop)) != target_value:
		node.set(prop, target_value)


static func _apply_preview_floor(node: Node3D, snap_xform: Transform3D, target: Node3D) -> void:
	if not (&"floor_plane" in node):
		return
	var floor_plane := _resolve_target_floor_plane(node, snap_xform.origin, target)
	node.set(&"floor_plane", floor_plane)


func _try_no_snap_floor_drop(node: Node3D, proposed: Transform3D) -> Variant:
	if not (&"floor_plane" in node):
		return null
	var exclude_rids: Array = []
	_collect_collision_rids(node, exclude_rids)
	var detected_var := _request_floor_below(node, proposed.origin, exclude_rids)
	if not (detected_var is Plane):
		return null
	var detected: Plane = detected_var
	if detected.normal == Vector3.ZERO or detected.is_equal_approx(Plane(Vector3.UP, 0.0)):
		return null
	if absf(detected.distance_to(proposed.origin)) > _NO_SNAP_SURFACE_TOLERANCE:
		return null
	node.set(&"floor_plane", detected)
	var lift_dir: Vector3 = detected.normal.normalized()
	var lifted := Transform3D(proposed.basis, proposed.origin + lift_dir * _NO_SNAP_FLOOR_LIFT)
	_preview_snap_pending = {
		"target": null,
		"result": {"transform": lifted, "no_snap_floor": detected},
		"preview": node,
	}
	return lifted


static func _restore_preview_state(node: Node3D) -> void:
	if node.has_meta(_FLIP_DECISION_META):
		node.remove_meta(_FLIP_DECISION_META)
	var reverse_prop := ConveyorSnapping.get_reverse_property_name(node)
	if reverse_prop != &"" and node.has_meta(_BASELINE_REVERSE_META):
		var baseline_reverse: bool = bool(node.get_meta(_BASELINE_REVERSE_META))
		if bool(node.get(reverse_prop)) != baseline_reverse:
			node.set(reverse_prop, baseline_reverse)
	if &"floor_plane" in node and node.has_meta(_BASELINE_FLOOR_META):
		var saved_global: Plane = node.get_meta(_BASELINE_FLOOR_META) as Plane
		if (node.get(&"floor_plane") as Plane) != saved_global:
			node.set(&"floor_plane", saved_global)


static func _resolve_target_floor_plane(node: Node3D, origin: Vector3, target: Node3D) -> Plane:
	var floor_source: Node3D = target
	while is_instance_valid(floor_source) and not (&"floor_plane" in floor_source):
		floor_source = floor_source.get_parent() as Node3D
	if is_instance_valid(floor_source):
		var inherited: Plane = floor_source.get(&"floor_plane")
		if inherited.normal != Vector3.ZERO:
			return inherited
	var exclude_rids: Array = []
	if is_instance_valid(node):
		_collect_collision_rids(node, exclude_rids)
	if is_instance_valid(target):
		_collect_collision_rids(target, exclude_rids)
	return _detect_floor_below(node, origin, exclude_rids)


func _commit_preview_snap_guards(pending: Dictionary) -> void:
	var target: Node3D = pending.get("target")
	var result: Dictionary = pending.get("result", {})
	var preview: Node3D = pending.get("preview")
	if result.is_empty():
		return
	var new_node := _pick_snappable()
	if new_node == null or not is_instance_valid(new_node):
		return

	var should_apply_scale: bool = result.has("scale")
	var property_overrides: Dictionary = result.get("property_overrides", {})
	var reverse_prop := ConveyorSnapping.get_reverse_property_name(new_node)
	var should_apply_reverse: bool = false
	var reverse_value: bool = false
	if reverse_prop != &"" and is_instance_valid(preview):
		reverse_value = bool(preview.get(reverse_prop))
		should_apply_reverse = reverse_value != bool(new_node.get(reverse_prop))
	var should_apply_floor: bool = false
	var floor_value: Plane
	if &"floor_plane" in new_node:
		var no_snap_floor: Variant = result.get("no_snap_floor", null)
		if no_snap_floor is Plane:
			floor_value = no_snap_floor
		else:
			floor_value = _resolve_target_floor_plane(new_node, result.transform.origin, target)
		should_apply_floor = floor_value != (new_node.get("floor_plane") as Plane)
	if not should_apply_scale and not should_apply_reverse and not should_apply_floor and property_overrides.is_empty():
		return

	var undo_redo := EditorInterface.get_editor_undo_redo()
	_committing = true
	undo_redo.create_action("Create Node", UndoRedo.MERGE_ALL)

	if should_apply_scale:
		undo_redo.add_do_property(new_node, "scale", result.scale as Vector3)

	for prop: String in property_overrides:
		undo_redo.add_do_property(new_node, prop, property_overrides[prop])

	if should_apply_reverse:
		undo_redo.add_do_property(new_node, reverse_prop, reverse_value)

	if should_apply_floor:
		undo_redo.add_do_property(new_node, "floor_plane", floor_value)

	undo_redo.commit_action()
	_committing = false


func bind_snap_meta(node: Node3D) -> void:
	if not is_instance_valid(node):
		return
	node.set_meta(&"_snap_transform", _on_gizmo_transform.bind(node))


func _ensure_hook() -> bool:
	var selected := _pick_snappable()
	if selected == null:
		if _pre_snap_transform == null and _active_preview_count == 0:
			_unhook()
			_reset()
		return false

	if _selected != null and _selected != selected:
		if _active_snap and _pre_snap_transform != null:
			_commit()
		_unhook()
		_reset()

	_selected = selected
	selected.set_meta(&"_snap_transform", _on_gizmo_transform.bind(selected))
	return true


func _unhook() -> void:
	if _selected != null and is_instance_valid(_selected):
		_selected.set_meta(&"_snap_transform", _on_gizmo_transform.bind(_selected))


func _reset() -> void:
	_selected = null
	_snap_result = {}
	_pre_snap_transform = null
	_pre_snap_reverse = null
	_flip_locked = false
	_active_snap = false
	_candidate_cache.clear()
	_candidate_cache_node = null
	_cache_sel_features = null
	_cache_sel_end_info = []
	_candidate_excludes = {}
	ConveyorSnapping.live_type_cache.clear()
	ConveyorSnapping.live_end_info_cache.clear()


func _on_gizmo_transform(proposed: Transform3D, selected: Node3D) -> Variant:
	var snap_disabled := not ConveyorSnapping.live_snap_enabled or Input.is_physical_key_pressed(SNAP_DISABLE_MODIFIER)
	var sel := EditorInterface.get_selection()
	var top_count: int = sel.get_top_selected_nodes().size() if sel != null else 0
	if top_count > 1:
		return _group_snap(proposed, selected, snap_disabled)
	if not _is_snappable(selected):
		_restore_pre_snap_reverse()
		_active_snap = false
		return null
	return _single_snap(proposed, selected, snap_disabled)


func _single_snap(proposed: Transform3D, selected: Node3D, snap_disabled: bool) -> Variant:
	if not _candidate_excludes.is_empty():
		_candidate_excludes = {}
		_candidate_cache.clear()
		_candidate_cache_node = null
	if _selected != selected:
		_selected = selected
		_snap_result = {}
		_pre_snap_transform = null
		_pre_snap_reverse = null
		_flip_locked = false
		_active_snap = false
		_candidate_cache.clear()
		_candidate_cache_node = null
		_cache_sel_features = null
		_cache_sel_end_info = []

	if snap_disabled:
		_restore_pre_snap_reverse()
		_active_snap = false
		return null

	var found := _find_snap(selected, proposed)
	if found.is_empty():
		_restore_pre_snap_reverse()
		_active_snap = false
		return null

	if _pre_snap_transform == null:
		_pre_snap_transform = proposed
	_snap_result = found.result
	_apply_live_reverse_flip()
	_active_snap = true
	return _snap_result.transform


func _group_snap(proposed: Transform3D, selected: Node3D, snap_disabled: bool) -> Variant:
	if snap_disabled:
		return null
	if not proposed.basis.is_equal_approx(selected.global_transform.basis):
		return null

	var anchor := _get_active_anchor()
	if anchor == null:
		return null

	var anchor_proposed: Transform3D = anchor.global_transform
	anchor_proposed.origin += proposed.origin - selected.global_transform.origin

	var new_excludes := _build_group_exclude_set()
	if not _excludes_equal(_candidate_excludes, new_excludes):
		_candidate_cache.clear()
		_candidate_cache_node = null
		_candidate_excludes = new_excludes

	var found := _find_snap(anchor, anchor_proposed)
	if found.is_empty():
		return null

	var snap_xform: Transform3D = found.result.transform
	if not snap_xform.basis.is_equal_approx(anchor_proposed.basis):
		return null
	if found.result.get("needs_reverse", false):
		return null

	# Stash the anchor's snap state so _commit() runs on drag-end; otherwise a group snap
	# moves transforms without ever committing the action.
	if _selected != anchor:
		_selected = anchor
		_pre_snap_transform = null
		_cache_sel_features = null
		_cache_sel_end_info = []
	if _pre_snap_transform == null:
		_pre_snap_transform = anchor.global_transform
	_snap_result = found.result
	_active_snap = true

	var result := proposed
	result.origin += snap_xform.origin - anchor_proposed.origin
	return result


static func _build_group_exclude_set() -> Dictionary:
	var out: Dictionary = {}
	var sel := EditorInterface.get_selection()
	if sel == null:
		return out
	for n in sel.get_top_selected_nodes():
		out[n] = true
	return out


static func _excludes_equal(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for k in a:
		if not b.has(k):
			return false
	return true


static func _get_active_anchor() -> Node3D:
	var sel := EditorInterface.get_selection()
	if sel == null:
		return null
	var top: Array[Node] = sel.get_top_selected_nodes()
	if top.is_empty():
		return null
	for n in top:
		if not (n is Node3D and _is_snappable(n as Node3D)):
			return null
	return top[-1] as Node3D


func _apply_live_reverse_flip() -> void:
	if _flip_locked:
		return
	_flip_locked = true
	if not _snap_result.get("needs_reverse", false):
		return
	var prop := ConveyorSnapping.get_reverse_property_name(_selected)
	if prop == &"":
		return
	if _pre_snap_reverse == null:
		_pre_snap_reverse = bool(_selected.get(prop))
	var target_value: bool = not bool(_pre_snap_reverse)
	if bool(_selected.get(prop)) != target_value:
		_selected.set(prop, target_value)


func _restore_pre_snap_reverse() -> void:
	_flip_locked = false
	if _pre_snap_reverse == null or not is_instance_valid(_selected):
		return
	var prop := ConveyorSnapping.get_reverse_property_name(_selected)
	if prop == &"":
		return
	if bool(_selected.get(prop)) != bool(_pre_snap_reverse):
		_selected.set(prop, bool(_pre_snap_reverse))


static func _should_skip_guards(selected: Node3D, result: Dictionary) -> bool:
	return (
		result.get("is_end_to_end", false)
		or ConveyorSnapping._is_chain_transfer(selected)
		or ConveyorSnapping._is_blade_stop(selected)
	)


func _commit() -> void:
	if not is_instance_valid(_selected) or not _selected.is_inside_tree() or _pre_snap_transform == null:
		return

	var found: Dictionary = _find_snap(_selected, _selected.global_transform)
	if found.is_empty():
		_restore_pre_snap_reverse()
		return

	var snap_result: Dictionary = found.result
	var skip_guards := _should_skip_guards(_selected, snap_result)
	var reverse_prop := ConveyorSnapping.get_reverse_property_name(_selected)
	var has_reverse_flip: bool = (
		_pre_snap_reverse != null
		and reverse_prop != &""
		and bool(_selected.get(reverse_prop)) != bool(_pre_snap_reverse)
	)
	if skip_guards and not has_reverse_flip:
		return

	var undo_redo := EditorInterface.get_editor_undo_redo()
	var is_diverter := ConveyorSnapping._is_diverter(_selected)
	var action_name := "Snap Conveyor"
	if ConveyorSnapping._is_sensor(_selected):
		action_name = "Snap Sensor to Side Guard"
	elif is_diverter:
		action_name = "Snap Diverter"
	_committing = true
	undo_redo.create_action(action_name)
	if not skip_guards:
		undo_redo.add_do_property(_selected, "global_transform", snap_result.transform)
		undo_redo.add_undo_property(_selected, "global_transform", _pre_snap_transform)
	if has_reverse_flip:
		undo_redo.add_do_property(_selected, reverse_prop, bool(_selected.get(reverse_prop)))
		undo_redo.add_undo_property(_selected, reverse_prop, bool(_pre_snap_reverse))
	var overrides: Dictionary = snap_result.get("property_overrides", {})
	for prop: String in overrides:
		var current: Variant = _selected.get(prop)
		if current is float and is_equal_approx(float(current), float(overrides[prop])):
			continue
		undo_redo.add_do_property(_selected, prop, overrides[prop])
		undo_redo.add_undo_property(_selected, prop, current)
	undo_redo.commit_action()
	_committing = false


static func _pick_snappable() -> Node3D:
	var selection := EditorInterface.get_selection()
	if selection == null:
		return null
	var found: Node3D = null
	for n in selection.get_selected_nodes():
		if n is Node3D and _is_snappable(n):
			if found != null:
				return null
			found = n
	return found


static func _is_snappable(node: Node3D) -> bool:
	return (
		ConveyorSnapping._is_diverter(node)
		or ConveyorSnapping._is_blade_stop(node)
		or ConveyorSnapping._is_chain_transfer(node)
		or ConveyorSnapping._is_sensor(node)
		or ConveyorSnapping._is_conveyor(node)
	)


static func _accepts_target(selected: Node3D, target: Node3D) -> bool:
	if target == selected:
		return false
	if not ConveyorSnapping._is_conveyor(target):
		return false
	var parent := target.get_parent() as Node3D
	if is_instance_valid(parent) and ConveyorSnapping._is_conveyor(parent):
		return false
	if ConveyorSnapping._is_chain_transfer(selected) or ConveyorSnapping._is_blade_stop(selected):
		return ConveyorSnapping._is_roller_conveyor(target)
	return true


func _find_snap(selected: Node3D, intent: Transform3D) -> Dictionary:
	if _candidate_cache.is_empty() or _candidate_cache_node != selected:
		_build_candidate_cache(selected)
		_candidate_cache_node = selected

	ConveyorSnapping.selected_xform_override = intent
	var on_top_attachment: bool = (
		ConveyorSnapping._is_blade_stop(selected)
		or ConveyorSnapping._is_chain_transfer(selected)
	)

	if _cache_sel_features == null:
		_cache_sel_features = ConveyorSnapFeatures._features_of(selected)
	var sel_features: Array = _cache_sel_features
	var sel_is_curved: bool = ConveyorSnapping._is_curved_conveyor(selected)
	var sel_has_spur: bool = ConveyorSnapping._has_spur_angles(selected)
	var sel_is_sensor: bool = ConveyorSnapping._is_sensor(selected)

	var sel_reach: float = 0.0
	if &"local_bbox" in selected:
		var bb: AABB = selected.get(&"local_bbox")
		if bb.size != Vector3.ZERO:
			sel_reach = maxf(
					maxf(absf(bb.position.x), absf(bb.end.x)),
					maxf(absf(bb.position.z), absf(bb.end.z)))
	if sel_reach == 0.0 and &"size" in selected:
		var sel_size: Vector3 = selected.size
		sel_reach = maxf(absf(sel_size.x), absf(sel_size.z)) * 0.5

	var best: Dictionary = {}
	var best_target: Node3D = null
	var best_dist := INF
	var best_is_override: bool = false
	for entry in _candidate_cache:
		var tgt: Node3D = entry.node
		if not is_instance_valid(tgt):
			continue
		if _xz_distance_to_target_box_cached(intent.origin, entry) > SEARCH_RADIUS + sel_reach:
			continue
		var override_threshold: bool = (
			not on_top_attachment
			and _selected_body_overlaps_target(intent, selected, entry)
		)
		if best_is_override and not override_threshold:
			continue
		ConveyorSnapping.target_xform_override = entry.xform
		var result: Dictionary
		if sel_is_sensor:
			result = ConveyorSnapFeatures.try_snap(
					selected, tgt, true, sel_features, _ensure_entry_features(entry))
		elif sel_is_curved or entry.is_curved:
			result = _select_curved_snap(intent, _ensure_entry_curved_pairs(entry, selected))
		elif sel_has_spur:
			result = ConveyorSnapping._calculate_spur_snap_transform(selected, tgt, true)
		elif entry.has_spur:
			result = ConveyorSnapping._calculate_snap_to_spur_target_transform(selected, tgt, true)
		else:
			result = ConveyorSnapFeatures.try_snap(
					selected, tgt, true, sel_features, _ensure_entry_features(entry))
		if result.is_empty():
			continue
		var snap_xform: Transform3D = result.transform
		var alignment: float = intent.basis.x.normalized().dot(snap_xform.basis.x.normalized())
		var rotation_penalty: float = (1.0 - alignment) * 2.0
		var rank_dist: float = intent.origin.distance_to(snap_xform.origin)
		var threshold: float = result.get("visible_threshold", VISIBLE_THRESHOLD)
		var preserves_facing: bool = alignment >= FACING_PRESERVED_DOT
		var gate_dist: float
		if override_threshold:
			gate_dist = rank_dist
		elif sel_is_sensor:
			gate_dist = _device_gate_distance(result, selected, intent, tgt, entry.xform)
		else:
			gate_dist = _snap_interface_xz_distance(result, selected, intent, tgt, entry.xform)
		if _DEBUG_SNAP and sel_is_sensor:
			print("[snap]   tgt=", tgt.name, " override=", override_threshold,
					" gate=", "%.3f" % gate_dist, " thr=", "%.3f" % threshold,
					" accepted=", override_threshold or gate_dist <= threshold)
		if not sel_is_sensor and not preserves_facing and gate_dist > VISIBLE_THRESHOLD:
			continue
		if not override_threshold and gate_dist > threshold:
			continue
		var dist: float = rank_dist + rotation_penalty
		if override_threshold and not best_is_override:
			best_is_override = true
			best_dist = INF
		if dist < best_dist:
			best_dist = dist
			best = result
			best_target = tgt

	ConveyorSnapping.selected_xform_override = null
	ConveyorSnapping.target_xform_override = null

	if best.is_empty():
		return {}
	return {"result": best, "target": best_target}


static func _local_bbox_corners(node: Node3D, fallback_size: Variant) -> Array:
	if node and &"local_bbox" in node:
		var bbox: AABB = node.get(&"local_bbox")
		if bbox.size != Vector3.ZERO:
			var p: Vector3 = bbox.position
			var e: Vector3 = bbox.end
			return [
				Vector3(p.x, 0, p.z),
				Vector3(e.x, 0, p.z),
				Vector3(p.x, 0, e.z),
				Vector3(e.x, 0, e.z),
			]
	if fallback_size != null:
		var s: Vector3 = fallback_size
		var hx: float = s.x * 0.5
		var hz: float = s.z * 0.5
		return [
			Vector3(-hx, 0, -hz),
			Vector3(hx, 0, -hz),
			Vector3(-hx, 0, hz),
			Vector3(hx, 0, hz),
		]
	return []


static func _visual_footprint_corners(selected: Node3D) -> Array:
	var min_x: float = INF
	var max_x: float = -INF
	var min_z: float = INF
	var max_z: float = -INF
	var found: bool = false
	var sel_inv: Transform3D = selected.global_transform.affine_inverse()
	var stack: Array[Node] = [selected]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for child: Node in n.get_children():
			stack.push_back(child)
		if n is VisualInstance3D:
			var vi: VisualInstance3D = n
			var aabb: AABB = vi.get_aabb()
			if aabb.size == Vector3.ZERO:
				continue
			var xf: Transform3D = sel_inv * vi.global_transform
			for i: int in range(8):
				var corner: Vector3 = xf * aabb.get_endpoint(i)
				min_x = minf(min_x, corner.x)
				max_x = maxf(max_x, corner.x)
				min_z = minf(min_z, corner.z)
				max_z = maxf(max_z, corner.z)
			found = true
	if not found:
		return []
	return [
		Vector3(min_x, 0.0, min_z),
		Vector3(max_x, 0.0, min_z),
		Vector3(min_x, 0.0, max_z),
		Vector3(max_x, 0.0, max_z),
	]


static func _selected_body_overlaps_target(intent: Transform3D, selected: Node3D, entry: Dictionary) -> bool:
	var tgt_corners: Array = _local_bbox_corners(entry.node, entry.size)
	if tgt_corners.is_empty():
		return false
	var tgt_xform: Transform3D = entry.xform
	var tgt_inv_basis: Basis = tgt_xform.basis.orthonormalized().transposed()
	var tgt_min_x: float = INF
	var tgt_max_x: float = -INF
	var tgt_min_z: float = INF
	var tgt_max_z: float = -INF
	for c: Vector3 in tgt_corners:
		tgt_min_x = minf(tgt_min_x, c.x)
		tgt_max_x = maxf(tgt_max_x, c.x)
		tgt_min_z = minf(tgt_min_z, c.z)
		tgt_max_z = maxf(tgt_max_z, c.z)

	var sel_size: Variant = selected.size if &"size" in selected else null
	var sel_corners: Array = _local_bbox_corners(selected, sel_size)
	if sel_corners.is_empty():
		sel_corners = _visual_footprint_corners(selected)
	if sel_corners.is_empty():
		var local: Vector3 = tgt_inv_basis * (intent.origin - tgt_xform.origin)
		return (local.x > tgt_min_x and local.x < tgt_max_x
				and local.z > tgt_min_z and local.z < tgt_max_z)

	var sel_min_x: float = INF
	var sel_max_x: float = -INF
	var sel_min_z: float = INF
	var sel_max_z: float = -INF
	for sc: Vector3 in sel_corners:
		var world_corner: Vector3 = intent * sc
		var local_corner: Vector3 = tgt_inv_basis * (world_corner - tgt_xform.origin)
		sel_min_x = minf(sel_min_x, local_corner.x)
		sel_max_x = maxf(sel_max_x, local_corner.x)
		sel_min_z = minf(sel_min_z, local_corner.z)
		sel_max_z = maxf(sel_max_z, local_corner.z)

	return (
		sel_min_x < tgt_max_x and sel_max_x > tgt_min_x
		and sel_min_z < tgt_max_z and sel_max_z > tgt_min_z
	)


func _build_candidate_cache(selected: Node3D) -> void:
	_candidate_cache.clear()
	ConveyorSnapping.live_type_cache.clear()
	ConveyorSnapping.live_end_info_cache.clear()
	_cache_sel_features = null
	_cache_sel_end_info = []
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return
	var nodes: Array[Node3D] = []
	_collect_candidates(root, selected, nodes, _candidate_excludes)
	_populate_node_caches(selected)
	_cache_sel_end_info = ConveyorSnapping._get_end_info(selected)
	for n in nodes:
		var size: Variant = n.size if &"size" in n else null
		var local_bbox: Variant = n.get(&"local_bbox") if &"local_bbox" in n else null
		var flags: Dictionary = _populate_node_caches(n)
		_candidate_cache.append({
			"node": n,
			"xform": n.global_transform,
			"size": size,
			"local_bbox": local_bbox,
			"is_curved": flags.is_curved,
			"has_spur": flags.has_spur,
		})


func _ensure_entry_features(entry: Dictionary) -> Array:
	if not entry.has("features"):
		entry["features"] = ConveyorSnapFeatures._features_of(entry.node)
	return entry["features"]


func _ensure_entry_curved_pairs(entry: Dictionary, selected: Node3D) -> Array:
	if not entry.has("curved_pairs"):
		entry["curved_pairs"] = _build_curved_snap_pairs(
				selected, entry.node, _cache_sel_end_info, entry.xform)
	return entry["curved_pairs"]


func _build_curved_snap_pairs(selected: Node3D, target: Node3D, sel_ends: Array, target_xform: Transform3D) -> Array:
	var tgt_ends: Array = ConveyorSnapping._get_end_info(target)
	var gap: float = ConveyorSnapping._get_snap_gap(selected, target)
	var sel_outputs: Array[bool] = []
	for se in sel_ends:
		sel_outputs.append(ConveyorSnapping._is_output_end(selected, se))
	var tgt_outputs: Array[bool] = []
	for te in tgt_ends:
		tgt_outputs.append(ConveyorSnapping._is_output_end(target, te))

	ConveyorSnapping.target_xform_override = target_xform
	var pairs: Array = []
	for se_idx in range(sel_ends.size()):
		var other_pos: Vector3 = sel_ends[1 - se_idx].pos
		for te_idx in range(tgt_ends.size()):
			var se: Dictionary = sel_ends[se_idx]
			var te: Dictionary = tgt_ends[te_idx]
			var snap_t: Transform3D = ConveyorSnapping._snap_end_to_end(selected, se, target, te, gap)
			pairs.append({
				"result": ConveyorSnapping._make_snap_result(snap_t, se, te),
				"other_sel_pos": other_pos,
				"free_end_after": snap_t * other_pos,
				"flow_compatible": sel_outputs[se_idx] != tgt_outputs[te_idx],
			})
	ConveyorSnapping.target_xform_override = null
	return pairs


static func _select_curved_snap(intent: Transform3D, pairs: Array) -> Dictionary:
	var best: Dictionary = {}
	var best_dist: float = INF
	var best_compatible: bool = false
	for p in pairs:
		var fe_before: Vector3 = intent * (p.other_sel_pos as Vector3)
		var d: float = fe_before.distance_squared_to(p.free_end_after)
		if d < best_dist:
			best_dist = d
			best = p.result
			best_compatible = p.flow_compatible
	if best.is_empty():
		return {}
	var result: Dictionary = best.duplicate()
	result["needs_reverse"] = not best_compatible
	return result


func _populate_node_caches(node: Node3D) -> Dictionary:
	var nid: int = node.get_instance_id()
	var flags: Dictionary = {
		"is_curved": ConveyorSnapping._is_curved_conveyor(node),
		"is_curved_roller": ConveyorSnapping._is_curved_roller_conveyor(node),
		"is_straight": ConveyorSnapping._is_straight_conveyor(node),
		"is_spur": ConveyorSnapping._is_spur_conveyor(node),
		"has_spur": ConveyorSnapping._has_spur_angles(node),
	}
	ConveyorSnapping.live_type_cache[nid] = flags
	ConveyorSnapping.live_end_info_cache[nid] = ConveyorSnapping._get_end_info(node)
	return flags


static func _xz_distance_to_target_box_cached(point: Vector3, entry: Dictionary) -> float:
	var xform: Transform3D = entry.xform
	var local: Vector3 = xform.basis.orthonormalized().transposed() * (point - xform.origin)
	var local_bbox: Variant = entry.get("local_bbox")
	if local_bbox is AABB and (local_bbox as AABB).size != Vector3.ZERO:
		var bb: AABB = local_bbox
		var clamped_x: float = clampf(local.x, bb.position.x, bb.end.x)
		var clamped_z: float = clampf(local.z, bb.position.z, bb.end.z)
		return Vector2(local.x - clamped_x, local.z - clamped_z).length()
	var size: Variant = entry.size
	if size == null:
		var d := xform.origin - point
		return Vector2(d.x, d.z).length()
	var half: Vector3 = (size as Vector3) * 0.5
	var clamped_x_c: float = clampf(local.x, -half.x, half.x)
	var clamped_z_c: float = clampf(local.z, -half.z, half.z)
	return Vector2(local.x - clamped_x_c, local.z - clamped_z_c).length()


static func _snap_interface_xz_distance(result: Dictionary, selected: Node3D, intent: Transform3D, target: Node3D, tgt_xform: Transform3D) -> float:
	var sel_end: Dictionary = result.get("snapped_end", {})
	var tgt_end: Dictionary = result.get("target_end", {})
	if not sel_end.has("pos") or not tgt_end.has("pos"):
		return _xz_distance(intent.origin, (result["transform"] as Transform3D).origin)

	if result.get("is_end_to_end", false):
		var sel_ends: Array = ConveyorSnapping._get_end_info(selected)
		var tgt_ends: Array = ConveyorSnapping._get_end_info(target)
		var min_dist: float = INF
		for se in sel_ends:
			var se_world: Vector3 = intent * (se.pos as Vector3)
			for te in tgt_ends:
				var te_world: Vector3 = tgt_xform * (te.pos as Vector3)
				var d: float = _xz_distance(se_world, te_world)
				if d < min_dist:
					min_dist = d
		return min_dist

	var sel_end_world: Vector3 = intent * (sel_end["pos"] as Vector3)
	var tgt_end_world: Vector3 = tgt_xform * (tgt_end["pos"] as Vector3)
	return _xz_distance(sel_end_world, tgt_end_world)


static func _device_gate_distance(result: Dictionary, selected: Node3D, intent: Transform3D, target: Node3D, tgt_xform: Transform3D) -> float:
	var interface_dist: float = _snap_interface_xz_distance(result, selected, intent, target, tgt_xform)
	var tgt_end: Dictionary = result.get("target_end", {})
	if not tgt_end.has("pos"):
		return interface_dist
	var contact_world: Vector3 = tgt_xform * (tgt_end["pos"] as Vector3)
	return minf(interface_dist, _xz_distance(intent.origin, contact_world))


static func _xz_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


static func _detect_floor_below(node: Node3D, origin: Vector3, exclude_rids: Array = []) -> Plane:
	var fallback := Plane(Vector3.UP, 0.0)
	if not node.is_inside_tree():
		return fallback
	var world := node.get_world_3d()
	if world == null or world.direct_space_state == null:
		return fallback
	var query := PhysicsRayQueryParameters3D.new()
	query.from = origin + Vector3.UP * 0.01
	query.to = origin + Vector3.DOWN * 100.0
	if not exclude_rids.is_empty():
		query.exclude = exclude_rids
	var hit := world.direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return fallback
	return Plane(hit.normal, hit.position)


static func _collect_collision_rids(node: Node, out: Array) -> void:
	if node is CollisionObject3D:
		out.append((node as CollisionObject3D).get_rid())
	for child in node.get_children():
		_collect_collision_rids(child, out)


static func _collect_candidates(node: Node, selected: Node3D, out: Array[Node3D], excludes: Dictionary = {}) -> void:
	if node == selected or excludes.has(node):
		return
	if node is Node3D and _accepts_target(selected, node):
		out.append(node)
	for child in node.get_children():
		_collect_candidates(child, selected, out, excludes)
