extends SceneTree
## Native data, mesh/collision, map alignment and sloped-warning regression tests.
## No profile reads/writes. Headless checks do NOT certify GPU appearance or FPS.
const Terrain = preload("res://scripts/terrain.gd")
const GroundMesh = preload("res://scripts/terrain_mesh.gd")
const World = preload("res://scripts/world.gd")
const MapView = preload("res://scripts/world_map.gd")
const Layout = preload("res://scripts/world_layout.gd")
const Navigation = preload("res://scripts/navigation.gd")
const Creature = preload("res://scripts/enemy_visual.gd")
const AI = preload("res://scripts/enemy_ai.gd")
var passed: int = 0
var failed: int = 0

func _initialize() -> void:
	Engine.max_fps = 60
	call_deferred("_run")

func _run() -> void:
	create_timer(60.0).timeout.connect(_timeout)
	Game.autosave_enabled = false
	Game.automatic_ticks = false
	_check(Terrain.valid_data(), "Authored terrain resource imports with the expected sample count")
	if not Terrain.valid_data():
		quit(1)
		return
	_check(absf(Terrain.height_at(0, 8)) < 0.025, "Village spawn remains level")
	_check(absf(Terrain.height_at(-16, -36) - 2.3) < 0.025, "Northreach camp is raised to its level terrace")
	_check(absf(Terrain.height_at(0, -60) - 4.8) < 0.025, "Watchwarden courtyard is on the higher plateau")
	_check(Terrain.height_at(20, -56) > 6.0, "Ironroot ridge has real height")
	_check(Terrain.height_at(19, 9.5) < Terrain.WATER_HEIGHT - 1.0, "Pond floor is below the water surface")
	_check(not Terrain.is_walkable(Vector2(INF, 0)), "Invalid terrain coordinates cannot become walkable")
	var geometry: ArrayMesh = GroundMesh.mesh_resource()
	var arrays: Array = geometry.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	_check(vertices.size() == 27797 and indices.size() == 54912 * 3, "Real mesh has the declared vertex and triangle counts")
	var match_data: bool = true
	var valid_normals: bool = normals.size() == vertices.size()
	for index: int in range(vertices.size()):
		var vertex: Vector3 = vertices[index]
		match_data = match_data and absf(vertex.y - Terrain.height_at(vertex.x, vertex.z)) < 0.0001
		if valid_normals:
			valid_normals = normals[index].is_finite() and normals[index].y > 0.0 and absf(normals[index].length() - 1.0) < 0.0001
	_check(match_data, "Every ground vertex agrees with the movement height sampler")
	_check(valid_normals, "Terrain normals are normalized and upward-facing")
	_check(geometry.get_aabb().size.y > 8.0, "Ground mesh is not a flat plane")
	var world: Node3D = World.new()
	root.add_child(world)
	world.set_process(false)
	await physics_frame
	await physics_frame
	var body: StaticBody3D = world.get_node("TerrainCollision") as StaticBody3D
	var shape_node: CollisionShape3D = body.get_node("MatchingTerrainTriangles") as CollisionShape3D
	_check(shape_node.shape is ConcavePolygonShape3D, "Flat box collider has been replaced by terrain triangles")
	if shape_node.shape is ConcavePolygonShape3D:
		var shape: ConcavePolygonShape3D = shape_node.shape as ConcavePolygonShape3D
		_check(shape.get_faces() == geometry.get_faces(), "Collision and visible terrain use identical triangles")
	var samples: Array[Vector2] = [Vector2(0, 8), Vector2(20, -56), Vector2(-16, -36),
		Vector2(0, -60), Vector2(-23.2, -18.3), Vector2(19, 9.5), Vector2(12, 8), Vector2(26, 8)]
	for target: Dictionary in Layout.targets():
		var at: Vector3 = target["pos"]
		samples.append(Vector2(at.x, at.z))
	for at: Vector2 in samples:
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(Vector3(at.x, 30, at.y), Vector3(at.x, -5, at.y), 1)
		query.collide_with_areas = false
		var hit: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(query)
		_check(not hit.is_empty(), "Downward click ray hits terrain at " + str(at))
		if not hit.is_empty():
			var point: Vector3 = hit["position"]
			_check(absf(point.y - Terrain.height_at(at.x, at.y)) < 0.002, "Raycast height agrees with sampler at " + str(at))
	var navigation = Navigation.new()
	navigation.build()
	for at: Vector3 in [Vector3(-16, 0, -36), Vector3(0, 0, -60), Vector3(20, 0, -56)]:
		var route: PackedVector3Array = navigation.route(Layout.SPAWN, at)
		_check(not route.is_empty(), "Uphill route exists to " + str(at))
		var legal: bool = true
		for i: int in range(route.size()):
			legal = legal and navigation.clear_position(route[i]) and Terrain.is_walkable(Vector2(route[i].x, route[i].z))
			if i > 0:
				legal = legal and navigation.segment_clear(route[i - 1], route[i])
		_check(legal, "Entire uphill route has clear walkable segments")
	for at: Vector3 in [Vector3(12,0,3), Vector3(26,0,3), Vector3(12,0,16), Vector3(26,0,16),
		Vector3(12,0,8), Vector3(26,0,8), Vector3(19,0,3), Vector3(19,0,16)]:
		_check(navigation.can_fish_from(at) and Terrain.grounded(at).y > Terrain.WATER_HEIGHT, "Dry fishing bank/corner remains available: " + str(at))
	var map = MapView.new()
	root.add_child(map)
	map.size = Vector2(540, 530)
	_check(map.RELIEF_MAP.get_width() == 496 and map.RELIEF_MAP.get_height() == 800, "Relief map imports at the authored resolution")
	for at: Vector2 in samples:
		var logical: Vector3 = Vector3(at.x, 0, at.y)
		_check(map.world_point(map.point(logical)).distance_to(logical) < 0.001, "Map and world click coordinates align: " + str(at))
	var targets: Dictionary = world.get("targets")
	for definition: Dictionary in Layout.targets():
		var id: String = str(definition["id"])
		var item: Node3D = targets[id]["root"]
		if str(definition["kind"]) != "fish":
			_check(item.position.distance_to(Terrain.grounded(definition["pos"])) < 0.001, "Target presentation sits on its terrain anchor: " + id)
	# A real enemy strike on the Briarwood slope: X/Z footprint remains committed.
	var entry: Dictionary = targets["wolf_1"]
	var status: Dictionary = Game.world["wolf_1"]
	var origin: Vector3 = status["pos"]
	AI.begin_windup(Game.definitions["wolf_1"], status, origin + Vector3(1.4, 0, 0.4))
	Creature.animate(entry, status, 1.0, 0.05)
	var warning: MeshInstance3D = entry["warning"]
	var warning_arrays: Array = warning.mesh.surface_get_arrays(0)
	var warning_vertices: PackedVector3Array = warning_arrays[Mesh.ARRAY_VERTEX]
	var projected: bool = warning.visible and warning.scale == Vector3.ONE
	for vertex: Vector3 in warning_vertices:
		var at: Vector3 = warning.global_transform * vertex
		projected = projected and absf(at.y - Terrain.height_at(at.x, at.z) - 0.07) < 0.001
		projected = projected and Vector2(vertex.x, vertex.z).length() <= float(status["strike_reach"]) + 0.0001
	_check(projected, "Warning follows the slope while preserving the committed damage footprint")
	var previous_mesh: Mesh = warning.mesh
	Creature.animate(entry, status, 1.1, 0.05)
	_check(warning.mesh == previous_mesh, "Unchanged warning poses reuse the projected mesh")
	map.free()
	world.free()
	print("TERRAIN NATIVE RESULT: %d passed; %d failed. No GPU visual/performance acceptance." % [passed, failed])
	quit(1 if failed > 0 else 0)

func _check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
		print("TERRAIN PASS: " + label)
	else:
		failed += 1
		push_error("TERRAIN FAIL: " + label)

func _timeout() -> void:
	push_error("TERRAIN FAIL: native suite timed out")
	quit(1)
