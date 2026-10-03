extends RefCounted
## Shared source of truth for visible footprints, target positions and navigation.
## Coordinates are metres; Vector2(x, z) maps onto the horizontal world plane.

const SPAWN: Vector3 = Vector3(0, 0, 8)
const LIMIT: int = 29
const NORTH_LIMIT: int = -67
const MAP_BOUNDS: Rect2 = Rect2(-31, -69, 62, 100)
const SAFE_AREAS: Array[Rect2] = [Rect2(-29, -12, 58, 41), Rect2(-27, -41, 20, 10)]
# Every new wall is shared by visible geometry, map, pathfinding and melee sight tests.
const OBSTACLES: Array[Rect2] = [
	Rect2(-4, -31, 1.3, 1.3), Rect2(2.7, -31, 1.3, 1.3),
	Rect2(-9, -66, 1.0, 12.0), Rect2(9, -66, 1.0, 12.0),
	Rect2(-9, -66, 19.0, 1.0),
	Rect2(-9, -55, 6.0, 1.0), Rect2(3, -55, 7.0, 1.0),
	Rect2(9, -46, 1.3, 5.0),
]
const NAV_CLEARANCE: float = 0.65
# Covers current creature silhouettes, including their visual attack lean.
const ENEMY_SAFE_MARGIN: float = 2.1
const TARGET_SOLID_RADIUS: float = 1.05
const SOLID_TARGET_KINDS: Array[String] = ["tree", "oak", "rock", "campfire", "bank", "forge", "market", "guide", "bait_shop", "ranger"]
const POND: Rect2 = Rect2(13, 4, 12, 11)
const FISHING_BANK_RANGE: float = 2.0
const FISHING_CAST_INSET: float = 1.25
const FISHING_MAX_CAST: float = 4.5
const BUILDINGS: Array[Dictionary] = [
	{"name": "Hearthmere Lodge", "center": Vector2(-10, 2), "size": Vector2(6, 6), "roof": "765855"},
	{"name": "Storehouse", "center": Vector2(-9, 14), "size": Vector2(6, 5), "roof": "46686a"},
	{"name": "Forge shed", "center": Vector2(8, -5), "size": Vector2(6, 5), "roof": "695554"},
	{"name": "Provisioner", "center": Vector2(7, 16), "size": Vector2(6, 5), "roof": "52685a"},
]

