## Map
## Radial mind-map floor. Generates the graph, draws connection lines,
## spawns node buttons, and manages traversal (which nodes are reachable).
##
## Traversal rule: a node is reachable if it is connected to at least one
## already-visited node and has not been visited itself.
class_name MapScene
extends Control

const BATTLE_SCENE := "res://scenes/map/battlefield.tscn"

## Actual card visual reused on deck-editing screens (forge / remove / upgrade).
const CARD_SCENE := preload("res://scenes/cards/card.tscn")
## Display size for those picker cards. Kept at the card's native 200×300 so the
## fixed label font sizes stay correctly proportioned (they don't scale with the
## card size), then laid out in a wrapping, scrollable flow.
const PICKER_CARD_SIZE := Vector2(200, 300)

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
## "Coins: " until a coin icon exists in assets/ui/hud, then just the number.
var _coins_prefix := "Coins: "
## Legend open/closed, remembered across map visits for this session.
static var _legend_open := true
var _deck_btn: Button = null
var _reachable: Array[int] = []        # updated by _refresh(), used by _draw()
var _reachable_from: Dictionary = {}   # reachable node id → id of the visited node that first revealed it
var _current_node: MapNode = null      # node whose overlay is currently open
## Items selected for merging in the inventory overlay.
var _merge_sel: Array = []

# ── Scroll screen state ───────────────────────────────────────────────────────
var _scroll_slot: EquipmentData = null      # item currently placed in the centre slot
var _scroll_slot_equipped: bool = false     # was it equipped (vs from inventory)?
var _scroll_slot_node: Control = null       # the centre slot Panel, for effect anims
var _scroll_last_msg: String = ""           # result line shown after the last scroll
var _scroll_last_color: Color = Color.WHITE

## How fast the map follows the mouse while panning.
## 1.0 = map moves 1:1 with the cursor; 0.5 = half speed; >1.0 = faster.
const PAN_SPEED := 1.0
## Breathing room (px) kept around the map edges when panned to a limit.
## Panning is only allowed as far as needed to reveal off-screen nodes.
const PAN_PADDING := 80.0

var _pan_offset: Vector2 = Vector2.ZERO
var _pan_drag_origin: Vector2 = Vector2.ZERO
var _is_panning: bool = false
var _map_bounds: Rect2 = Rect2()   # bounding box of all node positions, computed once
var _bg_mat: ShaderMaterial = null


func _process(_delta: float) -> void:
	# Continuous redraw drives the marching dashes on frontier paths.
	queue_redraw()


func _ready() -> void:
	_add_background()
	if GameState.has_map():
		_nodes = GameState.map_nodes
	else:
		_nodes = MapGenerator.generate(GameState.floor_num)
		GameState.map_nodes = _nodes
	# Materialise the starter deck up front so the Deck viewer works
	# before the first battle (battlefield keeps its own fallback).
	if not GameState.has_deck():
		var starter: Array[CardData] = []
		starter.assign(CardData.starter_deck())
		GameState.deck = starter

	_add_ink_background()
	_spawn_uis()
	_compute_map_bounds()
	# Start the view centred on the player's frontier, not on START.
	if GameState.current_node_id >= 0 and GameState.current_node_id < _nodes.size():
		_pan_offset = get_viewport_rect().size / 2.0 - _nodes[GameState.current_node_id].pos
		_apply_pan()
	_refresh()
	queue_redraw()
	_add_hud()

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
	# The background layer doesn't count — it's always there.
	for child in get_children():
		if child is CanvasLayer and child.name != "BgLayer":
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
	if _bg_mat != null:
		_bg_mat.set_shader_parameter("pan", _pan_offset)
	queue_redraw()


## Procedural sumi-e backdrop on a CanvasLayer BELOW the map canvas, so the
## connection lines (drawn in _draw) stay on top of it.
func _add_ink_background() -> void:
	var layer := CanvasLayer.new()
	layer.name = "BgLayer"
	layer.layer = -1
	add_child(layer)

	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg_mat = HudKit.ink_material()
	rect.material = _bg_mat
	layer.add_child(rect)


func _compute_map_bounds() -> void:
	if _nodes.is_empty():
		return
	var mn := _nodes[0].pos
	var mx := _nodes[0].pos
	for node in _nodes:
		mn = mn.min(node.pos)
		mx = mx.max(node.pos)
	# Positions are node CENTERS — grow by the largest node's half-size
	# (boss = RADIUS × 2.6) plus breathing room, so panning to the limit
	# shows the outermost ring fully instead of cutting it at the edge.
	_map_bounds = Rect2(mn, mx - mn).grow(MapNodeUI.RADIUS * 2.6 * 0.5 + 30.0)


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
	# Background lives on the BgLayer CanvasLayer (layer -1), so everything
	# drawn here renders on top of it. Flat fallback when the shader is off.
	if _bg_mat == null:
		draw_rect(Rect2(Vector2.ZERO, get_viewport_rect().size), Color(0.075, 0.085, 0.115))

	# Secret node glint hints — commented out, secret nodes are now fully invisible until discovered.
	#for node in _nodes:
		#if node.type == MapNode.Type.SECRET and not node.secret_revealed and not node.visited:
			#var p := node.pos + _pan_offset
			#draw_circle(p, 7.0, Color(1.0, 0.95, 0.6, 0.10))
			#draw_circle(p, 2.5, Color(1.0, 0.95, 0.7, 0.30))

	# Solid lines between visited nodes (already traveled).
	for node in _nodes:
		if not node.visited:
			continue
		for cid in node.connections:
			if cid <= node.id:
				continue
			if _nodes[cid].visited:
				var a := node.pos + _pan_offset
				var b := _nodes[cid].pos + _pan_offset
				var d := (b - a).normalized()
				var inset := MapNodeUI.RADIUS + 2.0
				draw_line(a + d * inset, b - d * inset, Color(0.40, 0.40, 0.44, 0.70), 3.0, true)

	# Dotted lines only from the visited node that first revealed each reachable node.
	# Endpoints are inset by node radius so lines stop at the icon edge, not the center.
	# The dash phase marches toward the unexplored node ("go this way").
	var dash_phase := Time.get_ticks_msec() / 1000.0 * 14.0
	for cid in _reachable:
		if cid not in _reachable_from:
			continue
		var target   := _nodes[cid]
		var revealer := _nodes[int(_reachable_from[cid])]
		var from_pos := revealer.pos + _pan_offset
		var to_pos   := target.pos   + _pan_offset
		var dir      := (to_pos - from_pos).normalized()
		var inset    := MapNodeUI.RADIUS + 2.0
		_draw_dashed_line(from_pos + dir * inset, to_pos - dir * inset,
				Color(0.80, 0.80, 0.80, 0.80), 6.0, 5.0, 2.0, dash_phase)


func _draw_dashed_line(from: Vector2, to: Vector2, color: Color,
		dash: float = 6.0, gap: float = 5.0, width: float = 2.0,
		phase: float = 0.0) -> void:
	var dir := to - from
	var total := dir.length()
	if total < 0.001:
		return
	dir /= total
	var pos := -fposmod(phase, dash + gap)
	var drawing := true
	while pos < total:
		var seg_end := pos + (dash if drawing else gap)
		if drawing:
			var a := maxf(pos, 0.0)
			var b := minf(seg_end, total)
			if b > a:
				draw_line(from + dir * a, from + dir * b, color, width, true)
		pos = seg_end
		drawing = not drawing


# ── Internal ──────────────────────────────────────────────────────────────────

func _add_background() -> void:
	pass  # background is drawn in _draw() so it doesn't cover the map lines


