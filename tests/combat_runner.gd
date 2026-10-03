extends SceneTree
## Native Godot regression suite. No reads or writes of actual player profile slots.
const State = preload("res://scripts/game_state.gd")
const AI = preload("res://scripts/enemy_ai.gd")
const Combat = preload("res://scripts/combat_rules.gd")
const Layout = preload("res://scripts/world_layout.gd")
const Creature = preload("res://scripts/enemy_visual.gd")
var sim
var passed: int = 0
var failed: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	sim = State.new()
	root.add_child(sim)
	sim.automatic_ticks = false
	sim.autosave_enabled = false
	_test_strike_geometry()
	_test_proximity()
	_test_committed_strikes()
	_test_attack_and_move()
	_test_cooldown_and_cancel()
	_test_safety_and_cover()
	_test_warning_mesh()
	print("COMBAT RESULT: %d passed; %d failed." % [passed, failed])
	sim.free()
	quit(1 if failed > 0 else 0)

func check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
		print("COMBAT PASS: " + label)
	else:
		failed += 1
		push_error("COMBAT FAIL: " + label)

func fresh(id: String = "slime_1") -> void:
	sim.cancel_action(false)
	sim._reset_world()
	sim.character = sim._new_character("Dodge Tester")
	sim.profile_slot = 0
	sim.playing = true
	sim._food_cooldown = 0.0
	sim._attack_cooldown = 0.0
	for key: String in sim.definitions:
		if str(sim.definitions[key]["kind"]) == "enemy" and key != id:
			sim.world[key]["alive"] = false
			sim.world[key]["cooldown"] = 99999.0

func advance(seconds: float) -> void:
	var remaining: float = seconds
	while remaining > 0.00001:
		var step: float = minf(remaining, 0.05)
		sim.tick(step)
		remaining -= step

func _test_strike_geometry() -> void:
	var origin: Vector3 = Vector3(-3, 0, -23)
	for arc: float in [90.0, 110.0, 120.0, 140.0]:
		var half: float = deg_to_rad(arc * 0.5)
		check(Combat.contains_point(origin, Vector3.BACK, 1.9, half, origin + Vector3(0, 0, 1.8)), "Front point is hittable at arc " + str(arc))
		check(not Combat.contains_point(origin, Vector3.BACK, 1.9, half, origin + Vector3(1.6, 0, 0)), "Side point can dodge while inside melee radius " + str(arc))
		check(not Combat.contains_point(origin, Vector3.BACK, 1.9, half, origin + Vector3(0, 0, -1)), "Behind the committed strike is safe " + str(arc))
		check(not Combat.contains_point(origin, Vector3.BACK, 1.9, half, origin + Vector3(0, 0, 1.901)), "No invisible reach extension " + str(arc))
	check(Combat.contains_point(origin, Vector3.BACK, 1.9, 0.8, origin), "Overlapping the enemy origin does not grant immunity")
	check(not Combat.contains_point(origin, Vector3.ZERO, 1.9, 0.8, origin), "Zero facing is rejected")
	check(not Combat.contains_point(origin, Vector3.BACK, 1.9, 0.8, Vector3(NAN, 0, 0)), "Invalid target coordinate is rejected")
	check(not Combat.contains_point(origin, Vector3.BACK, INF, 0.8, origin), "Invalid radius is rejected")
	check(not Combat.contains_point(origin, Vector3.BACK, 1.9, 0.8, origin + Vector3(0, 2, 1)), "Another floor is not hit")

func _test_proximity() -> void:
	var ids: Array[String] = []
	for key: String in sim.definitions:
		if str(sim.definitions[key]["kind"]) == "enemy":
			ids.append(key)
	for id: String in ids:
		fresh(id)
		var definition: Dictionary = sim.definitions[id]
		var status: Dictionary = sim.world[id]
		var home: Vector3 = status["pos"]
		var notice: float = float(definition.get("notice", Combat.DEFAULT_NOTICE))
		check(notice > 0.0, "Enemy has proximity engagement: " + id)
		var far: Vector3 = home + Vector3(0, 0, notice + 0.4)
		AI.step(id, definition, status, 0.05, far, sim.navigation, sim.world)
		check(not bool(status["aggro"]), "Outside detection radius stays unprovoked: " + id)
		var close: Vector3 = home + Vector3(0, 0, notice * 0.85)
		check(sim.navigation.segment_clear(home, close) and not Layout.is_safe(close), "Detection test has unobstructed unsafe ground: " + id)
		var damage: int = AI.step(id, definition, status, 0.05, close, sim.navigation, sim.world)
		check(bool(status["aggro"]) and damage == 0, "Proximity engages without an instant hit: " + id)
		check(sim.active_target.is_empty(), "Detection never authorizes a player attack: " + id)
	# Detection neither sees through a wall nor wakes a dead creature.
	fresh()
	var def: Dictionary = sim.definitions["slime_1"].duplicate(true)
	def["pos"] = Vector3(8, 0, -43)
	def["notice"] = 5.0
	var status: Dictionary = sim.world["slime_1"]
	AI.reset("slime_1", def, status, sim.navigation)
	AI.step("slime_1", def, status, 0.05, Vector3(12, 0, -43), sim.navigation, sim.world)
	check(not bool(status["aggro"]), "Real wall blocks proximity detection")
	status["alive"] = false
	AI.step("slime_1", def, status, 0.05, Vector3(8, 0, -42), sim.navigation, sim.world)
	check(not bool(status["aggro"]), "Dead enemy cannot engage")

