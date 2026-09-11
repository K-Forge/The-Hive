@tool
class_name BuildingWallRule
extends Resource

enum Wall { A, B, C, D, DOCK_DOOR }

## Which wall this rule paints where it matches.
@export var wall: Wall = Wall.B:
	set(value):
		wall = value
		notify_property_list_changed()
		emit_changed()

## Consecutive segments painted per run.
@export_range(1, 400, 1) var run: int = 1:
	set(value):
		run = value
		emit_changed()

## Segments skipped between runs. 0 = solid.
@export_range(0, 400, 1) var gap: int = 1:
	set(value):
		gap = value
		emit_changed()

## Number of runs to paint. 0 = unlimited (tile the whole perimeter).
@export_range(0, 100, 1) var count: int = 0:
	set(value):
		count = value
		notify_property_list_changed()
		emit_changed()

## Perimeter index where the first run begins.
@export_range(0, 400, 1) var start: int = 0:
	set(value):
		start = value
		emit_changed()

@export_group("Dock Door")

## Number of door openings per painted dock-door segment (only when wall is DOCK_DOOR).
@export_range(1, 2) var door_count: int = 1:
	set(value):
		door_count = value
		emit_changed()

## Width of each door aperture.
@export var opening_width: float = 4.0:
	set(value):
		opening_width = value
		emit_changed()

## Height of each door aperture.
@export var opening_height: float = 4.5:
	set(value):
		opening_height = value
		emit_changed()

@export var trailer: bool = true:
	set(value):
		trailer = value
		emit_changed()


func _validate_property(property: Dictionary) -> void:
	if property.name == "gap" and count == 1:
		property.usage &= ~PROPERTY_USAGE_EDITOR
	if wall != Wall.DOCK_DOOR and property.name in [
		"door_count", "opening_width", "opening_height", "trailer",
	]:
		property.usage &= ~PROPERTY_USAGE_EDITOR


func matches(perimeter_index: int, perimeter_length: int) -> bool:
	if run <= 0 or perimeter_length <= 0:
		return false

	var rel := posmod(perimeter_index - start, perimeter_length)
	if count > 0 and rel >= count * run + (count - 1) * gap:
		return false

	return posmod(rel, run + gap) < run