func _spawn_uis() -> void:
	for node in _nodes:
		var ui := MapNodeUI.new()
		add_child(ui)
		ui.setup(node)
		ui.node_clicked.connect(_on_node_clicked)
		_uis[node.id] = ui


func _refresh() -> void:
	_reachable.clear()
	_reachable_from.clear()
	for node in _nodes:
		if not node.visited:
			continue
		for cid in node.connections:
			if not _nodes[cid].visited and cid not in _reachable_from:
				_reachable.append(cid)
				_reachable_from[cid] = node.id

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


func _close_current_node() -> void:
	if _current_node == null:
		return
	_current_node.always_accessible = false
	_current_node = null
	_refresh()
	queue_redraw()


func _on_node_clicked(node: MapNode) -> void:
	node.visited = true
	_current_node = node

	# Battle nodes leave the map immediately — skip repainting so the player
	# doesn't glimpse the newly-revealed nodes under the transition. They'll
	# appear when the map is rebuilt on return from battle.
	var leaving_for_battle := node.type in [
		MapNode.Type.FIGHT, MapNode.Type.ELITE, MapNode.Type.BOSS]
	if not leaving_for_battle:
		_refresh()
		queue_redraw()

	match node.type:
		MapNode.Type.FIGHT, MapNode.Type.ELITE, MapNode.Type.BOSS:
			GameState.current_node_id = node.id
			SceneTransition.change_scene(BATTLE_SCENE)
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
	SceneTransition.change_scene(BATTLE_SCENE)


const CARD_VIEWER_SCENE := preload("res://scenes/ui/card_viewer.tscn")
var _card_viewer: CardViewer = null


## Builds the whole map HUD: coins + floor panel top-left,
## Inventory / Deck buttons top-right.
func _add_hud() -> void:
	var panel := HudKit.coins_floor_panel()
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.position = Vector2(16, 14)
	add_child(panel)
	_coins_label = panel.find_child("CoinsLabel", true, false) as Label
	_coins_prefix = "" if HudKit.icon("coin") != null else "Coins: "

	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 8)
	btns.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	btns.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	btns.offset_top = 14.0
	btns.offset_right = -16.0
	add_child(btns)

	var stats_btn := _hud_button("Stats", "stats", Color(0.55, 0.85, 0.75))
	stats_btn.pressed.connect(_show_stats_overlay)
	btns.add_child(stats_btn)

	var inv_btn := _hud_button("Inventory", "inventory", Color(0.76, 0.55, 0.35))
	inv_btn.pressed.connect(func(): InventoryOverlay.open(self))
	btns.add_child(inv_btn)

	_deck_btn = _hud_button(_deck_btn_label(), "deck", Color(0.87, 0.52, 0.45))
	_deck_btn.pressed.connect(_show_deck_viewer)
	btns.add_child(_deck_btn)

	# ── Bottom-left: control hints ────────────────────────────────────────────
	var hints := VBoxContainer.new()
	hints.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	hints.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hints.offset_left = 16.0
	hints.offset_bottom = -12.0
	hints.add_theme_constant_override("separation", 2)
	add_child(hints)
	for hint in ["Right-drag to pan", "Left-click a glowing node to travel"]:
		var lbl := Label.new()
		lbl.text = hint
		lbl.add_theme_font_size_override("font_size", 20)
		lbl.modulate = Color(1.0, 1.0, 1.0, 0.38)
		hints.add_child(lbl)

	# ── Bottom-right: node-type legend with a collapse tab above it ──────────
	var legend_box := VBoxContainer.new()
	legend_box.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	legend_box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	legend_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	legend_box.offset_right = -16.0
	legend_box.offset_bottom = -12.0
	legend_box.add_theme_constant_override("separation", 0)
	add_child(legend_box)

	# Tab hugs the box's top-left; only its top corners are rounded so the
	# two shapes read as one attached piece.
	var tab_btn := _hud_button("Legend ▾" if _legend_open else "Legend ▴")
	tab_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	for state in ["normal", "hover", "pressed"]:
		var s: StyleBoxFlat = tab_btn.get_theme_stylebox(state).duplicate()
		s.corner_radius_bottom_left = 0
		s.corner_radius_bottom_right = 0
		tab_btn.add_theme_stylebox_override(state, s)
	legend_box.add_child(tab_btn)

	var legend_style := _hud_style()
	legend_style.set_border_width_all(0)
	legend_style.corner_radius_top_left = 0
	legend_style.corner_radius_top_right = 0
	var legend_panel := PanelContainer.new()
	legend_panel.add_theme_stylebox_override("panel", legend_style)
	legend_panel.visible = _legend_open
	legend_box.add_child(legend_panel)

	tab_btn.pressed.connect(func():
		MapScene._legend_open = not MapScene._legend_open
		legend_panel.visible = MapScene._legend_open
		tab_btn.text = "Legend ▾" if MapScene._legend_open else "Legend ▴"
	)

	var legend := GridContainer.new()
	legend.columns = 2
	legend.add_theme_constant_override("h_separation", 36)
	legend.add_theme_constant_override("v_separation", 8)
	legend_panel.add_child(legend)

	# Unique node types on this floor. START is obvious; SECRET stays secret.
	var types: Array = []
	for node in _nodes:
		if node.type in [MapNode.Type.START, MapNode.Type.SECRET]:
			continue
		if node.type not in types:
			types.append(node.type)
	types.sort()

	for t in types:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		legend.add_child(row)
		var icon_rect := TextureRect.new()
		icon_rect.custom_minimum_size = Vector2(36, 36)
		icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var icon_path := MapNodeUI._icon_path(t)
		if ResourceLoader.exists(icon_path):
			icon_rect.texture = load(icon_path)
		row.add_child(icon_rect)
		var txt := Label.new()
		txt.text = _type_name(t)
		txt.add_theme_font_size_override("font_size", 26)
		txt.modulate = Color(0.80, 0.80, 0.84)
		row.add_child(txt)


## HUD building blocks live in HudKit (shared with the battlefield).
func _hud_style() -> StyleBoxFlat:
	return HudKit.style()


static func _hud_icon(icon_name: String) -> Texture2D:
	return HudKit.icon(icon_name)


static func _tinted(tex: Texture2D, tint: Color) -> Texture2D:
	return HudKit.tinted(tex, tint)


func _hud_button(label: String, icon_name: String = "",
		icon_tint: Color = Color.WHITE) -> Button:
	return HudKit.button(label, icon_name, icon_tint)


static func _type_name(t: MapNode.Type) -> String:
	match t:
		MapNode.Type.FIGHT:    return "Fight"
		MapNode.Type.ELITE:    return "Elite"
		MapNode.Type.BOSS:     return "Boss"
		MapNode.Type.SHOP:     return "Shop"
		MapNode.Type.REST:     return "Wizard"
		MapNode.Type.EVENT:    return "Event"
		MapNode.Type.ENCHANT:  return "Enchant"
		MapNode.Type.FORGE:    return "Forge"
		MapNode.Type.MYSTERY:  return "Mystery"
		MapNode.Type.GAMBLE:   return "Gamble"
		MapNode.Type.TREASURE: return "Treasure"
		MapNode.Type.SHRINE:   return "Shrine"
		MapNode.Type.DOJO:     return "Dojo"
		MapNode.Type.BOUNTY:   return "Bounty"
	return "?"


## Player stat sheet — shared with the battlefield via HudKit.
func _show_stats_overlay() -> void:
	HudKit.show_stats(self)


