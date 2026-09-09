@tool
extends Control


var code: CodeEdit = null
var values: Dictionary = {}

var _ident := RegEx.new()


func _ready() -> void:
	_ident.compile("[A-Za-z_][A-Za-z0-9_]*")
	resized.connect(queue_redraw)
	if code != null:
		code.get_v_scroll_bar().value_changed.connect(_on_scroll)
		code.get_h_scroll_bar().value_changed.connect(_on_scroll)


func set_values(v: Dictionary) -> void:
	values = v
	queue_redraw()


func _on_scroll(_v: float) -> void:
	if not values.is_empty():
		queue_redraw()


func _draw() -> void:
	if code == null or values.is_empty():
		return
	var font: Font = code.get_theme_font("font")
	var fs: int = code.get_theme_font_size("font_size")
	if font == null:
		font = ThemeDB.fallback_font
		fs = 14
	var right: float = size.x
	var vsb: VScrollBar = code.get_v_scroll_bar()
	if vsb != null and vsb.visible:
		right -= vsb.size.x
	var first: int = code.get_first_visible_line()
	var last: int = code.get_last_full_visible_line()
	for line: int in range(first, last + 1):
		if line < 0 or line >= code.get_line_count():
			continue
		var names: Array = _watched_on_line(code.get_line(line))
		if names.is_empty():
			continue
		var anchor: Rect2 = code.get_rect_at_line_column(line, code.get_line(line).length())
		if anchor.position.x < 0.0:
			continue
		var x: float = anchor.position.x + 24.0
		var baseline: float = anchor.position.y + anchor.size.y * 0.5 + float(fs) * 0.34
		var show_name: bool = names.size() > 1
		for n: String in names:
			if x >= right:
				break
			x = _draw_chip(font, fs, x, baseline, anchor, n, show_name, right)


func _draw_chip(font: Font, fs: int, x: float, baseline: float, anchor: Rect2, n: String, show_name: bool, right: float) -> float:
	var value: Variant = values[n]
	var name_str: String = (n + " ") if show_name else ""
	var val_str: String = _fmt(value)
	var name_w: float = font.get_string_size(name_str, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var val_w: float = font.get_string_size(val_str, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var pad: float = 4.0
	var full_w: float = name_w + val_w + pad * 2.0
	var box := Rect2(x - pad, anchor.position.y, minf(full_w, right - (x - pad)), anchor.size.y)
	draw_rect(box, Color(0.11, 0.12, 0.15, 0.92), true)
	draw_rect(box, Color(1.0, 1.0, 1.0, 0.08), false)
	draw_string(font, Vector2(x, baseline), name_str, HORIZONTAL_ALIGNMENT_LEFT, maxf(0.0, right - x), fs, Color(0.58, 0.61, 0.66))
	draw_string(font, Vector2(x + name_w, baseline), val_str, HORIZONTAL_ALIGNMENT_LEFT, maxf(0.0, right - (x + name_w)), fs, _val_color(value))
	return x + full_w + 10.0


func _watched_on_line(text: String) -> Array:
	var out: Array = []
	var seen: Dictionary = {}
	for m: RegExMatch in _ident.search_all(text):
		var w: String = m.get_string()
		if values.has(w) and not seen.has(w):
			seen[w] = true
			out.append(w)
	return out


func _fmt(v: Variant) -> String:
	match typeof(v):
		TYPE_BOOL:
			return "TRUE" if v else "FALSE"
		TYPE_FLOAT:
			var f: float = v
			if absf(f - roundf(f)) < 0.0001:
				return str(int(roundf(f)))
			return "%.2f" % f
		_:
			return str(v)


func _val_color(v: Variant) -> Color:
	match typeof(v):
		TYPE_BOOL:
			return Color(0.36, 0.85, 0.45) if v else Color(0.55, 0.57, 0.6)
		TYPE_INT, TYPE_FLOAT:
			return Color(0.46, 0.74, 1.0)
		_:
			return Color(0.85, 0.85, 0.85)
