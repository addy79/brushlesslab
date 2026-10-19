class_name ViewportPanel3D
extends StaticBody3D
## A flat panel in 3D that shows a normal 2D interface (Controls, styled with
## UiTheme at VR size) rendered in a SubViewport. The VR laser and the desktop
## mouse work on it like a mouse: where the ray hits becomes the mouse
## position, so hover, click and drag behave as on the desktop. The panel
## grows to fit its content's height; the width is fixed. Faces +z.

const VR_SCALE := 1.6
## Pixels per metre of panel.
const PX_PER_M := 1000.0

var viewport := SubViewport.new()
## Put the interface in here.
var content := MarginContainer.new()
## Width of the panel in pixels (metres × PX_PER_M).
var width_px := 700
## Shown above everything else (head-locked captions).
var overlay := false
var render_priority := 4

var _quad := MeshInstance3D.new()
var _mat := StandardMaterial3D.new()
var _shape := CollisionShape3D.new()
var _box := BoxShape3D.new()
var _last_px := Vector2(-1, -1)
var _down := false
var _height_px := 1


func _init(p_width_px := 700) -> void:
	width_px = p_width_px


func _ready() -> void:
	viewport.transparent_bg = true
	viewport.disable_3d = true
	viewport.gui_embed_subwindows = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.size = Vector2i(width_px, 64)
	add_child(viewport)
	content.theme = UiTheme.make(VR_SCALE)
	content.custom_minimum_size.x = width_px
	content.size.x = width_px
	viewport.add_child(content)
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.albedo_texture = viewport.get_texture()
	_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_mat.render_priority = render_priority
	_mat.no_depth_test = overlay
	_mat.cull_mode = BaseMaterial3D.CULL_BACK
	var q := QuadMesh.new()
	q.material = _mat
	_quad.mesh = q
	add_child(_quad)
	_shape.shape = _box
	add_child(_shape)
	_resize(64)


## The panel's size in metres.
func size_m() -> Vector2:
	return Vector2(width_px, _height_px) / PX_PER_M


func _process(_delta: float) -> void:
	if not is_visible_in_tree():
		return
	var h := maxi(int(ceil(content.get_combined_minimum_size().y)), 8)
	if h != _height_px:
		_resize(h)


func _resize(h: int) -> void:
	_height_px = h
	viewport.size = Vector2i(width_px, h)
	content.size = Vector2(width_px, h)
	var s := size_m()
	(_quad.mesh as QuadMesh).size = s
	_box.size = Vector3(s.x, s.y, 0.01)
	# The top edge stays where the panel is placed; it grows downwards.
	_quad.position.y = -s.y * 0.5
	_shape.position.y = -s.y * 0.5


## Global position of a pixel point on the panel.
func px_to_global(px: Vector2) -> Vector3:
	var s := size_m()
	var local := Vector3(px.x / PX_PER_M - s.x * 0.5, -px.y / PX_PER_M, 0.0)
	return global_transform * local


## Global position of the centre of a Control inside the panel.
func control_global(c: Control) -> Vector3:
	if c == null or not is_instance_valid(c):
		return Vector3.INF
	return px_to_global(c.get_global_rect().get_center())


func _hit_px(event: Interact.PointerEvent) -> Vector2:
	# Where the ray meets the panel's plane (also while dragging off its edge).
	var n := global_basis.z.normalized()
	var hit := event.hit_position
	var denom := n.dot(event.ray_dir)
	if absf(denom) > 1e-5:
		var t := n.dot(global_position - event.ray_origin) / denom
		if t > 0.0:
			hit = event.ray_origin + event.ray_dir * t
	var local := to_local(hit)
	var s := size_m()
	return Vector2((local.x + s.x * 0.5) * PX_PER_M, -local.y * PX_PER_M)


func _motion(px: Vector2) -> void:
	var m := InputEventMouseMotion.new()
	m.position = px
	m.global_position = px
	m.relative = px - _last_px if _last_px.x >= 0.0 else Vector2.ZERO
	m.button_mask = MOUSE_BUTTON_MASK_LEFT if _down else 0
	_last_px = px
	viewport.push_input(m)


func _button(px: Vector2, pressed: bool) -> void:
	var b := InputEventMouseButton.new()
	b.button_index = MOUSE_BUTTON_LEFT
	b.pressed = pressed
	b.position = px
	b.global_position = px
	b.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	viewport.push_input(b)


func pointer_moved(event: Interact.PointerEvent) -> void:
	_motion(_hit_px(event))


func pointer_hover(hovering: bool) -> void:
	if not hovering and not _down:
		_motion(Vector2(-100, -100))   # leave: clears hover highlights
		_last_px = Vector2(-1, -1)


func pointer_pressed(event: Interact.PointerEvent) -> void:
	var px := _hit_px(event)
	_motion(px)
	_down = true
	_button(px, true)


func pointer_dragged(event: Interact.PointerEvent) -> void:
	_motion(_hit_px(event))


func pointer_released() -> void:
	_down = false
	_button(_last_px, false)
