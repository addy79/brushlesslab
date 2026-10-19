extends Station
## Bench 2, teardown and reassembly. Pick a tool from the rack, then click a part: if
## nothing holds it and the tool fits, it comes off and goes to the tray (click it again
## to fit it back). Hand checks (turning the shaft, spinning and rocking bearings) give
## the feel a technician uses to find bearing, magnet and debris faults.

## Where the motor stands and the parts tray lies (bench space, metres; rect x/z).
const MOTOR_AT := Vector3(-0.36, 0.0, -0.06)
const TRAY_RECT := Rect2(-0.16, -0.3, 0.5, 0.5)
const RACK := ["hand", "wrench", "circlip_pliers", "tweezers", "hex_1_5", "hex_3", "phillips", "mallet", "heat_gun", "punch", "bearing_puller", "arbor_press", "soldering_iron"]

var model := MotorModel.new()
var tool := "hand"
## Which bearing ring the arbor press pushes on.
var press_ring := "outer"
var _scale := 1.0
## Tray place (model-space offset) of each part.
var _tray := {}
var _offsets := {}
var _rack := {}
var _parts_box := VBoxContainer.new()
var _checks_box := VBoxContainer.new()
var _tool_label: Label
var _ring_row: HBoxContainer
var _tool_buttons := {}


func _build() -> void:
	model.name = "Motor"
	add_child(model)
	model.part_clicked.connect(click_part)
	var tray := MeshUtil.box(Vector3(TRAY_RECT.size.x + 0.04, 0.008, TRAY_RECT.size.y + 0.04), MeshUtil.colored(Color(0.22, 0.24, 0.27), 0.7, 0.45),
		bench + Vector3(TRAY_RECT.get_center().x, 0.002, TRAY_RECT.get_center().y))
	add_child(tray)
	var tl := MeshUtil.label("parts tray (in teardown order)", 26, false)
	tl.pixel_size = 0.0011
	tl.outline_size = 0
	tl.modulate = Color(0.75, 0.8, 0.85)
	tl.rotation.x = -PI * 0.5
	tl.position = bench + Vector3(TRAY_RECT.get_center().x, 0.008, TRAY_RECT.end.y + 0.005)
	add_child(tl)
	_build_model()
	_build_rack()
	# --- panel ---
	panel.add_child(Ui.title("Teardown & reassembly", 26))
	panel.add_child(Ui.text("Choose a tool, then click a part on the motor (or in the list). Parts on the tray go back the same way: choose the tool that fits them and click them.", 15, UiTheme.MUTED))
	section(panel, "Tool")
	var flow := Ui.flow(6)
	for id: String in RACK:
		var t: Dictionary = TeardownPlan.TOOLS[id]
		var b := Ui.button("%s %s" % [t.icon, t.name], select_tool.bind(id), "Chip", 15)
		b.toggle_mode = true
		flow.add_child(b)
		_tool_buttons[id] = b
	panel.add_child(flow)
	_tool_label = Ui.text("", 15, UiTheme.AMBER)
	panel.add_child(_tool_label)
	_ring_row = Ui.hbox()
	_ring_row.add_child(Ui.text("Press pushes on the", 16))
	_ring_row.add_child(Ui.option(["outer ring", "inner ring"], 0, func(i: int) -> void: press_ring = ["outer", "inner"][i]))
	panel.add_child(_ring_row)
	section(panel, "Parts")
	panel.add_child(_parts_box)
	section(panel, "Hand checks")
	panel.add_child(_checks_box)
	select_tool("hand")


func _build_model() -> void:
	model.build(session.state)
	_scale = model.magnify_to(0.22)
	model.position = bench + MOTOR_AT
	_layout_tray()
	_offsets.clear()
	_place_parts(false)


