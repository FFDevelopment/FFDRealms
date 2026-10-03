extends Control
signal destination_chosen(verb: String, payload: Dictionary)
const Terrain = preload("res://scripts/terrain.gd")
const RELIEF_MAP = preload("res://assets/textures/terrain/world_relief.png")
const Layout = preload("res://scripts/world_layout.gd")
var font: Font
var caption_style: StyleBoxFlat = StyleBoxFlat.new()

func _ready() -> void:
	custom_minimum_size = Vector2(540, 530)
	mouse_filter = Control.MOUSE_FILTER_STOP
	font = ThemeDB.fallback_font
	caption_style.bg_color = Color(0.08, 0.13, 0.11, 0.90)
	queue_redraw()

func _process(_delta: float) -> void:
	queue_redraw()

func map_scale() -> float:
	return minf(size.x / Layout.MAP_BOUNDS.size.x, size.y / Layout.MAP_BOUNDS.size.y)

func map_offset() -> Vector2:
	return (size - Layout.MAP_BOUNDS.size * map_scale()) * 0.5

func point(pos: Vector3) -> Vector2:
	return map_offset() + (Vector2(pos.x, pos.z) - Layout.MAP_BOUNDS.position) * map_scale()

func world_point(at: Vector2) -> Vector3:
	var horizontal: Vector2 = (at - map_offset()) / maxf(map_scale(), 0.001) + Layout.MAP_BOUNDS.position
	return Vector3(horizontal.x, 0, horizontal.y)

func _footprint(rect: Rect2, tint: Color) -> void:
	draw_rect(Rect2(point(Vector3(rect.position.x, 0, rect.position.y)), rect.size * map_scale()), tint)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("20362e"))
	# This cached image is baked from the mesh's heightfield and material masks.
	draw_texture_rect(RELIEF_MAP, Rect2(map_offset(), Layout.MAP_BOUNDS.size * map_scale()), false)
	for area: Rect2 in Layout.SAFE_AREAS:
		# Outline only: never hide the terrain beneath an opaque safe-town rectangle.
		draw_rect(Rect2(point(Vector3(area.position.x, 0, area.position.y)), area.size * map_scale()), Color("b7dab3"), false, 1.5)
	for building: Dictionary in Layout.BUILDINGS:
		_footprint(Layout.building_rect(building), Color(str(building["roof"])))
	for obstacle: Rect2 in Layout.OBSTACLES:
		_footprint(obstacle, Color("a0a38d"))
	if not Game.path.is_empty():
		var route: PackedVector2Array = PackedVector2Array([point(Game.position_of_player())])
		for destination: Vector3 in Game.path:
			route.append(point(destination))
		if route.size() > 1:
			draw_polyline(route, Color("e8d596"), 2.0)
	for id: String in Game.definitions:
		var target: Dictionary = Game.definitions[id]
		var kind: String = str(target["kind"])
		if kind == "enemy" and not bool(Game.world[id]["alive"]):
			continue
		var at: Vector2 = point(Game.target_position(id))
		var tint: Color = Color("e0ce9d")
		match kind:
			"tree", "oak": tint = Color("abd08e")
			"rock": tint = Color("cfb299")
			"enemy": tint = Color("dd9d89")
		draw_circle(at, 4.5, Color("293d34"))
		draw_circle(at, 3.0, tint)
		if kind == "ranger" or kind == "guide":
			draw_arc(at, 7, 0, TAU, 16, Color("efdea2"), 1.0)
	if font != null:
		for region: Dictionary in [
			{"name": "WATCHWARDEN", "pos": Vector3(-8, 0, -63)},
			{"name": "BRIARWOOD", "pos": Vector3(-28, 0, -55)},
			{"name": "IRONROOT", "pos": Vector3(13, 0, -53)},
			{"name": "NORTHREACH", "pos": Vector3(-26, 0, -32)},
			{"name": "OLD WATCH", "pos": Vector3(-6, 0, -28)},
			{"name": "HEARTHMERE", "pos": Vector3(-7, 0, 22)}]:
			draw_string(font, point(region["pos"]), str(region["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("e0ddc2"))
		draw_string(font, Vector2(9, 20), "NORTH ^", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("d8dfbd"))
		var hovered: String = _nearest(get_local_mouse_position(), 9.0)
		_draw_legend()
		var cursor: Vector3 = world_point(get_local_mouse_position())
		var caption: String = ""
		if not hovered.is_empty():
			caption = str(Game.definitions[hovered]["name"])
		elif Layout.in_bounds(cursor):
			caption = "%s / %.1f m" % [Terrain.region_name(Vector2(cursor.x, cursor.z)), Terrain.height_at(cursor.x, cursor.z)]
		if not caption.is_empty():
			draw_style_box(caption_style, Rect2(6, size.y - 27, size.x - 12, 25))
			draw_string(font, Vector2(12, size.y - 9), caption, HORIZONTAL_ALIGNMENT_LEFT, size.x - 24, 13, Color("fff0c8"))
	var player: Vector2 = point(Game.position_of_player())
	draw_circle(player, 6.5, Color("283c33"))
	draw_circle(player, 4.5, Color("ffe2a1"))
	draw_arc(player, 9, 0, TAU, 24, Color("ffe2a1"), 1.5)

func _draw_legend() -> void:
	# The portrait map leaves a side margin; don't cover map paths with the key.
	if map_offset().x < 92.0:
		return
	var entries: Array = [
		["Meadow", Color("637d4f")], ["Woodland", Color("47663f")],
		["Rock / ore", Color("828573")], ["Paths", Color("a68f66")],
		["Paving", Color("a1997a")], ["Water", Color("355c61")],
		["Safe town", Color("b7dab3")]]
	for i: int in range(entries.size()):
		var y: float = 46.0 + float(i) * 24.0
		draw_rect(Rect2(10, y - 9, 9, 9), entries[i][1])
		draw_string(font, Vector2(25, y), str(entries[i][0]), HORIZONTAL_ALIGNMENT_LEFT, 72, 10, Color("ddd9bd"))
	draw_string(font, Vector2(10, 231), "Contours: 1 m", HORIZONTAL_ALIGNMENT_LEFT, 90, 10, Color("bbc7ae"))
	draw_string(font, Vector2(10, 251), "Click to travel", HORIZONTAL_ALIGNMENT_LEFT, 90, 10, Color("bbc7ae"))

func _nearest(at: Vector2, radius: float) -> String:
	var nearest: String = ""
	var distance: float = radius
	for id: String in Game.definitions:
		if str(Game.definitions[id]["kind"]) == "enemy" and not bool(Game.world[id]["alive"]):
			continue
		var d: float = at.distance_to(point(Game.target_position(id)))
		if d < distance:
			distance = d
			nearest = id
	return nearest

func _gui_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton:
		return
	var click: InputEventMouseButton = event
	if click.button_index != MOUSE_BUTTON_LEFT or not click.pressed:
		return
	var destination: Vector3 = world_point(click.position)
	if not Layout.in_bounds(destination):
		accept_event()
		return
	var nearest: String = _nearest(click.position, 8.0)
	if not nearest.is_empty():
		var payload: Dictionary = {"id": nearest}
		if nearest == "fish_1":
			payload["water_pos"] = Game.definitions[nearest]["pos"]
		destination_chosen.emit("interact", payload)
	elif Layout.POND.has_point(Vector2(destination.x, destination.z)):
		destination_chosen.emit("interact", {"id": "fish_1", "water_pos": destination})
	else:
		destination_chosen.emit("move", {"pos": destination})
	accept_event()
