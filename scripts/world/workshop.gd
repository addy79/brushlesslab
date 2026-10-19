class_name Workshop
extends Node3D
## The motor workshop: a room with six benches in a row (one per station), each with
## its name on a sign, an ESD mat, a pegboard and a lamp. All geometry is built here.

const BENCH_SIZE := Vector3(1.7, 0.9, 0.8)


func build(titles: Array) -> void:
	var count := titles.size()
	var x0 := Main.bench_position(0).x - 1.6
	var x1 := Main.bench_position(count - 1).x + 1.6
	var w := x1 - x0
	var cx := (x0 + x1) * 0.5
	# floor (epoxy grey), walls, ceiling
	var floor_mat := MeshUtil.colored(Color(0.32, 0.34, 0.36), 0.0, 0.85)
	add_child(MeshUtil.box(Vector3(w, 0.05, 7.0), floor_mat, Vector3(cx, -0.025, 1.6)))
	# safety walkway lines
	var yellow := MeshUtil.colored(Color(0.9, 0.75, 0.15), 0.0, 0.7)
	for z in [0.95, 2.6]:
		add_child(MeshUtil.box(Vector3(w - 0.4, 0.004, 0.06), yellow, Vector3(cx, 0.002, z)))
	var wall_mat := MeshUtil.colored(Color(0.78, 0.8, 0.82), 0.0, 0.9)
	add_child(MeshUtil.box(Vector3(w, 3.2, 0.1), wall_mat, Vector3(cx, 1.6, -0.75)))
	add_child(MeshUtil.box(Vector3(0.1, 3.2, 7.0), wall_mat, Vector3(x0, 1.6, 1.6)))
	add_child(MeshUtil.box(Vector3(0.1, 3.2, 7.0), wall_mat, Vector3(x1, 1.6, 1.6)))
	var stripe := MeshUtil.colored(Color(0.15, 0.32, 0.36), 0.0, 0.8)
	add_child(MeshUtil.box(Vector3(w, 0.9, 0.02), stripe, Vector3(cx, 0.45, -0.69)))
	add_child(MeshUtil.box(Vector3(w, 0.05, 7.0), MeshUtil.colored(Color(0.9, 0.9, 0.9), 0.0, 0.9), Vector3(cx, 3.2, 1.6)))
	# title on the back wall
	var sign := MeshUtil.label("BRUSHLESS LAB  ·  motor reverse-engineering & service", 64, false)
	sign.pixel_size = 0.003
	sign.modulate = Color("e8955a")
	sign.outline_size = 0
	sign.position = Vector3(cx, 2.85, -0.69)
	add_child(sign)
	for i in count:
		_bench(i, str(titles[i]))
	# lights: ceiling strips
	for i in count:
		var l := OmniLight3D.new()
		l.position = Main.bench_position(i) + Vector3(0, 1.6, 0.4)
		l.omni_range = 3.2
		l.light_energy = 0.9
		l.shadow_enabled = i % 2 == 0
		add_child(l)
		var strip := MeshUtil.box(Vector3(1.2, 0.03, 0.12), MeshUtil.mat("glow"), Vector3(l.position.x, 3.17, 0.4))
		strip.material_override = _strip_mat()
		add_child(strip)


func _strip_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1, 1, 0.97)
	m.emission_enabled = true
	m.emission = Color(1, 0.98, 0.92)
	m.emission_energy_multiplier = 1.5
	return m


func _bench(i: int, title: String) -> void:
	var top := Main.bench_position(i)
	var b := Node3D.new()
	b.name = "Bench%d" % (i + 1)
	add_child(b)
	var s := BENCH_SIZE
	# worktop, frame, legs, shelf
	b.add_child(MeshUtil.box(Vector3(s.x, 0.04, s.z), MeshUtil.colored(Color(0.62, 0.5, 0.36), 0.0, 0.7), top + Vector3(0, -0.02, 0)))
	b.add_child(MeshUtil.box(Vector3(s.x - 0.3, 0.004, s.z - 0.2), MeshUtil.mat("mat_green"), top + Vector3(0, 0.002, 0.02)))
	var frame := MeshUtil.colored(Color(0.18, 0.3, 0.42), 0.6, 0.45)
	for dx in [-1, 1]:
		for dz in [-1, 1]:
			b.add_child(MeshUtil.box(Vector3(0.05, s.y - 0.04, 0.05), frame, top + Vector3(dx * (s.x * 0.5 - 0.06), -s.y * 0.5 - 0.02, dz * (s.z * 0.5 - 0.06))))
	b.add_child(MeshUtil.box(Vector3(s.x - 0.1, 0.03, s.z - 0.1), frame, top + Vector3(0, -0.72, 0)))
	b.add_child(MeshUtil.box(Vector3(s.x - 0.1, 0.06, 0.03), frame, top + Vector3(0, -0.07, s.z * 0.5 - 0.04)))
	# pegboard on the wall behind with tool outlines
	var peg := MeshUtil.colored(Color(0.85, 0.82, 0.74), 0.0, 0.9)
	b.add_child(MeshUtil.box(Vector3(s.x - 0.1, 0.7, 0.02), peg, Vector3(top.x, top.y + 0.75, -0.68)))
	var dot := MeshUtil.colored(Color(0.45, 0.42, 0.38), 0.0, 0.9)
	for gx in 14:
		for gy in 6:
			b.add_child(MeshUtil.box(Vector3(0.012, 0.012, 0.004), dot, Vector3(top.x - 0.72 + gx * 0.11, top.y + 0.47 + gy * 0.11, -0.665)))
	# station sign
	var plate := MeshUtil.box(Vector3(0.9, 0.16, 0.02), MeshUtil.colored(Color(0.1, 0.11, 0.13), 0.2, 0.5), Vector3(top.x, top.y + 1.28, -0.66))
	b.add_child(plate)
	var l := MeshUtil.label("%d  %s" % [i + 1, title], 52, false)
	l.pixel_size = 0.0022
	l.outline_size = 0
	l.modulate = Color("e8ecf4")
	l.position = Vector3(top.x, top.y + 1.28, -0.645)
	b.add_child(l)
	# bench lamp (arm + head)
	var lamp_mat := MeshUtil.colored(Color(0.9, 0.9, 0.88), 0.3, 0.4)
	b.add_child(MeshUtil.cylinder(0.06, 0.02, lamp_mat, top + Vector3(-s.x * 0.5 + 0.12, 0.01, -0.28)))
	var arm := MeshUtil.cylinder(0.01, 0.55, lamp_mat, top + Vector3(-s.x * 0.5 + 0.12, 0.28, -0.28))
	b.add_child(arm)
	var head := MeshUtil.cylinder(0.07, 0.05, lamp_mat, top + Vector3(-s.x * 0.5 + 0.22, 0.55, -0.2))
	head.rotation.z = -0.5
	b.add_child(head)
	var spot := SpotLight3D.new()
	spot.position = top + Vector3(-s.x * 0.5 + 0.22, 0.52, -0.2)
	spot.rotation = Vector3(-PI * 0.5, 0, -0.5)
	spot.rotation_degrees = Vector3(-70, -60, 0)
	spot.spot_range = 1.4
	spot.spot_angle = 40.0
	spot.light_energy = 1.2
	b.add_child(spot)
