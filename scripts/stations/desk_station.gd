extends Station
## Bench 1, the job desk: pick a job (reverse-engineer a mystery motor, service a customer's
## motor, or a free lab), read the customer's ticket, fill in the datasheet or the diagnosis,
## and hand in the report, which is graded against the hidden truth.

const MODES := [["reverse", "Reverse-engineer a mystery motor"], ["service", "Service a customer's motor"], ["free", "Free lab (healthy motor)"]]
const MOTORS := [["2212", "Drone outrunner 2212-920KV"], ["57BL", "Industrial inrunner 57BL-24V"], ["mystery", "Mystery outrunner (random design)"]]

var model := MotorModel.new()
var ticket := Label3D.new()
var _pick_mode := 1
var _pick_motor := 0
var _pick_fault := 0          ## 0 = random (hidden)
var _guided := true
var _job_key := ""
var _report: Dictionary = {}
var _job_box := VBoxContainer.new()
var _fault_option: OptionButton
var _motor_option: OptionButton
var _clock: Label
var _fields := {}


func _build() -> void:
	_guided = session.guided
	model.name = "DeskMotor"
	add_child(model)
	ticket.font = MeshUtil.math_font()
	ticket.font_size = 30
	ticket.pixel_size = 0.0011
	ticket.outline_size = 0
	ticket.modulate = Color(0.12, 0.12, 0.14)
	ticket.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ticket.width = 520
	ticket.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	ticket.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	ticket.rotation.x = -PI * 0.5
	# top-aligned, so the label's origin sits at the paper's far edge (paper spans z ±0.21)
	ticket.position = bench + Vector3(0.28, 0.006, 0.05 - 0.19)
	add_child(ticket)
	var paper := MeshUtil.box(Vector3(0.62, 0.002, 0.42), MeshUtil.colored(Color(0.96, 0.94, 0.86), 0.0, 0.9), bench + Vector3(0.28, 0.003, 0.05))
	add_child(paper)
	# the customer's box
	var box_mat := MeshUtil.colored(Color(0.62, 0.48, 0.3), 0.0, 0.9)
	add_child(MeshUtil.box(Vector3(0.3, 0.2, 0.24), box_mat, bench + Vector3(-0.6, 0.1, -0.18)))
	# --- panel ---
	panel.add_child(Ui.title("Job Desk", 26))
	panel.add_child(Ui.text("Pick a job. Mystery motors have a random hidden design; service jobs hide one fault. Your measurements go into the notebook.", 15, UiTheme.MUTED))
	section(panel, "New job")
	var mode_names: Array = []
	for m in MODES:
		mode_names.append(m[1])
	panel.add_child(Ui.option(mode_names, _pick_mode, func(i: int) -> void:
		_pick_mode = i
		_fill_motor_options()))
	_motor_option = Ui.option([], 0, func(i: int) -> void:
		_pick_motor = i
		_fill_fault_options())
	panel.add_child(_motor_option)
	_fault_option = Ui.option([], 0, func(i: int) -> void: _pick_fault = i)
	panel.add_child(_fault_option)
	panel.add_child(Ui.toggle("Guided (next-step hints and explanations)", _guided, func(on: bool) -> void: _guided = on, 16))
	panel.add_child(Ui.button("Start this job", start_job, "Primary", 18))
	_fill_motor_options()
	panel.add_child(Ui.sep())
	panel.add_child(_job_box)
	_job_box.add_theme_constant_override("separation", 8)


func _motor_ids() -> Array:
	match MODES[_pick_mode][0]:
		"reverse":
			return ["mystery"]
		"service":
			return ["2212", "57BL"]
	return ["2212", "57BL", "mystery"]


func _fill_motor_options() -> void:
	_motor_option.clear()
	for id: String in _motor_ids():
		for m in MOTORS:
			if m[0] == id:
				_motor_option.add_item(m[1])
	_pick_motor = 0
	_motor_option.selected = 0
	_fill_fault_options()


