extends SceneTree
## Run with: godot --headless --path . --script res://tests/test_runner.gd
## Test saves live ONLY in user://test_profiles, never in the three player slots.
const State = preload("res://scripts/game_state.gd")
const Catalog = preload("res://scripts/catalog.gd")
const Saves = preload("res://scripts/save_store.gd")
const Layout = preload("res://scripts/world_layout.gd")
var sim
var passed: int = 0
var failed: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	sim = State.new()
	sim.name = "IsolatedSimulation"
	root.add_child(sim)
	sim.automatic_ticks = false
	sim.autosave_enabled = false
	_test_levels()
	_test_navigation()
	_test_inventory()
	_test_harvesting()
	_test_fishing_and_bait()
	_test_shoreline()
	_test_manual_actions()
	_test_crafting()
	_test_bank_and_shop()
	_test_food_and_combat()
	_test_quest()
	_test_profiles()
	print("\nRESULT: %d passed; %d failed." % [passed, failed])
	print("These are in-engine simulation checks. They do not replace visual or Windows playtesting.")
	sim.queue_free()
	quit(1 if failed > 0 else 0)

func check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
		print("PASS: " + label)
	else:
		failed += 1
		push_error("FAIL: " + label)

func fresh() -> void:
	sim.cancel_action(false)
	sim._reset_world()
	sim.character = sim._new_character("Tester")
	sim.profile_slot = 0
	sim.playing = true
	sim._food_cooldown = 0.0
	sim._attack_cooldown = 0.0

func advance(seconds: float) -> void:
	for _i: int in range(ceili(seconds / 0.1)):
		sim.tick(0.1)

func visit(id: String) -> void:
	check(sim.request_interaction(id), "Request interaction with " + id)
	for _i: int in range(600):
		if sim.pending_target.is_empty():
			break
		sim.tick(0.1)
	var target: Dictionary = sim.definitions[id]
	if str(target["kind"]) == "fish":
		check(sim.active_target == id and sim.navigation.can_fish_from(sim.position_of_player()), "Reach a dry shoreline through navigation")
	else:
		check(sim.position_of_player().distance_to(sim.target_position(id)) <= State.REACH + 0.06, "Reach " + id + " through navigation")

func _test_levels() -> void:
	check(Catalog.level_for_xp(0) == 1, "New skills begin at level 1")
	check(Catalog.level_for_xp(39) == 1, "XP threshold lower boundary")
	check(Catalog.level_for_xp(40) == 2, "40 XP gives level 2")
	check(Catalog.level_for_xp(160) == 3, "160 XP gives level 3")
	check(Catalog.level_for_xp(-10) == 1, "Negative XP cannot lower level below 1")
	check(Catalog.level_for_xp(100000000) == 50, "Prototype level cap is enforced")

func _test_navigation() -> void:
	fresh()
	check(not sim.navigation.walkable(Vector2i(19, 9)), "Pond is blocked")
	check(not sim.navigation.walkable(Vector2i(-10, 2)), "Building footprint is blocked")
	check(not sim.navigation.walkable(Vector2i(-14, -6)), "Tree trunk is blocked")
	check(not sim.navigation.walkable(Vector2i(7, 0)), "Forge footprint is blocked")
	check(sim.navigation.walkable(Vector2i(0, 8)), "Spawn is navigable")
	var route: PackedVector3Array = sim.navigation.route(Vector3(-16, 0, 2), Vector3(-4, 0, 2))
	check(route.size() > 12, "Route goes around the lodge rather than through it")
	var legal: bool = true
	for i: int in range(route.size()):
		var cell: Vector2i = Vector2i(roundi(route[i].x), roundi(route[i].z))
		legal = legal and sim.navigation.walkable(cell)
		if i > 0:
			var last: Vector2i = Vector2i(roundi(route[i - 1].x), roundi(route[i - 1].z))
			if last.x != cell.x and last.y != cell.y:
				legal = legal and sim.navigation.walkable(Vector2i(last.x, cell.y)) and sim.navigation.walkable(Vector2i(cell.x, last.y))
	check(legal, "Path cells are walkable and never cut blocked diagonal corners")
	check(not sim.request_move(Vector3(INF, 0, 0)), "Non-finite movement request rejected")
	var before: Vector3 = sim.position_of_player()
	sim.request_move(Vector3(0, 0, 20))
	sim.tick(0.1)
	check(sim.position_of_player().distance_to(before) <= State.WALK_SPEED * 0.1 + 0.01, "Movement is speed-limited, not a teleport")
	sim.cancel_action(false)
	var stopped: Vector3 = sim.position_of_player()
	advance(1.0)
	check(sim.position_of_player().is_equal_approx(stopped), "Cancel stops movement")