static func targets() -> Array[Dictionary]:
	return [
		{"id": "guide", "kind": "guide", "name": "Warden Elin", "pos": Vector3(0, 0, 2)},
		{"id": "bank", "kind": "bank", "name": "Village bank", "pos": Vector3(-5, 0, 9)},
		{"id": "campfire", "kind": "campfire", "name": "Campfire", "pos": Vector3(-4, 0, 4)},
		{"id": "forge", "kind": "forge", "name": "Smelter & anvil", "pos": Vector3(7, 0, 0)},
		{"id": "market", "kind": "market", "name": "Mara's provisions", "pos": Vector3(5, 0, 10)},
		{"id": "pine_1", "kind": "tree", "name": "Pine tree", "pos": Vector3(-14, 0, -6), "item": "logs", "skill": "Woodcutting", "level": 1, "xp": 12, "duration": 1.8, "stock": 3, "respawn": 9.0},
		{"id": "pine_2", "kind": "tree", "name": "Pine tree", "pos": Vector3(-19, 0, -7), "item": "logs", "skill": "Woodcutting", "level": 1, "xp": 12, "duration": 1.8, "stock": 3, "respawn": 9.0},
		{"id": "pine_3", "kind": "tree", "name": "Pine tree", "pos": Vector3(-14, 0, -13), "item": "logs", "skill": "Woodcutting", "level": 1, "xp": 12, "duration": 1.8, "stock": 3, "respawn": 9.0},
		{"id": "oak_1", "kind": "oak", "name": "Old oak (level 3)", "pos": Vector3(-22, 0, -18), "item": "oak_logs", "skill": "Woodcutting", "level": 3, "xp": 24, "duration": 2.4, "stock": 4, "respawn": 12.0},
		{"id": "copper_1", "kind": "rock", "name": "Copper outcrop", "pos": Vector3(12, 0, -13), "item": "copper_ore", "skill": "Mining", "level": 1, "xp": 14, "duration": 2.0, "stock": 3, "respawn": 10.0},
		{"id": "copper_2", "kind": "rock", "name": "Copper outcrop", "pos": Vector3(17, 0, -17), "item": "copper_ore", "skill": "Mining", "level": 1, "xp": 14, "duration": 2.0, "stock": 3, "respawn": 10.0},
		{"id": "tin_1", "kind": "rock", "name": "Tin outcrop", "pos": Vector3(18, 0, -10), "item": "tin_ore", "skill": "Mining", "level": 1, "xp": 14, "duration": 2.0, "stock": 3, "respawn": 10.0},
		{"id": "iron_1", "kind": "rock", "name": "Iron outcrop (level 3)", "pos": Vector3(23, 0, -21), "item": "iron_ore", "skill": "Mining", "level": 3, "xp": 28, "duration": 2.5, "stock": 4, "respawn": 12.0},
		# The bucket is a shop, not the source of fish. Stand on dry land and cast into water.
		{"id": "bait_bucket", "kind": "bait_shop", "name": "Bait bucket", "pos": Vector3(10, 0, 6)},
		{"id": "fish_1", "kind": "fish", "name": "Stillwater Pond - trout", "pos": Vector3(14.7, 0, 8), "bait_item": "fishing_bait", "item": "raw_trout", "skill": "Fishing", "level": 1, "xp": 12, "duration": 2.0, "stock": -1, "respawn": 0.0},
		{"id": "slime_1", "kind": "enemy", "name": "Mossling", "pos": Vector3(-3, 0, -23), "hp": 18, "notice": 3.5, "windup": 0.75, "recovery": 0.65, "attack_arc": 110.0},
		{"id": "slime_2", "kind": "enemy", "name": "Mossling", "pos": Vector3(2, 0, -25), "hp": 18, "notice": 3.5, "windup": 0.75, "recovery": 0.65, "attack_arc": 110.0},
		{"id": "slime_3", "kind": "enemy", "name": "Mossling", "pos": Vector3(5, 0, -20), "hp": 18, "notice": 3.5, "windup": 0.75, "recovery": 0.65, "attack_arc": 110.0},
		# Northreach frontier: shared services use the existing bank and inventory.
		{"id": "ranger", "kind": "ranger", "name": "Ranger Tamsin", "pos": Vector3(-14, 0, -36)},
		{"id": "camp_bank", "kind": "bank", "name": "Northreach bank", "pos": Vector3(-21, 0, -35)},
		{"id": "camp_fire", "kind": "campfire", "name": "Northreach campfire", "pos": Vector3(-18, 0, -38)},
		{"id": "camp_forge", "kind": "forge", "name": "Frontier forge", "pos": Vector3(-24, 0, -38)},
		{"id": "camp_shop", "kind": "market", "name": "Northreach supplies", "pos": Vector3(-10, 0, -35)},
		{"id": "oak_2", "kind": "oak", "name": "Briarwood oak (level 3)", "pos": Vector3(-23, 0, -46), "item": "oak_logs", "skill": "Woodcutting", "level": 3, "xp": 24, "duration": 2.4, "stock": 4, "respawn": 12.0},
		{"id": "oak_3", "kind": "oak", "name": "Briarwood oak (level 3)", "pos": Vector3(-23, 0, -56), "item": "oak_logs", "skill": "Woodcutting", "level": 3, "xp": 24, "duration": 2.4, "stock": 4, "respawn": 12.0},
		{"id": "pine_4", "kind": "tree", "name": "Frontier pine", "pos": Vector3(-20, 0, -61), "item": "logs", "skill": "Woodcutting", "level": 1, "xp": 12, "duration": 1.8, "stock": 3, "respawn": 9.0},
		{"id": "iron_2", "kind": "rock", "name": "Ironroot iron (level 3)", "pos": Vector3(16, 0, -41), "item": "iron_ore", "skill": "Mining", "level": 3, "xp": 28, "duration": 2.5, "stock": 4, "respawn": 12.0},
		{"id": "iron_3", "kind": "rock", "name": "Ironroot iron (level 3)", "pos": Vector3(24, 0, -46), "item": "iron_ore", "skill": "Mining", "level": 3, "xp": 28, "duration": 2.5, "stock": 4, "respawn": 12.0},
		{"id": "coal_1", "kind": "rock", "name": "Coal seam (level 3)", "pos": Vector3(19, 0, -55), "item": "coal", "skill": "Mining", "level": 3, "xp": 30, "duration": 2.6, "stock": 4, "respawn": 14.0},
		{"id": "coal_2", "kind": "rock", "name": "Coal seam (level 3)", "pos": Vector3(14, 0, -59), "item": "coal", "skill": "Mining", "level": 3, "xp": 30, "duration": 2.6, "stock": 4, "respawn": 14.0},
		{"id": "coal_3", "kind": "rock", "name": "Coal seam (level 3)", "pos": Vector3(24, 0, -62), "item": "coal", "skill": "Mining", "level": 3, "xp": 30, "duration": 2.6, "stock": 4, "respawn": 14.0},
		{"id": "wolf_1", "kind": "enemy", "species": "wolf", "name": "Briar wolf", "pos": Vector3(-16, 0, -47), "hp": 30, "speed": 3.2, "damage": 4, "interval": 1.7, "windup": 0.65, "recovery": 0.60, "attack_arc": 90.0, "leash": 12.0, "roam": 2.0, "notice": 4.0, "coins": 10, "xp": 42, "drop": "wolf_pelt", "respawn": 18.0},
		{"id": "wolf_2", "kind": "enemy", "species": "wolf", "name": "Briar wolf", "pos": Vector3(-13, 0, -52), "hp": 30, "speed": 3.2, "damage": 4, "interval": 1.7, "windup": 0.65, "recovery": 0.60, "attack_arc": 90.0, "leash": 12.0, "roam": 2.0, "notice": 4.0, "coins": 10, "xp": 42, "drop": "wolf_pelt", "respawn": 18.0},
		{"id": "crawler_1", "kind": "enemy", "species": "crawler", "name": "Stone crawler", "pos": Vector3(17, 0, -48), "hp": 38, "speed": 2.0, "damage": 4, "interval": 2.0, "windup": 0.90, "recovery": 0.80, "attack_arc": 120.0, "leash": 10.0, "roam": 1.6, "notice": 3.0, "coins": 13, "xp": 52, "drop": "stone_shard", "respawn": 20.0},
		{"id": "crawler_2", "kind": "enemy", "species": "crawler", "name": "Stone crawler", "pos": Vector3(22, 0, -58), "hp": 38, "speed": 2.0, "damage": 4, "interval": 2.0, "windup": 0.90, "recovery": 0.80, "attack_arc": 120.0, "leash": 10.0, "roam": 1.6, "notice": 3.0, "coins": 13, "xp": 52, "drop": "stone_shard", "respawn": 20.0},
		{"id": "watchwarden", "kind": "enemy", "species": "warden", "name": "The Watchwarden", "pos": Vector3(0, 0, -61), "hp": 72, "speed": 1.9, "damage": 7, "interval": 2.3, "windup": 1.10, "recovery": 1.00, "attack_arc": 140.0, "reach": 2.05, "leash": 8.0, "roam": 1.0, "notice": 5.0, "coins": 38, "xp": 120, "drop": "warden_core", "respawn": 40.0},
	]

