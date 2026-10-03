extends Node
## The local simulation owns movement, timers and item/XP/gold transactions.
## This prototype is SINGLE PLAYER. This is not an authenticated MMO server.
signal changed
signal message(text: String)
signal panel_requested(kind: String)
signal effect(at: Vector3, text: String, tint: Color)

const Catalog = preload("res://scripts/catalog.gd")
const Layout = preload("res://scripts/world_layout.gd")
const Navigation = preload("res://scripts/navigation.gd")
const Saves = preload("res://scripts/save_store.gd")
const EnemyAI = preload("res://scripts/enemy_ai.gd")
const Combat = preload("res://scripts/combat_rules.gd")
const Appearance = preload("res://scripts/appearance.gd")
const WALK_SPEED: float = 4.4
const REACH: float = 2.2

var navigation = Navigation.new()
var character: Dictionary = {}
var definitions: Dictionary = {}
var world: Dictionary = {}
var path: PackedVector3Array = PackedVector3Array()
var playing: bool = false
var autosave_enabled: bool = true
var automatic_ticks: bool = true
var profile_slot: int = 0
var pending_target: String = ""
var active_target: String = ""
var station_id: String = ""
var action_time: float = 0.0
var action_duration: float = 1.0
var _fishing_plan: Dictionary = {}
var _resolving_action: bool = false
var facing: Vector3 = Vector3(0, 0, -1)
var _autosave_time: float = 0.0
var _ui_time: float = 0.0
var _food_cooldown: float = 0.0
var _attack_cooldown: float = 0.0
var _pursuit_repath: float = 0.0
var _pursuit_time: float = 0.0
var _pursuit_goal: Vector3 = Vector3.ZERO

func _ready() -> void:
	navigation.build()
	_reset_world()
	character = _new_character("Adventurer")

func _new_character(player_name: String) -> Dictionary:
	var xp: Dictionary = {}
	for skill: String in Catalog.SKILLS:
		xp[skill] = 0
	var safe_name: String = player_name.replace("\n", " ").replace("\r", " ").strip_edges().substr(0, 16)
	if safe_name.is_empty():
		safe_name = "Adventurer"
	return {"name": safe_name, "pos": Layout.SPAWN, "hp": 30, "coins": 15,
		"bag": {"cooked_trout": 3}, "bank": {}, "weapon": "wood_sword", "xp": xp,
		"appearance": Appearance.defaults(),
		"quest": {"started": false, "claimed": false, "wood": 0, "ore": 0, "cooked": 0, "blade": 0, "slimes": 0},
		"frontier": {"started": false, "claimed": false, "wolves": 0, "coal": 0, "warden": 0}}

func _reset_world() -> void:
	definitions.clear()
	world.clear()
	for target: Dictionary in Layout.targets():
		var id: String = str(target["id"])
		definitions[id] = target
		world[id] = {"stock": int(target.get("stock", -1)), "cooldown": 0.0,
			"hp": int(target.get("hp", 0)), "alive": true, "heal_delay": 0.0,
			"aggro": false, "attack_time": 0.0}
		if str(target["kind"]) == "enemy":
			EnemyAI.reset(id, target, world[id], navigation)

func begin_game(slot: int, player_name: String, start_fresh: bool = false) -> bool:
	if slot < 1 or slot > 3:
		return false
	var loaded: Dictionary = {}
	if not start_fresh and Saves.exists(slot):
		loaded = Saves.load_profile(slot)
		if not bool(loaded.get("ok", false)):
			message.emit(str(loaded.get("error", "Profile could not be loaded.")))
			return false
	cancel_action(false)
	_reset_world()
	profile_slot = slot
	# Existing adventures always restore their saved character name. The name field is
	# consulted only when a slot is created or explicitly replaced.
	if bool(loaded.get("ok", false)):
		_restore_character(loaded["data"])
	else:
		character = _new_character(player_name)
	playing = true
	_autosave_time = 0.0
	_food_cooldown = 0.0
	_attack_cooldown = 0.0
	changed.emit()
	if bool(loaded.get("recovered", false)):
		message.emit("Recovered the backup profile; the damaged file will be preserved.")
	else:
		message.emit("Welcome to Hearthmere. Speak to Warden Elin at the town square.")
	if loaded.is_empty():
		save_game(false)
	return true

func position_of_player() -> Vector3:
	return character.get("pos", Layout.SPAWN)

func target_position(id: String) -> Vector3:
	if not definitions.has(id):
		return Vector3.ZERO
	return world[id].get("pos", definitions[id]["pos"])

func enemy_attackable(id: String) -> bool:
	return definitions.has(id) and str(definitions[id]["kind"]) == "enemy" and bool(world[id]["alive"]) and str(world[id]["state"]) != "return"

func skill_level(skill: String) -> int:
	return Catalog.level_for_xp(int(character.get("xp", {}).get(skill, 0)))