func _test_inventory() -> void:
	fresh()
	check(sim.bag_used() == 3, "Starter backpack contains 3 cooked trout")
	check(sim._add_item("logs", 25), "Backpack accepts exact remaining capacity")
	check(sim.bag_used() == 28, "Inventory capacity is 28 units")
	check(not sim._add_item("logs", 1), "Inventory overflow rejected")
	check(not sim._add_item("unknown_item", 1), "Unknown item rejected")
	check(not sim._remove_item("logs", -2), "Negative item removal rejected")
	check(not sim._remove_item("logs", 26), "Removing more than owned is rejected")
	check(sim.count_item("logs") == 25, "Rejected transactions leave inventory unchanged")

func _test_harvesting() -> void:
	fresh()
	check(not sim.request_interaction("iron_1"), "Level-1 player cannot mine iron")
	check(not sim.request_interaction("oak_1"), "Level-1 player cannot chop oak")
	visit("pine_1")
	advance(5.7)
	check(sim.count_item("logs") == 1, "One click yields only one log, even after several action durations")
	check(sim.active_target.is_empty() and int(sim.world["pine_1"]["stock"]) == 2, "Harvest stops with stock remaining")
	for _i: int in range(2):
		visit("pine_1")
		advance(2.0)
	check(sim.count_item("logs") == 3, "Three separate clicks yield three logs")
	check(int(sim.world["pine_1"]["stock"]) == 0, "Three manually completed chops deplete the tree")
	check(int(sim.character["xp"]["Woodcutting"]) == 36, "Gathering awards expected XP")
	check(int(sim.character["quest"]["wood"]) == 0, "Quest actions do not count before acceptance")
	check(not sim.request_interaction("pine_1"), "A depleted node rejects rather than queues a click")
	advance(12.0)
	check(int(sim.world["pine_1"]["stock"]) == 3, "Pine replenishes after its cooldown")
	check(sim.count_item("logs") == 3 and sim.active_target.is_empty() and sim.pending_target.is_empty(), "Replenishing does not resume gathering")
	visit("pine_1")
	advance(0.4)
	sim.cancel_action(false)
	advance(3.0)
	check(sim.count_item("logs") == 3, "Interrupted harvest gives no partial reward")
	fresh()
	sim._add_item("logs", 25)
	check(not sim.request_interaction("copper_1"), "Full inventory rejects ore gathering immediately")
	advance(6.0)
	check(sim.count_item("copper_ore") == 0, "Full inventory prevents new ore")
	check(int(sim.world["copper_1"]["stock"]) == 3, "Failed harvest does not consume the resource node")

