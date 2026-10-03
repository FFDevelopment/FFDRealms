extends SceneTree
## Native appearance/safe-town regressions. Run Tests.bat includes this suite.
## Real profile slots are never read/written. File round-trips use user://test_profiles only.
const State = preload("res://scripts/game_state.gd")
const Appearance = preload("res://scripts/appearance.gd")
const Actor = preload("res://scripts/actor.gd")
const Wardrobe = preload("res://scripts/wardrobe.gd")
const Layout = preload("res://scripts/world_layout.gd")
const AI = preload("res://scripts/enemy_ai.gd")
const Saves = preload("res://scripts/save_store.gd")
var sim
var passed: int = 0
var failed: int = 0
var submitted: Dictionary = {}

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	sim = State.new()
	root.add_child(sim)
	sim.automatic_ticks = false
	sim.autosave_enabled = false
	_fresh()
	_test_validation()
	_test_cosmetic_commit()
	_test_materials()
	_test_preview()
	_test_save_roundtrip()
	_test_safe_geometry()
	_test_safe_routing()
	_test_combat_boundary()
	print("APPEARANCE/SAFETY RESULT: %d passed; %d failed." % [passed, failed])
	sim.free()
	quit(1 if failed > 0 else 0)

func _fresh() -> void:
	sim.cancel_action(false)
	sim._reset_world()
	sim.character = sim._new_character("Appearance Tester")
	sim._attack_cooldown = 0.0
	sim.profile_slot = 1
	sim.playing = true

func check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
		print("APPEARANCE/SAFETY PASS: " + label)
	else:
		failed += 1
		push_error("APPEARANCE/SAFETY FAIL: " + label)

func _test_validation() -> void:
	var first: Dictionary = Appearance.defaults()
	first["skin_color"] = "010203"
	check(Appearance.defaults()["skin_color"] != first["skin_color"], "Default dictionaries do not leak between characters")
	check(Appearance.sanitize(null) == Appearance.defaults(), "Null appearance gets defaults")
	check(Appearance.sanitize([1, 2]) == Appearance.defaults(), "Wrong outer type gets defaults")
	var data: Dictionary = Appearance.sanitize({"skin_color": "#ABCDEF", "hair_color": "ffffffff", "shirt_fabric": "../bad-fabric.gd", "pack_visible": "false", "coins": 999999, "pants_style": "slacks"})
	check(data["skin_color"] == "abcdef", "Hex colors normalize without losing independent channels")
	check(data["hair_color"] == Appearance.DEFAULTS["hair_color"], "Eight-digit/transparent color values rejected")
	check(data["shirt_fabric"] == "cotton" and data["pack_visible"] == true, "Unknown fabric and non-boolean visibility get safe defaults")
	check(data["pants_style"] == "slacks" and not data.has("coins"), "Style whitelist accepts slacks and drops unrelated fields")
	for key: String in Appearance.COLOR_LABELS:
		var candidate: Dictionary = Appearance.defaults()
		candidate[key] = "123abc"
		var cleaned: Dictionary = Appearance.sanitize(candidate)
		check(cleaned[key] == "123abc", "Independent dye channel: " + key)
		for other: String in Appearance.COLOR_LABELS:
			if other != key:
				check(cleaned[other] == Appearance.DEFAULTS[other], "Changing %s leaves %s alone" % [key, other])

func _test_cosmetic_commit() -> void:
	_fresh()
	var before: Dictionary = sim.character.duplicate(true)
	before.erase("appearance")
	var look: Dictionary = Appearance.defaults()
	look["pants_style"] = "slacks"
	look["skin_color"] = "815331"
	look["shirt_color"] = "ac314f"
	look["pack_visible"] = false
	look["coins"] = 9999999
	check(sim.dispatch("appearance", {"look": look}), "Appearance commits in a safe town")
	var after: Dictionary = sim.character.duplicate(true)
	after.erase("appearance")
	check(after == before, "Cosmetic commit leaves position, HP, money, items, weapon, XP and quests unchanged")
	check(sim.character["appearance"]["pants_style"] == "slacks" and not sim.character["appearance"]["pack_visible"], "Style and visibility persist in character data")
	check(not sim.dispatch("appearance", {"look": "bad"}), "Non-dictionary appearance intent rejected")
	sim.character["pos"] = Vector3(0, 0, -25)
	look["pants_style"] = "denim"
	check(not sim.update_appearance(look) and sim.character["appearance"]["pants_style"] == "slacks", "Cannot use wardrobe out in combat territory")
	sim.character["pos"] = Vector3(-14, 0, -33)
	check(sim.update_appearance(look), "Northreach Camp also permits customization")