func max_hp() -> int:
	return 30 + (skill_level("Combat") - 1) * 2

func bag_used() -> int:
	return Catalog.inventory_slots(character.get("bag", {}))

func count_item(id: String, bank: bool = false) -> int:
	var inventory: Dictionary = character.get("bank" if bank else "bag", {})
	return int(inventory.get(id, 0))

func can_add_item(id: String, amount: int) -> bool:
	if not Catalog.ITEMS.has(id) or amount < 1 or amount > Catalog.MAX_ITEM_COUNT:
		return false
	if count_item(id) + amount > Catalog.MAX_ITEM_COUNT:
		return false
	var after: Dictionary = character["bag"].duplicate()
	after[id] = count_item(id) + amount
	return Catalog.inventory_slots(after) <= Catalog.BAG_CAPACITY

func _add_item(id: String, amount: int) -> bool:
	if not can_add_item(id, amount):
		return false
	character["bag"][id] = count_item(id) + amount
	return true

func _remove_item(id: String, amount: int) -> bool:
	if amount < 1 or count_item(id) < amount:
		return false
	var remaining: int = count_item(id) - amount
	if remaining == 0:
		character["bag"].erase(id)
	else:
		character["bag"][id] = remaining
	return true

func _award_xp(skill: String, amount: int) -> void:
	var before: int = skill_level(skill)
	character["xp"][skill] = int(character["xp"].get(skill, 0)) + amount
	if skill_level(skill) > before:
		message.emit("%s reached level %d!" % [skill, skill_level(skill)])
		effect.emit(position_of_player() + Vector3.UP * 2.5, "LEVEL %d" % skill_level(skill), Color("eed18d"))

func dispatch(verb: String, payload: Dictionary = {}) -> bool:
	# Future networking should transport intents to an authoritative simulation.
	# Never synchronize a client's inventory or trust client-supplied reward totals.
	if verb == "save":
		return save_game()
	if not playing:
		return false
	match verb:
		"move":
			if not payload.get("pos", null) is Vector3:
				return false
			return request_move(payload["pos"])
		"interact":
			return request_interaction(str(payload.get("id", "")), payload.get("water_pos", null))
		"cancel":
			cancel_action()
			return true
		"eat":
			return eat_food()
		"appearance":
			return update_appearance(payload.get("look", null))
		"equip":
			return equip_weapon(str(payload.get("id", "")))
		"recipe":
			return craft(str(payload.get("id", "")))
		"deposit":
			return bank_transfer(str(payload.get("id", "")), int(payload.get("amount", 1)), true)
		"withdraw":
			return bank_transfer(str(payload.get("id", "")), int(payload.get("amount", 1)), false)
		"deposit_all":
			return deposit_all()
		"sell":
			return sell_item(str(payload.get("id", "")), int(payload.get("amount", 1)))
		"buy_food":
			return buy_food()
		"buy_bait":
			var requested: Variant = payload.get("amount", 1)
			if not requested is int:
				return false
			return buy_bait(int(requested))
		"rest":
			return rest()
		"quest":
			return talk_quest()
		"frontier_quest":
			return talk_frontier()
	return false

func cancel_action(close_panel: bool = true) -> void:
	path.clear()
	pending_target = ""
	active_target = ""
	station_id = ""
	action_time = 0.0
	_fishing_plan.clear()
	_pursuit_time = 0.0
	_pursuit_repath = 0.0
	if close_panel:
		panel_requested.emit("")
	changed.emit()

func request_move(destination: Vector3) -> bool:
	if not Layout.in_bounds(destination):
		return false
	cancel_action()
	var here: Vector3 = position_of_player()
	var ground: Vector3 = Vector3(destination.x, 0, destination.z)
	if navigation.clear_position(ground) and navigation.segment_clear(here, ground):
		# A clear dodge click travels directly, without first walking back to a grid centre.
		path = PackedVector3Array([ground])
	else:
		path = navigation.route(here, ground)
		if path.size() > 1 and navigation.segment_clear(here, path[1]):
			path.remove_at(0)
	return not path.is_empty()

func _in_interaction_range(target: Dictionary, slack: float = 0.0) -> bool:
	if str(target["kind"]) == "fish":
		if _fishing_plan.is_empty():
			return false
		var here: Vector3 = position_of_player()
		var stand: Vector3 = _fishing_plan["stand_pos"]
		var cast: Vector3 = _fishing_plan["cast_pos"]
		return here.distance_to(stand) <= 0.18 + slack and navigation.can_fish_from(here) and Layout.is_pond_point(cast) and here.distance_to(cast) <= Layout.FISHING_MAX_CAST + 0.15
	var id: String = str(target["id"])
	var at: Vector3 = target_position(id)
	if position_of_player().distance_to(at) > REACH + slack:
		return false
	return str(target["kind"]) != "enemy" or (enemy_attackable(id) and not Layout.is_safe(position_of_player()) and not Layout.segment_crosses_safe(position_of_player(), at) and navigation.segment_clear(position_of_player(), at))

