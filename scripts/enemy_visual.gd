extends RefCounted
## Original low-poly creatures with explicit surface materials. This presentation layer never modifies simulation state.
const Terrain = preload("res://scripts/terrain.gd")
const Geo = preload("res://scripts/geometry.gd")
const Surfaces = preload("res://scripts/world_materials.gd")
const Combat = preload("res://scripts/combat_rules.gd")

static func build(parent: Node3D, definition: Dictionary) -> Dictionary:
	var species: String = str(definition.get("species", "mossling"))
	var legs: Array[Node3D] = []
	var height: float = 2.0
	match species:
		"wolf":
			Surfaces.apply(Geo.sphere(parent, Vector3(0, 0.85, 0), 0.70, Color("817b6e"), Vector3(0.65, 0.78, 1.45)), "fur")
			Surfaces.apply(Geo.sphere(parent, Vector3(0, 1.20, -0.75), 0.40, Color("a19b89"), Vector3(0.80, 0.93, 1.05)), "fur")
			Surfaces.apply(Geo.box(parent, Vector3(0, 1.07, -1.13), Vector3(0.33, 0.26, 0.50), Color("b0a998")), "fur")
			Geo.box(parent, Vector3(0, 1.10, -1.4), Vector3(0.28, 0.18, 0.10), Color("383b38"))
			for side: float in [-1.0, 1.0]:
				Surfaces.apply(Geo.cylinder(parent, Vector3(side * 0.22, 1.62, -0.65), 0.16, 0.0, 0.45, Color("747469"), 5), "fur")
				Geo.sphere(parent, Vector3(side * 0.25, 1.27, -1.04), 0.06, Color("eed6a0"))
				for z: float in [-0.50, 0.62]:
					var leg: Node3D = Node3D.new()
					leg.position = Vector3(side * 0.35, 0.60, z)
					parent.add_child(leg)
					Surfaces.apply(Geo.box(leg, Vector3(0, -0.25, 0), Vector3(0.20, 0.62, 0.24), Color("666b61")), "fur")
					legs.append(leg)
			var tail: MeshInstance3D = Surfaces.apply(Geo.box(parent, Vector3(0, 0.98, 1.0), Vector3(0.20, 0.20, 0.80), Color("666b61")), "fur")
			tail.rotation.x = -0.4
		"crawler":
			Surfaces.apply(Geo.sphere(parent, Vector3(0, 0.57, 0), 0.85, Color("687a73"), Vector3(1.1, 0.70, 1.0)), "stone")
			for side: float in [-1.0, 1.0]:
				for z: float in [-0.58, 0, 0.58]:
					var leg: Node3D = Node3D.new()
					leg.position = Vector3(side * 0.68, 0.35, z)
					parent.add_child(leg)
					var limb: MeshInstance3D = Surfaces.apply(Geo.box(leg, Vector3(side * 0.18, -0.05, 0), Vector3(0.58, 0.24, 0.20), Color("8d9a89")), "stone")
					limb.rotation.z = side * -0.5
					legs.append(leg)
				Geo.sphere(parent, Vector3(side * 0.30, 0.65, -0.77), 0.10, Color("c6c58a"))
			for z: float in [-0.3, 0.3]:
				Surfaces.apply(Geo.cylinder(parent, Vector3(0, 1.15, z), 0.28, 0, 0.70, Color("a1b0a5"), 5), "stone")
		"warden":
			height = 3.7
			Surfaces.apply(Geo.box(parent, Vector3(0, 1.65, 0), Vector3(1.50, 1.55, 0.95), Color("80867a")), "masonry")
			Surfaces.apply(Geo.box(parent, Vector3(0, 2.72, 0), Vector3(0.93, 0.80, 0.80), Color("a2a38f")), "stone")
			Geo.box(parent, Vector3(0, 1.70, -0.52), Vector3(0.45, 0.55, 0.08), Color("d2b866"), true)
			for side: float in [-1.0, 1.0]:
				Geo.box(parent, Vector3(side * 0.24, 2.8, -0.43), Vector3(0.20, 0.10, 0.06), Color("e4d397"), true)
				var leg: Node3D = Node3D.new()
				leg.position = Vector3(side * 0.48, 0.85, 0)
				parent.add_child(leg)
				Surfaces.apply(Geo.box(leg, Vector3(0, -0.40, 0), Vector3(0.56, 0.84, 0.68), Color("747b70")), "stone")
				legs.append(leg)
				Surfaces.apply(Geo.box(parent, Vector3(side * 1.05, 1.80, 0), Vector3(0.55, 1.48, 0.65), Color("8b907f")), "stone")
			Surfaces.apply(Geo.box(parent, Vector3(1.1, 1.0, -0.5), Vector3(0.70, 0.64, 1.2), Color("737b73")), "stone")
		_:
			Surfaces.apply(Geo.sphere(parent, Vector3(0, 0.65, 0), 0.8, Color("87a55b"), Vector3(1.0, 0.83, 1.0)), "moss")
			for x: float in [-0.23, 0.23]:
				Geo.sphere(parent, Vector3(x, 0.85, -0.62), 0.15, Color("f4edd6"))
				Geo.sphere(parent, Vector3(x, 0.85, -0.755), 0.065, Color("253f39"))
			Surfaces.apply(Geo.cylinder(parent, Vector3(0.1, 1.37, 0), 0.16, 0, 0.50, Color("607c43"), 5), "leaves")
	return {"legs": legs, "height": height, "species": species}