## Label like "Cards (9+5)": deck actions + the permanent move cards.
func _deck_btn_label() -> String:
	return "Cards (%d+%d)" % [GameState.deck.size(), MovePool.MOVE_IDS.size()]


func _show_deck_viewer() -> void:
	if _card_viewer == null or not is_instance_valid(_card_viewer):
		_card_viewer = CARD_VIEWER_SCENE.instantiate()
		add_child(_card_viewer)
	_refresh_coins_label()
	var cards: Array = GameState.deck.duplicate()
	for id in MovePool.MOVE_IDS:
		cards.append(CardData.by_id(id))
	_card_viewer.show_cards("Cards  (%d+%d)" % [GameState.deck.size(), MovePool.MOVE_IDS.size()], cards)


func _refresh_coins_label() -> void:
	if is_instance_valid(_coins_label):
		_coins_label.text = _coins_prefix + str(GameState.coins)
	if is_instance_valid(_deck_btn):
		_deck_btn.text = _deck_btn_label()


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

	# Format C: choices dealt as cards.
	var row := EventTemplates.choice_frame(root, "Event",
			"A mysterious stranger offers his services. Which fate will you draw?",
			Color(0.85, 0.55, 1.0))

	var remove_cost := REMOVE_BASE_COST * (GameState.cards_removed + 1)
	var remove_card := EventTemplates.choice_card("Remove a Card",
			"Erase one technique from your deck.\n\n%d coins" % remove_cost,
			Color(0.95, 0.40, 0.40), load("res://assets/ui/icon_discard_8.png"))
	remove_card.pressed.connect(func(): _build_remove_select(root, overlay))
	row.add_child(remove_card)

	var scavenge_card := EventTemplates.choice_card("Scavenge Ruins",
			"Search the rubble for equipment,\nscrolls… or something stranger.",
			Color(0.90, 0.75, 0.25), load("res://assets/map/nodes/treasure.png"))
	scavenge_card.pressed.connect(func(): _build_scavenge_result(root, overlay))
	row.add_child(scavenge_card)

	var leave_card := EventTemplates.choice_card("Leave",
			"Walk away.\nSome fates are better unturned.",
			Color(0.55, 0.55, 0.60))
	leave_card.pressed.connect(func(): overlay.queue_free())
	row.add_child(leave_card)


## Clickable tile showing an actual card visual (art, name, live description,
## "+N" enchant in the name) plus an optional footer line. Used by the deck-
## editing screens (forge / remove / dojo) instead of plain text buttons.
func _make_picker_card(cd: CardData, footer: String, enabled: bool, on_pick: Callable) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)

	var btn := Button.new()
	btn.flat = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = PICKER_CARD_SIZE
	btn.disabled = not enabled
	if enabled and on_pick.is_valid():
		btn.pressed.connect(on_pick)
	box.add_child(btn)

	var card: GameCard = CARD_SCENE.instantiate()
	card.card_size = PICKER_CARD_SIZE
	card.data = cd
	card.undraggable = true
	card.set_anchors_preset(Control.PRESET_FULL_RECT)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE   # let clicks reach the Button
	if not enabled:
		card.modulate = Color(0.55, 0.55, 0.55)
	btn.add_child(card)

	if footer != "":
		var lbl := Label.new()
		lbl.text = footer
		lbl.add_theme_font_size_override("font_size", 14)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl.custom_minimum_size = Vector2(PICKER_CARD_SIZE.x, 0)
		if not enabled:
			lbl.modulate = Color(0.55, 0.55, 0.55)
		box.add_child(lbl)

	return box


## A vertical-only ScrollContainer holding a wrapping row of picker cards.
## Returns the HFlowContainer to populate.
func _card_picker_flow(parent: Control) -> HFlowContainer:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)

	# Pad inside the scroll so the first card row isn't clipped against the top edge.
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	scroll.add_child(margin)

	var flow := HFlowContainer.new()
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flow.add_theme_constant_override("h_separation", 12)
	flow.add_theme_constant_override("v_separation", 12)
	margin.add_child(flow)
	return flow


func _build_forge_select(root: Control, overlay: CanvasLayer) -> void:
	_clear_children(root)

	# Format D: workbench list.
	var vbox := EventTemplates.merchant_split(root, "forge", "res://assets/map/nodes/forge.png")

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

	var flow := _card_picker_flow(vbox)

	for card in GameState.deck:
		if card == null or card.type == CardData.CardType.MOVE:
			continue   # move cards can't be forged
		var cost := FORGE_BASE_COST * (card.level + 1)
		var rate: int = FORGE_SUCCESS_RATES[mini(card.level, FORGE_SUCCESS_RATES.size() - 1)]
		var can_afford := GameState.coins >= cost

		var footer := "Cost: %dg  |  %d%%" % [cost, rate]
		var captured_card := card
		var captured_cost := cost
		var captured_rate := rate
		flow.add_child(_make_picker_card(card, footer, can_afford, func():
			GameState.coins -= captured_cost
			_refresh_coins_label()
			var succeeded := (randi() % 100) < captured_rate
			if succeeded:
				captured_card.damage += 2
				captured_card.upgrades += 1
			captured_card.level += 1
			_build_forge_result(captured_card, succeeded, root, overlay)
		))

	var back_btn := Button.new()
	back_btn.text = "Back"
	back_btn.add_theme_font_size_override("font_size", 17)
	back_btn.pressed.connect(func(): _build_forge_menu(root, overlay))
	vbox.add_child(back_btn)


func _build_forge_result(card: CardData, succeeded: bool, root: Control, overlay: CanvasLayer) -> void:
	_clear_children(root)

	var vbox := EventTemplates.result_flash(root, 180.0)

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
		detail_lbl.text = "%s  →  Damage: %d   (Lv.%d)" % [card.display_name(), card.damage, card.level]
	else:
		detail_lbl.text = "%s is unchanged.   (Lv.%d)" % [card.display_name(), card.level]
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

	# Format D: workbench list.
	var vbox := EventTemplates.merchant_split(root, "event", "res://assets/map/nodes/event.png")

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

	var flow := _card_picker_flow(vbox)

	for card in GameState.deck:
		if card == null or card.type == CardData.CardType.MOVE:
			continue   # move cards can't be removed
		var captured_card := card
		flow.add_child(_make_picker_card(card, "", can_afford and safe_to_remove, func():
			GameState.coins -= remove_cost
			GameState.cards_removed += 1
			GameState.deck.erase(captured_card)
			_refresh_coins_label()
			_close_current_node()
			overlay.queue_free()
		))

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

	# 10% of scavenged equipment finds are the mysterious key;
	# otherwise a normal weighted drop.
	var ed: EquipmentData
	if randi() % 100 < 10:
		ed = (EquipmentData.by_id(&"key") as EquipmentData).duplicate()
	else:
		ed = EquipmentData.random_drop()

	var vbox := EventTemplates.result_flash(root, 240.0)

	var title := Label.new()
	title.text = "You found equipment!" if EquipmentData.is_equippable(ed) else "You found an item!"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	title.modulate = Color(0.9, 0.75, 0.2)
	vbox.add_child(title)

	_overlay_item_tile(vbox, ed)

	var name_lbl := Label.new()
	name_lbl.text = ed.equipment_name
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 28)
	name_lbl.modulate = EquipmentData.rarity_color(ed.rarity)
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
	take_btn.text = "Add to inventory"
	take_btn.add_theme_font_size_override("font_size", 20)
	take_btn.custom_minimum_size = Vector2(160, 0)
	take_btn.pressed.connect(func():
		GameState.inventory.append(ed)
		_close_current_node()
		overlay.queue_free()
	)
	vbox.add_child(take_btn)

	var leave_btn := Button.new()
	leave_btn.text = "Leave it"
	leave_btn.add_theme_font_size_override("font_size", 16)
	leave_btn.modulate = Color(0.65, 0.65, 0.65)
	leave_btn.pressed.connect(func(): overlay.queue_free())
	vbox.add_child(leave_btn)


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
		# Reward is an actual item of the next tier, so rarity and stats agree.
		var pool: Array = EquipmentData.of_rarity(src_rarity + 1)
		new_item = (pool.pick_random() as EquipmentData).duplicate()
		GameState.inventory.append(new_item)

	_build_merge_result(new_item, success, src_rarity, root, overlay)