static func interaction_position(target: Dictionary) -> Vector3:
	# Non-fishing targets use melee/service reach. Fishing has a per-click shore plan.
	return target["pos"]

static func building_rect(building: Dictionary) -> Rect2:
	var center: Vector2 = building["center"]
	var size: Vector2 = building["size"]
	return Rect2(center - size * 0.5, size)

static func region_name(pos: Vector3) -> String:
	if pos.z < -31:
		if SAFE_AREAS[1].has_point(Vector2(pos.x, pos.z)):
			return "Northreach Camp"
		if pos.z < -54 and absf(pos.x) <= 10:
			return "Watchwarden Ruins"
		if pos.x > 8 and pos.z < -40:
			return "Ironroot Dig"
		if pos.x < -8 and pos.z < -41:
			return "Briarwood"
		return "Northreach Frontier"
	if pos.z < -18:
		return "The Overgrown Watch"
	if pos.x < -11:
		return "Whisperwood"
	if pos.x > 9 and pos.z < -7:
		return "Copperfall Quarry"
	if pos.x > 9:
		return "Stillwater Pond"
	return "Hearthmere"

static func pond_point(pos: Vector3) -> Vector3:
	# Nearest point on the rectangular water footprint, not a movement destination.
	return Vector3(clampf(pos.x, POND.position.x, POND.end.x), 0,
		clampf(pos.z, POND.position.y, POND.end.y))

