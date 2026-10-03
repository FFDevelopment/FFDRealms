extends RefCounted
## Original procedural placeholder art. No downloaded models or font files.
static var materials: Dictionary = {}

static func material(tint: Color, glow: bool = false) -> StandardMaterial3D:
	var key: String = tint.to_html() + str(glow)
	if materials.has(key):
		return materials[key]
	var result: StandardMaterial3D = StandardMaterial3D.new()
	result.albedo_color = tint
	result.roughness = 0.87
	result.metallic_specular = 0.20
	if tint.a < 1.0:
		result.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if glow:
		result.emission_enabled = true
		result.emission = tint
		result.emission_energy_multiplier = 0.85
	materials[key] = result
	return result

static func mesh(parent: Node3D, shape: Mesh, at: Vector3, tint: Color, glow: bool = false) -> MeshInstance3D:
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.mesh = shape
	instance.material_override = material(tint, glow)
	instance.position = at
	parent.add_child(instance)
	return instance

static func box(parent: Node3D, at: Vector3, size: Vector3, tint: Color, glow: bool = false) -> MeshInstance3D:
	var shape: BoxMesh = BoxMesh.new()
	shape.size = size
	return mesh(parent, shape, at, tint, glow)

static func cylinder(parent: Node3D, at: Vector3, bottom: float, top: float, height: float, tint: Color, segments: int = 10) -> MeshInstance3D:
	var shape: CylinderMesh = CylinderMesh.new()
	shape.bottom_radius = bottom
	shape.top_radius = top
	shape.height = height
	shape.radial_segments = segments
	return mesh(parent, shape, at, tint)

static func sphere(parent: Node3D, at: Vector3, radius: float, tint: Color, scale_to: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var shape: SphereMesh = SphereMesh.new()
	shape.radius = radius
	shape.height = radius * 2.0
	shape.radial_segments = 10
	shape.rings = 5
	var instance: MeshInstance3D = mesh(parent, shape, at, tint)
	instance.scale = scale_to
	return instance

static func ring(parent: Node3D, at: Vector3, radius: float, tint: Color) -> MeshInstance3D:
	var shape: TorusMesh = TorusMesh.new()
	shape.inner_radius = radius - 0.045
	shape.outer_radius = radius + 0.045
	shape.rings = 24
	shape.ring_segments = 6
	return mesh(parent, shape, at, tint)

static func label(parent: Node3D, text: String, at: Vector3, tint: Color = Color("f4ead5"), font_size: int = 32) -> Label3D:
	var result: Label3D = Label3D.new()
	result.text = text
	result.position = at
	result.font_size = font_size
	result.pixel_size = 0.012
	result.modulate = tint
	result.outline_modulate = Color("1c2926")
	result.outline_size = 8
	result.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	parent.add_child(result)
	return result

static func pick_area(parent: Node3D, id: String, size: Vector3, at: Vector3) -> Area3D:
	var area: Area3D = Area3D.new()
	area.collision_layer = 2
	area.collision_mask = 0
	area.set_meta("target_id", id)
	var collider: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	collider.position = at
	area.add_child(collider)
	parent.add_child(area)
	return area
