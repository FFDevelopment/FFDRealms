extends Node3D
const Terrain = preload("res://scripts/terrain.gd")
const World = preload("res://scripts/world.gd")
const Actor = preload("res://scripts/actor.gd")
const HUD = preload("res://scripts/hud.gd")
const Geo = preload("res://scripts/geometry.gd")
const Layout = preload("res://scripts/world_layout.gd")
var landscape
var player
var player_ring: MeshInstance3D
var hud
var camera: Camera3D
var yaw: float = 0.45
var zoom: float = 24.0
var focus: Vector3 = Vector3(0, 0, 8)
var click_pending: bool = false
var click_may_interact: bool = false
var click_force_move: bool = false
var click_position: Vector2 = Vector2.ZERO
var hover_timer: float = 0.0
var fishing_line: MeshInstance3D
var fishing_float: MeshInstance3D
var marker: MeshInstance3D
var marker_remaining: float = 0.0
var smoke_mode: bool = false
var smoke_frames: int = 0
var remote_actors: Dictionary = {}

func _ready() -> void:
	get_tree().auto_accept_quit = false
	landscape = World.new()
	landscape.name = "Hearthmere"
	add_child(landscape)
	player = Actor.new()
	player.name = "PlayerVisual"
	add_child(player)
	player.build_actor("Adventurer")
	for child: Node in player.get_children():
		if child is MeshInstance3D and (child as MeshInstance3D).mesh is TorusMesh:
			player_ring = child as MeshInstance3D
	player.position = Terrain.grounded(Game.position_of_player())
	camera = Camera3D.new()
	camera.name = "AdventureCamera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = zoom
	camera.far = 180.0
	camera.near = 0.1
	camera.current = true
	add_child(camera)
	_update_camera(1.0)
	marker = Geo.ring(self, Vector3.ZERO, 0.4, Color("f5d99b"))
	marker.visible = false
	fishing_line = Geo.box(self, Vector3.ZERO, Vector3(0.018, 0.018, 1.0), Color("e9e1c7"))
	fishing_line.name = "FishingLine"
	fishing_float = Geo.sphere(self, Vector3.ZERO, 0.10, Color("e39567"), Vector3(0.75, 1.0, 0.75))
	fishing_float.name = "FishingFloat"
	fishing_line.visible = false
	fishing_float.visible = false
	hud = HUD.new()
	hud.name = "AdventureHUD"
	add_child(hud)
	Game.effect.connect(_show_effect)
	Network.players_changed.connect(_sync_remote_players)
	Network.multiplayer_changed.connect(_sync_remote_players)
	_sync_remote_players()
	smoke_mode = "--smoke-test" in OS.get_cmdline_user_args()
	if smoke_mode:
		Engine.max_fps = 60
		Game.autosave_enabled = false
		Game.begin_game(1, "Smoke Test", true)
		hud.resume_game()

func _process(delta: float) -> void:
	if Game.character.is_empty():
		return
	player.position = Terrain.grounded(Game.position_of_player())
	if player_ring != null:
		player_ring.quaternion = Quaternion(Vector3.UP, Terrain.normal_at(player.position.x, player.position.z))
	player.name_label.text = str(Game.character["name"])
	player.apply_appearance(Game.character.get("appearance", {}))
	var tool: String = str(Game.character["weapon"])
	if not Game.active_target.is_empty():
		var kind: String = str(Game.definitions[Game.active_target]["kind"])
		if kind in ["tree", "oak"]:
			tool = "axe"
		elif kind == "rock":
			tool = "pick"
		elif kind == "fish":
			tool = "rod"
	player.set_tool(tool)
	player.animate(delta, Game.playing and not Game.path.is_empty(), Game.playing and not Game.active_target.is_empty(), Game.facing, Game.action_time / maxf(Game.action_duration, 0.01))
	_update_remote_actors(delta)
	_update_fishing_visuals()
	if Game.playing and hud.modal_kind.is_empty():
		if Input.is_physical_key_pressed(KEY_Q):
			yaw -= delta * 1.45
		if Input.is_physical_key_pressed(KEY_E):
			yaw += delta * 1.45
	_update_camera(delta)
	marker_remaining = maxf(0, marker_remaining - delta)
	marker.visible = marker_remaining > 0.0
	if marker.visible:
		marker.scale = Vector3.ONE * (1.0 + sin(marker_remaining * 8) * 0.12)
	if smoke_mode:
		smoke_frames += 1
		if smoke_frames >= 120:
			if landscape.targets.size() != Game.definitions.size():
				push_error("SMOKE FAIL: target visuals do not match simulation targets")
				get_tree().quit(1)
			else:
				print("SMOKE PASS: world, player, camera, HUD and all target visuals instantiated for 120 frames.")
				get_tree().quit(0)


