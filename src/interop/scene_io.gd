class_name OipSceneIO
extends RefCounted


const MANIFEST_PATH := "res://src/interop/part_mapping.json"
const SCENE_VERSION := 2
const ROT_EPSILON := 1e-9


static func _load_manifest() -> Dictionary:
	var f := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	if f == null:
		push_error("scene_io: cannot open manifest %s" % MANIFEST_PATH)
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("scene_io: manifest is not a JSON object")
		return {}
	return parsed


static func import_scene(doc: Dictionary, parent: Node) -> Array[Node]:
	var parts_def: Dictionary = _load_manifest().get("parts", {})
	var created: Array[Node] = []
	var id_to_node := {}
	var deferred: Array = []
	var parts: Array = doc.get("parts", [])
	for entry_v: Variant in parts:
		var part: Dictionary = entry_v
		var type_name := String(part.get("type", ""))
		if not parts_def.has(type_name):
			push_warning("scene_io: no mapping for type '%s', skipping" % type_name)
			continue
		var pmap: Dictionary = parts_def[type_name]
		var node := _instantiate_part(pmap)
		if node == null:
			push_warning("scene_io: cannot create '%s'" % type_name)
			continue
		var web_id := String(part.get("id", type_name))
		node.name = String(part.get("name", web_id))
		node.set_meta("oip_web_id", web_id)
		node.set_meta("oip_type", type_name)
		if part.has("parent"):
			node.set_meta("oip_parent", String(part["parent"]))
		_apply_transform(node, part, pmap)
		_apply_params(node, part.get("params", {}), pmap.get("params", []))
		_apply_godot_extra(node, part.get("params", {}))
		_stash_web_extra(node, part.get("params", {}), pmap.get("webOnly", []))
		parent.add_child(node)
		created.append(node)
		id_to_node[web_id] = node
		deferred.append({"node": node, "params": part.get("params", {}), "maps": pmap.get("params", [])})
	for d_v: Variant in deferred:
		var d: Dictionary = d_v
		_apply_refs(d["node"], d["params"], d["maps"], id_to_node)
	for node: Node in created:
		if not node.has_meta("oip_parent"):
			continue
		var pid := String(node.get_meta("oip_parent"))
		if not id_to_node.has(pid):
			push_warning("scene_io: parent id '%s' not found for '%s'; keeping it top-level" % [pid, node.name])
			continue
		var new_parent: Node = id_to_node[pid]
		if node is Node3D:
			node.reparent(new_parent, true)
		else:
			node.get_parent().remove_child(node)
			new_parent.add_child(node)
	if doc.has("stProgram"):
		parent.set_meta("oip_st_program", String(doc["stProgram"]))
	if doc.has("scanMs"):
		parent.set_meta("oip_st_scan_ms", int(doc["scanMs"]))
	return created


static func _instantiate_part(pmap: Dictionary) -> Node:
	var scene_path := String(pmap.get("godotScene", ""))
	if scene_path == "":
		return Node3D.new()
	var packed := load(scene_path) as PackedScene
	if packed == null:
		return null
	return packed.instantiate()


static func _apply_transform(node: Node, part: Dictionary, pmap: Dictionary) -> void:
	var n3 := node as Node3D
	if n3 == null:
		return
	var native_scale := n3.scale
	var pos_arr: Array = part.get("position", [0.0, 0.0, 0.0])
	var pos := Vector3(float(pos_arr[0]), float(pos_arr[1]), float(pos_arr[2]))
	var euler := Vector3(
		float(part.get("rotationX", 0.0)),
		float(part.get("rotationY", 0.0)),
		float(part.get("rotationZ", 0.0)))
	var basis := Basis.from_euler(euler, EULER_ORDER_YXZ)
	var origin := pos + basis * _origin_offset(pmap)
	n3.transform = Transform3D(basis.scaled(native_scale), origin)


static func _origin_offset(pmap: Dictionary) -> Vector3:
	var arr: Array = pmap.get("importOriginOffset", [])
	if arr.size() != 3:
		return Vector3.ZERO
	return Vector3(float(arr[0]), float(arr[1]), float(arr[2]))