func _test_committed_strikes() -> void:
	for id: String in ["slime_1", "wolf_1", "crawler_1", "watchwarden"]:
		for outcome: String in ["stay", "side", "behind", "range", "reenter"]:
			fresh(id)
			var definition: Dictionary = sim.definitions[id]
			var status: Dictionary = sim.world[id]
			var home: Vector3 = status["pos"]
			var front: Vector3 = home + Vector3(0, 0, 1.5)
			AI.provoke(status)
			AI.begin_windup(definition, status, front)
			var locked: Vector3 = status["strike_facing"]
			var duration: float = float(status["state_time"])
			AI.provoke(status)
			check(is_equal_approx(float(status["state_time"]), duration), "Hit/reprovocation cannot delay committed strike: " + id)
			var target: Vector3 = front
			match outcome:
				"side", "reenter": target = home + Vector3(1.5, 0, 0)
				"behind": target = home - Vector3(0, 0, 1.5)
				"range": target = home + Vector3(0, 0, Combat.reach(definition) + 1.0)
			check(sim.navigation.segment_clear(home, target), "Dodge test is not being decided by cover: " + id + " / " + outcome)
			var total: int = 0
			var elapsed: float = 0.0
			while elapsed < duration + 0.05:
				if outcome == "reenter" and elapsed > duration * 0.5:
					target = front
				total += AI.step(id, definition, status, 0.05, target, sim.navigation, sim.world)
				elapsed += 0.05
			check(status["pos"].is_equal_approx(home) and status["facing"].is_equal_approx(locked), "Windup and recovery do not move or swivel: " + id)
			var expected: int = int(definition.get("damage", 3)) if outcome in ["stay", "reenter"] else 0
			check(total == expected and int(status["strike_id"]) == 1, "Exactly one impact result: " + id + " / " + outcome)
			check(str(status["state"]) == "recover", "A miss still commits enemy recovery: " + id)
			check(str(status["strike_result"]) == ("hit" if expected > 0 else "miss"), "Strike outcome matches current position: " + id)

func _test_attack_and_move() -> void:
	fresh()
	var status: Dictionary = sim.world["slime_1"]
	var home: Vector3 = status["pos"]
	sim.character["pos"] = home + Vector3(0, 0, 1.6)
	AI.provoke(status)
	AI.begin_windup(sim.definitions["slime_1"], status, sim.position_of_player())
	check(sim.request_interaction("slime_1"), "Player can attack during a telegraphed windup")
	advance(0.40)
	check(int(status["hp"]) == 15 and sim.active_target.is_empty(), "Quick player strike lands once before enemy impact")
	var cooldown: float = sim._attack_cooldown
	check(sim.request_move(home + Vector3(1.6, 0, 0.5)), "Player can immediately move during weapon recovery")
	check(is_equal_approx(sim._attack_cooldown, cooldown), "Movement does not erase weapon cooldown")
	advance(0.40)
	check(int(sim.character["hp"]) == 30 and str(status["strike_result"]) == "miss", "Attack then sidestep avoids the enemy impact")
	check(int(status["hp"]) == 15 and int(sim.character["xp"]["Combat"]) == 0, "Dodging creates no automatic hit, kill reward or XP")
	# One missed swing is not permanent immunity: a subsequent windup aims afresh.
	sim.cancel_action(false)
	AI.begin_windup(sim.definitions["slime_1"], status, sim.position_of_player())
	advance(0.80)
	check(int(sim.character["hp"]) == 27, "Standing in the next aimed strike causes damage")

