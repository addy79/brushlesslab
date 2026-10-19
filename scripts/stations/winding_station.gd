extends Station
## Bench 5, rewinding: with the stator stripped, choose a letter (phase + direction) and
## click teeth to wind them. The phasor star shows each coil's EMF phasor (star of slots)
## and the three phase sums, which must be equal and 120° apart. Turns per tooth and the
## connection set KV: copy the original or the motor comes back with a different KV.

const BRUSHES := ["A", "a", "B", "b", "C", "c", "—"]

var model := MotorModel.new()
var preview: MotorState
var layout: Array = []
var brush := 0
var turns := 13
var connection := "Y"
var phasor := PlotView.new(Vector2(320, 320))
var _status := VBoxContainer.new()
var _built_for: MotorState
var _text: Label
var _editor := VBoxContainer.new()


func _build() -> void:
	persist(phasor)
	persist(_status)
	model.name = "Stator"
	add_child(model)
	model.tooth_clicked.connect(click_tooth)
	panel.add_child(Ui.title("Winding bench", 26))
	panel.add_child(Ui.text("Pick a letter, then click teeth to wind them. Capital = clockwise seen from the tooth tip, small = counter-clockwise.", 15, UiTheme.MUTED))
	panel.add_child(_editor)
	_editor.add_theme_constant_override("separation", 8)


func refresh() -> void:
	if _built_for != session.state:
		_reset_editor()
	_rebuild_editor()


func _available() -> bool:
	for o: Dictionary in session.repair_options():
		if o.id == "rewind":
			return o.available
	return false


func _reset_editor() -> void:
	_built_for = session.state
	var spec := session.spec
	turns = spec.turns
	connection = session.state.connection
	preview = MotorState.new(spec)
	layout.clear()
	for i in spec.slots:
		layout.append({"phase": 0, "sign": 1, "turns": 0})
	_apply_preview()


func _apply_preview() -> void:
	preview.coils = layout.duplicate(true)
	model.build(preview, {"teeth": true})
	model.magnify_to(0.32)
	model.position = bench + Vector3(-0.2, 0.0, -0.05)
	model.show_only(["stator"])
	model.set_clickable(false)
	for t in model.teeth:
		t.enabled = true
	model.phase_colors = true


func _rebuild_editor() -> void:
	detach_persistent()
	Ui.clear(_editor)
	var spec := session.spec
	if not _available():
		_editor.add_child(Ui.status("The stator must be stripped first: %s." % ("take the bell and the stator off at bench 2" if spec.kind == "outrunner" else "take the rotor out at bench 2"), "warn", 16))
		_editor.add_child(Ui.text("You can still plan a layout here; \"Wind it\" works once the stator is ready.", 14, UiTheme.MUTED))
	var row := Ui.flow(6)
	for i in BRUSHES.size():
		var b := Ui.button(BRUSHES[i], func() -> void:
			brush = i
			_rebuild_editor(), "Chip", 20)
		b.toggle_mode = true
		b.set_pressed_no_signal(i == brush)
		b.custom_minimum_size.x = 48
		if i < 6:
			b.add_theme_color_override("font_color", MotorModel.PHASE_COLORS[i / 2].lightened(0.2))
		row.add_child(b)
	_editor.add_child(row)
	_text = Ui.mono(Winding.to_text_partial(layout), 24)
	_editor.add_child(_text)
	var tools := Ui.flow(6)
	tools.add_child(Ui.button("Strip all", strip_all, "Ghost", 15))
	var traced: String = session.measured.get("winding", "")
	if traced is String and traced.length() == spec.slots and not traced.contains("·"):
		tools.add_child(Ui.button("Copy my traced layout", set_layout_text.bind(traced), "Ghost", 15))
	if session.guided:
		tools.add_child(Ui.button("Suggest (star of slots)", set_layout_text.bind(Winding.to_text(Winding.design(spec.slots, spec.poles))), "Ghost", 15))
	_editor.add_child(tools)
	var trow := Ui.hbox()
	trow.add_child(Ui.text("Turns per tooth", 16))
	trow.add_child(Ui.spin(1, 120, turns, 1, func(v: float) -> void:
		turns = int(v)
		for c: Dictionary in layout:
			if c.turns > 0:
				c.turns = turns
		_update_status()))
	_editor.add_child(trow)
	var crow := Ui.hbox()
	crow.add_child(Ui.text("Connection", 16))
	crow.add_child(Ui.option(["Y (star)", "Δ (delta)"], 0 if connection == "Y" else 1, func(i: int) -> void:
		connection = ["Y", "D"][i]
		_update_status()))
	_editor.add_child(crow)
	_editor.add_child(Ui.text("Wire: %.2f mm × %d strand%s, same as the original." % [spec.wire_d, spec.strands, "s" if spec.strands > 1 else ""], 14, UiTheme.MUTED))
	_editor.add_child(phasor)
	_editor.add_child(_status)
	var wind := Ui.button("Wind it (varnish and bake)", wind_it, "Primary", 18)
	wind.disabled = not _available()
	_editor.add_child(wind)
	_update_status()