func _build_merge_result(new_item, success: bool, src_rarity: int,
		root: Control, overlay: CanvasLayer) -> void:
	_clear_children(root)

	var vbox := EventTemplates.result_flash(root, 200.0)

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
		_overlay_item_tile(vbox, ed)
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
		# Scroll boosts count toward the item's upgrade cap.
		ed.enchant_level += 1
		return [true, false]
	else:
		var destroyed: bool = (randi() % 100) < sd.destroy_chance
		if destroyed:
			if is_equipped:
				GameState.equipment.erase(ed.slot)
		
			else:
				GameState.inventory.erase(ed)
		return [false, destroyed]


# ── Scavenge: scroll drop ─────────────────────────────────────────────────────

func _build_scavenge_scroll_result(root: Control, overlay: CanvasLayer) -> void:
	_clear_children(root)

	var pool: Array = ScrollData.all().duplicate()
	pool.shuffle()
	var sd: ScrollData = (pool[0] as ScrollData).duplicate()

	var vbox := EventTemplates.result_flash(root, 240.0)

	var title := Label.new()
	title.text = "You found a scroll!"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	title.modulate = sd.stat_color()
	vbox.add_child(title)

	_overlay_item_tile(vbox, sd)

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
	take_btn.text = "Add to inventory"
	take_btn.add_theme_font_size_override("font_size", 20)
	take_btn.custom_minimum_size = Vector2(160, 0)
	take_btn.pressed.connect(func():
		GameState.scrolls.append(sd)
		_close_current_node()
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

	# Format B: the wizard speaks.
	var vbox := EventTemplates.dialogue_split(root, "wizard", "The Wizard",
			Color(0.45, 0.88, 0.95), "res://assets/map/nodes/rest.png")

	var desc := Label.new()
	desc.text = "\"I can erase one technique from your memory. Choose wisely.\""
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.add_theme_font_size_override("font_size", 18)
	desc.modulate = Color(0.72, 0.72, 0.72)
	vbox.add_child(desc)

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

	var flow := _card_picker_flow(vbox)

	for card in GameState.deck:
		if card == null or card.type == CardData.CardType.MOVE:
			continue   # move cards can't be removed
		var captured_card := card
		flow.add_child(_make_picker_card(card, "", safe_to_remove, func():
			GameState.deck.erase(captured_card)
			_build_wizard_done(captured_card.display_name(), root, overlay)
		))

	var leave_btn := Button.new()
	leave_btn.text = "Decline"
	leave_btn.add_theme_font_size_override("font_size", 17)
	leave_btn.modulate = Color(0.65, 0.65, 0.65)
	leave_btn.pressed.connect(func(): overlay.queue_free())
	vbox.add_child(leave_btn)


func _build_wizard_done(card_name: String, root: Control, overlay: CanvasLayer) -> void:
	_clear_children(root)

	var vbox := EventTemplates.result_flash(root, 160.0)

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
	ok_btn.pressed.connect(func(): _close_current_node(); overlay.queue_free())
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
		for i in SHOP_EQUIP_COUNT:
			var drop := EquipmentData.random_drop()
			if drop != null:
				map_node.shop_stock_equip.append(drop)

		var scroll_pool: Array = ScrollData.all().duplicate()
		scroll_pool.shuffle()
		for i in mini(SHOP_SCROLL_COUNT, scroll_pool.size()):
			map_node.shop_stock_scrolls.append((scroll_pool[i] as ScrollData).duplicate())

		map_node.shop_stocked = true

	_build_shop_view(map_node.shop_stock_equip, map_node.shop_stock_scrolls, map_node, root, overlay)


func _build_shop_view(stock_equip: Array, stock_scrolls: Array,
		map_node: MapNode, root: Control, overlay: CanvasLayer) -> void:
	_clear_children(root)

	# Format D: merchant counter.
	var outer := EventTemplates.merchant_split(root, "merchant", "res://assets/map/nodes/shop.png")

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
	outer.add_child(_inv_section_label("EQUIPMENT"))

	if stock_equip.is_empty():
		var sold_lbl := Label.new()
		sold_lbl.text = "Sold out!"
		sold_lbl.modulate = Color(0.5, 0.5, 0.5)
		sold_lbl.add_theme_font_size_override("font_size", 14)
		outer.add_child(sold_lbl)
	else:
		# Tile grid: click an item to buy it, price shown under each tile.
		var eq_grid := HBoxContainer.new()
		eq_grid.alignment = BoxContainer.ALIGNMENT_CENTER
		eq_grid.add_theme_constant_override("separation", 28)
		outer.add_child(eq_grid)
		for ed in stock_equip:
			var price: int = SHOP_EQUIP_PRICES.get(ed.rarity, 1)
			var can_afford := GameState.coins >= price

			var cell := VBoxContainer.new()
			cell.add_theme_constant_override("separation", 4)
			eq_grid.add_child(cell)

			var tile := InventoryOverlay.make_tile(ed, 110.0)
			tile.disabled = not can_afford
			if not can_afford:
				tile.modulate = Color(0.55, 0.55, 0.55)
			var cap_ed: EquipmentData = ed
			var cap_price: int = price
			tile.pressed.connect(func():
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
			cell.add_child(tile)

			var price_lbl := Label.new()
			price_lbl.text = "%dg" % price
			price_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			price_lbl.add_theme_font_size_override("font_size", 16)
			price_lbl.modulate = Color(1.0, 0.85, 0.1) if can_afford else Color(0.45, 0.45, 0.45)
			cell.add_child(price_lbl)

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
		var sc_grid := HBoxContainer.new()
		sc_grid.alignment = BoxContainer.ALIGNMENT_CENTER
		sc_grid.add_theme_constant_override("separation", 28)
		outer.add_child(sc_grid)
		for scroll in stock_scrolls:
			var sd := scroll as ScrollData
			var can_afford := GameState.coins >= SHOP_SCROLL_PRICE

			var cell := VBoxContainer.new()
			cell.add_theme_constant_override("separation", 4)
			sc_grid.add_child(cell)

			var tile := InventoryOverlay.make_scroll_tile(sd, 110.0)
			tile.disabled = not can_afford
			if not can_afford:
				tile.modulate = Color(0.55, 0.55, 0.55)
			var cap_sd: ScrollData = sd
			tile.pressed.connect(func():
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
			cell.add_child(tile)

			var price_lbl := Label.new()
			price_lbl.text = "%dg" % SHOP_SCROLL_PRICE
			price_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			price_lbl.add_theme_font_size_override("font_size", 16)
			price_lbl.modulate = Color(1.0, 0.85, 0.1) if can_afford else Color(0.45, 0.45, 0.45)
			cell.add_child(price_lbl)

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

	# Format C: choices dealt as cards.
	var row := EventTemplates.choice_frame(root, "The Forge",
			"The blacksmith's hammer never rests.", Color(1.0, 0.62, 0.25))

	var forge_card := EventTemplates.choice_card("Forge a Card",
			"+2 damage on success.\nCoins spent either way.\n\n%d+ coins" % FORGE_BASE_COST,
			Color(1.0, 0.62, 0.25), load("res://assets/map/nodes/forge.png"))
	forge_card.pressed.connect(func(): _build_forge_select(root, overlay))
	row.add_child(forge_card)

	var scroll_card := EventTemplates.choice_card("Use a Scroll",
			"Apply a scroll's power\nto a piece of equipment.\n\n%d owned" % GameState.scrolls.size(),
			Color(0.75, 0.55, 0.95), load("res://assets/map/nodes/enchant.png"))
	scroll_card.disabled = GameState.scrolls.is_empty()
	scroll_card.pressed.connect(func(): _build_scroll_select(root, overlay))
	row.add_child(scroll_card)

	var merge_card := EventTemplates.choice_card("Merge Items",
			"3 items of the same rarity\nbecome one of the next tier.",
			Color(0.35, 0.75, 0.95), load("res://assets/ui/icon_three_card.png"))
	merge_card.pressed.connect(func():
		_merge_sel.clear()
		_build_merge_view(root, overlay)
	)
	row.add_child(merge_card)

	var leave_card := EventTemplates.choice_card("Leave",
			"The hammer can wait.",
			Color(0.55, 0.55, 0.60))
	leave_card.pressed.connect(func(): overlay.queue_free())
	row.add_child(leave_card)


func _build_scroll_select(root: Control, overlay: CanvasLayer, fresh: bool = true) -> void:
	_clear_children(root)
	if fresh:
		_scroll_slot = null
		_scroll_last_msg = ""
	# Drop a stale slotted item that was removed/destroyed elsewhere.
	if _scroll_slot != null and not _slot_item_exists(_scroll_slot):
		_scroll_slot = null

	# Format D: workbench list.
	var vbox := EventTemplates.merchant_split(root, "forge", "res://assets/map/nodes/forge.png")

	var title := Label.new()
	title.text = "Use a Scroll"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 38)
	title.modulate = Color(0.85, 0.65, 1.0)
	vbox.add_child(title)

	var hint := Label.new()
	hint.text = "Drag a scroll onto the item in the slot." if _scroll_slot != null \
		else "Click or drag an item into the slot, then apply a scroll."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 16)
	hint.modulate = Color(0.65, 0.65, 0.65)
	vbox.add_child(hint)

	# Outcome of the previous scroll, shown until the next action.
	if _scroll_last_msg != "":
		var msg := Label.new()
		msg.text = _scroll_last_msg
		msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		msg.add_theme_font_size_override("font_size", 17)
		msg.modulate = _scroll_last_color
		vbox.add_child(msg)

	# Two columns: the item slot on the left, scrolls + item lists on the right.
	var cols := HBoxContainer.new()
	cols.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 24)
	vbox.add_child(cols)

	# ── Left box: the centre slot, vertically centred ────────────────────────
	var left_box := _boxed_panel()
	left_box.size_flags_stretch_ratio = 0.85
	cols.add_child(left_box)
	var left := CenterContainer.new()
	left_box.add_child(left)
	left.add_child(_build_scroll_slot(root, overlay))

	# ── Right box: scrolls (drag sources) + placeable items ──────────────────
	var right_box := _boxed_panel()
	right_box.size_flags_stretch_ratio = 1.3
	cols.add_child(right_box)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 8)
	right_box.add_child(right)

	right.add_child(_inv_section_label("SCROLLS"))
	var s_grid := GridContainer.new()
	s_grid.columns = 8
	s_grid.add_theme_constant_override("h_separation", 8)
	s_grid.add_theme_constant_override("v_separation", 8)
	right.add_child(s_grid)

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

	right.add_child(HSeparator.new())

	# ── Items you can place in the slot (click or drag) ───────────────────────
	var scr := ScrollContainer.new()
	scr.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(scr)

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
		if ed == null or ed.enchant_level >= ed.max_enchant or ed == _scroll_slot:
			continue
		eq_grid.add_child(_make_item_source_tile(ed, true, root, overlay))

	cv.add_child(_inv_section_label("ITEMS"))
	var inv_grid := GridContainer.new()
	inv_grid.columns = 8
	inv_grid.add_theme_constant_override("h_separation", 8)
	inv_grid.add_theme_constant_override("v_separation", 8)
	cv.add_child(inv_grid)
	for item in GameState.inventory:
		var ed := item as EquipmentData
		if ed == null or not EquipmentData.is_equippable(ed) \
				or ed.enchant_level >= ed.max_enchant or ed == _scroll_slot:
			continue
		inv_grid.add_child(_make_item_source_tile(ed, false, root, overlay))

	var back_btn := Button.new()
	back_btn.text = "Back"
	back_btn.add_theme_font_size_override("font_size", 17)
	back_btn.pressed.connect(func(): _build_forge_menu(root, overlay))
	vbox.add_child(back_btn)