static func build_warning(parent: Node3D, definition: Dictionary) -> MeshInstance3D:
	# Fixed-size fan faces local -Z; the same radius/angle drive the hit validator.
	var radius: float = Combat.reach(definition)
	var half: float = Combat.half_angle(definition)
	var vertices: PackedVector3Array = PackedVector3Array()
	var border: PackedVector3Array = PackedVector3Array()
	var segments: int = 48
	for i: int in range(segments):
		var first: float = -half + 2.0 * half * float(i) / float(segments)
		var last: float = -half + 2.0 * half * float(i + 1) / float(segments)
		var a: Vector3 = Vector3(sin(first), 0, -cos(first))
		var b: Vector3 = Vector3(sin(last), 0, -cos(last))
		# Radial subdivisions follow curved ground, not just the centre and rim.
		for ring: int in range(8):
			var near_radius: float = radius * float(ring) / 8.0
			var far_radius: float = radius * float(ring + 1) / 8.0
			vertices.append_array(PackedVector3Array([a * near_radius, a * far_radius, b * far_radius,
				a * near_radius, b * far_radius, b * near_radius]))
		# Outline is inside the validated reach, not a larger, misleading halo.
		var inner: float = maxf(0.0, radius - 0.045)
		border.append_array(PackedVector3Array([a * inner, a * radius, b * radius,
			a * inner, b * radius, b * inner]))
	var warning: MeshInstance3D = MeshInstance3D.new()
	warning.name = "CommittedStrikeArea"
	warning.mesh = _triangle_mesh(vertices)
	warning.set_meta("flat_vertices", vertices)
	warning.material_override = _warning_material(Color(1.0, 0.56, 0.16, 0.30))
	warning.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	warning.visible = false
	parent.add_child(warning)
	var outline: MeshInstance3D = MeshInstance3D.new()
	outline.name = "StrikeBoundary"
	outline.mesh = _triangle_mesh(border)
	outline.set_meta("flat_vertices", border)
	outline.material_override = _warning_material(Color(1.0, 0.70, 0.30, 0.85))
	outline.position.y = 0.003
	outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	warning.add_child(outline)
	return warning

static func _triangle_mesh(vertices: PackedVector3Array) -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var result: ArrayMesh = ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return result

