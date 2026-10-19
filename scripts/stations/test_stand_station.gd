extends Station
## Bench 6, the test stand: the motor on a thrust/torque stand, driven by a six-step ESC
## (DriveSim). Live speed, current, power, thrust, temperature, the scope on lead A, the
## vibration spectrum (with shaft and bearing markers) and its envelope, the ISO 10816
## zone, the motor's sound, and the final test that a repaired motor must pass.
##
## The simulation is expensive (20 µs steps), so it runs inside a time budget per frame;
## on slow hardware it runs in slow motion and says so. Standalone headsets start in the
## cheaper "fast" model (DriveSim.fast); a desktop that falls behind switches to it too.

const VIEWS := ["Lead A voltage", "Lead A current", "Vibration spectrum", "Envelope spectrum (bearings)"]
const FINAL_SECONDS := 3.0
const MIX_RATE := 22050.0

var model := MotorModel.new()
var sim: DriveSim
var view_index := 2
var plot := PlotView.new(Vector2(320, 240))
var monitor_plot := PlotView.new(Vector2(560, 300))
## Real seconds of CPU allowed per frame for the simulation.
var budget_ms := 7.0
## Simulated seconds per real second (1 = real time).
var sim_rate := 1.0
## Use DriveSim's fast model (100 µs steps, in-sync ESC).
var fast_mode := OS.has_feature("android")
var _behind_t := 0.0
var final_running := false
var final_t := 0.0
var last_final := {}

var _monitor_vp := SubViewport.new()
var _prop := Node3D.new()
var _blur := MeshInstance3D.new()
var _readouts := {}
var _controls := VBoxContainer.new()
var _results := VBoxContainer.new()
var _throttle_slider: HSlider
var _plot_t := 0.0
var _spec_t := 0.0
var _spectrum := {}
var _vib := 0.0
var _player := AudioStreamPlayer.new()
var _playback: AudioStreamGeneratorPlayback
var _phase := 0.0
var _phase2 := 0.0
var _abuf := 0.0
var _built_for: MotorState
var _final_start := 0.0


func _build() -> void:
	persist(plot)
	budget_ms = 4.0 if OS.has_feature("android") else 7.0
	model.name = "Motor"
	add_child(model)
	_build_stand()
	_monitor_vp.size = Vector2i(560, 300)
	_monitor_vp.disable_3d = true
	_monitor_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_monitor_vp)
	_monitor_vp.add_child(monitor_plot)
	monitor_plot.size = Vector2(560, 300)
	var screen := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.44, 0.235)
	screen.mesh = q
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.albedo_texture = _monitor_vp.get_texture()
	screen.material_override = sm
	screen.position = bench + Vector3(0.48, 0.42, -0.3)
	screen.rotation.y = -0.35
	add_child(screen)
	add_child(MeshUtil.box(Vector3(0.48, 0.28, 0.03), MeshUtil.colored(Color(0.1, 0.1, 0.12), 0.2, 0.5), bench + Vector3(0.485, 0.42, -0.318)))
	(get_child(get_child_count() - 1) as Node3D).rotation.y = -0.35
	add_child(MeshUtil.box(Vector3(0.03, 0.3, 0.03), MeshUtil.colored(Color(0.1, 0.1, 0.12), 0.2, 0.5), bench + Vector3(0.5, 0.15, -0.33)))
	# sound
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = MIX_RATE
	gen.buffer_length = 0.15
	_player.stream = gen
	_player.volume_db = -10.0
	add_child(_player)
	_player.play()
	_playback = _player.get_stream_playback()
	# --- panel ---
	panel.add_child(Ui.title("Test stand", 26))
	panel.add_child(_controls)
	_controls.add_theme_constant_override("separation", 8)
	panel.add_child(_results)


