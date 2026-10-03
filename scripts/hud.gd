extends CanvasLayer
const Combat = preload("res://scripts/combat_rules.gd")
const Catalog = preload("res://scripts/catalog.gd")
const Layout = preload("res://scripts/world_layout.gd")
const Saves = preload("res://scripts/save_store.gd")
const MapView = preload("res://scripts/world_map.gd")
const Wardrobe = preload("res://scripts/wardrobe.gd")
const INK: Color = Color("e9e4d3")
const MUTED: Color = Color("a5b5a9")
const GOLD: Color = Color("dcc187")
const BACK: Color = Color("203630")
var root: Control
var region_label: Label
var health_label: Label
var gold_label: Label
var action_label: Label
var action_bar: ProgressBar
var side_panel: PanelContainer
var side_content: VBoxContainer
var side_scroll: ScrollContainer
var side_tab: String = "bag"
var selected_item: String = "cooked_trout"
var log_label: Label
var hover_label: Label
var objective_label: Label
var messages: PackedStringArray = PackedStringArray()
var overlay: ColorRect
var modal_kind: String = ""
var modal_content: VBoxContainer
var modal_scroll: ScrollContainer
var modal_title: Label
var modal_subtitle: Label
var name_input: LineEdit
var slot_input: OptionButton
var menu_error: Label
var new_confirm: ConfirmationDialog
var wardrobe_editor
var login_username: LineEdit
var login_password: LineEdit
var signup_email: LineEdit
var updates_check: CheckBox
var remember_check: CheckBox
var account_status: Label
var account_busy: bool = false
var _side_signature: String = ""
var _modal_signature: String = ""

func _ready() -> void:
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = _theme()
	add_child(root)
	_build_chrome()
	Game.changed.connect(refresh)
	Game.message.connect(add_message)
	Game.panel_requested.connect(_on_panel_requested)
	Network.account_changed.connect(_on_account_changed)
	Network.account_result.connect(_on_account_result)
	Network.multiplayer_changed.connect(_on_multiplayer_changed)
	refresh()
	if Network.is_signed_in() or Network.offline_mode:
		show_menu()
	else:
		show_account_gate()

func _theme() -> Theme:
	var theme: Theme = Theme.new()
	theme.default_font_size = 17
	theme.set_color("font_color", "Label", INK)
	theme.set_color("font_color", "Button", INK)
	theme.set_color("font_hover_color", "Button", Color("fff1cd"))
	theme.set_color("font_disabled_color", "Button", Color("74887d"))
	theme.set_stylebox("normal", "Button", _style(Color("304a40"), Color("4f6852"), 7))
	theme.set_stylebox("hover", "Button", _style(Color("45614c"), GOLD, 7))
	theme.set_stylebox("pressed", "Button", _style(Color("6a7350"), GOLD, 7))
	theme.set_stylebox("disabled", "Button", _style(Color("253c32"), Color("3c5144"), 7))
	theme.set_stylebox("panel", "PanelContainer", _style(Color(0.10, 0.18, 0.16, 0.96), Color("51614b"), 10))
	theme.set_stylebox("background", "ProgressBar", _style(Color("172923"), Color("172923"), 4))
	theme.set_stylebox("fill", "ProgressBar", _style(Color("abbd81"), Color("abbd81"), 4))
	theme.set_stylebox("normal", "LineEdit", _style(Color("152922"), Color("647554"), 6))
	theme.set_color("font_color", "LineEdit", INK)
	theme.set_color("font_placeholder_color", "LineEdit", MUTED)
	return theme

func _style(fill: Color, border: Color, radius: int = 8) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style

func _label(text: String, size: int = 17, color: Color = INK, wrap: bool = false) -> Label:
	var node: Label = Label.new()
	node.text = text
	node.add_theme_font_size_override("font_size", size)
	node.add_theme_color_override("font_color", color)
	if wrap:
		node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return node

func _button(text: String, action: Callable, accent: bool = false) -> Button:
	var node: Button = Button.new()
	node.text = text
	node.custom_minimum_size = Vector2(0, 40)
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	node.focus_mode = Control.FOCUS_NONE
	if accent:
		node.add_theme_stylebox_override("normal", _style(Color("65714c"), GOLD, 7))
	node.pressed.connect(action)
	return node

func _margin(parent: Node, padding: int = 16) -> MarginContainer:
	var margin: MarginContainer = MarginContainer.new()
	for edge: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, padding)
	parent.add_child(margin)
	return margin

func _panel(left: float, top: float, right: float, bottom: float, preset: int = Control.PRESET_FULL_RECT) -> PanelContainer:
	var panel: PanelContainer = PanelContainer.new()
	root.add_child(panel)
	panel.set_anchors_and_offsets_preset(preset)
	panel.offset_left = left
	panel.offset_top = top
	panel.offset_right = right
	panel.offset_bottom = bottom
	return panel