## A framed container box (background + border + inner padding), used to make
## the scroll screen's two columns read as separate panels.
func _boxed_panel() -> PanelContainer:
	var p := PanelContainer.new()
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.07, 0.10, 0.85)
	sb.set_border_width_all(2)
	sb.border_color = Color(0.30, 0.30, 0.36)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(14)
	p.add_theme_stylebox_override("panel", sb)
	return p


## True while the slotted item is still owned by the player.
func _slot_item_exists(ed: EquipmentData) -> bool:
	return GameState.equipment.values().has(ed) or GameState.inventory.has(ed)


## The centre slot: empty (accepts an item) or filled (accepts a scroll).
func _build_scroll_slot(root: Control, overlay: CanvasLayer) -> Control:
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 6)

	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(150, 150)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.09, 0.12)
	sb.set_border_width_all(3)
	sb.border_color = Color(0.55, 0.42, 0.75) if _scroll_slot != null else Color(0.32, 0.32, 0.38)
	sb.set_corner_radius_all(12)
	panel.add_theme_stylebox_override("panel", sb)
	_scroll_slot_node = panel
	col.add_child(panel)

	if _scroll_slot == null:
		var lbl := Label.new()
		lbl.text = "＋\nPlace an item"
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 16)
		lbl.modulate = Color(0.5, 0.5, 0.56)
		lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(lbl)
		panel.set_drag_forwarding(
			_no_drag_data,
			_can_drop_item_in_slot,
			_drop_item_in_slot.bind(root, overlay)
		)
	else:
		var icon := InventoryOverlay.make_tile(_scroll_slot, 132.0)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE   # let the panel catch drops
		icon.position = Vector2(9, 9)
		icon.size = Vector2(132, 132)
		panel.add_child(icon)
		panel.set_drag_forwarding(
			_no_drag_data,
			_can_drop_scroll_in_slot,
			_drop_scroll_in_slot.bind(root, overlay)
		)
		# Click the slotted item to take it back out.
		panel.tooltip_text = "Click to remove"
		panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		panel.gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT \
					and not ev.pressed:
				_scroll_slot = null
				_build_scroll_select(root, overlay, false)
		)

		# Name on its own line (fits the slot width), enchant count on a second
		# line — so a long name+count never gets clipped to "…".
		var name_lbl := Label.new()
		name_lbl.text = _scroll_slot.equipment_name
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_lbl.add_theme_font_size_override("font_size", 14)
		name_lbl.modulate = Color(0.85, 0.85, 0.9)
		name_lbl.custom_minimum_size = Vector2(150, 0)
		name_lbl.clip_text = true
		name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		col.add_child(name_lbl)

		var lvl_lbl := Label.new()
		lvl_lbl.text = "✦ %d / %d" % [_scroll_slot.enchant_level, _scroll_slot.max_enchant]
		lvl_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lvl_lbl.add_theme_font_size_override("font_size", 12)
		lvl_lbl.modulate = Color(1.0, 0.85, 0.4)
		col.add_child(lvl_lbl)

		var tip := Label.new()
		tip.text = "(click to remove)"
		tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tip.add_theme_font_size_override("font_size", 12)
		tip.modulate = Color(0.5, 0.5, 0.55)
		col.add_child(tip)

	return col


