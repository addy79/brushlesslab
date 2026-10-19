extends Node
## End-to-end test in a real window: godot --path . -- --autotest
## Works through complete jobs bench by bench (service jobs with different faults, a
## reverse-engineering job, the VR panel layout), checks the outcome at every step and
## saves screenshots to screenshots/. Exit code = number of failed checks.

var main: Main
var passed := 0
var failed := 0
var failures: Array[String] = []


func check(cond: bool, what: String) -> void:
	if cond:
		passed += 1
		print("  ok   ", what)
	else:
		failed += 1
		failures.append(what)
		print("  FAIL ", what)


func _ready() -> void:
	main.sfx.enabled = false
	await _frames(10)
	print("== start-up")
	check(main.station != null and main.station_index == 0, "starts at the Job Desk")
	check(Main.STATIONS.size() == 6, "six benches")
	check(main.hud.drawer.visible, "desktop drawer visible without a headset")
	for i in Main.STATIONS.size():
		await _go(i)
		check(main.station.panel.get_parent() == main.hud.drawer_holder, "bench %d panel sits in the desktop drawer" % (i + 1))
		await _shot("bench_%d_free" % (i + 1))
	await _service_bearing()
	await _reverse_job()
	await _service_rewind()
	await _service_hall()
	await _mistakes()
	await _vr_layout()
	print("\n%d passed, %d failed" % [passed, failed])
	for f in failures:
		print("  FAILED: ", f)
	get_tree().quit(failed)


# --- helpers ----------------------------------------------------------------------------------

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _go(i: int) -> void:
	main.load_station(i)
	await _frames(6)


## Saves a screenshot; `wait` real seconds first so part animations have finished.
func _shot(name: String, wait := 0.3) -> void:
	await get_tree().create_timer(wait).timeout
	await _frames(3)
	await RenderingServer.frame_post_draw
	main.save_screenshot(name)


func _desk() -> Station:
	await _go(0)
	return main.station


func _start(mode: String, motor: String, fault: String, seed_value: int) -> void:
	var desk := await _desk()
	desk.call("start_job", mode, motor, fault, seed_value)
	await _frames(4)


## Takes everything off in the standard order with the right tools.
func _strip(td: Station, upto := "") -> bool:
	var s := main.session
	for id: String in TeardownPlan.order(s.spec):
		var p: Dictionary = s.plan()[id]
		td.call("select_tool", p.tool)
		td.call("click_part", id)
		if not s.is_removed(id):
			print("     could not remove ", id)
			return false
		if id == upto:
			break
	return true


## Puts everything back in the guided order with the right tools and press ring.
func _reassemble(td: Station) -> bool:
	var s := main.session
	td.set("press_ring", TeardownPlan.press_ring(s.spec))
	for n in 20:
		var id := s.next_on()
		if id == "":
			return true
		var p: Dictionary = s.plan()[id]
		td.call("select_tool", p.put)
		td.call("click_part", id)
		if s.is_removed(id):
			print("     could not fit ", id)
			return false
	return s.is_assembled()


## fast: run it on DriveSim's fast model (what a standalone headset uses).
func _final_test(fast := false) -> Dictionary:
	await _go(5)
	var ts := main.station
	ts.call("set_fast", fast)
	ts.call("start_final_test")
	ts.call("run_for", 3.4)
	await _frames(4)
	return main.session.final_test


# --- jobs ---------------------------------------------------------------------------------------