func _build_stand() -> void:
	var alu := MeshUtil.mat("aluminium")
	add_child(MeshUtil.box(Vector3(0.36, 0.02, 0.3), MeshUtil.colored(Color(0.15, 0.16, 0.18), 0.4, 0.5), bench + Vector3(-0.1, 0.01, -0.05)))
	# back bracket and safety cage hoops around the prop plane
	add_child(MeshUtil.box(Vector3(0.2, 0.12, 0.012), alu, bench + Vector3(-0.1, 0.07, -0.19)))
	var cage := MeshUtil.colored(Color(0.85, 0.85, 0.2, 0.35), 0.0, 0.5)
	cage.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for dx in [-0.17, 0.17]:
		add_child(MeshUtil.box(Vector3(0.008, 0.4, 0.008), alu, bench + Vector3(-0.1 + dx, 0.2, -0.19)))
	# load cell
	add_child(MeshUtil.box(Vector3(0.06, 0.02, 0.1), MeshUtil.colored(Color(0.75, 0.75, 0.78), 0.8, 0.3), bench + Vector3(-0.1, 0.03, -0.05)))
	# ESC and battery
	add_child(MeshUtil.box(Vector3(0.05, 0.012, 0.03), MeshUtil.colored(Color(0.1, 0.3, 0.6), 0.0, 0.6), bench + Vector3(0.18, 0.006, 0.05)))
	add_child(MeshUtil.box(Vector3(0.14, 0.04, 0.05), MeshUtil.colored(Color(0.2, 0.2, 0.22), 0.0, 0.6), bench + Vector3(0.18, 0.02, 0.15)))
	var label := MeshUtil.label("⚠ keep clear of the prop plane", 28, false)
	label.pixel_size = 0.0012
	label.modulate = Color(0.95, 0.75, 0.2)
	label.outline_size = 0
	label.rotation.x = -PI * 0.5
	label.position = bench + Vector3(-0.1, 0.022, 0.13)
	add_child(label)


func _build_model() -> void:
	_built_for = session.state
	model.build(session.state)
	model.magnify_to(0.16)
	model.position = bench + Vector3(-0.1, 0.04, -0.05)
	model.set_clickable(false)
	sim = DriveSim.new(session.state)
	sim.fast = fast_mode
	sim.tripped.connect(func(reason: String) -> void:
		say("ESC: " + reason, "error")
		_rebuild_controls())
	_spectrum = {}
	_vib = 0.0
	_add_load_visuals()


func _add_load_visuals() -> void:
	if _prop.get_parent():
		_prop.get_parent().remove_child(_prop)
	for c in _prop.get_children():
		c.queue_free()
	if model.spinning == null:
		return
	var spec := session.spec
	if spec.load == "prop":
		var y := 5.0 + spec.stator_h + 1.0 + 12.0
		var blade := MeshUtil.colored(Color(0.08, 0.08, 0.09), 0.0, 0.4)
		# the prop is drawn at a third of its 254 mm span so it fits the magnified view
		for s in [-1, 1]:
			var b := MeshUtil.box(Vector3(36.0, 1.0, 7.0), blade, Vector3(s * 20.0, y, 0))
			b.rotation.x = 0.3 * s
			_prop.add_child(b)
		_prop.add_child(MeshUtil.cylinder(4.0, 4.0, blade, Vector3(0, y, 0)))
		var disc := CylinderMesh.new()
		disc.top_radius = 39.0
		disc.bottom_radius = 39.0
		disc.height = 0.5
		_blur.mesh = disc
		_blur.material_override = MeshUtil.flat_material(Color(0.1, 0.1, 0.12, 0.25))
		_blur.position = Vector3(0, y, 0)
		model.add_child(_blur)
	else:
		var y := spec.stator_h + 14.0 + 6.0 + 26.0
		_prop.add_child(MeshUtil.cylinder(26.0, 6.0, MeshUtil.mat("dark_steel"), Vector3(0, y, 0)))
		_prop.add_child(MeshUtil.box(Vector3(6.0, 6.2, 10.0), MeshUtil.colored(Color(0.9, 0.9, 0.9), 0.0, 0.5), Vector3(22.0, y, 0)))
	model.spinning.add_child(_prop)
	_blur.visible = false
	_prop.visible = spec.load != "prop" or sim.prop_on


func refresh() -> void:
	if _built_for != session.state:
		_build_model()
	_rebuild_controls()


func _rebuild_controls() -> void:
	detach_persistent()
	Ui.clear(_controls)
	_readouts.clear()
	var spec := session.spec
	if not session.is_assembled():
		_controls.add_child(Ui.status("The motor is not fully assembled. Put every part back at bench 2 (next: %s) before running it." % session.next_on().replace("_", " "), "warn", 16))
		return
	_controls.add_child(Ui.text("%s on a %s. Supply %.1f V%s." % [spec.name, "six-step sensorless ESC" if not spec.has_halls else "Hall-sensored drive", sim.supply_v, " (3S LiPo)" if spec.supply_v < 12.0 else ""], 15, UiTheme.MUTED))
	var row := Ui.flow(6)
	var arm := Ui.button("▶ Arm and run" if not sim.armed else "■ Stop", toggle_run, "Primary", 17)
	row.add_child(arm)
	if spec.load == "prop":
		row.add_child(Ui.toggle("Propeller 10×4.5", sim.prop_on, func(on: bool) -> void:
			sim.prop_on = on
			_prop.visible = on, 15))
	row.add_child(Ui.toggle("Fast simulation", fast_mode, set_fast, 15))
	_controls.add_child(row)
	var trow := Ui.hbox()
	trow.add_child(Ui.text("Throttle", 16))
	_throttle_slider = Ui.slider(0.0, 1.0, sim.throttle, 0.01, func(v: float) -> void: sim.throttle = v, 300)
	trow.add_child(_throttle_slider)
	_controls.add_child(trow)
	if spec.load == "brake":
		var brow := Ui.hbox()
		brow.add_child(Ui.text("Brake (N·m)", 16))
		brow.add_child(Ui.slider(0.0, 0.4, sim.brake_torque, 0.01, func(v: float) -> void: sim.brake_torque = v, 260))
		_controls.add_child(brow)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 6)
	for key in ["rpm", "current", "power", "thrust", "temp", "vib"]:
		var r := readout("", 20)
		r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(r)
		_readouts[key] = r
	_controls.add_child(grid)
	var state_l := Ui.text("", 15, UiTheme.MUTED)
	_controls.add_child(state_l)
	_readouts["state"] = state_l
	_controls.add_child(Ui.option(VIEWS, view_index, func(i: int) -> void: view_index = i))
	_controls.add_child(plot)
	var rec := Ui.flow(6)
	rec.add_child(Ui.button("Record this run", record_run, "", 15))
	rec.add_child(Ui.button("Run the final test", start_final_test, "Primary", 16))
	_controls.add_child(rec)
	if session.guided:
		_controls.add_child(Ui.text("Peaks at whole multiples of the shaft speed (1×, 2×) mean unbalance or a bent shaft; peaks between them (BPFO, BPFI) mean a bearing; the envelope spectrum shows bearing defects clearest. ISO 10816 zones: A < 0.71, B < 1.8, C < 4.5 mm/s.", 14, UiTheme.LILAC))
	_show_final()


func set_fast(on: bool) -> void:
	fast_mode = on
	_behind_t = 0.0
	if sim:
		sim.fast = on


func toggle_run() -> void:
	if sim.armed:
		sim.stop()
	else:
		if sim.mode == "fault":
			sim.mode = "stopped"
		sim.start()
		main.sfx.play("click")
	_rebuild_controls()


func _process(delta: float) -> void:
	if sim == null:
		return
	_step_sim(delta)
	model.set_rotor_angle(sim.theta)
	var fast := absf(sim.rpm()) > 400.0
	_blur.visible = fast and session.spec.load == "prop" and sim.prop_on
	if _prop.get_child_count() > 0 and session.spec.load == "prop":
		for c in _prop.get_children():
			(c as Node3D).visible = sim.prop_on and not fast
	_feed_audio()
	if final_running:
		final_t = sim.time - _final_start
		if final_t >= FINAL_SECONDS:
			_finish_final_test()
	_plot_t += delta
	_spec_t += delta
	if _plot_t > 0.12:
		_plot_t = 0.0
		var spec_due := _spec_t > 0.5
		if spec_due:
			_spec_t = 0.0
		_update_readouts()
		_update_plot(spec_due)


## Advances the simulation as close to real time as the frame budget allows.
func _step_sim(delta: float) -> void:
	if not sim.armed and absf(sim.omega) < 0.01 and sim.mode != "ramp":
		sim_rate = 1.0
		return
	var target := minf(delta, 1.0 / 30.0)
	var t0 := Time.get_ticks_usec()
	var done := 0.0
	var chunk := 1.0 / 240.0
	while done < target - 1e-6:
		var step := minf(chunk, target - done)
		sim.advance(step)
		done += step
		if (Time.get_ticks_usec() - t0) / 1000.0 > budget_ms:
			break
	sim_rate = lerpf(sim_rate, done / maxf(delta, 1e-4), 0.1)
	# a computer that can't keep the detailed model near real time gets the fast one
	_behind_t = _behind_t + delta if sim_rate < 0.6 and not fast_mode else 0.0
	if _behind_t > 2.0:
		set_fast(true)
		say("This computer can't run the detailed motor model in real time, so the test stand switched to the fast model (same physics, 100 µs steps).", "info")
		_rebuild_controls()


