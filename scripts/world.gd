extends Node3D
const Terrain = preload("res://scripts/terrain.gd")
const GroundMesh = preload("res://scripts/terrain_mesh.gd")
const Geo = preload("res://scripts/geometry.gd")
const Surfaces = preload("res://scripts/world_materials.gd")
const POND_SHADER = preload("res://shaders/pond_water.gdshader")
const Layout = preload("res://scripts/world_layout.gd")
const Catalog = preload("res://scripts/catalog.gd")
const Actor = preload("res://scripts/actor.gd")
const Creature = preload("res://scripts/enemy_visual.gd")
var targets: Dictionary = {}
var flames: Array[Node3D] = []
var elapsed: float = 0.0
var hovered_id: String = ""

func _ready() -> void:
	_build_environment()
	_build_land()
	for building: Dictionary in Layout.BUILDINGS:
		_build_house(building)
	for definition: Dictionary in Layout.targets():
		_build_target(definition)
	_build_details()
	_build_frontier()

func _build_environment() -> void:
	var environment: WorldEnvironment = WorldEnvironment.new()
	environment.name = "DaylightEnvironment"
	var settings: Environment = Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("819790")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	# Softer daylight: keep a readable ambient floor without washing out shadows.
	settings.ambient_light_color = Color("b8c7c4")
	settings.ambient_light_energy = 0.32
	settings.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	settings.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	settings.tonemap_exposure = 0.95
	settings.fog_enabled = true
	settings.fog_light_color = Color("819790")
	settings.fog_light_energy = 0.55
	settings.fog_density = 0.0015
	environment.environment = settings
	add_child(environment)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.name = "Daylight"
	sun.rotation_degrees = Vector3(-52, -28, 0)
	sun.light_color = Color("fff2d9")
	sun.light_energy = 0.90
	sun.light_specular = 0.25
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 80.0
	add_child(sun)

func _build_land() -> void:
	GroundMesh.build(self)
	var water_plane: PlaneMesh = PlaneMesh.new()
	water_plane.size = Layout.POND.size
	water_plane.subdivide_width = 16
	water_plane.subdivide_depth = 16
	var water: MeshInstance3D = Geo.mesh(self, water_plane, Vector3(19, Terrain.WATER_HEIGHT, 9.5), Color("568d9b"))
	var shader: Shader = Shader.new()
	# Shader albedo is linear; subdued values avoid pale water and white glare.
	shader.code = "shader_type spatial; render_mode cull_disabled; void vertex(){ VERTEX.y += sin(VERTEX.x * 2.0 + TIME) * 0.025; } void fragment(){ ALBEDO = vec3(0.11,0.24,0.27) + sin(UV.x*55.0+TIME)*0.008; ROUGHNESS = 0.75; SPECULAR = 0.12; }"
	var water_material: ShaderMaterial = ShaderMaterial.new()
	water_material.shader = shader
	water.material_override = water_material
	# Preserve the legacy water when textures are disabled for troubleshooting.
	if Surfaces.enabled():
		var textured_water: ShaderMaterial = ShaderMaterial.new()
		textured_water.shader = POND_SHADER
		textured_water.set_shader_parameter("ripple_map", Surfaces.ALBEDO["water"])
		textured_water.set_shader_parameter("ripple_normal", Surfaces.NORMAL["water"])
		textured_water.set_shader_parameter("use_normal_map", Surfaces.normals_enabled())
		textured_water.set_shader_parameter("pond_size", Layout.POND.size)
		water.material_override = textured_water
		water.set_meta("world_surface", "water")
	Surfaces.apply(Geo.box(self, Terrain.grounded(Vector3(12.4, 0.09, 8)), Vector3(2.2, 0.18, 2.8), Color("947b58")), "planks")
	for z: float in [6.8, 7.4, 8.0, 8.6, 9.2]:
		Surfaces.apply(Geo.box(self, Terrain.grounded(Vector3(12.4, 0.20, z)), Vector3(2.2, 0.025, 0.035), Color("564d3c")), "timber")
	for i: int in range(6):
		Geo.ring(self, Vector3(14.4 + float(i % 3) * 3.4, Terrain.WATER_HEIGHT + 0.06, 6.3 + float(i / 3) * 5.5), 0.35, Color("8eb9bd"))