func _test_fishing_and_bait() -> void:
	fresh()
	var fish: Dictionary = sim.definitions["fish_1"]
	var water: Vector3 = fish["pos"]
	var plan: Dictionary = sim.navigation.fishing_approach(sim.position_of_player(), water)
	check(not plan.is_empty(), "A dynamic bank plan exists from spawn")
	var bank: Vector3 = plan.get("stand_pos", Vector3.ZERO)
	check(Layout.POND.has_point(Vector2(water.x, water.z)), "Fish target is in the pond")
	check(not fish.has("stand_pos"), "Fishing no longer has one fixed standing point")
	check(sim.navigation.can_fish_from(bank), "Dynamic standing point is dry and navigable")
	check(not sim.request_interaction("fish_1"), "Fishing without carried bait is rejected")
	check(sim.pending_target.is_empty() and sim.active_target.is_empty(), "No bait leaves no pending fishing action")
	check(not sim.buy_bait(1), "Bait cannot be bought remotely")
	visit("bait_bucket")
	check(sim.station_id == "bait_bucket" and sim.active_target.is_empty(), "Bucket opens a shop, not a fishing action")
	advance(3.0)
	check(sim.count_item("raw_trout") == 0, "Interacting with the bucket never grants fish")
	for amount: int in [-1, 0, 2, 100001]:
		check(not sim.buy_bait(amount), "Invalid bait pack rejected: %d" % amount)
	check(not sim.dispatch("buy_bait", {"amount": 1.5}), "Fractional bait quantity rejected")
	check(not sim.dispatch("buy_bait", {"amount": "5"}), "String bait quantity rejected")
	check(sim.buy_bait(5), "Five-bait purchase succeeds at bucket")
	check(int(sim.character["coins"]) == 10 and sim.count_item("fishing_bait") == 5, "Bait purchase charges exactly one coin per bait")
	check(sim.bag_used() == 4, "Five bait occupy one slot beside three food")
	visit("fish_1")
	check(sim.active_target == "fish_1", "Arriving at bank starts pond fishing")
	check(sim.facing.dot((sim.fishing_cast_position() - sim.position_of_player()).normalized()) > 0.99, "Character faces the water instead of the bucket")
	advance(2.1)
	check(sim.count_item("raw_trout") == 1 and sim.count_item("fishing_bait") == 4, "One completed catch exchanges exactly one bait for one fish")
	check(int(sim.character["xp"]["Fishing"]) == 12, "Completed catch grants exactly 12 Fishing XP")
	sim.cancel_action(false)
	var bait_before: int = sim.count_item("fishing_bait")
	visit("fish_1")
	advance(0.4)
	sim.cancel_action(false)
	advance(3.0)
	check(sim.count_item("fishing_bait") == bait_before and sim.count_item("raw_trout") == 1, "Canceling a partial catch preserves bait and grants no fish")
	check(int(sim.character["xp"]["Fishing"]) == 12, "Canceled catch grants no extra XP")
	fresh()
	sim.character["bag"] = {"fishing_bait": 1}
	visit("fish_1")
	advance(2.1)
	check(sim.count_item("fishing_bait") == 0 and sim.count_item("raw_trout") == 1, "Final bait produces exactly one fish")
	check(sim.active_target.is_empty(), "Running out of bait automatically stops fishing")
	advance(6.0)
	check(sim.count_item("raw_trout") == 1, "Fishing cannot continue after bait runs out")
	fresh()
	sim.character["bag"] = {"logs": 27, "fishing_bait": 2}
	check(sim.bag_used() == 28, "Stacked bait respects the 28-slot limit")
	check(not sim.request_interaction("fish_1"), "Full backpack blocks a catch when the bait stack would remain")
	check(sim.count_item("fishing_bait") == 2 and sim.count_item("raw_trout") == 0, "Blocked catch consumes no bait or inventory")
	sim.character["bag"]["fishing_bait"] = 1
	visit("fish_1")
	advance(2.1)
	check(sim.count_item("raw_trout") == 1 and sim.bag_used() == 28 and sim.count_item("fishing_bait") == 0, "Final bait may free its slot for the catch in a full bag")
	fresh()
	sim.character["bag"] = {"logs": 26, "fishing_bait": 2}
	visit("fish_1")
	advance(4.3)
	check(sim.count_item("raw_trout") == 1 and sim.count_item("fishing_bait") == 1 and sim.active_target.is_empty(), "One click stops after the first fish with bait left")
	visit("fish_1")
	advance(2.1)
	check(sim.count_item("raw_trout") == 2 and sim.bag_used() == 28 and sim.active_target.is_empty(), "Two separate casts handle the final-bait slot exchange without overflow")
	fresh()
	sim.character["bag"] = {"fishing_bait": 2}
	visit("fish_1")
	sim.character["bag"]["logs"] = 27
	advance(2.1)
	check(sim.count_item("fishing_bait") == 2 and sim.count_item("raw_trout") == 0 and sim.active_target.is_empty(), "Capacity is checked again at catch completion")
	fresh()
	sim.character["bag"] = {"fishing_bait": 1}
	visit("fish_1")
	sim.character["bag"].erase("fishing_bait")
	advance(2.1)
	check(sim.count_item("raw_trout") == 0 and int(sim.character["xp"]["Fishing"]) == 0, "Missing bait at completion cannot grant fish or XP")
	fresh()
	visit("bait_bucket")
	sim.character["coins"] = 0
	check(not sim.buy_bait(1) and sim.count_item("fishing_bait") == 0, "Insufficient coins cannot create bait")
	sim.character["coins"] = 15
	sim.character["bag"] = {"logs": 28}
	check(not sim.buy_bait(5) and int(sim.character["coins"]) == 15, "Failed capacity check does not spend coins")
	sim.character["bag"] = {"logs": 27, "fishing_bait": 1}
	check(sim.buy_bait(5) and sim.bag_used() == 28 and sim.count_item("fishing_bait") == 6, "Purchases can extend an existing stack in a full backpack")
	sim.character["bag"]["fishing_bait"] = Catalog.MAX_ITEM_COUNT
	var coins_before: int = int(sim.character["coins"])
	check(not sim.buy_bait(1) and int(sim.character["coins"]) == coins_before, "Stack cap rejects purchase without charging")
	fresh()
	sim._add_item("fishing_bait", 10)
	visit("bank")
	check(sim.bank_transfer("fishing_bait", 10, true), "Bait can be deposited at the bank")
	check(sim.count_item("fishing_bait", true) == 10 and sim.count_item("fishing_bait") == 0, "Banking conserves bait quantity")
	check(not sim.request_interaction("fish_1"), "Banked bait cannot be used remotely for fishing")
	visit("bank")
	sim.character["bag"] = {"logs": 28}
	check(not sim.bank_transfer("fishing_bait", 10, false), "New bait stack withdrawal needs a free slot")
	check(sim.count_item("fishing_bait", true) == 10, "Failed withdrawal leaves bank bait unchanged")
	sim._remove_item("logs", 1)
	check(sim.bank_transfer("fishing_bait", 10, false), "Entire bait stack withdraws into one free slot")
	check(sim.bag_used() == 28 and sim.count_item("fishing_bait") == 10 and sim.count_item("fishing_bait", true) == 0, "Bait withdrawal preserves count and slot capacity")
	var data: Dictionary = sim.serialized_character()
	sim._restore_character(data)
	check(sim.count_item("fishing_bait") == 10 and sim.bag_used() == 28, "Reload preserves a full bag containing a bait stack")
	fresh()
	var legacy: Dictionary = sim.serialized_character()
	legacy["build"] = "0.1.1"
	legacy["coins"] = 42
	legacy["quest"]["started"] = true
	legacy["xp"]["Mining"] = 160
	sim._restore_character(legacy)
	check(sim.count_item("cooked_trout") == 3 and sim.count_item("fishing_bait") == 0, "Old profile with no bait loads without changing its items")
	check(int(sim.character["coins"]) == 42 and sim.skill_level("Mining") == 3 and bool(sim.character["quest"]["started"]), "Existing coin, skill and quest progress are retained")

