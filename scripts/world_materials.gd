extends RefCounted
## Presentation-only materials. Never modifies colliders, gameplay state or character dyes.
## PNGs are pre-baked and imported with mipmaps; no texture generation runs each frame.
const ALBEDO: Dictionary = {
	"grass": preload("res://assets/textures/world/grass_albedo.png"),
	"earth": preload("res://assets/textures/world/earth_albedo.png"),
	"path": preload("res://assets/textures/world/path_albedo.png"),
	"cobble": preload("res://assets/textures/world/cobble_albedo.png"),
	"stone": preload("res://assets/textures/world/stone_albedo.png"),
	"masonry": preload("res://assets/textures/world/masonry_albedo.png"),
	"plaster": preload("res://assets/textures/world/plaster_albedo.png"),
	"shingles": preload("res://assets/textures/world/shingles_albedo.png"),
	"timber": preload("res://assets/textures/world/timber_albedo.png"),
	"planks": preload("res://assets/textures/world/planks_albedo.png"),
	"bark": preload("res://assets/textures/world/bark_albedo.png"),
	"leaves": preload("res://assets/textures/world/leaves_albedo.png"),
	"ore": preload("res://assets/textures/world/ore_albedo.png"),
	"canvas": preload("res://assets/textures/world/canvas_albedo.png"),
	"metal": preload("res://assets/textures/world/metal_albedo.png"),
	"moss": preload("res://assets/textures/world/moss_albedo.png"),
	"fur": preload("res://assets/textures/world/fur_albedo.png"),
	"water": preload("res://assets/textures/world/water_albedo.png"),
}
const NORMAL: Dictionary = {
	"grass": preload("res://assets/textures/world/grass_normal.png"),
	"earth": preload("res://assets/textures/world/earth_normal.png"),
	"path": preload("res://assets/textures/world/path_normal.png"),
	"cobble": preload("res://assets/textures/world/cobble_normal.png"),
	"stone": preload("res://assets/textures/world/stone_normal.png"),
	"masonry": preload("res://assets/textures/world/masonry_normal.png"),
	"plaster": preload("res://assets/textures/world/plaster_normal.png"),
	"shingles": preload("res://assets/textures/world/shingles_normal.png"),
	"timber": preload("res://assets/textures/world/timber_normal.png"),
	"planks": preload("res://assets/textures/world/planks_normal.png"),
	"bark": preload("res://assets/textures/world/bark_normal.png"),
	"leaves": preload("res://assets/textures/world/leaves_normal.png"),
	"ore": preload("res://assets/textures/world/ore_normal.png"),
	"canvas": preload("res://assets/textures/world/canvas_normal.png"),
	"metal": preload("res://assets/textures/world/metal_normal.png"),
	"moss": preload("res://assets/textures/world/moss_normal.png"),
	"fur": preload("res://assets/textures/world/fur_normal.png"),
	"water": preload("res://assets/textures/world/water_normal.png"),
}
# Tile frequency is in repeats per metre, not repeats per building or whole map.
const PROFILES: Dictionary = {
	"grass": {"scale": Vector3(0.28, 0.28, 0.28), "roughness": 0.98, "bump": 0.48},
	"earth": {"scale": Vector3(0.40, 0.40, 0.40), "roughness": 0.98, "bump": 0.50},
	"path": {"scale": Vector3(0.38, 0.38, 0.38), "roughness": 0.97, "bump": 0.65},
	"cobble": {"scale": Vector3(0.22, 0.22, 0.22), "roughness": 0.93, "bump": 0.75},
	"stone": {"scale": Vector3(0.56, 0.56, 0.56), "roughness": 0.95, "bump": 0.72},
	"masonry": {"scale": Vector3(0.30, 0.30, 0.30), "roughness": 0.93, "bump": 0.78},
	"plaster": {"scale": Vector3(0.65, 0.65, 0.65), "roughness": 0.98, "bump": 0.35},
	"shingles": {"scale": Vector3(0.32, 0.32, 0.32), "roughness": 0.92, "bump": 0.80},
	"timber": {"scale": Vector3(0.80, 0.40, 0.80), "roughness": 0.92, "bump": 0.60},
	"planks": {"scale": Vector3(0.65, 0.40, 0.65), "roughness": 0.92, "bump": 0.68},
	"bark": {"scale": Vector3(0.90, 0.40, 0.90), "roughness": 1.0, "bump": 0.72},
	"leaves": {"scale": Vector3(0.80, 0.80, 0.80), "roughness": 0.95, "bump": 0.40},
	"ore": {"scale": Vector3(1.1, 1.1, 1.1), "roughness": 0.78, "bump": 0.68},
	"canvas": {"scale": Vector3(1.1, 1.1, 1.1), "roughness": 0.97, "bump": 0.35},
	"metal": {"scale": Vector3(1.2, 1.2, 1.2), "roughness": 0.67, "bump": 0.30},
	"moss": {"scale": Vector3(0.90, 0.90, 0.90), "roughness": 0.98, "bump": 0.62},
	"fur": {"scale": Vector3(0.95, 0.65, 0.95), "roughness": 0.96, "bump": 0.40},
}
static var materials: Dictionary = {}

static func enabled() -> bool:
	return bool(ProjectSettings.get_setting("ffdrealms/visuals/world_textures", true))

static func normals_enabled() -> bool:
	return bool(ProjectSettings.get_setting("ffdrealms/visuals/normal_maps", true))

static func surface(kind: String, tint: Color, world_space: bool = false) -> StandardMaterial3D:
	# Callers never receive an editable character/GUI material through this cache.
	if not PROFILES.has(kind):
		push_error("Unknown world surface: " + kind)
		return null
	var cache_key: String = "%s|%s|%s|%s" % [kind, tint.to_html(), str(world_space), str(normals_enabled())]
	if materials.has(cache_key):
		return materials[cache_key] as StandardMaterial3D
	var profile: Dictionary = PROFILES[kind]
	var result: StandardMaterial3D = StandardMaterial3D.new()
	result.resource_name = "FFD " + kind
	result.albedo_color = tint
	result.albedo_texture = ALBEDO[kind] as Texture2D
	result.roughness = float(profile["roughness"])
	result.metallic_specular = 0.20
	result.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	result.texture_repeat = true
	result.uv1_triplanar = true
	result.uv1_world_triplanar = world_space
	result.uv1_triplanar_sharpness = 8.0
	result.uv1_scale = profile["scale"]
	result.normal_enabled = normals_enabled()
	result.normal_texture = NORMAL[kind] as Texture2D
	result.normal_scale = float(profile["bump"])
	materials[cache_key] = result
	return result

static func apply(instance: MeshInstance3D, kind: String, world_space: bool = false) -> MeshInstance3D:
	# An explicit call applies only to the selected world mesh. No color guessing,
	# recursive scene-wide replacement, collider edits or texture allocation in _process.
	if instance == null or not enabled():
		return instance
	var previous: StandardMaterial3D = instance.material_override as StandardMaterial3D
	if previous == null or previous.emission_enabled or previous.albedo_color.a < 1.0:
		return instance
	var replacement: StandardMaterial3D = surface(kind, previous.albedo_color, world_space)
	if replacement == null:
		return instance
	instance.material_override = replacement
	instance.set_meta("world_surface", kind)
	return instance
