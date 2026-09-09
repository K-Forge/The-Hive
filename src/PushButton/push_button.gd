@tool
class_name PushButton
extends Node3D

## Text label displayed on the button.
@export var text: String = "STOP":
	set(value):
		text = value
		if _text:
			_text.text = text

## When true, button stays pressed until clicked again (toggle mode).
@export var toggle: bool = false:
	set(value):
		toggle = value
		if not toggle:
			pressed = false

## When true, output is inverted (false when pressed).
@export var normally_closed: bool = false:
	set(value):
		normally_closed = value
		_update_output()

## Current pressed state of the button.
@export var pressed: bool = false:
	set(value):
		pressed = value
		_update_output()
		
		if not toggle and pressed:
			_reset_pushbutton()
			var tween := create_tween()
			tween.tween_property(_button_mesh, "position", Vector3(0, 0, _button_pressed_z_pos), 0.035)
			tween.tween_interval(0.2)
			tween.tween_property(_button_mesh, "position", Vector3.ZERO, 0.02)
		elif _button_mesh:
			if pressed:
				_button_mesh.position = Vector3(0, 0, _button_pressed_z_pos)
			else:
				_button_mesh.position = Vector3.ZERO

## Final output signal after applying normally_closed logic (read-only).
@export var output: bool = false:
	set(value):
		if _pushbutton_tag.is_ready() and value != output:
			_pushbutton_tag.write_bit(value)
		output = value

## When true, the button illuminates (lamp indicator).
@export var lamp: bool = false:
	set(value):
		lamp = value
		if _button_mesh:
			_ensure_unique_material()
			var mat := _button_mesh.get_surface_override_material(0)
			if value:
				mat.emission_energy_multiplier = 1.0
			else:
				mat.emission_energy_multiplier = 0.0

## Color of the button and its lamp emission.
@export var button_color: Color = Color.RED:
	set(value):
		button_color = value
		if _button_mesh:
			_ensure_unique_material()
			var mat := _button_mesh.get_surface_override_material(0)
			mat.albedo_color = value
			mat.emission = value

var _button_pressed_z_pos: float = -0.04
var _pushbutton_tag := OIPCommsTag.new()
var _lamp_tag := OIPCommsTag.new()
var _material_made_unique: bool = false

@onready var _text: Label3D = $Text
@onready var _button_mesh: MeshInstance3D = $Meshes/Button

@export_category("Communications")
## Enable communication with external PLC/control systems.
@export var enable_comms: bool = false
@export var pushbutton_tag_group_name: String
## The tag group for writing button output state.
@export_custom(0, "tag_group_enum") var pushbutton_tag_groups: String:
	set(value):
		pushbutton_tag_group_name = value
		pushbutton_tag_groups = value
## The tag name for the button output in the selected tag group.[br]Datatype: [code]BOOL[/code][br][br]Format varies by protocol:[br][b]EIP:[/b] CIP tag names[br][b]Modbus:[/b] prefix+number (e.g. [code]co0[/code])[br][b]OPC UA:[/b] full NodeId (e.g. [code]ns=2;s=MyVariable[/code] or [code]ns=2;i=12345[/code]).
@export var pushbutton_tag_name: String = ""
@export var lamp_tag_group_name: String
## The tag group for reading lamp control signals.
@export_custom(0, "tag_group_enum") var lamp_tag_groups: String:
	set(value):
		lamp_tag_group_name = value
		lamp_tag_groups = value
## The tag name for the lamp control in the selected tag group.[br]Datatype: [code]BOOL[/code][br][br]Format varies by protocol:[br][b]EIP:[/b] CIP tag names[br][b]Modbus:[/b] prefix+number (e.g. [code]co0[/code])[br][b]OPC UA:[/b] full NodeId (e.g. [code]ns=2;s=MyVariable[/code] or [code]ns=2;i=12345[/code]).
@export var lamp_tag_name: String = ""


func _validate_property(property: Dictionary) -> void:
	if property.name == "output":
		property.usage = PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY
	elif not OIPCommsSetup.validate_tag_property(property, "pushbutton_tag_group_name", "pushbutton_tag_groups", "pushbutton_tag_name"):
		OIPCommsSetup.validate_tag_property(property, "lamp_tag_group_name", "lamp_tag_groups", "lamp_tag_name")


func _enter_tree() -> void:
	pushbutton_tag_group_name = OIPCommsSetup.default_tag_group(pushbutton_tag_group_name)
	lamp_tag_group_name = OIPCommsSetup.default_tag_group(lamp_tag_group_name)
	Simulation.started.connect(_on_simulation_started)
	OIPCommsSetup.connect_comms(self, _tag_group_initialized, _tag_group_polled)


func _ready() -> void:
	_text.text = text
	button_color = button_color
	lamp = lamp


func _ensure_unique_material() -> void:
	if not _button_mesh or _material_made_unique:
		return
		
	var current_override := _button_mesh.get_surface_override_material(0)
	if current_override:
		var unique_mat := current_override.duplicate() as Material
		_button_mesh.set_surface_override_material(0, unique_mat)
	else:
		var mat: StandardMaterial3D = _button_mesh.mesh.surface_get_material(0).duplicate()
		_button_mesh.set_surface_override_material(0, mat)
	
	_material_made_unique = true


func _exit_tree() -> void:
	Simulation.started.disconnect(_on_simulation_started)
	OIPCommsSetup.disconnect_comms(self, _tag_group_initialized, _tag_group_polled)


func use() -> void:
	pressed = not pressed


func _reset_pushbutton() -> void:
	await get_tree().create_timer(0.3).timeout
	pressed = false


func _update_output() -> void:
	var new_output := pressed
	if normally_closed:
		new_output = !pressed
	output = new_output


func _on_simulation_started() -> void:
	if enable_comms:
		_pushbutton_tag.register(pushbutton_tag_group_name, pushbutton_tag_name, OIPComms.TAG_TYPE_BOOL)
		_lamp_tag.register(lamp_tag_group_name, lamp_tag_name, OIPComms.TAG_TYPE_BOOL)


func _tag_group_initialized(tag_group_name_param: String) -> void:
	if _pushbutton_tag.on_group_initialized(tag_group_name_param):
		_pushbutton_tag.write_bit(output)
	_lamp_tag.on_group_initialized(tag_group_name_param)


func _tag_group_polled(tag_group_name_param: String) -> void:
	if not enable_comms:
		return

	if _lamp_tag.matches_group(tag_group_name_param):
		lamp = _lamp_tag.read_bit()