## Runs the simulation for `seconds` of simulated time right away (autotest, no budget).
func run_for(seconds: float) -> void:
	var n := int(seconds * 60.0)
	for i in n:
		sim.advance(1.0 / 60.0)
	_update_plot(true)
	final_t = sim.time - _final_start
	if final_running and final_t >= FINAL_SECONDS:
		_finish_final_test()
	_update_readouts()


func _update_readouts() -> void:
	if _readouts.is_empty():
		return
	var a := sim.avg
	var spec := session.spec
	set_readout(_readouts.rpm, "%.0f rpm" % absf(a.rpm))
	set_readout(_readouts.current, "%.2f A" % a.bus_i, Color("ff8a8a") if a.bus_i > spec.max_current * 0.9 else Color("9ff0c8"))
	set_readout(_readouts.power, "%.0f W in, %.0f%%" % [a.p_in, 100.0 * a.p_out / maxf(a.p_in, 0.01)])
	if spec.load == "prop":
		set_readout(_readouts.thrust, "%.0f g thrust" % (a.thrust / 9.81 * 1000.0))
	else:
		set_readout(_readouts.thrust, "%.2f N·m" % a.torque)
	var temp := session.state.winding_temp
	set_readout(_readouts.temp, "%.0f °C winding" % temp, Color("ff8a8a") if temp > spec.max_temp * 0.8 else Color("9ff0c8"))
	set_readout(_readouts.vib, "%.2f mm/s %s" % [_vib, Vibration.zone(_vib).substr(0, 1)], Color("ff8a8a") if _vib > 1.8 else Color("9ff0c8"))
	var st := "ESC: %s" % sim.mode
	if fast_mode:
		st += " (fast model)"
	if sim.mode == "fault":
		st += " — " + sim.fault_reason
	if sim_rate < 0.93 and sim.armed:
		st += "   (simulation at %.0f %% of real time on this computer)" % (sim_rate * 100.0)
	if final_running:
		st += "   FINAL TEST %.1f / %.0f s" % [final_t, FINAL_SECONDS]
	(_readouts.state as Label).text = st


## spec_due: recompute the spectra (FFTs are costly, twice a second is enough).
func _update_plot(spec_due := true) -> void:
	var spec := session.spec
	var views: Array[PlotView] = [plot, monitor_plot]
	var running := absf(sim.omega) > 1.0
	if spec_due and running:
		var samples := sim.recent(sim.buf_accel, 4096)
		var plain := Vibration.spectrum(samples, DriveSim.SAMPLE_RATE)
		_vib = Vibration.velocity_rms(plain)
		_spectrum = Vibration.envelope_spectrum(samples, DriveSim.SAMPLE_RATE) if view_index == 3 else plain
	elif not running:
		_vib = lerpf(_vib, 0.0, 0.3)
	for p in views:
		p.markers.clear()
		match view_index:
			0, 1:
				p.mode = "time"
				var buf := sim.buf_va if view_index == 0 else sim.buf_current
				var f_e := absf(sim.avg.rpm) / 60.0 * spec.pole_pairs()
				var count := clampi(int(DriveSim.SAMPLE_RATE * 2.0 / maxf(f_e, 20.0)), 40, 2000)
				p.traces = [sim.recent(buf, count)]
				p.trace_names.assign(["V_A" if view_index == 0 else "I_A"])
				var top := sim.supply_v * 1.1 if view_index == 0 else maxf(spec.max_current * 1.2, 1.0)
				p.y_range = Vector2(-top * 0.15 if view_index == 0 else -top, top)
				p.title = "%s, %.1f ms" % [VIEWS[view_index], count / DriveSim.SAMPLE_RATE * 1000.0]
				p.footer = "commutation %.0f Hz" % (6.0 * f_e)
			_:
				p.mode = "spectrum"
				if _spectrum.is_empty():
					p.traces = []
					p.footer = "run the motor to see the spectrum"
				else:
					var f_max := 1000.0 if view_index == 2 else 800.0
					var freq: PackedFloat32Array = _spectrum.freq
					var amp: PackedFloat32Array = _spectrum.amp
					var n := 0
					while n < freq.size() and freq[n] <= f_max:
						n += 1
					var arr := amp.slice(0, n)
					var top := 0.0
					for v in arr:
						top = maxf(top, v)
					p.traces = [arr]
					p.x_range = Vector2(0.0, freq[maxi(n - 1, 1)])
					p.y_range = Vector2(0.0, maxf(top * 1.15, 0.05))
					var cols := {"1×": Color(1, 1, 1, 0.6), "2×": Color(1, 1, 1, 0.4), "BPFO": Color(1, 0.5, 0.3, 0.8), "BPFI": Color(1, 0.8, 0.3, 0.8), "electrical": Color(0.5, 0.8, 1, 0.5), "cogging": Color(0.7, 0.6, 1, 0.5)}
					var mf := sim.marker_frequencies()
					for k: String in mf:
						p.markers.append({"f": mf[k], "label": k, "color": cols.get(k, Color.WHITE)})
					p.footer = "0–%.0f Hz   overall %.2f mm/s RMS: zone %s" % [p.x_range.y, _vib, Vibration.zone(_vib)]
				p.title = VIEWS[view_index]
				p.trace_names.assign([])
		p.queue_redraw()


