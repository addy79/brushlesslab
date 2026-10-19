class_name MeshUtil
extends RefCounted
## Fonts, labels and the workshop's materials (steel, copper, anodised aluminium...).

static var _font: SystemFont
static var _materials := {}


## The app's font (system sans with symbol and emoji fallbacks: Ω µ ° ≈ →).
static func math_font() -> Font:
	if _font == null:
		_font = SystemFont.new()
		_font.font_names = PackedStringArray(["Noto Sans", "DejaVu Sans", "Liberation Sans", "sans-serif"])
		var emoji := SystemFont.new()
		emoji.font_names = PackedStringArray(["Noto Color Emoji", "Apple Color Emoji", "Segoe UI Emoji"])
		_font.fallbacks = [emoji]
	return _font


## Label readable on top of geometry (billboard) or fixed on a surface.
static func label(text: String, font_size: int = 32, billboard := true) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = math_font()
	l.font_size = font_size
	l.pixel_size = 0.0012
	l.outline_size = 10
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED if billboard else BaseMaterial3D.BILLBOARD_DISABLED
	l.no_depth_test = billboard
	l.render_priority = 10
	return l


static func flat_material(color: Color, unshaded := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	if color.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


## Shared physically based materials by name.
static func mat(name: String) -> StandardMaterial3D:
	if _materials.has(name):
		return _materials[name]
	var m := StandardMaterial3D.new()
	match name:
		"steel":
			_pbr(m, Color(0.72, 0.74, 0.77), 0.9, 0.28)
		"dark_steel":
			_pbr(m, Color(0.3, 0.31, 0.33), 0.8, 0.4)
		"lamination":
			_pbr(m, Color(0.36, 0.38, 0.4), 0.7, 0.45)
		"copper":
			_pbr(m, Color(0.85, 0.45, 0.22), 0.95, 0.3)
		"copper_burnt":
			_pbr(m, Color(0.28, 0.13, 0.06), 0.5, 0.7)
		"anodised_red":
			_pbr(m, Color(0.7, 0.08, 0.1), 0.6, 0.35)
		"anodised_black":
			_pbr(m, Color(0.09, 0.09, 0.1), 0.5, 0.45)
		"aluminium":
			_pbr(m, Color(0.8, 0.81, 0.83), 0.85, 0.35)
		"magnet":
			_pbr(m, Color(0.62, 0.63, 0.65), 0.9, 0.22)
		"magnet_n":
			_pbr(m, Color(0.85, 0.25, 0.22), 0.3, 0.4)
		"magnet_s":
			_pbr(m, Color(0.2, 0.42, 0.85), 0.3, 0.4)
		"film_light":
			_pbr(m, Color(0.55, 0.85, 0.45), 0.0, 0.6)
		"film_dark":
			_pbr(m, Color(0.12, 0.3, 0.12), 0.0, 0.6)
		"brass":
			_pbr(m, Color(0.86, 0.68, 0.3), 0.95, 0.3)
		"gold":
			_pbr(m, Color(0.95, 0.75, 0.35), 1.0, 0.2)
		"pcb":
			_pbr(m, Color(0.08, 0.38, 0.18), 0.0, 0.5)
		"plastic_black":
			_pbr(m, Color(0.06, 0.06, 0.07), 0.0, 0.6)
		"insulator":
			_pbr(m, Color(0.92, 0.85, 0.55), 0.0, 0.6)
		"rubber":
			_pbr(m, Color(0.05, 0.05, 0.05), 0.0, 0.9)
		"wood":
			_pbr(m, Color(0.55, 0.38, 0.22), 0.0, 0.8)
		"bench":
			_pbr(m, Color(0.3, 0.32, 0.35), 0.2, 0.7)
		"mat_green":
			_pbr(m, Color(0.12, 0.35, 0.3), 0.0, 0.9)
		"glow":
			m.albedo_color = Color(0.4, 1.0, 0.6)
			m.emission_enabled = true
			m.emission = Color(0.3, 1.0, 0.5)
			m.emission_energy_multiplier = 2.0
		_:
			_pbr(m, Color(0.6, 0.6, 0.6), 0.0, 0.6)
	_materials[name] = m
	return m


static func _pbr(m: StandardMaterial3D, c: Color, metal: float, rough: float) -> void:
	m.albedo_color = c
	m.metallic = metal
	m.roughness = rough
	m.metallic_specular = 0.5


static func colored(c: Color, metal := 0.0, rough := 0.6) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	_pbr(m, c, metal, rough)
	return m


static func mesh_instance(mesh: Mesh, material: Material = null, pos := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	if material:
		mi.material_override = material
	mi.position = pos
	return mi


static func box(size: Vector3, material: Material, pos := Vector3.ZERO) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	return mesh_instance(b, material, pos)


static func cylinder(radius: float, height: float, material: Material, pos := Vector3.ZERO, segments := 32) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = height
	c.radial_segments = segments
	c.rings = 1
	return mesh_instance(c, material, pos)