func _test_shoreline() -> void:
	var banks: Array[Vector3] = [
		Vector3(12, 0, 9), Vector3(26, 0, 9), Vector3(19, 0, 3), Vector3(19, 0, 16),
		Vector3(12, 0, 3), Vector3(26, 0, 3), Vector3(12, 0, 16), Vector3(26, 0, 16),
		Vector3(11.8, 0, 11.2), Vector3(26.2, 0, 6.4), Vector3(15.4, 0, 2.8), Vector3(21.6, 0, 16.2)]
	for bank: Vector3 in banks:
		fresh()
		sim.character["pos"] = bank
		sim.character["bag"] = {"fishing_bait": 5}
		check(sim.request_interaction("fish_1", Vector3(19, 0, 9)), "Shoreline cast accepted at " + str(bank))
		check(sim.active_target == "fish_1" and sim.path.is_empty(), "Nearby bank needs no forced movement")
		var cast: Vector3 = sim.fishing_cast_position()
		check(Layout.is_pond_point(cast) and bank.distance_to(cast) <= Layout.FISHING_MAX_CAST, "Cast stays in nearby pond water")
		check(sim.facing.dot((cast - bank).normalized()) > 0.99, "Player faces the per-click cast point")
		advance(8.0)
		check(sim.position_of_player().is_equal_approx(bank), "Fishing retains exact bank coordinates")
		check(sim.count_item("raw_trout") == 1 and sim.count_item("fishing_bait") == 4, "Idle shoreline cast gives exactly one fish")
	var approaches: Array[Vector3] = [Vector3(0, 0, 8), Vector3(29, 0, 9), Vector3(19, 0, -5), Vector3(19, 0, 24)]
	for start: Vector3 in approaches:
		fresh()
		sim.character["pos"] = start
		sim.character["bag"] = {"fishing_bait": 5}
		var plan: Dictionary = sim.navigation.fishing_approach(start, Vector3(19, 0, 9))
		check(not plan.is_empty(), "Reachable shoreline found from " + str(start))
		if plan.is_empty():
			continue
		var stand: Vector3 = plan["stand_pos"]
		var route: PackedVector3Array = plan["path"]
		var dry: bool = not route.is_empty()
		for i: int in range(route.size()):
			dry = dry and sim.navigation.clear_position(route[i])
			if i > 0:
				for j: int in range(1, 10):
					dry = dry and not Layout.POND.grow(Layout.NAV_CLEARANCE).has_point(Vector2(route[i - 1].lerp(route[i], float(j) / 10.0).x, route[i - 1].lerp(route[i], float(j) / 10.0).z))
		check(dry and sim.navigation.can_fish_from(stand), "Approach route stays on dry land")
		if start.x > Layout.POND.end.x:
			check(stand.x > Layout.POND.end.x, "East approach uses the east bank, not the bucket")
		elif start.z < Layout.POND.position.y:
			check(stand.z < Layout.POND.position.y, "North approach uses the north bank")
		elif start.z > Layout.POND.end.y:
			check(stand.z > Layout.POND.end.y, "South approach uses the south bank")
		check(sim.request_interaction("fish_1"), "Far pond click is accepted as one pending action")
		advance(30.0)
		check(sim.count_item("raw_trout") == 1 and sim.active_target.is_empty() and sim.pending_target.is_empty(), "Walking to the bank authorizes only one catch")
	fresh()
	sim.character["bag"] = {"fishing_bait": 5}
	for invalid: Variant in [Vector3(INF, 0, 8), Vector3(NAN, 0, 8), Vector3(0, 0, 8), Vector3(19, 50, 8), "pond", 42]:
		check(not sim.dispatch("interact", {"id": "fish_1", "water_pos": invalid}), "Invalid pond intent rejected: " + str(invalid))
	check(sim.active_target.is_empty() and sim.pending_target.is_empty(), "Invalid casts never queue a reward")
	# Restore the edited navigation cells after this isolated no-route check.
	for x: int in range(-Layout.LIMIT, Layout.LIMIT + 1):
		for z: int in range(-Layout.LIMIT, Layout.LIMIT + 1):
			if sim.navigation.can_fish_from(Vector3(x, 0, z)):
				sim.navigation.grid.set_point_solid(Vector2i(x, z), true)
	check(not sim.request_interaction("fish_1"), "No walkable bank fails instead of routing into water")
	check(sim.count_item("fishing_bait") == 5, "No-route failure preserves bait")
	sim.navigation.build()