## Box of a part in model space (mm): [centre, size], from its fitted collision box.
func _part_box(id: String) -> Array:
	var p: Node3D = model.parts[id]
	for c in p.get_children():
		if c is CollisionShape3D and (c as CollisionShape3D).shape is BoxShape3D:
			var size: Vector3 = ((c as CollisionShape3D).shape as BoxShape3D).size
			return [model.parts[id].transform * (c as CollisionShape3D).position, size]
	return [p.position, Vector3.ONE * 3.0]


## Gives every removable part a fixed place on the parts tray, packed in rows in the
## order they come off, so the tray reads like the teardown sequence.
func _layout_tray() -> void:
	_tray.clear()
	var ids: Array = TeardownPlan.order(session.spec).duplicate()
	if session.spec.kind == "outrunner":
		ids.insert(ids.find("bell") + 1, "grub_screw")
	var x := TRAY_RECT.position.x
	var z := TRAY_RECT.position.y
	var row_d := 0.0
	var gap := 0.035
	for id: String in ids:
		var box := _part_box(id)
		var size: Vector3 = box[1] * _scale
		if x + size.x > TRAY_RECT.end.x and x > TRAY_RECT.position.x:
			x = TRAY_RECT.position.x
			z += row_d + gap
			row_d = 0.0
		var world := bench + Vector3(x + size.x * 0.5, 0.0, z + size.z * 0.5)
		var local := (world - model.position) / _scale
		var centre: Vector3 = box[0]
		# sit it on the tray: its lowest point at the bench top (model y = 0)
		_tray[id] = Vector3(local.x - centre.x, (box[1] as Vector3).y * 0.5 - centre.y + 1.0, local.z - centre.z)
		x += size.x + gap
		row_d = maxf(row_d, size.z)
	# the grub screw rides inside the bell: its offset is relative to the bell's place
	if _tray.has("grub_screw"):
		_tray["grub_screw"] -= _tray["bell"]


## Which part carries `id` along with it when it is on (riders move with the carrier).
func _carrier(id: String) -> String:
	if session.spec.kind == "outrunner":
		return "bell" if id == "prop_adapter" else ""
	return "rotor" if id == "bearing_front" or id == "bearing_rear" else ""


func _target_offset(id: String) -> Vector3:
	if session.is_removed(id) and _tray.has(id):
		return _tray[id]
	var c := _carrier(id)
	if c != "" and session.is_removed(c):
		return _tray[c]
	return Vector3.ZERO


## Moves every part to where the session says it is.
func _place_parts(animate := true) -> void:
	for id: String in model.parts:
		var target := _target_offset(id)
		if _offsets.get(id, Vector3.ZERO).is_equal_approx(target) and _offsets.has(id):
			continue
		_offsets[id] = target
		model.move_part(id, target, 0.7 if animate else 0.0)


func _build_rack() -> void:
	var n := RACK.size()
	for i in n:
		var id: String = RACK[i]
		var c := Clickable.new()
		c.id = id
		c.tooltip = TeardownPlan.TOOLS[id].name
		var x := -0.74 + 1.48 * i / (n - 1)
		c.position = bench + Vector3(x, 0.0, 0.31)
		add_child(c)
		c.add_child(_tool_mesh(id))
		var l := MeshUtil.label(TeardownPlan.TOOLS[id].icon, 40)
		l.pixel_size = 0.0009
		l.position = Vector3(0, 0.07, 0)
		l.no_depth_test = false
		c.add_child(l)
		c.fit_box(0.012)
		c.clicked.connect(func(_n: Clickable) -> void: select_tool(id))
		_rack[id] = c


