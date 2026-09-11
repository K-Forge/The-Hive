@tool
class_name BeltSegment
extends Resource

## One straight run in a path-based belt conveyor; chained tangent-to-tangent via fillet arcs.


func _init() -> void:
	# Per-instance copy so editing one conveyor's segment doesn't leak across scenes.
	resource_local_to_scene = true

## Nominal length, before tangent-fillet inset is deducted.
@export_custom(PROPERTY_HINT_NONE, "suffix:m") var length: float = 4.0:
	set(value):
		if value == length:
			return
		length = value
		emit_changed()

## Tilt relative to the previous segment (or path base for segment 0). Rotates around +Z.
@export_range(-89.0, 89.0, 0.1, "suffix:°") var tilt_relative_deg: float = 0.0:
	set(value):
		if value == tilt_relative_deg:
			return
		tilt_relative_deg = value
		emit_changed()