func _test_manual_actions() -> void:
	for id: String in ["pine_1", "oak_1", "copper_1", "tin_1", "iron_1", "fish_1"]:
		fresh()
		for skill: String in Catalog.SKILLS:
			sim.character["xp"][skill] = 160
		sim.character["bag"] = {"fishing_bait": 5}
		var target: Dictionary = sim.definitions[id]
		var item: String = str(target["item"])
		var skill_name: String = str(target["skill"])
		visit(id)
		advance(0.4)
		var elapsed: float = sim.action_time
		for _i: int in range(20):
			check(not sim.request_interaction(id), "Busy click rejected for " + id)
		check(is_equal_approx(sim.action_time, elapsed), "Busy clicks do not restart the action timer")
		check(not sim.request_interaction("slime_1"), "Clicking another target cannot buffer a second action")
		advance(30.0)
		check(sim.count_item(item) == 1, "No unattended repeat for " + id)
		check(int(sim.character["xp"][skill_name]) == 160 + int(target["xp"]), "Exactly one XP award for " + id)
		check(sim.active_target.is_empty() and sim.pending_target.is_empty(), "No action remains queued for " + id)
		sim._finish_harvest(id)
		check(sim.count_item(item) == 1, "Duplicate harvest completion cannot award another item")
		visit(id)
		advance(0.4)
		sim.cancel_action(false)
		advance(10.0)
		check(sim.count_item(item) == 1, "Canceled action cannot finish later")
		visit(id)
		advance(float(target["duration"]) + 0.2)
		check(sim.count_item(item) == 2, "Fresh post-completion click produces exactly the next item")
	fresh()
	sim.character["bag"] = {"raw_trout": 3}
	visit("campfire")
	check(sim.craft("cook_trout"), "One cooking click accepted")
	advance(30.0)
	check(sim.count_item("raw_trout") == 2 and sim.count_item("cooked_trout") == 1, "Cooking does not repeat on remaining ingredients")
	fresh()
	sim.character["bag"] = {"copper_ore": 3, "tin_ore": 3}
	visit("forge")
	check(sim.craft("smelt_bronze"), "One smithing click accepted")
	advance(30.0)
	check(sim.count_item("bronze_bar") == 1 and sim.count_item("copper_ore") == 2, "Smithing does not repeat on remaining ingredients")
	fresh()
	sim.character["bag"] = {"fishing_bait": 4}
	visit("fish_1")
	advance(0.3)
	var saved: Dictionary = sim.serialized_character()
	fresh()
	sim._restore_character(saved)
	advance(30.0)
	check(sim.count_item("raw_trout") == 0 and sim.count_item("fishing_bait") == 4, "Saving mid-action never saves an automatic future reward")

