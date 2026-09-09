@tool

# TBD -> figure out how to programmatically disable these classes from editor
# end user does not need to see them
# https://forum.godotengine.org/t/how-to-exclude-custom-classes-from-the-create-new-node-menu/51269/9
# right now the type hints are useful
class_name _OIPCommsDock
extends Control

signal save_changes(value: bool)

const TAG_GROUPS_FILE := "res://oip_data/tag_groups.cfg"
const SETTINGS_FILE := "res://oip_data/comms_settings.cfg"
const TAG_GROUP = preload("res://addons/oip_comms/controls/tag_group.tscn")
const _SERVICE_SCRIPT: GDScript = preload("res://src/comms/oip_comms_service.gd")

@onready var v_box_container: VBoxContainer = $Layout/ScrollContainer/TagGroupList
@onready var enable_comms: CheckBox = $Layout/Toolbar/EnableComms
@onready var enable_logging: CheckBox = $Layout/Toolbar/EnableLogging
@onready var save_comms_button: Button = $"Layout/Toolbar/Save Changes"


var tag_groups_data: Array = []
var last_tag_groups_data: Array = []
var changes_present := false
var settings_config: ConfigFile = ConfigFile.new()
var tag_groups_config: ConfigFile = ConfigFile.new()
var _service: Node

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute("res://oip_data")
	load_tag_groups_data()
	load_tag_groups_ui()
	load_settings()

	_service = _SERVICE_SCRIPT.new()
	add_child(_service)
	_service.bootstrap()

	last_tag_groups_data = tag_groups_data.duplicate(true)

	OIPComms.comms_error.connect(_on_comms_error)

	if is_instance_valid(save_comms_button):
		save_comms_button.pressed.connect(_on_save_comms_button_pressed)
		save_comms_button.disabled = true

func load_tag_groups_data() -> void:
	tag_groups_data = []

	var error = tag_groups_config.load(TAG_GROUPS_FILE)
	if error == OK:
		var group_count = tag_groups_config.get_value("info", "group_count", 0)

		for i in range(group_count):
			var group_section = "group_" + str(i)
			var group_data = {
				"name": tag_groups_config.get_value(group_section, "name", "TagGroup" + str(i)),
				"polling_rate": tag_groups_config.get_value(group_section, "polling_rate", "100"),
				"protocol": tag_groups_config.get_value(group_section, "protocol", "0"),
				"gateway": tag_groups_config.get_value(group_section, "gateway", "localhost"),
				"path": tag_groups_config.get_value(group_section, "path", "1,0"),
				"cpu": tag_groups_config.get_value(group_section, "cpu", "ControlLogix"),
				"saved": true
			}
			tag_groups_data.append(group_data)

func load_settings() -> void:
	var error = settings_config.load(SETTINGS_FILE)

	if error == OK:
		enable_comms.button_pressed = settings_config.get_value("settings", "enable_comms", false)
		#TODO a bug is making this always false.
		#enable_logging.button_pressed = settings_config.get_value("settings", "enable_logging", false)

func load_tag_groups_ui() -> void:
	for tag_group: _OIPCommsTagGroup in v_box_container.get_children():
		tag_group.queue_free()

	for tag_group_data: Dictionary in tag_groups_data:
		var tag_group := TAG_GROUP.instantiate()
		tag_group.save_data = tag_group_data.duplicate()
		tag_group.tag_group_delete.connect(tag_group_delete)
		tag_group.tag_group_save.connect(tag_group_save)
		v_box_container.add_child(tag_group)

func tag_group_save(_t: _OIPCommsTagGroup) -> void:
	save_tag_groups_ui()
	mark_changes_present()

func _has_duplicate_names() -> bool:
	var names: Array[String] = []
	for tag_group_data: Dictionary in tag_groups_data:
		var n: String = tag_group_data.name
		if n in names:
			return true
		names.append(n)
	return false

