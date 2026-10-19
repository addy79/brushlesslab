extends SceneTree
## Headless tests of the physics model (no window):
##   godot --headless --path . -s tests/model_test.gd
## Exit code = number of failed checks.

var passed := 0
var failed := 0


func check(cond: bool, what: String) -> void:
	if cond:
		passed += 1
		print("  ok   ", what)
	else:
		failed += 1
		print("  FAIL ", what)


func near(a: float, b: float, rel: float) -> bool:
	return absf(a - b) <= absf(b) * rel


func _init() -> void:
	print("== windings")
	var w := Winding.design(12, 14)
	check(Winding.equivalent(Winding.to_text(w), "AabBCcaABbcC"), "12N14P designs the dLRK layout AabBCcaABbcC (got %s)" % Winding.to_text(w))
	check(near(Winding.winding_factor(w, 12, 14), 0.933, 0.005), "12N14P winding factor 0.933 (%.3f)" % Winding.winding_factor(w, 12, 14))
	var kw_expect := {"9,6": 0.866, "12,10": 0.933, "9,8": 0.945, "9,10": 0.945, "18,16": 0.945, "12,8": 0.866, "24,22": 0.949, "9,12": 0.866, "18,20": 0.945}
	for key: String in kw_expect:
		var q := int(key.get_slice(",", 0))
		var p := int(key.get_slice(",", 1))
		var c := Winding.design(q, p)
		check(c.size() == q and near(Winding.winding_factor(c, q, p), kw_expect[key], 0.01), "%dN%dP balanced, kw %.3f (%.3f)" % [q, p, kw_expect[key], Winding.winding_factor(c, q, p) if c.size() > 0 else 0.0])
	check(Winding.equivalent("aABbcCAabBCc", "AabBCcaABbcC"), "pattern equivalence: started on another tooth")
	check(Winding.equivalent("AacCBbaACcbB", "AabBCcaABbcC"), "pattern equivalence: B and C leads swapped")
	check(Winding.equivalent("aABbcCAabBCc".to_upper().to_lower(), "AabBCcaABbcC") == false, "all lower case is a different (wrong) layout")
	check(not Winding.equivalent("AaBbCcAaBbCc", "AabBCcaABbcC"), "a wrong 12N14P layout is rejected")
	check(Winding.check(Winding.design(12, 14), 12, 14).is_empty(), "the design passes the rewind check")
	check(not Winding.check(Winding.from_text("AabBCcaABbcc"), 12, 14).is_empty(), "one reversed coil fails the rewind check")

	print("== flux model, healthy 2212")
	var s := MotorState.new(MotorSpec.drone_2212())
	check(near(s.measured_kv(), 920.0, 0.003), "KV from back-EMF = 920 (%.1f)" % s.measured_kv())
	var pk := s.mag.peak_line_k()
	check(near(pk[1], pk[0], 0.01) and near(pk[2], pk[0], 0.01), "three lead pairs balanced (%.5f %.5f %.5f)" % pk)
	var zc := 0
	var prev := s.mag.line_k(0, 0)
	for i in range(1, Magnetics.N):
		var v := s.mag.line_k(0, i)
		if signf(v) != signf(prev) and v != 0.0:
			zc += 1
		prev = v
	check(zc == 14, "A-B EMF crosses zero 2 × 7 pole pairs = 14 times per turn (%d)" % zc)
	check(near(s.resistance_ll(0, 1), 0.105 * (1.0 + 0.00393 * 2.0), 0.001), "R A-B = 0.105 Ω at 20 °C (%.4f at 22 °C)" % s.resistance_ll(0, 1))
	check(near(s.inductance_ll(0, 1), 34e-6, 0.03), "L A-B ≈ 34 µH (%.1f µH)" % (s.inductance_ll(0, 1) * 1e6))
	check(MotorSpec.drone_2212().cogging_steps() == 84, "12N14P: LCM = 84 cogging steps per turn")

	print("== faults")
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var f := MotorState.new(MotorSpec.drone_2212())
	f.shorted[1] = 0.22
	f.rebuild()
	var rab := f.resistance_ll(0, 1)
	var rbc := f.resistance_ll(1, 2)
	var rca := f.resistance_ll(2, 0)
	check(rab < rca * 0.92 and rbc < rca * 0.92 and near(rab, rbc, 0.01), "shorted turns in B: R_AB, R_BC low, R_CA normal (%.4f %.4f %.4f)" % [rab, rbc, rca])
	check(f.inductance_ll(0, 1) < f.inductance_ll(2, 0) * 0.6, "shorted turns pull L_AB far down (%.1f vs %.1f µH)" % [f.inductance_ll(0, 1) * 1e6, f.inductance_ll(2, 0) * 1e6])
	var o := MotorState.new(MotorSpec.drone_2212())
	o.open_phase = 2
	check(is_inf(o.resistance_ll(1, 2)) and is_inf(o.resistance_ll(2, 0)) and not is_inf(o.resistance_ll(0, 1)), "open phase C: B-C and C-A read OL, A-B normal")
	var d := MotorState.new(MotorSpec.drone_2212())
	for m: Dictionary in d.magnets:
		m.strength = 0.8
	d.rebuild()
	check(near(d.measured_kv(), 1150.0, 0.01), "magnets at 80 %%: KV rises to 1150 (%.0f)" % d.measured_kv())
	var flip := MotorState.new(MotorSpec.drone_2212())
	flip.magnets[3].polarity = -1
	flip.rebuild()
	var cp := flip.mag.cycle_peaks(0)
	var healthy_cp := s.mag.cycle_peaks(0)
	check(cp.min() < cp.max() * 0.85 and healthy_cp.min() > healthy_cp.max() * 0.99, "one magnet glued in flipped: uneven EMF peaks (%.4f .. %.4f)" % [cp.min(), cp.max()])
	var rw := MotorState.new(MotorSpec.drone_2212())
	rw.coils = Winding.from_text("AaBbCcAaBbCc", 13)
	rw.rewound = true
	rw.rebuild()
	check(rw.measured_kv() > 1400.0 or rw.mag.peak_line_k().min() < pk[0] * 0.7, "a wrong rewind gives weak back-EMF (KV %.0f)" % rw.measured_kv())
	check(not rw.is_healthy(), "a wrong rewind is reported as a problem")

	print("== delta and mystery motors")
	for seed_value in [3, 17, 42, 99, 123]:
		var ms := MotorSpec.mystery(seed_value)
		var st := MotorState.new(ms)
		check(st.coils.size() == ms.slots and near(st.measured_kv(), ms.kv, 0.005), "mystery #%d %dN%dP %s KV %.0f: model KV %.0f" % [seed_value, ms.slots, ms.poles, ms.connection, ms.kv, st.measured_kv()])
		check(near(st.resistance_ll(0, 1), ms.r_ll * (1.0 + 0.00393 * 2.0), 0.002), "   R_ll %.3f Ω reproduced (%s)" % [ms.r_ll, ms.connection])

	print("== Hall sensors (57BL)")
	var h := MotorState.new(MotorSpec.industrial_57bl())
	var codes := {}
	for i in 360:
		codes[h.hall_code(TAU / 4.0 * i / 360.0)] = true
	check(codes.size() == 6 and not codes.has(0) and not codes.has(7), "six valid Hall codes per electrical turn (%s)" % str(codes.keys()))
	check(near(h.measured_kv(), 190.0, 0.005), "57BL KV = 190 (%.1f)" % h.measured_kv())

	print("== drive simulation")
	var t_start := Time.get_ticks_msec()
	var sim := DriveSim.new(MotorState.new(MotorSpec.drone_2212()))
	sim.prop_on = false
	sim.throttle = 1.0
	sim.start()
	for i in 150:
		sim.advance(1.0 / 60.0)
	var cost := (Time.get_ticks_msec() - t_start) / 2.5
	print("     sim cost: %.0f ms per simulated second" % cost)
	check(sim.mode == "run", "2212 started sensorless (mode %s, desyncs %d)" % [sim.mode, sim.desyncs])
	var nl := absf(sim.avg.rpm)
	# six-step drive: the 60° conduction window averages ~95 % of the peak EMF, so no-load
	# speed lands a few per cent above KV × V (KV here is defined by the peak line EMF)
	check(nl > 920.0 * 11.1 * 0.95 and nl < 920.0 * 11.1 * 1.07, "no-load speed ≈ KV × V = 10212 rpm (%.0f)" % nl)
	check(sim.avg.bus_i > 0.15 and sim.avg.bus_i < 1.5, "no-load current I0 small (%.2f A)" % sim.avg.bus_i)
	sim.prop_on = true
	for i in 120:
		sim.advance(1.0 / 60.0)
	check(absf(sim.avg.rpm) > 6500.0 and absf(sim.avg.rpm) < 9500.0, "with a 10x4.5 prop: 6500–9500 rpm (%.0f)" % absf(sim.avg.rpm))
	check(sim.avg.bus_i > 6.0 and sim.avg.bus_i < 16.0, "with prop: 6–16 A (%.1f A)" % sim.avg.bus_i)
	check(sim.avg.thrust / 9.81 * 1000.0 > 550.0 and sim.avg.thrust / 9.81 * 1000.0 < 1000.0, "thrust 550–1000 g (%.0f g)" % (sim.avg.thrust / 9.81 * 1000.0))
	var eff: float = sim.avg.p_out / maxf(sim.avg.p_in, 0.01)
	check(eff > 0.6 and eff < 0.92, "efficiency 60–92 %% (%.0f %%)" % (eff * 100.0))
	var spec_h := Vibration.spectrum(sim.recent(sim.buf_accel, 8192), DriveSim.SAMPLE_RATE)
	var v_healthy := Vibration.velocity_rms(spec_h)
	print("     healthy vibration %.2f mm/s (%s)" % [v_healthy, Vibration.zone(v_healthy)])
	check(v_healthy < 1.8, "healthy motor vibration zone A/B (%.2f mm/s)" % v_healthy)

	var bent := MotorState.new(MotorSpec.drone_2212())
	bent.runout_mm = 0.12
	var bsim := _run(bent, 1.0, true, 3.0)
	var bspec := Vibration.spectrum(bsim.recent(bsim.buf_accel, 8192), DriveSim.SAMPLE_RATE)
	var vb := Vibration.velocity_rms(bspec)
	var f1: float = absf(bsim.avg.rpm) / 60.0
	check(vb > 4.5, "bent shaft: zone D (%.2f mm/s)" % vb)
	check(Vibration.peak_near(bspec, f1) > Vibration.peak_near(spec_h, absf(sim.avg.rpm) / 60.0) * 4.0, "bent shaft: big 1× peak")

	var worn := MotorState.new(MotorSpec.drone_2212())
	worn.bearings["bottom"].wear = 0.8
	var wsim := _run(worn, 1.0, true, 3.0)
	var env := Vibration.envelope_spectrum(wsim.recent(wsim.buf_accel, 8192), DriveSim.SAMPLE_RATE)
	var bpfo: float = wsim.marker_frequencies().BPFO
	var env_h := Vibration.envelope_spectrum(sim.recent(sim.buf_accel, 8192), DriveSim.SAMPLE_RATE)
	check(Vibration.peak_near(env, bpfo, 0.02) > 5.0 * Vibration.peak_near(env_h, sim.marker_frequencies().BPFO, 0.02), "worn bearing: BPFO line in the envelope spectrum (%.0f Hz)" % bpfo)

	var shorted := MotorState.new(MotorSpec.drone_2212())
	shorted.shorted[0] = 0.22
	shorted.rebuild()
	var ssim := _run(shorted, 1.0, false, 2.5)
	check(ssim.avg.bus_i > 3.0 * 0.41 and ssim.state.winding_temp > 26.0, "shorted turns: high no-load current (%.2f A) and heating (%.0f °C)" % [ssim.avg.bus_i, ssim.state.winding_temp])

	var open := MotorState.new(MotorSpec.drone_2212())
	open.open_phase = 1
	var osim := _run(open, 0.5, true, 3.0)
	check(osim.mode == "fault" or absf(osim.avg.rpm) < 3000.0, "open phase: fails to run properly (mode %s, %.0f rpm)" % [osim.mode, absf(osim.avg.rpm)])

	var gf := MotorState.new(MotorSpec.drone_2212())
	gf.insulation_mohm = 0.2
	var gsim := _run(gf, 0.6, true, 3.0)
	check(gsim.mode == "fault" and gsim.fault_reason.contains("Ground"), "ground fault: the controller trips (%s)" % gsim.fault_reason)

	var ind := DriveSim.new(MotorState.new(MotorSpec.industrial_57bl()))
	ind.throttle = 1.0
	ind.start()
	for i in 120:
		ind.advance(1.0 / 60.0)
	check(absf(ind.avg.rpm) > 190.0 * 24.0 * 0.95 and absf(ind.avg.rpm) < 190.0 * 24.0 * 1.10, "57BL sensored no-load ≈ 4560 rpm (%.0f)" % absf(ind.avg.rpm))
	ind.brake_torque = 0.2
	for i in 120:
		ind.advance(1.0 / 60.0)
	check(ind.avg.bus_i > 2.0 and ind.avg.bus_i < 6.0, "57BL at 0.2 N·m: 2–6 A (%.2f A, %.0f rpm)" % [ind.avg.bus_i, absf(ind.avg.rpm)])
	var hd := MotorState.new(MotorSpec.industrial_57bl())
	hd.hall_dead = 1
	var hsim := DriveSim.new(hd)
	hsim.throttle = 0.25
	hsim.start()
	var reversals := 0
	var last_sign := 0.0
	for i in 120:
		hsim.advance(1.0 / 60.0)
		var sg := signf(hsim.omega)
		if sg != 0.0 and last_sign != 0.0 and sg != last_sign:
			reversals += 1
		if sg != 0.0:
			last_sign = sg
	check(absf(hsim.avg.rpm) < 0.85 * absf(ind.avg.rpm) or reversals > 0, "dead Hall sensor: rough, slow or jerky (%.0f rpm, %d reversals)" % [absf(hsim.avg.rpm), reversals])

	print("== fast mode (standalone headsets) agrees with the detailed model")
	var t_fast := Time.get_ticks_msec()
	var fsim := DriveSim.new(MotorState.new(MotorSpec.drone_2212()))
	fsim.fast = true
	fsim.prop_on = false
	fsim.throttle = 1.0
	fsim.start()
	for i in 150:
		fsim.advance(1.0 / 60.0)
	var fast_cost := (Time.get_ticks_msec() - t_fast) / 2.5
	print("     fast sim cost: %.0f ms per simulated second (detailed %.0f)" % [fast_cost, cost])
	check(fast_cost < cost * 0.5, "fast mode at least 2× cheaper (%.0f vs %.0f ms/s)" % [fast_cost, cost])
	check(fsim.mode == "run" and near(absf(fsim.avg.rpm), nl, 0.03), "fast: no-load speed within 3 %% (%.0f vs %.0f rpm)" % [absf(fsim.avg.rpm), nl])
	fsim.prop_on = true
	for i in 120:
		fsim.advance(1.0 / 60.0)
	print("     fast prop: %.0f rpm %.2f A %.0f g; detailed %.0f rpm %.2f A %.0f g" % [absf(fsim.avg.rpm), fsim.avg.bus_i, fsim.avg.thrust / 9.81 * 1000.0, absf(sim.avg.rpm), sim.avg.bus_i, sim.avg.thrust / 9.81 * 1000.0])
	check(near(absf(fsim.avg.rpm), absf(sim.avg.rpm), 0.04), "fast: prop speed within 4 %")
	check(near(fsim.avg.bus_i, sim.avg.bus_i, 0.08), "fast: prop current within 8 %")
	var fv := Vibration.velocity_rms(Vibration.spectrum(fsim.recent(fsim.buf_accel, 8192), DriveSim.SAMPLE_RATE))
	check(fv < 1.8, "fast: healthy motor zone A/B (%.2f mm/s)" % fv)
	var fb := _run(bent, 1.0, true, 3.0, true)
	check(Vibration.velocity_rms(Vibration.spectrum(fb.recent(fb.buf_accel, 8192), DriveSim.SAMPLE_RATE)) > 4.5, "fast: bent shaft zone D")
	var fw := _run(worn, 1.0, true, 3.0, true)
	var fenv := Vibration.envelope_spectrum(fw.recent(fw.buf_accel, 8192), DriveSim.SAMPLE_RATE)
	check(Vibration.peak_near(fenv, fw.marker_frequencies().BPFO, 0.02) > 5.0 * Vibration.peak_near(env_h, sim.marker_frequencies().BPFO, 0.02), "fast: worn bearing BPFO line")
	var fs := _run(shorted, 1.0, false, 2.5, true)
	check(fs.avg.bus_i > 3.0 * 0.41, "fast: shorted turns draw high current (%.2f A)" % fs.avg.bus_i)
	var fo := _run(open, 0.5, true, 3.0, true)
	check(fo.mode == "fault" or absf(fo.avg.rpm) < 3000.0, "fast: open phase fails to run (mode %s, %.0f rpm)" % [fo.mode, absf(fo.avg.rpm)])
	var fg := _run(gf, 0.6, true, 3.0, true)
	check(fg.mode == "fault" and fg.fault_reason.contains("Ground"), "fast: ground fault trips")
	var find := _run(MotorState.new(MotorSpec.industrial_57bl()), 1.0, false, 2.0, true)
	check(near(absf(find.avg.rpm), absf(ind.avg.rpm), 0.2) or absf(find.avg.rpm) > 190.0 * 24.0 * 0.95, "fast: 57BL sensored runs (%.0f rpm)" % absf(find.avg.rpm))

	print("\n%d passed, %d failed" % [passed, failed])
	quit(failed)


func _run(state: MotorState, throttle: float, prop: bool, seconds: float, fast := false) -> DriveSim:
	var sim := DriveSim.new(state)
	sim.fast = fast
	sim.prop_on = prop
	sim.throttle = throttle
	sim.start()
	for i in int(seconds * 60.0):
		sim.advance(1.0 / 60.0)
	return sim