func _fill_fault_options() -> void:
	_fault_option.clear()
	_pick_fault = 0
	var service: bool = MODES[_pick_mode][0] == "service"
	_fault_option.visible = service
	if not service:
		return
	_fault_option.add_item("Fault: random, hidden (recommended)")
	for j: Dictionary in Faults.jobs_for(_motor_ids()[_pick_motor]):
		_fault_option.add_item("Instructor: %s (%s)" % [j.title, Faults.CAUSES[j.id]])
	_fault_option.selected = 0


## Starts the job picked in the form (also used by the autotest with explicit values).
func start_job(mode := "", motor := "", fault := "", seed_value := 0) -> void:
	if mode == "":
		mode = MODES[_pick_mode][0]
		motor = _motor_ids()[_pick_motor]
		if mode == "service":
			var jobs := Faults.jobs_for(motor)
			if _pick_fault == 0:
				var rng := RandomNumberGenerator.new()
				rng.randomize()
				fault = jobs[rng.randi_range(0, jobs.size() - 1)].id
			else:
				fault = jobs[_pick_fault - 1].id
	session.guided = _guided
	_report = {}
	session.start(mode, motor, fault if mode == "service" else "none", seed_value)
	main.sfx.play("pop")


func refresh() -> void:
	if _clock:
		_clock.text = "Time on the job: %d min" % int((Time.get_ticks_msec() - session.started_ms) / 60000.0)
	var key := "%s|%s|%d|%s|%d" % [session.mode, session.motor_id, session.seed_value, session.fault, session.started_ms]
	if key == _job_key:
		return
	_job_key = key
	_rebuild_model()
	_rebuild_job_box()
	_update_ticket()


func _rebuild_model() -> void:
	model.build(session.state)
	model.magnify_to(0.2)
	model.position = bench + Vector3(-0.3, 0.0, 0.0)
	model.rotation.y = 0.5
	model.set_clickable(false)


func _update_ticket() -> void:
	var s := session
	var t := "WORK ORDER  #%05d\n\n" % s.seed_value
	match s.mode:
		"reverse":
			t += "Motor: unlabelled outrunner, label worn off.\nCustomer: \"We need spares. Tell us exactly what this is: teeth, magnets, winding, connection, KV and resistance, so a winder can copy it.\""
		"service":
			t += "Motor: %s\nComplaint: %s" % [s.spec.name, s.job.get("complaint", "")]
		_:
			t += "Motor: %s\nFree lab: a healthy motor to explore." % s.spec.name
	ticket.text = t


func _rebuild_job_box() -> void:
	Ui.clear(_job_box)
	_fields.clear()
	var s := session
	section(_job_box, "Current job")
	_job_box.add_child(Ui.text(s.title(), 18, UiTheme.AMBER))
	_clock = Ui.text("", 14, UiTheme.MUTED)
	_job_box.add_child(_clock)
	match s.mode:
		"service":
			_job_box.add_child(Ui.text("Customer: " + s.job.get("complaint", ""), 16))
			if s.guided:
				_job_box.add_child(Ui.text("Hint: " + s.job.get("hint", ""), 15, UiTheme.LILAC))
			section(_job_box, "Diagnosis")
			var causes: Array = ["— choose the root cause —"]
			var ids: Array = [""]
			for id: String in Faults.CAUSES:
				causes.append(Faults.CAUSES[id])
				ids.append(id)
			_job_box.add_child(Ui.option(causes, maxi(ids.find(s.diagnosis), 0), func(i: int) -> void:
				s.diagnosis = ids[i]
				s.note("diagnosis", "Diagnosis: %s" % causes[i])))
		"reverse":
			_job_box.add_child(Ui.text("Work out the design from measurements. Fill in what you found:", 16))
			section(_job_box, "Datasheet")
			_field("slots", "Slots (stator teeth)", "e.g. 12")
			_field("poles", "Poles (magnets)", "e.g. 14")
			var conn := ["— connection —", "Y (star)", "Δ (delta)"]
			var cvals := ["", "Y", "D"]
			var row := Ui.hbox()
			row.add_child(Ui.text("Connection", 16))
			row.add_child(Ui.option(conn, maxi(cvals.find(s.datasheet.get("connection", "")), 0), func(i: int) -> void:
				if cvals[i] == "":
					s.datasheet.erase("connection")
				else:
					s.datasheet["connection"] = cvals[i]))
			_job_box.add_child(row)
			_field("kv", "KV (rpm per volt)", "from the back-EMF test")
			_field("r_mohm", "R line-to-line (mΩ)", "milliohm meter")
			_field("winding", "Winding (letters per tooth)", "e.g. AabBCcaABbcC")
			_field("size", "Stator size code", "diameter+height, e.g. 2212")
		_:
			_job_box.add_child(Ui.text("Nothing is wrong with this motor: use it to learn the benches. Bench 2 takes it apart, bench 3 measures it, bench 4 shows the inside, bench 5 rewinds, bench 6 runs it.", 16))
	if s.mode != "free":
		_job_box.add_child(Ui.button("Hand in the report", hand_in, "Primary", 18))
	if not _report.is_empty():
		_show_report()


