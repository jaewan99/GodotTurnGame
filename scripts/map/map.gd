## Map
## Radial mind-map floor. Generates the graph, draws connection lines,
## spawns node buttons, and manages traversal (which nodes are reachable).
##
## Traversal rule: a node is reachable if it is connected to at least one
## already-visited node and has not been visited itself.
class_name MapScene
extends Control

const BATTLE_SCENE := "res://scenes/map/battlefield.tscn"

## Forge success rate (%) indexed by the card's current level before the attempt.
## Level 0→1: 100%, 1→2: 80%, 2→3: 65%, 3→4: 50%, 4→5: 35%, 5→6: 20%, 6+: 10%
const FORGE_SUCCESS_RATES := [100, 80, 65, 50, 35, 20, 10]
const FORGE_BASE_COST  := 50   # coins × (level + 1)
const REMOVE_BASE_COST := 50   # coins × (cards_removed + 1)

var _nodes: Array[MapNode] = []
var _uis: Dictionary = {}   # node id -> MapNodeUI
var _coins_label: Label = null
## Items selected for merging in the inventory overlay.
var _merge_sel: Array = []


func _ready() -> void:
	_add_background()
	if GameState.has_map():
		_nodes = GameState.map_nodes
	else:
		_nodes = MapGenerator.generate()
		GameState.map_nodes = _nodes
	_spawn_uis()
	_refresh()
	queue_redraw()
	_add_coins_label()
	_add_inventory_button()
	_add_floor_indicator()


# ── Drawing ───────────────────────────────────────────────────────────────────

func _draw() -> void:
	for node in _nodes:
		for cid in node.connections:
			if cid <= node.id:   # draw each edge once
				continue
			var other: MapNode = _nodes[cid]
			var traveled := node.visited and other.visited
			var col := Color(0.75, 0.75, 0.75, 0.85) if traveled \
					else Color(0.40, 0.40, 0.40, 0.55)
			draw_line(node.pos, other.pos, col, 2.0, true)


# ── Internal ──────────────────────────────────────────────────────────────────

func _add_background() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.09, 0.07)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	move_child(bg, 0)


func _spawn_uis() -> void:
	for node in _nodes:
		var ui := MapNodeUI.new()
		add_child(ui)
		ui.setup(node)
		ui.node_clicked.connect(_on_node_clicked)
		_uis[node.id] = ui


func _refresh() -> void:
	var reachable: Array[int] = []
	for node in _nodes:
		if not node.visited:
			continue
		for cid in node.connections:
			if not _nodes[cid].visited and cid not in reachable:
				reachable.append(cid)

	for node in _nodes:
		(_uis[node.id] as MapNodeUI).refresh(node.id in reachable)


func _on_node_clicked(node: MapNode) -> void:
	node.visited = true
	_refresh()
	queue_redraw()

	match node.type:
		MapNode.Type.FIGHT, MapNode.Type.ELITE, MapNode.Type.BOSS:
			GameState.current_node_id = node.id
			get_tree().change_scene_to_file(BATTLE_SCENE)
		MapNode.Type.REST:
			_show_toast("Rest — heal or upgrade (not yet implemented)")
		MapNode.Type.SHOP:
			_show_toast("Shop (not yet implemented)")
		MapNode.Type.EVENT:
			_show_event_overlay()


func _add_coins_label() -> void:
	_coins_label = Label.new()
	_coins_label.name = "CoinsLabel"
	_coins_label.add_theme_font_size_override("font_size", 24)
	_coins_label.modulate = Color(1.0, 0.85, 0.1)
	_coins_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_coins_label.offset_left   =  20.0
	_coins_label.offset_top    =  16.0
	_coins_label.offset_right  = 320.0
	_coins_label.offset_bottom =  56.0
	_coins_label.text = "Coins: %d" % GameState.coins
	add_child(_coins_label)


func _refresh_coins_label() -> void:
	if is_instance_valid(_coins_label):
		_coins_label.text = "Coins: %d" % GameState.coins


func _show_toast(msg: String) -> void:
	var lbl := Label.new()
	lbl.text = msg
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	lbl.set_anchors_preset(Control.PRESET_CENTER)
	lbl.offset_left   = -300.0
	lbl.offset_right  =  300.0
	lbl.offset_top    = -30.0
	lbl.offset_bottom =  30.0
	add_child(lbl)
	await get_tree().create_timer(2.0).timeout
	if is_instance_valid(lbl):
		lbl.queue_free()


# ── Event overlay ─────────────────────────────────────────────────────────────

func _show_event_overlay() -> void:
	var overlay := CanvasLayer.new()
	overlay.layer = 10
	add_child(overlay)

	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 0.82)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(bg)

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(root)

	_build_event_choice(root, overlay)


