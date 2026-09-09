@tool
extends VBoxContainer


const OverlayScript := preload("res://addons/st_editor/st_monitor_overlay.gd")
const GROUP := "ST"
const PROGRAM_META := "oip_st_program"
const POLL_SEC := 0.12

var _scene_root: Node = null
var _code: CodeEdit = null
var _overlay: Control = null
var _status: Label = null
var _loading := false
var _watching := false
var _poll_accum := 0.0


func _init() -> void:
	name = "ST Program"
	custom_minimum_size.y = 200
	_build_ui()
	set_process(false)


func _ready() -> void:
	visibility_changed.connect(_on_visibility_changed)
	if Engine.has_singleton("Simulation"):
		var sim: Object = Engine.get_singleton("Simulation")
		if not sim.is_connected("stopped", _on_sim_stopped):
			sim.connect("stopped", _on_sim_stopped)


func _build_ui() -> void:
	var bar := HBoxContainer.new()
	var title := Label.new()
	title.text = "Structured Text"
	bar.add_child(title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)
	_status = Label.new()
	bar.add_child(_status)
	var check_btn := Button.new()
	check_btn.text = "Check"
	check_btn.tooltip_text = "Compile-check the program against the embedded ST engine"
	check_btn.pressed.connect(_on_check)
	bar.add_child(check_btn)
	var apply_btn := Button.new()
	apply_btn.text = "Apply"
	apply_btn.tooltip_text = "Hot-swap this program into the running simulation"
	apply_btn.pressed.connect(_on_apply)
	bar.add_child(apply_btn)
	add_child(bar)

	_code = CodeEdit.new()
	_code.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_code.gutters_draw_line_numbers = true
	_code.highlight_current_line = true
	_code.draw_tabs = false
	_code.syntax_highlighter = _make_highlighter()
	_code.editable = false
	_code.text_changed.connect(_on_text_changed)
	add_child(_code)

	_overlay = OverlayScript.new()
	_code.add_child(_overlay)
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.code = _code


func set_scene_root(root: Node) -> void:
	_scene_root = root
	_loading = true
	if root != null:
		_code.text = String(root.get_meta(PROGRAM_META, ""))
		_code.editable = true
	else:
		_code.text = ""
		_code.editable = false
	_loading = false


func _on_text_changed() -> void:
	if _loading or _scene_root == null:
		return
	_scene_root.set_meta(PROGRAM_META, _code.text)
	EditorInterface.mark_scene_as_unsaved()


func _on_apply() -> void:
	if _scene_root != null:
		_scene_root.set_meta(PROGRAM_META, _code.text)
	if Engine.has_singleton("OIPComms"):
		OIPComms.set_soft_plc_program(GROUP, _code.text)
	_set_status("Applied to running sim", Color(0.5, 0.8, 0.55))


func _on_check() -> void:
	if not Engine.has_singleton("OIPComms"):
		_set_status("OIPComms unavailable", Color(0.9, 0.6, 0.3))
		return
	var err := String(OIPComms.compile_soft_plc(GROUP, _code.text))
	if err.is_empty():
		_set_status("✓ compiles", Color(0.5, 0.8, 0.55))
	else:
		_set_status("✗ " + err, Color(0.95, 0.5, 0.5))


func _on_visibility_changed() -> void:
	var vis := is_visible_in_tree()
	if vis == _watching:
		return
	_watching = vis
	if Engine.has_singleton("OIPComms"):
		OIPComms.set_soft_plc_watch_enabled(GROUP, vis)
	set_process(vis)
	if not vis:
		_overlay.call("set_values", {})


func _on_sim_stopped() -> void:
	_overlay.call("set_values", {})


func _process(dt: float) -> void:
	_poll_accum += dt
	if _poll_accum < POLL_SEC:
		return
	_poll_accum = 0.0
	if Engine.has_singleton("OIPComms"):
		_overlay.call("set_values", OIPComms.get_soft_plc_watch(GROUP))


func _set_status(text: String, color: Color) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", color)


func _make_highlighter() -> SyntaxHighlighter:
	var h := CodeHighlighter.new()
	h.number_color = Color(0.46, 0.74, 1.0)
	h.symbol_color = Color(0.7, 0.7, 0.75)
	h.function_color = Color(0.4, 0.7, 1.0)
	h.member_variable_color = Color(0.85, 0.85, 0.9)
	var kw := Color(0.9, 0.55, 0.75)
	var keywords: Array[String] = [
		"IF", "THEN", "ELSE", "ELSIF", "END_IF", "CASE", "OF", "END_CASE",
		"FOR", "TO", "BY", "DO", "END_FOR", "WHILE", "END_WHILE", "REPEAT", "UNTIL", "END_REPEAT",
		"VAR", "VAR_INPUT", "VAR_OUTPUT", "VAR_IN_OUT", "VAR_GLOBAL", "END_VAR", "CONSTANT", "RETAIN",
		"FUNCTION", "END_FUNCTION", "FUNCTION_BLOCK", "END_FUNCTION_BLOCK", "PROGRAM", "END_PROGRAM",
		"TRUE", "FALSE", "AND", "OR", "XOR", "NOT", "MOD", "RETURN", "EXIT",
		"BOOL", "INT", "DINT", "UINT", "UDINT", "SINT", "USINT", "LINT", "REAL", "LREAL", "TIME", "WORD", "BYTE", "DWORD",
	]
	for k: String in keywords:
		h.add_keyword_color(k, kw)
	var comment := Color(0.45, 0.5, 0.45)
	h.add_color_region("(*", "*)", comment, false)
	h.add_color_region("//", "", comment, true)
	h.add_color_region("'", "'", Color(0.7, 0.85, 0.5), false)
	return h