func fishing_cast_position() -> Vector3:
	return _fishing_plan.get("cast_pos", Vector3.ZERO)

func accepts_interaction_click() -> bool:
	return playing and active_target.is_empty() and not _resolving_action

func request_interaction(id: String, requested_water: Variant = null) -> bool:
	if not definitions.has(id):
		return false
	# Early clicks are rejected, not buffered and not used to restart the timer.
	if not accepts_interaction_click():
		message.emit("Finish this action, then click again. Extra clicks are not queued.")
		return false
	var target: Dictionary = definitions[id]
	if str(target["kind"]) == "enemy" and _attack_cooldown > 0.0:
		message.emit("Weapon recovering (%.1fs). Move now; click again when ready. No attack queued." % _attack_cooldown)
		return false
	if str(target["kind"]) == "enemy" and not enemy_attackable(id):
		message.emit("That enemy is dead or returning home. No attack started.")
		return false
	var water: Vector3 = target["pos"]
	if str(target["kind"]) == "fish" and requested_water != null:
		if not requested_water is Vector3:
			return false
		water = requested_water
		if not Layout.is_pond_point(water):
			return false
	cancel_action()
	if target.has("level") and skill_level(str(target["skill"])) < int(target["level"]):
		message.emit("Requires %s level %d." % [str(target["skill"]), int(target["level"])])
		return false
	if target.has("item"):
		var reason: String = _harvest_error(target)
		if not reason.is_empty():
			message.emit(reason)
			return false
	var status: Dictionary = world[id]
	if float(status["cooldown"]) > 0.0 or not bool(status["alive"]):
		message.emit("%s is unavailable. Click again after it returns." % str(target["name"]))
		return false
	if str(target["kind"]) == "fish":
		_fishing_plan = navigation.fishing_approach(position_of_player(), water)
		if _fishing_plan.is_empty():
			message.emit("There is no clear route to a dry fishing bank.")
			return false
		path = _fishing_plan["path"]
	else:
		path = navigation.route(position_of_player(), target_position(id), true, str(target["kind"]) == "enemy")
		_pursuit_goal = target_position(id)
	pending_target = id
	if _in_interaction_range(target):
		_begin_interaction()
		return true
	if path.is_empty():
		pending_target = ""
		_fishing_plan.clear()
		message.emit("There is no clear route to that target.")
		return false
	return true

func _begin_interaction() -> void:
	if pending_target.is_empty() or not definitions.has(pending_target):
		return
	var id: String = pending_target
	pending_target = ""
	path.clear()
	var target: Dictionary = definitions[id]
	if not _in_interaction_range(target, 0.05):
		_fishing_plan.clear()
		message.emit("Move closer to interact.")
		return
	var aim: Vector3 = fishing_cast_position() if str(target["kind"]) == "fish" else target_position(id)
	facing = (aim - position_of_player()).normalized()
	var status: Dictionary = world[id]
	if float(status["cooldown"]) > 0.0 or not bool(status["alive"]):
		_fishing_plan.clear()
		message.emit("%s will return in %d seconds." % [str(target["name"]), ceili(float(status["cooldown"]))])
		return
	if target.has("item"):
		var reason: String = _harvest_error(target)
		if not reason.is_empty():
			_fishing_plan.clear()
			message.emit(reason)
			return
		active_target = id
		action_duration = float(target["duration"])
		action_time = 0.0
	elif str(target["kind"]) == "enemy":
		if _attack_cooldown > 0.0:
			message.emit("Weapon is still recovering. Click again when ready.")
			return
		active_target = id
		action_duration = Combat.PLAYER_STRIKE_TIME
		action_time = 0.0
		# Separate from active_target: moving/canceling never bypasses attack cadence.
		_attack_cooldown = Combat.PLAYER_ATTACK_INTERVAL
		# Do not reset a provoked enemy's timer each time the player clicks/cancels.
		EnemyAI.provoke(status)
	else:
		station_id = id
		panel_requested.emit(str(target["kind"]))
	changed.emit()

func _physics_process(delta: float) -> void:
	if automatic_ticks:
		tick(delta)

func tick(delta: float) -> void:
	if not playing:
		return
	var step: float = clampf(delta, 0.0, 0.25)
	_food_cooldown = maxf(0.0, _food_cooldown - step)
	_attack_cooldown = maxf(0.0, _attack_cooldown - step)
	_update_world(step)
	_update_pursuit(step)
	_update_movement(step)
	_update_enemy_retaliation(step)
	_update_action(step)
	_autosave_time += step
	if autosave_enabled and _autosave_time >= 30.0:
		_autosave_time = 0.0
		save_game(false)
	_ui_time += step
	if _ui_time >= 0.12:
		_ui_time = 0.0
		changed.emit()