static func _apply_params(node: Node, params: Dictionary, param_maps: Array) -> void:
	var vec3_acc := {}
	for pm_v: Variant in param_maps:
		var pm: Dictionary = pm_v
		var convert := String(pm.get("convert", "identity"))
		if convert == "partRef":
			continue
		var web_key := String(pm.get("web", ""))
		if not params.has(web_key):
			continue
		var godot_key := String(pm.get("godot", ""))
		if convert == "vec3":
			if not vec3_acc.has(godot_key):
				var cur := Vector3.ZERO
				if godot_key in node:
					cur = node.get(godot_key)
				vec3_acc[godot_key] = cur
			var vec: Vector3 = vec3_acc[godot_key]
			var val := float(params[web_key])
			match String(pm.get("component", "x")):
				"x":
					vec.x = val
				"y":
					vec.y = val
				"z":
					vec.z = val
			vec3_acc[godot_key] = vec
			continue
		if convert == "stackLights":
			_apply_stack_lights(node, params[web_key] as Array)
			continue
		if convert == "wallRules":
			node.set("rules", _to_wall_rules(params[web_key] as Array))
			continue
		if convert == "waypoints":
			_apply_waypoints(node, params[web_key] as Dictionary)
			continue
		var gv: Variant = _web_to_godot(convert, params[web_key], pm)
		node.set(godot_key, gv)
		for k_v: Variant in (pm.get("alsoGodot", []) as Array):
			node.set(String(k_v), gv)
	for gk: String in vec3_acc.keys():
		node.set(gk, vec3_acc[gk])


static func _apply_refs(node: Node, params: Dictionary, param_maps: Array, id_to_node: Dictionary) -> void:
	for pm_v: Variant in param_maps:
		var pm: Dictionary = pm_v
		if String(pm.get("convert", "")) != "partRef":
			continue
		var web_key := String(pm.get("web", ""))
		if not params.has(web_key):
			continue
		var ref_id := String(params[web_key])
		if ref_id == "":
			continue
		if not id_to_node.has(ref_id):
			push_warning("scene_io: partRef '%s' -> unknown id '%s'" % [web_key, ref_id])
			continue
		node.set(String(pm.get("godot", "")), id_to_node[ref_id])


static func _web_to_godot(convert: String, v: Variant, pm: Dictionary) -> Variant:
	match convert:
		"identity", "tagFanout":
			return v
		"degToRad":
			return deg_to_rad(float(v))
		"color":
			return Color.html(String(v).trim_prefix("#"))
		"enumMap":
			var em: Dictionary = pm.get("enumMap", {})
			return int(em.get(String(v), 0))
		"segments":
			var out: Array[BeltSegment] = []
			for s_v: Variant in (v as Array):
				var s: Dictionary = s_v
				var seg := BeltSegment.new()
				seg.length = float(s.get("length", 0.0))
				seg.tilt_relative_deg = float(s.get("tiltDeg", 0.0))
				out.append(seg)
			return out
		_:
			push_warning("scene_io: unknown convert '%s'" % convert)
			return v


static func export_scene(root: Node) -> Dictionary:
	var parts_def: Dictionary = _load_manifest().get("parts", {})
	var scene_to_type := {}
	for type_name: String in parts_def.keys():
		var gs := String((parts_def[type_name] as Dictionary).get("godotScene", ""))
		if gs != "":
			scene_to_type[gs] = type_name
	var out_parts: Array = []
	_collect_parts(root, "", scene_to_type, parts_def, out_parts)
	var out := {"version": SCENE_VERSION, "parts": out_parts}
	if root.has_meta("oip_st_program"):
		out["stProgram"] = String(root.get_meta("oip_st_program"))
	if root.has_meta("oip_st_scan_ms"):
		out["scanMs"] = int(root.get_meta("oip_st_scan_ms"))
	return out


static func _collect_parts(
		node: Node, parent_id: String, scene_to_type: Dictionary,
		parts_def: Dictionary, out_parts: Array) -> void:
	for child: Node in node.get_children():
		var type_name := _type_of(child, scene_to_type)
		if type_name == "":
			continue
		out_parts.append(_export_part(child, type_name, parts_def[type_name], parent_id))
		_collect_parts(child, String(child.get_meta("oip_web_id", child.name)),
			scene_to_type, parts_def, out_parts)


