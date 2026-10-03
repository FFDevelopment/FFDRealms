extends SceneTree
## Native regression suite. No player saves are read, written, or deleted.
## godot --headless --path . --script res://tests/frontier_runner.gd
const State = preload("res://scripts/game_state.gd")
const AI = preload("res://scripts/enemy_ai.gd")
const Catalog = preload("res://scripts/catalog.gd")
const Layout = preload("res://scripts/world_layout.gd")
const MapView = preload("res://scripts/world_map.gd")
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
	_test_frontier_navigation()
	_test_follow_and_manual_attacks()
	_test_windup_and_cover()
	_test_return_and_death()
	_test_species_rewards()
	_test_quest_and_steel()
	_test_legacy_save()
	_test_map()
	print("FRONTIER RESULT: %d passed; %d failed." % [passed, failed])
	sim.queue_free()
	quit(1 if failed > 0 else 0)

func check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
		print("FRONTIER PASS: " + label)
	else:
		failed += 1
		push_error("FRONTIER FAIL: " + label)

func fresh() -> void:
	sim.cancel_action(false)
	sim._reset_world()
	sim.character = sim._new_character("Frontier Tester")
	sim.profile_slot = 0
	sim.playing = true
	sim._food_cooldown = 0.0
	sim._attack_cooldown = 0.0

func advance(seconds: float) -> void:
	for _i: int in range(ceili(seconds / 0.05)):
		sim.tick(0.05)

func solo(id: String) -> void:
	for key: String in sim.definitions:
		if str(sim.definitions[key]["kind"]) == "enemy" and key != id:
			sim.world[key]["alive"] = false
			sim.world[key]["cooldown"] = 9999.0

func stand_at(id: String, offset: Vector3 = Vector3(0, 0, 1.6)) -> void:
	sim.character["pos"] = sim.target_position(id) + offset
	sim.station_id = id

func _test_frontier_navigation() -> void:
	fresh()
	check(sim.definitions.size() == 36, "Expanded target catalog is loaded")
	check(sim.navigation.walkable(Vector2i(0, -33)), "North road is open")
	check(sim.navigation.walkable(Vector2i(0, -61)), "Guardian courtyard is walkable")
	check(not sim.navigation.walkable(Vector2i(9, -60)), "Courtyard wall is blocked")
	check(not sim.request_move(Vector3(0, 0, -80)), "Movement beyond new bounds is rejected")
	check(not sim.navigation.clear_position(Vector3(19, 0, 9)), "Original pond remains non-walkable")
	for id: String in sim.definitions:
		var target: Dictionary = sim.definitions[id]
		if target["pos"].z >= -31:
			continue
		var route: PackedVector3Array = sim.navigation.route(Layout.SPAWN, target["pos"], true, str(target["kind"]) == "enemy")
		check(not route.is_empty(), "North-road route exists to " + id)
		var clear: bool = not route.is_empty()
		for i: int in range(route.size()):
			clear = clear and sim.navigation.clear_position(route[i])
			if i > 0:
				clear = clear and sim.navigation.segment_clear(route[i - 1], route[i])
		check(clear, "Route avoids walls, trunks and water: " + id)
	check(Layout.is_safe(Vector3(-14, 0, -33)) and not Layout.is_safe(Vector3(0, 0, -61)), "Camp is safe; guardian arena is not")
	# Shared bank contents, not a second separate bank inventory.
	sim.character["bag"] = {"logs": 3}
	stand_at("bank", Vector3(0, 0, 2))
	check(sim.bank_transfer("logs", 3, true), "Village bank accepts a deposit")
	stand_at("camp_bank", Vector3(0, 0, 2))
	check(sim.bank_transfer("logs", 3, false) and sim.count_item("logs") == 3, "Northreach bank withdraws the same stored supplies")