func _field(key: String, label: String, placeholder: String) -> void:
	var row := Ui.hbox()
	var l := Ui.text(label, 16)
	l.custom_minimum_size.x = 210
	row.add_child(l)
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.text = str(session.datasheet.get(key, ""))
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	e.add_theme_font_size_override("font_size", 16)
	e.text_changed.connect(func(t: String) -> void:
		if t.strip_edges() == "":
			session.datasheet.erase(key)
		else:
			session.datasheet[key] = t.strip_edges())
	e.focus_entered.connect(func() -> void: main.desktop_camera.typing = true)
	e.focus_exited.connect(func() -> void: main.desktop_camera.typing = false)
	row.add_child(e)
	_job_box.add_child(row)
	_fields[key] = e


## Sets a datasheet answer as if typed (autotest).
func set_answer(key: String, value: String) -> void:
	session.datasheet[key] = value
	if _fields.has(key):
		(_fields[key] as LineEdit).text = value


func hand_in() -> void:
	_report = session.report()
	session.finished = true
	var pct: float = 100.0 * _report.score / maxf(_report.max, 1.0)
	say("Report handed in: %d / %d (%.0f %%)" % [_report.score, _report.max, pct], "ok" if pct >= 70.0 else "warn")
	_rebuild_job_box()


func report() -> Dictionary:
	return _report


func _show_report() -> void:
	section(_job_box, "Report")
	var pct: float = 100.0 * _report.score / maxf(_report.max, 1.0)
	_job_box.add_child(Ui.title("Score %d / %d  (%.0f %%)" % [_report.score, _report.max, pct], 22, UiTheme.GREEN if pct >= 70.0 else UiTheme.AMBER))
	for line: String in _report.lines:
		var kind := "ok" if line.begins_with("✔") else ("warn" if line.begins_with("⚠") else "error")
		_job_box.add_child(Ui.status(line, kind, 15))
	_job_box.add_child(Ui.text("%.0f minutes. Mistakes cost 3 points each (max 20)." % _report.minutes, 14, UiTheme.MUTED))
	if session.mode == "reverse":
		var s := session.spec
		_job_box.add_child(Ui.text("The real design: %dN%dP, %s, %.0f KV, %.0f mΩ, winding %s, %s stator, %s bearings." %
			[s.slots, s.poles, "star" if s.connection == "Y" else "delta", s.kv, s.r_ll * 1000.0, Winding.to_text(Winding.design(s.slots, s.poles)), s.size_code, s.bearings[0]], 15, UiTheme.MUTED))


func view() -> Array:
	return [bench + Vector3(0.0, 0.62, 0.78), bench + Vector3(0.0, 0.0, -0.05)]


func view_width() -> float:
	return 1.2