## Motor sound: commutation whine and hum, plus the vibration signal (grinding bearings,
## rattling magnets and grit are audible).
func _feed_audio() -> void:
	if _playback == null:
		return
	var frames := _playback.get_frames_available()
	if frames <= 0:
		return
	var f_r := absf(sim.rpm()) / 60.0
	var f_e := f_r * session.spec.pole_pairs()
	var load := clampf(sim.avg.bus_i / maxf(session.spec.max_current, 1.0), 0.0, 1.0)
	var amp := clampf(f_r / 60.0, 0.0, 1.0) * (0.06 + 0.12 * load)
	var acc := sim.recent(sim.buf_accel, 1024)
	var step := DriveSim.SAMPLE_RATE / MIX_RATE * clampf(sim_rate, 0.05, 1.0)
	for i in frames:
		_phase = fmod(_phase + 6.0 * f_e / MIX_RATE, 1.0)
		_phase2 = fmod(_phase2 + f_e / MIX_RATE, 1.0)
		_abuf = fmod(_abuf + step, 1023.0)
		var s := amp * (0.5 * sin(TAU * _phase) + 0.35 * sin(TAU * _phase2))
		s += clampf(acc[int(_abuf)] * 0.08, -0.4, 0.4) * clampf(f_r / 20.0, 0.0, 1.0)
		_playback.push_frame(Vector2(s, s))


func record_run() -> void:
	var a := sim.avg
	var spec := session.spec
	if absf(a.rpm) < 50.0:
		say("Run the motor first.", "warn")
		return
	var samples := sim.recent(sim.buf_accel, 8192)
	var sp := Vibration.spectrum(samples, DriveSim.SAMPLE_RATE)
	var v := Vibration.velocity_rms(sp)
	var env := Vibration.envelope_spectrum(samples, DriveSim.SAMPLE_RATE)
	var mf := sim.marker_frequencies()
	var f1: float = mf["1×"]
	var t := "Run at %.0f %% throttle: %.0f rpm, %.2f A, %.0f W, %.0f °C; vibration %.2f mm/s (zone %s)" % [sim.throttle * 100.0, absf(a.rpm), a.bus_i, a.p_in, session.state.winding_temp, v, Vibration.zone(v).substr(0, 1)]
	if spec.load == "prop" and sim.prop_on:
		t += "; thrust %.0f g" % (a.thrust / 9.81 * 1000.0)
	var p1 := Vibration.peak_near(sp, f1)
	var bp := Vibration.peak_near(env, mf.BPFO, 0.02)
	t += "; 1× peak %.3f m/s², envelope at BPFO %.3f" % [p1, bp]
	if sim.mode == "fault":
		t += "; ESC tripped: " + sim.fault_reason
	session.measured["vib"] = v
	note("run", t, absf(a.rpm))


func start_final_test() -> void:
	if not session.is_assembled():
		say("Assemble the motor first.", "warn")
		return
	sim.stop()
	sim.mode = "stopped"
	sim.prop_on = false
	sim.brake_torque = 0.0
	sim.throttle = 1.0
	if _throttle_slider:
		_throttle_slider.set_value_no_signal(1.0)
	_prop.visible = session.spec.load != "prop"
	sim.desyncs = 0
	sim.start()
	final_running = true
	final_t = 0.0
	_final_start = sim.time
	last_final = {}
	say("Final test: full throttle, no load, %.0f s. Checking start-up, no-load speed and current, vibration and temperature." % FINAL_SECONDS)
	_rebuild_controls()


