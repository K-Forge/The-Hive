@tool
extends EditorPlugin

var tag_group_enum: TagGroupOptionButtonPlugin = TagGroupOptionButtonPlugin.new()

func _enter_tree() -> void:
	add_inspector_plugin(tag_group_enum)


func _exit_tree() -> void:
	remove_inspector_plugin(tag_group_enum)

class TagGroupOptionButtonPlugin extends EditorInspectorPlugin:
	func _can_handle(object: Object) -> bool:
		return true
	
	func _parse_property(object: Object, type: Variant.Type, name: String, hint_type: PropertyHint, hint_string: String, usage_flags: int, wide: bool) -> bool:
		if hint_string == "tag_group_enum" and type in [TYPE_NIL, TYPE_STRING]:
			add_property_editor(name, TagGroupOptionButton.new())
			return true
		return false
		
class TagGroupOptionButton extends EditorProperty:
	var option_button: OptionButton
	
	func _init() -> void:
		option_button = OptionButton.new()
		option_button.flat = true
		option_button.allow_reselect = true
		add_child(option_button)
		_populate_options()
		option_button.item_selected.connect(_on_item_selected)
		OIPComms.tag_groups_registered.connect(_tag_groups_registered)
	
	func _on_item_selected(index: int) -> void:
		if index < 0 or index >= option_button.item_count:
			return
		var value := option_button.get_item_text(index)
		if value.begins_with("⚠️ "):
			value = value.substr(3)
		var storage_prop := get_edited_property().replace("tag_groups", "tag_group_name")
		emit_changed(storage_prop, value)
	
	func _populate_options() -> void:
		option_button.clear()
		var groups := OIPComms.get_tag_groups()
		for group in groups:
			option_button.add_item(group)
		option_button.disabled = groups.is_empty()
	
	func _select_current_value() -> void:
		var obj := get_edited_object()
		if obj == null:
			return
		var storage_prop := get_edited_property().replace("tag_groups", "tag_group_name")
		var current_value: Variant = obj.get(storage_prop)
		if current_value == null or not current_value is String or current_value.is_empty():
			option_button.select(-1)
			option_button.text = "(None)"
			return
		var groups := OIPComms.get_tag_groups()
		for i in range(groups.size()):
			if groups[i] == current_value:
				option_button.select(i)
				return
		option_button.add_item("⚠️ " + current_value)
		var stale_index := option_button.item_count - 1
		option_button.set_item_disabled(stale_index, true)
		option_button.select(stale_index)
	
	func _update_property() -> void:
		_select_current_value()
	
	func _tag_groups_registered() -> void:
		_populate_options()
		_select_current_value()
				
