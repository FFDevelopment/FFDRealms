extends RefCounted
## Local deterministic enemy simulation. Rendering never decides hits or rewards.
## States: idle -> patrol -> chase -> windup -> recover -> strafe; any fight -> return.
const Layout = preload("res://scripts/world_layout.gd")
const Combat = preload("res://scripts/combat_rules.gd")
const REPATH_INTERVAL: float = 0.35
const BODY_GAP: float = 0.95

static func reset(id: String, definition: Dictionary, status: Dictionary, navigation = null) -> void:
	var home: Vector3 = definition["pos"]
	if navigation != null and not navigation.enemy_clear_position(home):
		home = navigation.nearest_enemy_position(home)
	if not home.is_finite():
		# Fail closed if the map has no valid spawn. Never draw/attack from a town fallback.
		status["alive"] = false
		home = Vector3.ZERO
	status["pos"] = home
	status["home"] = home
	status["facing"] = Vector3(0, 0, 1)
	status["strike_origin"] = home
	status["strike_facing"] = Vector3(0, 0, 1)
	status["strike_reach"] = Combat.reach(definition)
	status["strike_half_angle"] = Combat.half_angle(definition)
	status["strike_duration"] = Combat.windup(definition)
	status["strike_id"] = 0
	status["strike_result"] = ""
	status["notice_flash"] = 0.0
	status["state"] = "idle"
	status["state_time"] = 2.0 + float(posmod(id.hash(), 25)) / 10.0
	status["nav_path"] = PackedVector3Array()
	status["goal"] = home
	status["repath"] = 0.0
	status["stalled"] = 0.0
	status["hit_flash"] = 0.0
	status["swing"] = 0.0
	status["moving"] = false
	status["aggro"] = false
	status["attack_time"] = 0.0
	status["patrol_phase"] = float(posmod(id.hash(), 628)) / 100.0
	status["strafe_sign"] = -1.0 if posmod(id.hash(), 2) == 0 else 1.0

static func provoke(status: Dictionary) -> bool:
	if not bool(status["alive"]) or str(status["state"]) == "return":
		return false
	if not bool(status["aggro"]):
		status["aggro"] = true
		status["notice_flash"] = 0.8
		status["state"] = "chase"
		status["nav_path"] = PackedVector3Array()
		status["repath"] = 0.0
		status["stalled"] = 0.0
	# Existing attack/windup timers survive repeated player clicks and hit reactions.
	return true

static func disengage(status: Dictionary) -> void:
	status["aggro"] = false
	status["state"] = "return"
	status["state_time"] = 0.0
	status["attack_time"] = 0.0
	status["swing"] = 0.0
	status["strike_result"] = ""
	status["notice_flash"] = 0.0
	status["stalled"] = 0.0
	status["repath"] = 0.0
	status["nav_path"] = PackedVector3Array()