## An item tile in the lists — click OR drag it to fill the centre slot.
func _make_item_source_tile(ed: EquipmentData, is_equipped: bool,
		root: Control, overlay: CanvasLayer) -> Button:
	var tile := InventoryOverlay.make_tile(ed, 86.0)
	tile.pressed.connect(func(): _place_in_slot(ed, is_equipped, root, overlay))
	tile.set_drag_forwarding(
		_item_drag_data.bind(ed, is_equipped, tile),
		_reject_drop,
		_ignore_drop
	)
	return tile


func _place_in_slot(ed: EquipmentData, is_equipped: bool,
		root: Control, overlay: CanvasLayer) -> void:
	_scroll_slot = ed
	_scroll_slot_equipped = is_equipped
	_scroll_last_msg = ""
	_build_scroll_select(root, overlay, false)


## Apply a scroll to the slotted item, animate the outcome in the box, rebuild.
func _resolve_scroll_on_slot(sd: ScrollData, root: Control, overlay: CanvasLayer) -> void:
	var ed := _scroll_slot
	if ed == null:
		return
	var result := _apply_scroll(sd, ed, _scroll_slot_equipped)
	GameState.scrolls.erase(sd)
	var success: bool = result[0]
	var destroyed: bool = result[1]

	if success:
		_scroll_last_msg = "%s glows — +%d %s!" % [ed.equipment_name, sd.boost_amount, sd.stat_label()]
		_scroll_last_color = Color(0.35, 1.0, 0.5)
	elif destroyed:
		_scroll_last_msg = "%s shattered!" % ed.equipment_name
		_scroll_last_color = Color(1.0, 0.35, 0.3)
	else:
		_scroll_last_msg = "The scroll fizzled — %s is unchanged." % ed.equipment_name
		_scroll_last_color = Color(0.95, 0.65, 0.3)

	await _play_slot_effect(_scroll_slot_node, success, destroyed)

	if destroyed:
		_scroll_slot = null
	_build_scroll_select(root, overlay, false)


## Simple in-box feedback: green glow (success), orange wobble (fizzle),
## red flash + shatter-out (destroyed).
func _play_slot_effect(node: Control, success: bool, destroyed: bool) -> void:
	if not is_instance_valid(node):
		return
	node.pivot_offset = node.size / 2.0
	var tw := create_tween().set_ease(Tween.EASE_OUT)
	if success:
		tw.tween_property(node, "modulate", Color(0.5, 1.8, 0.7), 0.12)
		tw.parallel().tween_property(node, "scale", Vector2(1.12, 1.12), 0.12)
		tw.tween_property(node, "modulate", Color.WHITE, 0.40)
		tw.parallel().tween_property(node, "scale", Vector2.ONE, 0.40)
	elif destroyed:
		tw.tween_property(node, "modulate", Color(2.0, 0.4, 0.3), 0.10)
		tw.tween_property(node, "modulate", Color(1.0, 1.0, 1.0, 0.0), 0.40)
		tw.parallel().tween_property(node, "scale", Vector2(0.55, 0.55), 0.40)
	else:
		tw.tween_property(node, "modulate", Color(1.7, 1.1, 0.4), 0.10)
		tw.tween_property(node, "rotation", deg_to_rad(7.0), 0.06)
		tw.tween_property(node, "rotation", deg_to_rad(-7.0), 0.06)
		tw.tween_property(node, "rotation", 0.0, 0.06)
		tw.tween_property(node, "modulate", Color.WHITE, 0.20)
	await tw.finished


# ── Drag & drop forwarding callbacks ──────────────────────────────────────────

func _scroll_drag_data(_pos: Vector2, sd: ScrollData, tile: Control) -> Variant:
	var prev := TextureRect.new()
	var art := InventoryOverlay.scroll_icon(sd)
	prev.texture = art if art != null else load(InventoryOverlay.ICON_PATH)
	prev.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	prev.stretch_mode = TextureRect.STRETCH_SCALE
	prev.custom_minimum_size = Vector2(56, 56)
	prev.size = Vector2(56, 56)
	if art == null:
		prev.modulate = sd.stat_color()
	tile.set_drag_preview(prev)
	return {"scroll": sd}


func _item_drag_data(_pos: Vector2, ed: EquipmentData, is_equipped: bool, tile: Control) -> Variant:
	var prev := TextureRect.new()
	var art := InventoryOverlay.equip_icon(ed)
	prev.texture = art if art != null else load(InventoryOverlay.ICON_PATH)
	prev.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	prev.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	prev.custom_minimum_size = Vector2(60, 60)
	prev.size = Vector2(60, 60)
	if art == null:
		prev.modulate = EquipmentData.rarity_color(ed.rarity)
	tile.set_drag_preview(prev)
	return {"item": ed, "equipped": is_equipped}


func _no_drag_data(_pos: Vector2) -> Variant:
	return null


func _reject_drop(_pos: Vector2, _data: Variant) -> bool:
	return false


func _ignore_drop(_pos: Vector2, _data: Variant) -> void:
	pass


func _can_drop_item_in_slot(_pos: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.has("item")


func _drop_item_in_slot(_pos: Vector2, data: Variant, root: Control, overlay: CanvasLayer) -> void:
	_place_in_slot(data["item"], data["equipped"], root, overlay)


func _can_drop_scroll_in_slot(_pos: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.has("scroll") \
		and _scroll_slot != null and _scroll_slot.enchant_level < _scroll_slot.max_enchant


func _drop_scroll_in_slot(_pos: Vector2, data: Variant, root: Control, overlay: CanvasLayer) -> void:
	_resolve_scroll_on_slot(data["scroll"], root, overlay)


func _build_merge_view(root: Control, overlay: CanvasLayer) -> void:
	_clear_children(root)
	# Sanitise merge selection — items may have been removed by prior actions.
	_merge_sel = _merge_sel.filter(func(i): return GameState.inventory.has(i))

	# Format D: workbench list.
	var vbox := EventTemplates.merchant_split(root, "forge", "res://assets/map/nodes/forge.png")

	var title := Label.new()
	title.text = "Merge Items"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 38)
	title.modulate = Color(1.0, 0.62, 0.25)
	vbox.add_child(title)

	var hint := Label.new()
	hint.text = "Click 3 items of the same rarity into the slots, then Merge.  (80% success)"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 16)
	hint.modulate = Color(0.65, 0.65, 0.65)
	vbox.add_child(hint)

	# Two columns: the three merge slots on the left, item list on the right.
	var cols := HBoxContainer.new()
	cols.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 24)
	vbox.add_child(cols)

	# ── Left box: three slots in a row, sized to the items (not stretched) ────
	var left_box := _boxed_panel()
	left_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER  # hug the slots
	cols.add_child(left_box)
	var left_center := CenterContainer.new()
	left_box.add_child(left_center)
	var slots := HBoxContainer.new()
	slots.add_theme_constant_override("separation", 10)
	left_center.add_child(slots)
	for i in range(3):
		slots.add_child(_merge_slot(i, root, overlay))

	# ── Right box: inventory items (click to place in the next slot) ─────────
	var right_box := _boxed_panel()
	right_box.size_flags_stretch_ratio = 1.3
	cols.add_child(right_box)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 8)
	right_box.add_child(right)

	right.add_child(_inv_section_label("ITEMS"))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(scroll)

	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(grid)

	var any_item := false
	for item in GameState.inventory:
		var ed := item as EquipmentData
		if ed == null or not EquipmentData.is_equippable(ed) or _merge_sel.has(ed):
			continue
		any_item = true
		var tile := InventoryOverlay.make_tile(ed, 86.0)
		var cap_ed := ed
		tile.pressed.connect(func():
			if not _merge_sel.has(cap_ed) and _merge_sel.size() < 3:
				_merge_sel.append(cap_ed)
				_build_merge_view(root, overlay)
		)
		grid.add_child(tile)

	if not any_item:
		var empty_lbl := Label.new()
		empty_lbl.text = "No items available to merge."
		empty_lbl.modulate = Color(0.5, 0.5, 0.5)
		empty_lbl.add_theme_font_size_override("font_size", 15)
		grid.add_child(empty_lbl)

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