func _build_event_choice(root: Control, overlay: CanvasLayer) -> void:
	_clear_children(root)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.offset_left   = -300.0
	vbox.offset_right  =  300.0
	vbox.offset_top    = -280.0
	vbox.offset_bottom =  280.0
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 18)
	root.add_child(vbox)

	var title := Label.new()
	title.text = "Event"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 52)
	title.modulate = Color(0.85, 0.55, 1.0)
	vbox.add_child(title)

	var desc := Label.new()
	desc.text = "A wandering blacksmith offers his services."
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.add_theme_font_size_override("font_size", 19)
	desc.modulate = Color(0.78, 0.78, 0.78)
	vbox.add_child(desc)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 8)
	vbox.add_child(spacer)

	var forge_btn := Button.new()
	forge_btn.text = "Forge a Card  (%d+ coins)" % FORGE_BASE_COST
	forge_btn.add_theme_font_size_override("font_size", 22)
	forge_btn.custom_minimum_size = Vector2(0, 54)
	forge_btn.pressed.connect(func():
		_build_forge_select(root, overlay)
	)
	vbox.add_child(forge_btn)

	var remove_cost := REMOVE_BASE_COST * (GameState.cards_removed + 1)
	var remove_btn := Button.new()
	remove_btn.text = "Remove a Card  (%d coins)" % remove_cost
	remove_btn.add_theme_font_size_override("font_size", 22)
	remove_btn.custom_minimum_size = Vector2(0, 54)
	remove_btn.pressed.connect(func():
		_build_remove_select(root, overlay)
	)
	vbox.add_child(remove_btn)

	var scavenge_btn := Button.new()
	scavenge_btn.text = "Scavenge Ruins  (find random equipment)"
	scavenge_btn.add_theme_font_size_override("font_size", 22)
	scavenge_btn.custom_minimum_size = Vector2(0, 54)
	scavenge_btn.pressed.connect(func():
		_build_scavenge_result(root, overlay)
	)
	vbox.add_child(scavenge_btn)

	var leave_btn := Button.new()
	leave_btn.text = "Leave"
	leave_btn.add_theme_font_size_override("font_size", 18)
	leave_btn.modulate = Color(0.65, 0.65, 0.65)
	leave_btn.pressed.connect(func(): overlay.queue_free())
	vbox.add_child(leave_btn)


func _build_forge_select(root: Control, overlay: CanvasLayer) -> void:
	_clear_children(root)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left   = 80.0
	vbox.offset_right  = -80.0
	vbox.offset_top    = 50.0
	vbox.offset_bottom = -50.0
	vbox.add_theme_constant_override("separation", 10)
	root.add_child(vbox)

	var title := Label.new()
	title.text = "Forge a Card"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 38)
	title.modulate = Color(1.0, 0.82, 0.2)
	vbox.add_child(title)

	var sub := Label.new()
	sub.text = "+2 damage on success. Coins spent either way."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 17)
	sub.modulate = Color(0.72, 0.72, 0.72)
	vbox.add_child(sub)

	var coins_row := HBoxContainer.new()
	coins_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(coins_row)
	var coins_lbl := Label.new()
	coins_lbl.add_theme_font_size_override("font_size", 19)
	coins_lbl.modulate = Color(1.0, 0.85, 0.1)
	coins_lbl.text = "Your coins: %d" % GameState.coins
	coins_row.add_child(coins_lbl)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	var grid := VBoxContainer.new()
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("separation", 6)
	scroll.add_child(grid)

	for card in GameState.deck:
		var cost := FORGE_BASE_COST * (card.level + 1)
		var rate: int = FORGE_SUCCESS_RATES[mini(card.level, FORGE_SUCCESS_RATES.size() - 1)]
		var can_afford := GameState.coins >= cost

		var btn := Button.new()
		btn.text = "%-18s  Dmg: %2d  Lv.%d  →  Cost: %dg  |  Success: %d%%" % [
			card.card_name, card.damage, card.level, cost, rate
		]
		btn.add_theme_font_size_override("font_size", 16)
		btn.custom_minimum_size = Vector2(0, 44)
		btn.disabled = not can_afford
		if not can_afford:
			btn.modulate = Color(0.5, 0.5, 0.5)

		var captured_card := card
		var captured_cost := cost
		var captured_rate := rate
		btn.pressed.connect(func():
			GameState.coins -= captured_cost
			_refresh_coins_label()
			var succeeded := (randi() % 100) < captured_rate
			if succeeded:
				captured_card.damage += 2
			captured_card.level += 1
			_build_forge_result(captured_card, succeeded, root, overlay)
		)
		grid.add_child(btn)

	var back_btn := Button.new()
	back_btn.text = "Back"
	back_btn.add_theme_font_size_override("font_size", 17)
	back_btn.pressed.connect(func(): _build_event_choice(root, overlay))
	vbox.add_child(back_btn)


func _build_forge_result(card: CardData, succeeded: bool, root: Control, overlay: CanvasLayer) -> void:
	_clear_children(root)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.offset_left   = -360.0
	vbox.offset_right  =  360.0
	vbox.offset_top    = -180.0
	vbox.offset_bottom =  180.0
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 22)
	root.add_child(vbox)

	var result_lbl := Label.new()
	result_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_lbl.add_theme_font_size_override("font_size", 44)
	if succeeded:
		result_lbl.text = "Forge successful!"
		result_lbl.modulate = Color(0.25, 1.0, 0.45)
	else:
		result_lbl.text = "The forge sputters..."
		result_lbl.modulate = Color(1.0, 0.38, 0.28)
	vbox.add_child(result_lbl)

	var detail_lbl := Label.new()
	detail_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail_lbl.add_theme_font_size_override("font_size", 22)
	if succeeded:
		detail_lbl.text = "%s  →  Damage: %d   (Lv.%d)" % [card.card_name, card.damage, card.level]
	else:
		detail_lbl.text = "%s is unchanged.   (Lv.%d)" % [card.card_name, card.level]
	vbox.add_child(detail_lbl)

	var coins_lbl := Label.new()
	coins_lbl.text = "Coins remaining: %d" % GameState.coins
	coins_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	coins_lbl.add_theme_font_size_override("font_size", 18)
	coins_lbl.modulate = Color(1.0, 0.85, 0.1)
	vbox.add_child(coins_lbl)

	var ok_btn := Button.new()
	ok_btn.text = "Continue"
	ok_btn.add_theme_font_size_override("font_size", 20)
	ok_btn.custom_minimum_size = Vector2(160, 0)
	ok_btn.pressed.connect(func(): overlay.queue_free())
	vbox.add_child(ok_btn)


func _build_remove_select(root: Control, overlay: CanvasLayer) -> void:
	_clear_children(root)

	var remove_cost := REMOVE_BASE_COST * (GameState.cards_removed + 1)
	var can_afford  := GameState.coins >= remove_cost
	var safe_to_remove := GameState.deck.size() > 1

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left   = 80.0
	vbox.offset_right  = -80.0
	vbox.offset_top    = 50.0
	vbox.offset_bottom = -50.0
	vbox.add_theme_constant_override("separation", 10)
	root.add_child(vbox)

	var title := Label.new()
	title.text = "Remove a Card"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 38)
	title.modulate = Color(1.0, 0.38, 0.38)
	vbox.add_child(title)

	var info_lbl := Label.new()
	info_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info_lbl.add_theme_font_size_override("font_size", 19)
	info_lbl.modulate = Color(1.0, 0.85, 0.1)
	info_lbl.text = "Cost: %d coins  (You have: %d)" % [remove_cost, GameState.coins]
	vbox.add_child(info_lbl)

	if not can_afford:
		var warn := Label.new()
		warn.text = "Not enough coins!"
		warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		warn.add_theme_font_size_override("font_size", 17)
		warn.modulate = Color(1.0, 0.3, 0.3)
		vbox.add_child(warn)
	elif not safe_to_remove:
		var warn := Label.new()
		warn.text = "Your deck only has one card — cannot remove."
		warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		warn.add_theme_font_size_override("font_size", 17)
		warn.modulate = Color(1.0, 0.6, 0.2)
		vbox.add_child(warn)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	var grid := VBoxContainer.new()
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("separation", 6)
	scroll.add_child(grid)

	for card in GameState.deck:
		var btn := Button.new()
		btn.text = "%-18s  Dmg: %2d  Lv.%d" % [card.card_name, card.damage, card.level]
		btn.add_theme_font_size_override("font_size", 16)
		btn.custom_minimum_size = Vector2(0, 44)
		btn.disabled = not can_afford or not safe_to_remove
		if not (can_afford and safe_to_remove):
			btn.modulate = Color(0.5, 0.5, 0.5)

		var captured_card := card
		btn.pressed.connect(func():
			GameState.coins -= remove_cost
			GameState.cards_removed += 1
			GameState.deck.erase(captured_card)
			_refresh_coins_label()
			overlay.queue_free()
		)
		grid.add_child(btn)

	var back_btn := Button.new()
	back_btn.text = "Back"
	back_btn.add_theme_font_size_override("font_size", 17)
	back_btn.pressed.connect(func(): _build_event_choice(root, overlay))
	vbox.add_child(back_btn)


func _equipment_stat_summary(ed: EquipmentData) -> String:
	if ed.damage_bonus    > 0: return "(+%d dmg)"       % ed.damage_bonus
	if ed.block_per_turn  > 0: return "(+%d blk/rnd)"   % ed.block_per_turn
	if ed.max_hp_bonus    > 0: return "(+%d HP)"        % ed.max_hp_bonus
	if ed.max_energy_bonus > 0: return "(+%d energy)"  % ed.max_energy_bonus
	if ed.crit_chance     > 0: return "(+%d%% crit)"   % ed.crit_chance
	return ""


# ── Scavenge event option ─────────────────────────────────────────────────────

func _build_scavenge_result(root: Control, overlay: CanvasLayer) -> void:
	_clear_children(root)

	# 70 % equipment, 30 % scroll
	if randi() % 10 < 3:
		_build_scavenge_scroll_result(root, overlay)
		return

	var pool: Array = EquipmentData.all().duplicate()
	pool.shuffle()
	var ed := (pool[0] as EquipmentData).duplicate()

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.offset_left   = -360.0
	vbox.offset_right  =  360.0
	vbox.offset_top    = -240.0
	vbox.offset_bottom =  240.0
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 16)
	root.add_child(vbox)

	var title := Label.new()
	title.text = "You found equipment!"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	title.modulate = Color(0.9, 0.75, 0.2)
	vbox.add_child(title)

	var slot_labels := {0: "Weapon", 1: "Offhand", 2: "Chest", 3: "Helm", 4: "Shoes"}
	var slot_colors := {
		0: Color(0.90, 0.50, 0.20),
		1: Color(0.25, 0.56, 0.88),
		2: Color(0.25, 0.75, 0.45),
		3: Color(0.65, 0.25, 0.88),
		4: Color(0.20, 0.80, 0.85),
	}
	var slot_color: Color = slot_colors.get(ed.slot, Color(0.7, 0.7, 0.7))
	var rarity_col := EquipmentData.rarity_color(ed.rarity)

	var rarity_lbl := Label.new()
	rarity_lbl.text = EquipmentData.rarity_name(ed.rarity)
	rarity_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rarity_lbl.add_theme_font_size_override("font_size", 16)
	rarity_lbl.modulate = rarity_col
	vbox.add_child(rarity_lbl)

	var type_lbl := Label.new()
	type_lbl.text = slot_labels.get(ed.slot, "Equipment")
	type_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	type_lbl.add_theme_font_size_override("font_size", 16)
	type_lbl.modulate = slot_color
	vbox.add_child(type_lbl)

	var name_lbl := Label.new()
	name_lbl.text = ed.equipment_name
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 30)
	vbox.add_child(name_lbl)

	var stat_lbl := Label.new()
	stat_lbl.text = _equipment_stat_summary(ed)
	stat_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stat_lbl.add_theme_font_size_override("font_size", 20)
	stat_lbl.modulate = Color(0.9, 0.9, 0.6)
	vbox.add_child(stat_lbl)

	var existing := GameState.equipment.get(ed.slot) as EquipmentData
	if existing != null:
		var replace_lbl := Label.new()
		replace_lbl.text = "Replaces: %s" % existing.equipment_name
		replace_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		replace_lbl.add_theme_font_size_override("font_size", 15)
		replace_lbl.modulate = Color(0.7, 0.5, 0.5)
		vbox.add_child(replace_lbl)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 8)
	vbox.add_child(spacer)

	var take_btn := Button.new()
	take_btn.text = "Take it"
	take_btn.add_theme_font_size_override("font_size", 20)
	take_btn.custom_minimum_size = Vector2(160, 0)
	take_btn.pressed.connect(func():
		var old := GameState.equipment.get(ed.slot) as EquipmentData
		if old != null:
			GameState.inventory.append(old)
		GameState.equipment[ed.slot] = ed

		overlay.queue_free()
	)
	vbox.add_child(take_btn)

	var stash_btn := Button.new()
	stash_btn.text = "Add to inventory"
	stash_btn.add_theme_font_size_override("font_size", 17)
	stash_btn.pressed.connect(func():
		GameState.inventory.append(ed)
		overlay.queue_free()
	)
	vbox.add_child(stash_btn)

	var leave_btn := Button.new()
	leave_btn.text = "Leave it"
	leave_btn.add_theme_font_size_override("font_size", 16)
	leave_btn.modulate = Color(0.65, 0.65, 0.65)
	leave_btn.pressed.connect(func(): overlay.queue_free())
	vbox.add_child(leave_btn)


# ── Inventory button ──────────────────────────────────────────────────────────

func _add_inventory_button() -> void:
	var btn := Button.new()
	btn.text = "Inventory"
	btn.add_theme_font_size_override("font_size", 18)
	btn.set_anchors_preset(Control.PRESET_TOP_LEFT)
	btn.offset_left   =  20.0
	btn.offset_top    =  60.0
	btn.offset_right  = 170.0
	btn.offset_bottom =  96.0
	btn.pressed.connect(_show_inventory_overlay)
	add_child(btn)


# ── Floor progress indicator ──────────────────────────────────────────────────

func _add_floor_indicator() -> void:
	var hbox := HBoxContainer.new()
	hbox.set_anchors_preset(Control.PRESET_TOP_WIDE)
	hbox.offset_top    =  10.0
	hbox.offset_bottom =  50.0
	hbox.alignment     = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 8)
	add_child(hbox)

	for i in GameState.MAX_FLOORS:
		var floor_num := i + 1

		if i > 0:
			var arrow := Label.new()
			arrow.text = "→"
			arrow.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
			arrow.add_theme_font_size_override("font_size", 16)
			arrow.add_theme_color_override("font_color", Color(0.38, 0.38, 0.40))
			hbox.add_child(arrow)

		var panel := PanelContainer.new()
		var style := StyleBoxFlat.new()
		style.corner_radius_top_left     = 5
		style.corner_radius_top_right    = 5
		style.corner_radius_bottom_left  = 5
		style.corner_radius_bottom_right = 5
		style.set_border_width_all(2)

		var lbl := Label.new()
		lbl.add_theme_font_size_override("font_size", 13)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
		lbl.custom_minimum_size  = Vector2(100, 0)

		if floor_num < GameState.floor:
			style.bg_color     = Color(0.12, 0.28, 0.12)
			style.border_color = Color(0.25, 0.55, 0.25)
			lbl.text = "✓  Floor %d" % floor_num
			lbl.add_theme_color_override("font_color", Color(0.50, 0.85, 0.50))
		elif floor_num == GameState.floor:
			style.bg_color     = Color(0.38, 0.26, 0.03)
			style.border_color = Color(0.95, 0.78, 0.15)
			lbl.text = "★  Floor %d" % floor_num
			lbl.add_theme_color_override("font_color", Color(1.00, 0.88, 0.20))
		else:
			style.bg_color     = Color(0.10, 0.10, 0.12)
			style.border_color = Color(0.22, 0.22, 0.24)
			lbl.text = "Floor %d" % floor_num
			lbl.add_theme_color_override("font_color", Color(0.35, 0.35, 0.37))

		panel.add_theme_stylebox_override("panel", style)
		panel.add_child(lbl)
		hbox.add_child(panel)


# ── Inventory overlay ─────────────────────────────────────────────────────────

func _show_inventory_overlay() -> void:
	var overlay := CanvasLayer.new()
	overlay.layer = 10
	add_child(overlay)

	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 0.88)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(bg)

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(root)

	_merge_sel.clear()
	_build_inventory_view(root, overlay)


func _build_inventory_view(root: Control, overlay: CanvasLayer) -> void:
	_clear_children(root)
	# Sanitise merge selection — items may have been removed by prior actions.
	_merge_sel = _merge_sel.filter(func(i): return GameState.inventory.has(i))

	var panel := Panel.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left   = -490.0
	panel.offset_right  =  490.0
	panel.offset_top    = -370.0
	panel.offset_bottom =  370.0
	root.add_child(panel)

	var outer := VBoxContainer.new()
	outer.set_anchors_preset(Control.PRESET_FULL_RECT)
	outer.offset_left = 14; outer.offset_right  = -14
	outer.offset_top  = 10; outer.offset_bottom = -10
	outer.add_theme_constant_override("separation", 6)
	panel.add_child(outer)

	# Header
	var hdr := HBoxContainer.new()
	outer.add_child(hdr)

	var title_lbl := Label.new()
	title_lbl.text = "INVENTORY"
	title_lbl.add_theme_font_size_override("font_size", 26)
	title_lbl.modulate = Color(0.88, 0.82, 1.0)
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr.add_child(title_lbl)

	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.add_theme_font_size_override("font_size", 16)
	close_btn.pressed.connect(func():
		_merge_sel.clear()
		overlay.queue_free()
	)
	hdr.add_child(close_btn)

	outer.add_child(HSeparator.new())

	# Scrollable content
	var scr := ScrollContainer.new()
	scr.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(scr)

	var cv := VBoxContainer.new()
	cv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cv.add_theme_constant_override("separation", 5)
	scr.add_child(cv)

	_inv_section_equipped(cv, root, overlay)
	cv.add_child(HSeparator.new())
	_inv_section_items(cv, root, overlay)
	cv.add_child(HSeparator.new())
	_inv_section_scrolls(cv, root, overlay)


# ── Inventory: Equipped section ───────────────────────────────────────────────

func _inv_section_equipped(cv: VBoxContainer, root: Control, overlay: CanvasLayer) -> void:
	var hdr := _inv_section_label("EQUIPPED")
	cv.add_child(hdr)

	var slot_names := {0: "Weapon ", 1: "Offhand", 2: "Chest  ", 3: "Helm   ", 4: "Shoes  "}
	for slot_int in [0, 1, 2, 3, 4]:
		var ed := GameState.equipment.get(slot_int) as EquipmentData
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		cv.add_child(row)

		var info := Label.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_theme_font_size_override("font_size", 14)
		if ed != null:
			info.text = "%s  %s  [%s]  %s" % [
				slot_names.get(slot_int, "?"),
				ed.equipment_name,
				EquipmentData.rarity_name(ed.rarity),
				_equipment_stat_summary(ed),
			]
			info.modulate = EquipmentData.rarity_color(ed.rarity)
		else:
			info.text = "%s  —" % slot_names.get(slot_int, "?")
			info.modulate = Color(0.45, 0.45, 0.45)
		row.add_child(info)

		# Unequip button — moves item to inventory
		if ed != null:
			var unequip_btn := Button.new()
			unequip_btn.text = "Unequip"
			unequip_btn.add_theme_font_size_override("font_size", 13)
			var captured_slot: int = slot_int
			var captured_ed   := ed
			unequip_btn.pressed.connect(func():
				GameState.equipment.erase(captured_slot)
				GameState.inventory.append(captured_ed)
		
				_build_inventory_view(root, overlay)
			)
			row.add_child(unequip_btn)

		# Swap button — shows matching inventory items
		var matching := GameState.inventory.filter(
			func(i): return (i as EquipmentData) != null and (i as EquipmentData).slot == slot_int
		)
		var swap_btn := Button.new()
		swap_btn.text = "Swap"
		swap_btn.add_theme_font_size_override("font_size", 13)
		swap_btn.disabled = matching.is_empty()
		var captured_slot2: int = slot_int
		swap_btn.pressed.connect(func():
			_build_slot_picker(captured_slot2, root, overlay)
		)
		row.add_child(swap_btn)


# ── Inventory: Items section ──────────────────────────────────────────────────

func _inv_section_items(cv: VBoxContainer, root: Control, overlay: CanvasLayer) -> void:
	var count := GameState.inventory.size()
	cv.add_child(_inv_section_label("ITEMS  (%d)" % count))

	if count == 0:
		var empty_lbl := Label.new()
		empty_lbl.text = "No items in inventory."
		empty_lbl.modulate = Color(0.5, 0.5, 0.5)
		empty_lbl.add_theme_font_size_override("font_size", 13)
		cv.add_child(empty_lbl)
		return

	var hint := Label.new()
	hint.text = "Select 3 of the same rarity to merge them."
	hint.add_theme_font_size_override("font_size", 13)
	hint.modulate = Color(0.65, 0.65, 0.65)
	cv.add_child(hint)

	for item in GameState.inventory:
		var ed := item as EquipmentData
		if ed == null:
			continue
		var selected := _merge_sel.has(ed)

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		if selected:
			row.modulate = Color(1.3, 1.3, 0.7)
		cv.add_child(row)

		var info := Label.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_theme_font_size_override("font_size", 14)
		info.text = "%s  [%s]  %s" % [
			ed.equipment_name,
			EquipmentData.rarity_name(ed.rarity),
			_equipment_stat_summary(ed),
		]
		info.modulate = EquipmentData.rarity_color(ed.rarity)
		row.add_child(info)

		# Equip button
		var equip_btn := Button.new()
		equip_btn.text = "Equip"
		equip_btn.add_theme_font_size_override("font_size", 13)
		var cap_ed := ed
		equip_btn.pressed.connect(func():
			var old := GameState.equipment.get(cap_ed.slot) as EquipmentData
			if old != null:
				GameState.inventory.append(old)
			GameState.equipment[cap_ed.slot] = cap_ed
			GameState.inventory.erase(cap_ed)
			_merge_sel.erase(cap_ed)
	
			_build_inventory_view(root, overlay)
		)
		row.add_child(equip_btn)

		# Select/Deselect for merge
		var sel_btn := Button.new()
		sel_btn.text = "Deselect" if selected else "Select"
		sel_btn.add_theme_font_size_override("font_size", 13)
		var cap_ed2 := ed
		sel_btn.pressed.connect(func():
			if _merge_sel.has(cap_ed2):
				_merge_sel.erase(cap_ed2)
			else:
				_merge_sel.append(cap_ed2)
			_build_inventory_view(root, overlay)
		)
		row.add_child(sel_btn)

	# Merge button — only enabled when selection is valid
	if _is_valid_merge():
		var src_rarity: EquipmentData.Rarity = _merge_sel[0].rarity
		var next_name := EquipmentData.rarity_name(src_rarity + 1)
		var merge_btn := Button.new()
		merge_btn.text = "Merge 3 %s  →  %s  (80%%)" % [
			EquipmentData.rarity_name(src_rarity), next_name
		]
		merge_btn.add_theme_font_size_override("font_size", 16)
		merge_btn.modulate = EquipmentData.rarity_color(src_rarity + 1)
		merge_btn.pressed.connect(func(): _do_merge(root, overlay))
		cv.add_child(merge_btn)


func _is_valid_merge() -> bool:
	if _merge_sel.size() != 3:
		return false
	var r: int = (_merge_sel[0] as EquipmentData).rarity
	for item in _merge_sel:
		if (item as EquipmentData).rarity != r:
			return false
	# Can't merge Legendary or Mystery
	return r < EquipmentData.Rarity.LEGENDARY


func _do_merge(root: Control, overlay: CanvasLayer) -> void:
	var src_rarity: EquipmentData.Rarity = (_merge_sel[0] as EquipmentData).rarity
	for item in _merge_sel:
		GameState.inventory.erase(item)
	_merge_sel.clear()

	var success: bool = (randi() % 100) < 80
	var new_item: EquipmentData = null
	if success:
		var pool: Array = EquipmentData.all().duplicate()
		pool.shuffle()
		new_item = (pool[0] as EquipmentData).duplicate()
		new_item.rarity = src_rarity + 1
		GameState.inventory.append(new_item)

	_build_merge_result(new_item, success, src_rarity, root, overlay)


func _build_merge_result(new_item, success: bool, src_rarity: int,
		root: Control, overlay: CanvasLayer) -> void:
	_clear_children(root)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.offset_left   = -360.0; vbox.offset_right  = 360.0
	vbox.offset_top    = -200.0; vbox.offset_bottom = 200.0
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 18)
	root.add_child(vbox)

	var result_lbl := Label.new()
	result_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_lbl.add_theme_font_size_override("font_size", 42)
	if success:
		result_lbl.text = "Merge successful!"
		result_lbl.modulate = Color(0.25, 1.0, 0.45)
	else:
		result_lbl.text = "The merge failed…"
		result_lbl.modulate = Color(1.0, 0.35, 0.28)
	vbox.add_child(result_lbl)

	if success and new_item != null:
		var ed := new_item as EquipmentData
		var detail := Label.new()
		detail.text = "%s  [%s]  %s" % [
			ed.equipment_name,
			EquipmentData.rarity_name(ed.rarity),
			_equipment_stat_summary(ed),
		]
		detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		detail.add_theme_font_size_override("font_size", 22)
		detail.modulate = EquipmentData.rarity_color(ed.rarity)
		vbox.add_child(detail)
	elif not success:
		var lost_lbl := Label.new()
		lost_lbl.text = "All 3 %s items were lost." % EquipmentData.rarity_name(src_rarity)
		lost_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lost_lbl.add_theme_font_size_override("font_size", 18)
		lost_lbl.modulate = Color(0.72, 0.72, 0.72)
		vbox.add_child(lost_lbl)

	var ok_btn := Button.new()
	ok_btn.text = "Continue"
	ok_btn.add_theme_font_size_override("font_size", 18)
	ok_btn.custom_minimum_size = Vector2(140, 0)
	ok_btn.pressed.connect(func(): _build_inventory_view(root, overlay))
	vbox.add_child(ok_btn)


# ── Inventory: Scrolls section ────────────────────────────────────────────────

func _inv_section_scrolls(cv: VBoxContainer, root: Control, overlay: CanvasLayer) -> void:
	cv.add_child(_inv_section_label("SCROLLS  (%d)" % GameState.scrolls.size()))

	if GameState.scrolls.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "No scrolls in inventory."
		empty_lbl.modulate = Color(0.5, 0.5, 0.5)
		empty_lbl.add_theme_font_size_override("font_size", 13)
		cv.add_child(empty_lbl)
		return

	for scroll in GameState.scrolls:
		var sd: ScrollData = scroll as ScrollData
		if sd == null:
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		cv.add_child(row)

		var info := Label.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_theme_font_size_override("font_size", 14)
		info.text = "%s  +%d %s  |  %d%% success  /  %d%% destroy on fail" % [
			sd.scroll_name,
			sd.boost_amount,
			sd.stat_label(),
			sd.success_chance,
			sd.destroy_chance,
		]
		info.modulate = sd.stat_color()
		row.add_child(info)

		var use_btn := Button.new()
		use_btn.text = "Use"
		use_btn.add_theme_font_size_override("font_size", 13)
		var cap_sd: ScrollData = sd
		use_btn.pressed.connect(func(): _build_scroll_picker(cap_sd, root, overlay))
		row.add_child(use_btn)


# ── Slot picker (swap equipped) ───────────────────────────────────────────────

func _build_slot_picker(slot_int: int, root: Control, overlay: CanvasLayer) -> void:
	_clear_children(root)

	var slot_names := {0: "Weapon", 1: "Offhand", 2: "Chest", 3: "Helm", 4: "Shoes"}
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.offset_left   = -400.0; vbox.offset_right  = 400.0
	vbox.offset_top    = -300.0; vbox.offset_bottom = 300.0
	vbox.add_theme_constant_override("separation", 10)
	root.add_child(vbox)

	var title := Label.new()
	title.text = "Choose a %s to equip" % slot_names.get(slot_int, "item")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	vbox.add_child(title)

	var matches := GameState.inventory.filter(
		func(i): return (i as EquipmentData) != null and (i as EquipmentData).slot == slot_int
	)
	for item in matches:
		var ed := item as EquipmentData
		var btn := Button.new()
		btn.text = "%s  [%s]  %s" % [
			ed.equipment_name,
			EquipmentData.rarity_name(ed.rarity),
			_equipment_stat_summary(ed),
		]
		btn.add_theme_font_size_override("font_size", 16)
		btn.modulate = EquipmentData.rarity_color(ed.rarity)
		var cap_ed := ed
		btn.pressed.connect(func():
			var old := GameState.equipment.get(cap_ed.slot) as EquipmentData
			if old != null:
				GameState.inventory.append(old)
			GameState.equipment[cap_ed.slot] = cap_ed
			GameState.inventory.erase(cap_ed)
			_merge_sel.erase(cap_ed)
	
			_build_inventory_view(root, overlay)
		)
		vbox.add_child(btn)

	var back_btn := Button.new()
	back_btn.text = "Back"
	back_btn.add_theme_font_size_override("font_size", 16)
	back_btn.pressed.connect(func(): _build_inventory_view(root, overlay))
	vbox.add_child(back_btn)


# ── Scroll picker ─────────────────────────────────────────────────────────────

func _build_scroll_picker(sd: ScrollData, root: Control, overlay: CanvasLayer) -> void:
	_clear_children(root)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.offset_left   = -430.0; vbox.offset_right  = 430.0
	vbox.offset_top    = -340.0; vbox.offset_bottom = 340.0
	vbox.add_theme_constant_override("separation", 8)
	root.add_child(vbox)

	var title := Label.new()
	title.text = "Apply %s to which item?" % sd.scroll_name
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	title.modulate = sd.stat_color()
	vbox.add_child(title)

	var sub := Label.new()
	sub.text = "+%d %s  |  %d%% success  |  %d%% destroy on fail" % [
		sd.boost_amount, sd.stat_label(),
		sd.success_chance, sd.destroy_chance,
	]
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 15)
	sub.modulate = Color(0.72, 0.72, 0.72)
	vbox.add_child(sub)

	vbox.add_child(HSeparator.new())

	# Equipped items
	var eq_lbl := Label.new()
	eq_lbl.text = "Equipped"
	eq_lbl.add_theme_font_size_override("font_size", 14)
	eq_lbl.modulate = Color(0.65, 0.65, 0.65)
	vbox.add_child(eq_lbl)

	for item in GameState.equipment.values():
		var ed := item as EquipmentData
		if ed == null:
			continue
		vbox.add_child(_make_scroll_target_btn(sd, ed, true, root, overlay))

	# Inventory items
	if not GameState.inventory.is_empty():
		var inv_lbl := Label.new()
		inv_lbl.text = "Inventory"
		inv_lbl.add_theme_font_size_override("font_size", 14)
		inv_lbl.modulate = Color(0.65, 0.65, 0.65)
		vbox.add_child(inv_lbl)
		for item in GameState.inventory:
			var ed := item as EquipmentData
			if ed == null:
				continue
			vbox.add_child(_make_scroll_target_btn(sd, ed, false, root, overlay))

	var back_btn := Button.new()
	back_btn.text = "Cancel"
	back_btn.add_theme_font_size_override("font_size", 15)
	back_btn.pressed.connect(func(): _build_inventory_view(root, overlay))
	vbox.add_child(back_btn)


func _make_scroll_target_btn(sd: ScrollData, ed: EquipmentData, is_equipped: bool,
		root: Control, overlay: CanvasLayer) -> Button:
	var btn := Button.new()
	btn.text = "%s  [%s]  %s" % [
		ed.equipment_name,
		EquipmentData.rarity_name(ed.rarity),
		_equipment_stat_summary(ed),
	]
	btn.add_theme_font_size_override("font_size", 15)
	btn.modulate = EquipmentData.rarity_color(ed.rarity)
	var cap_sd: ScrollData = sd
	var cap_ed: EquipmentData = ed
	var cap_eq: bool = is_equipped
	btn.pressed.connect(func():
		var result := _apply_scroll(cap_sd, cap_ed, cap_eq)
		GameState.scrolls.erase(cap_sd)
		_build_scroll_result(cap_sd, cap_ed.equipment_name, result[0], result[1], root, overlay)
	)
	return btn


func _apply_scroll(sd: ScrollData, ed: EquipmentData, is_equipped: bool) -> Array:
	# Returns [success: bool, destroyed: bool]
	var success: bool = (randi() % 100) < sd.success_chance
	if success:
		match sd.stat_type:
			ScrollData.StatType.DAMAGE:     ed.damage_bonus     += sd.boost_amount
			ScrollData.StatType.BLOCK:      ed.block_per_turn   += sd.boost_amount
			ScrollData.StatType.MAX_HP:     ed.max_hp_bonus     += sd.boost_amount
			ScrollData.StatType.MAX_ENERGY: ed.max_energy_bonus += sd.boost_amount
			ScrollData.StatType.CRIT:       ed.crit_chance      += sd.boost_amount
		return [true, false]
	else:
		var destroyed: bool = (randi() % 100) < sd.destroy_chance
		if destroyed:
			if is_equipped:
				GameState.equipment.erase(ed.slot)
		
			else:
				GameState.inventory.erase(ed)
		return [false, destroyed]


func _build_scroll_result(sd: ScrollData, item_name: String, success: bool, destroyed: bool,
		root: Control, overlay: CanvasLayer) -> void:
	_clear_children(root)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.offset_left   = -360.0; vbox.offset_right  = 360.0
	vbox.offset_top    = -200.0; vbox.offset_bottom = 200.0
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 18)
	root.add_child(vbox)

	var result_lbl := Label.new()
	result_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_lbl.add_theme_font_size_override("font_size", 40)
	if success:
		result_lbl.text = "Scroll worked!"
		result_lbl.modulate = Color(0.25, 1.0, 0.45)
	elif destroyed:
		result_lbl.text = "The item shattered!"
		result_lbl.modulate = Color(1.0, 0.25, 0.20)
	else:
		result_lbl.text = "Scroll fizzled…"
		result_lbl.modulate = Color(0.88, 0.55, 0.20)
	vbox.add_child(result_lbl)

	var detail_lbl := Label.new()
	detail_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail_lbl.add_theme_font_size_override("font_size", 18)
	if success:
		detail_lbl.text = "%s received +%d %s." % [
			item_name, sd.boost_amount, sd.stat_label()
		]
	elif destroyed:
		detail_lbl.text = "%s was destroyed." % item_name
	else:
		detail_lbl.text = "%s is unchanged." % item_name
	vbox.add_child(detail_lbl)

	var ok_btn := Button.new()
	ok_btn.text = "Continue"
	ok_btn.add_theme_font_size_override("font_size", 18)
	ok_btn.custom_minimum_size = Vector2(140, 0)
	ok_btn.pressed.connect(func(): _build_inventory_view(root, overlay))
	vbox.add_child(ok_btn)


# ── Scavenge: scroll drop ─────────────────────────────────────────────────────

func _build_scavenge_scroll_result(root: Control, overlay: CanvasLayer) -> void:
	_clear_children(root)

	var pool: Array = ScrollData.all().duplicate()
	pool.shuffle()
	var sd: ScrollData = (pool[0] as ScrollData).duplicate()

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.offset_left   = -360.0; vbox.offset_right  = 360.0
	vbox.offset_top    = -240.0; vbox.offset_bottom = 240.0
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 16)
	root.add_child(vbox)

	var title := Label.new()
	title.text = "You found a scroll!"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	title.modulate = sd.stat_color()
	vbox.add_child(title)

	var name_lbl := Label.new()
	name_lbl.text = sd.scroll_name
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 28)
	vbox.add_child(name_lbl)

	var stat_lbl := Label.new()
	stat_lbl.text = "+%d %s  |  %d%% success  /  %d%% destroy on fail" % [
		sd.boost_amount, sd.stat_label(),
		sd.success_chance, sd.destroy_chance,
	]
	stat_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stat_lbl.add_theme_font_size_override("font_size", 17)
	stat_lbl.modulate = Color(0.85, 0.85, 0.65)
	vbox.add_child(stat_lbl)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 6)
	vbox.add_child(spacer)

	var take_btn := Button.new()
	take_btn.text = "Take it"
	take_btn.add_theme_font_size_override("font_size", 20)
	take_btn.custom_minimum_size = Vector2(160, 0)
	take_btn.pressed.connect(func():
		GameState.scrolls.append(sd)
		overlay.queue_free()
	)
	vbox.add_child(take_btn)

	var leave_btn := Button.new()
	leave_btn.text = "Leave it"
	leave_btn.add_theme_font_size_override("font_size", 16)
	leave_btn.modulate = Color(0.65, 0.65, 0.65)
	leave_btn.pressed.connect(func(): overlay.queue_free())
	vbox.add_child(leave_btn)


# ── Shared helpers ────────────────────────────────────────────────────────────

func _inv_section_label(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.modulate = Color(0.75, 0.70, 0.90)
	return lbl


func _clear_children(node: Control) -> void:
	for c in node.get_children():
		c.queue_free()