func _sync_remote_players() -> void:
	var wanted: Dictionary = Network.remote_players if Network.multiplayer_online() else {}
	for existing: Variant in remote_actors.keys():
		var pid: int = int(existing)
		if not wanted.has(pid):
			var old_actor: Node = remote_actors[pid].get("actor", null)
			if is_instance_valid(old_actor):
				old_actor.queue_free()
			remote_actors.erase(pid)
	for raw_pid: Variant in wanted:
		var pid: int = int(raw_pid)
		var info: Dictionary = wanted[pid]
		if not remote_actors.has(pid):
			var avatar = Actor.new()
			avatar.name = "RemotePlayer_%d" % pid
			add_child(avatar)
			avatar.build_actor(str(info.get("name", "Adventurer")), Color("5c7f87"), false)
			avatar.position = Terrain.grounded(info.get("pos", Vector3.ZERO))
			remote_actors[pid] = {"actor": avatar, "last": avatar.position}
		var actor = remote_actors[pid]["actor"]
		actor.name_label.text = str(info.get("name", "Adventurer"))
		actor.apply_appearance(info.get("appearance", {}))
		actor.set_tool("wood_sword")

func _update_remote_actors(delta: float) -> void:
	if remote_actors.is_empty():
		return
	for raw_pid: Variant in remote_actors.keys():
		var pid: int = int(raw_pid)
		if not Network.remote_players.has(pid):
			continue
		var entry: Dictionary = remote_actors[pid]
		var actor = entry["actor"]
		var info: Dictionary = Network.remote_players[pid]
		var destination: Vector3 = Terrain.grounded(info.get("pos", Vector3.ZERO))
		var before: Vector3 = actor.position
		actor.position = actor.position.lerp(destination, minf(1.0, delta * 10.0))
		var moved: bool = before.distance_to(actor.position) > 0.002
		var direction: Vector3 = info.get("facing", Vector3(0, 0, -1))
		actor.animate(delta, moved, false, direction)
		entry["last"] = actor.position
		remote_actors[pid] = entry

func _update_fishing_visuals() -> void:
	var fishing: bool = Game.playing and not Game.active_target.is_empty()
	if fishing:
		fishing = str(Game.definitions[Game.active_target]["kind"]) == "fish" and is_instance_valid(player.rod_tip)
	fishing_line.visible = fishing
	fishing_float.visible = fishing
	if not fishing:
		return
	var cast_position: Vector3 = Game.fishing_cast_position()
	cast_position.y = Terrain.WATER_HEIGHT + 0.12 + sin(player.phase * 0.8) * 0.025
	fishing_float.position = cast_position
	var tip: Vector3 = player.rod_tip.global_position
	var length: float = tip.distance_to(cast_position)
	if length <= 0.01:
		fishing_line.visible = false
		return
	fishing_line.position = (tip + cast_position) * 0.5
	fishing_line.look_at(cast_position)
	fishing_line.scale = Vector3(1.0, 1.0, length)

func _update_camera(delta: float) -> void:
	var right: Vector3 = Vector3(cos(yaw), 0, -sin(yaw))
	var desired: Vector3 = Terrain.grounded(Game.position_of_player()) + right * 3.8
	if focus.distance_to(desired) > 15.0:
		focus = desired
	else:
		focus = focus.lerp(desired, minf(1.0, delta * 9.0))
	camera.position = focus + Vector3(sin(yaw) * 23.0, 28.0, cos(yaw) * 23.0)
	camera.look_at(focus + Vector3.UP * 0.3)
	camera.size = lerpf(camera.size, zoom, minf(1.0, delta * 12.0))

func _unhandled_input(event: InputEvent) -> void:
	if not Game.playing or not hud.modal_kind.is_empty():
		return
	if event is InputEventMouseButton:
		var click: InputEventMouseButton = event
		if not click.pressed:
			return
		match click.button_index:
			MOUSE_BUTTON_LEFT:
				# Capture readiness AT the click, not a later physics tick after completion.
				# Only press events are accepted: holding the button never repeats an action.
				click_may_interact = Game.accepts_interaction_click()
				click_force_move = click.shift_pressed
				click_position = click.position
				click_pending = true
			MOUSE_BUTTON_WHEEL_UP:
				zoom = maxf(14.0, zoom - 1.5)
			MOUSE_BUTTON_WHEEL_DOWN:
				zoom = minf(38.0, zoom + 1.5)
			_: return
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		var motion: InputEventMouseMotion = event
		if (motion.button_mask & (MOUSE_BUTTON_MASK_MIDDLE | MOUSE_BUTTON_MASK_RIGHT)) != 0:
			yaw -= motion.relative.x * 0.006
			get_viewport().set_input_as_handled()