func _update_world(delta: float) -> void:
	for id: String in world:
		var status: Dictionary = world[id]
		if float(status["cooldown"]) > 0.0:
			status["cooldown"] = maxf(0.0, float(status["cooldown"]) - delta)
			if float(status["cooldown"]) <= 0.0:
				status["stock"] = int(definitions[id].get("stock", -1))
				status["alive"] = true
				status["hp"] = int(definitions[id].get("hp", 0))
				status["aggro"] = false
				status["attack_time"] = 0.0
				if str(definitions[id]["kind"]) == "enemy":
					EnemyAI.reset(id, definitions[id], status, navigation)

func _update_enemy_retaliation(delta: float) -> void:
	for id: String in world:
		if str(definitions[id]["kind"]) != "enemy":
			continue
		var was_aggro: bool = bool(world[id]["aggro"])
		var previous_strike: int = int(world[id]["strike_id"])
		var damage: int = EnemyAI.step(id, definitions[id], world[id], delta, position_of_player(), navigation, world)
		if not was_aggro and bool(world[id]["aggro"]):
			effect.emit(target_position(id) + Vector3.UP * 2.5, "!", Color("edbc77"))
			message.emit("%s spotted you! Watch the orange strike area and move before impact." % str(definitions[id]["name"]))
		if int(world[id]["strike_id"]) != previous_strike and str(world[id]["strike_result"]) == "miss":
			effect.emit(target_position(id) + Vector3.UP * 2.1, "MISSED", Color("a8d7cf"))
		if damage > 0 and not Layout.is_safe(position_of_player()) and not Layout.enemy_forbidden(target_position(id)):
			character["hp"] = int(character["hp"]) - damage
			effect.emit(position_of_player() + Vector3.UP * 2.2, "-%d" % damage, Color("ed9287"))
			if int(character["hp"]) <= 0:
				_respawn_player()
				return

func _update_pursuit(delta: float) -> void:
	# A distant click follows the moving target for THIS swing only, with a timeout.
	if pending_target.is_empty() or str(definitions[pending_target]["kind"]) != "enemy":
		return
	_pursuit_time += delta
	_pursuit_repath = maxf(0.0, _pursuit_repath - delta)
	if not enemy_attackable(pending_target) or _pursuit_time > 12.0:
		cancel_action()
		message.emit("Pursuit stopped. Choose another position and click again.")
		return
	var aim: Vector3 = target_position(pending_target)
	if _pursuit_repath <= 0.0 and (path.is_empty() or aim.distance_to(_pursuit_goal) > 0.65):
		path = navigation.route(position_of_player(), aim, true, true)
		if path.size() > 1 and navigation.segment_clear(position_of_player(), path[1]):
			path.remove_at(0)
		_pursuit_goal = aim
		_pursuit_repath = 0.30

func _update_movement(delta: float) -> void:
	var budget: float = WALK_SPEED * delta
	while not path.is_empty() and budget > 0.0:
		var here: Vector3 = position_of_player()
		var next: Vector3 = path[0]
		var distance: float = here.distance_to(next)
		if distance <= 0.015:
			character["pos"] = next
			path.remove_at(0)
			continue
		facing = (next - here).normalized()
		if distance <= budget:
			character["pos"] = next
			budget -= distance
			path.remove_at(0)
		else:
			character["pos"] = here.move_toward(next, budget)
			budget = 0.0
	if not pending_target.is_empty():
		var destination: Dictionary = definitions[pending_target]
		if _in_interaction_range(destination):
			_begin_interaction()
		elif path.is_empty() and str(destination["kind"]) != "enemy":
			pending_target = ""
			_fishing_plan.clear()
			message.emit("Cannot reach that target from here.")

func _update_action(delta: float) -> void:
	if active_target.is_empty():
		return
	var id: String = active_target
	var target: Dictionary = definitions[id]
	if not _in_interaction_range(target, 0.15):
		cancel_action()
		message.emit("Target moved out of reach or behind cover. Click again to approach.")
		return
	if str(target["kind"]) == "enemy":
		facing = (target_position(id) - position_of_player()).normalized()
	action_time += delta
	if action_time < action_duration:
		return
	# Consume one click once. There is deliberately no repeat timer or next action.
	_resolving_action = true
	if str(target["kind"]) == "enemy":
		_hit_enemy(id)
	else:
		_finish_harvest(id)
	_resolving_action = false
	changed.emit()

func _consume_action(id: String) -> bool:
	# Consume before emitting any rewards/signals. Duplicate completion calls do nothing.
	if active_target != id or action_time < action_duration:
		return false
	active_target = ""
	pending_target = ""
	action_time = 0.0
	_fishing_plan.clear()
	return true

