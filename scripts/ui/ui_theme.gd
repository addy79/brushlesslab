class_name UiTheme
extends RefCounted
## The interface's look: dark graphite cards, rounded buttons that light up on
## hover, toggle switches, and the Brushless Lab colours (from the icon: copper
## windings and teal steel). Variations: "Tab" (station tabs), "Chip" (small
## toggles), "Card" (choices), "Primary" (main action), "Ghost" (quiet buttons),
## "Section" (headings).

const NAVY := Color(0.08, 0.09, 0.11, 0.94)
const NAVY2 := Color(0.14, 0.15, 0.18, 0.97)
const NAVY3 := Color(0.21, 0.23, 0.27, 1.0)
const LINE := Color(1, 1, 1, 0.08)
const AMBER := Color("e8955a")   # copper
const BLUE := Color("4fc3c9")    # teal
const GREEN := Color("7fd18b")
const ROSE := Color("ef8fa0")
const LILAC := Color("c8b6ff")
const TEXT := Color("e8ecf4")
const MUTED := Color("a3b0c4")
const INK := Color("1a1410")


## Size factor for the theme being built (VR panels use bigger text and padding).
static var k := 1.0


static func box(bg: Color, radius := 12, border := Color(0, 0, 0, 0), bw := 0, mx := 14.0, my := 9.0, shadow := 0) -> StyleBoxFlat:
	radius = roundi(radius * k)
	mx *= k
	my *= k
	bw = maxi(roundi(bw * k), 1) if bw > 0 else 0
	shadow = roundi(shadow * k)
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.content_margin_left = mx
	s.content_margin_right = mx
	s.content_margin_top = my
	s.content_margin_bottom = my
	if bw > 0:
		s.border_color = border
		s.set_border_width_all(bw)
	if shadow > 0:
		s.shadow_color = Color(0, 0, 0, 0.35)
		s.shadow_size = shadow
		s.shadow_offset = Vector2(0, 3)
	s.anti_aliasing = true
	return s


## scale: 1 on the desktop; VR panels use about 1.6 (text read from a metre away).
static func make(scale := 1.0) -> Theme:
	k = scale
	var t := Theme.new()
	t.default_font = MeshUtil.math_font()
	t.default_font_size = roundi(15 * k)
	# Panels: glass cards.
	t.set_stylebox("panel", "PanelContainer", box(NAVY, 18, LINE, 1, 14, 12, 14))
	t.set_stylebox("panel", "Panel", box(NAVY, 18, LINE, 1, 14, 12, 14))
	t.set_color("font_color", "Label", TEXT)
	# Buttons.
	_button(t, "Button", NAVY2, NAVY3, AMBER, 12)
	_button(t, "OptionButton", NAVY2, NAVY3, AMBER, 12)
	t.set_type_variation("Tab", "Button")
	_button(t, "Tab", Color(0, 0, 0, 0), Color(1, 1, 1, 0.07), AMBER, 20, 14.0, 7.0)
	t.set_type_variation("Chip", "Button")
	_button(t, "Chip", Color(1, 1, 1, 0.05), Color(1, 1, 1, 0.1), BLUE, 20, 12.0, 6.0)
	t.set_type_variation("Card", "Button")
	_button(t, "Card", NAVY2, NAVY3, AMBER, 14, 16.0, 12.0)
	t.set_stylebox("hover", "Card", box(NAVY3, 14, AMBER, 2, 16, 12, 8))
	t.set_type_variation("Primary", "Button")
	t.set_stylebox("normal", "Primary", box(AMBER, 14, Color(0, 0, 0, 0), 0, 22, 11, 6))
	t.set_stylebox("hover", "Primary", box(AMBER.lightened(0.15), 14, Color(0, 0, 0, 0), 0, 22, 11, 10))
	t.set_stylebox("pressed", "Primary", box(AMBER.darkened(0.15), 14, Color(0, 0, 0, 0), 0, 22, 11, 2))
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		t.set_color(c, "Primary", INK)
	t.set_font_size("font_size", "Primary", roundi(18 * k))
	t.set_type_variation("Ghost", "Button")
	_button(t, "Ghost", Color(0, 0, 0, 0), Color(1, 1, 1, 0.08), BLUE, 12, 10.0, 6.0)
	t.set_type_variation("Section", "Button")
	_button(t, "Section", Color(0, 0, 0, 0), Color(1, 1, 1, 0.05), Color(1, 1, 1, 0.08), 8, 4.0, 4.0)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		t.set_color(c, "Section", BLUE)
	t.set_font_size("font_size", "Section", roundi(13 * k))
	# Switches and check boxes.
	for type in ["CheckButton", "CheckBox"]:
		t.set_stylebox("normal", type, box(Color(0, 0, 0, 0), 10, Color(0, 0, 0, 0), 0, 6, 6))
		t.set_stylebox("hover", type, box(Color(1, 1, 1, 0.05), 10, Color(0, 0, 0, 0), 0, 6, 6))
		t.set_stylebox("pressed", type, box(Color(0, 0, 0, 0), 10, Color(0, 0, 0, 0), 0, 6, 6))
		t.set_stylebox("hover_pressed", type, box(Color(1, 1, 1, 0.05), 10, Color(0, 0, 0, 0), 0, 6, 6))
		t.set_stylebox("focus", type, StyleBoxEmpty.new())
		t.set_color("font_color", type, TEXT)
		t.set_color("font_hover_color", type, Color.WHITE)
		t.set_color("font_pressed_color", type, TEXT)
		t.set_color("font_hover_pressed_color", type, Color.WHITE)
	t.set_icon("checked", "CheckButton", _switch(true, k))
	t.set_icon("unchecked", "CheckButton", _switch(false, k))
	# Sliders, bars, scrollbars, fields, popups.
	t.set_stylebox("slider", "HSlider", box(Color(1, 1, 1, 0.12), 4, Color(0, 0, 0, 0), 0, 0, 3))
	t.set_stylebox("grabber_area", "HSlider", box(BLUE, 4, Color(0, 0, 0, 0), 0, 0, 3))
	t.set_stylebox("grabber_area_highlight", "HSlider", box(BLUE.lightened(0.2), 4, Color(0, 0, 0, 0), 0, 0, 3))
	t.set_icon("grabber", "HSlider", _dot(roundi(16 * k), Color.WHITE))
	t.set_icon("grabber_highlight", "HSlider", _dot(roundi(18 * k), AMBER))
	t.set_stylebox("background", "ProgressBar", box(Color(1, 1, 1, 0.1), 6, Color(0, 0, 0, 0), 0, 0, 0))
	t.set_stylebox("fill", "ProgressBar", box(BLUE, 6, Color(0, 0, 0, 0), 0, 0, 0))
	t.set_stylebox("scroll", "VScrollBar", box(Color(0, 0, 0, 0), 4, Color(0, 0, 0, 0), 0, 3, 0))
	t.set_stylebox("grabber", "VScrollBar", box(Color(1, 1, 1, 0.15), 4, Color(0, 0, 0, 0), 0, 3, 0))
	t.set_stylebox("grabber_highlight", "VScrollBar", box(Color(1, 1, 1, 0.3), 4, Color(0, 0, 0, 0), 0, 3, 0))
	t.set_stylebox("grabber_pressed", "VScrollBar", box(AMBER, 4, Color(0, 0, 0, 0), 0, 3, 0))
	t.set_stylebox("normal", "LineEdit", box(Color(0, 0, 0, 0.3), 12, Color(1, 1, 1, 0.12), 1, 12, 8))
	t.set_stylebox("focus", "LineEdit", box(Color(0, 0, 0, 0.3), 12, BLUE, 2, 12, 8))
	t.set_color("font_placeholder_color", "LineEdit", MUTED)
	t.set_stylebox("panel", "PopupMenu", box(NAVY2, 12, LINE, 1, 6, 6, 10))
	t.set_stylebox("hover", "PopupMenu", box(NAVY3, 8, Color(0, 0, 0, 0), 0, 6, 4))
	t.set_stylebox("panel", "TooltipPanel", box(NAVY2, 10, LINE, 1, 10, 6))
	t.set_stylebox("separator", "HSeparator", box(Color(1, 1, 1, 0.08), 0, Color(0, 0, 0, 0), 0, 0, 0))
	t.set_constant("separation", "HSeparator", roundi(12 * k))
	k = 1.0
	return t


