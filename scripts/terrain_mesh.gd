extends RefCounted
## Ground is a real indexed triangle mesh with a matching static collision mesh.
const Terrain = preload("res://scripts/terrain.gd")
const Surfaces = preload("res://scripts/world_materials.gd")
const Geo = preload("res://scripts/geometry.gd")
const LAND_SHADER = preload("res://shaders/terrain.gdshader")
const TINT_MAP = preload("res://assets/textures/terrain/land_tint.png")
const BLEND_MAP = preload("res://assets/textures/terrain/land_blend.png")
static var _mesh: ArrayMesh

static func mesh_resource() -> ArrayMesh:
	if _mesh != null:
		return _mesh
	var columns: int = Terrain.DATA.columns
	var rows: int = Terrain.DATA.rows
	var count: int = columns * rows
	var vertices: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var tangents: PackedFloat32Array = PackedFloat32Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var uv2s: PackedVector2Array = PackedVector2Array()
	var indices: PackedInt32Array = PackedInt32Array()
	vertices.resize(count)
	normals.resize(count)
	tangents.resize(count * 4)
	uvs.resize(count)
	uv2s.resize(count)
	for z: int in range(rows):
		for x: int in range(columns):
			var index: int = z * columns + x
			var wx: float = Terrain.DATA.origin.x + float(x) * Terrain.DATA.step
			var wz: float = Terrain.DATA.origin.y + float(z) * Terrain.DATA.step
			vertices[index] = Vector3(wx, Terrain.vertex_height(x, z), wz)
			var normal: Vector3 = Terrain.normal_at(wx, wz)
			normals[index] = normal
			var tangent: Vector3 = Vector3(normal.y, -normal.x, 0).normalized()
			tangents[index * 4] = tangent.x
			tangents[index * 4 + 1] = tangent.y
			tangents[index * 4 + 2] = tangent.z
			tangents[index * 4 + 3] = -1.0
			uvs[index] = Vector2(wx, wz)
			uv2s[index] = Vector2(float(x) / float(columns - 1), float(z) / float(rows - 1))
	for z: int in range(rows - 1):
		for x: int in range(columns - 1):
			var a: int = z * columns + x
			var b: int = a + 1
			var d: int = a + columns
			var c: int = d + 1
			# Clockwise winding viewed from above: two triangles share diagonal A-C.
			indices.append_array(PackedInt32Array([a, b, c, a, c, d]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TANGENT] = tangents
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_INDEX] = indices
	_mesh = ArrayMesh.new()
	_mesh.resource_name = "Hearthmere authored terrain"
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return _mesh

static func build(parent: Node3D) -> MeshInstance3D:
	if not Terrain.valid_data():
		push_error("Terrain data is incomplete. Re-extract the complete 0.3.0 project.")
		return null
	var surface: MeshInstance3D = MeshInstance3D.new()
	surface.name = "TerrainSurface"
	surface.mesh = mesh_resource()
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = LAND_SHADER
	material.set_shader_parameter("land_tint", TINT_MAP)
	material.set_shader_parameter("land_blend", BLEND_MAP)
	material.set_shader_parameter("use_detail", Surfaces.enabled())
	material.set_shader_parameter("use_normal_maps", Surfaces.normals_enabled() and Surfaces.enabled())
	for key: String in ["grass", "path", "stone", "cobble"]:
		material.set_shader_parameter(key + "_map", Surfaces.ALBEDO[key])
		material.set_shader_parameter(key + "_normal", Surfaces.NORMAL[key])
	surface.material_override = material
	parent.add_child(surface)
	var body: StaticBody3D = StaticBody3D.new()
	body.name = "TerrainCollision"
	body.collision_layer = 1
	body.collision_mask = 0
	var collider: CollisionShape3D = CollisionShape3D.new()
	collider.name = "MatchingTerrainTriangles"
	collider.shape = surface.mesh.create_trimesh_shape()
	body.add_child(collider)
	parent.add_child(body)
	_build_skirt(parent)
	return surface

static func _build_skirt(parent: Node3D) -> void:
	# Hide the exposed heightfield edges with solid-looking earth down to the base.
	var boundary: Array[Vector2i] = []
	var columns: int = Terrain.DATA.columns
	var rows: int = Terrain.DATA.rows
	for x: int in range(columns):
		boundary.append(Vector2i(x, 0))
	for z: int in range(1, rows):
		boundary.append(Vector2i(columns - 1, z))
	for x: int in range(columns - 2, -1, -1):
		boundary.append(Vector2i(x, rows - 1))
	for z: int in range(rows - 2, -1, -1):
		boundary.append(Vector2i(0, z))
	var tool: SurfaceTool = SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index: int in range(boundary.size()):
		var a: Vector2i = boundary[index]
		var b: Vector2i = boundary[(index + 1) % boundary.size()]
		var ap: Vector3 = Vector3(Terrain.DATA.origin.x + a.x * Terrain.DATA.step, Terrain.vertex_height(a.x, a.y), Terrain.DATA.origin.y + a.y * Terrain.DATA.step)
		var bp: Vector3 = Vector3(Terrain.DATA.origin.x + b.x * Terrain.DATA.step, Terrain.vertex_height(b.x, b.y), Terrain.DATA.origin.y + b.y * Terrain.DATA.step)
		var bottom_a: Vector3 = Vector3(ap.x, -4.0, ap.z)
		var bottom_b: Vector3 = Vector3(bp.x, -4.0, bp.z)
		for vertex: Vector3 in [ap, bottom_a, bp, bp, bottom_a, bottom_b]:
			tool.add_vertex(vertex)
	tool.generate_normals()
	var skirt: MeshInstance3D = Geo.mesh(parent, tool.commit(), Vector3.ZERO, Color("80755a"))
	skirt.name = "TerrainEarthEdges"
	Surfaces.apply(skirt, "earth", true)