func _build_chrome() -> void:
	var bar: PanelContainer = _panel(20, 18, -20, 88, Control.PRESET_TOP_WIDE)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	_margin(bar, 10).add_child(row)
	var brand: VBoxContainer = VBoxContainer.new()
	brand.custom_minimum_size.x = 190
	row.add_child(brand)
	brand.add_child(_label("FFD REALMS", 25, GOLD))
	brand.add_child(_label("NORTHREACH   /   v" + Catalog.VERSION, 11, MUTED))
	var status: VBoxContainer = VBoxContainer.new()
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(status)
	region_label = _label("Hearthmere", 20)
	status.add_child(region_label)
	var vitals: HBoxContainer = HBoxContainer.new()
	vitals.add_theme_constant_override("separation", 20)
	status.add_child(vitals)
	health_label = _label("Health 30 / 30", 14, Color("c5dca2"))
	gold_label = _label("15 coins", 14, GOLD)
	vitals.add_child(health_label)
	vitals.add_child(gold_label)
	row.add_child(_button("Appearance  C", show_wardrobe))
	row.add_child(_button("Map  M", show_map))
	row.add_child(_button("Eat  F", _intent.bind("eat", {})))
	row.add_child(_button("Save", _intent.bind("save", {})))
	row.add_child(_button("Menu", show_menu))
	row.get_child(2).custom_minimum_size.x = 95
	objective_label = _label("A new beginning\nSpeak to Warden Elin in the square.", 18, Color("f1e2bc"), true)
	root.add_child(objective_label)
	objective_label.position = Vector2(32, 109)
	objective_label.size = Vector2(430, 68)
	objective_label.add_theme_color_override("font_shadow_color", Color("20372d"))
	objective_label.add_theme_constant_override("shadow_offset_x", 1)
	objective_label.add_theme_constant_override("shadow_offset_y", 2)
	objective_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	side_panel = _panel(-326, 107, -20, -117, Control.PRESET_RIGHT_WIDE)
	var side: VBoxContainer = VBoxContainer.new()
	side.add_theme_constant_override("separation", 12)
	_margin(side_panel, 14).add_child(side)
	var tabs: HBoxContainer = HBoxContainer.new()
	side.add_child(tabs)
	tabs.add_child(_button("Bag", select_tab.bind("bag")))
	tabs.add_child(_button("Skills", select_tab.bind("skills")))
	tabs.add_child(_button("Journal", select_tab.bind("journal")))
	side_scroll = ScrollContainer.new()
	side_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side.add_child(side_scroll)
	side_content = VBoxContainer.new()
	side_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side_content.add_theme_constant_override("separation", 12)
	side_scroll.add_child(side_content)
	var action_panel: PanelContainer = _panel(20, -100, -20, -18, Control.PRESET_BOTTOM_WIDE)
	var action_row: HBoxContainer = HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 24)
	_margin(action_panel, 10).add_child(action_row)
	var action_column: VBoxContainer = VBoxContainer.new()
	action_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_row.add_child(action_column)
	action_label = _label("", 16, INK, true)
	action_column.add_child(action_label)
	action_bar = ProgressBar.new()
	action_bar.custom_minimum_size.y = 7
	action_bar.max_value = 1.0
	action_bar.show_percentage = false
	action_column.add_child(action_bar)
	action_row.add_child(_button("Stop  Space", _intent.bind("cancel", {})))
	action_row.add_child(_button("Controls", show_help))
	log_label = _label("", 15, Color("ece5cc"), true)
	root.add_child(log_label)
	log_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	log_label.offset_left = 30
	log_label.offset_right = 640
	log_label.offset_top = -261
	log_label.offset_bottom = -114
	log_label.add_theme_color_override("font_shadow_color", Color("172e25"))
	log_label.add_theme_constant_override("shadow_offset_y", 2)
	log_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hover_label = _label("", 17, Color("ffe7ad"), false)
	hover_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hover_label)

func add_message(text: String) -> void:
	messages.append(text)
	while messages.size() > 5:
		messages.remove_at(0)
	log_label.text = "\n".join(messages)
	if modal_kind == "wardrobe" and is_instance_valid(wardrobe_editor):
		wardrobe_editor.show_feedback(text)
	if is_instance_valid(menu_error) and modal_kind == "menu":
		menu_error.text = text

func refresh() -> void:
	if not is_instance_valid(root) or Game.character.is_empty():
		return
	region_label.text = Layout.region_name(Game.position_of_player()) + ("  |  SAFE TOWN" if Layout.is_safe(Game.position_of_player()) else "")
	health_label.text = "Health %d / %d" % [int(Game.character["hp"]), Game.max_hp()]
	gold_label.text = "%d coins" % int(Game.character["coins"])
	action_label.text = Game.action_label()
	action_bar.value = Game.action_time / maxf(Game.action_duration, 0.01) if not Game.active_target.is_empty() else (1.0 - Game._attack_cooldown / Combat.PLAYER_ATTACK_INTERVAL if Game._attack_cooldown > 0.0 else 0.0)
	var quest: Dictionary = Game.character["quest"]
	var frontier: Dictionary = Game.character["frontier"]
	if bool(frontier["claimed"]):
		objective_label.text = "Northreach secured\nSteelworking learned. Smithing 5 unlocks steel gear."
	elif Game.frontier_ready():
		objective_label.text = "Expedition complete\nReturn to Ranger Tamsin at Northreach Camp."
	elif bool(frontier["started"]):
		objective_label.text = "Beyond the Old Watch\nClear the frontier. Track objectives in Journal [J]."
	elif bool(quest["claimed"]):
		objective_label.text = "Beyond the Old Watch\nFollow the north road to Ranger Tamsin. Map [M]"
	elif Game.quest_ready():
		objective_label.text = "Ready to report\nReturn to Warden Elin for your reward."
	elif bool(quest["started"]):
		objective_label.text = "A Foothold in Hearthmere\nGather, craft and clear the watch.  Journal [J]"
	else:
		objective_label.text = "A new beginning\nSpeak to Warden Elin in the square."
	var relevant: Array = [Game.character["bag"], Game.character["xp"], quest, frontier, Game.character["weapon"], selected_item, side_tab]
	var signature: String = JSON.stringify(relevant)
	if signature != _side_signature:
		_side_signature = signature
		_rebuild_side()
	var modal_signature: String = signature + str(Game.character["bank"]) + str(Game.character["coins"])
	if modal_kind in ["bank", "market", "forge", "campfire", "guide", "bait_shop", "ranger"] and modal_signature != _modal_signature:
		_modal_signature = modal_signature
		_rebuild_station()

func _clear(container: Node) -> void:
	for child: Node in container.get_children():
		container.remove_child(child)
		child.queue_free()

func select_tab(tab: String) -> void:
	side_panel.visible = true
	side_tab = tab
	_side_signature = ""
	refresh()

func toggle_bag() -> void:
	if side_panel.visible and side_tab == "bag":
		side_panel.visible = false
	else:
		select_tab("bag")

func _rebuild_side() -> void:
	var scroll_position: int = side_scroll.scroll_vertical
	_clear(side_content)
	match side_tab:
		"skills": _build_skills(side_content)
		"journal": _build_journal(side_content)
		_: _build_bag(side_content)
	side_scroll.set_deferred("scroll_vertical", scroll_position)

func _build_bag(parent: VBoxContainer) -> void:
	parent.add_child(_label("BACKPACK    %d / %d" % [Game.bag_used(), Catalog.BAG_CAPACITY], 17, GOLD))
	parent.add_child(_label("28 slots. Bait stacks in one slot; other items use one slot each.", 13, MUTED, true))
	var grid: GridContainer = GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 5)
	grid.add_theme_constant_override("v_separation", 5)
	parent.add_child(grid)
	var inventory: Dictionary = Game.character["bag"]
	for id: String in Catalog.ITEMS:
		if int(inventory.get(id, 0)) < 1:
			continue
		var entry: Dictionary = Catalog.ITEMS[id]
		var button: Button = _button("%s\nx%d" % [str(entry["short"]), int(inventory[id])], _select_item.bind(id))
		button.custom_minimum_size = Vector2(62, 62)
		button.add_theme_font_size_override("font_size", 12)
		button.tooltip_text = Catalog.item_name(id)
		var tint: Color = Color(str(entry["color"]))
		button.add_theme_stylebox_override("normal", _style(tint.darkened(0.67), GOLD if id == selected_item else tint.darkened(0.3), 5))
		grid.add_child(button)
	if inventory.is_empty():
		parent.add_child(_label("Empty. Your axe, pickaxe and rod are permanent starter tools.", 15, MUTED, true))
	parent.add_child(HSeparator.new())
	if Catalog.ITEMS.has(selected_item) and Game.count_item(selected_item) > 0:
		var entry: Dictionary = Catalog.ITEMS[selected_item]
		parent.add_child(_label(str(entry["name"]), 20, INK, true))
		parent.add_child(_label("Sale value: %d coins each" % int(entry["sell"]), 14, MUTED))
		if entry.has("damage"):
			parent.add_child(_label("Base melee damage: %d" % int(entry["damage"]), 15, MUTED))
			parent.add_child(_button("Equip weapon", _intent.bind("equip", {"id": selected_item}), true))
		elif entry.has("heal"):
			parent.add_child(_label("Restores up to 12 health. One-second eating cooldown.", 14, MUTED, true))
			parent.add_child(_button("Eat trout  [F]", _intent.bind("eat", {}), true))
		elif selected_item == "fishing_bait":
			parent.add_child(_label("One bait per completed catch. Click Stillwater Pond to fish. Interrupted or blocked catches use no bait.", 15, MUTED, true))
		else:
			parent.add_child(_label("Use at a crafting station, store at the village bank, or sell to Mara.", 15, MUTED, true))
	parent.add_child(HSeparator.new())
	parent.add_child(_label("EQUIPPED", 14, GOLD))
	parent.add_child(_label(Catalog.item_name(str(Game.character["weapon"])), 19, INK, true))
	parent.add_child(_label("Tools: axe, pickaxe, fishing rod\nBuy bait at the pond bucket.", 14, MUTED, true))
	parent.add_child(_button("Change appearance  [C]", show_wardrobe))

func _select_item(id: String) -> void:
	selected_item = id
	_side_signature = ""
	refresh()

func _build_skills(parent: VBoxContainer) -> void:
	parent.add_child(_label("LEARN BY DOING", 18, GOLD))
	for skill: String in Catalog.SKILLS:
		var level: int = Game.skill_level(skill)
		var xp: int = int(Game.character["xp"][skill])
		var floor_xp: int = Catalog.xp_for_level(level)
		var next_xp: int = Catalog.xp_for_level(level + 1)
		parent.add_child(_label("%s   %d" % [skill, level], 18))
		var bar: ProgressBar = ProgressBar.new()
		bar.custom_minimum_size.y = 9
		bar.max_value = maxi(1, next_xp - floor_xp)
		bar.value = xp - floor_xp
		bar.show_percentage = false
		parent.add_child(bar)
		parent.add_child(_label("%d XP  /  next level %d XP" % [xp, next_xp] if level < 50 else "Prototype level cap reached", 12, MUTED))
	parent.add_child(_label("LEVEL 3\nWoodcutting: oak\nMining: iron and coal\nSmithing: iron gear\n\nLEVEL 5 + FRONTIER QUEST\nSmithing: steel bars and swords", 14, GOLD, true))

