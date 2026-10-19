class_name Clickable
extends StaticBody3D
## A part of the scene that reacts to the pointer (VR laser trigger or left click):
## it glows while pointed at and emits `clicked`. Collision is a box fitted to the
## meshes under it (fit_box) or added by the caller.

signal clicked(node: Clickable)

var id := ""
var enabled := true:
	set(value):
		enabled = value
		if not enabled:
			pointer_hover(false)
## Text shown next to the pointer while hovering (stations read it).
var tooltip := ""

static var _glow: StandardMaterial3D
var _hovering := false


func pointer_pressed(_event: Interact.PointerEvent) -> void:
	if enabled:
		clicked.emit(self)


func pointer_hover(hovering: bool) -> void:
	_hovering = hovering and enabled
	if _glow == null:
		_glow = StandardMaterial3D.new()
		_glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_glow.albedo_color = Color(0.3, 0.85, 1.0, 0.22)
		_glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_glow.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	for mi in _meshes(self):
		mi.material_overlay = _glow if _hovering else null


func is_hovering() -> bool:
	return _hovering


## Mesh instances that belong to this clickable (not to nested clickables).
func _meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for c in node.get_children():
		if c is Clickable:
			continue
		if c is MeshInstance3D:
			out.append(c)
		out.append_array(_meshes(c))
	return out


## Adds a box collision shape around this clickable's own meshes (in its local space).
func fit_box(pad := 0.0) -> void:
	var box := AABB()
	var first := true
	for mi in _meshes(self):
		if mi.mesh == null:
			continue
		var xf := global_transform.affine_inverse() * mi.global_transform if is_inside_tree() else _rel(mi)
		var b := xf * mi.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	if first:
		return
	var shape := CollisionShape3D.new()
	var s := BoxShape3D.new()
	s.size = box.size + Vector3.ONE * pad * 2.0
	shape.shape = s
	shape.position = box.get_center()
	add_child(shape)


## Transform of a descendant relative to this node, without needing the scene tree.
func _rel(n: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node = n
	while cur and cur != self:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf
