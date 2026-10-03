extends SceneTree
## Native material/import/isolation checks. This does not certify rendered appearance.
const Surfaces = preload("res://scripts/world_materials.gd")
const World = preload("res://scripts/world.gd")
const Geo = preload("res://scripts/geometry.gd")
const Actor = preload("res://scripts/actor.gd")
var checks_failed: int = 0
var checks_passed: int = 0

func _initialize() -> void:
	Engine.max_fps = 60
	call_deferred("_run")

func _run() -> void:
	create_timer(30.0).timeout.connect(_on_timeout)
	Game.autosave_enabled = false
	Game.automatic_ticks = false
	var original_enabled: bool = Surfaces.enabled()
	var original_normals: bool = Surfaces.normals_enabled()
	ProjectSettings.set_setting("ffdrealms/visuals/world_textures", true)
	ProjectSettings.set_setting("ffdrealms/visuals/normal_maps", true)
	_check(Surfaces.ALBEDO.size() == 18 and Surfaces.NORMAL.size() == 18, "All 18 color/normal map pairs are preloaded")
	for kind: String in Surfaces.ALBEDO:
		var color_map: Texture2D = Surfaces.ALBEDO[kind] as Texture2D
		var normal_map: Texture2D = Surfaces.NORMAL[kind] as Texture2D
		_check(color_map != null and normal_map != null, kind + " resources import as textures")
		if color_map != null and normal_map != null:
			_check(color_map.get_width() == 512 and color_map.get_height() == 512 and normal_map.get_width() == 512 and normal_map.get_height() == 512, kind + " has the expected 512px maps")
	for kind: String in Surfaces.PROFILES:
		var mat: StandardMaterial3D = Surfaces.surface(kind, Color("8a9576"))
		_check(mat != null, kind + " constructs a material")
		if mat == null:
			continue
		_check(mat.albedo_texture == Surfaces.ALBEDO[kind] and mat.normal_texture == Surfaces.NORMAL[kind], kind + " binds the correct pair")
		_check(mat.texture_repeat and mat.texture_filter == BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC, kind + " uses filtered repeating textures")
		_check(mat.uv1_triplanar and not mat.uv1_world_triplanar, kind + " local mapping stays on moving meshes")
		_check(mat.normal_enabled and mat.normal_scale > 0.0 and mat.roughness >= 0.65, kind + " keeps subtle non-glossy material response")
		_check(Surfaces.surface(kind, Color("8a9576")) == mat, kind + " reuses the immutable material cache")
	var textured_world: Node3D = World.new()
	root.add_child(textured_world)
	textured_world.set_process(false)
	var counts: Dictionary = {}
	_count_surfaces(textured_world, counts)
	var ground: MeshInstance3D = textured_world.get_node("TerrainSurface") as MeshInstance3D
	var ground_material: ShaderMaterial = ground.material_override as ShaderMaterial
	for kind: String in Surfaces.ALBEDO:
		var bound_to_ground: bool = kind in ["grass", "path", "stone", "cobble"] and ground_material.get_shader_parameter(kind + "_map") == Surfaces.ALBEDO[kind]
		_check(int(counts.get(kind, 0)) > 0 or bound_to_ground, kind + " is actually assigned to world/creature or terrain material")
	var previous_character: Dictionary = Game.character.duplicate(true)
	var collision_contract: Array = []
	_collect_collisions(textured_world, collision_contract)
	_check(collision_contract.size() == 37, "One real terrain collider and all 36 interaction shapes remain")
	var water: MeshInstance3D = _find_surface(textured_world, "water")
	_check(water != null and water.material_override is ShaderMaterial, "Pond uses its dedicated opaque water shader")
	if water != null and water.material_override is ShaderMaterial:
		var water_mat: ShaderMaterial = water.material_override as ShaderMaterial
		_check(water_mat.get_shader_parameter("ripple_map") == Surfaces.ALBEDO["water"], "Animated water binds its ripple map")
		_check(water_mat.get_shader_parameter("ripple_normal") == Surfaces.NORMAL["water"], "Animated water binds its normal map")
	var entries: Dictionary = textured_world.get("targets")
	var enemy: Dictionary = entries["slime_1"]
	var warning: MeshInstance3D = enemy["warning"]
	var warning_mat: StandardMaterial3D = warning.material_override as StandardMaterial3D
	_check(not warning.has_meta("world_surface") and warning_mat != null and warning_mat.albedo_texture == null, "Attack warning remains untextured and independent")
	_check(warning_mat != null and warning_mat.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED, "Orange strike sector retains its unshaded readability")
	textured_world.free()
	ProjectSettings.set_setting("ffdrealms/visuals/world_textures", false)
	var plain_world: Node3D = World.new()
	root.add_child(plain_world)
	plain_world.set_process(false)
	var plain_counts: Dictionary = {}
	_count_surfaces(plain_world, plain_counts)
	var plain_collisions: Array = []
	_collect_collisions(plain_world, plain_collisions)
	_check(plain_counts.is_empty(), "Fallback applies no new world textures")
	_check(plain_collisions == collision_contract, "Texture setting cannot change collision shapes, positions or interaction areas")
	_check(Game.character == previous_character, "Building either visual mode does not change the character")
	plain_world.free()
	ProjectSettings.set_setting("ffdrealms/visuals/world_textures", true)
	var holder: Node3D = Node3D.new()
	root.add_child(holder)
	var tint: Color = Color("796246")
	var original: StandardMaterial3D = Geo.material(tint)
	var piece: MeshInstance3D = Geo.box(holder, Vector3.ZERO, Vector3.ONE, tint)
	Surfaces.apply(piece, "timber")
	_check(original.albedo_texture == null and piece.material_override != original, "World texture application never mutates the plain-material cache")
	var glow: MeshInstance3D = Geo.box(holder, Vector3.ZERO, Vector3.ONE, tint, true)
	var previous_glow: Material = glow.material_override
	Surfaces.apply(glow, "timber")
	_check(glow.material_override == previous_glow, "Emissive indicators cannot be overwritten by the world texture helper")
	var actor = Actor.new()
	holder.add_child(actor)
	actor.build_actor("Material Test")
	var skin: StandardMaterial3D = actor.slot_materials["skin_color"]
	var shirt: StandardMaterial3D = actor.slot_materials["shirt_color"]
	var before_skin: Color = skin.albedo_color
	var before_shirt: Texture2D = shirt.albedo_texture
	Surfaces.surface("canvas", Color("334477"))
	_check(skin.albedo_color == before_skin and shirt.albedo_texture == before_shirt and skin.albedo_texture == null, "Wardrobe dyes and fabrics are untouched")
	holder.free()
	ProjectSettings.set_setting("ffdrealms/visuals/normal_maps", false)
	var flat: StandardMaterial3D = Surfaces.surface("stone", tint)
	_check(not flat.normal_enabled and flat.albedo_texture != null, "Normal-map fallback keeps color textures")
	ProjectSettings.set_setting("ffdrealms/visuals/world_textures", original_enabled)
	ProjectSettings.set_setting("ffdrealms/visuals/normal_maps", original_normals)
	print("TEXTURE RESULT: %d passed; %d failed. Imported resources/materials only; no rendered visual acceptance." % [checks_passed, checks_failed])
	quit(1 if checks_failed > 0 else 0)

