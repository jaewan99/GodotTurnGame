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

## Enchant success rate (%) indexed by item's current enchant_level before the attempt.
## Lv0→1: 100%, 1→2: 80%, 2→3: 65%, 3→4: 50%, 4→5: 35%, 5→6: 20%, 6+: 10%
const ENCHANT_SUCCESS_RATES := [100, 80, 65, 50, 35, 20, 10]
const ENCHANT_BASE_COST := 30   # coins × (enchant_level + 1)

const SHOP_EQUIP_PRICES := {
	0: 1,   # COMMON
	1: 1,   # UNCOMMON
	2: 1,   # RARE
	3: 1,   # UNIQUE
	4: 1,   # LEGENDARY
	5: 1,   # MYSTERY
}
const SHOP_SCROLL_PRICE  := 1
const SHOP_EQUIP_COUNT   := 3
const SHOP_SCROLL_COUNT  := 3

var _nodes: Array[MapNode] = []
var _uis: Dictionary = {}   # node id -> MapNodeUI
var _coins_label: Label = null
var _reachable: Array[int] = []   # updated by _refresh(), used by _draw()
## Items selected for merging in the inventory overlay.
var _merge_sel: Array = []

## How fast the map follows the mouse while panning.
## 1.0 = map moves 1:1 with the cursor; 0.5 = half speed; >1.0 = faster.
const PAN_SPEED := 0.55
## Breathing room (px) kept around the map edges when panned to a limit.
## Panning is only allowed as far as needed to reveal off-screen nodes.
const PAN_PADDING := 80.0

var _pan_offset: Vector2 = Vector2.ZERO
var _pan_drag_origin: Vector2 = Vector2.ZERO
var _is_panning: bool = false
var _map_bounds: Rect2 = Rect2()   # bounding box of all node positions, computed once


func _ready() -> void:
	_add_background()
	if GameState.has_map():
		_nodes = GameState.map_nodes
	else:
		_nodes = MapGenerator.generate(GameState.floor)
		GameState.map_nodes = _nodes
	_spawn_uis()
	_compute_map_bounds()
	_refresh()
	queue_redraw()
	_add_coins_label()
	_add_inventory_button()
	_add_floor_indicator()

	# Dojo victory → free guaranteed card upgrade.
	if GameState.dojo_reward_pending:
		GameState.dojo_reward_pending = false
		_show_dojo_upgrade_overlay()

	# Clear one-shot battle modifiers that survived a lost/abandoned battle.
	GameState.battle_tier_override = -1
	GameState.bounty_rounds = 0
	GameState.coin_mult = 1


# ── Pan input ─────────────────────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	# Don't pan while any overlay (CanvasLayer) is open.
	for child in get_children():
		if child is CanvasLayer:
			return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed:
			_pan_drag_origin = event.position
			_is_panning = false
		else:
			if _is_panning:
				get_viewport().set_input_as_handled()
			_is_panning = false

	elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		var delta: Vector2 = event.position - _pan_drag_origin
		if not _is_panning and delta.length() > 6.0:
			_is_panning = true
		if _is_panning:
			_pan_offset += event.relative * PAN_SPEED
			_apply_pan()
			get_viewport().set_input_as_handled()


func _apply_pan() -> void:
	_clamp_pan()
	for node in _nodes:
		var ui := _uis[node.id] as MapNodeUI
		ui.position = node.pos + _pan_offset - ui.size / 2.0
	queue_redraw()


func _compute_map_bounds() -> void:
	if _nodes.is_empty():
		return
	var mn := _nodes[0].pos
	var mx := _nodes[0].pos
	for node in _nodes:
		mn = mn.min(node.pos)
		mx = mx.max(node.pos)
	_map_bounds = Rect2(mn, mx - mn)


func _clamp_pan() -> void:
	# "Reveal-only" clamp: you can pan just far enough to bring the map's
	# far edge into view (plus PAN_PADDING), and no further. If the map
	# already fits on screen along an axis, that axis doesn't pan at all.
	var vp := get_viewport_rect().size

	# Dragging LEFT (negative offset): stop when the map's right edge
	# reaches the right side of the screen.
	var min_x := vp.x - PAN_PADDING - _map_bounds.end.x
	# Dragging RIGHT (positive offset): stop when the map's left edge
	# reaches the left side of the screen.
	var max_x := PAN_PADDING - _map_bounds.position.x
	_pan_offset.x = 0.0 if min_x > max_x else clampf(_pan_offset.x, min_x, max_x)

	var min_y := vp.y - PAN_PADDING - _map_bounds.end.y
	var max_y := PAN_PADDING - _map_bounds.position.y
	_pan_offset.y = 0.0 if min_y > max_y else clampf(_pan_offset.y, min_y, max_y)


# ── Drawing ───────────────────────────────────────────────────────────────────

func _draw() -> void:
	for node in _nodes:
		# Faint glint hint at an undiscovered secret node's position.
		if node.type == MapNode.Type.SECRET and not node.secret_revealed and not node.visited:
			var p := node.pos + _pan_offset
			draw_circle(p, 7.0, Color(1.0, 0.95, 0.6, 0.10))
			draw_circle(p, 2.5, Color(1.0, 0.95, 0.7, 0.30))
			continue

		var node_visible := node.visited or node.id in _reachable
		if not node_visible:
			continue
		for cid in node.connections:
			var other: MapNode = _nodes[cid]
			var other_visible := other.visited or cid in _reachable

			# Hidden neighbor: draw a stub fading into the fog so the player
			# can tell this path continues. No stub = dead end.
			if not other_visible:
				if other.type == MapNode.Type.SECRET and not other.secret_revealed:
					continue   # don't leak secret nodes
				var from := node.pos + _pan_offset
				var dir := (other.pos - node.pos).normalized()
				# Three segments with decreasing alpha = "trails off" effect.
				draw_line(from + dir * 34.0, from + dir * 70.0,
						Color(0.75, 0.75, 0.75, 0.60), 2.5, true)
				draw_line(from + dir * 70.0, from + dir * 100.0,
						Color(0.70, 0.70, 0.70, 0.32), 2.5, true)
				draw_line(from + dir * 100.0, from + dir * 124.0,
						Color(0.65, 0.65, 0.65, 0.12), 2.5, true)
				continue

			if cid <= node.id:   # draw each full edge once
				continue
			var traveled := node.visited and other.visited
			var col := Color(0.75, 0.75, 0.75, 0.85) if traveled \
					else Color(0.40, 0.40, 0.40, 0.55)
			draw_line(node.pos + _pan_offset, other.pos + _pan_offset, col, 2.0, true)


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
	_reachable.clear()
	for node in _nodes:
		if not node.visited:
			continue
		for cid in node.connections:
			if not _nodes[cid].visited and cid not in _reachable:
				_reachable.append(cid)

	for node in _nodes:
		var ui := _uis[node.id] as MapNodeUI
		# Secret nodes reveal themselves once an adjacent node is visited.
		if node.type == MapNode.Type.SECRET and node.id in _reachable:
			node.secret_revealed = true
		if node.type == MapNode.Type.SECRET:
			ui.visible = node.secret_revealed or node.visited
		else:
			ui.visible = node.visited or node.id in _reachable

		ui.refresh(node.id in _reachable)


func _on_node_clicked(node: MapNode) -> void:
	node.visited = true
	_refresh()
	queue_redraw()

	match node.type:
		MapNode.Type.FIGHT, MapNode.Type.ELITE, MapNode.Type.BOSS:
			GameState.current_node_id = node.id
			get_tree().change_scene_to_file(BATTLE_SCENE)
		MapNode.Type.REST:
			_show_wizard_overlay()
		MapNode.Type.SHOP:
			_show_shop_overlay(node)
		MapNode.Type.EVENT:
			_show_event_overlay()
		MapNode.Type.ENCHANT:
			_show_enchant_overlay(node)
		MapNode.Type.FORGE:
			_show_forge_overlay()
		MapNode.Type.MYSTERY:
			_show_mystery_overlay(node)
		MapNode.Type.GAMBLE:
			_show_gamble_overlay()
		MapNode.Type.TREASURE:
			_show_treasure_overlay()
		MapNode.Type.SHRINE:
			_show_shrine_overlay()
		MapNode.Type.DOJO:
			_show_dojo_overlay(node)
		MapNode.Type.BOUNTY:
			_show_bounty_overlay(node)
		MapNode.Type.SECRET:
			_show_secret_overlay(node)


## Launches a battle from a special node with one-shot modifiers.
func _go_battle(node: MapNode, tier: int = -1, bounty: int = 0, mult: int = 1) -> void:
	GameState.current_node_id = node.id
	GameState.battle_tier_override = tier
	GameState.bounty_rounds = bounty
	GameState.coin_mult = mult
	get_tree().change_scene_to_file(BATTLE_SCENE)


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
	desc.text = "A mysterious stranger offers his services."
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.add_theme_font_size_override("font_size", 19)
	desc.modulate = Color(0.78, 0.78, 0.78)
	vbox.add_child(desc)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 8)
	vbox.add_child(spacer)

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
	back_btn.pressed.connect(func(): _build_forge_menu(root, overlay))
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
	ok_btn.pressed.connect(func(): _build_forge_menu(root, overlay))
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


# Equipment display text lives in EquipmentData (shared with InventoryOverlay
# and other scenes); these wrappers keep the many local call sites short.
func _equipment_stat_summary(ed: EquipmentData) -> String:
	return EquipmentData.stat_summary(ed)


func _equipment_enchant_tag(ed: EquipmentData) -> String:
	return EquipmentData.enchant_tag(ed)


func _equipment_tooltip(ed: EquipmentData) -> String:
	return EquipmentData.tooltip(ed)


# ── Scavenge event option ─────────────────────────────────────────────────────

func _build_scavenge_result(root: Control, overlay: CanvasLayer) -> void:
	_clear_children(root)

	# 20% chance: a stranger marks an undiscovered secret node on your map.
	if randi() % 100 < 20:
		for n in _nodes:
			if n.type == MapNode.Type.SECRET and not n.secret_revealed and not n.visited:
				n.secret_revealed = true
				_refresh()
				queue_redraw()
				_build_simple_result("A stranger approaches…", Color(0.3, 0.85, 0.75),
						"\"I saw something hidden out there.\"\nA location has been marked on your map.",
						root, overlay)
				return

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
	btn.pressed.connect(func(): InventoryOverlay.open(self))
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
	ok_btn.pressed.connect(func(): _build_merge_view(root, overlay))
	vbox.add_child(ok_btn)


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
	ok_btn.pressed.connect(func(): _build_forge_menu(root, overlay))
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


# ── Wizard overlay ────────────────────────────────────────────────────────────

func _show_wizard_overlay() -> void:
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

	_build_wizard_view(root, overlay)


func _build_wizard_view(root: Control, overlay: CanvasLayer) -> void:
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
	title.text = "The Wizard"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 48)
	title.modulate = Color(0.45, 0.88, 0.95)
	vbox.add_child(title)

	var desc := Label.new()
	desc.text = "\"I can erase one technique from your memory. Choose wisely.\""
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.add_theme_font_size_override("font_size", 18)
	desc.modulate = Color(0.72, 0.72, 0.72)
	vbox.add_child(desc)

	vbox.add_child(HSeparator.new())

	var safe_to_remove := GameState.deck.size() > 1

	if not safe_to_remove:
		var warn := Label.new()
		warn.text = "Your deck only has one card — nothing to remove."
		warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		warn.add_theme_font_size_override("font_size", 17)
		warn.modulate = Color(1.0, 0.6, 0.2)
		vbox.add_child(warn)
	else:
		var hint := Label.new()
		hint.text = "Choose a card to remove from your deck (free):"
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hint.add_theme_font_size_override("font_size", 16)
		hint.modulate = Color(0.65, 0.65, 0.65)
		vbox.add_child(hint)

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
		btn.disabled = not safe_to_remove
		if not safe_to_remove:
			btn.modulate = Color(0.5, 0.5, 0.5)

		var captured_card := card
		btn.pressed.connect(func():
			GameState.deck.erase(captured_card)
			_build_wizard_done(captured_card.card_name, root, overlay)
		)
		grid.add_child(btn)

	var leave_btn := Button.new()
	leave_btn.text = "Decline"
	leave_btn.add_theme_font_size_override("font_size", 17)
	leave_btn.modulate = Color(0.65, 0.65, 0.65)
	leave_btn.pressed.connect(func(): overlay.queue_free())
	vbox.add_child(leave_btn)


func _build_wizard_done(card_name: String, root: Control, overlay: CanvasLayer) -> void:
	_clear_children(root)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.offset_left   = -360.0
	vbox.offset_right  =  360.0
	vbox.offset_top    = -160.0
	vbox.offset_bottom =  160.0
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 22)
	root.add_child(vbox)

	var result := Label.new()
	result.text = "Forgotten."
	result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result.add_theme_font_size_override("font_size", 48)
	result.modulate = Color(0.45, 0.88, 0.95)
	vbox.add_child(result)

	var detail := Label.new()
	detail.text = "%s has been removed from your deck." % card_name
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail.add_theme_font_size_override("font_size", 20)
	detail.modulate = Color(0.75, 0.75, 0.75)
	vbox.add_child(detail)

	var ok_btn := Button.new()
	ok_btn.text = "Continue"
	ok_btn.add_theme_font_size_override("font_size", 20)
	ok_btn.custom_minimum_size = Vector2(160, 0)
	ok_btn.pressed.connect(func(): overlay.queue_free())
	vbox.add_child(ok_btn)


# ── Shop overlay ──────────────────────────────────────────────────────────────

func _close_shop_node(map_node: MapNode) -> void:
	# Everything bought — close the shop for good.
	map_node.always_accessible = false
	_refresh()
	queue_redraw()


func _show_shop_overlay(map_node: MapNode) -> void:
	var overlay := CanvasLayer.new()
	overlay.layer = 10
	add_child(overlay)

	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 0.85)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(bg)

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(root)

	# Stock is generated once per node and persisted, so leaving and
	# re-entering the shop shows the remaining items, not fresh stock.
	if not map_node.shop_stocked:
		var equip_pool: Array = EquipmentData.all().duplicate()
		equip_pool.shuffle()
		for i in mini(SHOP_EQUIP_COUNT, equip_pool.size()):
			map_node.shop_stock_equip.append((equip_pool[i] as EquipmentData).duplicate())

		var scroll_pool: Array = ScrollData.all().duplicate()
		scroll_pool.shuffle()
		for i in mini(SHOP_SCROLL_COUNT, scroll_pool.size()):
			map_node.shop_stock_scrolls.append((scroll_pool[i] as ScrollData).duplicate())

		map_node.shop_stocked = true

	_build_shop_view(map_node.shop_stock_equip, map_node.shop_stock_scrolls, map_node, root, overlay)


func _build_shop_view(stock_equip: Array, stock_scrolls: Array,
		map_node: MapNode, root: Control, overlay: CanvasLayer) -> void:
	_clear_children(root)

	var panel := Panel.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left   = -500.0
	panel.offset_right  =  500.0
	panel.offset_top    = -380.0
	panel.offset_bottom =  380.0
	root.add_child(panel)

	var outer := VBoxContainer.new()
	outer.set_anchors_preset(Control.PRESET_FULL_RECT)
	outer.offset_left = 18; outer.offset_right  = -18
	outer.offset_top  = 14; outer.offset_bottom = -14
	outer.add_theme_constant_override("separation", 8)
	panel.add_child(outer)

	# Header
	var hdr := HBoxContainer.new()
	outer.add_child(hdr)

	var title_lbl := Label.new()
	title_lbl.text = "SHOP"
	title_lbl.add_theme_font_size_override("font_size", 30)
	title_lbl.modulate = Color(1.0, 0.88, 0.30)
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr.add_child(title_lbl)

	var shop_coins_lbl := Label.new()
	shop_coins_lbl.add_theme_font_size_override("font_size", 20)
	shop_coins_lbl.modulate = Color(1.0, 0.85, 0.1)
	shop_coins_lbl.text = "Coins: %d" % GameState.coins
	hdr.add_child(shop_coins_lbl)

	outer.add_child(HSeparator.new())

	# Equipment section
	var slot_names := {0: "Weapon", 1: "Offhand", 2: "Chest", 3: "Helm", 4: "Shoes"}

	outer.add_child(_inv_section_label("EQUIPMENT"))

	if stock_equip.is_empty():
		var sold_lbl := Label.new()
		sold_lbl.text = "Sold out!"
		sold_lbl.modulate = Color(0.5, 0.5, 0.5)
		sold_lbl.add_theme_font_size_override("font_size", 14)
		outer.add_child(sold_lbl)
	else:
		for ed in stock_equip:
			var price: int = SHOP_EQUIP_PRICES.get(ed.rarity, 1)
			var can_afford := GameState.coins >= price

			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 10)
			outer.add_child(row)

			var info := Label.new()
			info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			info.add_theme_font_size_override("font_size", 15)
			info.text = "[%s]  %s%s  [%s]  %s" % [
				slot_names.get(ed.slot, "?"),
				ed.equipment_name,
				_equipment_enchant_tag(ed),
				EquipmentData.rarity_name(ed.rarity),
				_equipment_stat_summary(ed),
			]
			var base_col := EquipmentData.rarity_color(ed.rarity)
			info.modulate = base_col if can_afford else base_col * Color(0.50, 0.50, 0.50, 1.0)
			info.tooltip_text = _equipment_tooltip(ed)
			info.mouse_filter = Control.MOUSE_FILTER_PASS
			row.add_child(info)

			var price_lbl := Label.new()
			price_lbl.text = "%dg" % price
			price_lbl.add_theme_font_size_override("font_size", 14)
			price_lbl.modulate = Color(1.0, 0.85, 0.1) if can_afford else Color(0.45, 0.45, 0.45)
			price_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			row.add_child(price_lbl)

			var buy_btn := Button.new()
			buy_btn.text = "Buy"
			buy_btn.add_theme_font_size_override("font_size", 14)
			buy_btn.disabled = not can_afford
			var cap_ed: EquipmentData = ed
			var cap_price: int = price
			buy_btn.pressed.connect(func():
				GameState.coins -= cap_price
				GameState.inventory.append(cap_ed)
				stock_equip.erase(cap_ed)
				_refresh_coins_label()
				if stock_equip.is_empty() and stock_scrolls.is_empty():
					_close_shop_node(map_node)
					overlay.queue_free()
				else:
					_build_shop_view(stock_equip, stock_scrolls, map_node, root, overlay)
			)
			row.add_child(buy_btn)

	outer.add_child(HSeparator.new())

	# Scrolls section
	outer.add_child(_inv_section_label("SCROLLS"))

	if stock_scrolls.is_empty():
		var sold_lbl := Label.new()
		sold_lbl.text = "Sold out!"
		sold_lbl.modulate = Color(0.5, 0.5, 0.5)
		sold_lbl.add_theme_font_size_override("font_size", 14)
		outer.add_child(sold_lbl)
	else:
		for scroll in stock_scrolls:
			var sd := scroll as ScrollData
			var can_afford := GameState.coins >= SHOP_SCROLL_PRICE

			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 10)
			outer.add_child(row)

			var info := Label.new()
			info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			info.add_theme_font_size_override("font_size", 15)
			info.text = "%s  +%d %s  |  %d%% success / %d%% destroy on fail" % [
				sd.scroll_name,
				sd.boost_amount,
				sd.stat_label(),
				sd.success_chance,
				sd.destroy_chance,
			]
			var base_col := sd.stat_color()
			info.modulate = base_col if can_afford else base_col * Color(0.50, 0.50, 0.50, 1.0)
			row.add_child(info)

			var price_lbl := Label.new()
			price_lbl.text = "%dg" % SHOP_SCROLL_PRICE
			price_lbl.add_theme_font_size_override("font_size", 14)
			price_lbl.modulate = Color(1.0, 0.85, 0.1) if can_afford else Color(0.45, 0.45, 0.45)
			price_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			row.add_child(price_lbl)

			var buy_btn := Button.new()
			buy_btn.text = "Buy"
			buy_btn.add_theme_font_size_override("font_size", 14)
			buy_btn.disabled = not can_afford
			var cap_sd: ScrollData = sd
			buy_btn.pressed.connect(func():
				GameState.coins -= SHOP_SCROLL_PRICE
				GameState.scrolls.append(cap_sd)
				stock_scrolls.erase(cap_sd)
				_refresh_coins_label()
				if stock_equip.is_empty() and stock_scrolls.is_empty():
					_close_shop_node(map_node)
					overlay.queue_free()
				else:
					_build_shop_view(stock_equip, stock_scrolls, map_node, root, overlay)
			)
			row.add_child(buy_btn)

	outer.add_child(HSeparator.new())

	var leave_btn := Button.new()
	leave_btn.text = "Leave Shop"
	leave_btn.add_theme_font_size_override("font_size", 18)
	leave_btn.custom_minimum_size = Vector2(0, 44)
	leave_btn.pressed.connect(func(): overlay.queue_free())
	outer.add_child(leave_btn)


# ── Forge node overlay ────────────────────────────────────────────────────────

func _show_forge_overlay() -> void:
	var overlay := CanvasLayer.new()
	overlay.layer = 10
	add_child(overlay)

	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 0.85)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(bg)

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(root)

	_merge_sel.clear()
	_build_forge_menu(root, overlay)


func _build_forge_menu(root: Control, overlay: CanvasLayer) -> void:
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
	title.text = "The Forge"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 52)
	title.modulate = Color(1.0, 0.62, 0.25)
	vbox.add_child(title)

	var desc := Label.new()
	desc.text = "The blacksmith's hammer never rests."
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

	var scroll_btn := Button.new()
	scroll_btn.text = "Use a Scroll  (%d owned)" % GameState.scrolls.size()
	scroll_btn.add_theme_font_size_override("font_size", 22)
	scroll_btn.custom_minimum_size = Vector2(0, 54)
	scroll_btn.disabled = GameState.scrolls.is_empty()
	scroll_btn.pressed.connect(func():
		_build_scroll_select(root, overlay)
	)
	vbox.add_child(scroll_btn)

	var merge_btn := Button.new()
	merge_btn.text = "Merge Items  (3 same rarity → next tier)"
	merge_btn.add_theme_font_size_override("font_size", 22)
	merge_btn.custom_minimum_size = Vector2(0, 54)
	merge_btn.pressed.connect(func():
		_merge_sel.clear()
		_build_merge_view(root, overlay)
	)
	vbox.add_child(merge_btn)

	var leave_btn := Button.new()
	leave_btn.text = "Leave"
	leave_btn.add_theme_font_size_override("font_size", 18)
	leave_btn.modulate = Color(0.65, 0.65, 0.65)
	leave_btn.pressed.connect(func(): overlay.queue_free())
	vbox.add_child(leave_btn)


func _build_scroll_select(root: Control, overlay: CanvasLayer) -> void:
	_clear_children(root)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left   = 80.0
	vbox.offset_right  = -80.0
	vbox.offset_top    = 40.0
	vbox.offset_bottom = -40.0
	vbox.add_theme_constant_override("separation", 10)
	root.add_child(vbox)

	var title := Label.new()
	title.text = "Use a Scroll"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 38)
	title.modulate = Color(0.85, 0.65, 1.0)
	vbox.add_child(title)

	var hint := Label.new()
	hint.text = "Drag a scroll onto an item to apply it."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 16)
	hint.modulate = Color(0.65, 0.65, 0.65)
	vbox.add_child(hint)

	# ── Scrolls (drag sources) ────────────────────────────────────────────────
	vbox.add_child(_inv_section_label("SCROLLS"))
	var s_grid := GridContainer.new()
	s_grid.columns = 8
	s_grid.add_theme_constant_override("h_separation", 8)
	s_grid.add_theme_constant_override("v_separation", 8)
	vbox.add_child(s_grid)

	for item in GameState.scrolls:
		var sd: ScrollData = item as ScrollData
		if sd == null:
			continue
		var tile := InventoryOverlay.make_scroll_tile(sd)
		tile.set_drag_forwarding(
			_scroll_drag_data.bind(sd, tile),
			_reject_drop,
			_ignore_drop
		)
		s_grid.add_child(tile)

	vbox.add_child(HSeparator.new())

	# ── Targets: equipped + inventory items (drop a scroll on them) ──────────
	var scr := ScrollContainer.new()
	scr.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scr)

	var cv := VBoxContainer.new()
	cv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cv.add_theme_constant_override("separation", 8)
	scr.add_child(cv)

	cv.add_child(_inv_section_label("EQUIPPED"))
	var eq_grid := GridContainer.new()
	eq_grid.columns = 8
	eq_grid.add_theme_constant_override("h_separation", 8)
	eq_grid.add_theme_constant_override("v_separation", 8)
	cv.add_child(eq_grid)
	for slot_int in [0, 1, 2, 3, 4]:
		var ed := GameState.equipment.get(slot_int) as EquipmentData
		if ed == null:
			continue
		eq_grid.add_child(_make_scroll_target_tile(ed, true, root, overlay))

	cv.add_child(_inv_section_label("ITEMS"))
	var inv_grid := GridContainer.new()
	inv_grid.columns = 8
	inv_grid.add_theme_constant_override("h_separation", 8)
	inv_grid.add_theme_constant_override("v_separation", 8)
	cv.add_child(inv_grid)
	for item in GameState.inventory:
		var ed := item as EquipmentData
		if ed == null:
			continue
		inv_grid.add_child(_make_scroll_target_tile(ed, false, root, overlay))

	var back_btn := Button.new()
	back_btn.text = "Back"
	back_btn.add_theme_font_size_override("font_size", 17)
	back_btn.pressed.connect(func(): _build_forge_menu(root, overlay))
	vbox.add_child(back_btn)


## Equipment tile that accepts a dragged scroll and applies it on drop.
func _make_scroll_target_tile(ed: EquipmentData, is_equipped: bool,
		root: Control, overlay: CanvasLayer) -> Button:
	var tile := InventoryOverlay.make_tile(ed, 86.0)
	tile.set_drag_forwarding(
		_no_drag_data,
		_can_drop_scroll,
		_drop_scroll_on.bind(ed, is_equipped, root, overlay)
	)
	return tile


# ── Drag & drop forwarding callbacks ──────────────────────────────────────────

func _scroll_drag_data(_pos: Vector2, sd: ScrollData, tile: Control) -> Variant:
	var prev := TextureRect.new()
	prev.texture = load(InventoryOverlay.ICON_PATH)
	prev.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	prev.stretch_mode = TextureRect.STRETCH_SCALE
	prev.custom_minimum_size = Vector2(56, 56)
	prev.size = Vector2(56, 56)
	prev.modulate = sd.stat_color()
	tile.set_drag_preview(prev)
	return {"scroll": sd}


func _no_drag_data(_pos: Vector2) -> Variant:
	return null


func _reject_drop(_pos: Vector2, _data: Variant) -> bool:
	return false


func _ignore_drop(_pos: Vector2, _data: Variant) -> void:
	pass


func _can_drop_scroll(_pos: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.has("scroll")


func _drop_scroll_on(_pos: Vector2, data: Variant, ed: EquipmentData,
		is_equipped: bool, root: Control, overlay: CanvasLayer) -> void:
	var sd: ScrollData = data["scroll"]
	var result := _apply_scroll(sd, ed, is_equipped)
	GameState.scrolls.erase(sd)
	_build_scroll_result(sd, ed.equipment_name, result[0], result[1], root, overlay)


func _build_merge_view(root: Control, overlay: CanvasLayer) -> void:
	_clear_children(root)
	# Sanitise merge selection — items may have been removed by prior actions.
	_merge_sel = _merge_sel.filter(func(i): return GameState.inventory.has(i))

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left   = 80.0
	vbox.offset_right  = -80.0
	vbox.offset_top    = 50.0
	vbox.offset_bottom = -50.0
	vbox.add_theme_constant_override("separation", 10)
	root.add_child(vbox)

	var title := Label.new()
	title.text = "Merge Items"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 38)
	title.modulate = Color(1.0, 0.62, 0.25)
	vbox.add_child(title)

	var hint := Label.new()
	hint.text = "Left-click: select 3 items of the same rarity  •  Right-click: deselect  (80% success)"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 16)
	hint.modulate = Color(0.65, 0.65, 0.65)
	vbox.add_child(hint)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	var grid := GridContainer.new()
	grid.columns = 8
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(grid)

	if GameState.inventory.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "No items in inventory."
		empty_lbl.modulate = Color(0.5, 0.5, 0.5)
		empty_lbl.add_theme_font_size_override("font_size", 15)
		grid.add_child(empty_lbl)

	for item in GameState.inventory:
		var ed := item as EquipmentData
		if ed == null:
			continue
		var selected := _merge_sel.has(ed)

		var tile := InventoryOverlay.make_tile(ed, 86.0)
		if selected:
			tile.modulate = Color(1.30, 1.30, 0.90)
			var check := Label.new()
			check.text = "✓"
			check.add_theme_font_size_override("font_size", 18)
			check.modulate = Color(1.0, 0.9, 0.3)
			check.set_anchors_preset(Control.PRESET_TOP_LEFT)
			check.offset_left = 4.0; check.offset_right = 24.0
			check.offset_top = 0.0;  check.offset_bottom = 22.0
			check.mouse_filter = Control.MOUSE_FILTER_IGNORE
			tile.add_child(check)

		var cap_ed := ed
		tile.pressed.connect(func():
			if not _merge_sel.has(cap_ed) and _merge_sel.size() < 3:
				_merge_sel.append(cap_ed)
				_build_merge_view(root, overlay)
		)
		tile.gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseButton and ev.pressed \
					and ev.button_index == MOUSE_BUTTON_RIGHT \
					and _merge_sel.has(cap_ed):
				_merge_sel.erase(cap_ed)
				_build_merge_view(root, overlay)
		)
		grid.add_child(tile)

	# Merge button — always visible, activates when the selection is valid.
	var merge_btn := Button.new()
	merge_btn.add_theme_font_size_override("font_size", 18)
	merge_btn.custom_minimum_size = Vector2(0, 50)
	if _is_valid_merge():
		var src_rarity: EquipmentData.Rarity = _merge_sel[0].rarity
		merge_btn.text = "Merge 3 %s  →  %s  (80%%)" % [
			EquipmentData.rarity_name(src_rarity),
			EquipmentData.rarity_name(src_rarity + 1),
		]
		merge_btn.modulate = EquipmentData.rarity_color(src_rarity + 1)
		merge_btn.pressed.connect(func(): _do_merge(root, overlay))
	else:
		merge_btn.text = "Merge  (select 3 items of the same rarity)"
		merge_btn.disabled = true
		merge_btn.modulate = Color(0.6, 0.6, 0.6)
	vbox.add_child(merge_btn)

	var back_btn := Button.new()
	back_btn.text = "Back"
	back_btn.add_theme_font_size_override("font_size", 17)
	back_btn.pressed.connect(func(): _build_forge_menu(root, overlay))
	vbox.add_child(back_btn)


# ── Enchant overlay ───────────────────────────────────────────────────────────

func _show_enchant_overlay(map_node: MapNode) -> void:
	var overlay := CanvasLayer.new()
	overlay.layer = 10
	add_child(overlay)

	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 0.85)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(bg)

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(root)

	_build_enchant_select(map_node, root, overlay)


func _build_enchant_select(map_node: MapNode, root: Control, overlay: CanvasLayer) -> void:
	_clear_children(root)

	var panel := Panel.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left   = -490.0
	panel.offset_right  =  490.0
	panel.offset_top    = -360.0
	panel.offset_bottom =  360.0
	root.add_child(panel)

	var outer := VBoxContainer.new()
	outer.set_anchors_preset(Control.PRESET_FULL_RECT)
	outer.offset_left = 18; outer.offset_right  = -18
	outer.offset_top  = 14; outer.offset_bottom = -14
	outer.add_theme_constant_override("separation", 8)
	panel.add_child(outer)

	# Header
	var title := Label.new()
	title.text = "✦  Enchant Equipment"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	title.modulate = Color(0.45, 0.75, 1.0)
	outer.add_child(title)

	var sub := Label.new()
	sub.text = "Boost an item's primary stat. Coins spent either way."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 16)
	sub.modulate = Color(0.68, 0.68, 0.68)
	outer.add_child(sub)

	var coins_lbl := Label.new()
	coins_lbl.text = "Your coins: %d" % GameState.coins
	coins_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	coins_lbl.add_theme_font_size_override("font_size", 17)
	coins_lbl.modulate = Color(1.0, 0.85, 0.1)
	outer.add_child(coins_lbl)

	outer.add_child(HSeparator.new())

	var scr := ScrollContainer.new()
	scr.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(scr)

	var cv := VBoxContainer.new()
	cv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cv.add_theme_constant_override("separation", 5)
	scr.add_child(cv)

	# Collect all equipment (equipped + inventory)
	var all_equip: Array[EquipmentData] = []
	for slot_int in [0, 1, 2, 3, 4]:
		var ed := GameState.equipment.get(slot_int) as EquipmentData
		if ed != null:
			all_equip.append(ed)
	for item in GameState.inventory:
		var ed := item as EquipmentData
		if ed != null:
			all_equip.append(ed)

	if all_equip.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "You have no equipment to enchant."
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_lbl.add_theme_font_size_override("font_size", 17)
		empty_lbl.modulate = Color(0.5, 0.5, 0.5)
		cv.add_child(empty_lbl)
	else:
		cv.add_child(_inv_section_label("EQUIPPED"))
		var has_equipped := false
		for slot_int in [0, 1, 2, 3, 4]:
			var ed := GameState.equipment.get(slot_int) as EquipmentData
			if ed != null:
				cv.add_child(_build_enchant_row(ed, map_node, root, overlay))
				has_equipped = true
		if not has_equipped:
			var none_lbl := Label.new()
			none_lbl.text = "Nothing equipped."
			none_lbl.add_theme_font_size_override("font_size", 13)
			none_lbl.modulate = Color(0.45, 0.45, 0.45)
			cv.add_child(none_lbl)

		var inv_equip := GameState.inventory.filter(func(i): return i is EquipmentData)
		if not inv_equip.is_empty():
			cv.add_child(HSeparator.new())
			cv.add_child(_inv_section_label("INVENTORY"))
			for item in inv_equip:
				cv.add_child(_build_enchant_row(item as EquipmentData, map_node, root, overlay))

	outer.add_child(HSeparator.new())

	var leave_btn := Button.new()
	leave_btn.text = "Leave"
	leave_btn.add_theme_font_size_override("font_size", 18)
	leave_btn.custom_minimum_size = Vector2(0, 42)
	leave_btn.pressed.connect(func(): overlay.queue_free())
	outer.add_child(leave_btn)


func _build_enchant_row(ed: EquipmentData, map_node: MapNode, root: Control, overlay: CanvasLayer) -> HBoxContainer:
	var cost := ENCHANT_BASE_COST * (ed.enchant_level + 1)
	var rate: int = ENCHANT_SUCCESS_RATES[mini(ed.enchant_level, ENCHANT_SUCCESS_RATES.size() - 1)]
	var can_afford := GameState.coins >= cost

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var info := Label.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_font_size_override("font_size", 14)
	info.text = "%s%s  [%s]  %s  →  %dg  |  %d%%" % [
		ed.equipment_name,
		_equipment_enchant_tag(ed),
		EquipmentData.rarity_name(ed.rarity),
		_equipment_stat_summary(ed),
		cost, rate,
	]
	var base_col := EquipmentData.rarity_color(ed.rarity)
	info.modulate = base_col if can_afford else base_col * Color(0.55, 0.55, 0.55, 1.0)
	info.tooltip_text = _equipment_tooltip(ed)
	info.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(info)

	var enchant_btn := Button.new()
	enchant_btn.text = "Enchant"
	enchant_btn.add_theme_font_size_override("font_size", 13)
	enchant_btn.disabled = not can_afford
	var cap_ed := ed
	var cap_cost := cost
	var cap_rate := rate
	enchant_btn.pressed.connect(func():
		GameState.coins -= cap_cost
		_refresh_coins_label()
		var succeeded := (randi() % 100) < cap_rate
		if succeeded:
			_apply_enchant(cap_ed)
		_build_enchant_result(cap_ed, succeeded, map_node, root, overlay)
	)
	row.add_child(enchant_btn)
	return row


func _apply_enchant(ed: EquipmentData) -> void:
	if   ed.damage_bonus     > 0: ed.damage_bonus     += 1
	elif ed.block_per_turn   > 0: ed.block_per_turn   += 1
	elif ed.max_hp_bonus     > 0: ed.max_hp_bonus     += 3
	elif ed.max_energy_bonus > 0: ed.max_energy_bonus += 1
	elif ed.crit_chance      > 0: ed.crit_chance      += 5
	else:
		match ed.slot:
			0: ed.damage_bonus     += 1
			1: ed.block_per_turn   += 1
			2: ed.max_hp_bonus     += 3
			3: ed.max_energy_bonus += 1
			4: ed.crit_chance      += 5
	ed.enchant_level += 1


func _build_enchant_result(ed: EquipmentData, succeeded: bool,
		map_node: MapNode, root: Control, overlay: CanvasLayer) -> void:
	_clear_children(root)

	# On success: permanently close the enchant node.
	if succeeded:
		map_node.always_accessible = false
		_refresh()
		queue_redraw()

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.offset_left   = -400.0; vbox.offset_right  =  400.0
	vbox.offset_top    = -220.0; vbox.offset_bottom =  220.0
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 22)
	root.add_child(vbox)

	var result_lbl := Label.new()
	result_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_lbl.add_theme_font_size_override("font_size", 44)
	if succeeded:
		result_lbl.text = "Enchantment holds!"
		result_lbl.modulate = Color(0.25, 0.75, 1.0)
	else:
		result_lbl.text = "The enchantment fades…"
		result_lbl.modulate = Color(1.0, 0.38, 0.28)
	vbox.add_child(result_lbl)

	var detail_lbl := Label.new()
	detail_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail_lbl.add_theme_font_size_override("font_size", 20)
	if succeeded:
		detail_lbl.text = "%s%s  —  %s" % [
			ed.equipment_name, _equipment_enchant_tag(ed), _equipment_stat_summary(ed)
		]
	else:
		detail_lbl.text = "%s is unchanged." % ed.equipment_name
	detail_lbl.modulate = EquipmentData.rarity_color(ed.rarity)
	vbox.add_child(detail_lbl)

	var coins_lbl := Label.new()
	coins_lbl.text = "Coins remaining: %d" % GameState.coins
	coins_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	coins_lbl.add_theme_font_size_override("font_size", 17)
	coins_lbl.modulate = Color(1.0, 0.85, 0.1)
	vbox.add_child(coins_lbl)

	if not succeeded:
		var try_again_btn := Button.new()
		try_again_btn.text = "Enchant Again"
		try_again_btn.add_theme_font_size_override("font_size", 18)
		try_again_btn.custom_minimum_size = Vector2(180, 0)
		try_again_btn.pressed.connect(func(): _build_enchant_select(map_node, root, overlay))
		vbox.add_child(try_again_btn)

	var ok_btn := Button.new()
	ok_btn.text = "Done"
	ok_btn.add_theme_font_size_override("font_size", 18)
	ok_btn.custom_minimum_size = Vector2(180, 0)
	ok_btn.pressed.connect(func(): overlay.queue_free())
	vbox.add_child(ok_btn)


# ── Special node overlays (mystery / gamble / treasure / shrine / dojo / bounty / secret) ──

## Creates a standard dark full-screen overlay. Returns [overlay, root].
func _new_overlay() -> Array:
	var overlay := CanvasLayer.new()
	overlay.layer = 10
	add_child(overlay)
	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 0.84)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(bg)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(root)
	return [overlay, root]


## Centered VBox container for overlay content.
func _overlay_vbox(root: Control, half_h: float = 240.0) -> VBoxContainer:
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.offset_left = -380.0; vbox.offset_right  = 380.0
	vbox.offset_top  = -half_h; vbox.offset_bottom = half_h
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 16)
	root.add_child(vbox)
	return vbox


func _overlay_title(vbox: VBoxContainer, text: String, color: Color, size: int = 42) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", size)
	lbl.modulate = color
	vbox.add_child(lbl)


func _overlay_text(vbox: VBoxContainer, text: String, size: int = 18,
		color: Color = Color(0.78, 0.78, 0.78)) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", size)
	lbl.modulate = color
	vbox.add_child(lbl)


func _overlay_button(vbox: VBoxContainer, text: String, on_press: Callable,
		size: int = 20, dim: bool = false) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.add_theme_font_size_override("font_size", size)
	btn.custom_minimum_size = Vector2(0, 48)
	if dim:
		btn.modulate = Color(0.65, 0.65, 0.65)
	btn.pressed.connect(on_press)
	vbox.add_child(btn)
	return btn


## Simple result screen: title + detail + Continue.
func _build_simple_result(title: String, title_col: Color, detail: String,
		root: Control, overlay: CanvasLayer) -> void:
	_clear_children(root)
	var vbox := _overlay_vbox(root, 180.0)
	_overlay_title(vbox, title, title_col)
	_overlay_text(vbox, detail, 20)
	_overlay_text(vbox, "Coins: %d" % GameState.coins, 16, Color(1.0, 0.85, 0.1))
	_overlay_button(vbox, "Continue", func(): overlay.queue_free())