func save_all() -> void:
	save_tag_groups_ui()

	if _has_duplicate_names():
		var dialog := AcceptDialog.new()
		dialog.title = "OIP Comms"
		dialog.dialog_text = "Duplicate tag group names found. Please rename before saving."
		add_child(dialog)
		dialog.popup_centered()
		dialog.confirmed.connect(dialog.queue_free)
		dialog.canceled.connect(dialog.queue_free)
		return

	changes_present = false
	save_changes.emit(changes_present)

	if is_instance_valid(save_comms_button):
		save_comms_button.disabled = true

	var buffer_tag_groups_data := tag_groups_data.duplicate(true)

	if last_tag_groups_data.hash() != tag_groups_data.hash():
		save_tag_groups_data()
		print("OIP Comms: Tag group data saved")

	save_settings()
	last_tag_groups_data = buffer_tag_groups_data

	for tag_group_data: Dictionary in tag_groups_data:
		tag_group_data["saved"] = true
	for tag_group: _OIPCommsTagGroup in v_box_container.get_children():
		tag_group.lock_name()

	_service.register_tag_groups()

func save_tag_groups_ui() -> void:
	tag_groups_data = []
	for tag_group: _OIPCommsTagGroup in v_box_container.get_children():
		tag_group.save()
		tag_groups_data.push_back(tag_group.save_data)

func save_tag_groups_data() -> void:
	tag_groups_config.clear()

	tag_groups_config.set_value("info", "group_count", tag_groups_data.size())

	for i in range(tag_groups_data.size()):
		var group_data = tag_groups_data[i]
		var group_section = "group_" + str(i)

		tag_groups_config.set_value(group_section, "name", group_data.name)
		tag_groups_config.set_value(group_section, "polling_rate", group_data.polling_rate)
		tag_groups_config.set_value(group_section, "protocol", group_data.protocol)
		tag_groups_config.set_value(group_section, "gateway", group_data.gateway)
		tag_groups_config.set_value(group_section, "path", group_data.path)
		tag_groups_config.set_value(group_section, "cpu", group_data.cpu)

	tag_groups_config.save(TAG_GROUPS_FILE)

func tag_group_delete(t: _OIPCommsTagGroup) -> void:
	var index := -1

	var i := 0
	for tag_group: _OIPCommsTagGroup in v_box_container.get_children():
		if tag_group == t:
			index = i
			break
		i += 1

	if index != -1:
		tag_groups_data.remove_at(index)
		t.queue_free()
		mark_changes_present()

func _on_AddTagGroup_pressed() -> void:
	var _name := "TagGroup" + str(len(tag_groups_data))
	tag_groups_data.push_back({
		"name": _name, "polling_rate": "100", "protocol": "0",
		"gateway": "localhost", "path": "1,0", "cpu": "ControlLogix"
	})
	load_tag_groups_ui()
	mark_changes_present()

func _on_EnableComms_toggled(toggled_on: bool) -> void:
	OIPComms.set_enable_comms(toggled_on)
	OIPComms.enable_comms_changed.emit()
	save_settings()

func _on_EnableLogging_toggled(toggled_on: bool) -> void:
	OIPComms.set_enable_log(toggled_on)
	save_settings()

func _on_comms_error() -> void:
	_show_comms_error.call_deferred()

func _show_comms_error() -> void:
	var msg: String = OIPComms.get_comms_error()
	var dialog := AcceptDialog.new()
	dialog.title = "OIP Comms Error"
	dialog.dialog_text = msg
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()

func save_settings() -> void:
	settings_config.set_value("settings", "enable_comms", enable_comms.button_pressed)
	settings_config.set_value("settings", "enable_logging", enable_logging.button_pressed)
	settings_config.save(SETTINGS_FILE)

func _on_save_comms_button_pressed() -> void:
	save_all()

func mark_changes_present() -> void:
	if not changes_present:
		changes_present = true
		save_changes.emit(changes_present)
		if is_instance_valid(save_comms_button):
			save_comms_button.disabled = false