func _count_surfaces(node: Node, counts: Dictionary) -> void:
	if node.has_meta("world_surface"):
		var kind: String = str(node.get_meta("world_surface"))
		counts[kind] = int(counts.get(kind, 0)) + 1
	for child: Node in node.get_children():
		_count_surfaces(child, counts)

func _find_surface(node: Node, kind: String) -> MeshInstance3D:
	if node is MeshInstance3D and str(node.get_meta("world_surface", "")) == kind:
		return node as MeshInstance3D
	for child: Node in node.get_children():
		var found: MeshInstance3D = _find_surface(child, kind)
		if found != null:
			return found
	return null

func _collect_collisions(node: Node, records: Array) -> void:
	if node is CollisionShape3D:
		var collider: CollisionShape3D = node as CollisionShape3D
		var shape: BoxShape3D = collider.shape as BoxShape3D
		if shape != null:
			records.append({"transform": collider.global_transform, "size": shape.size})
		elif collider.shape is ConcavePolygonShape3D:
			var ground_shape: ConcavePolygonShape3D = collider.shape as ConcavePolygonShape3D
			records.append({"transform": collider.global_transform, "terrain_faces": ground_shape.get_faces()})
	for child: Node in node.get_children():
		_collect_collisions(child, records)

func _check(ok: bool, description: String) -> void:
	if ok:
		checks_passed += 1
		print("TEXTURE PASS: " + description)
	else:
		checks_failed += 1
		push_error("TEXTURE FAIL: " + description)

func _on_timeout() -> void:
	push_error("TEXTURE FAIL: suite timed out before completion")
	quit(1)
