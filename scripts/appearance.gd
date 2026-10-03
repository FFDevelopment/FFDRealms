extends RefCounted
## Validated per-character cosmetics. Only texture objects are shared, never mutable materials.
const DEFAULTS: Dictionary = {
	"skin_color": "deb28c", "hair_color": "493b34", "eyes_color": "293b39",
	"shirt_color": "467e82", "pants_color": "3a4d52", "shoes_color": "53483c",
	"belt_color": "644c39", "pack_color": "886745", "stitch_color": "c8ac78",
	"shirt_fabric": "cotton", "pants_style": "denim", "shoe_fabric": "leather",
	"shoe_style": "boots", "hair_style": "short", "pack_visible": true,
}
const COLOR_LABELS: Dictionary = {
	"skin_color": "Skin", "hair_color": "Hair", "eyes_color": "Eyes",
	"shirt_color": "Top", "pants_color": "Trousers", "shoes_color": "Footwear",
	"belt_color": "Belt", "pack_color": "Backpack", "stitch_color": "Stitching",
}
const OPTIONS: Dictionary = {
	"shirt_fabric": ["cotton", "linen", "knit", "denim"],
	"pants_style": ["denim", "slacks", "canvas"],
	"shoe_fabric": ["leather", "suede"],
	"shoe_style": ["boots", "shoes"],
	"hair_style": ["short", "swept", "bald"],
}
const OPTION_LABELS: Dictionary = {
	"shirt_fabric": "Top fabric", "pants_style": "Trouser style", "shoe_fabric": "Footwear material",
	"shoe_style": "Footwear style", "hair_style": "Hair style",
}
const STYLE_LABELS: Dictionary = {
	"cotton": "Plain cotton", "linen": "Woven linen", "knit": "Knitted wool",
	"denim": "Denim / jeans", "slacks": "Tailored slacks", "canvas": "Canvas workwear",
	"leather": "Leather", "suede": "Suede", "boots": "Ankle boots", "shoes": "Low shoes",
	"short": "Short hair", "swept": "Side-swept hair", "bald": "No hair",
}
static var textures: Dictionary = {}

static func defaults() -> Dictionary:
	return DEFAULTS.duplicate(true)

static func sanitize(source: Variant) -> Dictionary:
	var result: Dictionary = defaults()
	if not source is Dictionary:
		return result
	for key: String in COLOR_LABELS:
		var value: Variant = source.get(key, DEFAULTS[key])
		if value is String:
			var code: String = str(value).trim_prefix("#").to_lower()
			if code.length() == 6 and Color.html_is_valid(code):
				result[key] = code
	for key: String in OPTIONS:
		var value: Variant = source.get(key, DEFAULTS[key])
		if value is String and value in OPTIONS[key]:
			result[key] = value
	if source.get("pack_visible", null) is bool:
		result["pack_visible"] = source["pack_visible"]
	return result

static func fabric_for(slot: String, look: Dictionary) -> String:
	match slot:
		"shirt_color": return str(look["shirt_fabric"])
		"pants_color": return str(look["pants_style"])
		"shoes_color": return str(look["shoe_fabric"])
		"belt_color": return "leather"
		"pack_color": return "canvas"
	return ""

static func fabric_texture(style: String) -> Texture2D:
	if style.is_empty():
		return null
	if textures.has(style):
		return textures[style]
	# Original, deterministic, tileable 128px weave maps. Neutral so dyes remain independent.
	var image: Image = Image.create(128, 128, false, Image.FORMAT_RGBA8)
	for y: int in range(128):
		for x: int in range(128):
			var grain: float = float(posmod(x * 73 + y * 97 + x * y * 13, 29)) / 28.0
			var shade: float = 0.96
			match style:
				"denim":
					shade = 0.68 + (0.25 if posmod(x + y, 8) < 3 else 0.0) + grain * 0.07
				"slacks":
					shade = 0.93 + (0.04 if x % 4 < 2 else 0.0) + grain * 0.03
				"canvas":
					shade = 0.79 + (0.13 if posmod(x / 4 + y / 4, 2) == 0 else 0.0) + grain * 0.08
				"linen":
					shade = 0.78 + (0.10 if x % 8 < 4 else 0.0) + (0.07 if y % 8 < 4 else 0.0) + grain * 0.05
				"knit":
					var stitch: int = absi(x % 16 - 8)
					shade = 0.74 + (0.19 if posmod(y + stitch, 16) < 6 else 0.0) + grain * 0.07
				"leather": shade = 0.91 + grain * 0.09
				"suede": shade = 0.83 + grain * 0.17
				_: shade = 0.93 + (0.035 if (x + y) % 2 == 0 else 0.0) + grain * 0.035
			image.set_pixel(x, y, Color(shade, shade, shade, 1.0))
	image.generate_mipmaps()
	var texture: ImageTexture = ImageTexture.create_from_image(image)
	textures[style] = texture
	return texture