static func _warning_material(tint: Color) -> StandardMaterial3D:
	# Each enemy gets its own material; pulsing one cannot recolor another enemy.
	var result: StandardMaterial3D = StandardMaterial3D.new()
	result.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	result.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	result.cull_mode = BaseMaterial3D.CULL_DISABLED
	result.albedo_color = tint
	return result

static func animate(entry: Dictionary, status: Dictionary, time: float, delta: float) -> void:
	var visual: Node3D = entry["visual"]
	var facing: Vector3 = status["facing"]
	if facing.length_squared() > 0.01:
		var turn: float = atan2(-facing.x, -facing.z)
		visual.rotation.y = turn if str(status["state"]) in ["windup", "recover"] else lerp_angle(visual.rotation.y, turn, minf(1.0, delta * 12.0))
	var moving: bool = bool(status["moving"])
	var info: Dictionary = entry["creature"]
	var legs: Array[Node3D] = info["legs"]
	for i: int in range(legs.size()):
		legs[i].rotation.x = sin(time * 10.0 + float(i % 2) * PI) * 0.48 if moving else 0.0
	var state: String = str(status["state"])
	visual.position.y = absf(sin(time * 9.0)) * 0.10 if moving else 0.0
	visual.rotation.x = -0.16 if state == "windup" else (0.18 if float(status["swing"]) > 0.0 else 0.0)
	# A hit flinch is visual only; it never resets the enemy's attack cooldown.
	visual.rotation.z = sin(float(status["hit_flash"]) * 50.0) * 0.12 if float(status["hit_flash"]) > 0.0 else 0.0
	visual.scale = Vector3.ONE
	if str(info["species"]) == "mossling":
		visual.scale.y = 0.94 + sin(time * (8.0 if moving else 3.0)) * 0.07
	var warning: MeshInstance3D = entry["warning"]
	warning.visible = bool(status["alive"]) and (state == "windup" or (state == "recover" and float(status["swing"]) > 0.0))
	# Never follow the player's new position or pulse the footprint size.
	var strike_facing: Vector3 = status["strike_facing"]
	var origin: Vector3 = status["strike_origin"]
	var here: Vector3 = status["pos"]
	warning.position = Vector3(origin.x - here.x, 0.0, origin.z - here.z)
	warning.rotation.y = atan2(-strike_facing.x, -strike_facing.z)
	warning.scale = Vector3.ONE
	if warning.visible:
		_conform_warning(warning, origin, here)
	var tint: StandardMaterial3D = warning.material_override as StandardMaterial3D
	if tint != null:
		var progress: float = clampf(1.0 - float(status["state_time"]) / maxf(float(status["strike_duration"]), 0.01), 0.0, 1.0)
		tint.albedo_color = Color(1.0, 0.56 - 0.22 * progress, 0.16, 0.24 + 0.20 * progress) if state == "windup" else Color(1.0, 0.30, 0.12, 0.50)

static func _conform_warning(warning: MeshInstance3D, origin: Vector3, here: Vector3) -> void:
	var anchor_y: float = Terrain.height_at(here.x, here.z)
	var signature: Vector3 = Vector3(origin.x, warning.rotation.y, origin.z)
	if warning.get_meta("terrain_signature", Vector3.INF) == signature and is_equal_approx(float(warning.get_meta("terrain_anchor_y", INF)), anchor_y):
		return
	warning.set_meta("terrain_signature", signature)
	warning.set_meta("terrain_anchor_y", anchor_y)
	var pieces: Array[MeshInstance3D] = [warning, warning.get_node("StrikeBoundary") as MeshInstance3D]
	for piece: MeshInstance3D in pieces:
		var flat: PackedVector3Array = piece.get_meta("flat_vertices")
		var vertices: PackedVector3Array = flat.duplicate()
		for index: int in range(vertices.size()):
			var vertex: Vector3 = vertices[index]
			var horizontal: Vector3 = origin + warning.basis * vertex
			vertex.y = Terrain.height_at(horizontal.x, horizontal.z) - anchor_y + 0.07
			vertices[index] = vertex
		piece.mesh = _triangle_mesh(vertices)
