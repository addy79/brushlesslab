class_name Main
extends Node3D
## Entry point. Builds the workshop, starts OpenXR when a headset is present (desktop
## mode otherwise), holds the job (Session) and swaps the bench stations.
## Command line (after "--"): --autotest, --station=N, --mode=reverse|service|free,
## --motor=2212|57BL|mystery, --fault=ID, --seed=N, --expert, --xr-preview.

const STATIONS: Array[Dictionary] = [
	{"title": "Job Desk", "script": "res://scripts/stations/desk_station.gd"},
	{"title": "Teardown", "script": "res://scripts/stations/teardown_station.gd"},
	{"title": "Electrical", "script": "res://scripts/stations/electrical_station.gd"},
	{"title": "Inspect & Repair", "script": "res://scripts/stations/inspect_station.gd"},
	{"title": "Winding", "script": "res://scripts/stations/winding_station.gd"},
	{"title": "Test Stand", "script": "res://scripts/stations/test_stand_station.gd"},
]
const BENCH_SPACING := 2.4
const VR_PANEL_W := 820
const VR_PANEL_H := 1040

var xr_interface: XRInterface
var xr_available := false
var xr_active := false
var session := Session.new()
var station: Station
var station_index := -1

var workshop := Workshop.new()
var hud := Hud.new()
var sfx := Sfx.new()
var haptics := Haptics.new()
var locomotion := XRLocomotion.new()
var desktop_camera := FreeFlyCamera.new()
var desktop_pointer := DesktopPointer.new()
var xr_origin := XROrigin3D.new()
var xr_camera := XRCamera3D.new()
var left_hand := XRHand.new()
var right_hand := XRHand.new()
## VR panels: the station's controls (left of the bench) and the job/notebook (right).
var vr_station_panel := ViewportPanel3D.new(VR_PANEL_W)
var vr_job_panel := ViewportPanel3D.new(640)
var _vr_scroll := ScrollContainer.new()
var _vr_job := VBoxContainer.new()
var _vr_tip := Label3D.new()
var _panels_forced := false
var _dirty := true
var _tabs_vr: Array[Button] = []


## Top centre of bench `index` (world space).
static func bench_position(index: int) -> Vector3:
	return Vector3(index * BENCH_SPACING, 0.9, 0.0)


func _ready() -> void:
	InputSetup.register()
	add_child(sfx)
	add_child(haptics)
	_build_world()
	_build_rig()
	haptics.left = left_hand
	haptics.right = right_hand
	var titles: Array = []
	for s in STATIONS:
		titles.append(s.title)
	add_child(hud)
	hud.setup(titles)
	hud.station_requested.connect(load_station)
	hud.xr_requested.connect(func() -> void: set_xr_mode(not xr_active))
	_build_vr_panels(titles)
	get_viewport().size_changed.connect(_fit_view)
	session.changed.connect(func() -> void: _dirty = true)
	session.message.connect(show_message)

	xr_interface = XRServer.find_interface("OpenXR")
	xr_available = xr_interface != null and xr_interface.is_initialized()
	set_xr_mode(xr_available)

	var args := OS.get_cmdline_user_args()
	var first := 0
	var mode := "free"
	var motor := "2212"
	var fault := "none"
	var seed_value := 0
	for a in args:
		var v := a.get_slice("=", 1)
		if a.begins_with("--station="):
			first = clampi(int(v) - 1, 0, STATIONS.size() - 1)
		elif a.begins_with("--mode="):
			mode = v
		elif a.begins_with("--motor="):
			motor = v
		elif a.begins_with("--fault="):
			fault = v
		elif a.begins_with("--seed="):
			seed_value = int(v)
	session.guided = not args.has("--expert")
	session.start(mode, motor, fault, seed_value)
	load_station(first)
	if not xr_available:
		show_message("No VR headset found: desktop mode. Hold the right mouse button to look, H for help.", "info")
	if args.has("--xr-preview"):
		_panels_forced = true
		_apply_panel_visibility()
	if args.has("--autotest"):
		var test: Node = load(OS.get_environment("TEST") if OS.get_environment("TEST") != "" else "res://tests/autotest.gd").new()
		test.set("main", self)
		add_child(test)


# --- world and rig ---------------------------------------------------------------------------