func _build_journal(parent: VBoxContainer) -> void:
	parent.add_child(_label("A Foothold in\nHearthmere", 23, GOLD))
	var quest: Dictionary = Game.character["quest"]
	if not bool(quest["started"]):
		parent.add_child(_label("Meet Warden Elin in the square to accept your first quest. Actions before accepting do not count.", 16, INK, true))
	else:
		for key: String in Catalog.QUEST_GOALS:
			var amount: int = int(quest[key])
			var goal: int = int(Catalog.QUEST_GOALS[key])
			var done: bool = amount >= goal
			parent.add_child(_label("%s  %s\n      %d / %d" % ["DONE" if done else "TODO", str(Catalog.QUEST_LABELS[key]), amount, goal], 15, Color("c4d6a0") if done else INK, true))
	parent.add_child(_label("Reward: 75 coins + 40 XP in each skill. Milestones track actions; Elin does not take your supplies.", 15, GOLD, true))
	parent.add_child(_label("Suggested route\nForest: 5 logs\nQuarry: 3 copper + 3 tin\nForge: 3 bars, then bronze sword\nPond bucket: buy at least 3 bait\nPond and fire: catch and cook 3 trout\nOld Watch: defeat 3 mosslings\nReturn to Elin", 15, MUTED, true))
	if bool(quest["claimed"]):
		parent.add_child(_label("QUEST COMPLETE", 18, Color("c4d6a0")))
	parent.add_child(HSeparator.new())
	parent.add_child(_label("Beyond the\nOld Watch", 23, GOLD))
	var frontier: Dictionary = Game.character["frontier"]
	if not bool(frontier["started"]):
		parent.add_child(_label("Complete Elin's quest, then follow the north road through the old watch to Ranger Tamsin. You can explore Northreach before accepting, but objectives count only after acceptance.", 15, INK, true))
	else:
		for key: String in Catalog.FRONTIER_GOALS:
			parent.add_child(_label("%d / %d  %s" % [int(frontier[key]), int(Catalog.FRONTIER_GOALS[key]), str(Catalog.FRONTIER_LABELS[key])], 15, INK, true))
	parent.add_child(_label("Reward: 110 coins, 100 Combat XP, 80 Smithing XP and steel recipes. Steel also requires Smithing 5. Bring an iron sword and cooked food; Mining 3 is needed for coal.", 15, GOLD, true))
	if bool(frontier["claimed"]):
		parent.add_child(_label("EXPEDITION COMPLETE", 18, Color("c4d6a0")))

func _intent(verb: String, payload: Dictionary) -> void:
	Game.dispatch(verb, payload)
	refresh()

func _new_modal(kind: String, heading: String, subtitle: String, width: float = 650, height: float = 650) -> void:
	if is_instance_valid(overlay):
		root.remove_child(overlay)
		overlay.queue_free()
	modal_kind = kind
	_modal_signature = ""
	overlay = ColorRect.new()
	overlay.color = Color(0.035, 0.06, 0.05, 0.64)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel: PanelContainer = PanelContainer.new()
	overlay.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left = -width * 0.5
	panel.offset_right = width * 0.5
	panel.offset_top = -height * 0.5
	panel.offset_bottom = height * 0.5
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	_margin(panel, 23).add_child(column)
	modal_title = _label(heading, 29, GOLD, true)
	column.add_child(modal_title)
	modal_subtitle = _label(subtitle, 15, MUTED, true)
	column.add_child(modal_subtitle)
	column.add_child(HSeparator.new())
	modal_scroll = ScrollContainer.new()
	modal_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	modal_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(modal_scroll)
	modal_content = VBoxContainer.new()
	modal_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	modal_content.add_theme_constant_override("separation", 12)
	modal_scroll.add_child(modal_content)
	if kind not in ["menu", "account", "account_settings"]:
		column.add_child(_button("Discard changes / Back to world  [Esc]" if kind == "wardrobe" else "Back to world  [Esc]", close_modal))

func close_modal(cancel: bool = true) -> void:
	if modal_kind == "account":
		return
	if modal_kind == "account_settings":
		show_menu()
		return
	if modal_kind == "menu":
		if Game.profile_slot > 0:
			resume_game()
		return
	if is_instance_valid(overlay):
		root.remove_child(overlay)
		overlay.queue_free()
	overlay = null
	modal_kind = ""
	if cancel:
		Game.cancel_action(false)

func _on_panel_requested(kind: String) -> void:
	if kind.is_empty():
		if modal_kind != "menu":
			close_modal(false)
		return
	var headings: Dictionary = {"bank": "Village bank", "campfire": "A place by the fire", "forge": "Smelter & anvil", "market": "Mara's provisions", "guide": "Warden Elin", "bait_shop": "Stillwater bait bucket", "ranger": "Ranger Tamsin"}
	var heading: String = str(Game.definitions.get(Game.station_id, {}).get("name", headings.get(kind, kind)))
	_new_modal(kind, heading, "%s  /  %d coins  /  Backpack %d of 28" % [Layout.region_name(Game.position_of_player()), int(Game.character["coins"]), Game.bag_used()])
	_rebuild_station()