## "You found equipment" screen with Equip / Stash / Leave.
func _build_found_equipment(ed: EquipmentData, title: String,
		root: Control, overlay: CanvasLayer) -> void:
	_clear_children(root)
	var vbox := _overlay_vbox(root)
	_overlay_title(vbox, title, Color(0.9, 0.75, 0.2), 36)
	_overlay_text(vbox, EquipmentData.rarity_name(ed.rarity), 16, EquipmentData.rarity_color(ed.rarity))
	_overlay_text(vbox, ed.equipment_name + _equipment_enchant_tag(ed), 30, Color.WHITE)
	_overlay_text(vbox, _equipment_stat_summary(ed), 20, Color(0.9, 0.9, 0.6))
	_overlay_button(vbox, "Take it", func():
		var old := GameState.equipment.get(ed.slot) as EquipmentData
		if old != null:
			GameState.inventory.append(old)
		GameState.equipment[ed.slot] = ed
		overlay.queue_free()
	)
	_overlay_button(vbox, "Add to inventory", func():
		GameState.inventory.append(ed)
		overlay.queue_free()
	, 17)
	_overlay_button(vbox, "Leave it", func(): overlay.queue_free(), 16, true)


## "You found a scroll" screen with Take / Leave.
func _build_found_scroll(sd: ScrollData, title: String,
		root: Control, overlay: CanvasLayer) -> void:
	_clear_children(root)
	var vbox := _overlay_vbox(root)
	_overlay_title(vbox, title, sd.stat_color(), 36)
	_overlay_text(vbox, sd.scroll_name, 28, Color.WHITE)
	_overlay_text(vbox, "+%d %s  |  %d%% success  /  %d%% destroy on fail" % [
		sd.boost_amount, sd.stat_label(), sd.success_chance, sd.destroy_chance,
	], 17, Color(0.85, 0.85, 0.65))
	_overlay_button(vbox, "Take it", func():
		GameState.scrolls.append(sd)
		overlay.queue_free()
	)
	_overlay_button(vbox, "Leave it", func(): overlay.queue_free(), 16, true)


## Random equipment from the pool, optionally with boosted rarity.
func _roll_equipment(rarity_boost: int = 0) -> EquipmentData:
	var pool: Array = EquipmentData.all().duplicate()
	pool.shuffle()
	var ed := (pool[0] as EquipmentData).duplicate()
	ed.rarity = mini(ed.rarity + rarity_boost, EquipmentData.Rarity.LEGENDARY)
	return ed


# ── Mystery "?" node ──────────────────────────────────────────────────────────

func _show_mystery_overlay(node: MapNode) -> void:
	var parts := _new_overlay()
	var overlay: CanvasLayer = parts[0]
	var root: Control = parts[1]

	# Mostly good, rare disaster.
	var roll := randi() % 100
	if roll < 25:
		var coins := randi_range(40, 80) * GameState.floor
		GameState.coins += coins
		_refresh_coins_label()
		_build_simple_result("A hidden cache!", Color(1.0, 0.85, 0.1),
				"You found %d coins." % coins, root, overlay)
	elif roll < 45:
		_build_found_equipment(_roll_equipment(), "Something glints in the dark…", root, overlay)
	elif roll < 60:
		var pool: Array = ScrollData.all().duplicate()
		pool.shuffle()
		_build_found_scroll((pool[0] as ScrollData).duplicate(), "An old satchel…", root, overlay)
	elif roll < 75:
		var card_pool: Array = CardData.reward_pool().duplicate()
		card_pool.shuffle()
		var cd := (card_pool[0] as CardData).duplicate()
		GameState.deck.append(cd)
		_build_simple_result("A forgotten technique!", Color(0.55, 0.85, 1.0),
				"%s was added to your deck." % cd.card_name, root, overlay)
	elif roll < 90:
		_build_ambush_intro("An enemy was waiting!", node, MapNode.Type.FIGHT, 1, root, overlay)
	elif roll < 97:
		var lost := GameState.coins / 4
		GameState.coins -= lost
		_refresh_coins_label()
		_build_simple_result("A trap!", Color(1.0, 0.38, 0.28),
				"Bandits made off with %d coins." % lost, root, overlay)
	else:
		_build_ambush_intro("An ELITE ambush!", node, MapNode.Type.ELITE, 2, root, overlay)


## Intro screen before a forced fight (mystery/secret ambushes).
func _build_ambush_intro(title: String, node: MapNode, tier: int, mult: int,
		root: Control, overlay: CanvasLayer) -> void:
	_clear_children(root)
	var vbox := _overlay_vbox(root, 160.0)
	_overlay_title(vbox, title, Color(1.0, 0.38, 0.28))
	if mult > 1:
		_overlay_text(vbox, "Defeat it for ×%d coins!" % mult, 18, Color(1.0, 0.85, 0.1))
	_overlay_button(vbox, "Fight!", func():
		overlay.queue_free()
		_go_battle(node, tier, 0, mult)
	)


# ── Gamble node ───────────────────────────────────────────────────────────────

func _show_gamble_overlay() -> void:
	var parts := _new_overlay()
	var overlay: CanvasLayer = parts[0]
	var root: Control = parts[1]
	_build_gamble_menu(root, overlay)


func _build_gamble_menu(root: Control, overlay: CanvasLayer) -> void:
	_clear_children(root)
	var vbox := _overlay_vbox(root, 260.0)
	_overlay_title(vbox, "The Gambler", Color(0.95, 0.35, 0.65), 48)
	_overlay_text(vbox, "\"Feeling lucky, traveler?\"")
	_overlay_text(vbox, "Your coins: %d" % GameState.coins, 17, Color(1.0, 0.85, 0.1))

	var stake := GameState.coins / 2
	var flip_btn := _overlay_button(vbox,
			"Coin Flip — wager %d coins, 50%% to double them" % stake, func():
		if randi() % 2 == 0:
			GameState.coins += stake
			_refresh_coins_label()
			_build_simple_result("You won!", Color(0.25, 1.0, 0.45),
					"The coin lands your way. +%d coins!" % stake, root, overlay)
		else:
			GameState.coins -= stake
			_refresh_coins_label()
			_build_simple_result("You lost…", Color(1.0, 0.38, 0.28),
					"The gambler grins. −%d coins." % stake, root, overlay)
	)
	flip_btn.disabled = GameState.coins < 10

	var chest_btn := _overlay_button(vbox,
			"Demon Chest — pay 60 coins, 70% chance of a rare item", func():
		GameState.coins -= 60
		_refresh_coins_label()
		if randi() % 100 < 70:
			_build_found_equipment(_roll_equipment(1), "The chest creaks open…", root, overlay)
		else:
			_build_simple_result("Empty!", Color(0.7, 0.7, 0.7),
					"The chest was full of cobwebs.", root, overlay)
	)
	chest_btn.disabled = GameState.coins < 60

	_overlay_button(vbox, "Walk away", func(): overlay.queue_free(), 17, true)