func click_tooth(i: int) -> void:
	if BRUSHES[brush] == "—":
		layout[i] = {"phase": 0, "sign": 1, "turns": 0}
	else:
		var ch: String = BRUSHES[brush]
		layout[i] = {"phase": Winding.LETTERS.find(ch.to_upper()), "sign": 1 if ch == ch.to_upper() else -1, "turns": turns}
	main.sfx.play("click")
	_after_edit()


func strip_all() -> void:
	for i in layout.size():
		layout[i] = {"phase": 0, "sign": 1, "turns": 0}
	_after_edit()


func set_layout_text(text: String) -> void:
	var coils := Winding.from_text(text, turns)
	if coils.size() != layout.size():
		say("That layout has %d letters; this stator has %d teeth." % [coils.size(), layout.size()], "warn")
		return
	layout = coils
	_after_edit()


func _after_edit() -> void:
	preview.coils = layout.duplicate(true)
	model.phase_colors = true
	if _text:
		_text.text = Winding.to_text_partial(layout)
	_update_status()


func _update_status() -> void:
	var spec := session.spec
	Ui.clear(_status)
	# phasor star: each wound tooth's phasor, then the phase sums
	phasor.mode = "phasor"
	phasor.title = "Star of slots (electrical)"
	phasor.phasors.clear()
	var sums := [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
	var n := 0
	for i in layout.size():
		var c: Dictionary = layout[i]
		if c.turns <= 0:
			continue
		var a := deg_to_rad(Winding.tooth_angle(i, spec.slots, spec.poles)) + (PI if c.sign < 0 else 0.0)
		phasor.phasors.append({"angle": a, "label": str(i + 1), "color": Color(MotorModel.PHASE_COLORS[c.phase], 0.55), "length": 0.62})
		sums[c.phase] += Vector2(cos(a), sin(a))
		n += 1
	var biggest := maxf(maxf(sums[0].length(), sums[1].length()), maxf(sums[2].length(), 0.001))
	for p in 3:
		if sums[p].length() > 0.01:
			phasor.phasors.append({"angle": sums[p].angle(), "label": Winding.LETTERS[p], "color": MotorModel.PHASE_COLORS[p], "length": sums[p].length() / biggest})
	phasor.footer = "%d of %d teeth wound" % [n, spec.slots]
	phasor.queue_redraw()
	var issues: Array[String] = []
	if n == spec.slots:
		issues = Winding.check(layout, spec.slots, spec.poles)
	else:
		issues.append("%d of %d teeth wound" % [n, spec.slots])
	if n == spec.slots:
		var kw := Winding.winding_factor(layout, spec.slots, spec.poles)
		_status.add_child(Ui.text("Winding factor %.3f" % kw, 15))
	if issues.is_empty():
		_status.add_child(Ui.status("✔ Balanced three-phase winding.", "ok", 16))
	else:
		for s in issues:
			_status.add_child(Ui.status("✘ " + s, "error" if n == spec.slots else "info", 15))
	if turns != spec.turns or connection != spec.connection:
		var k := float(spec.turns) / turns * (sqrt(3.0) if connection == "D" and spec.connection == "Y" else (1.0 / sqrt(3.0) if connection == "Y" and spec.connection == "D" else 1.0))
		_status.add_child(Ui.status("⚠ The original had %d turns, %s. This gives about %.0f KV instead of %.0f." % [spec.turns, "star" if spec.connection == "Y" else "delta", spec.kv * k, spec.kv], "warn", 15))


func wind_it() -> void:
	if not _available():
		say("Strip the stator first.", "warn")
		return
	var r := session.rewind(layout.duplicate(true), connection)
	main.sfx.play("success" if r.ok else "error")
	if r.ok:
		say("Wound, varnished and baked: %s, %d turns, %s." % [Winding.to_text(layout), turns, "star" if connection == "Y" else "delta"], "ok")
	else:
		say("Wound, but: %s" % "; ".join(r.issues), "error")


func view() -> Array:
	return [bench + Vector3(-0.15, 0.6, 0.66), bench + Vector3(-0.15, 0.07, -0.05)]


func view_width() -> float:
	return 0.6