func _test_follow_and_manual_attacks() -> void:
	fresh()
	solo("slime_1")
	# Approaching from a safe village is allowed; attacking from safety is not.
	check(sim.request_interaction("slime_1") and not sim.pending_target.is_empty(), "Distant enemy click can leave the safe village")
	sim.cancel_action(false)
	stand_at("slime_1")
	check(sim.request_interaction("slime_1"), "One close-range combat click accepted")
	advance(0.2)
	var elapsed: float = sim.action_time
	for _i: int in range(10):
		check(not sim.request_interaction("slime_1"), "Busy clicks never queue extra attacks")
	check(is_equal_approx(sim.action_time, elapsed), "Spam cannot reset swing progress")
	advance(1.0)
	check(int(sim.world["slime_1"]["hp"]) == 15 and sim.active_target.is_empty(), "One click deals one 3-damage hit then stops")
	var previous: Vector3 = sim.target_position("slime_1")
	sim.request_move(Vector3(-3, 0, -16))
	advance(1.0)
	var current: Vector3 = sim.target_position("slime_1")
	check(current.z > previous.z and current.distance_to(previous) <= 2.46, "Enemy follows the retreating player at its configured speed")
	check(bool(sim.world["slime_1"]["aggro"]), "Enemy does not drop aggro at the old melee boundary")
	var face: Vector3 = sim.world["slime_1"]["facing"]
	var committed: bool = str(sim.world["slime_1"]["state"]) in ["windup", "recover"]
	var intended: Vector3 = sim.world["slime_1"]["strike_facing"] if committed else (sim.position_of_player() - current).normalized()
	check(face.dot(intended) > 0.95, "Enemy faces the player in pursuit and holds its committed strike direction")
	advance(4.0)
	check(int(sim.world["slime_1"]["hp"]) == 15 and int(sim.character["xp"]["Combat"]) == 0, "Enemy pursuit creates no automatic player damage or XP")
	var live: Vector3 = sim.target_position("slime_1")
	check(live.distance_to(sim.definitions["slime_1"]["pos"]) > 2.0, "Enemy has a live position independent of its spawn")
	check(sim.request_interaction("slime_1"), "The moved enemy can be clicked again")
	advance(1.2)
	check(int(sim.world["slime_1"]["hp"]) == 12, "Second deliberate click hits the live position")
	var timer: float = float(sim.world["slime_1"]["attack_time"])
	sim.cancel_action(false)
	check(is_equal_approx(float(sim.world["slime_1"]["attack_time"]), timer), "Cancel cannot reset an enemy cooldown")

func _test_windup_and_cover() -> void:
	fresh()
	solo("slime_1")
	stand_at("slime_1")
	var status: Dictionary = sim.world["slime_1"]
	AI.provoke(status)
	AI.begin_windup(sim.definitions["slime_1"], status, sim.position_of_player())
	status["state_time"] = 0.35
	status["hit_flash"] = 0.22
	AI.provoke(status)
	check(str(status["state"]) == "windup" and is_equal_approx(float(status["state_time"]), 0.35), "Hit reaction/reprovocation cannot stun-lock the windup")
	sim.request_move(Vector3(-3, 0, -17))
	advance(0.40)
	check(int(sim.character["hp"]) == 30 and str(status["state"]) == "recover", "Leaving reach during windup dodges the attack")
	# Force a long-reach test across a real obstacle, so sight validation is decisive.
	var definition: Dictionary = sim.definitions["slime_1"].duplicate(true)
	definition["reach"] = 5.0
	definition["pos"] = Vector3(8, 0, -43)
	AI.reset("slime_1", definition, status)
	status["aggro"] = true
	AI.begin_windup(definition, status, Vector3(12, 0, -43))
	status["state_time"] = 0.01
	var damage: int = AI.step("slime_1", definition, status, 0.1, Vector3(12, 0, -43), sim.navigation, sim.world)
	check(damage == 0, "Enemy attack cannot pass through the Ironroot wall")
	check(not sim.navigation.segment_clear(Vector3(8, 0, -43), Vector3(12, 0, -43)), "Cover line is blocked by the same obstacle as pathfinding")
	# Movement should take the route around that wall rather than clip through it.
	status["state"] = "chase"
	status["repath"] = 0.0
	status["attack_time"] = 0.0
	definition["reach"] = 1.9
	var clear: bool = true
	for _i: int in range(100):
		var before: Vector3 = status["pos"]
		AI.step("slime_1", definition, status, 0.1, Vector3(12, 0, -43), sim.navigation, sim.world)
		clear = clear and sim.navigation.segment_clear(before, status["pos"])
	check(clear and status["pos"].distance_to(Vector3(12, 0, -43)) <= 2.1, "Pursuit moves around cover on clear segments")

