class_name Ui
extends RefCounted
## Small builders for the station panels (2D controls shown on ViewportPanel3D).


static func vbox(sep := 8) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func hbox(sep := 8) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


static func flow(sep := 6) -> HFlowContainer:
	var f := HFlowContainer.new()
	f.add_theme_constant_override("h_separation", sep)
	f.add_theme_constant_override("v_separation", sep)
	return f


static func card() -> PanelContainer:
	return PanelContainer.new()


static func title(text: String, size := 30, color := UiTheme.AMBER) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func text(t: String, size := 20, color := UiTheme.TEXT) -> Label:
	var l := Label.new()
	l.text = t
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.custom_minimum_size.x = 100
	return l


static func mono(t: String, size := 22, color := Color("9ff0c8")) -> Label:
	var l := text(t, size, color)
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["DejaVu Sans Mono", "Noto Sans Mono", "Liberation Mono", "monospace"])
	l.add_theme_font_override("font", f)
	return l


static func button(t: String, cb: Callable, variation := "", size := 20) -> Button:
	var b := Button.new()
	b.text = t
	b.theme_type_variation = variation
	b.add_theme_font_size_override("font_size", size)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	return b


static func toggle(t: String, on: bool, cb: Callable, size := 20) -> CheckButton:
	var c := CheckButton.new()
	c.text = t
	c.button_pressed = on
	c.focus_mode = Control.FOCUS_NONE
	c.add_theme_font_size_override("font_size", size)
	c.toggled.connect(cb)
	return c


static func slider(min_v: float, max_v: float, value: float, step: float, cb: Callable, width := 360) -> HSlider:
	var s := HSlider.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = step
	s.value = value
	s.custom_minimum_size = Vector2(width, 36)
	s.focus_mode = Control.FOCUS_NONE
	s.value_changed.connect(cb)
	return s


static func option(items: Array, selected: int, cb: Callable, size := 20) -> OptionButton:
	var o := OptionButton.new()
	for it in items:
		o.add_item(str(it))
	o.selected = selected
	o.clip_text = true
	o.fit_to_longest_item = false
	o.custom_minimum_size.x = 120
	o.focus_mode = Control.FOCUS_NONE
	o.add_theme_font_size_override("font_size", size)
	o.item_selected.connect(cb)
	return o


static func spin(min_v: float, max_v: float, value: float, step: float, cb: Callable, suffix := "") -> SpinBox:
	var s := SpinBox.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = step
	s.value = value
	s.suffix = suffix
	s.custom_minimum_size.x = 170
	s.value_changed.connect(cb)
	s.get_line_edit().add_theme_font_size_override("font_size", 20)
	return s


static func sep() -> HSeparator:
	return HSeparator.new()


static func clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()


## A coloured status line (ok/warn/error/info).
static func status(t: String, kind := "info", size := 20) -> Label:
	var col := UiTheme.TEXT
	match kind:
		"ok":
			col = UiTheme.GREEN
		"warn":
			col = UiTheme.AMBER
		"error":
			col = UiTheme.ROSE
		"info":
			col = UiTheme.BLUE
	return text(t, size, col)