func _test_crafting() -> void:
	fresh()
	sim._add_item("copper_ore", 3)
	sim._add_item("tin_ore", 3)
	check(not sim.craft("smelt_bronze"), "Crafting away from station is rejected")
	check(sim.count_item("copper_ore") == 3, "Rejected craft preserves ingredients")
	visit("forge")
	for _i: int in range(3):
		check(sim.craft("smelt_bronze"), "Smelt a bronze bar from copper and tin")
	check(sim.count_item("bronze_bar") == 3, "Three smelts produce three bars")
	check(sim.count_item("copper_ore") == 0 and sim.count_item("tin_ore") == 0, "Smelting consumes both ore types")
	check(sim.craft("forge_bronze"), "Three bars forge a bronze sword")
	check(sim.count_item("bronze_bar") == 0 and sim.count_item("bronze_sword") == 1, "Sword recipe is transactional")
	check(not sim.craft("forge_bronze"), "No second sword without ingredients")
	var used: int = sim.bag_used()
	check(sim.equip_weapon("bronze_sword"), "Owned weapon can be equipped")
	check(str(sim.character["weapon"]) == "bronze_sword", "Equipped weapon updates")
	check(sim.count_item("wood_sword") == 1 and sim.bag_used() == used, "Swapped-out weapon returns without adding inventory units")
	check(not sim.equip_weapon("iron_sword"), "Unowned weapon cannot be equipped")
	fresh()
	sim._add_item("raw_trout", 1)
	visit("campfire")
	check(sim.craft("cook_trout"), "Campfire cooks raw trout")
	check(sim.count_item("raw_trout") == 0 and sim.count_item("cooked_trout") == 4, "Cooking consumes raw fish and grants cooked fish")

func _test_bank_and_shop() -> void:
	fresh()
	sim._add_item("logs", 5)
	check(not sim.bank_transfer("logs", 1, true), "Remote bank access rejected")
	visit("bank")
	check(not sim.bank_transfer("logs", -5, true), "Negative bank deposit rejected")
	check(sim.bank_transfer("logs", 5, true), "Deposit moves owned resources to storage")
	check(sim.count_item("logs") == 0 and sim.count_item("logs", true) == 5, "Deposit conserves item count")
	check(sim.bank_transfer("logs", 5, false), "Withdraw returns stored resources")
	check(not sim.bank_transfer("logs", 1, false), "Repeated withdrawal cannot duplicate items")
	sim.bank_transfer("logs", 5, true)
	sim._add_item("tin_ore", 25)
	check(not sim.bank_transfer("logs", 5, false), "Withdrawal respects backpack capacity")
	check(sim.count_item("logs", true) == 5, "Failed withdrawal preserves bank items")
	check(sim.deposit_all(), "Deposit-all operates at the bank")
	check(sim.bag_used() == 0 and str(sim.character["weapon"]) == "wood_sword", "Deposit-all does not remove equipped weapon")
	fresh()
	sim._add_item("logs", 4)
	var coins: int = int(sim.character["coins"])
	check(not sim.sell_item("logs", 1), "Remote selling rejected")
	visit("market")
	check(not sim.sell_item("logs", -1), "Negative sale rejected")
	check(sim.sell_item("logs", 4), "Provisioner buys owned supplies")
	check(int(sim.character["coins"]) == coins + 8 and sim.count_item("logs") == 0, "Sale credits exact amount and removes supplies")
	check(not sim.sell_item("logs", 1), "Repeated sale cannot mint coins")
	check(sim.buy_food(), "Food purchase succeeds with gold and capacity")
	check(int(sim.character["coins"]) == coins and sim.count_item("cooked_trout") == 4, "Food purchase debits exactly 8 coins")