func _rebuild_station() -> void:
	if not is_instance_valid(modal_content):
		return
	var previous_scroll: int = modal_scroll.scroll_vertical
	_clear(modal_content)
	modal_subtitle.text = "%s  /  %d coins  /  Backpack %d of 28" % [Layout.region_name(Game.position_of_player()), int(Game.character["coins"]), Game.bag_used()]
	match modal_kind:
		"ranger":
			modal_content.add_child(_label("The north road is open, but the ruins are not safe. Thin the briar wolves, sample the coal seams, and bring down the Watchwarden.", 20, INK, true))
			modal_content.add_child(_label("Northreach Camp is a safe rest area. Its bank shares storage with Hearthmere. Beyond camp, creatures pursue, reposition and telegraph attacks. An iron sword and cooked food are recommended.", 16, MUTED, true))
			var quest: Dictionary = Game.character["frontier"]
			var caption: String = "Accept: Beyond the Old Watch"
			if bool(quest["started"]):
				caption = "Claim expedition reward" if Game.frontier_ready() else "Ask about my progress"
			if bool(quest["claimed"]):
				caption = "Ask about steelworking"
			modal_content.add_child(_button(caption, _intent.bind("frontier_quest", {}), true))
			if not bool(Game.character["quest"]["claimed"]):
				modal_content.add_child(_label("First complete Elin's Hearthmere quest. You may still explore the new region.", 16, GOLD, true))
			for key: String in Catalog.FRONTIER_GOALS:
				modal_content.add_child(_label("%d / %d  %s" % [int(quest[key]), int(Catalog.FRONTIER_GOALS[key]), str(Catalog.FRONTIER_LABELS[key])], 16, INK, true))
			modal_content.add_child(_label("Reward: 110 coins, 100 Combat XP, 80 Smithing XP, and steelworking recipes. Smithing level 5 is also required for steel.", 16, GOLD, true))
		"guide":
			modal_content.add_child(_label("\"Hearthmere needs people who can build as well as fight. Learn the local trades, prepare a proper blade, and clear the mosslings from the old watch.\"", 20, INK, true))
			modal_content.add_child(_label("Accept the quest before gathering. You keep what you make; I only need proof you've learned the skills.", 16, MUTED, true))
			var quest: Dictionary = Game.character["quest"]
			var caption: String = "Accept: A Foothold in Hearthmere"
			if bool(quest["started"]):
				caption = "Claim reward" if Game.quest_ready() else "Ask about my progress"
			if bool(quest["claimed"]):
				caption = "Ask about the road ahead"
			modal_content.add_child(_button(caption, _intent.bind("quest", {}), true))
			modal_content.add_child(_label("Reward: 75 coins and 40 XP in every skill.\nOpen Journal [J] for your objectives.", 16, GOLD, true))
			if bool(quest["started"]):
				for key: String in Catalog.QUEST_GOALS:
					modal_content.add_child(_label("%d / %d    %s" % [int(quest[key]), int(Catalog.QUEST_GOALS[key]), str(Catalog.QUEST_LABELS[key])], 15, MUTED, true))
		"forge", "campfire":
			if modal_kind == "campfire":
				modal_content.add_child(_button("Rest and restore health (free)", _intent.bind("rest", {}), true))
				modal_content.add_child(_label("Buy bait at the pond bucket, catch raw trout at Stillwater Pond, then cook them here. Each cooked trout restores up to 12 health.", 16, INK, true))
			else:
				modal_content.add_child(_label("1 copper + 1 tin = 1 bronze bar.\n3 bronze bars = 1 bronze sword.\nAfter forging, select the sword in your Bag and equip it.", 16, INK, true))
			for id: String in Catalog.RECIPES:
				var recipe: Dictionary = Catalog.RECIPES[id]
				if str(recipe["station"]) != modal_kind:
					continue
				modal_content.add_child(HSeparator.new())
				modal_content.add_child(_label(str(recipe["name"]), 20, GOLD))
				modal_content.add_child(_label("Requires " + Catalog.recipe_cost_text(recipe), 15, MUTED, true))
				var caption: String = "Make one  (+%d XP)" % int(recipe["xp"])
				var locked: bool = Game.skill_level(str(recipe["skill"])) < int(recipe["level"])
				var quest_locked: bool = bool(recipe.get("requires_frontier", false)) and not bool(Game.character["frontier"]["claimed"])
				if quest_locked:
					modal_content.add_child(_label("Complete Beyond the Old Watch to learn this recipe.", 15, GOLD, true))
				if locked:
					caption = "Requires %s level %d" % [str(recipe["skill"]), int(recipe["level"])]
				var button: Button = _button(caption, _intent.bind("recipe", {"id": id}))
				button.disabled = locked or quest_locked
				modal_content.add_child(button)
		"bank":
			modal_content.add_child(_label("Equipped gear and coins stay on your character. Bait stacks in one backpack slot; other items use one slot each.", 15, MUTED, true))
			modal_content.add_child(_button("Deposit entire backpack", _intent.bind("deposit_all", {}), true))
			for id: String in Catalog.ITEMS:
				var carried: int = Game.count_item(id)
				var stored: int = Game.count_item(id, true)
				if carried + stored == 0:
					continue
				modal_content.add_child(HSeparator.new())
				modal_content.add_child(_label("%s   |   Bag %d   /   Bank %d" % [Catalog.item_name(id), carried, stored], 16, INK, true))
				var row: HBoxContainer = HBoxContainer.new()
				modal_content.add_child(row)
				if carried > 0:
					row.add_child(_button("Deposit 1", _intent.bind("deposit", {"id": id, "amount": 1})))
				if stored > 0:
					row.add_child(_button("Withdraw 1", _intent.bind("withdraw", {"id": id, "amount": 1})))
					row.add_child(_button("Withdraw all", _intent.bind("withdraw", {"id": id, "amount": stored})))
		"bait_shop":
			modal_content.add_child(_label("FISH FROM THE POND", 20, GOLD))
			modal_content.add_child(_label("The bucket sells bait. Your starter rod is already included. Buy bait, return to the world, then click the water from any dry bank. Each click starts one cast; click again after the catch.", 17, INK, true))
			modal_content.add_child(_label("One bait per completed catch. No bait is spent when you stop early or cannot carry the fish. All bait shares one backpack slot.", 15, MUTED, true))
			modal_content.add_child(_label("Bait carried: %d  /  %d coin each" % [Game.count_item("fishing_bait"), Catalog.BAIT_PRICE], 18, GOLD))
			for amount: int in Catalog.BAIT_PACKS:
				var price: int = amount * Catalog.BAIT_PRICE
				var button: Button = _button("Buy %d bait  /  %d coins" % [amount, price], _intent.bind("buy_bait", {"amount": amount}), true)
				button.disabled = int(Game.character["coins"]) < price or not Game.can_add_item("fishing_bait", amount)
				modal_content.add_child(button)
			modal_content.add_child(_label("Need coins? Sell logs, ore or fish to Mara in the village. Bait in the bank must be withdrawn before fishing.", 15, MUTED, true))
		"market":
			modal_content.add_child(_button("Buy cooked trout  /  8 coins", _intent.bind("buy_food", {}), true))
			modal_content.add_child(_label("Sell surplus supplies. Your equipped weapon is not listed.", 15, MUTED, true))
			for id: String in Catalog.ITEMS:
				var amount: int = Game.count_item(id)
				if amount <= 0:
					continue
				var value: int = int(Catalog.ITEMS[id]["sell"])
				modal_content.add_child(_label("%s  x%d" % [Catalog.item_name(id), amount], 18, INK))
				var row: HBoxContainer = HBoxContainer.new()
				modal_content.add_child(row)
				row.add_child(_button("Sell 1  /  %d coins" % value, _intent.bind("sell", {"id": id, "amount": 1})))
				row.add_child(_button("Sell all  /  %d coins" % (value * amount), _intent.bind("sell", {"id": id, "amount": amount})))
	modal_scroll.set_deferred("scroll_vertical", previous_scroll)