func _test_return_and_death() -> void:
	fresh()
	solo("slime_1")
	stand_at("slime_1")
	sim.request_interaction("slime_1")
	advance(1.1)
	var status: Dictionary = sim.world["slime_1"]
	sim.character["pos"] = Vector3(-3, 0, -10)
	sim.tick(0.05)
	check(str(status["state"]) == "return" and not bool(status["aggro"]), "Safe-area retreat starts a return-home state")
	check(not sim.request_interaction("slime_1"), "Returning enemies reject attack clicks")
	sim.active_target = "slime_1"
	sim.action_time = sim.action_duration
	sim._hit_enemy("slime_1")
	check(int(status["hp"]) == 15 and int(sim.character["xp"]["Combat"]) == 0, "Returning enemy cannot be chipped down or award XP")
	advance(8.0)
	check(int(status["hp"]) == 18 and not bool(status["aggro"]), "Return home restores full health")
	check(sim.active_target.is_empty() and sim.pending_target.is_empty(), "Return never restarts a player action")
	fresh()
	solo("slime_1")
	stand_at("slime_1")
	sim.character["hp"] = 1
	sim.request_interaction("slime_1")
	advance(3.0)
	check(sim.position_of_player().is_equal_approx(Layout.SPAWN), "Enemy AI can defeat the player and trigger recovery")
	check(not bool(sim.world["slime_1"]["aggro"]), "Player death clears pursuit")
	check(sim.active_target.is_empty() and sim.pending_target.is_empty(), "Player death leaves no queued attack")

func _test_species_rewards() -> void:
	for id: String in ["wolf_1", "crawler_1", "watchwarden"]:
		fresh()
		solo(id)
		sim.character["weapon"] = "iron_sword"
		stand_at(id)
		var before: int = int(sim.character["coins"])
		var clicks: int = 0
		while bool(sim.world[id]["alive"]) and clicks < 20:
			check(sim.request_interaction(id), "Manual attack accepted: " + id)
			advance(1.1)
			clicks += 1
			if int(sim.character["hp"]) < 15:
				sim.eat_food()
		check(not bool(sim.world[id]["alive"]), "Manual combat defeats " + id)
		var definition: Dictionary = sim.definitions[id]
		check(int(sim.character["coins"]) == before + int(definition["coins"]), "Exact species coin reward: " + id)
		check(sim.count_item(str(definition["drop"])) == 1, "Exactly one species drop: " + id)
		check(int(sim.character["xp"]["Combat"]) == int(definition["xp"]), "Exact species Combat XP: " + id)
		var coins: int = int(sim.character["coins"])
		sim._hit_enemy(id)
		check(int(sim.character["coins"]) == coins, "Duplicate completion cannot reward a dead " + id)
		sim.character["pos"] = Layout.SPAWN
		advance(float(definition["respawn"]) + 0.2)
		check(bool(sim.world[id]["alive"]) and int(sim.world[id]["hp"]) == int(definition["hp"]), "Species respawns with full health: " + id)
		check(sim.active_target.is_empty(), "Respawn never restarts player attacks: " + id)