func _test_food_and_combat() -> void:
	fresh()
	check(not sim.eat_food(), "Food is not consumed at full health")
	sim.character["hp"] = 20
	check(sim.eat_food(), "Food heals an injured player")
	check(int(sim.character["hp"]) == 30 and sim.count_item("cooked_trout") == 2, "Healing is capped and consumes one fish")
	sim.character["hp"] = 20
	check(not sim.eat_food(), "Eating cooldown prevents repeated instant consumption")
	advance(1.2)
	check(sim.eat_food(), "Eating becomes available after cooldown")
	fresh()
	var coins: int = int(sim.character["coins"])
	visit("slime_1")
	advance(1.1)
	check(int(sim.world["slime_1"]["hp"]) == 15 and sim.active_target.is_empty(), "One combat click makes one 3-damage attack")
	advance(6.0)
	check(int(sim.world["slime_1"]["hp"]) == 15, "Idle player never automatically attacks or counterattacks")
	check(int(sim.character["hp"]) < 30 and bool(sim.world["slime_1"]["aggro"]), "Provoked enemy still retaliates between manual swings")
	check(int(sim.character["coins"]) == coins and int(sim.character["xp"]["Combat"]) == 0, "Idle combat grants no kill loot or Combat XP")
	var timer_before: float = float(sim.world["slime_1"]["attack_time"])
	sim.cancel_action(false)
	check(is_equal_approx(float(sim.world["slime_1"]["attack_time"]), timer_before), "Cancel cannot reset enemy retaliation timer")
	for _i: int in range(5):
		visit("slime_1")
		check(not sim.request_interaction("slime_1"), "Attack spam does not queue or reset a swing")
		advance(1.1)
	check(not bool(sim.world["slime_1"]["alive"]), "Six manual attacks defeat a mossling")
	check(int(sim.character["coins"]) == coins + 6, "Defeat grants exact coin reward")
	check(sim.count_item("slime_gel") == 1 and int(sim.character["xp"]["Combat"]) == 26, "Defeat grants one gel and expected combat XP")
	sim._hit_enemy("slime_1")
	check(not sim.request_interaction("slime_1"), "Dead enemy rejects a queued attack")
	advance(1.0)
	check(int(sim.character["coins"]) == coins + 6, "Dead enemy and duplicate completion cannot grant extra rewards")
	advance(15.0)
	check(bool(sim.world["slime_1"]["alive"]) and int(sim.world["slime_1"]["hp"]) == 18, "Enemy respawns at full health")
	check(sim.active_target.is_empty() and int(sim.character["coins"]) == coins + 6, "Enemy respawn does not restart attacks or reward farming")
	fresh()
	visit("slime_1")
	advance(1.1)
	sim.request_move(Layout.SPAWN)
	advance(20.0)
	check(not bool(sim.world["slime_1"]["aggro"]), "Retreating beyond pursuit range disengages enemy retaliation")
	check(int(sim.world["slime_1"]["hp"]) == 18, "Disengaged enemy eventually recovers")
	check(sim.active_target.is_empty() and int(sim.character["xp"]["Combat"]) == 0, "Retreat never resumes an attack")
	fresh()
	sim.character["hp"] = 1
	sim.character["coins"] = 4
	visit("slime_2")
	advance(2.8)
	check(sim.position_of_player().is_equal_approx(Layout.SPAWN), "Death returns player to safe spawn")
	check(int(sim.character["coins"]) == 0, "Death penalty never creates negative gold")
	check(int(sim.character["hp"]) == sim.max_hp() and sim.bag_used() == 3, "Death restores health and preserves inventory")

