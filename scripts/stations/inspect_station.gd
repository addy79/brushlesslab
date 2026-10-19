extends Station
## Bench 4, inspection and repair with the motor open: count teeth and magnets, measure
## the stator with calipers, trace each coil's phase and direction, read the lead joints
## (star or delta), check every magnet with a Gauss meter or viewing film, measure shaft
## runout with a dial indicator, look for burns and debris, and do the repairs.

const TOOLS := ["Look closely", "Trace a coil", "Gauss meter", "Dial indicator", "Calipers"]

var model := MotorModel.new()
var tool := 0
var selected_magnet := -1
var glue_north := true
var dial_angle := 0.0
var _scale := 1.0
var _tool_box := VBoxContainer.new()
var _repair_box := VBoxContainer.new()
var _dial: PanelContainer
var _built_for: MotorState
var _exposed := false


func _build() -> void:
	model.name = "Motor"
	add_child(model)
	model.tooth_clicked.connect(_on_tooth)
	model.magnet_clicked.connect(_on_magnet)
	panel.add_child(Ui.title("Inspect & repair", 26))
	panel.add_child(Ui.text("With the rotor off you can see everything. Pick an inspection tool, then click teeth or magnets.", 15, UiTheme.MUTED))
	var row := Ui.flow(6)
	for i in TOOLS.size():
		var b := Ui.button(TOOLS[i], func() -> void:
			tool = i
			_rebuild_tools(), "Chip", 15)
		b.toggle_mode = true
		b.name = "Tool%d" % i
		row.add_child(b)
	panel.add_child(row)
	panel.add_child(_tool_box)
	_tool_box.add_theme_constant_override("separation", 8)
	section(panel, "Repairs")
	panel.add_child(_repair_box)
	_repair_box.add_theme_constant_override("separation", 6)


func _rotor_id() -> String:
	return "bell" if session.spec.kind == "outrunner" else "rotor"


func _build_model() -> void:
	_built_for = session.state
	_exposed = session.windings_exposed()
	model.build(session.state, {"teeth": _exposed, "magnets": _exposed, "leads": false})
	_scale = model.magnify_to(0.3)
	model.position = bench + Vector3(0.12, 0.0, -0.08)
	model.set_clickable(false)
	if _exposed:
		# only the stator (with its base or housing) and the rotor, laid out side by side
		var keep := ["stator", _rotor_id(), "base"]
		for id: String in model.parts:
			if id == "grub_screw":
				continue
			(model.parts[id] as Node3D).visible = keep.has(id)
		var r: Node3D = model.parts[_rotor_id()]
		var spec := session.spec
		if spec.kind == "outrunner":
			var y_top := 5.0 + spec.stator_h + 1.0
			r.transform = Transform3D(Basis(Vector3.RIGHT, PI), Vector3(-spec.stator_od * 1.9, y_top + 17.0, 0.0))
		else:
			r.transform = Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(-75.0, 20.0, 10.0))
		if session.guided:
			_show_traced()


func refresh() -> void:
	if _built_for != session.state or _exposed != session.windings_exposed():
		_build_model()
	else:
		model.refresh()
		if _exposed and session.guided:
			_show_traced()
	_rebuild_tools()
	_rebuild_repairs()