## A simple recognisable shape for each tool, lying on the bench.
func _tool_mesh(id: String) -> Node3D:
	var n := Node3D.new()
	var grip := MeshUtil.colored(Color(0.85, 0.2, 0.15), 0.0, 0.6)
	var steel := MeshUtil.mat("steel")
	match id:
		"hand":
			n.add_child(MeshUtil.box(Vector3(0.06, 0.012, 0.07), MeshUtil.colored(Color(0.2, 0.5, 0.8), 0.0, 0.8), Vector3(0, 0.006, 0)))
		"wrench":
			n.add_child(MeshUtil.box(Vector3(0.012, 0.006, 0.1), steel, Vector3(0, 0.004, 0)))
			n.add_child(MeshUtil.cylinder(0.014, 0.006, steel, Vector3(0, 0.004, -0.05)))
		"circlip_pliers", "bearing_puller":
			n.add_child(MeshUtil.box(Vector3(0.008, 0.01, 0.09), grip, Vector3(-0.008, 0.006, 0.01)))
			n.add_child(MeshUtil.box(Vector3(0.008, 0.01, 0.09), grip, Vector3(0.008, 0.006, 0.01)))
			n.add_child(MeshUtil.box(Vector3(0.006, 0.008, 0.04), steel, Vector3(0, 0.006, -0.05)))
		"tweezers":
			n.add_child(MeshUtil.box(Vector3(0.004, 0.004, 0.1), steel, Vector3(-0.004, 0.003, 0)))
			n.add_child(MeshUtil.box(Vector3(0.004, 0.004, 0.1), steel, Vector3(0.004, 0.003, 0)))
		"hex_1_5", "hex_3":
			var r := 0.002 if id == "hex_1_5" else 0.0035
			var shaft := MeshUtil.cylinder(r, 0.08, MeshUtil.mat("dark_steel"), Vector3(0, r, 0), 6)
			shaft.rotation.x = PI * 0.5
			n.add_child(shaft)
			n.add_child(MeshUtil.box(Vector3(0.025, r * 2.0, r * 2.0), MeshUtil.mat("dark_steel"), Vector3(0.012, r, 0.04)))
		"phillips":
			var h := MeshUtil.cylinder(0.009, 0.06, grip, Vector3(0, 0.009, 0.025))
			h.rotation.x = PI * 0.5
			n.add_child(h)
			var s := MeshUtil.cylinder(0.002, 0.05, steel, Vector3(0, 0.009, -0.03))
			s.rotation.x = PI * 0.5
			n.add_child(s)
		"mallet":
			var hd := MeshUtil.cylinder(0.016, 0.05, MeshUtil.colored(Color(0.85, 0.75, 0.2), 0.0, 0.7), Vector3(0, 0.016, -0.04))
			hd.rotation.z = PI * 0.5
			n.add_child(hd)
			n.add_child(MeshUtil.box(Vector3(0.01, 0.01, 0.08), MeshUtil.mat("wood"), Vector3(0, 0.008, 0.02)))
		"heat_gun":
			n.add_child(MeshUtil.box(Vector3(0.035, 0.04, 0.1), MeshUtil.colored(Color(0.9, 0.5, 0.1), 0.0, 0.6), Vector3(0, 0.02, 0)))
			var noz := MeshUtil.cylinder(0.012, 0.04, steel, Vector3(0, 0.03, -0.065))
			noz.rotation.x = PI * 0.5
			n.add_child(noz)
		"punch":
			var p := MeshUtil.cylinder(0.004, 0.1, MeshUtil.mat("dark_steel"), Vector3(0, 0.004, 0))
			p.rotation.x = PI * 0.5
			n.add_child(p)
		"arbor_press":
			n.add_child(MeshUtil.box(Vector3(0.06, 0.012, 0.06), MeshUtil.colored(Color(0.2, 0.35, 0.6), 0.5, 0.5), Vector3(0, 0.006, 0)))
			n.add_child(MeshUtil.box(Vector3(0.014, 0.12, 0.014), MeshUtil.colored(Color(0.2, 0.35, 0.6), 0.5, 0.5), Vector3(0, 0.06, -0.022)))
			n.add_child(MeshUtil.cylinder(0.006, 0.05, steel, Vector3(0, 0.08, 0.0)))
		"soldering_iron":
			var b := MeshUtil.cylinder(0.008, 0.09, MeshUtil.colored(Color(0.15, 0.15, 0.15), 0.0, 0.5), Vector3(0, 0.008, 0.01))
			b.rotation.x = PI * 0.5
			n.add_child(b)
			var tip := MeshUtil.cylinder(0.002, 0.04, steel, Vector3(0, 0.008, -0.055))
			tip.rotation.x = PI * 0.5
			n.add_child(tip)
	return n