static func step(id: String, definition: Dictionary, status: Dictionary, delta: float,
	player: Vector3, navigation, population: Dictionary) -> int:
	# Returns at most one validated damage event. No player actions are created here.
	status["hit_flash"] = maxf(0.0, float(status["hit_flash"]) - delta)
	status["swing"] = maxf(0.0, float(status["swing"]) - delta)
	status["repath"] = maxf(0.0, float(status["repath"]) - delta)
	status["moving"] = false
	status["notice_flash"] = maxf(0.0, float(status["notice_flash"]) - delta)
	if not bool(status["alive"]):
		return 0
	var here: Vector3 = status["pos"]
	var home: Vector3 = status["home"]
	if not navigation.enemy_clear_position(home):
		home = navigation.nearest_enemy_position(home)
		if not home.is_finite():
			status["alive"] = false
			disengage(status)
			return 0
		status["home"] = home
	if not navigation.enemy_clear_position(here):
		# Repair an invalid runtime placement before movement/damage; not normal return behavior.
		status["pos"] = home
		status["hp"] = int(definition["hp"])
		disengage(status)
		return 0
	var speed: float = float(definition.get("speed", 2.45))
	var leash: float = float(definition.get("leash", 12.0))
	var reach: float = Combat.reach(definition)
	if str(status["state"]) == "return":
		_return_home(id, definition, status, delta, navigation, population)
		return 0
	if not bool(status["aggro"]):
		var notice: float = float(definition.get("notice", Combat.DEFAULT_NOTICE))
		if notice > 0.0 and here.distance_to(player) <= notice and home.distance_to(player) <= leash and not Layout.is_safe(player) and _combat_line_clear(here, player, navigation):
			provoke(status)
		else:
			_patrol(id, definition, status, delta, navigation, population)
			return 0
	if player.distance_to(home) > leash or here.distance_to(home) > leash + 0.5 or Layout.is_safe(player) or not navigation.clear_position(player):
		disengage(status)
		return 0
	var toward: Vector3 = player - here
	var distance: float = toward.length()
	# Commit at windup: turning, hit reactions, and movement cannot retarget this swing.
	if str(status["state"]) not in ["windup", "recover"] and distance > 0.01:
		status["facing"] = toward.normalized()
	status["attack_time"] = minf(float(definition.get("interval", 1.6)), float(status["attack_time"]) + delta)
	match str(status["state"]):
		"windup":
			status["state_time"] = float(status["state_time"]) - delta
			if float(status["state_time"]) <= 0.0:
				status["state"] = "recover"
				status["state_time"] = Combat.recovery(definition)
				status["attack_time"] = 0.0
				status["swing"] = 0.24
				status["strike_id"] = int(status["strike_id"]) + 1
				var origin: Vector3 = status["strike_origin"]
				# Position is sampled NOW, against the locked, visibly marked strike.
				var connects: bool = Combat.contains_point(origin, status["strike_facing"],
					float(status["strike_reach"]), float(status["strike_half_angle"]), player)
				connects = connects and _combat_line_clear(origin, player, navigation)
				status["strike_result"] = "hit" if connects else "miss"
				if connects:
					return int(definition.get("damage", 3))
			return 0
		"recover":
			status["state_time"] = float(status["state_time"]) - delta
			if float(status["state_time"]) <= 0.0:
				status["state"] = "strafe"
				status["state_time"] = 0.40
			return 0
		"strafe":
			status["state_time"] = float(status["state_time"]) - delta
			# Short lateral steps, not full orbits that drag melee hits out of reach.
			var side: Vector3 = Vector3(-toward.z, 0, toward.x).normalized() * float(status["strafe_sign"])
			var candidate: Vector3 = here + side * speed * delta * 0.45
			if distance < reach + 0.2 and candidate.distance_to(home) <= leash and navigation.enemy_segment_clear(here, candidate) and _spacing_ok(id, here, candidate, population):
				status["pos"] = candidate
				status["moving"] = true
			if float(status["state_time"]) <= 0.0 or distance > reach + 0.2:
				status["state"] = "chase"
				status["repath"] = 0.0
			return 0
	# Chase closes distance, but never runs through the player or swings through cover.
	status["state"] = "chase"
	if distance < BODY_GAP:
		var back: Vector3 = -toward.normalized() if distance > 0.01 else Vector3.RIGHT
		var candidate: Vector3 = here + back * speed * delta
		if navigation.enemy_segment_clear(here, candidate) and _spacing_ok(id, here, candidate, population):
			status["pos"] = candidate
			status["moving"] = true
	elif distance > reach - 0.30 or not _combat_line_clear(here, player, navigation):
		_plan(status, player, navigation)
		_move(id, status, speed * delta, navigation, population, player, reach - 0.30)
	else:
		status["nav_path"] = PackedVector3Array()
	var at: Vector3 = status["pos"]
	if at.distance_to(player) <= reach and _combat_line_clear(at, player, navigation):
		status["stalled"] = 0.0
		if float(status["attack_time"]) >= float(definition.get("interval", 1.6)):
			begin_windup(definition, status, player)
	else:
		status["stalled"] = 0.0 if bool(status["moving"]) else float(status["stalled"]) + delta
		if float(status["stalled"]) >= 3.0:
			disengage(status)
	return 0

static func begin_windup(definition: Dictionary, status: Dictionary, player: Vector3) -> void:
	# One snapshot owns both collision and presentation until this attack finishes.
	var origin: Vector3 = status["pos"]
	var aim: Vector3 = Vector3(player.x - origin.x, 0, player.z - origin.z)
	if aim.length_squared() < 0.000001:
		aim = status["facing"]
	if aim.length_squared() < 0.000001:
		aim = Vector3.FORWARD
	status["strike_origin"] = origin
	status["strike_facing"] = aim.normalized()
	status["strike_reach"] = Combat.reach(definition)
	status["strike_half_angle"] = Combat.half_angle(definition)
	status["strike_duration"] = Combat.windup(definition)
	status["strike_result"] = ""
	status["facing"] = status["strike_facing"]
	status["state"] = "windup"
	status["state_time"] = status["strike_duration"]
	status["moving"] = false
	status["nav_path"] = PackedVector3Array()