func _rebuild_tools() -> void:
	Ui.clear(_tool_box)
	_dial = null
	for i in TOOLS.size():
		var b := panel.find_child("Tool%d" % i, true, false) as Button
		if b:
			b.set_pressed_no_signal(i == tool)
	model.film = false
	var exposed := session.windings_exposed()
	var need := "Take the %s off at bench 2 first." % ("bell" if session.spec.kind == "outrunner" else "rotor")
	match TOOLS[tool]:
		"Look closely":
			_tool_box.add_child(Ui.button("🔍 Look over the whole motor", look_closely, "", 16))
			_tool_box.add_child(Ui.button("🔌 Lift the sleeving and look at the lead joints", inspect_joints, "", 16))
			_tool_box.add_child(Ui.text("Counting: the teeth are numbered when the stator is out; hover a magnet to see its number.", 14, UiTheme.MUTED))
		"Trace a coil":
			if not exposed:
				_tool_box.add_child(Ui.status(need, "warn", 16))
				return
			_tool_box.add_child(Ui.text("Click a tooth: you follow its wire to the lead group it belongs to and see which way it is wound. Capital = clockwise seen from the tooth tip, small = counter-clockwise.", 15))
			_tool_box.add_child(Ui.mono(_traced_text(), 22))
			_tool_box.add_child(Ui.toggle("Colour the traced coils by phase", model.phase_colors, func(on: bool) -> void: model.phase_colors = on, 15))
		"Gauss meter":
			if not exposed:
				_tool_box.add_child(Ui.status(need, "warn", 16))
				return
			_tool_box.add_child(Ui.text("Click a magnet to put the Hall probe on its face (N reads positive).", 15))
			_tool_box.add_child(Ui.toggle("Magnetic viewing film over the magnets", false, func(on: bool) -> void: model.film = on, 15))
			_tool_box.add_child(Ui.button("Sweep all magnets and record", sweep_magnets, "", 15))
			if selected_magnet >= 0:
				_tool_box.add_child(Ui.text("Selected: magnet %d" % (selected_magnet + 1), 15, UiTheme.AMBER))
		"Dial indicator":
			_tool_box.add_child(Ui.text("Indicator on the shaft tip; turn the shaft slowly:", 15))
			var row := Ui.hbox()
			row.add_child(Ui.text("Angle", 16))
			row.add_child(Ui.slider(0.0, 360.0, dial_angle, 1.0, func(v: float) -> void:
				dial_angle = v
				_update_dial(), 260))
			_tool_box.add_child(row)
			_dial = readout("", 30)
			_tool_box.add_child(_dial)
			_tool_box.add_child(Ui.button("Turn one full turn and record the runout", measure_runout, "Primary", 15))
			_update_dial()
		"Calipers":
			if not exposed and session.spec.kind == "outrunner":
				_tool_box.add_child(Ui.status(need, "warn", 16))
				return
			_tool_box.add_child(Ui.button("📏 Measure the stator and record", measure_stator, "Primary", 16))
			if session.guided:
				_tool_box.add_child(Ui.text("Hobby motors are named by stator diameter and stack height in mm: 22 mm × 12 mm → \"2212\". Industrial frames by the flange size.", 14, UiTheme.LILAC))


func _rebuild_repairs() -> void:
	Ui.clear(_repair_box)
	for o: Dictionary in session.repair_options():
		var id: String = o.id
		if id.begins_with("bearing:"):
			continue
		if id == "rewind":
			_repair_box.add_child(Ui.text("Rewinding is done at bench 5 (%s)." % ("ready: " + o.title if o.available else "needs: " + o.needs), 14, UiTheme.MUTED))
			continue
		if id == "reglue":
			var row := Ui.hbox(6)
			var b := Ui.button(o.title, do_repair.bind(id), "", 15)
			b.disabled = not o.available
			row.add_child(b)
			row.add_child(Ui.option(["N facing in", "S facing in"], 0 if glue_north else 1, func(i: int) -> void: glue_north = i == 0, 14))
			_repair_box.add_child(row)
			continue
		var btn := Ui.button(o.title + ("" if o.available else "   (%s)" % o.needs), do_repair.bind(id), "", 15)
		btn.disabled = not o.available
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		_repair_box.add_child(btn)


func do_repair(id: String) -> void:
	var polarity := 1
	if id == "reglue" and selected_magnet >= 0:
		var should_be_north := selected_magnet % 2 == 0
		polarity = 1 if glue_north == should_be_north else -1
	var r := session.do_repair(id, selected_magnet, polarity)
	say(r.text, "ok" if r.ok else "warn")
	if r.ok:
		main.sfx.play("success" if id != "reglue" else "clack")


func _on_tooth(i: int) -> void:
	if TOOLS[tool] != "Trace a coil":
		say("Tooth %d. (Pick \"Trace a coil\" to follow its wire.)" % (i + 1))
		return
	var c: Dictionary = session.state.coils[i]
	var letter: String = Winding.LETTERS[c.phase]
	if c.sign < 0:
		letter = letter.to_lower()
	_traced()[i] = letter
	var dir := "clockwise" if c.sign > 0 else "counter-clockwise"
	var group := session.spec.lead_names[c.phase].substr(0, 1)
	main.sfx.play("click")
	if _traced().size() == session.spec.slots:
		note("winding", "Traced winding (tooth 1→%d): %s" % [session.spec.slots, _traced_text()], _traced_text())
	else:
		say("Tooth %d: wire goes to lead group %s, wound %s → \"%s\"" % [i + 1, group, dir, letter])
	if session.guided:
		_show_traced()
	_rebuild_tools()


## Teeth the learner has traced (index -> letter), kept with the job.
func _traced() -> Dictionary:
	if not session.measured.has("traced"):
		session.measured["traced"] = {}
	return session.measured["traced"]


func _traced_text() -> String:
	var s := ""
	for i in session.spec.slots:
		s += _traced().get(i, "·")
	return s


