@tool
class_name StackSegmentData
extends Resource

signal active_changed(value: bool)
signal color_changed(value: Color)

## When true, the segment light is illuminated.
@export var active: bool = false:
	set(value):
		active = value
		active_changed.emit(active)

## The color of this light segment when active.
@export var segment_color: Color = Color(0.0, 1.0, 0.0, 0.5):
	set(value):
		segment_color = value
		color_changed.emit(segment_color)