func _service_bearing() -> void:
	print("== service job: grinding noise (worn bearing), 2212")
	await _start("service", "2212", "bearing_worn", 5)
	var s := main.session
	check(s.mode == "service" and s.fault == "bearing_worn", "job started from the desk")
	check(main.guide_text().contains("Bench 2"), "guide points at the teardown bench first")
	await _shot("job_service_desk")
	await _go(1)
	var td := main.station
	td.call("turn_by_hand")
	check(s.measured.has("hand_turn") and str(s.notebook[-1]).contains("rough"), "turning by hand feels rough")
	await _go(2)
	var el := main.station
	el.set("pair", 0)
	el.call("record")
	check(s.measured.has("R_AB") and absf(float(s.measured.R_AB) - 0.105) < 0.004, "milliohm meter A–B ≈ 105 mΩ (%.1f mΩ)" % (float(s.measured.get("R_AB", 0.0)) * 1000.0))
	el.set("instrument", 3)
	el.call("_rebuild_instrument")
	el.call("record")
	check(float(s.measured.get("IR", 0.0)) >= 2000.0, "insulation healthy")
	await _shot("bench_3_milliohm")
	await _go(5)
	var ts := main.station
	ts.set("view_index", 3)
	ts.get("sim").set("throttle", 0.7)
	ts.call("toggle_run")
	ts.call("run_for", 2.0)
	await _frames(12)
	ts.call("record_run")
	check(s.measured.has("run"), "test-stand run recorded")
	await _shot("bench_6_bearing_envelope")
	ts.call("toggle_run")
	s.diagnosis = "bearing_worn"
	check(s.diagnosis_ok(), "diagnosis: worn bearing")
	await _go(1)
	td = main.station
	td.call("select_tool", "hand")
	td.call("click_part", "bell")
	check(not s.is_removed("bell") and s.mistakes.is_empty(), "bell won't come off while the circlip holds it")
	td.call("select_tool", "hand")
	td.call("click_part", "circlip")
	check(not s.is_removed("circlip") and s.mistakes.size() == 1, "wrong tool on the circlip is refused and noted")
	check(await _strip(td), "full teardown in the right order")
	await _shot("bench_2_stripped", 1.2)
	td.call("new_bearing", "top")
	td.call("new_bearing", "bottom")
	check(s.state.worst_bearing() == 0.0, "both bearings replaced")
	check(await _reassemble(td), "reassembled with the right tools")
	check(s.state.problems().is_empty(), "nothing left wrong (%s)" % ", ".join(s.state.problems()))
	await _shot("bench_2_reassembled", 1.2)
	var ft := await _final_test()
	check(ft.get("pass", false), "final test passes (%s)" % " | ".join(ft.get("lines", [])))
	await _shot("bench_6_final_test")
	var desk := await _desk()
	desk.call("hand_in")
	var rep: Dictionary = desk.call("report")
	check(rep.score >= 90, "report score %d / %d" % [rep.score, rep.max])
	await _shot("bench_1_report")


func _reverse_job() -> void:
	print("== reverse-engineering job: mystery outrunner")
	await _start("reverse", "mystery", "none", 42)
	var s := main.session
	var spec := s.spec
	print("     hidden design: %dN%dP %s %.0f KV %.0f mΩ" % [spec.slots, spec.poles, spec.connection, spec.kv, spec.r_ll * 1000.0])
	await _go(2)
	var el := main.station
	el.set("pair", 0)
	el.set("instrument", 0)
	el.call("_rebuild_instrument")
	el.call("record")
	el.set("instrument", 4)
	el.call("_rebuild_instrument")
	el.set("drill_rpm", 2000.0)
	await _frames(10)
	el.call("record")
	var kv := float(s.measured.get("KV", 0.0))
	check(absf(kv - spec.kv) / spec.kv < 0.03, "back-EMF KV %.0f vs real %.0f" % [kv, spec.kv])
	check(roundi(float(s.measured.get("pole_pairs", 0.0))) * 2 == spec.poles, "scope frequency gives %d poles" % spec.poles)
	await _shot("bench_3_backemf_scope")
	await _go(1)
	check(await _strip(main.station, "bell"), "bell off")
	await _go(3)
	var ins := main.station
	ins.call("measure_stator")
	ins.set("tool", 1)
	for i in spec.slots:
		ins.call("_on_tooth", i)
	ins.call("inspect_joints")
	ins.set("tool", 2)
	ins.call("_rebuild_tools")
	ins.call("sweep_magnets")
	check(s.measured.has("winding") and s.measured.has("joints") and s.measured.has("size"), "winding traced, joints and size recorded")
	await _frames(10)
	await _shot("bench_4_traced")
	var desk := await _desk()
	var r_ohm := float(s.measured.R_AB) / (1.0 + 0.00393 * (s.state.winding_temp - 20.0))
	desk.call("set_answer", "slots", str(spec.slots))
	desk.call("set_answer", "poles", str(roundi(float(s.measured.pole_pairs)) * 2))
	desk.call("set_answer", "connection", s.measured.joints)
	desk.call("set_answer", "kv", "%.0f" % kv)
	desk.call("set_answer", "r_mohm", "%.0f" % (r_ohm * 1000.0))
	desk.call("set_answer", "winding", s.measured.winding)
	desk.call("set_answer", "size", s.measured.size)
	desk.call("hand_in")
	var rep: Dictionary = desk.call("report")
	check(rep.score == rep.max, "datasheet all correct (%d / %d)" % [rep.score, rep.max])
	await _shot("bench_1_reverse_report")