func _build_house(definition: Dictionary) -> void:
	var root: Node3D = Node3D.new()
	var center: Vector2 = definition["center"]
	var size: Vector2 = definition["size"]
	root.position = Terrain.grounded(Vector3(center.x, 0, center.y))
	add_child(root)
	Surfaces.apply(Geo.box(root, Vector3(0, 0.18, 0), Vector3(size.x + 0.25, 0.36, size.y + 0.25), Color("828475")), "masonry")
	Surfaces.apply(Geo.box(root, Vector3(0, 1.8, 0), Vector3(size.x, 3.2, size.y), Color("d1c5a4")), "plaster")
	for x: float in [-size.x * 0.48, size.x * 0.48]:
		for z: float in [-size.y * 0.48, size.y * 0.48]:
			Surfaces.apply(Geo.box(root, Vector3(x, 1.8, z), Vector3(0.22, 3.3, 0.22), Color("6d5c47")), "timber")
	Surfaces.apply(Geo.box(root, Vector3(0, 2.85, size.y * 0.5 + 0.025), Vector3(size.x, 0.16, 0.10), Color("6d5c47")), "timber")
	Surfaces.apply(Geo.box(root, Vector3(0, 1.18, size.y * 0.5 + 0.03), Vector3(1.2, 2.05, 0.11), Color("765b42")), "planks")
	Surfaces.apply(Geo.box(root, Vector3(0.36, 1.15, size.y * 0.5 + 0.12), Vector3(0.08, 0.08, 0.08), Color("dcc28a")), "metal")
	for x: float in [-size.x * 0.30, size.x * 0.30]:
		Surfaces.apply(Geo.box(root, Vector3(x, 1.95, size.y * 0.5 + 0.05), Vector3(1.05, 1.05, 0.1), Color("685c47")), "timber")
		Geo.box(root, Vector3(x, 1.95, size.y * 0.5 + 0.115), Vector3(0.82, 0.80, 0.035), Color("9caf9e"))
		Surfaces.apply(Geo.box(root, Vector3(x, 1.95, size.y * 0.5 + 0.15), Vector3(0.07, 0.86, 0.03), Color("685c47")), "timber")
	var half_roof: float = size.x * 0.5 + 0.45
	for side: float in [-1.0, 1.0]:
		var roof: MeshInstance3D = Surfaces.apply(Geo.box(root, Vector3(side * size.x * 0.25, 4.05, 0), Vector3(half_roof, 0.22, size.y + 0.8), Color(str(definition["roof"]))), "shingles")
		roof.rotation.z = -side * 0.48
	Surfaces.apply(Geo.box(root, Vector3(0, 4.81, 0), Vector3(0.18, 0.18, size.y + 0.9), Color("5b5648")), "timber")
	Surfaces.apply(Geo.box(root, Vector3(size.x * 0.28, 4.35, -size.y * 0.25), Vector3(0.7, 2.4, 0.7), Color("878472")), "masonry")

