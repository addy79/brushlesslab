extends Station
## Bench 3, electrical tests on the three leads: resistance (cheap multimeter vs 4-wire
## milliohm meter), inductance (LCR meter at 1 kHz), insulation to the frame (500 V
## megger), back-EMF with a drill and an oscilloscope (gives KV and the pole count), and
## the Hall sensors (sensored motors). Readings come from the motor's condition.

const INSTRUMENTS := ["Milliohm meter (4-wire)", "Multimeter (2-wire)", "LCR meter, 1 kHz", "Insulation tester 500 V", "Drill + oscilloscope (back-EMF)", "Hall sensor tester"]
const PAIRS := [[0, 1], [1, 2], [2, 0]]
const PAIR_KEYS := ["AB", "BC", "CA"]

var model := MotorModel.new()
var instrument := 0
var pair := 0
var drill_rpm := 2000.0
var hall_angle := 0.0
var scope := PlotView.new(Vector2(560, 300))
var panel_scope := PlotView.new(Vector2(320, 220))
var _scope_vp := SubViewport.new()
var _display := Label3D.new()
var _probe_red := MeshInstance3D.new()
var _probe_black := MeshInstance3D.new()
var _inst_box := VBoxContainer.new()
var _inst_option: OptionButton
var _reading: PanelContainer
var _hall_leds: Array[Label] = []
var _t := 0.0
var _last_vpk: Array[float] = [0.0, 0.0, 0.0]


func _build() -> void:
	persist(panel_scope)
	model.name = "Motor"
	add_child(model)
	model.lead_clicked.connect(_on_lead)
	_build_model()
	# bench instrument (one box with a display) and the scope with a live screen
	var box := MeshUtil.box(Vector3(0.24, 0.1, 0.16), MeshUtil.colored(Color(0.85, 0.65, 0.15), 0.1, 0.6), bench + Vector3(0.12, 0.05, -0.12))
	add_child(box)
	add_child(MeshUtil.box(Vector3(0.2, 0.05, 0.004), MeshUtil.colored(Color(0.05, 0.08, 0.06), 0.0, 0.3), bench + Vector3(0.12, 0.065, -0.038)))
	_display.font = MeshUtil.math_font()
	_display.font_size = 40
	_display.pixel_size = 0.0007
	_display.modulate = Color("9ff0c8")
	_display.outline_size = 0
	_display.position = bench + Vector3(0.12, 0.065, -0.035)
	add_child(_display)
	var scope_body := MeshUtil.box(Vector3(0.42, 0.26, 0.2), MeshUtil.colored(Color(0.2, 0.22, 0.25), 0.3, 0.5), bench + Vector3(0.55, 0.13, -0.18))
	add_child(scope_body)
	_scope_vp.size = Vector2i(560, 300)
	_scope_vp.disable_3d = true
	_scope_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_scope_vp)
	_scope_vp.add_child(scope)
	scope.size = Vector2(560, 300)
	var screen := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.34, 0.182)
	screen.mesh = q
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.albedo_texture = _scope_vp.get_texture()
	screen.material_override = sm
	screen.position = bench + Vector3(0.53, 0.14, -0.078)
	add_child(screen)
	for p: MeshInstance3D in [_probe_red, _probe_black]:
		var sph := SphereMesh.new()
		sph.radius = 0.012
		sph.height = 0.024
		p.mesh = sph
		p.material_override = MeshUtil.colored(Color(0.9, 0.1, 0.1) if p == _probe_red else Color(0.05, 0.05, 0.05), 0.0, 0.4)
		add_child(p)
	# --- panel ---
	panel.add_child(Ui.title("Electrical tests", 26))
	panel.add_child(Ui.text("Probe the three leads (click a lead on the motor, or pick a pair). Everything you read goes into the notebook with \"Record\".", 15, UiTheme.MUTED))
	var names: Array = INSTRUMENTS.duplicate()
	if not session.spec.has_halls:
		names.pop_back()
	_inst_option = Ui.option(names, instrument, func(i: int) -> void:
		instrument = i
		_rebuild_instrument())
	panel.add_child(_inst_option)
	panel.add_child(_inst_box)
	_inst_box.add_theme_constant_override("separation", 8)
	_rebuild_instrument()


func view() -> Array:
	return [bench + Vector3(0.05, 0.6, 0.82), bench + Vector3(0.05, 0.06, -0.1)]


func view_width() -> float:
	return 1.15