static func _type_of(node: Node, scene_to_type: Dictionary) -> String:
	if node.has_meta("oip_type"):
		return String(node.get_meta("oip_type"))
	var sfp := String(node.scene_file_path)
	if scene_to_type.has(sfp):
		return String(scene_to_type[sfp])
	return ""


static func _export_part(node: Node, type_name: String, pmap: Dictionary, parent_id: String) -> Dictionary:
	var part := {}
	var web_id := String(node.get_meta("oip_web_id", node.name))
	part["id"] = web_id
	if String(node.name) != web_id:
		part["name"] = String(node.name)
	if parent_id != "":
		part["parent"] = parent_id
	elif node.has_meta("oip_parent"):
		part["parent"] = String(node.get_meta("oip_parent"))
	part["type"] = type_name
	var n3 := node as Node3D
	if n3 != null:
		var t := n3.global_transform
		var web_origin := t.origin - t.basis.orthonormalized() * _origin_offset(pmap)
		part["position"] = [web_origin.x, web_origin.y, web_origin.z]
		var euler := t.basis.orthonormalized().get_euler(EULER_ORDER_YXZ)
		part["rotationY"] = euler.y
		if absf(euler.x) > ROT_EPSILON:
			part["rotationX"] = euler.x
		if absf(euler.z) > ROT_EPSILON:
			part["rotationZ"] = euler.z
	var params := {}
	for pm_v: Variant in (pmap.get("params", []) as Array):
		var pm: Dictionary = pm_v
		var convert := String(pm.get("convert", "identity"))
		var godot_key := String(pm.get("godot", ""))
		var web_key := String(pm.get("web", ""))
		if convert == "partRef":
			if godot_key in node:
				var ref_val: Variant = node.get(godot_key)
				if ref_val is Node and (ref_val as Node).has_meta("oip_web_id"):
					params[web_key] = String((ref_val as Node).get_meta("oip_web_id"))
				else:
					params[web_key] = ""
			continue
		if convert == "vec3":
			if godot_key in node:
				var vec: Vector3 = node.get(godot_key)
				match String(pm.get("component", "x")):
					"x":
						params[web_key] = vec.x
					"y":
						params[web_key] = vec.y
					"z":
						params[web_key] = vec.z
			continue
		if convert == "stackLights":
			params[web_key] = _read_stack_lights(node)
			continue
		if convert == "wallRules":
			params[web_key] = _read_wall_rules(node)
			continue
		if convert == "waypoints":
			params[web_key] = _read_waypoints(node)
			continue
		if not (godot_key in node):
			continue
		params[web_key] = _godot_to_web(convert, node.get(godot_key), pm)
	_export_godot_extra(node, params, pmap.get("godotOnly", []))
	_reemit_web_extra(node, params)
	part["params"] = params
	return part


static func _apply_godot_extra(node: Node, params: Dictionary) -> void:
	var extra: Variant = params.get("_godotExtra", null)
	if typeof(extra) != TYPE_DICTIONARY:
		return
	for k_v: Variant in (extra as Dictionary).keys():
		var key := String(k_v)
		if key in node:
			node.set(key, _decode_extra((extra as Dictionary)[k_v]))


static func _export_godot_extra(node: Node, params: Dictionary, godot_only: Array) -> void:
	var extra := {}
	for k_v: Variant in godot_only:
		var key := String(k_v)
		if key == "scene":
			continue
		if key in node:
			var enc: Variant = _encode_extra(node.get(key))
			if enc != null:
				extra[key] = enc
	if not extra.is_empty():
		params["_godotExtra"] = extra


static func _stash_web_extra(node: Node, params: Dictionary, web_only: Array) -> void:
	var stash := {}
	for k_v: Variant in web_only:
		var key := String(k_v)
		if params.has(key):
			stash[key] = params[key]
	if not stash.is_empty():
		node.set_meta("oip_web_extra", stash)


