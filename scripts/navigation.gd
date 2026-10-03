extends RefCounted
## Grid navigation prevents building/water traversal and diagonal corner cutting.
const Terrain = preload("res://scripts/terrain.gd")
const Layout = preload("res://scripts/world_layout.gd")
var grid: AStarGrid2D = AStarGrid2D.new()
var enemy_grid: AStarGrid2D = AStarGrid2D.new()
var solid_rects: Array[Rect2] = []
var solid_points: Array[Vector2] = []

func build() -> void:
	solid_rects.clear()
	solid_points.clear()
	solid_rects.append(Layout.POND.grow(Layout.NAV_CLEARANCE))
	for building: Dictionary in Layout.BUILDINGS:
		solid_rects.append(Layout.building_rect(building).grow(Layout.NAV_CLEARANCE))
	for obstacle: Rect2 in Layout.OBSTACLES:
		solid_rects.append(obstacle.grow(Layout.NAV_CLEARANCE))
	for target: Dictionary in Layout.targets():
		if str(target["kind"]) in Layout.SOLID_TARGET_KINDS:
			var at: Vector3 = target["pos"]
			solid_points.append(Vector2(at.x, at.z))
	grid.region = Rect2i(-Layout.LIMIT, Layout.NORTH_LIMIT, Layout.LIMIT * 2 + 1, Layout.LIMIT - Layout.NORTH_LIMIT + 1)
	grid.cell_size = Vector2.ONE
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	grid.update()
	enemy_grid.region = grid.region
	enemy_grid.cell_size = grid.cell_size
	enemy_grid.diagonal_mode = grid.diagonal_mode
	enemy_grid.default_compute_heuristic = grid.default_compute_heuristic
	enemy_grid.default_estimate_heuristic = grid.default_estimate_heuristic
	enemy_grid.update()
	for x: int in range(-Layout.LIMIT, Layout.LIMIT + 1):
		for z: int in range(Layout.NORTH_LIMIT, Layout.LIMIT + 1):
			grid.set_point_solid(Vector2i(x, z), _blocked(Vector2(x, z)))
			enemy_grid.set_point_solid(Vector2i(x, z), _blocked(Vector2(x, z)) or Layout.enemy_forbidden(Vector3(x, 0, z)))

func _blocked(point: Vector2) -> bool:
	if not Terrain.is_walkable(point):
		return true
	for rect: Rect2 in solid_rects:
		if rect.has_point(point):
			return true
	for at: Vector2 in solid_points:
		if point.distance_to(at) <= Layout.TARGET_SOLID_RADIUS:
			return true
	return false

func walkable(cell: Vector2i) -> bool:
	return grid.is_in_boundsv(cell) and not grid.is_point_solid(cell)

func nearest_cell(pos: Vector3) -> Vector2i:
	var base: Vector2i = Vector2i(clampi(roundi(pos.x), -Layout.LIMIT, Layout.LIMIT), clampi(roundi(pos.z), Layout.NORTH_LIMIT, Layout.LIMIT))
	if walkable(base):
		return base
	var best: Vector2i = Vector2i(0, 8)
	var distance: float = INF
	for radius: int in range(1, 10):
		for x: int in range(-radius, radius + 1):
			for y: int in range(-radius, radius + 1):
				var candidate: Vector2i = base + Vector2i(x, y)
				if walkable(candidate):
					var d: float = Vector2(candidate).distance_squared_to(Vector2(pos.x, pos.z))
					if d < distance:
						distance = d
						best = candidate
		if distance < INF:
			return best
	return best

func route(from: Vector3, to: Vector3, interaction: bool = false, combat: bool = false) -> PackedVector3Array:
	var start: Vector2i = nearest_cell(from)
	var finish: Vector2i = nearest_cell(to)
	if interaction:
		var shortest: float = INF
		for x: int in range(-2, 3):
			for z: int in range(-2, 3):
				var candidate: Vector2i = Vector2i(roundi(to.x) + x, roundi(to.z) + z)
				var world: Vector3 = Vector3(candidate.x, 0, candidate.y)
				if not walkable(candidate) or world.distance_to(to) > 2.15:
					continue
				if combat and (Layout.is_safe(world) or Layout.segment_crosses_safe(world, to) or not segment_clear(world, to)):
					continue
				var trial: PackedVector2Array = grid.get_point_path(start, candidate)
				if not trial.is_empty():
					var score: float = float(trial.size()) + world.distance_to(to) * 0.05
					if score < shortest:
						shortest = score
						finish = candidate
		if combat and shortest == INF:
			return PackedVector3Array()
	var path_2d: PackedVector2Array = grid.get_point_path(start, finish)
	var result: PackedVector3Array = PackedVector3Array()
	# Include the nearest start-cell centre; omitting it can cut obstacle corners.
	for point: Vector2 in path_2d:
		result.append(Vector3(point.x, 0, point.y))
	return result

func clear_position(pos: Vector3) -> bool:
	if not Layout.in_bounds(pos) or absf(pos.y) > 0.1:
		return false
	return not _blocked(Vector2(pos.x, pos.z)) and walkable(Vector2i(roundi(pos.x), roundi(pos.z)))