# ── Treasure node ─────────────────────────────────────────────────────────────

func _show_treasure_overlay() -> void:
	var parts := _new_overlay()
	var overlay: CanvasLayer = parts[0]
	var root: Control = parts[1]

	var roll := randi() % 100
	if roll < 50:
		_build_found_equipment(_roll_equipment(1), "You found a treasure chest!", root, overlay)
	elif roll < 80:
		var coins := randi_range(60, 100) * GameState.floor
		GameState.coins += coins
		_refresh_coins_label()
		_build_simple_result("Treasure!", Color(1.0, 0.85, 0.1),
				"The chest held %d coins." % coins, root, overlay)
	else:
		var pool: Array = ScrollData.all().duplicate()
		pool.shuffle()
		_build_found_scroll((pool[0] as ScrollData).duplicate(),
				"You found a treasure chest!", root, overlay)


# ── Cursed shrine node ────────────────────────────────────────────────────────

func _show_shrine_overlay() -> void:
	var parts := _new_overlay()
	var overlay: CanvasLayer = parts[0]
	var root: Control = parts[1]

	var ed := _roll_equipment(2)

	var vbox := _overlay_vbox(root, 280.0)
	_overlay_title(vbox, "Cursed Shrine", Color(0.72, 0.35, 0.95), 46)
	_overlay_text(vbox, "An offering rests on the altar. Dark whispers promise power… for a price.")
	_overlay_text(vbox, EquipmentData.rarity_name(ed.rarity), 16, EquipmentData.rarity_color(ed.rarity))
	_overlay_text(vbox, ed.equipment_name, 28, Color.WHITE)
	_overlay_text(vbox, _equipment_stat_summary(ed), 20, Color(0.9, 0.9, 0.6))
	_overlay_text(vbox, "Curse: −10 max HP for the rest of this run", 17, Color(1.0, 0.45, 0.4))
	_overlay_button(vbox, "Accept the offering", func():
		GameState.max_hp_curse += 10
		GameState.inventory.append(ed)
		_build_simple_result("The curse takes hold…", Color(0.72, 0.35, 0.95),
				"%s added to inventory. Max HP −10 this run." % ed.equipment_name,
				root, overlay)
	)
	_overlay_button(vbox, "Leave the shrine alone", func(): overlay.queue_free(), 17, true)


# ── Dojo node ─────────────────────────────────────────────────────────────────

func _show_dojo_overlay(node: MapNode) -> void:
	var parts := _new_overlay()
	var overlay: CanvasLayer = parts[0]
	var root: Control = parts[1]

	var vbox := _overlay_vbox(root, 200.0)
	_overlay_title(vbox, "Training Dojo", Color(0.5, 0.9, 0.4), 46)
	_overlay_text(vbox, "\"Defeat me, and I will perfect one of your techniques — free of charge.\"")
	_overlay_button(vbox, "Accept the duel", func():
		overlay.queue_free()
		_go_battle(node, MapNode.Type.FIGHT)
	)
	_overlay_button(vbox, "Decline", func(): overlay.queue_free(), 17, true)


## Shown after winning the dojo duel: pick a card, upgraded free + guaranteed.
func _show_dojo_upgrade_overlay() -> void:
	var parts := _new_overlay()
	var overlay: CanvasLayer = parts[0]
	var root: Control = parts[1]

	var vbox := _overlay_vbox(root, 320.0)
	_overlay_title(vbox, "Master's Lesson", Color(0.5, 0.9, 0.4), 40)
	_overlay_text(vbox, "\"Well fought. Choose a technique to perfect.\"  (+2 damage, free)")

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 320)
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
		var cap := card
		btn.pressed.connect(func():
			cap.damage += 2
			cap.level += 1
			_build_simple_result("Technique perfected!", Color(0.5, 0.9, 0.4),
					"%s  →  Damage: %d  (Lv.%d)" % [cap.card_name, cap.damage, cap.level],
					root, overlay)
		)
		grid.add_child(btn)


# ── Bounty node ───────────────────────────────────────────────────────────────

func _show_bounty_overlay(node: MapNode) -> void:
	var parts := _new_overlay()
	var overlay: CanvasLayer = parts[0]
	var root: Control = parts[1]

	var vbox := _overlay_vbox(root, 200.0)
	_overlay_title(vbox, "Bounty Board", Color(0.9, 0.55, 0.3), 46)
	_overlay_text(vbox, "WANTED: defeat the target within 3 rounds.")
	_overlay_text(vbox, "Reward: coins ×3", 19, Color(1.0, 0.85, 0.1))
	_overlay_button(vbox, "Take the contract", func():
		overlay.queue_free()
		_go_battle(node, MapNode.Type.FIGHT, 3)
	)
	_overlay_button(vbox, "Not today", func(): overlay.queue_free(), 17, true)


# ── Secret node ───────────────────────────────────────────────────────────────

func _show_secret_overlay(node: MapNode) -> void:
	var parts := _new_overlay()
	var overlay: CanvasLayer = parts[0]
	var root: Control = parts[1]

	var roll := randi() % 100
	if roll < 30:
		_build_found_equipment(_roll_equipment(2), "A hidden trove!", root, overlay)
	elif roll < 55:
		var coins := randi_range(100, 150) * GameState.floor
		GameState.coins += coins
		_refresh_coins_label()
		_build_simple_result("A hidden trove!", Color(1.0, 0.85, 0.1),
				"You found %d coins stashed away." % coins, root, overlay)
	elif roll < 80:
		_build_demon_trade(root, overlay)
	else:
		_build_ambush_intro("A guardian protects this place!", node, MapNode.Type.ELITE, 2, root, overlay)


## Unique encounter: trade max HP for a legendary item.
func _build_demon_trade(root: Control, overlay: CanvasLayer) -> void:
	_clear_children(root)
	var ed := _roll_equipment(99)   # always LEGENDARY
	var vbox := _overlay_vbox(root, 280.0)
	_overlay_title(vbox, "A Demon Awaits", Color(0.9, 0.2, 0.3), 46)
	_overlay_text(vbox, "\"Your vitality for my treasure. A fair trade, mortal.\"")
	_overlay_text(vbox, EquipmentData.rarity_name(ed.rarity), 16, EquipmentData.rarity_color(ed.rarity))
	_overlay_text(vbox, ed.equipment_name, 28, Color.WHITE)
	_overlay_text(vbox, _equipment_stat_summary(ed), 20, Color(0.9, 0.9, 0.6))
	_overlay_text(vbox, "Price: −15 max HP for the rest of this run", 17, Color(1.0, 0.45, 0.4))
	_overlay_button(vbox, "Make the trade", func():
		GameState.max_hp_curse += 15
		GameState.inventory.append(ed)
		_build_simple_result("The deal is struck.", Color(0.9, 0.2, 0.3),
				"%s added to inventory. Max HP −15 this run." % ed.equipment_name,
				root, overlay)
	)
	_overlay_button(vbox, "Refuse", func(): overlay.queue_free(), 17, true)


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