func show_account_gate() -> void:
	Game.playing = false
	_new_modal("account", "FFD REALMS ACCOUNT", "Development login for the multiplayer test server. Offline play remains available.", 690, 760)
	modal_content.add_child(_label("SIGN IN", 20, GOLD))
	login_username = LineEdit.new()
	login_username.placeholder_text = "Username"
	login_username.max_length = 24
	login_username.text = Network.username
	login_username.custom_minimum_size.y = 40
	modal_content.add_child(login_username)
	login_password = LineEdit.new()
	login_password.placeholder_text = "Password"
	login_password.secret = true
	login_password.max_length = 128
	login_password.custom_minimum_size.y = 40
	modal_content.add_child(login_password)
	remember_check = CheckBox.new()
	remember_check.text = "Remember this login on this computer"
	remember_check.button_pressed = true
	modal_content.add_child(remember_check)
	modal_content.add_child(_button("Sign in", _account_sign_in, true))
	modal_content.add_child(HSeparator.new())
	modal_content.add_child(_label("CREATE TEST ACCOUNT", 20, GOLD))
	signup_email = LineEdit.new()
	signup_email.placeholder_text = "Email (optional unless updates are enabled)"
	signup_email.max_length = 160
	signup_email.custom_minimum_size.y = 40
	modal_content.add_child(signup_email)
	updates_check = CheckBox.new()
	updates_check.text = "Email me about future FFDRealms test builds and updates"
	updates_check.button_pressed = false
	modal_content.add_child(updates_check)
	modal_content.add_child(_label("Create account uses the username/password above. Passwords are sent only to the configured test server and are not saved by the game. Remember me stores a session token instead.", 13, MUTED, true))
	modal_content.add_child(_button("Create account", _account_register, true))
	modal_content.add_child(HSeparator.new())
	modal_content.add_child(_button("Play offline / local profiles", _account_offline))
	account_status = _label("Checking saved login..." if Network.account_checking else "Test server: " + Network.server_label(), 14, MUTED, true)
	modal_content.add_child(account_status)

func _account_sign_in() -> void:
	if account_busy:
		return
	account_busy = true
	account_status.text = "Signing in..."
	Network.sign_in(login_username.text, login_password.text, remember_check.button_pressed)

func _account_register() -> void:
	if account_busy:
		return
	account_busy = true
	account_status.text = "Creating account..."
	Network.register_account(login_username.text, login_password.text, signup_email.text, updates_check.button_pressed, remember_check.button_pressed)

func _account_offline() -> void:
	account_busy = false
	Network.use_offline_mode()
	show_menu()

func _on_account_result(action: String, result: Dictionary) -> void:
	account_busy = false
	if action == "open":
		return
	if bool(result.get("ok", false)):
		if action in ["login", "register"]:
			if is_instance_valid(login_password):
				login_password.text = ""
			show_menu()
		elif action == "subscription" and is_instance_valid(account_status):
			account_status.text = "Update-email preference saved."
	else:
		var error: String = str(result.get("error", "Request failed."))
		if is_instance_valid(account_status):
			account_status.text = error
		elif modal_kind == "menu" and is_instance_valid(menu_error):
			menu_error.text = error

func _on_account_changed() -> void:
	if modal_kind == "account" and Network.is_signed_in():
		show_menu()

func _on_multiplayer_changed() -> void:
	if modal_kind == "menu":
		show_menu()

func _menu_join_multiplayer() -> void:
	if Game.profile_slot < 1:
		menu_error.text = "Load an adventure slot before joining multiplayer."
		return
	if Network.join_multiplayer():
		menu_error.text = "Connecting to multiplayer presence test..."

func _menu_leave_multiplayer() -> void:
	Network.leave_multiplayer()
	show_menu()

func _show_account_settings() -> void:
	if not Network.is_signed_in():
		Network.exit_offline_mode()
		show_account_gate()
		return
	Game.playing = false
	_new_modal("account_settings", "ACCOUNT & UPDATES", "Signed in as " + Network.username, 650, 590)
	signup_email = LineEdit.new()
	signup_email.placeholder_text = "Email"
	signup_email.text = Network.email
	signup_email.max_length = 160
	signup_email.custom_minimum_size.y = 40
	modal_content.add_child(signup_email)
	updates_check = CheckBox.new()
	updates_check.text = "Email me about future FFDRealms test builds and updates"
	updates_check.button_pressed = Network.updates_opt_in
	modal_content.add_child(updates_check)
	modal_content.add_child(_label("The test server stores this address only when supplied. This build records consent, but it does not send email by itself yet.", 14, MUTED, true))
	account_status = _label("Multiplayer: " + Network.multiplayer_label(), 14, GOLD, true)
	modal_content.add_child(account_status)
	modal_content.add_child(_button("Save email preference", _save_account_subscription, true))
	modal_content.add_child(_button("Sign out", _account_sign_out))
	modal_content.add_child(_button("Back", show_menu))