func select_tool(id: String) -> void:
	tool = id
	for t: String in _rack:
		(_rack[t] as Node3D).position.y = bench.y + (0.035 if t == id else 0.0)
	for t: String in _tool_buttons:
		(_tool_buttons[t] as Button).set_pressed_no_signal(t == id)
	if _tool_label:
		_tool_label.text = "In your hand: %s %s" % [TeardownPlan.TOOLS[id].icon, TeardownPlan.TOOLS[id].name]
	if _ring_row:
		_ring_row.visible = id == "arbor_press"
	main.sfx.play("click")


## A click on a part (3D or list): take it off, or fit it back if it is on the tray.
func click_part(id: String) -> void:
	var plan: Dictionary = session.plan()
	if not plan.has(id):
		say("The %s stays on the bench: it is the part everything else is taken off." % id.replace("_", " "), "info")
		return
	var r: Dictionary
	var was_off := session.is_removed(id)
	if was_off:
		r = session.put_on(id, tool, press_ring)
	else:
		r = session.take_off(id, tool)
	if r.ok:
		var sound := "pop"
		match tool:
			"wrench", "hex_1_5", "hex_3", "phillips":
				sound = "ratchet"
			"arbor_press", "bearing_puller", "punch", "mallet":
				sound = "press"
		if id == "bell" or id == "rotor":
			sound = "clack"
		main.sfx.play(sound)
		main.haptics.play("click")
		var why: String = plan[id].why if session.guided and not was_off else ""
		say(r.text + ("  " + why if why != "" else ""), "ok" if not r.text.contains("crunch") else "error")
		if r.text.contains("crunch"):
			model.refresh()
			_offsets.clear()
	else:
		say(r.text, "warn")
		main.sfx.play("error")
	_place_parts()


func refresh() -> void:
	if model.state != session.state:
		_build_model()
	_place_parts()
	_rebuild_parts()
	_rebuild_checks()


func _rebuild_parts() -> void:
	Ui.clear(_parts_box)
	var next_off := session.next_off()
	var next_on := session.next_on()
	for id: String in TeardownPlan.order(session.spec) + (["grub_screw"] if session.spec.kind == "outrunner" else []):
		var p: Dictionary = session.plan()[id]
		var off := session.is_removed(id)
		var row := Ui.hbox(6)
		var state_txt := "on tray" if off else "on motor"
		var b := Ui.button(id.replace("_", " "), click_part.bind(id), "Ghost", 15)
		b.custom_minimum_size.x = 150
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.add_child(b)
		var hint := ""
		if session.guided:
			if not off and id == next_off:
				hint = "take off: %s" % TeardownPlan.TOOLS[p.tool].name
			elif off and id == next_on:
				hint = "fit: %s" % TeardownPlan.TOOLS[p.put].name
		row.add_child(Ui.text(hint if hint != "" else state_txt, 14, UiTheme.LILAC if hint != "" else (UiTheme.AMBER if off else UiTheme.MUTED)))
		_parts_box.add_child(row)
	if session.guided and next_off != "" and not session.is_removed(next_off):
		_parts_box.add_child(Ui.text(session.plan()[next_off].verb, 14, UiTheme.MUTED))