func _harvest_bag(target: Dictionary) -> Dictionary:
	# Work on a copy so input consumption and output creation commit together.
	var after: Dictionary = character["bag"].duplicate()
	var bait: String = str(target.get("bait_item", ""))
	if not bait.is_empty():
		var remaining: int = int(after.get(bait, 0)) - 1
		if remaining > 0:
			after[bait] = remaining
		else:
			after.erase(bait)
	var item: String = str(target["item"])
	after[item] = int(after.get(item, 0)) + 1
	return after

func _harvest_error(target: Dictionary) -> String:
	var bait: String = str(target.get("bait_item", ""))
	if not bait.is_empty() and count_item(bait) < 1:
		return "You need fishing bait. Buy it from the bait bucket beside Stillwater Pond."
	if Catalog.inventory_slots(_harvest_bag(target)) > Catalog.BAG_CAPACITY:
		return "Backpack full. Bank or sell supplies before gathering. No bait was used."
	return ""

func _finish_harvest(id: String) -> void:
	if not _consume_action(id):
		return
	var target: Dictionary = definitions[id]
	var status: Dictionary = world[id]
	if int(status["stock"]) == 0 or float(status["cooldown"]) > 0.0:
		cancel_action()
		return
	var item: String = str(target["item"])
	var reason: String = _harvest_error(target)
	if not reason.is_empty():
		cancel_action()
		message.emit(reason)
		return
	# No awaits/signals between validation and commit; failed catches spend no bait.
	character["bag"] = _harvest_bag(target)
	_award_xp(str(target["skill"]), int(target["xp"]))
	if item == "logs":
		_quest_progress("wood")
	if str(target["skill"]) == "Mining":
		_quest_progress("ore")
	if item == "coal":
		_frontier_progress("coal")
	effect.emit(position_of_player() + Vector3.UP * 2.4, "+1 " + Catalog.item_name(item), Color("d4e4bf"))
	if int(status["stock"]) > 0:
		status["stock"] = int(status["stock"]) - 1
		if int(status["stock"]) == 0:
			status["cooldown"] = float(target["respawn"])
			cancel_action()
			message.emit("%s is depleted and will replenish." % str(target["name"]))
	if target.has("bait_item"):
		var next_error: String = _harvest_error(target)
		if not next_error.is_empty():
			cancel_action()
			message.emit("Out of bait. Buy more from the bait bucket." if count_item(str(target["bait_item"])) == 0 else "Backpack full. Fishing stopped; unused bait kept.")
	changed.emit()

func _hit_enemy(id: String) -> void:
	if not _consume_action(id):
		return
	var target: Dictionary = definitions[id]
	var status: Dictionary = world[id]
	if not enemy_attackable(id) or int(status["hp"]) <= 0 or not _in_interaction_range(target, 0.15):
		cancel_action()
		return
	var weapon: Dictionary = Catalog.ITEMS[str(character["weapon"])]
	var damage: int = int(weapon["damage"]) + int((skill_level("Combat") - 1) / 3)
	status["hp"] = maxi(0, int(status["hp"]) - damage)
	status["hit_flash"] = 0.22
	EnemyAI.provoke(status)
	effect.emit(target_position(id) + Vector3.UP * 1.8, "-%d" % damage, Color("f4d5a0"))
	if int(status["hp"]) == 0:
		# Death commits first; one clicked swing can award at most one kill.
		status["alive"] = false
		status["aggro"] = false
		status["attack_time"] = 0.0
		status["state"] = "dead"
		status["nav_path"] = PackedVector3Array()
		status["cooldown"] = float(target.get("respawn", 14.0))
		var coins: int = int(target.get("coins", 6))
		var xp: int = int(target.get("xp", 26))
		var drop: String = str(target.get("drop", "slime_gel"))
		character["coins"] = int(character["coins"]) + coins
		var received: bool = _add_item(drop, 1)
		_award_xp("Combat", xp)
		var species: String = str(target.get("species", "mossling"))
		if species == "mossling":
			_quest_progress("slimes")
		elif species == "wolf":
			_frontier_progress("wolves")
		elif species == "warden":
			_frontier_progress("warden")
		cancel_action()
		message.emit("%s defeated: +%d coins, +%d Combat XP%s" % [str(target["name"]), coins, xp,
			", +1 " + Catalog.item_name(drop) + "." if received else ". Backpack full; drop left behind."])
	changed.emit()

func _respawn_player() -> void:
	_attack_cooldown = 0.0
	for status: Dictionary in world.values():
		if status.has("state") and bool(status["alive"]):
			EnemyAI.disengage(status)
	var lost: int = mini(10, int(character["coins"]))
	character["coins"] = int(character["coins"]) - lost
	character["pos"] = Layout.SPAWN
	character["hp"] = max_hp()
	cancel_action()
	message.emit("You recovered in Hearthmere. Lost %d coins; equipment and items retained." % lost)
	changed.emit()