func _build_world() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.55, 0.62, 0.72)
	sky_mat.sky_horizon_color = Color(0.8, 0.8, 0.8)
	sky_mat.ground_bottom_color = Color(0.3, 0.3, 0.3)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.75
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.ssao_enabled = not OS.has_feature("android")
	env.ssao_intensity = 1.2
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55.0, 25.0, 0.0)
	sun.light_energy = 0.35
	add_child(sun)
	var titles: Array = []
	for s in STATIONS:
		titles.append(s.title)
	workshop.name = "Workshop"
	add_child(workshop)
	workshop.build(titles)


func _build_rig() -> void:
	desktop_camera.name = "DesktopCamera"
	desktop_camera.fov = 62.0
	desktop_camera.near = 0.02
	desktop_camera.move_speed = 1.2
	add_child(desktop_camera)
	desktop_pointer.camera = desktop_camera
	add_child(desktop_pointer)
	xr_origin.name = "XROrigin3D"
	add_child(xr_origin)
	xr_camera.name = "XRCamera3D"
	xr_camera.position = Vector3(0.0, 1.6, 0.0)
	xr_camera.near = 0.02
	xr_origin.add_child(xr_camera)
	for hand: XRHand in [left_hand, right_hand]:
		hand.tracker = &"left_hand" if hand == left_hand else &"right_hand"
		hand.pose = &"aim"
		hand.name = "LeftHand" if hand == left_hand else "RightHand"
		xr_origin.add_child(hand)
		hand.button_pressed.connect(_on_xr_button.bind(hand))
	locomotion.name = "Locomotion"
	add_child(locomotion)
	locomotion.setup(xr_origin, xr_camera, left_hand, right_hand)
	_vr_tip.font = MeshUtil.math_font()
	_vr_tip.font_size = 28
	_vr_tip.pixel_size = 0.0009
	_vr_tip.outline_size = 8
	_vr_tip.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_vr_tip.no_depth_test = true
	_vr_tip.render_priority = 20
	_vr_tip.visible = false
	add_child(_vr_tip)


func _build_vr_panels(titles: Array) -> void:
	vr_station_panel.name = "VRStationPanel"
	add_child(vr_station_panel)
	_vr_scroll.custom_minimum_size = Vector2(VR_PANEL_W - 40, VR_PANEL_H)
	_vr_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_vr_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS
	var pc := PanelContainer.new()
	pc.add_child(_vr_scroll)
	vr_station_panel.content.add_child(pc)
	vr_job_panel.name = "VRJobPanel"
	add_child(vr_job_panel)
	var jp := PanelContainer.new()
	vr_job_panel.content.add_child(jp)
	var jv := Ui.vbox(8)
	jp.add_child(jv)
	jv.add_child(Ui.title("⚙ Brushless Lab", 26))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	jv.add_child(grid)
	for i in titles.size():
		var b := Ui.button("%d %s" % [i + 1, titles[i]], load_station.bind(i), "Tab", 18)
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(b)
		_tabs_vr.append(b)
	_vr_job.add_theme_constant_override("separation", 6)
	jv.add_child(_vr_job)


func set_xr_mode(enable: bool) -> void:
	if enable and not xr_available:
		show_message("No OpenXR runtime: staying in desktop mode.", "warn")
		enable = false
	xr_active = enable
	get_viewport().use_xr = enable
	xr_camera.current = enable
	desktop_camera.current = not enable
	desktop_camera.enabled = not enable
	desktop_pointer.enabled = not enable
	left_hand.enabled = enable
	right_hand.enabled = enable
	locomotion.enabled = enable
	if enable:
		if xr_interface is OpenXRInterface:
			var openxr := xr_interface as OpenXRInterface
			if openxr.get_available_display_refresh_rates().has(90.0):
				openxr.display_refresh_rate = 90.0
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_apply_panel_visibility()


func _apply_panel_visibility() -> void:
	var vr := xr_active or _panels_forced
	vr_station_panel.visible = vr
	vr_job_panel.visible = vr
	hud.set_drawer_visible(not vr)
	_place_station_panel()
	_fit_view()


## Puts the station's 2D panel in the desktop drawer or on the VR panel.
func _place_station_panel() -> void:
	if station == null:
		return
	var p := station.panel
	var target: Control = _vr_scroll if (xr_active or _panels_forced) else hud.drawer_holder
	if p.get_parent() == target:
		return
	if p.get_parent():
		p.get_parent().remove_child(p)
	target.add_child(p)


