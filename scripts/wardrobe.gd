extends HBoxContainer
## Disposable preview/draft; no writes to Game until the Save appearance signal is accepted.
signal apply_requested(look: Dictionary)
const Appearance = preload("res://scripts/appearance.gd")
const Actor = preload("res://scripts/actor.gd")
const Geo = preload("res://scripts/geometry.gd")
var draft: Dictionary = {}
var preview_actor
var preview_viewport: SubViewport
var preview_camera: Camera3D
var color_controls: Dictionary = {}
var option_controls: Dictionary = {}
var pack_control: CheckButton
var summary: Label
var feedback: Label

func build(source: Dictionary) -> void:
	draft = Appearance.sanitize(source)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 20)
	var left: VBoxContainer = VBoxContainer.new()
	left.custom_minimum_size.x = 295
	left.add_theme_constant_override("separation", 10)
	add_child(left)
	var picture: TextureRect = TextureRect.new()
	picture.name = "CharacterPreview"
	picture.custom_minimum_size = Vector2(295, 382)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.mouse_filter = Control.MOUSE_FILTER_STOP
	picture.gui_input.connect(_preview_input)
	left.add_child(picture)
	preview_viewport = SubViewport.new()
	preview_viewport.name = "AppearanceViewport"
	preview_viewport.size = Vector2i(440, 570)
	preview_viewport.own_world_3d = true
	preview_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	picture.add_child(preview_viewport)
	picture.texture = preview_viewport.get_texture()
	var stage: Node3D = Node3D.new()
	preview_viewport.add_child(stage)
	var environment: WorldEnvironment = WorldEnvironment.new()
	var settings: Environment = Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("203630")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("c2d5d6")
	settings.ambient_light_energy = 0.32
	settings.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	settings.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	settings.tonemap_exposure = 0.95
	environment.environment = settings
	stage.add_child(environment)
	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, -30, 0)
	light.light_energy = 0.90
	light.light_color = Color("ffe9bc")
	stage.add_child(light)
	preview_actor = Actor.new()
	stage.add_child(preview_actor)
	preview_actor.build_actor("Preview", Color(str(draft["shirt_color"])), false)
	preview_actor.name_label.visible = false
	preview_actor.rotation.y = 0.28
	preview_actor.apply_appearance(draft)
	Geo.cylinder(stage, Vector3(0, -0.08, 0), 0.70, 0.73, 0.10, Color("456050"), 32)
	preview_camera = Camera3D.new()
	preview_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	preview_camera.size = 2.75
	preview_camera.position = Vector3(0, 1.5, -5)
	stage.add_child(preview_camera)
	preview_camera.look_at(Vector3(0, 1.07, 0))
	preview_camera.current = true
	var rotate: HBoxContainer = HBoxContainer.new()
	left.add_child(rotate)
	rotate.add_child(_button("Turn left", _rotate.bind(-PI / 4.0)))
	rotate.add_child(_button("Front", _front))
	rotate.add_child(_button("Turn right", _rotate.bind(PI / 4.0)))
	left.add_child(_label("Drag the preview to rotate.\nMouse wheel to zoom.", 14))
	summary = _label("", 14)
	left.add_child(summary)
	var right: VBoxContainer = VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.custom_minimum_size.x = 380
	right.add_theme_constant_override("separation", 12)
	add_child(right)
	var tabs: TabContainer = TabContainer.new()
	tabs.custom_minimum_size.y = 425
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_child(tabs)
	var body: VBoxContainer = _tab(tabs, "Body")
	_color(body, "skin_color")
	_color(body, "hair_color")
	_option(body, "hair_style")
	_color(body, "eyes_color")
	body.add_child(_label("Each color is independent. Use the picker or enter a hex color. Alpha is disabled so the character cannot become invisible.", 14))
	var clothes: VBoxContainer = _tab(tabs, "Clothes")
	_color(clothes, "shirt_color")
	_option(clothes, "shirt_fabric")
	clothes.add_child(HSeparator.new())
	_color(clothes, "pants_color")
	_option(clothes, "pants_style")
	clothes.add_child(HSeparator.new())
	_color(clothes, "shoes_color")
	_option(clothes, "shoe_style")
	_option(clothes, "shoe_fabric")
	var details: VBoxContainer = _tab(tabs, "Details")
	_color(details, "belt_color")
	_color(details, "pack_color")
	_color(details, "stitch_color")
	pack_control = CheckButton.new()
	pack_control.text = "Show backpack"
	pack_control.button_pressed = bool(draft["pack_visible"])
	pack_control.toggled.connect(_set_pack)
	details.add_child(pack_control)
	details.add_child(_label("Stitching is visible on jeans. Slacks use a pressed front crease. Hiding the backpack is cosmetic: storage capacity never changes.", 14))
	right.add_child(_label("Preview only until you save. Fabric changes keep your chosen dye colors. No armor, weapon or skill bonuses.", 14))
	right.add_child(_button("Reset preview to defaults", reset_draft))
	right.add_child(_button("Save appearance", _apply))
	feedback = _label("", 14)
	right.add_child(feedback)
	_refresh_preview()