## One of the three merge slots. Empty (waiting) or holding a placed item;
## clicking a filled slot removes that item from the selection.
func _merge_slot(index: int, root: Control, overlay: CanvasLayer) -> Control:
	var ed: EquipmentData = _merge_sel[index] if index < _merge_sel.size() else null

	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(96, 96)   # roughly one item-tile in size
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.09, 0.12)
	sb.set_border_width_all(3)
	sb.border_color = EquipmentData.rarity_color(ed.rarity) if ed != null \
		else Color(0.32, 0.32, 0.38)
	sb.set_corner_radius_all(12)
	panel.add_theme_stylebox_override("panel", sb)

	if ed == null:
		var lbl := Label.new()
		lbl.text = "＋"
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 26)
		lbl.modulate = Color(0.4, 0.4, 0.46)
		lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(lbl)
	else:
		var icon := InventoryOverlay.make_tile(ed, 80.0)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.position = Vector2(8, 8)
		icon.size = Vector2(80, 80)
		panel.add_child(icon)
		panel.tooltip_text = "Click to remove"
		panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var cap_ed := ed
		panel.gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT \
					and not ev.pressed:
				_merge_sel.erase(cap_ed)
				_build_merge_view(root, overlay)
		)

	return panel


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

	# Format D: workbench list.
	var outer := EventTemplates.merchant_split(root, "enchant", "res://assets/map/nodes/enchant.png")

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
		var eq_grid := HFlowContainer.new()
		eq_grid.add_theme_constant_override("h_separation", 22)
		eq_grid.add_theme_constant_override("v_separation", 14)
		cv.add_child(eq_grid)
		var has_equipped := false
		for slot_int in [0, 1, 2, 3, 4]:
			var ed := GameState.equipment.get(slot_int) as EquipmentData
			if ed != null:
				eq_grid.add_child(_build_enchant_cell(ed, map_node, root, overlay))
				has_equipped = true
		if not has_equipped:
			var none_lbl := Label.new()
			none_lbl.text = "Nothing equipped."
			none_lbl.add_theme_font_size_override("font_size", 13)
			none_lbl.modulate = Color(0.45, 0.45, 0.45)
			cv.add_child(none_lbl)

		var inv_equip := GameState.inventory.filter(
				func(i): return i is EquipmentData and EquipmentData.is_equippable(i))
		if not inv_equip.is_empty():
			cv.add_child(HSeparator.new())
			cv.add_child(_inv_section_label("INVENTORY"))
			var inv_grid := HFlowContainer.new()
			inv_grid.add_theme_constant_override("h_separation", 22)
			inv_grid.add_theme_constant_override("v_separation", 14)
			cv.add_child(inv_grid)
			for item in inv_equip:
				inv_grid.add_child(_build_enchant_cell(item as EquipmentData, map_node, root, overlay))

	outer.add_child(HSeparator.new())

	var leave_btn := Button.new()
	leave_btn.text = "Leave"
	leave_btn.add_theme_font_size_override("font_size", 18)
	leave_btn.custom_minimum_size = Vector2(0, 42)
	leave_btn.pressed.connect(func(): overlay.queue_free())
	outer.add_child(leave_btn)


## One enchant candidate: clickable item tile with cost | success rate below.
func _build_enchant_cell(ed: EquipmentData, map_node: MapNode, root: Control, overlay: CanvasLayer) -> VBoxContainer:
	var cost := ENCHANT_BASE_COST * (ed.enchant_level + 1)
	var rate: int = ENCHANT_SUCCESS_RATES[mini(ed.enchant_level, ENCHANT_SUCCESS_RATES.size() - 1)]
	var can_afford := GameState.coins >= cost
	var maxed := ed.enchant_level >= ed.max_enchant

	var cell := VBoxContainer.new()
	cell.add_theme_constant_override("separation", 4)

	var tile := InventoryOverlay.make_tile(ed, 96.0)
	tile.disabled = maxed or not can_afford
	if tile.disabled:
		tile.modulate = Color(0.55, 0.55, 0.55)
	var cap_ed := ed
	var cap_cost := cost
	var cap_rate := rate
	tile.pressed.connect(func():
		GameState.coins -= cap_cost
		_refresh_coins_label()
		var succeeded := (randi() % 100) < cap_rate
		if succeeded:
			_apply_enchant(cap_ed)
		_build_enchant_result(cap_ed, succeeded, map_node, root, overlay)
	)
	cell.add_child(tile)

	var info := Label.new()
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.add_theme_font_size_override("font_size", 13)
	if maxed:
		info.text = "MAX"
		info.modulate = Color(0.60, 0.60, 0.60)
	else:
		info.text = "%dg | %d%%" % [cost, rate]
		info.modulate = Color(1.0, 0.85, 0.1) if can_afford else Color(0.45, 0.45, 0.45)
	cell.add_child(info)
	return cell


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

	var vbox := EventTemplates.result_flash(root, 220.0)

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


func _overlay_title(vbox: VBoxContainer, text: String, color: Color, font_size: int = 42) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.modulate = color
	vbox.add_child(lbl)


func _overlay_text(vbox: VBoxContainer, text: String, font_size: int = 18,
		color: Color = Color(0.78, 0.78, 0.78)) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.modulate = color
	vbox.add_child(lbl)


func _overlay_button(vbox: VBoxContainer, text: String, on_press: Callable,
		font_size: int = 20, dim: bool = false) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.add_theme_font_size_override("font_size", font_size)
	btn.custom_minimum_size = Vector2(0, 48)
	if dim:
		btn.modulate = Color(0.65, 0.65, 0.65)
	btn.pressed.connect(on_press)
	vbox.add_child(btn)
	return btn


## Centered item tile (icon, rarity border, instant tooltip) for reward
## screens — the visual "item button" shown instead of plain text lines.
func _overlay_item_tile(vbox: VBoxContainer, item, tile_size: float = 132.0) -> void:
	var center := CenterContainer.new()
	vbox.add_child(center)
	var tile: Button
	if item is ScrollData:
		tile = InventoryOverlay.make_scroll_tile(item, tile_size)
	else:
		tile = InventoryOverlay.make_tile(item, tile_size)
	center.add_child(tile)


