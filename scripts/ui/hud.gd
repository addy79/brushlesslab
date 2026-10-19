class_name Hud
extends CanvasLayer
## Desktop interface: a top bar (station tabs, the current job), a drawer on the right
## that holds the station's panel, the notebook at the bottom left, toasts, the pointer
## tooltip and the help card (H). In VR the same station panel moves onto a 3D panel.

signal station_requested(index: int)
signal xr_requested

const DRAWER_MAX := 470
const DRAWER_MIN := 370

## Current drawer width in pixels (0 when hidden).
var drawer_w := DRAWER_MAX

var root := Control.new()
var drawer := PanelContainer.new()
var drawer_scroll := ScrollContainer.new()
var drawer_holder := MarginContainer.new()
var job_label := Label.new()
var next_label := Label.new()
var tooltip := Label.new()
var notebook_box := VBoxContainer.new()
var notebook_panel := PanelContainer.new()
var help_panel := PanelContainer.new()
var _tabs: Array[Button] = []
var _toasts := VBoxContainer.new()


func setup(titles: Array) -> void:
	layer = 5
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UiTheme.make(1.0)
	add_child(root)
	# --- top bar ---------------------------------------------------------------------------
	var bar := PanelContainer.new()
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.offset_left = 10
	bar.offset_right = -10
	bar.offset_top = 8
	root.add_child(bar)
	var row := Ui.hbox(6)
	bar.add_child(row)
	var logo := Ui.title("⚙ Brushless Lab", 20)
	row.add_child(logo)
	for i in titles.size():
		var b := Ui.button("%d %s" % [i + 1, titles[i]], station_requested.emit.bind(i), "Tab", 14)
		b.toggle_mode = true
		row.add_child(b)
		_tabs.append(b)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	row.add_child(Ui.button("VR", xr_requested.emit, "Ghost", 14))
	row.add_child(Ui.button("?", toggle_help, "Ghost", 14))
	# --- drawer ----------------------------------------------------------------------------
	drawer.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	drawer.offset_left = -DRAWER_MAX
	drawer.offset_right = -10
	drawer.offset_top = 66
	drawer.offset_bottom = -10
	root.add_child(drawer)
	var dv := Ui.vbox(6)
	drawer.add_child(dv)
	job_label.add_theme_font_size_override("font_size", 15)
	job_label.add_theme_color_override("font_color", UiTheme.AMBER)
	job_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dv.add_child(job_label)
	next_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	next_label.add_theme_font_size_override("font_size", 14)
	next_label.add_theme_color_override("font_color", UiTheme.LILAC)
	dv.add_child(next_label)
	drawer_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	drawer_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# a scrollbar that comes and goes changes the width, re-wraps the text and can flip
	# back and forth forever: keep it always there
	drawer_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS
	dv.add_child(drawer_scroll)
	drawer_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	drawer_holder.add_theme_constant_override("margin_right", 10)
	drawer_scroll.add_child(drawer_holder)
	# --- notebook --------------------------------------------------------------------------
	notebook_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	notebook_panel.offset_left = 10
	notebook_panel.offset_bottom = -10
	notebook_panel.offset_top = -190
	notebook_panel.offset_right = 470
	notebook_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	notebook_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(notebook_panel)
	var nv := Ui.vbox(2)
	notebook_panel.add_child(nv)
	var nt := Ui.title("📓 Notebook", 15, UiTheme.BLUE)
	nv.add_child(nt)
	nv.add_child(notebook_box)
	# --- toasts, tooltip, help ---------------------------------------------------------------
	_toasts.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_toasts.offset_left = 14
	_toasts.offset_top = 72
	_toasts.offset_right = 534
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_toasts)
	tooltip.add_theme_font_size_override("font_size", 15)
	tooltip.add_theme_color_override("font_color", Color.WHITE)
	tooltip.add_theme_color_override("font_outline_color", Color.BLACK)
	tooltip.add_theme_constant_override("outline_size", 6)
	tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(tooltip)
	help_panel.set_anchors_preset(Control.PRESET_CENTER)
	help_panel.custom_minimum_size = Vector2(620, 0)
	help_panel.offset_left = -310
	help_panel.offset_right = 310
	help_panel.offset_top = -230
	help_panel.visible = false
	root.add_child(help_panel)
	var hv := Ui.vbox(6)
	help_panel.add_child(hv)
	hv.add_child(Ui.title("How to use Brushless Lab", 22))
	hv.add_child(Ui.text(
		"Mouse: point and left-click parts, tools and buttons. Hold the right mouse button to look around.\n" +
		"Keys: %s/%s/%s/%s move, %s/%s down/up, Shift faster, 1–6 go to a bench, R resets the view, H shows this card, F1 toggles VR, F12 saves a screenshot.\n" %
		[InputSetup.key_label("move_forward"), InputSetup.key_label("move_left"), InputSetup.key_label("move_back"), InputSetup.key_label("move_right"),
		InputSetup.key_label("move_down"), InputSetup.key_label("move_up")] +
		"VR: trigger = point and press, left stick walks, right stick turns (snap) and flies, A/X = next bench, B/Y = previous bench.\n\n" +
		"Start at bench 1 (Job Desk): pick a job. Then work bench by bench: teardown, electrical tests, inspection and repair, rewinding, test stand. " +
		"Everything you measure goes into the notebook, and the desk grades your report.", 16))
	hv.add_child(Ui.button("Close", toggle_help, "Primary", 16))