func _tab(tabs: TabContainer, heading: String) -> VBoxContainer:
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.name = heading
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(scroll)
	var column: VBoxContainer = VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 10)
	scroll.add_child(column)
	return column

func _label(text: String, size: int = 16) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", size)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label

func _button(text: String, action: Callable) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.custom_minimum_size.y = 40
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(action)
	return button

func _row(parent: VBoxContainer, title: String) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.custom_minimum_size.y = 40
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)
	var label: Label = _label(title, 15)
	label.custom_minimum_size.x = 115
	label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	row.add_child(label)
	return row

func _color(parent: VBoxContainer, key: String) -> void:
	var row: HBoxContainer = _row(parent, str(Appearance.COLOR_LABELS[key]))
	var picker: ColorPickerButton = ColorPickerButton.new()
	picker.custom_minimum_size = Vector2(150, 40)
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.edit_alpha = false
	picker.color = Color(str(draft[key]))
	picker.tooltip_text = "Change only " + str(Appearance.COLOR_LABELS[key]).to_lower()
	picker.color_changed.connect(_set_color.bind(key))
	row.add_child(picker)
	color_controls[key] = picker

func _option(parent: VBoxContainer, key: String) -> void:
	var row: HBoxContainer = _row(parent, str(Appearance.OPTION_LABELS[key]))
	var option: OptionButton = OptionButton.new()
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	option.custom_minimum_size.y = 40
	var choices: Array = Appearance.OPTIONS[key]
	for value: String in choices:
		option.add_item(str(Appearance.STYLE_LABELS[value]))
	option.select(choices.find(draft[key]))
	option.item_selected.connect(_set_option.bind(key))
	row.add_child(option)
	option_controls[key] = option

func _set_color(value: Color, key: String) -> void:
	draft[key] = value.to_html(false)
	_refresh_preview()

func _set_option(index: int, key: String) -> void:
	var values: Array = Appearance.OPTIONS[key]
	if index >= 0 and index < values.size():
		draft[key] = values[index]
		_refresh_preview()

func _set_pack(shown: bool) -> void:
	draft["pack_visible"] = shown
	_refresh_preview()

func reset_draft() -> void:
	draft = Appearance.defaults()
	for key: String in color_controls:
		color_controls[key].color = Color(str(draft[key]))
	for key: String in option_controls:
		option_controls[key].select(Appearance.OPTIONS[key].find(draft[key]))
	pack_control.set_pressed_no_signal(bool(draft["pack_visible"]))
	_refresh_preview()

func _refresh_preview() -> void:
	preview_actor.apply_appearance(draft)
	summary.text = "%s top\n%s\n%s %s" % [str(Appearance.STYLE_LABELS[draft["shirt_fabric"]]), str(Appearance.STYLE_LABELS[draft["pants_style"]]), str(Appearance.STYLE_LABELS[draft["shoe_fabric"]]), str(draft["shoe_style"])]

func show_feedback(text: String) -> void:
	feedback.text = text

func _apply() -> void:
	apply_requested.emit(Appearance.sanitize(draft))

func _rotate(angle: float) -> void:
	preview_actor.rotation.y += angle

func _front() -> void:
	preview_actor.rotation.y = 0.0
	preview_camera.size = 2.75

func _preview_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var motion: InputEventMouseMotion = event
		if (motion.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			preview_actor.rotation.y += motion.relative.x * 0.012
	elif event is InputEventMouseButton:
		var click: InputEventMouseButton = event
		if click.pressed and click.button_index == MOUSE_BUTTON_WHEEL_UP:
			preview_camera.size = maxf(2.3, preview_camera.size - 0.15)
		elif click.pressed and click.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			preview_camera.size = minf(3.8, preview_camera.size + 0.15)