## Simple result screen: title + detail + Continue.
func _build_simple_result(title: String, title_col: Color, detail: String,
		root: Control, overlay: CanvasLayer) -> void:
	_clear_children(root)
	var vbox := EventTemplates.result_flash(root, 180.0)
	_overlay_title(vbox, title, title_col)
	_overlay_text(vbox, detail, 20)
	_overlay_text(vbox, "Coins: %d" % GameState.coins, 16, Color(1.0, 0.85, 0.1))
	_overlay_button(vbox, "Continue", func(): _close_current_node(); overlay.queue_free())


## "You found equipment" screen with Equip / Stash / Leave.
func _build_found_equipment(ed: EquipmentData, title: String,
		root: Control, overlay: CanvasLayer) -> void:
	_clear_children(root)
	var vbox := EventTemplates.result_flash(root)
	_overlay_title(vbox, title, Color(0.9, 0.75, 0.2), 36)
	_overlay_item_tile(vbox, ed)
	_overlay_text(vbox, ed.equipment_name + _equipment_enchant_tag(ed), 26,
			EquipmentData.rarity_color(ed.rarity))
	_overlay_text(vbox, _equipment_stat_summary(ed), 20, Color(0.9, 0.9, 0.6))
	_overlay_button(vbox, "Add to inventory", func():
		GameState.inventory.append(ed)
		_close_current_node()
		overlay.queue_free()
	)
	_overlay_button(vbox, "Leave it", func(): overlay.queue_free(), 16, true)


## "You found a scroll" screen with Take / Leave.
func _build_found_scroll(sd: ScrollData, title: String,
		root: Control, overlay: CanvasLayer) -> void:
	_clear_children(root)
	var vbox := EventTemplates.result_flash(root)
	_overlay_title(vbox, title, sd.stat_color(), 36)
	_overlay_item_tile(vbox, sd)
	_overlay_text(vbox, sd.scroll_name, 26, Color.WHITE)
	_overlay_text(vbox, "+%d %s  |  %d%% success  /  %d%% destroy on fail" % [
		sd.boost_amount, sd.stat_label(), sd.success_chance, sd.destroy_chance,
	], 17, Color(0.85, 0.85, 0.65))
	_overlay_button(vbox, "Add to inventory", func():
		GameState.scrolls.append(sd)
		_close_current_node()
		overlay.queue_free()
	)
	_overlay_button(vbox, "Leave it", func(): overlay.queue_free(), 16, true)


## Random equipment drop: weighted rarity roll, optionally boosted by tiers.
func _roll_equipment(rarity_boost: int = 0) -> EquipmentData:
	return EquipmentData.random_drop(rarity_boost)


# ── Mystery "?" node ──────────────────────────────────────────────────────────

func _show_mystery_overlay(node: MapNode) -> void:
	var parts := _new_overlay()
	var overlay: CanvasLayer = parts[0]
	var root: Control = parts[1]

	# Mostly good, rare disaster.
	var roll := randi() % 100
	if roll < 25:
		var coins := randi_range(40, 80) * GameState.floor_num
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
		var lost: int = GameState.coins / 4
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
	# Format A: narration on the scroll.
	var vbox := EventTemplates.scroll_split(root, "ambush", "res://assets/map/nodes/mystery.png")
	_overlay_title(vbox, title, Color(1.0, 0.38, 0.28))
	if mult > 1:
		_overlay_text(vbox, "Defeat it for ×%d coins!" % mult, 18, Color(1.0, 0.85, 0.1))
	_overlay_button(vbox, "Fight!", func():
		_close_current_node()
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
	# Format B: the gambler speaks.
	var vbox := EventTemplates.dialogue_split(root, "gambler", "The Gambler",
			Color(0.95, 0.35, 0.65), "res://assets/map/nodes/gamble.png")
	_overlay_text(vbox, "\"Feeling lucky, traveler?\"")
	_overlay_text(vbox, "Your coins: %d" % GameState.coins, 17, Color(1.0, 0.85, 0.1))

	var stake: int = GameState.coins / 2
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
		var coins := randi_range(60, 100) * GameState.floor_num
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

	# Format A: narration on the scroll.
	var vbox := EventTemplates.scroll_split(root, "shrine", "res://assets/map/nodes/shrine.png")
	_overlay_title(vbox, "Cursed Shrine", Color(0.72, 0.35, 0.95), 46)
	_overlay_text(vbox, "An offering rests on the altar. Dark whispers promise power… for a price.")
	_overlay_item_tile(vbox, ed)
	_overlay_text(vbox, ed.equipment_name, 26, EquipmentData.rarity_color(ed.rarity))
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

	# Format B: the master speaks.
	var vbox := EventTemplates.dialogue_split(root, "master", "Training Dojo",
			Color(0.5, 0.9, 0.4), "res://assets/map/nodes/dojo.png")
	_overlay_text(vbox, "\"Defeat me, and I will perfect one of your techniques — free of charge.\"")
	_overlay_button(vbox, "Accept the duel", func():
		_close_current_node()
		overlay.queue_free()
		_go_battle(node, MapNode.Type.FIGHT)
	)
	_overlay_button(vbox, "Decline", func(): overlay.queue_free(), 17, true)


## Shown after winning the dojo duel: pick a card, upgraded free + guaranteed.
func _show_dojo_upgrade_overlay() -> void:
	var parts := _new_overlay()
	var overlay: CanvasLayer = parts[0]
	var root: Control = parts[1]

	# Format B: the master speaks.
	var vbox := EventTemplates.dialogue_split(root, "master", "Master's Lesson",
			Color(0.5, 0.9, 0.4), "res://assets/map/nodes/dojo.png")
	_overlay_text(vbox, "\"Well fought. Choose a technique to perfect.\"  (+2 damage, free)")

	var flow := _card_picker_flow(vbox)
	(flow.get_parent() as Control).custom_minimum_size = Vector2(0, 320)

	for card in GameState.deck:
		if card == null or card.type == CardData.CardType.MOVE:
			continue   # move cards can't be upgraded
		var cap := card
		flow.add_child(_make_picker_card(card, "", true, func():
			cap.damage += 2
			cap.upgrades += 1
			cap.level += 1
			_build_simple_result("Technique perfected!", Color(0.5, 0.9, 0.4),
					"%s  →  Damage: %d  (Lv.%d)" % [cap.display_name(), cap.damage, cap.level],
					root, overlay)
		))


# ── Bounty node ───────────────────────────────────────────────────────────────

func _show_bounty_overlay(node: MapNode) -> void:
	var parts := _new_overlay()
	var overlay: CanvasLayer = parts[0]
	var root: Control = parts[1]

	# Format F: wanted poster — dark ink text on parchment.
	var vbox := EventTemplates.poster(root)
	_overlay_title(vbox, "WANTED", Color(0.30, 0.12, 0.08), 58)
	_overlay_text(vbox, "Defeat the target\nwithin 3 rounds.", 22, Color(0.22, 0.16, 0.09))
	_overlay_text(vbox, "REWARD: coins ×3", 24, Color(0.45, 0.28, 0.05))
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 14)
	vbox.add_child(spacer)
	_overlay_button(vbox, "Take the contract", func():
		_close_current_node()
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
		var coins := randi_range(100, 150) * GameState.floor_num
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
	# Format B: the demon speaks.
	var vbox := EventTemplates.dialogue_split(root, "demon", "A Demon Awaits",
			Color(0.9, 0.2, 0.3), "res://assets/map/nodes/secret.png")
	_overlay_text(vbox, "\"Your vitality for my treasure. A fair trade, mortal.\"")
	_overlay_item_tile(vbox, ed)
	_overlay_text(vbox, ed.equipment_name, 26, EquipmentData.rarity_color(ed.rarity))
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