func _physics_process(delta: float) -> void:
	if not is_instance_valid(hud) or not Game.playing or not hud.modal_kind.is_empty():
		click_pending = false
		return
	if click_pending:
		click_pending = false
		_handle_world_click(click_position, click_may_interact, click_force_move)
	hover_timer += delta
	if hover_timer < 0.09:
		return
	hover_timer = 0.0
	if get_viewport().gui_get_hovered_control() != null:
		hud.set_hover("", Vector2.ZERO)
		landscape.show_hover("")
		return
	var mouse: Vector2 = get_viewport().get_mouse_position()
	var id: String = _pick_target(mouse)
	landscape.show_hover(id)
	var caption: String = ""
	if not id.is_empty():
		caption = str(Game.definitions[id]["name"])
		var cooldown: float = float(Game.world[id]["cooldown"])
		if cooldown > 0.0:
			caption += "  /  returns in %ds" % ceili(cooldown)
		elif str(Game.definitions[id]["kind"]) == "bait_shop":
			caption += "  /  Buy bait"
		elif str(Game.definitions[id]["kind"]) == "fish":
			caption += "  /  One cast  /  Bait %d" % Game.count_item("fishing_bait")
		elif str(Game.definitions[id]["kind"]) == "enemy":
			caption += "  /  Returning home" if str(Game.world[id]["state"]) == "return" else "  /  One attack  /  HP %d" % int(Game.world[id]["hp"])
		else:
			caption += "  /  Click once"
	hud.set_hover(caption, mouse)

func _pick_target(screen: Vector2) -> String:
	var origin: Vector3 = camera.project_ray_origin(screen)
	var end: Vector3 = origin + camera.project_ray_normal(screen) * 200.0
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(origin, end, 2)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return ""
	var collider: Object = hit["collider"]
	return str(collider.get_meta("target_id", ""))

func _handle_world_click(screen: Vector2, allow_interaction: bool = true, force_move: bool = false) -> void:
	var id: String = "" if force_move else _pick_target(screen)
	if not id.is_empty():
		if not allow_interaction:
			Game.message.emit("Wait for the action to finish, then click again. No actions queued.")
			return
		var payload: Dictionary = {"id": id}
		if str(Game.definitions[id]["kind"]) == "fish":
			var water_plane: Plane = Plane(Vector3.UP, Terrain.WATER_HEIGHT)
			var water_hit: Variant = water_plane.intersects_ray(camera.project_ray_origin(screen), camera.project_ray_normal(screen))
			if water_hit is Vector3:
				var water: Vector3 = water_hit
				# Ray hits the thin pick box slightly before the visible water surface.
				water.x = clampf(water.x, Layout.POND.position.x + 0.01, Layout.POND.end.x - 0.01)
				water.z = clampf(water.z, Layout.POND.position.y + 0.01, Layout.POND.end.y - 0.01)
				water.y = 0.0
				payload["water_pos"] = water
		Game.dispatch("interact", payload)
		return
	# Raycast the actual terrain triangles. A Y=0 plane misplaces uphill clicks.
	var ray_origin: Vector3 = camera.project_ray_origin(screen)
	var ray_end: Vector3 = ray_origin + camera.project_ray_normal(screen) * 240.0
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(ray_origin, ray_end, 1)
	query.collide_with_areas = false
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		var destination: Vector3 = hit["position"]
		# Authority and old saves use X/Z; presentation samples terrain height separately.
		destination.y = 0.0
		if not Layout.in_bounds(destination):
			Game.message.emit("That road is beyond this prototype's boundary.")
			return
		if Game.dispatch("move", {"pos": destination}):
			if not Game.path.is_empty():
				marker.position = Terrain.grounded(Game.path[Game.path.size() - 1]) + Vector3.UP * 0.08
				marker.quaternion = Quaternion(Vector3.UP, Terrain.normal_at(marker.position.x, marker.position.z))
				marker_remaining = 1.7

func _show_effect(at: Vector3, text: String, tint: Color) -> void:
	var elevated: Vector3 = Terrain.grounded(at)
	var popup: Label3D = Geo.label(self, text, elevated, tint, 25)
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(popup, "position:y", elevated.y + 1.25, 1.1)
	tween.tween_property(popup, "modulate:a", 0.0, 1.1)
	tween.chain().tween_callback(popup.queue_free)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if is_instance_valid(hud):
			hud.request_quit()
		else:
			get_tree().quit()
