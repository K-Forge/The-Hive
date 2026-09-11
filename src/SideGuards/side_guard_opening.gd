@tool
class_name SideGuardOpening
extends Resource

## Single opening cut through a conveyor's side-guard rail. `arc_back` /
## `arc_front` are 1D parameters along the side-guard axis (see SideGuard).

const _DEFAULT_WIDTH: float = 1.0


@export var arc_back: float = 0.0:
	set(value):
		arc_back = value
		emit_changed()

@export var arc_front: float = 0.0:
	set(value):
		arc_front = value
		emit_changed()

## "left"/"right" for straight conveyors; "inner"/"outer" for curved.
@export_enum("left", "right", "inner", "outer") var side: String = "left":
	set(value):
		side = value
		emit_changed()

## Forces this arc range to stay guarded, carving back out of the geometry-derived (and
## other manual) openings. Use it where two parts touch but you don't want a transfer gap.
@export var subtract: bool = false:
	set(value):
		subtract = value
		emit_changed()


func _init() -> void:
	# Per-instance ownership so duplicated conveyors don't share opening Resources.
	resource_local_to_scene = true


func _validate_property(property: Dictionary) -> void:
	if property.name == "side":
		var curved_host: bool = get_meta(&"_curved_host", false)
		property.hint_string = "inner,outer" if curved_host else "left,right"


func _property_can_revert(property: StringName) -> bool:
	return property == &"side"


func _property_get_revert(property: StringName) -> Variant:
	# Revert to the host's first valid side, not the class default ("left"), so
	# reverting on a curved conveyor doesn't land on an invalid value.
	if property == &"side":
		var curved_host: bool = get_meta(&"_curved_host", false)
		return "inner" if curved_host else "left"
	return null


static func make(p_arc_back: float, p_arc_front: float, p_side: String) -> SideGuardOpening:
	var op := SideGuardOpening.new()
	op.arc_back = p_arc_back
	op.arc_front = p_arc_front
	op.side = p_side
	return op


## Merges openings on [param p_side] into non-overlapping ranges. [param manual] openings are
## guard-relative and shifted by [param manual_offset] into conveyor-arc; [param derived] are
## already in conveyor-arc. Manual openings flagged [member subtract] are removed from the
## union last, re-closing a stretch the geometry would otherwise open.
static func merge_openings_for_side(p_side: String, manual: Array, manual_offset: float, derived: Array) -> Array[Vector2]:
	var adds: Array[Vector2] = []
	var subs: Array[Vector2] = []
	for o: SideGuardOpening in manual:
		if o == null or o.side != p_side or o.arc_front <= o.arc_back:
			continue
		var r := Vector2(o.arc_back + manual_offset, o.arc_front + manual_offset)
		if o.subtract:
			subs.append(r)
		else:
			adds.append(r)
	for o: SideGuardOpening in derived:
		if o == null or o.side != p_side or o.arc_front <= o.arc_back:
			continue
		adds.append(Vector2(o.arc_back, o.arc_front))
	adds.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	var merged: Array[Vector2] = []
	for r: Vector2 in adds:
		if merged.is_empty() or r.x > merged[-1].y:
			merged.append(r)
		else:
			merged[-1] = Vector2(merged[-1].x, maxf(merged[-1].y, r.y))
	if subs.is_empty():
		return merged
	return _subtract_ranges(merged, subs)


## Removes every [param subs] span from [param adds], splitting a range when a subtraction lands mid-range.
static func _subtract_ranges(adds: Array[Vector2], subs: Array[Vector2]) -> Array[Vector2]:
	var result: Array[Vector2] = adds
	for sub: Vector2 in subs:
		var next: Array[Vector2] = []
		for r: Vector2 in result:
			if sub.y <= r.x or sub.x >= r.y:
				next.append(r)
				continue
			if sub.x > r.x:
				next.append(Vector2(r.x, sub.x))
			if sub.y < r.y:
				next.append(Vector2(sub.y, r.y))
		result = next
	return result


## Replaces nulls (from inspector "Add Element") with fresh instances and wires [param callback]
## to each opening's [signal Resource.changed] so inspector edits trigger the conveyor's rebuild.
static func sync_change_listeners(old_array: Array, new_array: Array, callback: Callable, curved: bool = false, default_arc: Vector2 = Vector2(NAN, NAN)) -> void:
	for op: SideGuardOpening in old_array:
		if op != null and op.changed.is_connected(callback):
			op.changed.disconnect(callback)
	for i in range(new_array.size()):
		# "New" = inserted by inspector Add Element, whether as null or a fresh
		# default instance (Godot does either depending on version).
		var is_new: bool = new_array[i] == null or not old_array.has(new_array[i])
		if new_array[i] == null:
			new_array[i] = SideGuardOpening.new()
		var op: SideGuardOpening = new_array[i]
		op.set_meta(&"_curved_host", curved)
		if is_new:
			# Default a fresh opening to the host's valid side and a modest span at the guard start.
			if curved and op.side == "left":
				op.side = "inner"
			if not is_nan(default_arc.x) and op.arc_front <= op.arc_back:
				op.arc_back = default_arc.x
				op.arc_front = minf(default_arc.x + _DEFAULT_WIDTH, default_arc.y)
		if not op.changed.is_connected(callback):
			op.changed.connect(callback)


## Deep-duplicates openings whose owner doesn't match `owner_id` (unbreaks duplicated conveyors).
static func claim_unique(openings: Array[SideGuardOpening], owner_id: int) -> void:
	const META: StringName = &"_owner_id"
	for i in range(openings.size()):
		var op: SideGuardOpening = openings[i]
		if op == null:
			continue
		var existing_id: int = op.get_meta(META, 0)
		if existing_id == 0 or existing_id == owner_id:
			op.set_meta(META, owner_id)
			op.resource_local_to_scene = true
		else:
			var dup := op.duplicate(true) as SideGuardOpening
			dup.set_meta(META, owner_id)
			dup.resource_local_to_scene = true
			openings[i] = dup