func segment_clear(from: Vector3, to: Vector3) -> bool:
	# Continuous collision sampling also prevents melee through walls or water.
	if not Layout.in_bounds(from) or not Layout.in_bounds(to):
		return false
	var steps: int = maxi(1, ceili(from.distance_to(to) / 0.20))
	for index: int in range(steps + 1):
		if not clear_position(from.lerp(to, float(index) / float(steps))):
			return false
	return true

func can_fish_from(pos: Vector3) -> bool:
	return clear_position(pos) and pos.distance_to(Layout.pond_point(pos)) <= Layout.FISHING_BANK_RANGE

func fishing_approach(from: Vector3, requested_water: Vector3) -> Dictionary:
	if not from.is_finite() or not Layout.is_pond_point(requested_water):
		return {}
	# Already beside ANY bank? Keep the exact current position, not a fixed marker.
	if can_fish_from(from):
		return {"stand_pos": from, "cast_pos": Layout.fishing_cast_from(from, requested_water),
			"path": PackedVector3Array()}
	var start: Vector2i = nearest_cell(from)
	if not walkable(start):
		return {}
	var best: Dictionary = {}
	var best_cost: float = INF
	var margin: int = ceili(Layout.FISHING_BANK_RANGE)
	for x: int in range(floori(Layout.POND.position.x) - margin, ceili(Layout.POND.end.x) + margin + 1):
		for z: int in range(floori(Layout.POND.position.y) - margin, ceili(Layout.POND.end.y) + margin + 1):
			var stand: Vector3 = Vector3(x, 0, z)
			if not can_fish_from(stand) or from.distance_to(stand) > best_cost:
				continue
			var trial: PackedVector2Array = grid.get_point_path(start, Vector2i(x, z))
			if trial.is_empty():
				continue
			var route_points: PackedVector3Array = PackedVector3Array()
			var cost: float = 0.0
			var last: Vector3 = from
			for point: Vector2 in trial:
				var next: Vector3 = Vector3(point.x, 0, point.y)
				cost += last.distance_to(next)
				route_points.append(next)
				last = next
			if cost < best_cost:
				best_cost = cost
				best = {"stand_pos": stand, "cast_pos": Layout.fishing_cast_from(stand, requested_water),
					"path": route_points}
	return best

func enemy_walkable(cell: Vector2i) -> bool:
	return enemy_grid.is_in_boundsv(cell) and not enemy_grid.is_point_solid(cell)

func enemy_clear_position(pos: Vector3) -> bool:
	return clear_position(pos) and not Layout.enemy_forbidden(pos) and enemy_walkable(Vector2i(roundi(pos.x), roundi(pos.z)))

func enemy_segment_clear(from: Vector3, to: Vector3) -> bool:
	return not Layout.segment_crosses_safe(from, to, Layout.ENEMY_SAFE_MARGIN) and segment_clear(from, to) and enemy_clear_position(to)

func nearest_enemy_position(pos: Vector3) -> Vector3:
	# No default/failure fallback into the player spawn or either town.
	if not pos.is_finite():
		return Vector3.INF
	var best: Vector3 = Vector3.INF
	var distance: float = INF
	var base: Vector2i = Vector2i(clampi(roundi(pos.x), -Layout.LIMIT, Layout.LIMIT), clampi(roundi(pos.z), Layout.NORTH_LIMIT, Layout.LIMIT))
	# Most calls take the zero-radius fast path; wide scan is only for invalid/legacy placements.
	for radius: int in range(0, Layout.LIMIT - Layout.NORTH_LIMIT + 2):
		for x: int in range(-radius, radius + 1):
			for z: int in range(-radius, radius + 1):
				if maxi(absi(x), absi(z)) != radius:
					continue
				var cell: Vector2i = base + Vector2i(x, z)
				if not enemy_walkable(cell):
					continue
				var world: Vector3 = Vector3(cell.x, 0, cell.y)
				var candidate_distance: float = world.distance_squared_to(pos)
				if candidate_distance < distance:
					best = world
					distance = candidate_distance
		if best.is_finite():
			return best
	return Vector3.INF

func enemy_route(from: Vector3, to: Vector3) -> PackedVector3Array:
	if not enemy_clear_position(from) or not to.is_finite() or Layout.is_safe(to):
		return PackedVector3Array()
	var start: Vector3 = nearest_enemy_position(from)
	var finish: Vector3 = nearest_enemy_position(to)
	if not start.is_finite() or not finish.is_finite():
		return PackedVector3Array()
	var points: PackedVector2Array = enemy_grid.get_point_path(Vector2i(roundi(start.x), roundi(start.z)), Vector2i(roundi(finish.x), roundi(finish.z)))
	var result: PackedVector3Array = PackedVector3Array()
	var previous: Vector3 = from
	for point: Vector2 in points:
		var next: Vector3 = Vector3(point.x, 0, point.y)
		if not enemy_segment_clear(previous, next):
			return PackedVector3Array()
		result.append(next)
		previous = next
	return result