func _build_model() -> void:
	model.build(session.state, {"leads": true})
	model.magnify_to(0.2)
	model.position = bench + Vector3(-0.4, 0.0, -0.05)
	model.rotation.y = 0.35
	model.set_clickable(false)


func _on_lead(k: int) -> void:
	# red probe goes on the clicked lead, black on the one that had red before
	var a: int = PAIRS[pair][0]
	if k == a:
		return
	for i in 3:
		if PAIRS[i][0] == k and PAIRS[i][1] == a or PAIRS[i][0] == a and PAIRS[i][1] == k:
			pair = i
	main.sfx.play("click")
	_rebuild_instrument()


func refresh() -> void:
	if model.state != session.state:
		_build_model()
		_rebuild_instrument()


func _rotor_on() -> bool:
	var plan := TeardownPlan.order(session.spec)
	for id: String in plan:
		if id == "stator" or id == "prop_adapter" or id == "circlip" or id == "shim" or id == "bolts" or id == "wave_washer" or id == "hall_board":
			continue
		if session.is_removed(id):
			return false
	return true


func _rebuild_instrument() -> void:
	detach_persistent()
	Ui.clear(_inst_box)
	if _inst_option:
		_inst_option.selected = instrument
	_hall_leds.clear()
	var spec := session.spec
	var name: String = INSTRUMENTS[instrument]
	if name.begins_with("Milliohm") or name.begins_with("Multimeter") or name.begins_with("LCR"):
		_pair_row()
		_reading = readout("", 34)
		_inst_box.add_child(_reading)
		_inst_box.add_child(Ui.button("Record this reading", record, "Primary", 16))
		if name.begins_with("Multimeter") and session.guided:
			_inst_box.add_child(Ui.text("A normal multimeter adds its own test-lead resistance (~0.2–0.3 Ω) and shows 0.1 Ω steps: useless for windings of a tenth of an ohm. Use the 4-wire milliohm meter.", 14, UiTheme.LILAC))
		if name.begins_with("LCR") and session.guided:
			_inst_box.add_child(Ui.text("Shorted turns act like a shorted transformer winding: the inductance of the pairs that include the damaged phase drops much more than their resistance.", 14, UiTheme.LILAC))
	elif name.begins_with("Insulation"):
		_inst_box.add_child(Ui.text("One probe on lead A, the other on the bare metal of the frame. 500 V DC for 60 s.", 15))
		_reading = readout("", 34)
		_inst_box.add_child(_reading)
		_inst_box.add_child(Ui.button("Test and record", record, "Primary", 16))
		if session.guided:
			_inst_box.add_child(Ui.text("A healthy winding reads thousands of MΩ. Below ~100 MΩ the insulation is damaged; below 1 MΩ a drive will trip on ground fault.", 14, UiTheme.LILAC))
	elif name.begins_with("Drill"):
		if not _rotor_on():
			_inst_box.add_child(Ui.status("Put the rotor (bell) and its bearings back first: the drill spins the shaft.", "warn", 16))
			_reading = null
			return
		var max_rpm := 3000.0 if spec.kind == "outrunner" else 1500.0
		drill_rpm = minf(drill_rpm, max_rpm)
		var row := Ui.hbox()
		row.add_child(Ui.text("Drill speed", 16))
		row.add_child(Ui.slider(300.0, max_rpm, drill_rpm, 50.0, func(v: float) -> void: drill_rpm = v, 260))
		_inst_box.add_child(row)
		_reading = readout("", 22)
		_inst_box.add_child(_reading)
		_inst_box.add_child(panel_scope)
		_inst_box.add_child(Ui.button("Record tach + scope readings", record, "Primary", 16))
		if session.guided:
			_inst_box.add_child(Ui.text("KV = rpm ÷ peak line-to-line volts. Electrical frequency f = rpm/60 × pole pairs, so pole pairs = 60·f ÷ rpm. Uneven peaks mean a weak, flipped or missing magnet.", 14, UiTheme.LILAC))
	elif name.begins_with("Hall"):
		if session.is_removed("hall_board"):
			_inst_box.add_child(Ui.status("The Hall board is off the motor. Fit it back (bench 2) to test it.", "warn", 16))
			_reading = null
			return
		_inst_box.add_child(Ui.text("5 V on the Hall supply, LEDs on the three outputs. Turn the shaft slowly by hand:", 15))
		var row := Ui.hbox()
		row.add_child(Ui.text("Shaft angle", 16))
		row.add_child(Ui.slider(0.0, 360.0, hall_angle, 1.0, func(v: float) -> void:
			hall_angle = v
			model.set_rotor_angle(deg_to_rad(v)), 280))
		_inst_box.add_child(row)
		var leds := Ui.hbox(14)
		for k in 3:
			var l := Ui.title("● H%s" % ["A", "B", "C"][k], 26, UiTheme.MUTED)
			leds.add_child(l)
			_hall_leds.append(l)
		_inst_box.add_child(leds)
		_reading = readout("", 22)
		_inst_box.add_child(_reading)
		_inst_box.add_child(Ui.button("Sweep one turn and record", record, "Primary", 16))
		if session.guided:
			_inst_box.add_child(Ui.text("Every sensor must switch on and off as the magnets pass. A healthy set gives six codes per electrical turn and never 000 or 111.", 14, UiTheme.LILAC))
	_update_probes()