func _at_station(kind: String) -> bool:
	if station_id.is_empty() or not definitions.has(station_id):
		return false
	var target: Dictionary = definitions[station_id]
	var target_position: Vector3 = target["pos"]
	return str(target["kind"]) == kind and position_of_player().distance_to(target_position) <= REACH + 0.05 and path.is_empty()

func craft(recipe_id: String) -> bool:
	if not Catalog.RECIPES.has(recipe_id):
		return false
	var recipe: Dictionary = Catalog.RECIPES[recipe_id]
	if bool(recipe.get("requires_frontier", false)) and not bool(character["frontier"]["claimed"]):
		message.emit("Complete Beyond the Old Watch with Ranger Tamsin to learn steelworking.")
		return false
	if not _at_station(str(recipe["station"])):
		message.emit("Visit the appropriate crafting station first.")
		return false
	if skill_level(str(recipe["skill"])) < int(recipe["level"]):
		message.emit("Requires %s level %d." % [str(recipe["skill"]), int(recipe["level"])])
		return false
	var consumed: int = 0
	var cost: Dictionary = recipe["cost"]
	for id: String in cost:
		if count_item(id) < int(cost[id]):
			message.emit("Need: " + Catalog.recipe_cost_text(recipe))
			return false
		consumed += int(cost[id])
	if bag_used() - consumed + 1 > Catalog.BAG_CAPACITY:
		message.emit("Make space in your backpack first.")
		return false
	for id: String in cost:
		_remove_item(id, int(cost[id]))
	_add_item(str(recipe["output"]), 1)
	_award_xp(str(recipe["skill"]), int(recipe["xp"]))
	if recipe_id == "cook_trout":
		_quest_progress("cooked")
	if recipe_id == "forge_bronze":
		_quest_progress("blade")
	message.emit("Made " + Catalog.item_name(str(recipe["output"])) + ".")
	changed.emit()
	return true

func eat_food() -> bool:
	if int(character["hp"]) >= max_hp():
		message.emit("You are already at full health.")
		return false
	if _food_cooldown > 0.0:
		return false
	if not _remove_item("cooked_trout", 1):
		message.emit("No cooked trout. Catch trout at the pond and cook it at the campfire.")
		return false
	character["hp"] = mini(max_hp(), int(character["hp"]) + 12)
	_food_cooldown = 1.0
	message.emit("Ate cooked trout. Restored up to 12 health.")
	changed.emit()
	return true

func equip_weapon(id: String) -> bool:
	if not Catalog.ITEMS.has(id) or not Catalog.ITEMS[id].has("damage") or count_item(id) < 1:
		return false
	var old: String = str(character["weapon"])
	_remove_item(id, 1)
	_add_item(old, 1)
	character["weapon"] = id
	message.emit("Equipped " + Catalog.item_name(id) + ".")
	changed.emit()
	return true

func rest() -> bool:
	if not _at_station("campfire"):
		return false
	character["hp"] = max_hp()
	message.emit("Rested by the fire. Health restored.")
	changed.emit()
	return true

func bank_transfer(id: String, amount: int, deposit: bool) -> bool:
	if not _at_station("bank") or not Catalog.ITEMS.has(id) or amount < 1 or amount > 100000:
		return false
	if deposit:
		if not _remove_item(id, amount):
			return false
		character["bank"][id] = count_item(id, true) + amount
	else:
		if count_item(id, true) < amount:
			return false
		if not _add_item(id, amount):
			message.emit("Not enough backpack space for that withdrawal.")
			return false
		var remaining: int = count_item(id, true) - amount
		if remaining == 0:
			character["bank"].erase(id)
		else:
			character["bank"][id] = remaining
	changed.emit()
	return true

func deposit_all() -> bool:
	if not _at_station("bank"):
		return false
	var bag: Dictionary = character["bag"]
	for id: String in bag.keys():
		bank_transfer(id, count_item(id), true)
	message.emit("Backpack deposited. Equipped weapon and coins stay with you.")
	return true

func sell_item(id: String, amount: int) -> bool:
	if not _at_station("market") or not Catalog.ITEMS.has(id) or amount < 1:
		return false
	if not _remove_item(id, amount):
		return false
	var paid: int = int(Catalog.ITEMS[id]["sell"]) * amount
	character["coins"] = int(character["coins"]) + paid
	message.emit("Sold %d %s for %d coins." % [amount, Catalog.item_name(id), paid])
	changed.emit()
	return true

func buy_food() -> bool:
	if not _at_station("market"):
		return false
	if int(character["coins"]) < 8:
		message.emit("Cooked trout costs 8 coins.")
		return false
	if not _add_item("cooked_trout", 1):
		message.emit("Backpack full.")
		return false
	character["coins"] = int(character["coins"]) - 8
	changed.emit()
	return true