func _save_account_subscription() -> void:
	Network.update_subscription(signup_email.text, updates_check.button_pressed)
	if is_instance_valid(account_status):
		account_status.text = "Saving..."

func _account_sign_out() -> void:
	Network.sign_out()
	show_account_gate()

func show_menu() -> void:
	Game.playing = false
	_new_modal("menu", "FFD REALMS", "MULTIPLAYER TEST  /  Hearthmere & Northreach  /  v" + Catalog.VERSION, 700, 790)
	modal_content.add_child(_label("Adventure profiles + authenticated presence test", 25, INK, true))
	if Network.is_signed_in():
		modal_content.add_child(_label("Account: %s   |   Multiplayer: %s" % [Network.username, Network.multiplayer_label()], 14, GOLD, true))
	else:
		modal_content.add_child(_label("Offline mode. Local adventure saves still work; multiplayer requires a test account.", 14, MUTED, true))
	if Game.profile_slot > 0:
		modal_content.add_child(_button("Resume adventure", resume_game, true))
		modal_content.add_child(_button("Customize current character", _menu_wardrobe))
		modal_content.add_child(_button("Save current profile", _intent.bind("save", {})))
	if Network.is_signed_in() and Game.profile_slot > 0:
		if Network.multiplayer_state == "offline":
			modal_content.add_child(_button("Join multiplayer presence test", _menu_join_multiplayer, true))
		else:
			modal_content.add_child(_button("Leave multiplayer test", _menu_leave_multiplayer))
	modal_content.add_child(_button("Account & email updates", _show_account_settings))
	modal_content.add_child(HSeparator.new())
	modal_content.add_child(_label("ADVENTURE SLOTS", 14, GOLD))
	slot_input = OptionButton.new()
	slot_input.custom_minimum_size.y = 40
	for slot: int in range(1, 4):
		var summary: Dictionary = Saves.profile_summary(slot)
		var caption: String = "Slot %d  /  %s" % [slot, str(summary.get("name", "Empty"))]
		if bool(summary.get("recovered", false)):
			caption += "  (backup)"
		slot_input.add_item(caption)
	if Game.profile_slot > 0:
		slot_input.select(Game.profile_slot - 1)
	slot_input.item_selected.connect(_slot_selected)
	modal_content.add_child(slot_input)
	name_input = LineEdit.new()
	name_input.placeholder_text = "Character name for a new/replaced adventure"
	name_input.max_length = 16
	name_input.custom_minimum_size.y = 40
	modal_content.add_child(name_input)
	_slot_selected(slot_input.selected)
	modal_content.add_child(_button("Play / continue selected slot", _play_selected, true))
	modal_content.add_child(_button("Start fresh in selected slot...", _confirm_new))
	menu_error = _label("Saved slots keep their own character name. The name box is used only when creating or replacing a slot.", 14, MUTED, true)
	modal_content.add_child(menu_error)
	modal_content.add_child(_button("Quit application", request_quit))

func _slot_selected(index: int) -> void:
	if not is_instance_valid(name_input):
		return
	var slot: int = index + 1
	var summary: Dictionary = Saves.profile_summary(slot)
	if bool(summary.get("exists", false)):
		name_input.text = str(summary.get("name", "Adventurer"))
		name_input.tooltip_text = "Continuing this slot always uses its saved name. Edit this only if you choose Start fresh."
	else:
		name_input.text = ""
		name_input.tooltip_text = "Choose the character name for this new adventure."

func _play_selected() -> void:
	# Save the current adventure before switching slots; abort on a write failure.
	if Game.profile_slot > 0 and not Game.save_game(false):
		return
	var slot: int = slot_input.selected + 1
	var creating: bool = not Saves.exists(slot)
	if Network.multiplayer_state != "offline":
		Network.leave_multiplayer()
	if Game.begin_game(slot, name_input.text, false):
		_remove_menu()
		if creating:
			show_wardrobe()

func _confirm_new() -> void:
	if Game.profile_slot > 0 and not Game.save_game(false):
		return
	if not Saves.exists(slot_input.selected + 1):
		_start_fresh()
		return
	if is_instance_valid(new_confirm):
		new_confirm.queue_free()
	new_confirm = ConfirmationDialog.new()
	new_confirm.title = "Replace selected adventure?"
	new_confirm.dialog_text = "Start a new character in slot %d?\nThis replaces that slot's progress. Other slots are unchanged." % (slot_input.selected + 1)
	new_confirm.confirmed.connect(_start_fresh)
	root.add_child(new_confirm)
	new_confirm.popup_centered(Vector2i(510, 210))

func _start_fresh() -> void:
	if Network.multiplayer_state != "offline":
		Network.leave_multiplayer()
	if Game.begin_game(slot_input.selected + 1, name_input.text, true):
		_remove_menu()
		show_wardrobe()

func _remove_menu() -> void:
	if is_instance_valid(overlay):
		root.remove_child(overlay)
		overlay.queue_free()
	overlay = null
	modal_kind = ""
	Game.playing = true
	refresh()

func resume_game() -> void:
	if Game.profile_slot > 0:
		_remove_menu()

func request_quit() -> void:
	if Game.profile_slot > 0 and not Game.save_game(false):
		return
	get_tree().quit()

