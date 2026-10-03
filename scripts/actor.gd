extends Node3D
## Presentation only: no appearance option grants stats, items, health or XP.
const Geo = preload("res://scripts/geometry.gd")
const Appearance = preload("res://scripts/appearance.gd")
var body: Node3D
var left_arm: Node3D
var right_arm: Node3D
var left_leg: Node3D
var right_leg: Node3D
var tool: Node3D
var rod_tip: Node3D
var name_label: Label3D
var phase: float = 0.0
var tool_key: String = ""
var parts: Dictionary = {}
var slot_materials: Dictionary = {}
var details: Dictionary = {}
var _appearance_signature: String = ""
var appearance_data: Dictionary = {}

func _part(slot: String, instance: MeshInstance3D) -> MeshInstance3D:
	if not parts.has(slot):
		parts[slot] = []
	parts[slot].append(instance)
	return instance

func _detail(key: String, instance: Node3D) -> void:
	if not details.has(key):
		details[key] = []
	details[key].append(instance)

func build_actor(display_name: String, coat: Color = Color("467e82"), player: bool = true) -> void:
	body = Node3D.new()
	add_child(body)
	_part("shirt_color", Geo.cylinder(body, Vector3(0, 1.12, 0), 0.31, 0.25, 0.66, coat, 12))
	_part("pants_color", Geo.box(body, Vector3(0, 0.77, 0), Vector3(0.47, 0.14, 0.30), Color.WHITE))
	_part("belt_color", Geo.box(body, Vector3(0, 0.83, 0), Vector3(0.5, 0.12, 0.32), Color.WHITE))
	Geo.box(body, Vector3(0, 0.84, -0.18), Vector3(0.13, 0.10, 0.06), Color("d6b272"))
	_part("skin_color", Geo.cylinder(body, Vector3(0, 1.56, 0), 0.12, 0.12, 0.18, Color.WHITE, 8))
	_part("skin_color", Geo.sphere(body, Vector3(0, 1.81, 0), 0.25, Color.WHITE, Vector3(0.88, 1.08, 0.88)))
	for style: String in ["short", "swept"]:
		var hair: Node3D = Node3D.new()
		body.add_child(hair)
		_detail(style, hair)
		var cap: MeshInstance3D = _part("hair_color", Geo.box(hair, Vector3(0, 2.00, 0.025), Vector3(0.41, 0.16, 0.38), Color.WHITE))
		_part("hair_color", Geo.box(hair, Vector3(0, 1.89, 0.16), Vector3(0.4, 0.26, 0.11), Color.WHITE))
		if style == "swept":
			cap.rotation.z = -0.14
			var fringe: MeshInstance3D = _part("hair_color", Geo.box(hair, Vector3(-0.06, 1.95, -0.16), Vector3(0.29, 0.15, 0.12), Color.WHITE))
			fringe.rotation.z = -0.25
	for x: float in [-0.08, 0.08]:
		Geo.box(body, Vector3(x, 1.84, -0.204), Vector3(0.066, 0.052, 0.024), Color("f1ead9"))
		_part("eyes_color", Geo.box(body, Vector3(x, 1.84, -0.22), Vector3(0.033, 0.043, 0.020), Color.WHITE))
	_part("skin_color", Geo.box(body, Vector3(0, 1.77, -0.22), Vector3(0.075, 0.072, 0.062), Color.WHITE))
	Geo.box(body, Vector3(0, 1.71, -0.205), Vector3(0.075, 0.018, 0.018), Color("755249"))
	var pack: MeshInstance3D = _part("pack_color", Geo.box(body, Vector3(0, 1.16, 0.28), Vector3(0.4, 0.48, 0.25), Color.WHITE))
	_detail("pack", pack)
	var flap: MeshInstance3D = _part("belt_color", Geo.box(body, Vector3(0, 1.37, 0.30), Vector3(0.42, 0.06, 0.26), Color.WHITE))
	_detail("pack", flap)
	for x: float in [-0.11, 0.11]:
		_part("shirt_color", Geo.box(body, Vector3(x, 1.43, -0.12), Vector3(0.14, 0.06, 0.20), Color.WHITE))
	left_arm = _limb(Vector3(-0.35, 1.42, 0), true)
	right_arm = _limb(Vector3(0.35, 1.42, 0), true)
	left_leg = _limb(Vector3(-0.14, 0.78, 0), false)
	right_leg = _limb(Vector3(0.14, 0.78, 0), false)
	tool = Node3D.new()
	tool.position = Vector3(0, -0.48, 0)
	right_arm.add_child(tool)
	name_label = Geo.label(self, display_name, Vector3(0, 2.45, 0), Color("f1e3bf"), 24)
	var look: Dictionary = Appearance.defaults()
	look["shirt_color"] = coat.to_html(false)
	apply_appearance(look)
	if player:
		Geo.ring(self, Vector3(0, 0.035, 0), 0.50, Color("d4be80"))
		set_tool("wood_sword")