func buy_bait(amount: int = 1) -> bool:
	if not _at_station("bait_shop"):
		message.emit("Visit the bait bucket beside Stillwater Pond to buy bait.")
		return false
	if not amount in Catalog.BAIT_PACKS:
		return false
	var price: int = amount * Catalog.BAIT_PRICE
	if int(character["coins"]) < price:
		message.emit("You need %d coins for %d bait." % [price, amount])
		return false
	if not _add_item("fishing_bait", amount):
		message.emit("Make one backpack slot available for bait, or use your existing stack.")
		return false
	character["coins"] = int(character["coins"]) - price
	message.emit("Bought %d bait for %d coins. Click the pond to fish." % [amount, price])
	changed.emit()
	return true

func _quest_progress(key: String) -> void:
	var quest: Dictionary = character["quest"]
	if bool(quest["started"]) and not bool(quest["claimed"]):
		quest[key] = mini(int(Catalog.QUEST_GOALS[key]), int(quest.get(key, 0)) + 1)

func quest_ready() -> bool:
	var quest: Dictionary = character.get("quest", {})
	if not (quest.get("started", false) == true) or (quest.get("claimed", false) == true):
		return false
	for key: String in Catalog.QUEST_GOALS:
		if int(quest.get(key, 0)) < int(Catalog.QUEST_GOALS[key]):
			return false
	return true

func talk_quest() -> bool:
	if not _at_station("guide"):
		return false
	var quest: Dictionary = character["quest"]
	if not bool(quest["started"]):
		quest["started"] = true
		message.emit("Quest accepted: A Foothold in Hearthmere. Progress starts now; open Journal [J].")
	elif quest_ready():
		quest["claimed"] = true
		character["coins"] = int(character["coins"]) + 75
		for skill: String in Catalog.SKILLS:
			_award_xp(skill, 40)
		message.emit("Quest complete! +75 coins and +40 XP in every skill. Your supplies are yours to keep.")
	elif bool(quest["claimed"]):
		message.emit("Elin: Follow the north road through the old watch. Ranger Tamsin awaits at Northreach Camp. Bring an iron sword and food.")
	else:
		message.emit("Elin: Learn the trades, prepare your blade, then clear the old watch. Your Journal tracks each task.")
	changed.emit()
	return true

func _frontier_progress(key: String) -> void:
	var quest: Dictionary = character["frontier"]
	if Catalog.FRONTIER_GOALS.has(key) and bool(quest["started"]) and not bool(quest["claimed"]):
		quest[key] = mini(int(Catalog.FRONTIER_GOALS[key]), int(quest.get(key, 0)) + 1)

func frontier_ready() -> bool:
	var quest: Dictionary = character["frontier"]
	if not bool(quest["started"]) or bool(quest["claimed"]):
		return false
	for key: String in Catalog.FRONTIER_GOALS:
		if int(quest.get(key, 0)) < int(Catalog.FRONTIER_GOALS[key]):
			return false
	return true

func talk_frontier() -> bool:
	if not _at_station("ranger"):
		return false
	if not bool(character["quest"]["claimed"]):
		message.emit("Tamsin: Earn Elin's trust first. Complete A Foothold in Hearthmere, then return.")
		return false
	var quest: Dictionary = character["frontier"]
	if not bool(quest["started"]):
		quest["started"] = true
		message.emit("Accepted Beyond the Old Watch. Clear 3 wolves, mine 3 coal, and defeat the Watchwarden. Iron equipment and food recommended.")
	elif frontier_ready():
		quest["claimed"] = true
		character["coins"] = int(character["coins"]) + 110
		_award_xp("Combat", 100)
		_award_xp("Smithing", 80)
		message.emit("Northreach secured! +110 coins, +100 Combat XP, +80 Smithing XP. Steel recipes learned; Smithing 5 is also required.")
	else:
		message.emit("Tamsin: Steel recipes are yours. Train Smithing to level 5 and combine iron bars with coal." if bool(quest["claimed"]) else "Tamsin: Your Journal tracks the expedition. Retreat to camp to recover; enemies will return home.")
	changed.emit()
	return true

func action_label() -> String:
	if not pending_target.is_empty():
		return "Walking to bank - one cast on arrival" if str(definitions[pending_target]["kind"]) == "fish" else "Walking to " + str(definitions[pending_target]["name"])
	if not path.is_empty():
		return "Exploring " + Layout.region_name(position_of_player())
	if not active_target.is_empty():
		var target: Dictionary = definitions[active_target]
		if str(target["kind"]) == "enemy":
			return "One attack | Enemy HP %d/%d | Click again when ready" % [int(world[active_target]["hp"]), int(target["hp"])]
		if str(target["kind"]) == "fish":
			return "One cast | Bait %d | Click again after the catch" % count_item("fishing_bait")
		return "%s - one action | Click again when ready" % str(target["skill"])
	if _attack_cooldown > 0.0:
		return "Weapon recovering %.1fs | Move out of the orange strike area | Click again when ready" % _attack_cooldown
	for id: String in world:
		if bool(world[id]["aggro"]):
			return "Weapon ready | Click once to strike, move to dodge | F to eat | Safe towns end pursuit"
	return "Ready - click for ONE action | Q / E rotate | Wheel zoom"