## Guided: traced coils show their phase colour.
func _show_traced() -> void:
	if _traced().is_empty():
		return
	model.phase_colors = true
	for i in model.coil_nodes.size():
		if not _traced().has(i):
			model.coil_nodes[i].material_override = MeshUtil.mat("copper")
			if i < model._arrows.size():
				model._arrows[i].visible = false


func _on_magnet(k: int) -> void:
	selected_magnet = k
	if TOOLS[tool] == "Gauss meter":
		var b := session.state.magnet_field(k)
		var mt := jitter(b * 1000.0, 0.01)
		note("gauss_%d" % k, "Magnet %d: %+.0f mT (%s)" % [k + 1, mt, "N" if mt > 0.0 else ("S" if mt < 0.0 else "nothing")], mt)
	else:
		say("Magnet %d selected." % (k + 1))
	_rebuild_tools()


func sweep_magnets() -> void:
	var vals: Array[String] = []
	for k in session.spec.poles:
		vals.append("%+.0f" % jitter(session.state.magnet_field(k) * 1000.0, 0.01))
	note("gauss", "Gauss sweep (mT, magnet 1→%d): %s" % [session.spec.poles, " ".join(vals)], vals.size())


func _update_dial() -> void:
	if _dial:
		set_readout(_dial, "%.3f mm" % session.state.runout_reading(deg_to_rad(dial_angle)))
	model.set_rotor_angle(deg_to_rad(dial_angle))


func measure_runout() -> void:
	var lo := INF
	var hi := -INF
	for i in 72:
		var r := session.state.runout_reading(TAU * i / 72.0)
		lo = minf(lo, r)
		hi = maxf(hi, r)
	var tir := hi - lo
	note("runout", "Shaft runout (TIR) = %.3f mm %s" % [tir, "(OK, < 0.02 mm)" if tir < 0.02 else "(too much: bent shaft or worn bearings)"], tir)


func measure_stator() -> void:
	var s := session.spec
	if s.kind == "outrunner":
		var d := snappedf(s.stator_od + randf_range(-0.03, 0.03), 0.01)
		var h := snappedf(s.stator_h + randf_range(-0.03, 0.03), 0.01)
		note("size", "Stator Ø %.2f mm × %.2f mm stack%s" % [d, h, ("  → size code %02d%02d" % [roundi(d), roundi(h)]) if session.guided else ""], s.size_code)
	else:
		note("size", "Frame 57.0 mm square, stator stack %.1f mm, bore %.1f mm" % [s.stator_h, s.stator_bore], s.size_code)


func look_closely() -> void:
	var st := session.state
	var s := session.spec
	var seen: Array[String] = []
	if session.windings_exposed():
		for t in st.burnt_teeth:
			seen.append("the varnish on tooth %d is dark brown and smells burnt" % (t + 1))
		for k in st.magnets.size():
			var m: Dictionary = st.magnets[k]
			if not m.present:
				seen.append("magnet %d is missing" % (k + 1))
			elif m.loose:
				seen.append("magnet %d has shifted and its glue line is cracked" % (k + 1))
			elif m.cracked:
				seen.append("magnet %d is cracked" % (k + 1))
		if st.debris > 0:
			seen.append("steel grit is stuck to the magnets")
		if st.hall_dead >= 0 and not session.is_removed("hall_board"):
			seen.append("Hall sensor %s looks darkened" % ["A", "B", "C"][st.hall_dead])
		seen.append("%d teeth, %d magnets" % [s.slots, s.poles] if session.guided else "the teeth are numbered 1 to %d" % s.slots)
	else:
		seen.append("from outside you can only see the bell, the base and the leads")
	if st.open_phase >= 0:
		seen.append("lead %s's solder joint at the stator is cracked and dark" % s.lead_names[st.open_phase].substr(0, 1))
	if st.runout_mm > 0.03:
		seen.append("the shaft tip runs off-centre")
	note("look", "Looked closely: " + "; ".join(seen) + ".")


func inspect_joints() -> void:
	if not session.windings_exposed():
		say("The joints are under the sleeving at the stator: take the %s off first." % _rotor_id(), "warn")
		return
	var t := ""
	if session.state.connection == "Y":
		t = "Lead joints: each lead holds ONE coil-group start; a fourth joint, sleeved, twists three wire ends together (the star point) → star (Y)."
	else:
		t = "Lead joints: each lead holds TWO wire ends (the end of one group and the start of the next); there is no fourth joint → delta (Δ)."
	note("joints", t, session.state.connection)


func view() -> Array:
	return [bench + Vector3(0.0, 0.58, 0.72), bench + Vector3(0.0, 0.06, -0.08)]


func view_width() -> float:
	return 0.8
