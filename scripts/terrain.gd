extends RefCounted
## One heightfield drives mesh vertices, collision, movement presentation and map.
## Simulation and saves deliberately keep logical X/Z positions with Y=0.
## Heights are sampled here, NOT stored in saves or independently randomized.
const HeightfieldData = preload("res://scripts/terrain_data.gd")
const DATA: HeightfieldData = preload("res://data/terrain/hearthmere_heightfield.tres")
const WATER_HEIGHT: float = -0.25
const MAX_WALKABLE_GRADE: float = 0.70

static func valid_data() -> bool:
	return DATA.columns > 1 and DATA.rows > 1 and DATA.step > 0.0 and DATA.samples.size() == DATA.columns * DATA.rows

static func _grid(at: Vector2) -> Vector2:
	return Vector2(clampf((at.x - DATA.origin.x) / DATA.step, 0.0, float(DATA.columns - 1) - 0.00001),
		clampf((at.y - DATA.origin.y) / DATA.step, 0.0, float(DATA.rows - 1) - 0.00001))

static func vertex_height(x: int, z: int) -> float:
	return DATA.samples[clampi(z, 0, DATA.rows - 1) * DATA.columns + clampi(x, 0, DATA.columns - 1)]

static func height_at(x: float, z: float) -> float:
	if not is_finite(x) or not is_finite(z):
		return 0.0
	var grid: Vector2 = _grid(Vector2(x, z))
	var ix: int = floori(grid.x)
	var iz: int = floori(grid.y)
	var u: float = grid.x - float(ix)
	var v: float = grid.y - float(iz)
	var a: float = vertex_height(ix, iz)
	var b: float = vertex_height(ix + 1, iz)
	var c: float = vertex_height(ix + 1, iz + 1)
	var d: float = vertex_height(ix, iz + 1)
	# Same A-C diagonal as terrain_mesh.gd. Bilinear interpolation would sink feet.
	if v <= u:
		return a + (b - a) * u + (c - b) * v
	return a + (c - d) * u + (d - a) * v

static func grounded(logical: Vector3) -> Vector3:
	return Vector3(logical.x, height_at(logical.x, logical.z) + logical.y, logical.z)

static func normal_at(x: float, z: float) -> Vector3:
	var dx: float = (height_at(x + 0.25, z) - height_at(x - 0.25, z)) / 0.5
	var dz: float = (height_at(x, z + 0.25) - height_at(x, z - 0.25)) / 0.5
	return Vector3(-dx, 1.0, -dz).normalized()

static func grade_at(at: Vector2) -> float:
	if not at.is_finite():
		return INF
	var grid: Vector2 = _grid(at)
	var x: int = floori(grid.x)
	var z: int = floori(grid.y)
	var a: float = vertex_height(x, z)
	var b: float = vertex_height(x + 1, z)
	var c: float = vertex_height(x + 1, z + 1)
	var d: float = vertex_height(x, z + 1)
	# Conservatively test both actual triangles, not a smoothed visual normal.
	return maxf(Vector2(b - a, c - b).length(), Vector2(c - d, d - a).length()) / DATA.step

static func is_walkable(at: Vector2) -> bool:
	return at.is_finite() and grade_at(at) <= MAX_WALKABLE_GRADE

static func region_name(at: Vector2) -> String:
	if at.x >= 13.0 and at.x <= 25.0 and at.y >= 4.0 and at.y <= 15.0:
		return "Stillwater Pond"
	if at.x >= -27.0 and at.x <= -7.0 and at.y >= -41.0 and at.y <= -31.0:
		return "Northreach Camp"
	if at.y < -53.0 and absf(at.x) < 10.0:
		return "Watchwarden Heights"
	if at.y < -39.0 and at.x > 10.0:
		return "Ironroot Ridge"
	if at.y < -42.0 and at.x < -8.0:
		return "Briarwood Hills"
	if at.y < -8.0 and at.x > 8.0:
		return "Hearthmere Quarry"
	if at.y < -8.0 and at.x < -8.0:
		return "Western Woodland"
	if at.y < -17.0:
		return "Old Watch Rise"
	return "Hearthmere Lowlands"
