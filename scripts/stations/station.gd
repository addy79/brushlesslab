class_name Station
extends Node3D
## One bench of the workshop. A station builds its 3D content (the motor as this bench
## needs it, instruments, tools) at `bench`, and its 2D panel into `panel` (shown in the
## desktop drawer or on a VR panel next to the bench). It reads and writes the shared
## Session; when the session changes, `refresh()` updates the panel.

signal message(text: String, kind: String)

var main: Main
var session: Session
var title := ""
var subtitle := ""
## World position of the bench centre (top surface).
var bench := Vector3.ZERO
## The station's 2D interface (re-parented between the desktop drawer and the VR panel).
var panel := VBoxContainer.new()


func setup(p_main: Main, index: int) -> void:
	main = p_main
	session = main.session
	bench = Main.bench_position(index)
	panel.add_theme_constant_override("separation", 10)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_build()
	refresh()


var _persistent: Array[Control] = []


## Widgets that survive panel rebuilds (plots): call detach_persistent() before Ui.clear.
func persist(c: Control) -> Control:
	_persistent.append(c)
	return c


func detach_persistent() -> void:
	for c in _persistent:
		if c.get_parent():
			c.get_parent().remove_child(c)


func _exit_tree() -> void:
	for c in _persistent:
		if is_instance_valid(c) and not c.is_inside_tree() and c.get_parent() == null:
			c.queue_free()


## Builds 3D content and the panel. Override.
func _build() -> void:
	pass


## Updates the panel and visuals after the session changed. Override.
func refresh() -> void:
	pass


## Called before the station is removed.
func teardown() -> void:
	pass


## Desktop camera: [position, look-at target].
func view() -> Array:
	return [bench + Vector3(0.0, 0.42, 0.62), bench + Vector3(0.0, 0.05, -0.05)]


## Width (m) of the bench area the desktop view must show around the view target.
func view_width() -> float:
	return 0.9


## Where the learner stands in VR (floor point).
func xr_position() -> Vector3:
	return Vector3(bench.x, 0.0, bench.z + 0.55)


func say(text: String, kind := "info") -> void:
	message.emit(text, kind)


## Writes to the notebook and tells the learner.
func note(key: String, text: String, value: Variant = null) -> void:
	session.note(key, text, value)
	say(text, "info")


## A "section" header row in the panel.
func section(parent: Control, text: String) -> Label:
	var l := Ui.title(text, 19, UiTheme.BLUE)
	parent.add_child(l)
	return l


## Small coloured value readout ("display") used by instruments.
static func readout(text: String, size := 30, color := Color("9ff0c8")) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiTheme.box(Color(0.02, 0.05, 0.05), 8, Color(0.3, 0.6, 0.5, 0.4), 1, 12, 6))
	var l := Ui.mono(text, size, color)
	l.name = "Value"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	p.add_child(l)
	return p


static func set_readout(p: PanelContainer, text: String, color := Color("9ff0c8")) -> void:
	var l := p.get_node("Value") as Label
	l.text = text
	l.add_theme_color_override("font_color", color)


## Small noise as a real instrument shows (fraction of the value).
func jitter(value: float, frac: float) -> float:
	return value * (1.0 + randf_range(-frac, frac))


## Engineering formatting: 0.1052 → "105.2 m", 3.4e-5 → "34.0 µ".
static func eng(v: float, unit: String, digits := 1) -> String:
	if is_inf(v):
		return "OL"
	var a := absf(v)
	var fmt := "%." + str(digits) + "f %s%s"
	if a >= 1e6:
		return fmt % [v / 1e6, "M", unit]
	if a >= 1e3:
		return fmt % [v / 1e3, "k", unit]
	if a >= 1.0 or a == 0.0:
		return fmt % [v, "", unit]
	if a >= 1e-3:
		return fmt % [v * 1e3, "m", unit]
	if a >= 1e-6:
		return fmt % [v * 1e6, "µ", unit]
	return fmt % [v * 1e9, "n", unit]