## Desktop: fits the HUD to the window and shifts the camera's lens so the bench sits in
## the middle of the area the drawer leaves free (an off-centre frustum, no rotation).
func _fit_view() -> void:
	var view := get_viewport().get_visible_rect().size
	hud.layout(view)
	var cam := desktop_camera
	# widen the view until the station's working width fits the free area (tall windows)
	if station and view.y > 0.0:
		var v := station.view()
		var d: float = (v[0] as Vector3).distance_to(v[1])
		var free_w := maxf(view.x - (hud.drawer_w + 20.0 if hud.drawer.visible else 0.0), 200.0)
		var need := 2.0 * rad_to_deg(atan(station.view_width() * view.y / free_w / (2.0 * d)))
		cam.fov = clampf(need, 55.0, 85.0)
	cam.projection = Camera3D.PROJECTION_FRUSTUM
	cam.size = 2.0 * cam.near * tan(deg_to_rad(cam.fov) * 0.5)
	var shift_px := (hud.drawer_w + 10.0) * 0.5 if hud.drawer.visible else 0.0
	cam.frustum_offset = Vector2(shift_px / maxf(view.y, 1.0) * cam.size, 0.0)


static func facing(pos: Vector3, target: Vector3) -> Transform3D:
	var dir := target - pos
	dir.y = 0.0
	return Transform3D(Basis.looking_at(-dir.normalized(), Vector3.UP), pos)


func _layout_vr() -> void:
	var stand := station.xr_position()
	var eye := stand + Vector3(0.0, 1.55, 0.0)
	vr_station_panel.transform = facing(stand + Vector3(-1.15, 1.95, -0.35), eye).scaled_local(Vector3.ONE * 1.15)
	vr_job_panel.transform = facing(stand + Vector3(1.1, 1.9, -0.35), eye).scaled_local(Vector3.ONE * 1.15)


# --- stations ------------------------------------------------------------------------------

func load_station(index: int) -> void:
	if index < 0 or index >= STATIONS.size():
		return
	desktop_pointer.pointer.release()
	left_hand.pointer.release()
	right_hand.pointer.release()
	if station:
		station.teardown()
		if station.panel.get_parent():
			station.panel.get_parent().remove_child(station.panel)
		station.panel.queue_free()
		remove_child(station)
		station.queue_free()
		station = null
	var s: Station = load(STATIONS[index].script).new()
	s.name = "Station"
	s.title = STATIONS[index].title
	station = s
	station_index = index
	add_child(s)
	s.message.connect(show_message)
	s.setup(self, index)
	hud.set_station(index)
	for i in _tabs_vr.size():
		_tabs_vr[i].button_pressed = i == index
	_place_station_panel()
	_layout_vr()
	reset_view()
	_dirty = true
	sfx.play("click")


func reset_view() -> void:
	if station == null:
		return
	var v := station.view()
	desktop_camera.reset_view(v[0], v[1])
	_fit_view()
	if xr_active:
		var stand := station.xr_position()
		xr_origin.global_transform = Transform3D(Basis.IDENTITY, stand)
		# put the head over the stand point, facing the bench (-z)
		var head := xr_camera.position
		xr_origin.global_position -= Vector3(head.x, 0.0, head.z)


func show_message(text: String, kind := "info") -> void:
	hud.toast(text, kind, 6.0 if kind == "error" else 4.5)
	if kind == "error":
		sfx.play("error")
		haptics.play("thump")
	elif kind == "ok":
		sfx.play("success")
	if xr_active or _panels_forced:
		_vr_messages.append([text, kind])
		while _vr_messages.size() > 3:
			_vr_messages.pop_front()
		_dirty = true


var _vr_messages: Array = []


# --- every frame ------------------------------------------------------------------------------

func _process(_delta: float) -> void:
	if _dirty:
		_dirty = false
		_refresh_session_views()
	_update_tooltip()


func _refresh_session_views() -> void:
	hud.set_job(session.title())
	hud.set_notebook(session.notebook)
	var next := guide_text() if session.guided else ""
	hud.set_next(("➜ " + next) if next != "" else "")
	if station:
		station.refresh()
	if vr_job_panel.visible:
		Ui.clear(_vr_job)
		_vr_job.add_child(Ui.text(session.title(), 20, UiTheme.AMBER))
		if next != "":
			_vr_job.add_child(Ui.text("➜ " + next, 18, UiTheme.LILAC))
		for m: Array in _vr_messages:
			_vr_job.add_child(Ui.status(m[0], m[1], 17))
		_vr_job.add_child(Ui.title("📓 Notebook", 18, UiTheme.BLUE))
		var start := maxi(session.notebook.size() - 8, 0)
		for i in range(start, session.notebook.size()):
			_vr_job.add_child(Ui.text("• " + session.notebook[i], 16, UiTheme.MUTED))