func update_appearance(source: Variant) -> bool:
	if not playing or profile_slot < 1 or not source is Dictionary:
		return false
	if not Layout.is_safe(position_of_player()):
		message.emit("Visit Hearthmere or Northreach Camp to change your appearance.")
		return false
	var look: Dictionary = Appearance.sanitize(source)
	# Persist the proposed snapshot BEFORE committing the new look. Failure keeps the old look.
	if autosave_enabled:
		var snapshot: Dictionary = serialized_character()
		snapshot["appearance"] = look
		var error: Error = Saves.write_profile(profile_slot, snapshot)
		if error != OK:
			message.emit("Appearance was not saved (error %d). Your previous look is unchanged." % int(error))
			return false
	character["appearance"] = look
	changed.emit()
	message.emit("Appearance saved to this character." if autosave_enabled else "Appearance applied for this test; saving is disabled.")
	return true

func save_game(show_message: bool = true) -> bool:
	if profile_slot < 1 or not autosave_enabled:
		return false
	var error: Error = Saves.write_profile(profile_slot, serialized_character())
	if error != OK:
		message.emit("Save failed (error %d). Your previous profile has not been silently replaced." % int(error))
		return false
	if show_message:
		message.emit("Saved profile %d." % profile_slot)
	return true

func serialized_character() -> Dictionary:
	var data: Dictionary = character.duplicate(true)
	var pos: Vector3 = position_of_player()
	data["pos"] = [pos.x, pos.y, pos.z]
	data["build"] = Catalog.VERSION
	data["appearance"] = Appearance.sanitize(character.get("appearance", {}))
	return data

func _restore_character(data: Dictionary) -> void:
	character = _new_character(str(data.get("name", "Adventurer")))
	character["appearance"] = Appearance.sanitize(data.get("appearance", {}))
	var xp: Variant = data.get("xp", {})
	if xp is Dictionary:
		for skill: String in Catalog.SKILLS:
			character["xp"][skill] = _bounded_int(xp.get(skill, 0), 0, 100000000)
	character["coins"] = _bounded_int(data.get("coins", 0), 0, 10000000)
	character["hp"] = _bounded_int(data.get("hp", 30), 1, max_hp(), 30)
	var weapon: String = str(data.get("weapon", "wood_sword"))
	if Catalog.ITEMS.has(weapon) and Catalog.ITEMS[weapon].has("damage"):
		character["weapon"] = weapon
	character["bag"] = {}
	character["bank"] = {}
	for inventory_name: String in ["bag", "bank"]:
		var source: Variant = data.get(inventory_name, {})
		if not source is Dictionary:
			continue
		for id: String in source:
			if not Catalog.ITEMS.has(id):
				continue
			var amount: int = _bounded_int(source[id], 0, 100000)
			if inventory_name == "bag":
				if bool(Catalog.ITEMS[id].get("stackable", false)):
					if bag_used() >= Catalog.BAG_CAPACITY:
						amount = 0
				else:
					amount = mini(amount, Catalog.BAG_CAPACITY - bag_used())
			if amount > 0:
				character[inventory_name][id] = amount
	var quest: Variant = data.get("quest", {})
	if quest is Dictionary:
		character["quest"]["started"] = (quest.get("started", false) == true)
		character["quest"]["claimed"] = (quest.get("claimed", false) == true)
		for key: String in Catalog.QUEST_GOALS:
			character["quest"][key] = _bounded_int(quest.get(key, 0), 0, int(Catalog.QUEST_GOALS[key]))
	var frontier: Variant = data.get("frontier", {})
	if frontier is Dictionary:
		character["frontier"]["started"] = (frontier.get("started", false) == true)
		character["frontier"]["claimed"] = (frontier.get("claimed", false) == true)
		for key: String in Catalog.FRONTIER_GOALS:
			character["frontier"][key] = _bounded_int(frontier.get(key, 0), 0, int(Catalog.FRONTIER_GOALS[key]))
	var pos: Variant = data.get("pos", [])
	if pos is Array and pos.size() == 3 and (pos[0] is float or pos[0] is int) and (pos[2] is float or pos[2] is int):
		var point: Vector3 = Vector3(float(pos[0]), 0, float(pos[2]))
		if point.is_finite():
			var cell: Vector2i = navigation.nearest_cell(point)
			character["pos"] = Vector3(cell.x, 0, cell.y)

func _bounded_int(value: Variant, low: int, high: int, fallback: int = 0) -> int:
	if not (value is int or value is float):
		return clampi(fallback, low, high)
	if value is float and not is_finite(float(value)):
		return clampi(fallback, low, high)
	return clampi(int(value), low, high)
