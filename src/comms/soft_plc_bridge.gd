@tool
extends Node

const SOFT_PLC_GROUP := "ST"
const TAG_GROUPS_FILE := "res://oip_data/tag_groups.cfg"


func _ready() -> void:
	if not OIPComms.tag_group_initialized.is_connected(_on_tag_group_initialized):
		OIPComms.tag_group_initialized.connect(_on_tag_group_initialized)
	if Engine.is_editor_hint():
		_register_soft_plc_groups()
		if not Simulation.started.is_connected(_on_started):
			Simulation.started.connect(_on_started)
		if not Simulation.stopped.is_connected(_on_stopped):
			Simulation.stopped.connect(_on_stopped)


func _on_started() -> void:
	OIPComms.set_sim_running(true)


func _on_stopped() -> void:
	OIPComms.set_sim_running(false)


func _on_tag_group_initialized(group_name: String) -> void:
	if group_name != SOFT_PLC_GROUP:
		return
	var root: Node = _scene_root()
	if root == null:
		push_warning("SoftPlcBridge: no scene root when '%s' initialized" % group_name)
		return
	if not root.has_meta("oip_st_program"):
		push_warning("SoftPlcBridge: scene root '%s' has no 'oip_st_program' metadata — nothing to run" % root.name)
		return
	var src := String(root.get_meta("oip_st_program"))
	print("SoftPlcBridge: feeding ST program (%d chars) to soft_plc group '%s'" % [src.length(), group_name])
	OIPComms.set_soft_plc_program(SOFT_PLC_GROUP, src)


func _scene_root() -> Node:
	if Engine.is_editor_hint() and Engine.has_singleton("EditorInterface"):
		var editor: Object = Engine.get_singleton("EditorInterface")
		return editor.get_edited_scene_root() as Node
	return get_tree().current_scene


func _register_soft_plc_groups() -> void:
	var config := ConfigFile.new()
	if config.load(TAG_GROUPS_FILE) != OK:
		return
	var count := int(config.get_value("info", "group_count", 0))
	for i: int in range(count):
		var section := "group_" + str(i)
		if str(config.get_value(section, "protocol", "0")) != "7":
			continue
		OIPComms.register_tag_group(
			str(config.get_value(section, "name", SOFT_PLC_GROUP)),
			int(config.get_value(section, "polling_rate", "100")),
			"soft_plc",
			str(config.get_value(section, "gateway", "res://oip-plc.js")),
			str(config.get_value(section, "path", "")),
			str(config.get_value(section, "cpu", "")))