func _finish_final_test() -> void:
	final_running = false
	var spec := session.spec
	var a := sim.avg
	var lines: Array[String] = []
	var ok := true
	var running := sim.mode == "run"
	lines.append(("✔" if running else "✘") + " Starts and runs (ESC %s%s)" % [sim.mode, ": " + sim.fault_reason if sim.fault_reason != "" else ""])
	ok = ok and running
	var expect := spec.kv * sim.supply_v
	var rpm := absf(a.rpm)
	# six-step drive runs a few per cent above KV × V (KV is defined by the peak EMF)
	var rpm_ok := rpm > expect * 0.93 and rpm < expect * 1.12
	lines.append(("✔" if rpm_ok else "✘") + " No-load speed %.0f rpm (KV × V = %.0f, allowed −7 %%…+12 %%)" % [rpm, expect])
	ok = ok and rpm_ok
	var i0_limit := spec.max_current * 0.15
	var i0_ok: bool = a.bus_i < i0_limit
	lines.append(("✔" if i0_ok else "✘") + " No-load current %.2f A (limit %.2f A)" % [a.bus_i, i0_limit])
	ok = ok and i0_ok
	var samples := sim.recent(sim.buf_accel, 8192)
	var v := Vibration.velocity_rms(Vibration.spectrum(samples, DriveSim.SAMPLE_RATE))
	var v_ok := v <= 1.8
	lines.append(("✔" if v_ok else "✘") + " Vibration %.2f mm/s (zone %s; A or B needed)" % [v, Vibration.zone(v).substr(0, 1)])
	ok = ok and v_ok
	var t_ok := session.state.winding_temp < spec.max_temp * 0.7
	lines.append(("✔" if t_ok else "✘") + " Winding temperature %.0f °C" % session.state.winding_temp)
	ok = ok and t_ok
	# resistance balance of the three lead pairs (standard after any winding work)
	var st := session.state
	var rr: Array[float] = [st.resistance_ll(0, 1), st.resistance_ll(1, 2), st.resistance_ll(2, 0)]
	var balanced: bool = not is_inf(rr.max()) and (rr.max() - rr.min()) / rr.min() < 0.03
	lines.append(("✔" if balanced else "✘") + " Lead resistances balanced (%s)" % ("spread %.1f %%" % (100.0 * (rr.max() - rr.min()) / rr.min()) if not is_inf(rr.max()) else "a pair reads OL"))
	ok = ok and balanced
	# the hand-spin check a technician does before signing off
	var feel: Array[String] = []
	if st.worst_bearing() > 0.3:
		feel.append("rough bearing")
	if st.debris > 0:
		feel.append("grit")
	if not st.shim_present:
		feel.append("end play")
	for m: Dictionary in st.magnets:
		if m.loose:
			feel.append("knock")
			break
	lines.append(("✔" if feel.is_empty() else "✘") + " Hand spin: %s" % ("smooth, no play" if feel.is_empty() else ", ".join(feel)))
	ok = ok and feel.is_empty()
	var ir_ok := session.state.insulation_mohm >= 100.0
	lines.append(("✔" if ir_ok else "✘") + " Insulation %s" % ("> 100 MΩ" if ir_ok else "below 100 MΩ"))
	ok = ok and ir_ok
	last_final = {"pass": ok, "lines": lines, "rpm": rpm, "i0": a.bus_i, "vib": v}
	session.record_final_test(last_final)
	session.note("final", "Final test %s: %.0f rpm, %.2f A, %.2f mm/s" % ["PASSED" if ok else "FAILED", rpm, a.bus_i, v])
	say("Final test " + ("PASSED" if ok else "FAILED"), "ok" if ok else "error")
	sim.stop()
	_rebuild_controls()


func _show_final() -> void:
	Ui.clear(_results)
	if last_final.is_empty():
		return
	section(_results, "Final test: " + ("PASSED" if last_final.pass else "FAILED"))
	for l: String in last_final.lines:
		_results.add_child(Ui.status(l, "ok" if l.begins_with("✔") else "error", 15))


func teardown() -> void:
	if sim:
		sim.stop()
	_player.stop()


func view() -> Array:
	return [bench + Vector3(0.12, 0.55, 0.9), bench + Vector3(0.12, 0.14, -0.12)]


func view_width() -> float:
	return 0.95
