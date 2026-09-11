@tool
class_name GenericData
extends Node

enum Datatype {
	BOOL,
	FLOAT,
	DOUBLE,
	INT
}

@export var data_type: Datatype = Datatype.BOOL:
	set(value):
		data_type = value
		match data_type:
			Datatype.FLOAT:
				tag_value = 0.0
			Datatype.DOUBLE, Datatype.INT:
				tag_value = 0
			Datatype.BOOL:
				tag_value = false

@export var tag_value: Variant:
	set(value):
		if is_same(value, tag_value):
			return
		tag_value = value
		if _tag.is_ready():
			match data_type:
				Datatype.BOOL:
					_tag.write_bit(value)
				Datatype.FLOAT:
					_tag.write_float32(value)
				Datatype.DOUBLE:
					_tag.write_float64(value)
				Datatype.INT:
					_tag.write_int32(value)

var _tag := OIPCommsTag.new()
@export_category("Communications")
@export var enable_comms: bool = false
@export var tag_group_name: String
@export_custom(0, "tag_group_enum") var tag_groups: String:
	set(value):
		tag_group_name = value
		tag_groups = value
## The tag name in the selected tag group.[br]Datatype: matches the selected [code]data_type[/code][br][br]Format varies by protocol:[br][b]EIP:[/b] CIP tag names[br][b]Modbus:[/b] prefix+number (e.g. [code]hr0[/code])[br][b]OPC UA:[/b] full NodeId (e.g. [code]ns=2;s=MyVariable[/code] or [code]ns=2;i=12345[/code]).
@export var tag_name: String = ""
@export var setup: bool = false


func _enter_tree() -> void:
	if not setup:
		tag_value = false
		setup = true

	tag_group_name = OIPCommsSetup.default_tag_group(tag_group_name)
	Simulation.started.connect(_on_simulation_started)
	OIPCommsSetup.connect_comms(self, _tag_group_initialized, _tag_group_polled)


func _exit_tree() -> void:
	Simulation.started.disconnect(_on_simulation_started)
	OIPCommsSetup.disconnect_comms(self, _tag_group_initialized, _tag_group_polled)


func _validate_property(property: Dictionary) -> void:
	if property.name == "setup":
		property.usage = PROPERTY_USAGE_STORAGE
	else:
		OIPCommsSetup.validate_tag_property(property)


func _property_can_revert(property: StringName) -> bool:
	return property == "tag_value"


func _property_get_revert(property: StringName) -> Variant:
	if property == "tag_value":
		return tag_value
	else:
		return null


func _on_simulation_started() -> void:
	if enable_comms:
		_tag.register(tag_group_name, tag_name, _oip_data_type())


# Maps the editor-facing Datatype to the OIPComms tag type so modbus_tcp sizes
# the register span correctly (FLOAT32/INT32 = 2 registers, FLOAT64 = 4).
func _oip_data_type() -> int:
	match data_type:
		Datatype.FLOAT:
			return OIPComms.TAG_TYPE_FLOAT32
		Datatype.DOUBLE:
			return OIPComms.TAG_TYPE_FLOAT64
		Datatype.INT:
			return OIPComms.TAG_TYPE_INT32
		_:
			return OIPComms.TAG_TYPE_BOOL


func _tag_group_initialized(group: String) -> void:
	_tag.on_group_initialized(group)


func _tag_group_polled(group: String) -> void:
	if not enable_comms or not _tag.matches_group(group):
		return
	var converted: Variant
	match data_type:
		Datatype.BOOL:
			converted = _tag.read_bit()
		Datatype.FLOAT:
			converted = _tag.read_float32()
		Datatype.DOUBLE:
			converted = _tag.read_float64()
		Datatype.INT:
			converted = _tag.read_int32()
	tag_value = converted