## Fits the drawer, notebook and toasts to the window size.
func layout(view: Vector2) -> void:
	drawer_w = int(clampf(view.x * 0.4, DRAWER_MIN, DRAWER_MAX)) if drawer.visible else 0
	drawer.offset_left = -drawer_w - 10
	var free := view.x - drawer_w - 30.0
	notebook_panel.offset_right = 10 + minf(460.0, free - 10.0)
	_toasts.offset_right = 14 + minf(520.0, free - 20.0)


func set_station(index: int) -> void:
	for i in _tabs.size():
		_tabs[i].button_pressed = i == index


func set_job(text: String) -> void:
	job_label.text = text


func set_next(text: String) -> void:
	next_label.text = text
	next_label.visible = text != ""


func set_drawer_visible(v: bool) -> void:
	drawer.visible = v
	notebook_panel.visible = v


func set_notebook(lines: Array) -> void:
	Ui.clear(notebook_box)
	var start := maxi(lines.size() - 5, 0)
	for i in range(start, lines.size()):
		var l := Ui.text("• " + str(lines[i]), 13, UiTheme.TEXT if i == lines.size() - 1 else UiTheme.MUTED)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		notebook_box.add_child(l)
	if lines.is_empty():
		notebook_box.add_child(Ui.text("Measurements and findings will appear here.", 13, UiTheme.MUTED))


func toast(text: String, kind := "info", seconds := 4.5) -> void:
	var p := PanelContainer.new()
	var col := {"ok": UiTheme.GREEN, "warn": UiTheme.AMBER, "error": UiTheme.ROSE}.get(kind, UiTheme.BLUE) as Color
	p.add_theme_stylebox_override("panel", UiTheme.box(Color(0.06, 0.07, 0.09, 0.92), 12, col, 2, 14, 8))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := Ui.text(text, 15, Color.WHITE)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(l)
	_toasts.add_child(p)
	while _toasts.get_child_count() > 3:
		var old := _toasts.get_child(0)
		_toasts.remove_child(old)
		old.queue_free()
	var tw := p.create_tween()
	tw.tween_interval(seconds)
	tw.tween_property(p, "modulate:a", 0.0, 0.6)
	tw.tween_callback(p.queue_free)


func set_tooltip(text: String, at: Vector2) -> void:
	tooltip.text = text
	tooltip.visible = text != ""
	tooltip.position = at + Vector2(18, 12)


func toggle_help() -> void:
	help_panel.visible = not help_panel.visible