func _build_target(definition: Dictionary) -> void:
	var root: Node3D = Node3D.new()
	root.position = Terrain.grounded(definition["pos"])
	if str(definition["kind"]) == "fish":
		root.position.y = Terrain.WATER_HEIGHT - 0.06
	add_child(root)
	var id: String = str(definition["id"])
	var kind: String = str(definition["kind"])
	var visual: Node3D = Node3D.new()
	root.add_child(visual)
	var crown: Node3D = Node3D.new()
	visual.add_child(crown)
	var size: Vector3 = Vector3(1.8, 2.0, 1.8)
	var height: float = 2.45
	var creature: Dictionary = {}
	match kind:
		"tree", "oak":
			Surfaces.apply(Geo.cylinder(visual, Vector3(0, 0.65, 0), 0.37, 0.24, 1.30, Color("7e5e3f"), 8), "bark")
			if kind == "tree":
				for i: int in range(3):
					Surfaces.apply(Geo.cylinder(crown, Vector3(0, 1.75 + i * 0.85, 0), 1.50 - i * 0.29, 0.05, 1.85, Color("365f49") if i % 2 == 0 else Color("49765a"), 9), "leaves")
			else:
				Surfaces.apply(Geo.sphere(crown, Vector3(0, 2.7, 0), 1.8, Color("6c8750")), "leaves")
				Surfaces.apply(Geo.sphere(crown, Vector3(-0.9, 2.35, 0.4), 1.1, Color("809958")), "leaves")
				Surfaces.apply(Geo.sphere(crown, Vector3(0.9, 2.5, -0.3), 1.3, Color("52724b")), "leaves")
			size = Vector3(2.5, 4.5, 2.5)
			height = 4.9
		"rock":
			Surfaces.apply(Geo.sphere(visual, Vector3(0, 0.7, 0), 1.15, Color("777e77"), Vector3(1.1, 0.8, 0.9)), "stone")
			var tint: Color = Color(str(Catalog.ITEMS[str(definition["item"])]["color"]))
			for offset: Vector3 in [Vector3(-0.5, 1.14, -0.2), Vector3(0.35, 1.25, 0.05), Vector3(0.7, 0.7, 0.45)]:
				var ore: MeshInstance3D = Surfaces.apply(Geo.box(crown, offset, Vector3(0.35, 0.28, 0.32), tint), "ore")
				ore.rotation = Vector3(0.3, 0.6, 0.4)
			size = Vector3(2.6, 1.8, 2.4)
			height = 2.3
		"guide", "ranger":
			var npc = Actor.new()
			visual.add_child(npc)
			npc.build_actor("", Color("708d77") if kind == "ranger" else Color("af8854"), false)
			npc.rotation.y = PI
			Geo.label(visual, "!", Vector3(0, 3.0, 0), Color("ecd58c"), 60)
		"bank":
			Surfaces.apply(Geo.box(visual, Vector3(0, 0.52, 0), Vector3(1.6, 0.95, 0.95), Color("865e3c")), "planks")
			Surfaces.apply(Geo.box(visual, Vector3(0, 1.03, 0), Vector3(1.7, 0.18, 1.05), Color("a98652")), "planks")
			for x: float in [-0.60, 0.60]:
				Surfaces.apply(Geo.box(visual, Vector3(x, 0.59, -0.49), Vector3(0.12, 0.94, 0.06), Color("c7b375")), "metal")
			Surfaces.apply(Geo.box(visual, Vector3(0, 0.75, -0.51), Vector3(0.24, 0.29, 0.08), Color("d0bc7e")), "metal")
			height = 1.65
		"campfire":
			for angle: float in [0.0, 1.57]:
				var log: MeshInstance3D = Surfaces.apply(Geo.box(visual, Vector3(0, 0.2, 0), Vector3(1.55, 0.26, 0.27), Color("70553c")), "bark")
				log.rotation.y = angle
			for i: int in range(8):
				var angle: float = float(i) * TAU / 8.0
				Surfaces.apply(Geo.sphere(visual, Vector3(cos(angle) * 0.86, 0.12, sin(angle) * 0.86), 0.18, Color("aaa18b")), "stone")
			var fire: Node3D = Node3D.new()
			visual.add_child(fire)
			Geo.cylinder(fire, Vector3(0, 0.65, 0), 0.38, 0, 1.0, Color("e9a250"), 7)
			Geo.cylinder(fire, Vector3(0, 0.50, 0), 0.23, 0, 0.85, Color("ffdc81"), 7)
			flames.append(fire)
			var light: OmniLight3D = OmniLight3D.new()
			light.position.y = 1.3
			light.light_color = Color("ffb86c")
			light.light_energy = 0.90
			light.omni_range = 5.0
			visual.add_child(light)
			height = 1.8
		"forge":
			Surfaces.apply(Geo.cylinder(visual, Vector3(-0.45, 0.75, 0), 0.85, 0.7, 1.5, Color("8d8674"), 10), "masonry")
			Geo.box(visual, Vector3(-0.45, 0.55, -0.64), Vector3(0.70, 0.6, 0.22), Color("382f29"))
			Geo.box(visual, Vector3(-0.45, 0.45, -0.78), Vector3(0.50, 0.28, 0.03), Color("e9964a"), true)
			Surfaces.apply(Geo.cylinder(visual, Vector3(0.85, 0.35, 0), 0.42, 0.42, 0.7, Color("795c43"), 8), "bark")
			Surfaces.apply(Geo.box(visual, Vector3(0.85, 0.91, 0), Vector3(1.15, 0.25, 0.6), Color("718080")), "metal")
			Surfaces.apply(Geo.box(visual, Vector3(0.85, 0.71, 0), Vector3(0.45, 0.36, 0.45), Color("647476")), "metal")
			size = Vector3(3.1, 2.2, 2.1)
			height = 2.4
		"market":
			Surfaces.apply(Geo.box(visual, Vector3(0, 0.62, 0), Vector3(2.2, 1.15, 1.0), Color("96734d")), "planks")
			for x: float in [-1.15, 1.15]:
				Surfaces.apply(Geo.box(visual, Vector3(x, 1.50, 0.3), Vector3(0.12, 3.0, 0.12), Color("67553e")), "timber")
			Surfaces.apply(Geo.box(visual, Vector3(0, 2.95, 0), Vector3(2.65, 0.16, 1.65), Color("b59f66")), "canvas")
			for x: float in [-0.65, 0.0, 0.65]:
				Geo.sphere(visual, Vector3(x, 1.30, -0.12), 0.18, Color("d8b86f"))
			size = Vector3(2.6, 3.1, 1.8)
			height = 3.5
		"bait_shop":
			Surfaces.apply(Geo.cylinder(visual, Vector3(0, 0.32, 0), 0.34, 0.39, 0.60, Color("857254"), 12), "planks")
			Surfaces.apply(Geo.cylinder(visual, Vector3(0, 0.63, 0), 0.33, 0.33, 0.02, Color("594838"), 12), "earth")
			Geo.ring(visual, Vector3(0, 0.64, 0), 0.37, Color("b6ae91"))
			for offset: Vector3 in [Vector3(-0.13, 0.66, 0), Vector3(0.1, 0.66, -0.12), Vector3(0.12, 0.66, 0.12)]:
				var bait: MeshInstance3D = Geo.sphere(visual, offset, 0.08, Color("d3a080"), Vector3(1.4, 0.4, 0.45))
				bait.rotation.y = offset.x * 5.0
			size = Vector3(1.2, 1.1, 1.2)
			height = 1.55
		"fish":
			Geo.ring(crown, Vector3(0, 0.16, 0), 0.75, Color("c1e0dc"))
			Geo.ring(crown, Vector3(0.18, 0.13, 0.12), 0.43, Color("98cbc9"))
			for offset: Vector3 in [Vector3(-0.22, 0.09, 0.12), Vector3(0.25, 0.09, -0.23)]:
				Geo.sphere(visual, offset, 0.18, Color("385e64"), Vector3(1.5, 0.17, 0.4))
			size = Vector3(Layout.POND.size.x, 0.3, Layout.POND.size.y)
			height = 1.3
		"enemy":
			creature = Creature.build(visual, definition)
			height = float(creature["height"])
			size = Vector3(2.5, height - 0.2, 2.6) if str(creature["species"]) == "warden" else Vector3(2.1, 1.9, 2.7)

	var pick_center: Vector3 = Vector3(0, size.y * 0.5, 0)
	if kind == "fish":
		var pond_center: Vector2 = Layout.POND.get_center()
		pick_center = Vector3(pond_center.x - root.position.x, 0.12, pond_center.y - root.position.z)
	var pick: Area3D = Geo.pick_area(root, id, size, pick_center)
	var text: Label3D = Geo.label(root, str(definition["name"]), Vector3(0, height, 0), Color("efe4c7"), 24)
	text.visible = kind in ["guide", "bank", "campfire", "forge", "market", "fish", "bait_shop", "ranger"]
	targets[id] = {"root": root, "visual": visual, "crown": crown, "label": text, "kind": kind, "pick": pick}
	if kind == "enemy":
		targets[id]["creature"] = creature
		var warning: MeshInstance3D = Creature.build_warning(root, definition)
		warning.visible = false
		targets[id]["warning"] = warning

