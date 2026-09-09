class_name OIPCommsSetup


static func validate_tag_property(
	property: Dictionary,
	group_name: String = "tag_group_name",
	groups: String = "tag_groups",
	tag: String = "tag_name"
) -> bool:
	var comms_enabled := OIPComms.get_enable_comms()

	if property.name == "Communications" and property.usage & PROPERTY_USAGE_CATEGORY:
		property.usage = PROPERTY_USAGE_CATEGORY if comms_enabled else PROPERTY_USAGE_NONE
		return true
	elif property.name == "enable_comms":
		property.usage = PROPERTY_USAGE_DEFAULT if comms_enabled else PROPERTY_USAGE_STORAGE
		return true
	elif property.name == group_name:
		property.usage = PROPERTY_USAGE_STORAGE
		return true
	elif property.name == groups:
		property.usage = PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_NO_INSTANCE_STATE if comms_enabled else PROPERTY_USAGE_NONE
		return true
	elif property.name == tag:
		property.usage = PROPERTY_USAGE_DEFAULT if comms_enabled else PROPERTY_USAGE_STORAGE
		return true

	return false


static func default_tag_group(current: String) -> String:
	if current.is_empty() and OIPComms.get_tag_groups().size() > 0:
		return OIPComms.get_tag_groups()[0]
	return current


static func connect_comms(
	node: Node,
	initialized: Callable = Callable(),
	polled: Callable = Callable()
) -> void:
	if initialized.is_valid():
		OIPComms.tag_group_initialized.connect(initialized)
	if polled.is_valid():
		OIPComms.tag_group_polled.connect(polled)
	OIPComms.enable_comms_changed.connect(node.notify_property_list_changed)


static func disconnect_comms(
	node: Node,
	initialized: Callable = Callable(),
	polled: Callable = Callable()
) -> void:
	if initialized.is_valid():
		OIPComms.tag_group_initialized.disconnect(initialized)
	if polled.is_valid():
		OIPComms.tag_group_polled.disconnect(polled)
	OIPComms.enable_comms_changed.disconnect(node.notify_property_list_changed)
