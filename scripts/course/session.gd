class_name Session
extends RefCounted
## One job at the workshop: the motor on the bench (design + condition), how far it is
## taken apart, what the learner has measured (the notebook), their answers (datasheet,
## diagnosis), the repairs and mistakes, and the final report.
##
## Modes:
##   "reverse": a mystery outrunner. Identify slots, poles, winding, connection, KV, R.
##   "service": a customer's motor with a hidden fault. Diagnose, repair, pass the final test.
##   "free":    a healthy motor to explore.

signal changed
signal message(text: String, kind: String)   ## kind: info | ok | warn | error

var mode := "free"
var motor_id := "2212"
var seed_value := 1
var spec: MotorSpec
var state: MotorState
var job := {}
var fault := "none"
## Parts that are off the motor (id -> true).
var removed := {}
## Removed parts the learner replaced with new ones (bearings), etc.
var history: Array[String] = []
var notebook: Array[String] = []
## Measured values by key (e.g. "R_AB", "KV", "vib") so the report can use them.
var measured := {}
## Learner's answers for the reverse-engineering datasheet.
var datasheet := {}
var diagnosis := ""
var repairs: Array[String] = []
var mistakes: Array[String] = []
var final_test := {}
var finished := false
var started_ms := 0
## Guided: show the next step and hints. Expert: no hints.
var guided := true

var _rng := RandomNumberGenerator.new()


func start(p_mode: String, p_motor: String, p_fault := "none", p_seed := 0) -> void:
	mode = p_mode
	motor_id = p_motor
	seed_value = p_seed if p_seed != 0 else int(Time.get_unix_time_from_system()) % 100000 + 1
	_rng.seed = seed_value
	spec = MotorSpec.by_id(motor_id, seed_value)
	state = MotorState.new(spec)
	fault = p_fault
	job = Faults.job(fault) if mode == "service" else {}
	if mode == "service":
		Faults.apply(state, fault, _rng)
	# a used motor: light normal wear on the bearings
	for n: String in state.bearings:
		state.bearings[n].wear = maxf(state.bearings[n].wear, _rng.randf_range(0.02, 0.1))
	state.rebuild()
	removed.clear()
	history.clear()
	notebook.clear()
	measured.clear()
	datasheet.clear()
	diagnosis = ""
	repairs.clear()
	mistakes.clear()
	final_test.clear()
	finished = false
	started_ms = Time.get_ticks_msec()
	_say("New job: %s" % title(), "info")
	changed.emit()


func title() -> String:
	match mode:
		"reverse":
			return "Reverse-engineer %s" % spec.name
		"service":
			return "Service: %s (%s)" % [job.get("title", ""), spec.name]
	return "Free lab: %s" % spec.name


func _say(text: String, kind := "info") -> void:
	message.emit(text, kind)


# --- teardown and reassembly -----------------------------------------------------------------

func plan() -> Dictionary:
	return TeardownPlan.plan(spec)


func is_removed(id: String) -> bool:
	return removed.has(id)


## True when nothing is off the motor.
func is_assembled() -> bool:
	return removed.is_empty()


## The windings can be reached (bell / rotor off).
func windings_exposed() -> bool:
	return is_removed("bell") or is_removed("rotor")


## Tries to take `id` off with `tool`. Returns {ok, text}.
func take_off(id: String, tool: String) -> Dictionary:
	var p: Dictionary = plan().get(id, {})
	if p.is_empty():
		return {"ok": false, "text": "That part stays on the bench."}
	if is_removed(id):
		return {"ok": false, "text": "It's already off."}
	for n: String in p.needs:
		if not is_removed(n):
			return {"ok": false, "text": "Something is still holding it: take the %s off first." % n.replace("_", " ")}
	if tool != p.tool:
		mistakes.append("wrong tool on %s (%s)" % [id, tool])
		return {"ok": false, "text": TeardownPlan.wrong_tool(tool, id)}
	removed[id] = true
	history.append("off: %s" % id)
	if id == "grub_screw":
		state.grub_locked = false
	changed.emit()
	return {"ok": true, "text": p.verb}