func _limb(at: Vector3, arm: bool) -> Node3D:
	var pivot: Node3D = Node3D.new()
	pivot.position = at
	body.add_child(pivot)
	if arm:
		_part("shirt_color", Geo.box(pivot, Vector3(0, -0.22, 0), Vector3(0.18, 0.42, 0.22), Color.WHITE))
		_part("skin_color", Geo.sphere(pivot, Vector3(0, -0.49, 0), 0.105, Color.WHITE))
	else:
		_part("pants_color", Geo.box(pivot, Vector3(0, -0.28, 0), Vector3(0.19, 0.56, 0.23), Color.WHITE))
		var denim: Node3D = Node3D.new()
		pivot.add_child(denim)
		_detail("denim", denim)
		_part("stitch_color", Geo.box(denim, Vector3(0.0, -0.07, 0.12), Vector3(0.13, 0.018, 0.014), Color.WHITE))
		_part("stitch_color", Geo.box(denim, Vector3(0.065, -0.12, 0.12), Vector3(0.013, 0.10, 0.014), Color.WHITE))
		_part("stitch_color", Geo.box(denim, Vector3(-0.065, -0.12, 0.12), Vector3(0.013, 0.10, 0.014), Color.WHITE))
		_part("stitch_color", Geo.box(denim, Vector3(0, -0.17, 0.12), Vector3(0.13, 0.016, 0.014), Color.WHITE))
		_part("stitch_color", Geo.box(denim, Vector3(signf(at.x) * 0.10, -0.30, 0), Vector3(0.01, 0.50, 0.015), Color.WHITE))
		var crease: MeshInstance3D = _part("pants_color", Geo.box(pivot, Vector3(0, -0.30, -0.12), Vector3(0.018, 0.50, 0.018), Color.WHITE))
		_detail("slacks", crease)
		var boot: MeshInstance3D = _part("shoes_color", Geo.box(pivot, Vector3(0, -0.64, -0.05), Vector3(0.21, 0.25, 0.32), Color.WHITE))
		_detail("boots", boot)
		var shoe: MeshInstance3D = _part("shoes_color", Geo.box(pivot, Vector3(0, -0.68, -0.055), Vector3(0.21, 0.17, 0.33), Color.WHITE))
		_detail("shoes", shoe)
		Geo.box(pivot, Vector3(0, -0.75, -0.06), Vector3(0.22, 0.05, 0.34), Color("30362e"))
	return pivot