func _test_cooldown_and_cancel() -> void:
	fresh()
	sim.character["pos"] = sim.target_position("slime_1") + Vector3(0, 0, 1.6)
	check(sim.request_interaction("slime_1"), "First manual swing starts")
	advance(0.10)
	sim.request_move(Vector3(-3, 0, -18))
	check(sim.active_target.is_empty() and sim._attack_cooldown > 0.0, "Early movement cancels the hit, not the attack cadence")
	for _i: int in range(10):
		check(not sim.request_interaction("slime_1"), "Cancel-spam cannot bypass cooldown")
	check(not sim.path.is_empty(), "Rejected early attack clicks do not cancel the dodge route")
	advance(1.0)
	check(int(sim.world["slime_1"]["hp"]) == 18 and sim.active_target.is_empty() and sim.pending_target.is_empty(), "Canceled swing and early clicks cannot produce delayed damage")
	sim.cancel_action(false)
	sim.character["pos"] = sim.target_position("slime_1") + Vector3(0, 0, 1.6)
	check(sim.request_interaction("slime_1"), "A fresh click after recovery starts a new swing")
	advance(0.40)
	check(int(sim.world["slime_1"]["hp"]) == 15 and not sim.request_interaction("slime_1"), "Completed quick strike still enforces remaining cooldown")
	sim.character["pos"] = Layout.SPAWN
	advance(8.0)
	check(sim.active_target.is_empty() and sim.pending_target.is_empty(), "Cooldown expiry and return home cannot auto-attack")

func _test_safety_and_cover() -> void:
	fresh()
	var definition: Dictionary = sim.definitions["slime_1"].duplicate(true)
	var status: Dictionary = sim.world["slime_1"]
	definition["pos"] = Vector3(-3, 0, -15)
	AI.reset("slime_1", definition, status, sim.navigation)
	var safe: Vector3 = Vector3(-3, 0, -11.9)
	AI.step("slime_1", definition, status, 0.1, safe, sim.navigation, sim.world)
	check(not bool(status["aggro"]), "Player inside Hearthmere does not trigger nearby enemy")
	AI.provoke(status)
	AI.begin_windup(definition, status, Vector3(-3, 0, -13.5))
	status["state_time"] = 0.01
	var hit: int = AI.step("slime_1", definition, status, 0.1, safe, sim.navigation, sim.world)
	check(hit == 0 and str(status["state"]) == "return", "Town entry cancels a pending strike and starts return")
	var before: Vector3 = status["pos"]
	AI.step("slime_1", definition, status, 0.1, Vector3(-3, 0, -14.0), sim.navigation, sim.world)
	check(not bool(status["aggro"]) and sim.navigation.enemy_segment_clear(before, status["pos"]), "Return movement cannot reacquire or cross into town")
	definition["pos"] = Vector3(8, 0, -43)
	definition["reach"] = 5.0
	AI.reset("slime_1", definition, status, sim.navigation)
	AI.provoke(status)
	AI.begin_windup(definition, status, Vector3(12, 0, -43))
	status["state_time"] = 0.01
	hit = AI.step("slime_1", definition, status, 0.1, Vector3(12, 0, -43), sim.navigation, sim.world)
	check(hit == 0 and str(status["strike_result"]) == "miss", "A committed sector never bypasses impact-time wall checks")

func _test_warning_mesh() -> void:
	fresh()
	var stage: Node3D = Node3D.new()
	root.add_child(stage)
	var visual: Node3D = Node3D.new()
	stage.add_child(visual)
	var definition: Dictionary = sim.definitions["slime_1"]
	var status: Dictionary = sim.world["slime_1"]
	var warning: MeshInstance3D = Creature.build_warning(stage, definition)
	var second: MeshInstance3D = Creature.build_warning(stage, definition)
	var creature: Dictionary = Creature.build(visual, definition)
	var entry: Dictionary = {"visual": visual, "warning": warning, "creature": creature}
	AI.provoke(status)
	AI.begin_windup(definition, status, status["pos"] + Vector3(1.5, 0, 0))
	Creature.animate(entry, status, 1.0, 0.05)
	check(warning.visible and warning.mesh is ArrayMesh, "Windup produces a visible sector mesh")
	check((-warning.basis.z).dot(status["strike_facing"]) > 0.999, "Warning points exactly along the committed strike")
	check(warning.scale == Vector3.ONE, "Warning never scales beyond its damage footprint")
	check(warning.material_override != second.material_override, "Enemies do not share pulsing warning materials")
	var arrays: Array = warning.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var within: bool = true
	for point: Vector3 in vertices:
		within = within and Vector2(point.x, point.z).length() <= Combat.reach(definition) + 0.00001
	check(vertices.size() == 2304 and within, "All warning vertices fit the configured strike reach")
	status["alive"] = false
	Creature.animate(entry, status, 1.2, 0.05)
	check(not warning.visible, "Enemy death hides its attack warning")
	stage.free()