## Tries to put `id` back with `tool`. `ring` = which bearing ring the press pushes on.
func put_on(id: String, tool: String, ring := "") -> Dictionary:
	var p: Dictionary = plan().get(id, {})
	if not is_removed(id):
		return {"ok": false, "text": "It's already in place."}
	var on_rotor := TeardownPlan.rides_on_rotor(spec, id)
	if on_rotor and not is_removed("rotor"):
		return {"ok": false, "text": "The bearings go onto the shaft with the rotor out on the bench."}
	for n: String in p.sits_on:
		if is_removed(n):
			# the shim and wave washer can be forgotten (with consequences); the rest can't
			return {"ok": false, "text": "Put the %s back first." % n.replace("_", " ")}
	if tool != p.put:
		mistakes.append("wrong tool fitting %s (%s)" % [id, tool])
		return {"ok": false, "text": "Use the %s to fit it." % TeardownPlan.TOOLS[p.put].name}
	var text := "Fitted the %s." % id.replace("_", " ")
	if id.begins_with("bearing"):
		var want := TeardownPlan.press_ring(spec)
		var bname := _bearing_key(id)
		if ring != want:
			state.bearings[bname].brinelled = true
			mistakes.append("pressed the %s bearing on the %s ring" % [bname, ring])
			text = "The press pushed through the balls: you felt a crunch. The races are dented (brinelled)."
			_say(text, "error")
		else:
			text = "Pressed in square, pushing on the %s ring: the fit ring takes the force, not the balls." % want
		state.rebuild()
	if id == "circlip" and is_removed("shim"):
		state.shim_present = false
		text += " The shim is still on the tray: the bell now has end play."
		mistakes.append("left the shim out")
	if id == "rear_cap" and is_removed("wave_washer"):
		text += " The wave washer is still on the tray: the bearings have no preload."
		mistakes.append("left the wave washer out")
	if id == "shim":
		state.shim_present = true
	removed.erase(id)
	if on_rotor:
		pass
	history.append("on: %s" % id)
	changed.emit()
	return {"ok": true, "text": text}


func _bearing_key(id: String) -> String:
	return id.trim_prefix("bearing_")


## Next part to take off in the standard order (guided hints), or "".
func next_off() -> String:
	for id: String in TeardownPlan.order(spec):
		if not is_removed(id):
			var ok := true
			for n: String in plan()[id].needs:
				if not is_removed(n):
					ok = false
			if ok:
				return id
	return ""


## Next part to put back (reverse order), or "".
func next_on() -> String:
	var order := TeardownPlan.order(spec).duplicate()
	order.reverse()
	if is_removed("grub_screw"):
		order.push_front("grub_screw")
	for id: String in order:
		if is_removed(id):
			return id
	return ""


# --- notebook --------------------------------------------------------------------------------

func note(key: String, text: String, value: Variant = null) -> void:
	if value != null:
		measured[key] = value
	var line := text
	if notebook.is_empty() or notebook[-1] != line:
		notebook.append(line)
		if notebook.size() > 60:
			notebook.pop_front()
	changed.emit()


# --- repairs ---------------------------------------------------------------------------------

## Repairs the learner can do now: [{id, title, needs_text, available}].
func repair_options() -> Array:
	var out: Array = []
	var outr := spec.kind == "outrunner"
	for n: String in state.bearings:
		var part := "bearing_" + n
		out.append({"id": "bearing:" + n, "title": "Fit a new %s bearing (%s)" % [n, state.bearings[n].type],
			"available": is_removed(part), "needs": "take the %s bearing out first" % n})
	if outr:
		out.append({"id": "shaft", "title": "Press in a new shaft", "available": is_removed("bell") and is_removed("grub_screw"),
			"needs": "bell off and grub screw out"})
		out.append({"id": "clean", "title": "Clean the magnets (tape off steel grit)", "available": is_removed("bell"), "needs": "bell off"})
		out.append({"id": "new_bell", "title": "Replace the bell with new magnets", "available": is_removed("bell"), "needs": "bell off"})
		out.append({"id": "reglue", "title": "Re-glue the selected magnet", "available": is_removed("bell"), "needs": "bell off"})
	else:
		out.append({"id": "hall", "title": "Replace the dead Hall sensor", "available": is_removed("hall_board"), "needs": "Hall board out"})
		out.append({"id": "new_rotor", "title": "Replace the rotor (new magnets)", "available": is_removed("rotor"), "needs": "rotor out"})
	out.append({"id": "resolder", "title": "Re-solder the lead joints", "available": windings_exposed(), "needs": "windings exposed"})
	out.append({"id": "rewind", "title": "Strip and rewind the stator (winding bench)", "available": is_removed("stator") if outr else is_removed("rotor"),
		"needs": "stator off the base" if outr else "rotor out"})
	return out


func do_repair(id: String, magnet := -1, polarity := 1) -> Dictionary:
	var text := ""
	match id.get_slice(":", 0):
		"bearing":
			var n := id.get_slice(":", 1)
			state.bearings[n] = {"type": state.bearings[n].type, "wear": 0.0, "brinelled": false, "new": true}
			text = "New %s bearing ready to press in." % state.bearings[n].type
		"shaft":
			state.runout_mm = 0.004
			text = "New shaft pressed in. Remember the grub screw with threadlocker."
		"clean":
			state.debris = 0
			text = "Magnets cleaned with tape: the grit is gone."
		"new_bell", "new_rotor":
			for k in state.magnets.size():
				state.magnets[k] = {"strength": 1.0, "polarity": 1, "shift": 0.0, "loose": false, "cracked": false, "present": true}
			state.runout_mm = minf(state.runout_mm, 0.004) if id == "new_bell" else state.runout_mm
			text = "New %s fitted (fresh magnets)." % ("bell" if id == "new_bell" else "rotor")
		"reglue":
			if magnet < 0:
				return {"ok": false, "text": "Select a magnet first (inspection bench, or click it here)."}
			var m: Dictionary = state.magnets[magnet]
			m.shift = 0.0
			m.loose = false
			m.present = true
			m.strength = maxf(m.strength, 0.95)
			m.polarity = polarity
			text = "Magnet %d glued with %s facing the stator." % [magnet + 1, _face(magnet, polarity)]
			if polarity < 0:
				mistakes.append("glued magnet %d the wrong way round" % (magnet + 1))
		"hall":
			state.hall_dead = -1
			text = "New Hall sensor soldered in."
		"resolder":
			state.open_phase = -1
			text = "Lead joints cleaned, re-soldered and sleeved."
		"rewind":
			return {"ok": false, "text": "Go to the winding bench to rewind."}
	repairs.append(id)
	state.rebuild()
	history.append("repair: %s" % id)
	changed.emit()
	return {"ok": true, "text": text}