func _build_details() -> void:
	var decorations: Node3D = Node3D.new()
	decorations.name = "GroundedScenery"
	add_child(decorations)
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = 41721
	# Boundary scenery remains completely outside the expanded walkable bounds.
	for side: float in [-1.0, 1.0]:
		for z: int in range(-63, 31, 10):
			Surfaces.apply(Geo.sphere(decorations, Vector3(side * 37.0, 0.1, z), random.randf_range(3.0, 5.0), Color("6a8063"), Vector3(1, 0.7, 1)), "moss")
	for x: int in range(-25, 30, 10):
		Surfaces.apply(Geo.sphere(decorations, Vector3(x, 0.1, -75), 5.0, Color("657667"), Vector3(1, 0.8, 1)), "moss")
	for i: int in range(95):
		var at: Vector3 = Vector3(random.randf_range(-28, 28), 0.04, random.randf_range(-28, 28))
		if absf(at.x) < 3.0 or absf(at.z + 5.0) < 2.0 or Layout.POND.grow(1.0).has_point(Vector2(at.x, at.z)):
			continue
		if at.x > 8 and at.z < -8:
			continue
		Surfaces.apply(Geo.cylinder(decorations, at, random.randf_range(0.18, 0.42), 0, 0.12, Color("789063"), 5), "grass")
		if i % 4 == 0:
			Geo.sphere(decorations, at + Vector3(0, 0.20, 0), 0.095, Color("d0ba89"))
	Geo.label(decorations, "NORTHREACH  ^", Vector3(0, 3.5, -30.3), Color("d4dabb"), 26)
	for x: float in [-3.0, 3.0]:
		Surfaces.apply(Geo.cylinder(decorations, Vector3(x, 1.5, 6), 0.085, 0.07, 3.0, Color("645841"), 8), "timber")
		Geo.box(decorations, Vector3(x, 3.15, 6), Vector3(0.40, 0.55, 0.40), Color("efd79a"), true)
		Surfaces.apply(Geo.cylinder(decorations, Vector3(x, 3.5, 6), 0.33, 0.03, 0.22, Color("4b5f54"), 6), "metal")
	_ground_decorations(decorations)