static func _reemit_web_extra(node: Node, params: Dictionary) -> void:
	if not node.has_meta("oip_web_extra"):
		return
	var stash: Dictionary = node.get_meta("oip_web_extra")
	for k_v: Variant in stash.keys():
		params[String(k_v)] = stash[k_v]


static func _encode_extra(v: Variant) -> Variant:
	match typeof(v):
		TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING:
			return v
		TYPE_STRING_NAME:
			return String(v)
		TYPE_VECTOR3:
			return {"__t": "Vector3", "v": [v.x, v.y, v.z]}
		TYPE_VECTOR2:
			return {"__t": "Vector2", "v": [v.x, v.y]}
		TYPE_COLOR:
			return {"__t": "Color", "v": [v.r, v.g, v.b, v.a]}
		TYPE_ARRAY:
			var out := []
			for e_v: Variant in (v as Array):
				out.append(_encode_extra(e_v))
			return out
		_:
			return null


static func _decode_extra(v: Variant) -> Variant:
	if typeof(v) == TYPE_DICTIONARY and (v as Dictionary).has("__t"):
		var a: Array = (v as Dictionary).get("v", [])
		match String((v as Dictionary)["__t"]):
			"Vector3":
				return Vector3(float(a[0]), float(a[1]), float(a[2]))
			"Vector2":
				return Vector2(float(a[0]), float(a[1]))
			"Color":
				return Color(float(a[0]), float(a[1]), float(a[2]), float(a[3]))
	if typeof(v) == TYPE_ARRAY:
		var out := []
		for e_v: Variant in (v as Array):
			out.append(_decode_extra(e_v))
		return out
	return v


const _WALL_NAMES := ["A", "B", "C", "D", "dock_door"]


static func _apply_stack_lights(node: Node, lights: Array) -> void:
	node.set("segments", lights.size())
	var data: Variant = node.get("_data")
	var segs: Array = []
	if data != null:
		segs = data.segment_datas
	var value := 0
	for i: int in lights.size():
		var light: Dictionary = lights[i]
		var on := bool(light.get("on", false))
		if data != null:
			while segs.size() <= i:
				segs.append(StackSegmentData.new())
			var seg: Variant = segs[i]
			if seg == null:
				seg = StackSegmentData.new()
				segs[i] = seg
			seg.segment_color = Color.html(String(light.get("color", "#ffffff")).trim_prefix("#"))
			seg.active = on
		if on:
			value |= (1 << i)
	node.set("light_value", value)


static func _read_stack_lights(node: Node) -> Array:
	var data: Variant = node.get("_data")
	var segs: Array = []
	if data != null:
		segs = data.segment_datas
	var lights: Array = []
	for i: int in int(node.get("segments")):
		var color_hex := "#ffffff"
		var on := false
		if i < segs.size():
			var seg: Variant = segs[i]
			var c: Color = seg.segment_color
			color_hex = "#" + c.to_html(not is_equal_approx(c.a, 1.0))
			on = bool(seg.active)
		lights.append({"color": color_hex, "on": on})
	return lights


static func _to_wall_rules(rules_in: Array) -> Array[BuildingWallRule]:
	var out: Array[BuildingWallRule] = []
	for r_v: Variant in rules_in:
		var r: Dictionary = r_v
		var rule := BuildingWallRule.new()
		rule.set("wall", _wall_enum(String(r.get("wall", "D"))))
		rule.run = int(r.get("run", 1))
		rule.gap = int(r.get("gap", 1))
		rule.count = int(r.get("count", 0))
		rule.start = int(r.get("start", 0))
		rule.door_count = int(r.get("doorCount", 1))
		rule.trailer = bool(r.get("trailer", true))
		out.append(rule)
	return out


static func _read_wall_rules(node: Node) -> Array:
	var out: Array = []
	for rule_v: Variant in (node.get("rules") as Array):
		var rule: Variant = rule_v
		out.append({
			"wall": _wall_name(int(rule.wall)),
			"run": int(rule.run),
			"gap": int(rule.gap),
			"count": int(rule.count),
			"start": int(rule.start),
			"doorCount": int(rule.door_count),
			"trailer": bool(rule.trailer),
		})
	return out