func _test_quest() -> void:
	fresh()
	check(not sim.talk_quest(), "Quest acceptance requires the guide")
	visit("guide")
	check(sim.talk_quest(), "Quest can be accepted")
	check(bool(sim.character["quest"]["started"]), "Quest state is stored")
	check(not sim.quest_ready(), "Incomplete quest is not reward-ready")
	var coins: int = int(sim.character["coins"])
	sim.talk_quest()
	check(int(sim.character["coins"]) == coins, "Incomplete quest cannot grant a reward")
	for key: String in Catalog.QUEST_GOALS:
		for _i: int in range(int(Catalog.QUEST_GOALS[key]) + 2):
			sim._quest_progress(key)
		check(int(sim.character["quest"][key]) == int(Catalog.QUEST_GOALS[key]), "Quest milestone clamps: " + key)
	check(sim.quest_ready(), "All milestones unlock quest turn-in")
	check(sim.talk_quest(), "Quest reward can be claimed at the guide")
	check(int(sim.character["coins"]) == coins + 75, "Quest grants 75 coins")
	for skill: String in Catalog.SKILLS:
		check(int(sim.character["xp"][skill]) == 40, "Quest grants 40 XP: " + skill)
	sim.talk_quest()
	check(int(sim.character["coins"]) == coins + 75 and not sim.quest_ready(), "Quest reward cannot be claimed twice")

func _test_profiles() -> void:
	fresh()
	sim._add_item("fishing_bait", 10)
	var name: String = "run_%d" % Time.get_ticks_msec()
	var path: String = "user://test_profiles/" + name + ".json"
	var first: Dictionary = sim.serialized_character()
	check(Saves.write_file(path, first) == OK, "Save writes a versioned profile in isolated test directory")
	var loaded: Dictionary = Saves.read_file(path)
	check(bool(loaded.get("ok", false)), "Saved profile parses")
	var second: Dictionary = first.duplicate(true)
	second["coins"] = 77
	check(Saves.write_file(path, second) == OK, "Subsequent save rotates the previous file")
	loaded = Saves.read_file(path)
	check(int(loaded.get("data", {}).get("coins", -1)) == 77, "Current save contains new state")
	var backup: Dictionary = Saves.read_file(path + ".bak")
	check(int(backup.get("data", {}).get("coins", -1)) == 15, "Backup contains previous state")
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string("{broken json")
		file.close()
	check(not bool(Saves.read_file(path).get("ok", false)), "Corrupt profile is rejected")
	loaded = Saves.load_file(path)
	check(bool(loaded.get("ok", false)) and bool(loaded.get("recovered", false)), "Corrupt primary recovers valid backup")
	check(Saves.write_file(path, second) == OK, "Recovered state can be saved while quarantining bad file")
	backup = Saves.read_file(path + ".bak")
	check(bool(backup.get("ok", false)), "Recovery does not overwrite a valid backup with corrupt data")
	sim._restore_character(second)
	check(int(sim.character["coins"]) == 77 and sim.count_item("cooked_trout") == 3, "Character state survives serialization round-trip")
	check(sim.count_item("fishing_bait") == 10 and sim.bag_used() == 4, "Saved bait stack survives file round-trip in one slot")
	var invalid: Dictionary = {"coins": -1, "bag": {"logs": 1000, "not_real": 50}, "xp": {"Mining": []}, "pos": [9999, 0, 9999], "weapon": "not_real"}
	sim._restore_character(invalid)
	check(sim.bag_used() <= 28 and sim.count_item("not_real") == 0, "Profile validation clamps inventory and removes unknown items")
	check(int(sim.character["coins"]) == 0 and sim.skill_level("Mining") == 1, "Invalid numeric profile fields are safely bounded")
	check(str(sim.character["weapon"]) == "wood_sword", "Invalid saved weapon falls back to starter gear")
	var cell: Vector2i = Vector2i(roundi(sim.position_of_player().x), roundi(sim.position_of_player().z))
	check(sim.navigation.walkable(cell), "Out-of-bounds saved position recovers to navigable ground")
	var directory: DirAccess = DirAccess.open("user://test_profiles")
	if directory != null:
		for filename: String in directory.get_files():
			if filename.begins_with(name + ".json"):
				directory.remove(filename)