func _process(delta: float) -> void:
	elapsed += delta
	for fire: Node3D in flames:
		fire.scale.y = 0.9 + sin(elapsed * 7.0) * 0.12
		fire.rotation.y += delta * 0.3
	if Game.world.is_empty():
		return
	for id: String in targets:
		var entry: Dictionary = targets[id]
		var status: Dictionary = Game.world.get(id, {})
		if status.is_empty():
			continue
		var visual: Node3D = entry["visual"]
		if str(entry["kind"]) == "enemy":
			var root: Node3D = entry["root"]
			root.position = Terrain.grounded(Game.target_position(id))
			visual.visible = bool(status["alive"])
			var pick: Area3D = entry["pick"]
			pick.collision_layer = 2 if bool(status["alive"]) else 0
			Creature.animate(entry, status, elapsed + float(posmod(id.hash(), 9)), delta)
			pick.rotation.y = visual.rotation.y
			var label: Label3D = entry["label"]
			var state: String = str(status["state"])
			label.visible = bool(status["alive"]) and (bool(status["aggro"]) or state == "return" or hovered_id == id)
			var battle_text: String = ""
			if state == "return":
				battle_text = "RETURNING HOME"
			elif state == "windup":
				battle_text = "MOVE OUT!  %.1fs" % maxf(0.0, float(status["state_time"]))
			elif float(status["notice_flash"]) > 0.0:
				battle_text = "!  ENGAGED"
			elif state == "recover":
				battle_text = "RECOVERING" if str(status["strike_result"]) != "miss" else "MISSED / RECOVERING"
			label.text = "%s  %d/%d\n%s" % [str(Game.definitions[id]["name"]), int(status["hp"]), int(Game.definitions[id]["hp"]), battle_text]
			label.modulate = Color("c5d1cd") if state == "return" else Color("f3d8b5")

		else:
			var crown: Node3D = entry["crown"]
			crown.visible = float(status["cooldown"]) <= 0.0
			if str(entry["kind"]) == "fish":
				var ripple_scale: float = 1.0 + sin(elapsed * 1.8) * 0.12
				crown.scale = Vector3(ripple_scale, 1.0, ripple_scale)