func _test_materials() -> void:
	var actor = Actor.new()
	var npc = Actor.new()
	root.add_child(actor)
	root.add_child(npc)
	actor.build_actor("Player")
	npc.build_actor("NPC", Color("9a723c"), false)
	var npc_color: Color = npc.slot_materials["shirt_color"].albedo_color
	var look: Dictionary = Appearance.defaults()
	look["shirt_color"] = "ab314f"
	look["pants_color"] = "20375e"
	look["pants_style"] = "denim"
	actor.apply_appearance(look)
	check(actor.slot_materials["shirt_color"] != npc.slot_materials["shirt_color"], "Actors own their mutable dye materials")
	check(npc.slot_materials["shirt_color"].albedo_color == npc_color, "Recoloring the player does not recolor NPCs")
	check(actor.slot_materials["pants_color"].albedo_color == Color("20375e"), "Trousers retain their own dye")
	check(actor.details["denim"][0].visible and not actor.details["slacks"][0].visible, "Jeans display pockets/stitching rather than a trouser crease")
	var jeans_texture: Texture2D = actor.slot_materials["pants_color"].albedo_texture
	look["pants_style"] = "slacks"
	look["shoe_style"] = "shoes"
	look["hair_style"] = "bald"
	look["pack_visible"] = false
	actor.apply_appearance(look)
	check(actor.details["slacks"][0].visible and not actor.details["denim"][0].visible, "Slacks display a crease rather than jeans details")
	check(actor.slot_materials["pants_color"].albedo_texture != jeans_texture, "Jeans and slacks use different actual texture maps")
	check(actor.slot_materials["pants_color"].albedo_color == Color("20375e"), "Changing fabric does not reset dye")
	check(actor.details["shoes"][0].visible and not actor.details["boots"][0].visible, "Low shoes and boots switch separately")
	check(not actor.details["short"][0].visible and not actor.details["swept"][0].visible, "Bald option hides only hair")
	check(not actor.details["pack"][0].visible and actor.tool_key == "wood_sword", "Hide backpack leaves the equipped weapon unchanged")
	for fabric: String in ["cotton", "linen", "knit", "denim", "slacks", "canvas", "leather", "suede"]:
		var texture: Texture2D = Appearance.fabric_texture(fabric)
		var image: Image = texture.get_image()
		check(image.get_width() == 128 and image.get_height() == 128, "Generated fabric map size: " + fabric)
		check(image.get_pixel(0, 0).a == 1.0, "Fabric is opaque: " + fabric)
		check(texture == Appearance.fabric_texture(fabric), "Texture cache is reused: " + fabric)
	actor.free()
	npc.free()

func _on_apply(look: Dictionary) -> void:
	submitted = look.duplicate(true)

func _test_preview() -> void:
	_fresh()
	var editor = Wardrobe.new()
	root.add_child(editor)
	editor.build(sim.character["appearance"])
	editor.apply_requested.connect(_on_apply)
	var committed: Dictionary = sim.character["appearance"].duplicate(true)
	editor._set_color(Color("a03020"), "shirt_color")
	editor._set_option(1, "pants_style")
	check(sim.character["appearance"] == committed, "Preview edits do not mutate saved/runtime character data")
	check(editor.draft["pants_style"] == "slacks", "Option change updates the draft")
	check(editor.color_controls.size() == 9 and editor.option_controls.size() == 5, "All individual color and style controls are constructed")
	check(editor.preview_viewport.own_world_3d and editor.preview_viewport.size.x > 0, "3D preview has a separate nonzero-sized world")
	var angle: float = editor.preview_actor.rotation.y
	editor._rotate(PI / 4.0)
	check(not is_equal_approx(angle, editor.preview_actor.rotation.y), "Preview can rotate")
	editor._apply()
	check(submitted["shirt_color"] == "a03020" and submitted["pants_style"] == "slacks", "Save emits the current validated draft")
	editor.reset_draft()
	check(editor.draft == Appearance.defaults(), "Reset affects the draft only")
	check(sim.character["appearance"] == committed, "Reset/discard does not change the character")
	editor.free()

func _test_save_roundtrip() -> void:
	_fresh()
	var legacy: Dictionary = sim.serialized_character()
	legacy.erase("appearance")
	legacy["coins"] = 123
	legacy["weapon"] = "iron_sword"
	sim._restore_character(legacy)
	check(sim.character["appearance"] == Appearance.defaults() and sim.character["coins"] == 123 and sim.character["weapon"] == "iron_sword", "Legacy profile adds appearance without wiping progress")
	var look: Dictionary = Appearance.defaults()
	look["skin_color"] = "6b4030"
	look["shirt_fabric"] = "linen"
	look["pants_style"] = "slacks"
	look["pants_color"] = "5a554b"
	sim.update_appearance(look)
	var path: String = "user://test_profiles/appearance_roundtrip.json"
	check(Saves.write_file(path, sim.serialized_character()) == OK, "Appearance writes to isolated test file")
	var restored: Dictionary = Saves.read_file(path)
	check(bool(restored.get("ok", false)), "Appearance test file parses")
	if bool(restored.get("ok", false)):
		sim._restore_character(restored["data"])
		check(sim.character["appearance"] == Appearance.sanitize(look), "All colors and styles survive JSON reload")
		check(sim.character["coins"] == 123 and sim.character["weapon"] == "iron_sword", "Cosmetic save preserves money and equipment")
	for suffix: String in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))