func _pair_row() -> void:
	var row := Ui.hbox(6)
	row.add_child(Ui.text("Leads", 16))
	for i in 3:
		var b := Ui.button(PAIR_KEYS[i].insert(1, "–"), func() -> void:
			pair = i
			_rebuild_instrument(), "Chip", 16)
		b.toggle_mode = true
		b.set_pressed_no_signal(i == pair)
		row.add_child(b)
	_inst_box.add_child(row)


func _update_probes() -> void:
	var name: String = INSTRUMENTS[instrument]
	var tips := model.lead_tips
	if tips.size() < 3:
		return
	var a: int = PAIRS[pair][0]
	var b: int = PAIRS[pair][1]
	_probe_red.visible = not name.begins_with("Drill") and not name.begins_with("Hall")
	_probe_black.visible = _probe_red.visible
	if name.begins_with("Insulation"):
		_probe_red.global_position = tips[0].global_position
		_probe_black.global_position = model.frame_point.global_position
	else:
		_probe_red.global_position = tips[a].global_position
		_probe_black.global_position = tips[b].global_position


## The instrument's current reading as text (with realistic resolution and noise).
func reading() -> String:
	var st := session.state
	var a: int = PAIRS[pair][0]
	var b: int = PAIRS[pair][1]
	var name: String = INSTRUMENTS[instrument]
	if name.begins_with("Milliohm"):
		var r := st.resistance_ll(a, b)
		return "OL" if is_inf(r) else "%.1f mΩ" % (jitter(r, 0.002) * 1000.0)
	if name.begins_with("Multimeter"):
		var r := st.resistance_ll(a, b)
		return "OL" if is_inf(r) else "%.1f Ω" % snappedf(r + 0.25 + randf_range(-0.05, 0.05), 0.1)
	if name.begins_with("LCR"):
		var l := st.inductance_ll(a, b, 0.0)
		return "OL" if is_inf(st.resistance_ll(a, b)) else eng(jitter(l, 0.004), "H", 1)
	if name.begins_with("Insulation"):
		var ir := st.insulation(0)
		return "> 2000 MΩ" if ir >= 2000.0 else ("%.0f MΩ" % ir if ir >= 1.0 else "%.2f MΩ  ⚠" % ir)
	return ""


func _process(delta: float) -> void:
	_t += delta
	var name: String = INSTRUMENTS[instrument]
	if _reading == null:
		_display.text = "---"
		return
	if name.begins_with("Drill"):
		_update_scope()
	elif name.begins_with("Hall"):
		_update_halls()
	elif int(_t * 4.0) != int((_t - delta) * 4.0):
		var r := reading()
		set_readout(_reading, r, Color("ff8a8a") if r == "OL" or r.contains("⚠") else Color("9ff0c8"))
		_display.text = r


func _update_scope() -> void:
	var st := session.state
	var spec := session.spec
	var w := drill_rpm * TAU / 60.0
	var pp := spec.pole_pairs()
	var f_e := drill_rpm / 60.0 * pp
	# time base: about two electrical cycles
	var span := 2.0 / f_e
	var n := 400
	var traces: Array = []
	var theta0 := fmod(_t * w, TAU)
	var vmax := 0.0
	for p in 3:
		var arr := PackedFloat32Array()
		arr.resize(n)
		for i in n:
			var th := theta0 + w * span * i / n
			arr[i] = st.mag.line_emf(p, th, w)
			vmax = maxf(vmax, absf(arr[i]))
		traces.append(arr)
	# peak over a full mechanical turn (the scope's Vpk measurement over many cycles)
	var pk := st.emf_peaks(drill_rpm)
	for p in 3:
		_last_vpk[p] = jitter(pk[p], 0.003)
	var vdiv := _nice(maxf(vmax, 0.05) * 2.4 / 8.0)
	for plot: PlotView in [scope, panel_scope]:
		plot.traces = traces
		plot.trace_names.assign(["A–B", "B–C", "C–A"])
		plot.y_range = Vector2(-4.0 * vdiv, 4.0 * vdiv)
		plot.title = "%s/div  %s/div" % [eng(vdiv, "V", 2), eng(span / 10.0, "s", 2)]
		plot.footer = "Vpk %.3f / %.3f / %.3f V   f = %.1f Hz" % [_last_vpk[0], _last_vpk[1], _last_vpk[2], jitter(f_e, 0.002)]
		plot.queue_redraw()
	var tach := jitter(drill_rpm, 0.002)
	set_readout(_reading, "Tach %.0f rpm" % tach)
	_display.text = "%.0f rpm" % tach
	model.set_rotor_angle(theta0)


