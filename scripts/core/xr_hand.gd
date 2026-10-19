class_name XRHand
extends XRController3D
## One VR controller: a laser pointer (trigger = press / grab at a distance,
## the grabbed object follows the controller's pose) and a grip that grabs a
## handle within reach, or the whole plot when nothing is near (see main.gd).

signal grip_changed(hand: XRHand, pressed: bool)
## Hand tracking: a pinch that didn't press anything (main.gd: continue).
signal pinch_empty(hand: XRHand)

const GRAB_REACH := 0.12

var pointer := PointerState.new()
var enabled := false:
	set(value):
		enabled = value
		if not enabled:
			pointer.release()
var grip_pressed := false
## Handle grabbed with the grip (not the laser).
var hand_held: Grabbable

## True while this hand is tracked without a controller (OpenXR hand
## interaction profile): pinch = trigger, the laser comes from the pinch point.
var hand_mode := false
## Buttons shown on the wrist in hand mode (main.gd adds them).
var wrist := Node3D.new()

var _body := MeshInstance3D.new()
var _joints: Array[MeshInstance3D] = []
var _laser := MeshInstance3D.new()
var _dot := MeshInstance3D.new()
var _laser_material := StandardMaterial3D.new()


func _ready() -> void:
	pointer.is_xr = true
	var body := _body
	var body_mesh := BoxMesh.new()
	body_mesh.size = Vector3(0.035, 0.03, 0.11)
	body_mesh.material = MeshUtil.flat_material(Color(0.2, 0.22, 0.28))
	body.mesh = body_mesh
	body.position = Vector3(0.0, 0.0, 0.03)
	add_child(body)
	var laser_mesh := BoxMesh.new()
	laser_mesh.size = Vector3(0.003, 0.003, 1.0)
	_laser_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_laser_material.albedo_color = Color(0.4, 0.8, 1.0, 0.7)
	_laser_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	laser_mesh.material = _laser_material
	_laser.mesh = laser_mesh
	add_child(_laser)
	var dot_mesh := SphereMesh.new()
	dot_mesh.radius = 0.008
	dot_mesh.height = 0.016
	dot_mesh.material = MeshUtil.flat_material(Color(0.6, 0.9, 1.0), true)
	_dot.mesh = dot_mesh
	_dot.top_level = true
	add_child(_dot)
	var jm := SphereMesh.new()
	jm.radius = 0.006
	jm.height = 0.012
	jm.material = MeshUtil.flat_material(Color(0.85, 0.9, 1.0, 0.8), true)
	for j in XRHandTracker.HAND_JOINT_MAX:
		var d := MeshInstance3D.new()
		d.mesh = jm
		d.top_level = true
		d.visible = false
		add_child(d)
		_joints.append(d)
	wrist.visible = false
	add_child(wrist)
	button_pressed.connect(_on_button_pressed)
	button_released.connect(_on_button_released)


func _process(_delta: float) -> void:
	var pt := XRServer.get_tracker(tracker) as XRPositionalTracker
	hand_mode = enabled and pt != null and String(pt.profile).contains("hand_interaction")
	_body.visible = not hand_mode
	wrist.visible = hand_mode
	_update_joints()
	var active := enabled and get_is_active()
	_laser.visible = active and hand_held == null
	_dot.visible = _laser.visible and pointer.has_hit
	if not active:
		return
	if hand_held:
		var event := _pose_event()
		hand_held.pointer_dragged(event)
		return
	pointer.update(get_world_3d(), global_transform, -global_basis.z.normalized())
	var length := pointer.hit_distance() if pointer.has_hit else 3.0
	_laser.scale = Vector3(1.0, 1.0, length)
	_laser.position = Vector3(0.0, 0.0, -length * 0.5)
	_dot.global_position = pointer.event.hit_position
	_laser_material.albedo_color = Color(0.4, 1.0, 0.6, 0.8) if pointer.is_hovering() else Color(0.4, 0.8, 1.0, 0.6)


## Small dots on the tracked hand's joints (so you can see your hands).
func _update_joints() -> void:
	var ht := XRServer.get_tracker("/user/hand_tracker/" + ("left" if tracker == &"left_hand" else "right")) as XRHandTracker
	var show := hand_mode and ht != null and ht.has_tracking_data
	var origin := get_parent() as Node3D
	for j in _joints.size():
		_joints[j].visible = show
		if show and origin:
			_joints[j].global_position = origin.global_transform * ht.get_hand_joint_transform(j).origin


func _pose_event() -> Interact.PointerEvent:
	var event := Interact.PointerEvent.new()
	event.is_xr = true
	event.pose = global_transform
	event.ray_origin = global_position
	event.ray_dir = -global_basis.z
	event.hit_position = global_position
	return event


## The closest grabbable handle within reach of the controller, or null.
func nearest_grabbable() -> Grabbable:
	var space := get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = GRAB_REACH
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, global_position)
	var best: Grabbable
	var best_d := INF
	for hit in space.intersect_shape(query, 16):
		var g := hit.collider as Grabbable
		if g and g.is_visible_in_tree():
			var d := g.global_position.distance_to(global_position)
			if d < best_d:
				best = g
				best_d = d
	return best


func _on_button_pressed(action: String) -> void:
	if not enabled:
		return
	if action == "trigger_click":
		var hit := pointer.is_hovering()
		pointer.press()
		if hand_mode and not hit:
			pinch_empty.emit(self)
	elif action == "grip_click":
		grip_pressed = true
		var g := nearest_grabbable()
		if g:
			hand_held = g
			g.pointer_pressed(_pose_event())
		else:
			grip_changed.emit(self, true)


func _on_button_released(action: String) -> void:
	if action == "trigger_click":
		pointer.release()
	elif action == "grip_click":
		grip_pressed = false
		if hand_held:
			hand_held.pointer_released()
			hand_held = null
		else:
			grip_changed.emit(self, false)