func _service_rewind() -> void:
	print("== service job: runs hot (shorted turns), rewind")
	await _start("service", "2212", "shorted_turns", 9)
	var s := main.session
	await _go(2)
	var el := main.station
	var rs: Array[float] = []
	for p in 3:
		el.set("pair", p)
		el.call("record")
		rs.append(float(s.measured["R_" + ["AB", "BC", "CA"][p]]))
	check(rs.max() / rs.min() > 1.08, "lead pairs unbalanced (%.1f / %.1f / %.1f mΩ)" % [rs[0] * 1000, rs[1] * 1000, rs[2] * 1000])
	s.diagnosis = "shorted_turns"
	await _go(1)
	var td := main.station
	check(await _strip(td), "stripped (stator heated off the base)")
	await _go(4)
	var w := main.station
	w.call("set_layout_text", Winding.to_text(Winding.design(s.spec.slots, s.spec.poles)))
	await _frames(4)
	await _shot("bench_5_layout")
	w.call("wind_it")
	check(s.state.rewound and s.state.shorted.max() == 0.0, "stator rewound")
	await _go(1)
	td = main.station
	td.call("new_bearing", "top")
	td.call("new_bearing", "bottom")
	check(await _reassemble(td), "reassembled")
	check(s.state.problems().is_empty(), "nothing left wrong (%s)" % ", ".join(s.state.problems()))
	var ft := await _final_test()
	check(ft.get("pass", false), "rewound motor passes the final test (%s)" % " | ".join(ft.get("lines", [])))
	ft = await _final_test(true)
	check(ft.get("pass", false), "rewound motor also passes on the fast model (%s)" % " | ".join(ft.get("lines", [])))
	var desk := await _desk()
	desk.call("hand_in")
	check((desk.call("report") as Dictionary).score >= 90, "report graded")


func _service_hall() -> void:
	print("== service job: jerky start (dead Hall sensor), 57BL")
	await _start("service", "57BL", "hall_dead", 3)
	var s := main.session
	await _go(2)
	var el := main.station
	el.set("instrument", 5)
	el.call("_rebuild_instrument")
	el.set("hall_angle", 40.0)
	await _frames(6)
	el.call("record")
	check(int(s.measured.get("halls", 0)) == 1, "Hall sweep finds one stuck sensor")
	await _shot("bench_3_hall_tester")
	s.diagnosis = "hall_dead"
	await _go(1)
	var td := main.station
	check(await _strip(td, "hall_board"), "Hall board out")
	await _shot("bench_2_57bl_open", 1.2)
	var r := s.do_repair("hall")
	check(r.ok and s.state.hall_dead < 0, "Hall sensor replaced")
	check(await _reassemble(td), "57BL reassembled")
	var ft := await _final_test()
	check(ft.get("pass", false), "57BL passes the final test (%s)" % " | ".join(ft.get("lines", [])))
	await _shot("bench_6_57bl")


func _mistakes() -> void:
	print("== mistakes have consequences")
	await _start("service", "2212", "bearing_worn", 13)
	var s := main.session
	await _go(1)
	var td := main.station
	await _strip(td)
	td.call("new_bearing", "top")
	td.call("new_bearing", "bottom")
	td.set("press_ring", "inner")
	td.call("select_tool", "arbor_press")
	td.call("click_part", "bearing_bottom")
	check(s.state.bearings["bottom"].brinelled, "pressing on the wrong ring brinells the bearing")
	td.set("press_ring", "outer")
	td.call("click_part", "bearing_top")
	td.call("select_tool", "heat_gun")
	td.call("click_part", "stator")
	check(s.is_removed("stator"), "heat gun does not fit the stator back")
	td.call("select_tool", "hand")
	td.call("click_part", "stator")
	td.call("click_part", "bell")
	td.call("select_tool", "circlip_pliers")
	td.call("click_part", "circlip")
	check(not s.state.shim_present, "fitting the circlip without the shim leaves end play")
	td.call("select_tool", "wrench")
	td.call("click_part", "prop_adapter")
	check(s.is_assembled() or s.is_removed("shim"), "only the shim is left on the tray")
	check(s.state.problems().size() >= 2, "problems remain: %s" % ", ".join(s.state.problems()))
	for fault: String in ["bearing_worn", "open_phase", "debris", "demagnetized", "loose_magnet"]:
		await _start("service", "2212", fault, 21)
		var ft := await _final_test()
		check(not ft.get("pass", true), "unrepaired %s fails the final test" % fault)
		ft = await _final_test(true)
		check(not ft.get("pass", true), "unrepaired %s fails on the fast model too" % fault)


func _vr_layout() -> void:
	print("== VR panel layout (preview without a headset)")
	main._panels_forced = true
	main._apply_panel_visibility()
	await _go(5)
	check(main.station.panel.get_parent() == main._vr_scroll, "station panel moves onto the VR panel")
	check(main.vr_station_panel.visible and not main.hud.drawer.visible, "VR panels shown, drawer hidden")
	main.desktop_camera.reset_view(main.station.xr_position() + Vector3(0, 1.6, 0.6), Main.bench_position(5) + Vector3(0, 0.3, 0))
	await _frames(20)
	await _shot("vr_preview_test_stand")
	await _go(3)
	main.desktop_camera.reset_view(main.station.xr_position() + Vector3(0, 1.6, 0.6), Main.bench_position(3) + Vector3(0, 0.3, 0))
	await _frames(20)
	await _shot("vr_preview_inspect")
	main._panels_forced = false
	main._apply_panel_visibility()
	await _frames(4)
	check(main.station.panel.get_parent() == main.hud.drawer_holder, "panel back in the drawer")