func apply_appearance(source: Dictionary) -> void:
	var signature: String = JSON.stringify(source)
	if signature == _appearance_signature or body == null:
		return
	_appearance_signature = signature
	appearance_data = Appearance.sanitize(source)
	for slot: String in parts:
		if not slot_materials.has(slot):
			slot_materials[slot] = StandardMaterial3D.new()
		var surface: StandardMaterial3D = slot_materials[slot]
		surface.albedo_color = Color(str(appearance_data[slot]))
		var fabric: String = Appearance.fabric_for(slot, appearance_data)
		surface.albedo_texture = Appearance.fabric_texture(fabric)
		surface.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		surface.roughness = 0.73 if fabric == "leather" else 0.94
		surface.metallic_specular = 0.12
		for mesh: MeshInstance3D in parts[slot]:
			mesh.material_override = surface
	for key: String in details:
		var shown: bool = key == str(appearance_data["pants_style"]) or key == str(appearance_data["shoe_style"]) or key == str(appearance_data["hair_style"])
		if key == "pack":
			shown = bool(appearance_data["pack_visible"])
		for node: Node3D in details[key]:
			node.visible = shown

func set_tool(key: String) -> void:
	if key == tool_key or tool == null:
		return
	tool_key = key
	rod_tip = null
	for child: Node in tool.get_children():
		tool.remove_child(child)
		child.queue_free()
	var wood: Color = Color("987451")
	var metal: Color = Color("b9cbd0")
	if key == "axe" or key == "pick":
		Geo.box(tool, Vector3(0, -0.22, 0), Vector3(0.065, 0.64, 0.065), wood)
		if key == "axe":
			Geo.box(tool, Vector3(0.10, -0.43, 0), Vector3(0.34, 0.22, 0.10), metal)
		else:
			var head: MeshInstance3D = Geo.box(tool, Vector3(0, -0.43, 0), Vector3(0.60, 0.085, 0.085), metal)
			head.rotation.z = 0.14
	elif key == "rod":
		var tip: Vector3 = Vector3(0, 1.1, -1.4)
		var rod: MeshInstance3D = Geo.box(tool, tip * 0.5, Vector3(0.045, tip.length(), 0.045), wood)
		rod.rotation.x = atan2(tip.z, tip.y)
		rod_tip = Node3D.new()
		rod_tip.name = "RodTip"
		rod_tip.position = tip
		tool.add_child(rod_tip)
	else:
		if key == "wood_sword":
			metal = wood
		elif key == "bronze_sword":
			metal = Color("d0a064")
		elif key == "steel_sword":
			metal = Color("dbe4e9")
		Geo.box(tool, Vector3(0, 0, 0), Vector3(0.075, 0.23, 0.075), Color("503e30"))
		Geo.box(tool, Vector3(0, -0.13, 0), Vector3(0.32, 0.055, 0.075), Color("d4af75"))
		Geo.box(tool, Vector3(0, -0.47, 0), Vector3(0.115, 0.63, 0.055), metal)

func animate(delta: float, moving: bool, working: bool, direction: Vector3, action_progress: float = 0.0) -> void:
	phase += delta * (8.5 if moving else 4.0)
	if direction.length_squared() > 0.01:
		body.rotation.y = lerp_angle(body.rotation.y, atan2(-direction.x, -direction.z), minf(1.0, delta * 13.0))
	var stride: float = sin(phase) * 0.58 if moving else 0.0
	left_leg.rotation.x = stride
	right_leg.rotation.x = -stride
	left_arm.rotation.x = -stride * 0.8
	right_arm.rotation.x = stride * 0.8
	if working:
		if tool_key == "rod":
			# Hold the rod steady instead of reusing the axe/mining swing.
			right_arm.rotation.x = -0.10 + sin(phase * 0.55) * 0.03
			left_arm.rotation.x = -0.25
		else:
			# One swing across the action timeline; no cyclic chopping/attack animation.
			right_arm.rotation.x = lerpf(-1.45, 0.45, smoothstep(0.15, 0.85, clampf(action_progress, 0.0, 1.0)))
			left_arm.rotation.x = -0.25
	body.position.y = absf(sin(phase)) * 0.045 if moving else sin(phase * 0.6) * 0.012