static func _plan(status: Dictionary, destination: Vector3, navigation) -> void:
	var points: PackedVector3Array = status["nav_path"]
	var old_goal: Vector3 = status["goal"]
	if float(status["repath"]) > 0.0:
		return
	if not points.is_empty() and old_goal.distance_to(destination) < 0.75:
		return
	var here: Vector3 = status["pos"]
	points = navigation.enemy_route(here, destination)
	# Avoid snapping/backtracking to rounded start-cell centres at each repath.
	if points.size() > 1 and navigation.enemy_segment_clear(here, points[1]):
		points.remove_at(0)
	status["nav_path"] = points
	status["goal"] = destination
	status["repath"] = REPATH_INTERVAL

static func _move(id: String, status: Dictionary, budget: float, navigation, population: Dictionary,
	stop_at: Vector3 = Vector3.INF, stop_range: float = 0.0) -> void:
	var points: PackedVector3Array = status["nav_path"]
	while not points.is_empty() and budget > 0.001:
		var here: Vector3 = status["pos"]
		if stop_at.is_finite() and here.distance_to(stop_at) <= stop_range and navigation.segment_clear(here, stop_at):
			points.clear()
			break
		var next: Vector3 = points[0]
		var distance: float = here.distance_to(next)
		if distance <= 0.025:
			points.remove_at(0)
			continue
		var stride: float = minf(budget, minf(distance, 0.16))
		var candidate: Vector3 = here.move_toward(next, stride)
		if not navigation.enemy_segment_clear(here, candidate) or not _spacing_ok(id, here, candidate, population):
			points.clear()
			break
		status["pos"] = candidate
		if not bool(status["aggro"]):
			status["facing"] = (next - here).normalized()
		status["moving"] = true
		budget -= stride
		if distance <= stride + 0.001:
			points.remove_at(0)
	status["nav_path"] = points

static func _spacing_ok(id: String, from: Vector3, to: Vector3, population: Dictionary) -> bool:
	for other_id: String in population:
		if other_id == id:
			continue
		var other: Dictionary = population[other_id]
		if not other.has("state") or not bool(other["alive"]):
			continue
		var other_pos: Vector3 = other["pos"]
		if to.distance_to(other_pos) < BODY_GAP and to.distance_to(other_pos) < from.distance_to(other_pos) - 0.001:
			return false
	return true

static func _patrol(id: String, definition: Dictionary, status: Dictionary, delta: float, navigation, population: Dictionary) -> void:
	var roam: float = float(definition.get("roam", 1.6))
	if str(status["state"]) == "patrol":
		_move(id, status, float(definition.get("speed", 2.45)) * 0.40 * delta, navigation, population)
		var points: PackedVector3Array = status["nav_path"]
		if points.is_empty():
			status["state"] = "idle"
			status["state_time"] = 2.5
		return
	status["state_time"] = float(status["state_time"]) - delta
	if float(status["state_time"]) > 0.0 or roam <= 0.0:
		return
	status["patrol_phase"] = float(status["patrol_phase"]) + 2.4
	var angle: float = float(status["patrol_phase"])
	var home: Vector3 = status["home"]
	var goal: Vector3 = home + Vector3(cos(angle), 0, sin(angle)) * roam
	goal = Vector3(roundf(goal.x), 0, roundf(goal.z))
	if goal.distance_to(home) <= roam + 0.5 and navigation.enemy_clear_position(goal) and not Layout.is_safe(goal):
		status["repath"] = 0.0
		_plan(status, goal, navigation)
		status["state"] = "patrol"
	else:
		status["state_time"] = 2.5

static func _return_home(id: String, definition: Dictionary, status: Dictionary, delta: float, navigation, population: Dictionary) -> void:
	var home: Vector3 = status["home"]
	var here: Vector3 = status["pos"]
	if here.distance_to(home) <= 0.10 and navigation.enemy_segment_clear(here, home):
		status["pos"] = home
		status["hp"] = int(definition["hp"])
		status["heal_delay"] = 0.0
		status["state"] = "idle"
		status["state_time"] = 3.0
		status["nav_path"] = PackedVector3Array()
		status["stalled"] = 0.0
		return
	_plan(status, home, navigation)
	_move(id, status, float(definition.get("speed", 2.45)) * 1.15 * delta, navigation, population)
	status["stalled"] = 0.0 if bool(status["moving"]) else float(status["stalled"]) + delta
	if float(status["stalled"]) > 2.0:
		# Crowd recovery: allow returning actors to pass other actors, never static walls.
		status["nav_path"] = PackedVector3Array()
		status["repath"] = 0.0
		_plan(status, home, navigation)
		_move(id, status, float(definition.get("speed", 2.45)) * delta, navigation, {})

static func _combat_line_clear(from: Vector3, to: Vector3, navigation) -> bool:
	return not Layout.segment_crosses_safe(from, to) and navigation.segment_clear(from, to)