func _face(k: int, polarity: int) -> String:
	var north := (k % 2 == 0) == (polarity > 0)
	return "north" if north else "south"


## Applies a rewind: new layout, fresh insulation.
func rewind(coils: Array, connection: String) -> Dictionary:
	var issues := Winding.check(coils, spec.slots, spec.poles)
	state.coils = coils
	state.connection = connection
	state.rewound = true
	state.shorted = [0.0, 0.0, 0.0]
	state.burnt_teeth.clear()
	state.insulation_mohm = 2500.0
	state.open_phase = -1
	state.rebuild()
	repairs.append("rewind")
	if not issues.is_empty():
		mistakes.append("rewind: " + issues[0])
	changed.emit()
	return {"ok": issues.is_empty(), "issues": issues}


# --- grading ---------------------------------------------------------------------------------

## Datasheet fields and how they are graded.
func grade_datasheet() -> Array:
	var rows: Array = []
	var d := datasheet
	rows.append(_row("Slots (teeth)", d.get("slots", ""), str(spec.slots), str(d.get("slots", "")) == str(spec.slots)))
	rows.append(_row("Poles (magnets)", d.get("poles", ""), str(spec.poles), str(d.get("poles", "")) == str(spec.poles)))
	rows.append(_row("Connection", d.get("connection", ""), "Y (star)" if spec.connection == "Y" else "Δ (delta)", d.get("connection", "") == spec.connection))
	var kv := float(d.get("kv", 0.0))
	rows.append(_row("KV (rpm/V)", d.get("kv", ""), "%.0f" % spec.kv, kv > 0.0 and absf(kv - spec.kv) / spec.kv <= 0.05))
	var r := float(d.get("r_mohm", 0.0))
	rows.append(_row("R line-line (mΩ)", d.get("r_mohm", ""), "%.0f" % (spec.r_ll * 1000.0), r > 0.0 and absf(r - spec.r_ll * 1000.0) / (spec.r_ll * 1000.0) <= 0.1))
	var wtext: String = d.get("winding", "")
	var truth := Winding.to_text(Winding.design(spec.slots, spec.poles))
	rows.append(_row("Winding", wtext, truth, Winding.equivalent(wtext, truth)))
	rows.append(_row("Stator size", d.get("size", ""), spec.size_code, str(d.get("size", "")).strip_edges() == spec.size_code))
	return rows


func _row(field: String, answer: Variant, truth: String, ok: bool) -> Dictionary:
	return {"field": field, "answer": str(answer), "truth": truth, "ok": ok}


func diagnosis_ok() -> bool:
	return diagnosis == fault


## Final test on the stand: compares the run with the healthy design.
func record_final_test(result: Dictionary) -> void:
	final_test = result
	history.append("final test: %s" % ("PASS" if result.get("pass", false) else "FAIL"))
	changed.emit()


func report() -> Dictionary:
	var score := 0
	var max_score := 0
	var lines: Array[String] = []
	if mode == "reverse":
		for r: Dictionary in grade_datasheet():
			max_score += 10
			if r.ok:
				score += 10
			lines.append("%s %s: %s (actual %s)" % ["✔" if r.ok else "✘", r.field, r.answer if r.answer != "" else "—", r.truth])
	elif mode == "service":
		max_score += 40
		if diagnosis_ok():
			score += 40
			lines.append("✔ Diagnosis: %s" % Faults.CAUSES[fault])
		else:
			lines.append("✘ Diagnosis: %s (actual: %s)" % [Faults.CAUSES.get(diagnosis, "none given"), Faults.CAUSES[fault]])
		max_score += 40
		var left := state.problems()
		if left.is_empty():
			score += 40
			lines.append("✔ Motor repaired: nothing left wrong")
		else:
			for p in left:
				lines.append("✘ Still wrong: %s" % p)
		max_score += 20
		if final_test.get("pass", false):
			score += 20
			lines.append("✔ Final test passed")
		else:
			lines.append("✘ Final test %s" % ("failed" if not final_test.is_empty() else "not run"))
	var penalty := mini(mistakes.size() * 3, 20)
	if max_score > 0:
		score = maxi(score - penalty, 0)
	for m in mistakes:
		lines.append("⚠ %s" % m)
	var minutes := (Time.get_ticks_msec() - started_ms) / 60000.0
	return {"score": score, "max": max_score, "lines": lines, "minutes": minutes}