func show_hover(id: String) -> void:
	hovered_id = id
	for key: String in targets:
		var entry: Dictionary = targets[key]
		if str(entry["kind"]) == "enemy":
			continue
		var text: Label3D = entry["label"]
		text.visible = str(entry["kind"]) in ["guide", "bank", "campfire", "forge", "market", "fish", "bait_shop", "ranger"] or key == id
		text.modulate = Color("ffe09c") if key == id else Color("efe4c7")

func _build_frontier() -> void:
	# Roads and clearings are blended into the shared terrain, not flat boxes.
	var decorations: Node3D = Node3D.new()
	decorations.name = "GroundedFrontier"
	add_child(decorations)
	for footprint: Rect2 in Layout.OBSTACLES:
		var center: Vector2 = footprint.get_center()
		var tall: bool = center.y > -33
		var height: float = 2.8 if tall else 1.3
		Surfaces.apply(Geo.box(decorations, Vector3(center.x, height * 0.5, center.y), Vector3(footprint.size.x, height, footprint.size.y), Color("82897b")), "masonry")
		Surfaces.apply(Geo.box(decorations, Vector3(center.x, height + 0.08, center.y), Vector3(footprint.size.x + 0.15, 0.16, footprint.size.y + 0.15), Color("a2a590")), "stone")
	Geo.label(decorations, "NORTHREACH CAMP", Vector3(-16, 3.7, -34), Color("e3d7ad"), 28)
	Geo.label(decorations, "WATCHWARDEN RUINS", Vector3(0, 3.8, -65), Color("c8c9ad"), 27)
	Geo.label(decorations, "IRONROOT DIG", Vector3(21, 3.1, -42), Color("d7d2b8"), 25)
	# Road lights and short posts are decorative, deliberately off the path centre.
	for z: float in [-33.0, -42.0, -51.0]:
		for x: float in [-2.8, 2.8]:
			Surfaces.apply(Geo.cylinder(decorations, Vector3(x, 0.6, z), 0.10, 0.08, 1.2, Color("706048"), 8), "timber")
			Surfaces.apply(Geo.box(decorations, Vector3(x, 1.3, z), Vector3(0.3, 0.3, 0.3), Color("bda56f")), "metal")
	_ground_decorations(decorations)

func _ground_decorations(group: Node3D) -> void:
	for child: Node in group.get_children():
		if child is Node3D:
			var item: Node3D = child as Node3D
			item.position = Terrain.grounded(item.position)