func _rebuild_checks() -> void:
	Ui.clear(_checks_box)
	var rotor_part := "bell" if session.spec.kind == "outrunner" else "rotor"
	if not session.is_removed(rotor_part):
		var row := Ui.flow(6)
		row.add_child(Ui.button("✋ Turn the shaft by hand", turn_by_hand, "", 15))
		row.add_child(Ui.button("⚡ Short the leads and turn", turn_shorted, "", 15))
		_checks_box.add_child(row)
	for n: String in session.state.bearing_names():
		var part := "bearing_" + n
		if not session.is_removed(part):
			continue
		var b: Dictionary = session.state.bearings[n]
		_checks_box.add_child(Ui.text("%s bearing %s%s (on the tray)" % [n.capitalize(), b.type, "  — new" if b.get("new", false) else ""], 15))
		var row := Ui.flow(6)
		row.add_child(Ui.button("Spin it", spin_bearing.bind(n), "Chip", 14))
		row.add_child(Ui.button("Rock it (play)", rock_bearing.bind(n), "Chip", 14))
		row.add_child(Ui.button("Swap for a new %s" % b.type, new_bearing.bind(n), "Chip", 14))
		_checks_box.add_child(row)
	if _checks_box.get_child_count() == 0:
		_checks_box.add_child(Ui.text("Put the %s back to turn the shaft; take a bearing out to check it." % rotor_part, 14, UiTheme.MUTED))


## What turning the shaft by hand feels like: the technician's first test.
func turn_by_hand() -> void:
	var st := session.state
	var spec := session.spec
	var feel: Array[String] = []
	feel.append("%d soft notches per turn (cogging: the LCM of teeth and magnets)" % spec.cogging_steps())
	var wear := st.worst_bearing()
	if wear > 0.5:
		feel.append("rough and gravelly: it grinds")
	elif wear > 0.25:
		feel.append("slightly rough")
	if st.debris > 0:
		feel.append("gritty, something scrapes inside")
	for m: Dictionary in st.magnets:
		if m.loose:
			feel.append("a tick every turn, like something knocking")
			break
	if not st.shim_present:
		feel.append("the shaft moves up and down (end play)")
	if st.runout_mm > 0.03:
		feel.append("the shaft tip visibly wobbles")
	var weak := 0.0
	for m: Dictionary in st.magnets:
		weak = maxf(weak, 1.0 - float(m.strength))
	if weak > 0.12:
		feel.append("the cogging notches feel weaker than on a new motor")
	if st.shorted.max() > 0.0:
		feel.append("when you flick it, it stops sooner than it should (drag)")
	if feel.size() == 1:
		feel.append("otherwise smooth and free")
	note("hand_turn", "Turned by hand: " + ", ".join(feel) + ".", true)
	main.haptics.play("tick")
	var tw := create_tween()
	tw.tween_method(model.set_rotor_angle, 0.0, TAU, 1.2)


## Shorting the three leads makes the windings a brake: every phase should drag the same.
func turn_shorted() -> void:
	var st := session.state
	var t := "Leads shorted: turning is much stiffer and even (back-EMF braking)."
	if st.open_phase >= 0:
		t = "Leads shorted: it brakes, but unevenly: easy spots every electrical turn. One phase is not connected."
	elif st.shorted.max() > 0.0:
		t = "Leads shorted: stiff, but it already dragged before you shorted them: some turns are shorted inside."
	note("short_turn", t, true)
	main.haptics.play("thump")


func spin_bearing(n: String) -> void:
	var r := session.state.bearing_spin(n)
	var feel := "smooth and quiet" if r.rough < 0.2 else ("a bit rough" if r.rough < 0.5 else "rough, it rumbles and grinds")
	note("spin_" + n, "%s bearing spun by hand: runs %.1f s, %s." % [n.capitalize(), r.seconds, feel], r.seconds)
	main.haptics.play("tick")


func rock_bearing(n: String) -> void:
	var p := session.state.bearing_play(n) * 1000.0
	note("play_" + n, "%s bearing radial play ≈ %.0f µm %s." % [n.capitalize(), p, "(fine)" if p < 15.0 else "(worn: new ones have ~5 µm)"], p)


func new_bearing(n: String) -> void:
	var r := session.do_repair("bearing:" + n)
	say(r.text + " Now press it in with the arbor press.", "ok" if r.ok else "warn")


func view() -> Array:
	return [bench + Vector3(-0.08, 0.75, 0.92), bench + Vector3(-0.08, 0.0, -0.04)]


func view_width() -> float:
	return 1.05