static func _nice(v: float) -> float:
	var e := pow(10.0, floor(log(v) / log(10.0)))
	for m in [1.0, 2.0, 5.0, 10.0]:
		if v <= m * e:
			return m * e
	return 10.0 * e


func _update_halls() -> void:
	var st := session.state
	var th := deg_to_rad(hall_angle)
	for k in 3:
		var on := st.hall(k, th)
		_hall_leds[k].add_theme_color_override("font_color", Color(0.3, 1.0, 0.4) if on else Color(0.25, 0.28, 0.3))
	set_readout(_reading, "code %d%d%d" % [int(st.hall(0, th)), int(st.hall(1, th)), int(st.hall(2, th))])
	_display.text = "H %d%d%d" % [int(st.hall(0, th)), int(st.hall(1, th)), int(st.hall(2, th))]


## Writes the current measurement into the notebook.
func record() -> void:
	var st := session.state
	var spec := session.spec
	var name: String = INSTRUMENTS[instrument]
	var key: String = PAIR_KEYS[pair]
	var leads := "%s–%s" % [spec.lead_names[PAIRS[pair][0]].substr(0, 1), spec.lead_names[PAIRS[pair][1]].substr(0, 1)]
	if name.begins_with("Milliohm"):
		var r := st.resistance_ll(PAIRS[pair][0], PAIRS[pair][1])
		var text := reading()
		note("R_" + key, "R %s = %s (at %.0f °C)" % [leads, text, st.winding_temp], INF if is_inf(r) else jitter(r, 0.002))
	elif name.begins_with("Multimeter"):
		note("DMM_" + key, "Multimeter %s: %s (includes test leads)" % [leads, reading()])
	elif name.begins_with("LCR"):
		var l := st.inductance_ll(PAIRS[pair][0], PAIRS[pair][1], 0.0)
		note("L_" + key, "L %s = %s at 1 kHz" % [leads, reading()], l)
	elif name.begins_with("Insulation"):
		note("IR", "Insulation lead → frame at 500 V: %s" % reading(), st.insulation(0))
	elif name.begins_with("Drill"):
		var pp := spec.pole_pairs()
		var f := jitter(drill_rpm / 60.0 * pp, 0.002)
		var tach := jitter(drill_rpm, 0.002)
		note("emf", "Drill %.0f rpm: Vpk A–B %.3f, B–C %.3f, C–A %.3f V; f = %.1f Hz" % [tach, _last_vpk[0], _last_vpk[1], _last_vpk[2], f], _last_vpk[0])
		var kv := tach / maxf(_last_vpk[0], 1e-6)
		session.measured["KV"] = kv
		session.measured["pole_pairs"] = 60.0 * f / tach
		if session.guided:
			note("KV", "→ KV ≈ %.0f / %.3f = %.0f rpm/V; pole pairs ≈ 60 × %.1f / %.0f = %.1f → %d magnets" % [tach, _last_vpk[0], kv, f, tach, 60.0 * f / tach, roundi(60.0 * f / tach) * 2], kv)
	elif name.begins_with("Hall"):
		var codes := {}
		var toggles := [{}, {}, {}]
		for i in 360:
			var th := TAU * i / 360.0
			codes[st.hall_code(th)] = true
			for k in 3:
				toggles[k][st.hall(k, th)] = true
		var dead: Array[String] = []
		for k in 3:
			if toggles[k].size() < 2:
				dead.append("H" + ["A", "B", "C"][k])
		var t := "Hall sweep: %d different codes%s" % [codes.size(), ("; %s stuck %s" % [", ".join(dead), "high"]) if not dead.is_empty() else "; all three toggle"]
		note("halls", t, dead.size())
	main.sfx.play("click")
