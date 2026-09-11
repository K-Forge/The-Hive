@tool
class_name StackLightData
extends Resource

var segments: int = 0
var segment_data: StackSegmentData = load("res://src/StackLight/StackSegmentData.tres")

## Array of segment data resources, one for each light in the stack.
@export var segment_datas: Array = []


func init_segments(count: int) -> void:
	var old_datas := segment_datas
	segment_datas = []
	segment_datas.resize(count)
	segments = count
	
	for i in range(count):
		if old_datas != null and i < old_datas.size() and old_datas[i] is StackSegmentData:
			segment_datas[i] = old_datas[i].duplicate(true)
		else:
			segment_datas[i] = segment_data.duplicate(true)


func set_segments(count: int) -> void:
	if count == segments:
		return
	
	var old_datas := segment_datas
	segment_datas = []
	segment_datas.resize(count)
	var old_count := segments
	segments = count
	
	for i in range(count):
		if i < old_count and old_datas[i] is StackSegmentData:
			segment_datas[i] = old_datas[i]
		else:
			segment_datas[i] = segment_data.duplicate(true)