func _test_quest_and_steel() -> void:
	fresh()
	check(not sim.talk_frontier(), "Frontier quest cannot be accepted remotely")
	stand_at("ranger", Vector3(0, 0, 2))
	check(not sim.talk_frontier(), "Elin's quest is the expedition prerequisite")
	sim._frontier_progress("wolves")
	check(int(sim.character["frontier"]["wolves"]) == 0, "Pre-acceptance kills do not count")
	sim.character["quest"]["claimed"] = true
	check(sim.talk_frontier(), "Eligible character accepts Tamsin's quest")
	for key: String in Catalog.FRONTIER_GOALS:
		for _i: int in range(int(Catalog.FRONTIER_GOALS[key]) + 2):
			sim._frontier_progress(key)
		check(int(sim.character["frontier"][key]) == int(Catalog.FRONTIER_GOALS[key]), "Expedition milestone caps: " + key)
	check(sim.frontier_ready(), "All expedition milestones enable turn-in")
	var before: int = int(sim.character["coins"])
	check(sim.talk_frontier(), "Expedition reward is claimable at Tamsin")
	check(int(sim.character["coins"]) == before + 110 and int(sim.character["xp"]["Combat"]) == 100 and int(sim.character["xp"]["Smithing"]) == 80, "Expedition pays its exact coin and XP rewards")
	sim.talk_frontier()
	check(int(sim.character["coins"]) == before + 110, "Expedition reward cannot be claimed twice")
	fresh()
	stand_at("forge", Vector3(0, 0, 2))
	sim.character["xp"]["Smithing"] = 640
	sim.character["bag"] = {"iron_bar": 3, "coal": 6}
	check(not sim.craft("smelt_steel") and sim.count_item("coal") == 6, "Skill alone does not bypass the steel quest gate")
	sim.character["frontier"]["claimed"] = true
	sim.character["xp"]["Smithing"] = 160
	check(not sim.craft("smelt_steel"), "Quest completion does not bypass Smithing 5")
	sim.character["xp"]["Smithing"] = 640
	check(sim.craft("smelt_steel"), "One steel recipe action succeeds when both gates are met")
	advance(10.0)
	check(sim.count_item("steel_bar") == 1 and sim.count_item("iron_bar") == 2 and sim.count_item("coal") == 4, "Steel crafting still requires a click per result")
	check(sim.craft("smelt_steel") and sim.craft("smelt_steel") and sim.craft("forge_steel"), "Remaining deliberate crafts create one steel sword")
	check(sim.equip_weapon("steel_sword") and str(sim.character["weapon"]) == "steel_sword", "Steel sword uses normal equipment handling")

func _test_legacy_save() -> void:
	fresh()
	var legacy: Dictionary = sim.serialized_character()
	legacy.erase("frontier")
	legacy["build"] = "0.1.3"
	legacy["coins"] = 123
	legacy["weapon"] = "iron_sword"
	legacy["bag"] = {"fishing_bait": 7, "oak_logs": 2}
	legacy["quest"]["claimed"] = true
	sim._restore_character(legacy)
	check(int(sim.character["coins"]) == 123 and str(sim.character["weapon"]) == "iron_sword", "Legacy money and equipment survive migration")
	check(sim.count_item("fishing_bait") == 7 and sim.count_item("oak_logs") == 2, "Legacy backpack items survive migration")
	check(bool(sim.character["quest"]["claimed"]) and not bool(sim.character["frontier"]["started"]), "Legacy quest persists and expedition starts unaccepted")
	sim.character["pos"] = Vector3(-14, 0, -33)
	sim.character["frontier"]["started"] = true
	sim.character["frontier"]["wolves"] = 2
	var saved: Dictionary = sim.serialized_character()
	fresh()
	sim._restore_character(saved)
	check(sim.position_of_player().is_equal_approx(Vector3(-14, 0, -33)) and int(sim.character["frontier"]["wolves"]) == 2, "Northern position and expedition progress round-trip")
	check(not saved.has("world") and not saved.has("active_target") and not saved.has("pending_target"), "Save never persists a future attack or world reward")

func _test_map() -> void:
	var map = MapView.new()
	root.add_child(map)
	map.size = Vector2(540, 530)
	for point: Vector3 in [Layout.SPAWN, Vector3(-14, 0, -33), Vector3(0, 0, -61), Vector3(26, 0, 9)]:
		check(map.world_point(map.point(point)).is_equal_approx(point), "Map coordinate round-trip: " + str(point))
	map.queue_free()