static func is_pond_point(pos: Vector3) -> bool:
	return pos.is_finite() and absf(pos.y) < 1.0 and POND.has_point(Vector2(pos.x, pos.z))

static func fishing_cast_from(stand: Vector3, requested: Vector3) -> Vector3:
	var water: Rect2 = POND.grow(-FISHING_CAST_INSET)
	var aim: Vector3 = Vector3(clampf(requested.x, water.position.x, water.end.x), 0,
		clampf(requested.z, water.position.y, water.end.y))
	if stand.distance_to(aim) <= FISHING_MAX_CAST:
		return aim
	# A click across the pond still casts into nearby water, never a pond-wide line.
	return Vector3(clampf(stand.x, water.position.x, water.end.x), 0,
		clampf(stand.z, water.position.y, water.end.y))

static func in_bounds(pos: Vector3) -> bool:
	return pos.is_finite() and absf(pos.x) <= LIMIT and pos.z >= NORTH_LIMIT and pos.z <= LIMIT

static func is_safe(pos: Vector3) -> bool:
	if not pos.is_finite():
		return false
	return _inside_safe_footprint(pos, 0.0)

static func enemy_forbidden(pos: Vector3) -> bool:
	return not pos.is_finite() or _inside_safe_footprint(pos, ENEMY_SAFE_MARGIN)

static func _inside_safe_footprint(pos: Vector3, margin: float) -> bool:
	# Inclusive edges: Rect2.has_point alone excludes the right and bottom edges.
	for original: Rect2 in SAFE_AREAS:
		var area: Rect2 = original.grow(margin)
		if pos.x >= area.position.x and pos.x <= area.end.x and pos.z >= area.position.y and pos.z <= area.end.y:
			return true
	return false

static func segment_crosses_safe(from: Vector3, to: Vector3, margin: float = 0.0) -> bool:
	# Exact closed 2D slab intersection. Endpoints outside do not imply a safe path.
	if not from.is_finite() or not to.is_finite():
		return true
	var origin: Vector2 = Vector2(from.x, from.z)
	var direction: Vector2 = Vector2(to.x - from.x, to.z - from.z)
	for original: Rect2 in SAFE_AREAS:
		var area: Rect2 = original.grow(margin)
		var enter: float = 0.0
		var leave: float = 1.0
		var intersects: bool = true
		for axis: int in range(2):
			if absf(direction[axis]) < 0.000001:
				if origin[axis] < area.position[axis] or origin[axis] > area.end[axis]:
					intersects = false
					break
			else:
				var first: float = (area.position[axis] - origin[axis]) / direction[axis]
				var last: float = (area.end[axis] - origin[axis]) / direction[axis]
				enter = maxf(enter, minf(first, last))
				leave = minf(leave, maxf(first, last))
				if enter > leave:
					intersects = false
					break
		if intersects:
			return true
	return false