static func _wall_enum(wall_name: String) -> int:
	var idx := _WALL_NAMES.find(wall_name)
	return idx if idx >= 0 else 3


static func _wall_name(value: int) -> String:
	if value >= 0 and value < _WALL_NAMES.size():
		return String(_WALL_NAMES[value])
	return "D"


static func _apply_waypoints(node: Node, store: Dictionary) -> void:
	var is_agv := "home_yaw_deg" in node
	var home: Array = store.get("home", [])
	if is_agv:
		node.set("home_position", _to_xz_vec(home))
		node.set("home_yaw_deg", float(home[2]) if home.size() > 2 else 0.0)
	else:
		node.set("home_position", _to_float_array(home))
	var dict := {}
	var points: Array = store.get("points", [])
	for i: int in points.size():
		var pt: Dictionary = points[i]
		dict["%d: %s" % [i + 1, String(pt.get("name", ""))]] = _encode_pose(is_agv, pt.get("pose", []))
	node.set("waypoints", dict)
	node.set("selected_waypoint", _find_key_for_name(dict, String(store.get("selected", ""))))
	node.set("new_waypoint_name", String(store.get("newName", "Point1")))


static func _read_waypoints(node: Node) -> Dictionary:
	var is_agv := "home_yaw_deg" in node
	var store := {}
	if is_agv:
		var hp: Vector3 = node.get("home_position")
		store["home"] = [hp.x, hp.z, float(node.get("home_yaw_deg"))]
	else:
		store["home"] = _from_float_array(node.get("home_position"))
	var points: Array = []
	var dict: Dictionary = node.get("waypoints")
	for key: Variant in dict.keys():
		points.append({"name": _strip_index(String(key)), "pose": _decode_pose(is_agv, dict[key])})
	store["points"] = points
	store["selected"] = _strip_index(String(node.get("selected_waypoint")))
	store["newName"] = String(node.get("new_waypoint_name"))
	return store


static func _encode_pose(is_agv: bool, pose: Variant) -> Variant:
	var arr: Array = pose
	if is_agv:
		var wp := AGVWaypoint.new()
		wp.position = _to_xz_vec(arr)
		wp.yaw_deg = float(arr[2]) if arr.size() > 2 else 0.0
		return wp
	return _to_float_array(arr)


static func _decode_pose(is_agv: bool, value: Variant) -> Array:
	if is_agv:
		var wp: Variant = value
		return [wp.position.x, wp.position.z, wp.yaw_deg]
	return _from_float_array(value)


static func _to_xz_vec(arr: Array) -> Vector3:
	var x := float(arr[0]) if arr.size() > 0 else 0.0
	var z := float(arr[1]) if arr.size() > 1 else 0.0
	return Vector3(x, 0.0, z)


static func _to_float_array(arr: Variant) -> Array[float]:
	var out: Array[float] = []
	for v: Variant in (arr as Array):
		out.append(float(v))
	return out


static func _from_float_array(arr: Variant) -> Array:
	var out: Array = []
	for v: Variant in (arr as Array):
		out.append(float(v))
	return out


static func _strip_index(key: String) -> String:
	var idx := key.find(": ")
	if idx >= 0:
		return key.substr(idx + 2)
	return key


static func _find_key_for_name(dict: Dictionary, name: String) -> String:
	for key: Variant in dict.keys():
		if _strip_index(String(key)) == name:
			return String(key)
	return ""


static func _godot_to_web(convert: String, v: Variant, pm: Dictionary) -> Variant:
	match convert:
		"identity", "tagFanout":
			return v
		"degToRad":
			return rad_to_deg(float(v))
		"color":
			var c: Color = v
			var with_alpha := not is_equal_approx(c.a, 1.0)
			return "#" + c.to_html(with_alpha)
		"enumMap":
			var em: Dictionary = pm.get("enumMap", {})
			for k: String in em.keys():
				if int(em[k]) == int(v):
					return k
			return ""
		"segments":
			var out: Array = []
			for seg_v: Variant in (v as Array):
				var seg: BeltSegment = seg_v
				out.append({"length": seg.length, "tiltDeg": seg.tilt_relative_deg})
			return out
		_:
			return v