static func _button(t: Theme, type: String, bg: Color, hover: Color, accent: Color, radius: int, mx := 14.0, my := 9.0) -> void:
	t.set_stylebox("normal", type, box(bg, radius, LINE, 1 if bg.a > 0.0 else 0, mx, my))
	t.set_stylebox("hover", type, box(hover, radius, accent.lerp(Color(1, 1, 1, 0), 0.4), 1, mx, my))
	t.set_stylebox("pressed", type, box(accent, radius, Color(0, 0, 0, 0), 0, mx, my))
	t.set_stylebox("hover_pressed", type, box(accent.lightened(0.1), radius, Color(0, 0, 0, 0), 0, mx, my))
	t.set_stylebox("disabled", type, box(Color(bg, bg.a * 0.5), radius, Color(0, 0, 0, 0), 0, mx, my))
	t.set_stylebox("focus", type, StyleBoxEmpty.new())
	t.set_color("font_color", type, TEXT)
	t.set_color("font_hover_color", type, Color.WHITE)
	t.set_color("font_pressed_color", type, INK)
	t.set_color("font_hover_pressed_color", type, INK)
	t.set_color("font_focus_color", type, TEXT)


## A rounded switch (on: amber with the knob right).
static func _switch(on: bool, scale := 1.0) -> ImageTexture:
	var w := roundi(40 * scale)
	var h := roundi(22 * scale)
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var track := AMBER if on else Color(1, 1, 1, 0.22)
	var r := h * 0.5
	for y in h:
		for x in w:
			var cx := clampf(x, r, w - r)
			var d := Vector2(x + 0.5, y + 0.5).distance_to(Vector2(cx, r))
			var a := clampf(r - d + 0.5, 0.0, 1.0)
			img.set_pixel(x, y, Color(track, track.a * a))
	var kx := w - r if on else r
	for y in h:
		for x in w:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(Vector2(kx, r))
			var a := clampf(r - 3.0 - d + 0.5, 0.0, 1.0)
			if a > 0.0:
				img.set_pixel(x, y, img.get_pixel(x, y).blend(Color(1, 1, 1, a)))
	return ImageTexture.create_from_image(img)


static func _dot(size: int, color: Color) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var r := size * 0.5
	for y in size:
		for x in size:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(Vector2(r, r))
			img.set_pixel(x, y, Color(color, clampf(r - 1.0 - d + 0.5, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)


## A small rounded label ("chip") with an emoji or text.
static func chip(text: String, bg: Color, fg := TEXT, size := 13, scale := 1.0) -> PanelContainer:
	k = scale
	size = roundi(size * scale)
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(bg, 20, Color(0, 0, 0, 0), 0, 10, 3))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", fg)
	p.add_child(l)
	k = 1.0
	return p