func _update_tooltip() -> void:
	var tip := ""
	if not xr_active:
		var h: Variant = desktop_pointer.pointer.hovered
		if is_instance_valid(h) and h is Clickable and (h as Clickable).enabled:
			tip = (h as Clickable).tooltip
		hud.set_tooltip(tip, get_viewport().get_mouse_position())
		return
	for hand: XRHand in [right_hand, left_hand]:
		var h: Variant = hand.pointer.hovered
		if is_instance_valid(h) and h is Clickable and (h as Clickable).enabled and (h as Clickable).tooltip != "":
			_vr_tip.text = (h as Clickable).tooltip
			_vr_tip.global_position = hand.pointer.event.hit_position + Vector3(0, 0.05, 0)
			_vr_tip.visible = true
			return
	_vr_tip.visible = false


## The next sensible step for the current job (guided mode).
func guide_text() -> String:
	var s := session
	var m := s.measured
	var lead := "R_AB" if m.has("R_AB") else ""
	match s.mode:
		"reverse":
			if lead == "":
				return "Bench 3 (Electrical): measure the resistance between each pair of leads with the milliohm meter."
			if not m.has("KV"):
				return "Bench 3: spin the motor with the drill and read the back-EMF on the scope to work out KV."
			if not s.windings_exposed() and not m.has("winding"):
				return "Bench 2 (Teardown): take the bell off to get at the windings."
			if not m.has("size"):
				return "Bench 4 (Inspect): measure the stator with the calipers, count teeth and magnets."
			if not m.has("winding"):
				return "Bench 4: trace each coil (phase and direction) to write down the winding."
			if not m.has("joints"):
				return "Bench 4: look at the lead joints to tell star (Y) from delta (Δ)."
			if s.datasheet.size() < 7:
				return "Bench 1 (Job Desk): fill in the datasheet, then hand in the report."
			return "Bench 1: hand in the report (you can reassemble the motor first)."
		"service":
			if not m.has("hand_turn"):
				return "Bench 2 (Teardown): turn the shaft by hand and listen: how does it feel?"
			if lead == "":
				return "Bench 3 (Electrical): measure all three lead pairs and the insulation."
			if not m.has("run") and s.is_assembled():
				return "Bench 6 (Test Stand): run it and look at current, speed, temperature and vibration."
			if s.diagnosis == "":
				return "Bench 1 (Job Desk): write down your diagnosis."
			var left := s.state.problems()
			if not left.is_empty():
				if s.diagnosis_ok():
					return "Fix: %s. (Repairs are at bench 4, bearings and parts at bench 2, rewinding at bench 5.)" % left[0]
				return "Repair what you diagnosed (repairs at bench 4, bearings at bench 2, rewinding at bench 5), or measure more if you are not sure."
			if not s.is_assembled():
				return "Bench 2: put the motor back together (next: %s)." % s.next_on().replace("_", " ")
			if not s.final_test.get("pass", false):
				return "Bench 6: run the final test."
			return "Bench 1: hand in the job report."
	return "Free lab: explore any bench. Start a real job at bench 1."


# --- input --------------------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_help"):
		hud.toggle_help()
	elif event.is_action_pressed("toggle_xr"):
		set_xr_mode(not xr_active)
	elif event.is_action_pressed("reset_view"):
		reset_view()
	elif event.is_action_pressed("screenshot"):
		save_screenshot("screenshot_%d" % Time.get_unix_time_from_system())
	else:
		for i in STATIONS.size():
			if event.is_action_pressed("station_%d" % (i + 1)):
				load_station(i)


func _on_xr_button(action: String, _hand: XRHand) -> void:
	match action:
		"ax_button":
			load_station((station_index + 1) % STATIONS.size())
		"by_button":
			load_station((station_index + STATIONS.size() - 1) % STATIONS.size())


func save_screenshot(file: String) -> String:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://screenshots"))
	var path := "res://screenshots/%s.png" % file
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(path))
	return path