func _test_safe_geometry() -> void:
	for area: Rect2 in Layout.SAFE_AREAS:
		for point: Vector2 in [area.position, Vector2(area.end.x, area.position.y), area.end, Vector2(area.position.x, area.end.y), area.get_center()]:
			var at: Vector3 = Vector3(point.x, 0, point.y)
			check(Layout.is_safe(at), "Town edges/corners count as safe: " + str(at))
			check(not sim.navigation.enemy_clear_position(at), "Enemies cannot occupy a town edge/corner: " + str(at))
		var a: Vector3 = Vector3(area.position.x - 3, 0, area.get_center().y)
		var b: Vector3 = Vector3(area.end.x + 3, 0, area.get_center().y)
		check(Layout.segment_crosses_safe(a, b), "Outside-to-outside crossing detects protected town")
	check(sim.navigation.clear_position(Layout.SPAWN) and not sim.navigation.enemy_clear_position(Layout.SPAWN), "Player town navigation is not blocked by enemy-only grid")
	check(not Layout.segment_crosses_safe(Vector3(0, 0, -23), Vector3(0, 0, -25)), "Ordinary wilderness combat segment remains valid")
	check(Layout.enemy_forbidden(Vector3.INF), "Non-finite enemy positions fail closed")

func _test_safe_routing() -> void:
	_fresh()
	for id: String in sim.definitions:
		if str(sim.definitions[id]["kind"]) == "enemy":
			check(sim.navigation.enemy_clear_position(sim.target_position(id)), "Spawn outside enemy exclusion buffer: " + id)
	var from: Vector3 = Vector3(-17, 0, -27)
	var destination: Vector3 = Vector3(-16, 0, -47)
	var route: PackedVector3Array = sim.navigation.enemy_route(from, destination)
	check(not route.is_empty(), "Enemy return route exists around Northreach Camp")
	var previous: Vector3 = from
	var clear: bool = not route.is_empty()
	for point: Vector3 in route:
		clear = clear and sim.navigation.enemy_segment_clear(previous, point)
		previous = point
	check(clear and Layout.segment_crosses_safe(from, destination), "Route detours around town rather than taking direct shortcut")
	var definition: Dictionary = sim.definitions["wolf_1"].duplicate(true)
	var status: Dictionary = sim.world["wolf_1"]
	AI.reset("wolf_1", definition, status, sim.navigation)
	status["pos"] = from
	status["hp"] = 10
	AI.disengage(status)
	clear = true
	for _i: int in range(800):
		previous = status["pos"]
		AI.step("wolf_1", definition, status, 0.1, Layout.SPAWN, sim.navigation, {})
		clear = clear and not Layout.enemy_forbidden(status["pos"]) and sim.navigation.enemy_segment_clear(previous, status["pos"])
		if str(status["state"]) == "idle":
			break
	check(clear and str(status["state"]) == "idle", "Existing return-home behavior completes without entering camp")
	check(int(status["hp"]) == int(definition["hp"]), "Normal arrival still restores full enemy HP")
	status["pos"] = Vector3(-4, 0, -36)
	status["nav_path"] = PackedVector3Array([Vector3(-14, 0, -36)])
	AI._move("wolf_1", status, 100.0, sim.navigation, {})
	check(not Layout.enemy_forbidden(status["pos"]), "Large movement budget/stale route cannot enter camp")
	status["pos"] = Vector3(-14, 0, -36)
	var damage: int = AI.step("wolf_1", definition, status, 0.1, Vector3(-14, 0, -35), sim.navigation, {})
	check(damage == 0 and not Layout.enemy_forbidden(status["pos"]), "Invalid in-town enemy is repaired before movement or damage")
	definition["pos"] = Vector3(-14, 0, -36)
	AI.reset("wolf_1", definition, status, sim.navigation)
	check(not Layout.enemy_forbidden(status["pos"]), "Unsafe future spawn definition is moved to valid wilderness")

func _test_combat_boundary() -> void:
	_fresh()
	var status: Dictionary = sim.world["wolf_1"]
	status["state"] = "windup"
	status["state_time"] = 0.01
	status["aggro"] = true
	sim.character["pos"] = Vector3(-16, 0, -41)
	var health: int = int(sim.character["hp"])
	sim.tick(0.25)
	check(sim.character["hp"] == health and str(status["state"]) == "return", "Entering town during windup cancels damage and retains return-home behavior")
	sim.active_target = "wolf_1"
	sim.action_time = sim.action_duration
	var enemy_hp: int = int(status["hp"])
	sim._hit_enemy("wolf_1")
	check(int(status["hp"]) == enemy_hp and sim.character["xp"]["Combat"] == 0, "Cannot attack/farm enemies from a safe-town edge")
	check(sim.active_target.is_empty(), "Rejected protected attack leaves no repeat action")
