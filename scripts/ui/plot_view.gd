class_name PlotView
extends Control
## A small instrument screen: time traces (oscilloscope), spectra with marker lines
## (vibration analyser), or a phasor star (winding analysis). Set the data, then
## queue_redraw().

const GRID := Color(0.3, 0.5, 0.45, 0.35)
const BG := Color(0.02, 0.05, 0.05)
const TRACE_COLORS := [Color("ffd75a"), Color("4fe3ff"), Color("ff7ad9"), Color("9dff8a")]

var mode := "time"          ## time | spectrum | phasor
var title := ""
## time: Array of PackedFloat32Array traces sharing the x range; spectrum: one trace.
var traces: Array = []
var trace_names: Array[String] = []
var x_range := Vector2(0.0, 1.0)
var y_range := Vector2(-1.0, 1.0)
var x_label := ""
var y_label := ""
## spectrum markers: [{f, label, color}]
var markers: Array = []
## phasor: [{angle (rad), label, color, length}]
var phasors: Array = []
var footer := ""
var divisions := Vector2i(10, 8)


func _init(size_px := Vector2(560, 300)) -> void:
	custom_minimum_size = size_px
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, BG)
	var font := get_theme_default_font()
	var fs := 15
	var plot := Rect2(Vector2(10, 26), size - Vector2(20, 52))
	if mode == "phasor":
		_draw_phasors(plot, font)
	else:
		for i in divisions.x + 1:
			var x := plot.position.x + plot.size.x * i / divisions.x
			draw_line(Vector2(x, plot.position.y), Vector2(x, plot.end.y), GRID, 1.0)
		for j in divisions.y + 1:
			var y := plot.position.y + plot.size.y * j / divisions.y
			draw_line(Vector2(plot.position.x, y), Vector2(plot.end.x, y), GRID, 1.0)
		if mode == "spectrum":
			_draw_markers(plot, font)
		for t in traces.size():
			_draw_trace(plot, traces[t], TRACE_COLORS[t % TRACE_COLORS.size()])
	var legend_x := size.x - 10.0
	var legend_w := 0.0
	for t in trace_names.size():
		legend_w += font.get_string_size(trace_names[t], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 14.0
	# the title gives way to the legend (it is clipped rather than drawn underneath)
	draw_string(font, Vector2(10, 19), title, HORIZONTAL_ALIGNMENT_LEFT, maxf(size.x - 20 - legend_w, 40.0), fs + 1, Color(0.85, 1.0, 0.95))
	for t in range(trace_names.size() - 1, -1, -1):
		var w := font.get_string_size(trace_names[t], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		legend_x -= w
		draw_string(font, Vector2(legend_x, 19), trace_names[t], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, TRACE_COLORS[t % TRACE_COLORS.size()])
		legend_x -= 14.0
	draw_string(font, Vector2(10, size.y - 8), footer, HORIZONTAL_ALIGNMENT_LEFT, size.x - 20, fs, Color(0.75, 0.9, 0.85))


func _draw_trace(plot: Rect2, data: Variant, color: Color) -> void:
	var arr: PackedFloat32Array = data
	var n := arr.size()
	if n < 2:
		return
	var pts := PackedVector2Array()
	var step := maxi(n / int(maxf(plot.size.x, 2.0)), 1)
	var i := 0
	while i < n:
		var v := arr[i]
		var y := 1.0 - (v - y_range.x) / (y_range.y - y_range.x)
		var x := float(i) / (n - 1)
		pts.append(plot.position + Vector2(x * plot.size.x, clampf(y, -0.02, 1.02) * plot.size.y))
		i += step
	draw_polyline(pts, color, 2.0, true)


func _draw_markers(plot: Rect2, font: Font) -> void:
	var row := 0
	for m: Dictionary in markers:
		var f: float = m.f
		if f < x_range.x or f > x_range.y:
			continue
		var x := plot.position.x + (f - x_range.x) / (x_range.y - x_range.x) * plot.size.x
		var c: Color = m.get("color", Color(1, 1, 1, 0.5))
		draw_dashed_line(Vector2(x, plot.position.y), Vector2(x, plot.end.y), c, 1.5, 5.0)
		draw_string(font, Vector2(x + 3, plot.position.y + 14 + 15 * (row % 3)), m.label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, c)
		row += 1


func _draw_phasors(plot: Rect2, font: Font) -> void:
	var c := plot.get_center()
	var rad := minf(plot.size.x, plot.size.y) * 0.42
	draw_arc(c, rad, 0, TAU, 64, GRID, 1.5)
	for s in 6:
		var a := TAU * s / 6.0
		draw_line(c, c + Vector2(cos(a), -sin(a)) * rad, Color(GRID, 0.2), 1.0)
	for p: Dictionary in phasors:
		var a: float = p.angle
		var tip := c + Vector2(cos(a), -sin(a)) * rad * float(p.get("length", 1.0))
		var col: Color = p.get("color", Color.WHITE)
		draw_line(c, tip, col, 3.0, true)
		draw_circle(tip, 4.0, col)
		var lab: String = p.get("label", "")
		if lab != "":
			draw_string(font, tip + Vector2(cos(a), -sin(a)) * 14.0 - Vector2(8, -5), lab, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, col)
