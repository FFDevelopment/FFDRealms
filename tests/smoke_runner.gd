extends SceneTree
## Scene/UI initialization check with an outer frame limit, even if a child errors.
## Run headless. This does not verify rendered appearance or frame rate.
const AI = preload("res://scripts/enemy_ai.gd")
var checks_failed: int = 0

func _initialize() -> void:
	Engine.max_fps = 60
	call_deferred("_run")

func _run() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	if packed == null:
		push_error("SMOKE FAIL: main scene could not load")
		quit(1)
		return
	var scene: Node = packed.instantiate()
	root.add_child(scene)
	for _i: int in range(10):
		await process_frame
	var world: Node = scene.get_node_or_null("Hearthmere")
	var actor: Node = scene.get_node_or_null("PlayerVisual")
	var camera: Node = scene.get_node_or_null("AdventureCamera")
	var hud: Node = scene.get_node_or_null("AdventureHUD")
	_check(world != null, "World node exists")
	_check(actor != null, "Player visual exists")
	_check(camera is Camera3D, "Production camera exists")
	_check(hud != null, "HUD exists")
	if world != null:
		var targets: Variant = world.get("targets")
		_check(targets is Dictionary and targets.size() == Game.definitions.size() and targets.size() == 36, "All 36 interactive targets have visuals")
	if hud != null:
		_check(str(hud.get("modal_kind")) == "menu", "Startup menu is shown")
		Game.autosave_enabled = false
		Game.begin_game(1, "Smoke Test", true)
		hud.resume_game()
		hud.select_tab("skills")
		await process_frame
		hud.select_tab("journal")
		await process_frame
		hud.select_tab("bag")
		hud.show_map()
		await process_frame
		_check(str(hud.get("modal_kind")) == "map", "Map panel opens")
		hud.close_modal()
		for kind: String in ["guide", "bank", "forge", "campfire", "market", "bait_shop", "ranger"]:
			hud._on_panel_requested(kind)
			await process_frame
			_check(str(hud.get("modal_kind")) == kind, "Service UI opens: " + kind)
			hud.close_modal()
	if hud != null and actor != null:
		var original_appearance: Dictionary = Game.character["appearance"].duplicate(true)
		hud.show_wardrobe()
		await process_frame
		_check(str(hud.get("modal_kind")) == "wardrobe", "Appearance panel opens in the village")
		var editor = hud.get("wardrobe_editor")
		if is_instance_valid(editor):
			editor._set_color(Color("8a395b"), "shirt_color")
			_check(Game.character["appearance"] == original_appearance, "Actual HUD edits remain draft-only")
		hud.close_modal()
		_check(Game.character["appearance"] == original_appearance, "Closing the wardrobe discards its preview")
		hud.show_wardrobe()
		await process_frame
		editor = hud.get("wardrobe_editor")
		if is_instance_valid(editor):
			editor._set_color(Color("8a395b"), "shirt_color")
			editor._set_option(1, "pants_style")
			editor._apply()
			scene._process(0.1)
			_check(str(hud.get("modal_kind")).is_empty(), "Saving appearance closes the panel")
			_check(Game.character["appearance"]["shirt_color"] == "8a395b" and Game.character["appearance"]["pants_style"] == "slacks", "HUD commits the requested individual cosmetics")
			_check(actor.slot_materials["shirt_color"].albedo_color == Color("8a395b"), "Main-scene player receives the saved dye")
			_check(actor.details["slacks"][0].visible, "Main-scene player receives the slacks style")
	if world != null:
		var environment_node: WorldEnvironment = world.get_node_or_null("DaylightEnvironment") as WorldEnvironment
		var sun: DirectionalLight3D = world.get_node_or_null("Daylight") as DirectionalLight3D
		_check(environment_node != null and environment_node.environment != null, "Daylight environment exists")
		if environment_node != null and environment_node.environment != null:
			_check(is_equal_approx(environment_node.environment.ambient_light_energy, 0.32), "Ambient uses reduced daylight value")
			_check(is_equal_approx(environment_node.environment.tonemap_exposure, 0.95), "Exposure uses reduced value")
		_check(sun != null, "Directional daylight exists")
		if sun != null:
			_check(is_equal_approx(sun.light_energy, 0.90) and sun.shadow_enabled, "Sun uses reduced energy while retaining shadows")
	if actor != null and hud != null:
		Game.automatic_ticks = false
		Game.cancel_action(false)
		Game.character["pos"] = Vector3(26, 0, 9)
		Game.character["bag"] = {"fishing_bait": 5}
		_check(Game.request_interaction("fish_1"), "Fishing starts from dry bank in real scene")
		scene._process(0.1)
		var line: MeshInstance3D = scene.get("fishing_line") as MeshInstance3D
		var bobber: MeshInstance3D = scene.get("fishing_float") as MeshInstance3D
		_check(line != null and line.visible, "Fishing line becomes visible")
		_check(bobber != null and bobber.visible, "Fishing float becomes visible")
		_check(str(actor.get("tool_key")) == "rod", "Character equips fishing rod")
		if bobber != null:
			var cast: Vector3 = Game.fishing_cast_position()
			_check(is_equal_approx(bobber.position.x, cast.x) and is_equal_approx(bobber.position.z, cast.z), "Float sits at the pond cast point")
		# Capture a real input event while busy, then handle it after completion.
		var click: InputEventMouseButton = InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = true
		click.position = Vector2(400, 300)
		scene._unhandled_input(click)
		_check(bool(scene.get("click_pending")) and not bool(scene.get("click_may_interact")), "Busy click captured as ineligible before next physics tick")
		scene.set("click_pending", false)
		for _i: int in range(25):
			Game.tick(0.1)
		scene._process(0.1)
		_check(Game.count_item("raw_trout") == 1 and Game.count_item("fishing_bait") == 4 and Game.active_target.is_empty(), "One actual-scene cast stops with four bait left")
		if line != null and bobber != null:
			_check(not line.visible and not bobber.visible, "Completed cast hides line and float automatically")
		for _i: int in range(100):
			Game.tick(0.1)
		_check(Game.count_item("raw_trout") == 1, "No further fish during idle frames")
		click.pressed = false
		scene._unhandled_input(click)
		_check(not bool(scene.get("click_pending")), "Mouse release does not start or queue an action")
		# Test all sides for per-cast line/float positions in the instantiated scene.
		for bank: Vector3 in [Vector3(12, 0, 9), Vector3(26, 0, 9), Vector3(19, 0, 3), Vector3(19, 0, 16)]:
			Game.cancel_action(false)
			Game.character["pos"] = bank
			_check(Game.request_interaction("fish_1"), "Real-scene shoreline cast: " + str(bank))
			scene._process(0.1)
			if bobber != null:
				_check(bobber.visible and bobber.position.distance_to(bank) <= 4.6, "Bobber stays near the selected bank")
			Game.cancel_action(false)
			scene._process(0.1)
			if line != null and bobber != null:
				_check(not line.visible and not bobber.visible, "Cancel hides line and float")
		Game.cancel_action(false)
		Game.character["pos"] = Vector3(-3, 0, -21)
		Game._reset_world()
		Game.world["slime_1"]["pos"] = Vector3(-3, 0, -23)
		_check(Game.request_interaction("slime_1"), "Real-scene enemy click starts one action")
		Game.character["pos"] = Vector3(-3, 0, -18)
		for _i: int in range(12):
			Game.tick(0.1)
		world._process(0.1)
		var entry: Dictionary = world.get("targets")["slime_1"]
		var enemy_root: Node3D = entry["root"]
		_check(enemy_root.position.is_equal_approx(preload("res://scripts/terrain.gd").grounded(Game.target_position("slime_1"))), "Enemy root and pick area follow the live simulation")
		AI.begin_windup(Game.definitions["slime_1"], Game.world["slime_1"], Game.position_of_player())
		world._process(0.1)
		var warning: MeshInstance3D = entry["warning"]
		_check(warning.visible, "Committed strike sector is visible during windup")
		var locked: Vector3 = Game.world["slime_1"]["strike_facing"]
		var warning_forward: Vector3 = -warning.basis.z
		_check(warning_forward.dot(locked) > 0.999 and warning.scale == Vector3.ONE, "Warning orientation matches the locked hit direction without size pulsing")
		var original_position: Vector3 = Game.position_of_player()
		var active_camera: Camera3D = camera as Camera3D
		var ground_screen: Vector2 = active_camera.unproject_position(original_position + Vector3(2, 0, 0))
		scene._handle_world_click(ground_screen, false, true)
		_check(not Game.path.is_empty() and Game.active_target.is_empty(), "Forced ground movement cancels a busy action rather than queuing an attack")
		Game.world["slime_1"]["alive"] = false
		world._process(0.1)
		var pick: Area3D = entry["pick"]
		_check(pick.collision_layer == 0 and not warning.visible, "Dead enemies lose click collision and strike sector")
		Game._reset_world()
		Game.character["pos"] = Vector3(0, 0, 8)
		Game.automatic_ticks = true
	for _i: int in range(120):
		await process_frame
	print("SMOKE RESULT: %d failed. Headless scene initialization only; no visual inspection." % checks_failed)
	quit(1 if checks_failed > 0 else 0)

func _check(condition: bool, description: String) -> void:
	if condition:
		print("SMOKE PASS: " + description)
	else:
		checks_failed += 1
		push_error("SMOKE FAIL: " + description)
