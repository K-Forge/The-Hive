@tool
extends Node

## Compatibility shim for the "OIPComms" global (industrial protocol tag
## read/write) provided natively by OIP's custom Godot fork / the oip_comms
## GDExtension. Neither is available on this Linux install (no .so shipped
## for this platform in this checkout), so this no-op stub exists purely to
## let part scripts compile and run with comms disabled (the default).
## It does not talk to any real PLC/protocol — enabling "Enable Comms" on a
## part will not actually communicate with anything while this stub is active.

const TAG_TYPE_BOOL := 0
const TAG_TYPE_UINT8 := 1
const TAG_TYPE_INT16 := 2
const TAG_TYPE_INT32 := 3
const TAG_TYPE_FLOAT32 := 4
const TAG_TYPE_FLOAT64 := 5

signal comms_error
signal enable_comms_changed
signal tag_group_initialized(group_name: String)
signal tag_group_polled(group_name: String)
signal tag_groups_registered

var _enable_comms := false
var _tag_groups: Array[String] = []


func get_enable_comms() -> bool:
	return _enable_comms


func set_enable_comms(value: bool) -> void:
	if _enable_comms == value:
		return
	_enable_comms = value
	enable_comms_changed.emit()


func get_comms_error() -> String:
	return ""


func set_enable_log(_value: bool) -> void:
	pass


func set_sim_running(_value: bool) -> void:
	pass


func clear_tag_groups() -> void:
	_tag_groups.clear()


func get_tag_groups() -> Array:
	return _tag_groups.duplicate()


func register_tag_group(group_name: String, _polling_rate: int, _protocol: String, _gateway: String, _path: String, _cpu: String) -> void:
	if not _tag_groups.has(group_name):
		_tag_groups.append(group_name)


func register_tag(_group: String, _tag: String, _data_type: int) -> bool:
	return false


func read_bit(_group: String, _tag: String) -> bool:
	return false


func write_bit(_group: String, _tag: String, _value: bool) -> void:
	pass


func read_float32(_group: String, _tag: String) -> float:
	return 0.0


func write_float32(_group: String, _tag: String, _value: float) -> void:
	pass


func read_float64(_group: String, _tag: String) -> float:
	return 0.0


func write_float64(_group: String, _tag: String, _value: float) -> void:
	pass


func read_int16(_group: String, _tag: String) -> int:
	return 0


func write_int16(_group: String, _tag: String, _value: int) -> void:
	pass


func read_int32(_group: String, _tag: String) -> int:
	return 0


func write_int32(_group: String, _tag: String, _value: int) -> void:
	pass


func read_uint8(_group: String, _tag: String) -> int:
	return 0


func write_uint8(_group: String, _tag: String, _value: int) -> void:
	pass


func compile_soft_plc(_group: String, _code: String) -> String:
	return ""


func set_soft_plc_program(_group: String, _src: String) -> void:
	pass


func set_soft_plc_watch_enabled(_group: String, _enabled: bool) -> void:
	pass


func get_soft_plc_watch(_group: String) -> Dictionary:
	return {}