func _menu_wardrobe() -> void:
	resume_game()
	show_wardrobe()

func show_wardrobe() -> void:
	if not Game.playing or Game.profile_slot < 1 or modal_kind == "wardrobe":
		return
	if not Layout.is_safe(Game.position_of_player()):
		add_message("Visit Hearthmere or Northreach Camp to change your appearance.")
		return
	Game.cancel_action(false)
	_new_modal("wardrobe", "Character appearance", "Individual dyes, fabrics and details. Changes apply only after Save appearance.", 890, 795)
	wardrobe_editor = Wardrobe.new()
	modal_content.add_child(wardrobe_editor)
	wardrobe_editor.build(Game.character.get("appearance", {}))
	wardrobe_editor.apply_requested.connect(_save_appearance)

func _save_appearance(look: Dictionary) -> void:
	if modal_kind == "wardrobe" and Game.dispatch("appearance", {"look": look}):
		close_modal()

func show_map() -> void:
	if not Game.playing:
		return
	Game.cancel_action(false)
	_new_modal("map", "Hearthmere & Northreach — Terrain Map", "Land colors match the world. Shading and contour lines show elevation. Hover land for its region and height.", 670, 780)
	var routes: HBoxContainer = HBoxContainer.new()
	modal_content.add_child(routes)
	routes.add_child(_button("Walk to village", _map_chosen.bind("move", {"pos": Vector3(0, 0, 8)})))
	routes.add_child(_button("Walk to Northreach", _map_chosen.bind("move", {"pos": Vector3(-14, 0, -33)})))
	var map = MapView.new()
	map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map.destination_chosen.connect(_map_chosen)
	modal_content.add_child(map)
	modal_content.add_child(_label("Green: trees   /   Stone: ore   /   Red: moving enemies\nGold ring: your character. Pale green outline: safe towns.\nTerrain colors: meadow, woodland, rocky ridges, paths and water.\nNorth is the top of this map.", 14, MUTED, true))

func _map_chosen(verb: String, payload: Dictionary) -> void:
	close_modal()
	Game.dispatch(verb, payload)

func show_help() -> void:
	if not Game.playing:
		return
	Game.cancel_action(false)
	_new_modal("help", "Controls & first test", "Desktop prototype  /  No controller or mobile build yet")
	modal_content.add_child(_label("Left-click ground  /  Walk there\nShift + left-click  /  Move even over an enemy\nLeft-click a target  /  Approach and perform ONE action\nQ and E  /  Rotate the camera\nMiddle or right mouse drag  /  Orbit\nMouse wheel  /  Zoom\nM  /  World map\nC  /  Character appearance (in safe towns)\nI  /  Toggle backpack\nJ  /  Journal\nF  /  Eat cooked trout\nSpace  /  Cancel your action (enemies can still retaliate)\nEscape  /  Close a panel or pause\nF5 or Save button  /  Save", 18, INK, true))
	modal_content.add_child(HSeparator.new())
	modal_content.add_child(_label("The first adventure\n1. Accept Elin's quest.\n2. Chop 5 pine logs.\n3. Mine 3 copper and 3 tin.\n4. Smelt 3 bars; forge and equip a bronze sword.\n5. Buy 3 bait from the pond bucket; click the water once per catch for 3 trout, then cook them at the fire.\n6. Click once per attack to defeat the three mosslings at the northern watch.\n7. Return to Elin and claim your reward.", 17, GOLD, true))
	modal_content.add_child(_label("Each gathering or combat click starts ONE action. Player strikes land after 0.35s; a separate 0.95s cooldown prevents cancel-spam. Move at any time; moving before impact cancels your hit. Click again when the weapon is ready. Early clicks do not queue; holding a button does not repeat. Cooking and smithing make one item per button click. Enemies pursue, face you, wind up and reposition. Moving just outside melee range is not enough to end a fight: retreat beyond their home radius or into a safe camp. Returning enemies cannot be attacked and recover fully at home. Enemies engage when you approach in the wild and have clear sight. Orange strike sectors lock direction when a windup starts: step sideways, behind the enemy or out of reach before impact to dodge. Wait for the MISSED or damage result before stepping back into the area. Shift + left-click forces a movement click through enemy pick boxes. Safe towns still block engagement and damage. All services are outside. Houses are decorative and cannot be entered in this build. Death returns you to the square and costs up to 10 coins; items are retained. Resource and monster timers restart when you load a profile. Northreach Camp has a shared bank, forge, food seller, campfire and Ranger Tamsin.", 15, MUTED, true))

func set_hover(text: String, mouse_position: Vector2) -> void:
	hover_label.visible = not text.is_empty() and modal_kind.is_empty()
	hover_label.text = text
	var available: Vector2 = root.size
	hover_label.position = Vector2(minf(mouse_position.x + 18, available.x - 310), minf(mouse_position.y + 22, available.y - 140))

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key: InputEventKey = event
	if not key.pressed or key.echo:
		return
	if modal_kind == "menu":
		if key.keycode == KEY_ESCAPE and Game.profile_slot > 0:
			resume_game()
		return
	if modal_kind == "wardrobe":
		if key.keycode == KEY_ESCAPE:
			close_modal()
		get_viewport().set_input_as_handled()
		return
	match key.keycode:
		KEY_C: show_wardrobe()
		KEY_ESCAPE:
			if not modal_kind.is_empty():
				close_modal()
			else:
				show_menu()
		KEY_M: show_map()
		KEY_I: toggle_bag()
		KEY_J: select_tab("journal")
		KEY_F: Game.dispatch("eat")
		KEY_SPACE: Game.dispatch("cancel")
		KEY_F5: Game.dispatch("save")
		_: return
	get_viewport().set_input_as_handled()
