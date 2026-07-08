## Battlefield
## The battle scene controller and turn manager.
##
## WeGo turn loop:
##   PLAN    — drag actions into 3 ordered slots (a move from the right-side pool,
##             OR a card from the hand). The actual card moves into the slot
##             (move cards are duplicated since they're reusable). Press "Lock In".
##   RESOLVE — slots play out 0 → 1 → 2. Within a slot, MOVES before ATTACKS.
##             Death is checked between slots.
##   CLEANUP — played cards discard, energy regens, hand refills → back to PLAN.
##
## Clearing a slot also clears every slot AFTER it (later cards may depend on
## energy from earlier ones, e.g. Focus → Slash).
##
## The "Hide" button hides the slots + move pool so you can see the battlefield.
## The enemy's plan (`_enemy_plan`) is empty for now; Step 3b fills it via AI.
## `@tool` so token placement updates live in the editor too.
@tool
class_name Battlefield
extends Node2D

const HAND_SIZE := 5
const MAX_SLOTS := 3
const SHARE_OFFSET := 32.0   # px to nudge each token sideways when sharing a cell
const CARD_SCENE := preload("res://scenes/cards/card.tscn")
const CARD_SIZE := Vector2(200, 300)
const MAP_SCENE := "res://scenes/map/map.tscn"


enum Phase { PLAN, RESOLVE }

var _deck: Deck
var _player: Token
var _enemy: Token
var _hand: Hand
var _phase: int = Phase.PLAN

# Fixed 3 slots. Each entry is null or { "data": CardData, "consumable": bool, "card": GameCard }
var _plan: Array = [null, null, null]
var _enemy_plan: Array = []   # filled by AI in Step 3b

var _slot_nodes: Array = []
var _lock_in: Button
var _hide_btn: Button
var _move_keys: Dictionary = {}     # arrow keycode -> move CardData
var _moves_by_dir: Dictionary = {}  # Vector2i direction -> move CardData (for the AI)
var _toast_token: int = 0           # guards overlapping toast timers
var _round: int = 0                 # current round number (shown top-center)
var _player_damage_bonus: int = 0   # from equipped WEAPON
var _player_crit_chance: int = 0    # from equipped SHOES (0–100 %)
var _resolve_display: Array[Control] = []  # plan indicator panels, freed each round
var _reveal_tooltip: Control = null        # enlarged card shown while hovering a reveal
var _intent_displays: Array[Control] = []  # enemy intent chips shown during PLAN phase
var _intent_popup: Control = null           # hover tooltip for an intent chip
var _all_cards: Array[CardData] = []  # full collection for the bag view
var _card_viewer: CardViewer
# Hand cards discarding on lock-in; freed at the start of _cleanup().
var _discarding_hand_cards: Array[GameCard] = []

# Move placeholder + picker
var _ai: EnemyAI
var _enemy_attack_card: CardData
var _enemy_recover_card: CardData

var _move_placeholder: GameCard
var _move_placeholder_home := Vector2(1490.0, 845.0)
var _move_picker: MovePicker
var _move_picker_target_slot: int = -1


func _ready() -> void:
	_place_tokens()
	if Engine.is_editor_hint():
		return  # everything below is runtime-only gameplay wiring

	add_to_group("battlefield")
	_player = get_node_or_null("Board/PlayerToken") as Token
	_enemy = get_node_or_null("Board/EnemyToken") as Token
	_hand = get_node_or_null("UI/Hand") as Hand

	var player_hud := get_node_or_null("UI/PlayerHUD")
	var enemy_hud := get_node_or_null("UI/EnemyHUD")
	if player_hud != null and _player != null:
		player_hud.bind(_player)
		player_hud.add_to_group("player_energy_hud")  # cards preview energy here
	if enemy_hud != null and _enemy != null:
		enemy_hud.bind(_enemy)

	if _player != null:
		_player.hit.connect(func(amount: int): _spawn_damage_number(_player, amount))
		_player.blocked.connect(func(amount: int): _spawn_float_text(
				_player, "Blocked %d" % amount, Color(0.55, 0.78, 1.0), 24))
	if _enemy != null:
		_enemy.hit.connect(func(amount: int): _spawn_damage_number(_enemy, amount))
		_enemy.blocked.connect(func(amount: int): _spawn_float_text(
				_enemy, "Blocked %d" % amount, Color(0.55, 0.78, 1.0), 24))

	_slot_nodes.clear()
	for i in range(MAX_SLOTS):
		var s := get_node_or_null("UI/PlanBar/Slot%d" % i)
		if s != null:
			s.index = i
			s.dropped.connect(_on_slot_dropped)
			s.cleared.connect(_clear_from)
			_slot_nodes.append(s)

	_lock_in = get_node_or_null("UI/LockInButton") as Button
	if _lock_in != null:
		_lock_in.pressed.connect(_on_lock_in)
		_style_lock_in_button()

	_hide_btn = get_node_or_null("UI/HideButton") as Button
	if _hide_btn != null:
		_hide_btn.pressed.connect(_on_toggle_hide)
		_style_hide_button()
		_layout_plan_group.call_deferred()

	# Same ink backdrop as the map scene.
	var bg := get_node_or_null("Background") as ColorRect
	if bg != null:
		bg.material = HudKit.ink_material()

	# Top HUD row, mirroring the map: coins/floor left, Round center (scene),
	# Stats/Inventory/Cards right.
	var ui_layer := get_node_or_null("UI") as CanvasLayer
	if ui_layer != null:
		var coins_panel := HudKit.coins_floor_panel()
		coins_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
		coins_panel.position = Vector2(16, 14)
		ui_layer.add_child(coins_panel)

		var btns := HBoxContainer.new()
		btns.add_theme_constant_override("separation", 8)
		btns.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		btns.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		btns.offset_top = 14.0
		btns.offset_right = -16.0
		ui_layer.add_child(btns)

		var stats_btn := HudKit.button("Stats", "stats", Color(0.55, 0.85, 0.75))
		stats_btn.pressed.connect(func(): HudKit.show_stats(self))
		btns.add_child(stats_btn)

		var inv_btn := HudKit.button("Inventory", "inventory", Color(0.76, 0.55, 0.35))
		inv_btn.pressed.connect(func(): InventoryOverlay.open(self, true))  # read-only in battle
		btns.add_child(inv_btn)

		var cards_btn := HudKit.button("Cards", "deck", Color(0.87, 0.52, 0.45))
		cards_btn.pressed.connect(_on_bag_pressed)
		btns.add_child(cards_btn)

	_card_viewer = get_node_or_null("UI/CardViewer") as CardViewer

	var discard_panel := get_node_or_null("UI/DiscardPile")
	if discard_panel != null:
		discard_panel.gui_input.connect(_on_discard_panel_input)

	var deck_panel := get_node_or_null("UI/DeckPile")
	if deck_panel != null:
		deck_panel.gui_input.connect(_on_deck_panel_input)

	_move_keys = {
		KEY_UP: CardData.by_id(&"move_up"),
		KEY_DOWN: CardData.by_id(&"move_down"),
		KEY_LEFT: CardData.by_id(&"move_left"),
		KEY_RIGHT: CardData.by_id(&"move_right"),
	}
	_moves_by_dir.clear()
	for mc in _move_keys.values():
		_moves_by_dir[mc.move_direction] = mc

	var starter: Array[CardData] = []
	if GameState.has_deck():
		starter = GameState.deck.duplicate()
	else:
		starter.assign(CardData.starter_deck())
		GameState.deck = starter.duplicate()
	for cd in starter:
		_all_cards.append(cd)
	for id in MovePool.MOVE_IDS:
		_all_cards.append(CardData.by_id(id))
	_deck = Deck.new(starter)
	_draw_to_hand_size()
	_update_pile_info()
	_apply_enemy_data()
	_apply_equipment()
	_setup_move_placeholder()
	_begin_plan()


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		_place_tokens()


func _place_tokens() -> void:
	var board := get_node_or_null("Board") as Board
	if board == null:
		return
	for child in board.get_children():
		if child is Token:
			child.board = board
			child.position = board.get_cell_position(child.start_cell.x, child.start_cell.y)


# ── PLAN phase ────────────────────────────────────────────────────────────────
func _begin_plan() -> void:
	# Last round's reveal stays up through this plan phase as a guide to the
	# enemy's patterns; it's replaced when the next reveal is shown.
	_phase = Phase.PLAN
	_plan = [null, null, null]
	_enemy_plan = []
	_round += 1
	var round_label := get_node_or_null("UI/BattleHUD/RoundLabel") as Label
	if round_label != null:
		round_label.text = "Round %d" % _round
	for s in _slot_nodes:
		s.show_placeholder(true)
	_set_planning_ui_visible(true)
	_refresh_lock_in()
	_update_facing()
	_update_sharing()
	# Enemy commits its plan at the start of PLAN so the player can react to it.
	_enemy_plan = _enemy_decide()
	_show_enemy_intent()
	# Refresh block: expire last round's block then re-grant from all equipped items.
	if _player != null:
		_player.block = 0
		for item in GameState.equipment.values():
			var ed := item as EquipmentData
			if ed != null:
				_player.block += ed.block_per_turn
		_player.block_changed.emit(_player.block)


## Show/hide all the card-planning UI. Hidden during the fight so the player can
## just watch the board; shown again in the plan phase.
func _set_planning_ui_visible(on: bool) -> void:
	for path in ["UI/Hand", "UI/PlanBar", "UI/LockInButton", "UI/HideButton", "UI/PlanFrame"]:
		var n := get_node_or_null(path) as CanvasItem
		if n != null:
			n.visible = on
	if _move_placeholder != null:
		_move_placeholder.visible = on
	if on:
		_layout_plan_group.call_deferred()


## A card was dropped onto slot `index`.
func _on_slot_dropped(index: int, payload: Dictionary) -> void:
	if _phase != Phase.PLAN or index < 0 or index >= MAX_SLOTS:
		return
	if _plan[index] != null:
		return  # slot already filled
	var data: CardData = payload.get("data")
	if data == null:
		return
	# Move placeholder: open the picker instead of placing the card.
	if data.id == &"move_chooser":
		_move_picker_target_slot = index
		_move_picker.show()
		return
	var consumable: bool = payload.get("consumable", false)
	if data.type != CardData.CardType.MOVE:
		if _projected_energy() - data.cost + data.energy_gain < 0:
			_show_toast("Not enough energy!")
			return  # can't afford

	# Get the card node: the real hand card (consumable) or a fresh duplicate (move).
	var card: GameCard
	if consumable:
		card = payload.get("card")
		if card == null:
			return
		# Guard: ignore a stray second drop of a card that's already in a slot.
		for entry in _plan:
			if entry != null and entry.get("card") == card:
				return
		_hand.take_card(card)
	else:
		card = CARD_SCENE.instantiate()
		card.consumable = false
		card.data = data

	var slot = _slot_nodes[index]
	_mount_card_in_slot(card, slot)
	slot.show_placeholder(false)
	_plan[index] = {"data": data, "consumable": consumable, "card": card}
	_refresh_lock_in()


## Build the Move placeholder card and the picker popup, add both to UI.
func _setup_move_placeholder() -> void:
	var ui := get_node_or_null("UI")
	if ui == null:
		return

	var placeholder_data := CardData.new()
	placeholder_data.id          = &"move_chooser"
	placeholder_data.card_name   = "Move"
	placeholder_data.type        = CardData.CardType.MOVE
	placeholder_data.cost        = 0
	placeholder_data.description = "Choose\na direction"

	_move_placeholder = CARD_SCENE.instantiate()
	_move_placeholder.consumable = false
	_move_placeholder.data       = placeholder_data
	_move_placeholder.card_size  = CARD_SIZE
	_move_placeholder.drag_ended.connect(_on_placeholder_drag_ended)
	ui.add_child(_move_placeholder)
	_move_placeholder.position = _move_placeholder_home
	# Sit behind the discard/deck/hand section (but in front of the plan panel
	# and enemy intent) by placing it just before the DiscardPile in the tree.
	var discard := ui.get_node_or_null("DiscardPile")
	if discard != null:
		ui.move_child(_move_placeholder, discard.get_index())

	_move_picker = MovePicker.new()
	ui.add_child(_move_picker)
	_move_picker.move_chosen.connect(_on_move_picker_chosen)


func _on_placeholder_drag_ended(_card: GameCard) -> void:
	_move_placeholder.position  = _move_placeholder_home
	_move_placeholder.rotation  = 0.0
	_move_placeholder.scale     = Vector2.ONE


## Called when the player picks a direction in the MovePicker popup.
func _on_move_picker_chosen(cd: CardData) -> void:
	var index := _move_picker_target_slot
	_move_picker_target_slot = -1
	if _phase != Phase.PLAN or index < 0 or index >= MAX_SLOTS:
		return
	if _plan[index] != null:
		return
	var card: GameCard = CARD_SCENE.instantiate()
	card.consumable   = false
	card.data         = cd
	var slot          = _slot_nodes[index]
	_mount_card_in_slot(card, slot)
	slot.show_placeholder(false)
	_plan[index] = {"data": cd, "consumable": false, "card": card}
	_refresh_lock_in()


## Put a full-size card into a plan slot, scaled to fit via a wrapper Control.
## We scale the wrapper (not the card) because GameCard rewrites its own `scale`
## every frame, and resizing `card_size` would distort the card's fixed-offset
## children — a uniform wrapper scale keeps the card pixel-perfect, just smaller.
func _mount_card_in_slot(card: GameCard, slot: Control) -> void:
	var slot_size: Vector2 = slot.size if slot.size.x > 1.0 else slot.custom_minimum_size
	var holder := Control.new()
	holder.name = "CardHolder"
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.scale = slot_size / CARD_SIZE
	slot.add_child(holder)
	if card.get_parent() != null:
		card.get_parent().remove_child(card)   # detach from hand/old slot first
	holder.add_child(card)
	card.card_size    = CARD_SIZE
	card.set_anchors_preset(Control.PRESET_TOP_LEFT, false)
	card.position     = Vector2.ZERO
	card.rotation     = 0.0
	card.scale        = Vector2.ONE
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE  # let clicks reach the slot (to clear)


## Clear slot `index` AND every slot after it. Consumable cards return to the hand.
func _clear_from(index: int) -> void:
	if _phase != Phase.PLAN:
		return
	for j in range(MAX_SLOTS - 1, index - 1, -1):
		var entry = _plan[j]
		if entry == null:
			continue
		var card: GameCard = entry.card
		var slot = _slot_nodes[j]
		var holder: Node = card.get_parent() if is_instance_valid(card) else null
		if entry.consumable and is_instance_valid(card):
			card.mouse_filter = Control.MOUSE_FILTER_STOP
			card.card_size = CARD_SIZE
			card.scale = Vector2.ONE
			if is_instance_valid(holder):
				holder.remove_child(card)         # detach before the hand re-adopts it
			_hand.return_card(card)               # puts the card back into the hand
			if is_instance_valid(holder):
				holder.queue_free()               # discard the now-empty wrapper
		elif is_instance_valid(holder):
			holder.queue_free()                   # frees the card child with it
		elif is_instance_valid(card):
			card.queue_free()
		slot.show_placeholder(true)
		_plan[j] = null
	_refresh_lock_in()


## Energy the player would have left after their currently-planned combat cards.
func _projected_energy() -> int:
	var e := _player.energy
	for entry in _plan:
		if entry != null:
			var d: CardData = entry.data
			if d.type != CardData.CardType.MOVE:
				e = e - d.cost + d.energy_gain
	return e


## Give the plain lock-in button an on-tone green look with a grayed-out
## disabled state (Godot swaps in the matching stylebox automatically).
func _style_lock_in_button() -> void:
	if _lock_in == null:
		return
	_lock_in.text = "Lock In"
	_lock_in.focus_mode = Control.FOCUS_NONE
	_lock_in.add_theme_font_size_override("font_size", 20)
	_lock_in.add_theme_color_override("font_color", Color(0.85, 1.0, 0.90))
	_lock_in.add_theme_color_override("font_hover_color", Color.WHITE)
	_lock_in.add_theme_color_override("font_disabled_color", Color(0.52, 0.56, 0.60))
	var palette := {
		"normal":   [Color(0.10, 0.28, 0.15, 0.95), Color(0.35, 0.85, 0.45, 0.90)],
		"hover":    [Color(0.14, 0.38, 0.20, 0.98), Color(0.55, 1.00, 0.60, 1.00)],
		"pressed":  [Color(0.08, 0.22, 0.12, 0.98), Color(0.35, 0.85, 0.45, 0.90)],
		"disabled": [Color(0.12, 0.13, 0.15, 0.85), Color(0.30, 0.33, 0.38, 0.70)],
	}
	for state in palette:
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(10)
		sb.set_content_margin_all(8.0)
		sb.bg_color     = palette[state][0]
		sb.border_color = palette[state][1]
		sb.set_border_width_all(2)
		_lock_in.add_theme_stylebox_override(state, sb)


func _refresh_lock_in() -> void:
	var n := 0
	for entry in _plan:
		if entry != null:
			n += 1
	if _lock_in != null:
		_lock_in.disabled = n != MAX_SLOTS
	_update_slot_states()


## Only the first empty slot accepts drops (no gaps). Empty slots after it are
## disabled + dimmed, so you must fill the slots left-to-right.
func _update_slot_states() -> void:
	var next_free := _next_free_slot()
	for i in range(_slot_nodes.size()):
		var slot = _slot_nodes[i]
		var filled: bool = _plan[i] != null
		var is_next: bool = (i == next_free)
		slot.set_droppable(is_next)


const _ICON_PAUSE  := preload("res://assets/ui/icon_pause.png")
const _ICON_RESUME := preload("res://assets/ui/icon_resume.png")

## Give the plain hide button a dark, on-tone look (normal + hover states).
func _style_hide_button() -> void:
	if _hide_btn == null:
		return
	_hide_btn.text = "Hide Plan"
	_hide_btn.focus_mode = Control.FOCUS_NONE
	_hide_btn.add_theme_font_size_override("font_size", 15)
	_hide_btn.add_theme_color_override("font_color", Color(0.82, 0.86, 0.94))
	_hide_btn.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0))
	for state in ["normal", "hover", "pressed"]:
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(8)
		sb.set_content_margin_all(6.0)
		sb.bg_color     = Color(0.10, 0.12, 0.16, 0.90)
		sb.border_color = Color(0.45, 0.52, 0.65, 0.80)
		sb.set_border_width_all(1)
		if state == "hover":
			sb.bg_color     = Color(0.16, 0.19, 0.25, 0.95)
			sb.border_color = Color(0.70, 0.80, 1.0, 0.90)
		elif state == "pressed":
			sb.bg_color = Color(0.07, 0.08, 0.11, 0.95)
		_hide_btn.add_theme_stylebox_override(state, sb)


const _HIDE_GAP := 10.0    # gap between Hide button and the slot row
const _LOCK_GAP := 16.0    # gap between the slot row and Lock In button
const _FRAME_PAD := 18.0   # padding of the background frame around the group

## Lay out the plan group as one tidy unit: Hide Plan centered above the slot
## row, Lock In centered below it, and a translucent frame around the whole
## thing. Positions are derived from the plan bar's rect so they stay aligned.
func _layout_plan_group() -> void:
	var plan_bar := get_node_or_null("UI/PlanBar") as Control
	if plan_bar == null:
		return
	# Centre the panel horizontally in the gap between the board's right edge and
	# the screen edge, so it has equal margins on both sides.
	var bar_w := plan_bar.size.x if plan_bar.size.x > 1.0 else 422.0
	var board := get_node_or_null("Board") as Board
	if board != null:
		var board_right := board.global_position.x + board.columns * board.cell_size * 0.5
		var screen_right := get_viewport_rect().size.x
		plan_bar.position.x = (board_right + screen_right) * 0.5 - bar_w * 0.5
	var row := plan_bar.get_global_rect()
	var cx := row.position.x + row.size.x * 0.5

	if _hide_btn != null:
		var hs := _hide_btn.size
		if hs.x < 1.0:
			hs = _hide_btn.custom_minimum_size
		_hide_btn.global_position = Vector2(cx - hs.x * 0.5, row.position.y - _HIDE_GAP - hs.y)

	if _lock_in != null:
		var ls := _lock_in.size
		if ls.x < 1.0:
			ls = _lock_in.custom_minimum_size
		_lock_in.global_position = Vector2(cx - ls.x * 0.5, row.end.y + _LOCK_GAP)

	_layout_plan_frame(row)


## Build/position the translucent frame that visually contains the plan group.
func _layout_plan_frame(row: Rect2) -> void:
	var ui := get_node_or_null("UI")
	if ui == null:
		return
	var frame := ui.get_node_or_null("PlanFrame") as Panel
	if frame == null:
		frame = Panel.new()
		frame.name = "PlanFrame"
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.05, 0.06, 0.09, 0.55)
		sb.border_color = Color(0.32, 0.37, 0.47, 0.55)
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(14)
		frame.add_theme_stylebox_override("panel", sb)
		ui.add_child(frame)
		ui.move_child(frame, 0)   # draw behind the slots and buttons
	var hide_h := _hide_btn.custom_minimum_size.y if _hide_btn != null else 0.0
	var lock_h := _lock_in.custom_minimum_size.y if _lock_in != null else 0.0
	var top := row.position.y - _HIDE_GAP - hide_h - _FRAME_PAD
	var bottom := row.end.y + _LOCK_GAP + lock_h + _FRAME_PAD
	frame.global_position = Vector2(row.position.x - _FRAME_PAD, top)
	frame.size = Vector2(row.size.x + _FRAME_PAD * 2.0, bottom - top)


func _on_toggle_hide() -> void:
	var plan_bar := get_node_or_null("UI/PlanBar") as CanvasItem
	var show := not (plan_bar != null and plan_bar.visible)
	if plan_bar != null:
		plan_bar.visible = show
	var frame := get_node_or_null("UI/PlanFrame") as CanvasItem
	if frame != null:
		frame.visible = show
	if _lock_in != null:
		_lock_in.visible = show
	if _hide_btn != null:
		_hide_btn.text = "Hide Plan" if show else "Show Plan"
	# While the plan is hidden the slots are gone, so a card can't be dropped into
	# a plan — but keep the hand draggable so the player can still lift cards to
	# read them. Only the Lock In button is frozen.
	_set_hand_interactable(true)
	if show:
		_refresh_lock_in()      # restore Lock In's enabled/disabled state
	elif _lock_in != null:
		_lock_in.disabled = true


## Enable/disable dragging cards out of the hand (and the move card) — used to
## freeze planning input while the plan is hidden.
func _set_hand_interactable(on: bool) -> void:
	if _hand != null:
		for c in _hand.get_children():
			if c is GameCard:
				c.undraggable = not on
	if _move_placeholder != null:
		_move_placeholder.undraggable = not on


## Pause / resume. The PauseButton + overlay run with PROCESS_MODE_ALWAYS so they
## still work while the tree is paused.
func _on_pause_toggle() -> void:
	var paused := not get_tree().paused
	get_tree().paused = paused
	var overlay := get_node_or_null("UI/PauseOverlay") as CanvasItem
	if overlay != null:
		overlay.visible = paused
	var btn := get_node_or_null("UI/BattleHUD/PauseButton") as Button
	if btn != null:
		btn.icon = _ICON_RESUME if paused else _ICON_PAUSE


func _on_bag_pressed() -> void:
	if _card_viewer != null:
		_card_viewer.show_cards("Bag — All Cards", _all_cards)

func _on_discard_panel_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _card_viewer != null:
			_card_viewer.show_cards("Discard Pile", _deck.discard_pile)


func _on_deck_panel_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _card_viewer != null:
			_card_viewer.show_cards("Draw Pile", _deck.draw_pile)


## Pop a short message in the center for ~2.5s. Overlapping calls reset the timer.
func _show_toast(msg: String) -> void:
	var toast := get_node_or_null("UI/Toast") as Label
	if toast == null:
		return
	toast.text = msg
	toast.visible = true
	_toast_token += 1
	var my_token := _toast_token
	await get_tree().create_timer(2.5).timeout
	if my_token == _toast_token and is_instance_valid(toast):
		toast.visible = false


# ── Enemy data ────────────────────────────────────────────────────────────────

func _apply_enemy_data() -> void:
	var node_type := MapNode.Type.FIGHT
	if GameState.current_node_id >= 0 and GameState.has_map():
		node_type = GameState.map_nodes[GameState.current_node_id].type
	# Map nodes (mystery fight, ambush, dojo, bounty…) can force an enemy tier.
	if GameState.battle_tier_override != -1:
		node_type = GameState.battle_tier_override as MapNode.Type

	var ed := EnemyData.by_node_type(node_type)
	if ed == null:
		ed = EnemyData.new()   # safe fallback with defaults

	_ai                 = EnemyData.create_ai(ed.ai_type)
	_enemy_attack_card  = CardData.by_id(ed.attack_id)
	_enemy_recover_card = CardData.by_id(ed.recover_id)

	if _enemy != null:
		_enemy.display_name  = ed.enemy_name
		_enemy.max_hp        = ed.max_hp
		_enemy.hp            = ed.max_hp
		_enemy.max_energy    = ed.max_energy
		_enemy.energy        = ed.start_energy
		_enemy.energy_regen  = ed.energy_regen


# ── Enemy AI ──────────────────────────────────────────────────────────────────

func _enemy_decide() -> Array:
	return _ai.decide(_enemy, _player, _moves_by_dir,
			_enemy_attack_card, _enemy_recover_card)


# ── Enemy intent display ──────────────────────────────────────────────────────

func _show_enemy_intent() -> void:
	if _enemy == null or not is_instance_valid(_enemy):
		return
	_clear_enemy_intent()

	# A compact row of symbol chips floating just above the enemy token's head.
	# Held in a UI container parked at the enemy's screen position, sitting in
	# the tree just above the PlanBar but below the piles/hand/viewer — so the
	# intent draws over the plan panel yet never over the hand or card lists.
	# Chips read left→right in the same order the actions resolve.
	const CHIP := Vector2(48.0, 44.0)
	const GAP := 6.0
	var n := _enemy_plan.size()
	if n == 0:
		return
	var root := _intent_root()
	if root == null:
		return
	root.position = _enemy.global_position
	var total := n * CHIP.x + (n - 1) * GAP
	var start_x := -total * 0.5
	var top_y := -(_enemy.box_size * 0.5) - CHIP.y - 16.0

	for i in n:
		var cd: CardData = _enemy_plan[i]
		var chip := Panel.new()
		chip.size = CHIP
		chip.position = Vector2(start_x + i * (CHIP.x + GAP), top_y)
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE

		var style := StyleBoxFlat.new()
		style.set_corner_radius_all(8)
		style.set_border_width_all(2)
		style.shadow_color = Color(0, 0, 0, 0.5)
		style.shadow_size = 3

		# Big symbol glyph, centered.
		var glyph := Label.new()
		glyph.set_anchors_preset(Control.PRESET_FULL_RECT)
		glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		glyph.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
		glyph.add_theme_font_size_override("font_size", 28)
		glyph.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		glyph.add_theme_constant_override("outline_size", 5)
		glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE

		# Small value tag in the bottom-right (damage / energy amount).
		var tag := Label.new()
		tag.set_anchors_preset(Control.PRESET_FULL_RECT)
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		tag.vertical_alignment   = VERTICAL_ALIGNMENT_BOTTOM
		tag.add_theme_font_size_override("font_size", 13)
		tag.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
		tag.add_theme_constant_override("outline_size", 4)
		tag.mouse_filter = Control.MOUSE_FILTER_IGNORE

		var desc := ""
		if cd == null:
			style.bg_color     = Color(0.10, 0.10, 0.10, 0.9)
			style.border_color = Color(0.30, 0.30, 0.30)
			glyph.text = "—"
			glyph.modulate = Color(0.6, 0.6, 0.6)
			desc = "The enemy has no planned action here."
		elif cd.type == CardData.CardType.MOVE:
			style.bg_color     = Color(0.05, 0.16, 0.07, 0.92)
			style.border_color = Color(0.28, 0.72, 0.38)
			var dir := cd.move_direction
			glyph.text = "→" if dir.x > 0 else "←" if dir.x < 0 else "↓" if dir.y > 0 else "↑"
			glyph.modulate = Color(0.6, 1.0, 0.7)
			var word := "right" if dir.x > 0 else "left" if dir.x < 0 else "down" if dir.y > 0 else "up"
			desc = "The enemy is about to move %s." % word
		elif cd.type == CardData.CardType.ATTACK:
			style.bg_color     = Color(0.24, 0.04, 0.04, 0.94)
			style.border_color = Color(0.95, 0.25, 0.22)
			glyph.text = "!"
			glyph.add_theme_font_size_override("font_size", 34)
			glyph.modulate = Color(1.0, 0.35, 0.32)
			tag.text = str(cd.damage)
			tag.modulate = Color(1.0, 0.85, 0.6)
			desc = "The enemy is about to attack for %d damage!" % cd.damage
		else:
			style.bg_color     = Color(0.05, 0.09, 0.24, 0.92)
			style.border_color = Color(0.30, 0.58, 0.95)
			glyph.text = "✦"
			glyph.modulate = Color(0.6, 0.8, 1.0)
			tag.text = "+%d" % cd.energy_gain
			tag.modulate = Color(0.7, 0.88, 1.0)
			desc = "The enemy is about to recover +%d energy." % cd.energy_gain

		chip.add_theme_stylebox_override("panel", style)
		chip.add_child(glyph)
		chip.add_child(tag)
		root.add_child(chip)
		_intent_displays.append(chip)

		# Hover → simple popup describing the intent.
		chip.mouse_filter = Control.MOUSE_FILTER_STOP
		var cx := chip.position.x + CHIP.x * 0.5
		var cdesc := desc
		var cclr := Color(style.border_color)
		chip.mouse_entered.connect(func() -> void: _show_intent_popup(cx, top_y, cdesc, cclr))
		chip.mouse_exited.connect(_hide_intent_popup)


## Container in the UI layer that holds the enemy-intent chips and popup.
## Enforces the draw order (back→front): PlanBar, Hide, Lock-In, intent — so the
## intent covers the plan panel, while the piles/hand/card-viewer (later in the
## tree) draw in front of the whole plan group and the intent.
func _intent_root() -> Control:
	var ui := get_node_or_null("UI")
	if ui == null:
		return null
	var root := ui.get_node_or_null("EnemyIntent") as Control
	if root == null:
		root = Control.new()
		root.name = "EnemyIntent"
		root.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ui.add_child(root)
	var plan_bar := ui.get_node_or_null("PlanBar")
	if plan_bar != null:
		# Move in reverse so they end up as PlanBar, Hide, Lock-In, intent.
		_move_after(ui, root, plan_bar)
		if _lock_in != null and _lock_in.get_parent() == ui:
			_move_after(ui, _lock_in, plan_bar)
		if _hide_btn != null and _hide_btn.get_parent() == ui:
			_move_after(ui, _hide_btn, plan_bar)
	return root


func _move_after(parent: Node, child: Node, anchor: Node) -> void:
	parent.move_child(child, mini(anchor.get_index() + 1, parent.get_child_count() - 1))


func _clear_enemy_intent() -> void:
	_hide_intent_popup()
	for c in _intent_displays:
		if is_instance_valid(c):
			c.queue_free()
	_intent_displays.clear()


## Small floating tooltip above the intent row, centered on `center_x`
## (in the enemy token's local space, matching the chip positions).
func _show_intent_popup(center_x: float, row_top: float, text: String, accent: Color) -> void:
	_hide_intent_popup()
	if not is_instance_valid(_enemy):
		return
	var w := 250.0
	var h := 54.0
	var pop := Panel.new()
	pop.size = Vector2(w, h)
	pop.position = Vector2(center_x - w * 0.5, row_top - h - 10.0)
	pop.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.06, 0.07, 0.10, 0.97)
	st.border_color = accent
	st.set_border_width_all(2)
	st.set_corner_radius_all(7)
	st.shadow_color = Color(0, 0, 0, 0.6)
	st.shadow_size = 5
	st.content_margin_left = 10.0
	st.content_margin_right = 10.0
	pop.add_theme_stylebox_override("panel", st)

	var lbl := Label.new()
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 15)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	lbl.add_theme_constant_override("outline_size", 3)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.text = text
	pop.add_child(lbl)

	var root := _intent_root()
	if root != null:
		root.add_child(pop)
	_intent_popup = pop


func _hide_intent_popup() -> void:
	if is_instance_valid(_intent_popup):
		_intent_popup.queue_free()
	_intent_popup = null


# ── RESOLVE phase ─────────────────────────────────────────────────────────────
func _on_lock_in() -> void:
	if _phase != Phase.PLAN:
		return
	_resolve()


func _resolve() -> void:
	_phase = Phase.RESOLVE
	if _lock_in != null:
		_lock_in.disabled = true

	# Fly unplayed hand cards to discard right at lock-in, before the UI hides.
	# Cards are reparented to the CanvasLayer so they stay visible after Hand is hidden.
	var ui := get_node_or_null("UI")
	var discard_panel := get_node_or_null("UI/DiscardPile") as Control
	if _hand != null and ui != null and discard_panel != null:
		var discard_target := discard_panel.global_position
		for card in _hand.detach_all_cards():
			_deck.discard(card.data)
			card.reparent(ui, true)
			card.tween_position(discard_target, 0.3, true)
			card.tween_scale(Vector2(0.1, 0.1), 0.3)
			_discarding_hand_cards.append(card)
		_update_pile_info()
		# Free them right after the animation — don't let them pile up during the fight.
		var to_free := _discarding_hand_cards.duplicate()
		_discarding_hand_cards.clear()
		get_tree().create_timer(0.4).timeout.connect(func():
			for c in to_free:
				if is_instance_valid(c):
					c.queue_free()
		)

	_set_planning_ui_visible(false)  # hide the card UI — watch the fight
	_clear_enemy_intent()
	_show_plan_displays()

	for slot in range(MAX_SLOTS):
		await _reveal_slot_indicators(slot)

		var actions: Array = []
		if _plan[slot] != null:
			actions.append({"actor": _player, "data": _plan[slot].data})
		if slot < _enemy_plan.size() and _enemy_plan[slot] != null:
			actions.append({"actor": _enemy, "data": _enemy_plan[slot]})

		for a in actions:
			if a.data.type == CardData.CardType.MOVE:
				_do_action(a.data, a.actor)
		await get_tree().create_timer(0.35).timeout
		_update_sharing()   # nudge side-by-side if now on same cell
		_update_facing()    # flip triangles if positions crossed

		for a in actions:
			if a.data.type != CardData.CardType.MOVE:
				_do_action(a.data, a.actor)
		await get_tree().create_timer(0.40).timeout

		if _player.is_dead() or _enemy.is_dead():
			break

	# Un-dim the reveal cards so the persisting guide stays clearly readable
	# (leave the row labels' own colours intact).
	for c in _resolve_display:
		if is_instance_valid(c) and c is PlanCard:
			c.modulate = Color.WHITE

	_cleanup()


func _cleanup() -> void:
	# PlanBar was hidden during resolve; reveal it so slot cards can animate.
	var plan_bar := get_node_or_null("UI/PlanBar") as CanvasItem
	if plan_bar != null:
		plan_bar.visible = true

	var ui := get_node_or_null("UI")
	var discard_panel := get_node_or_null("UI/DiscardPile") as Control
	var discard_target := Vector2.INF
	if discard_panel != null:
		discard_target = discard_panel.global_position  # top-left of the pile panel

	var flying: Array[GameCard] = []

	for j in range(MAX_SLOTS):
		var entry = _plan[j]
		if entry == null:
			continue
		var card: GameCard = entry.card
		var holder: Node = card.get_parent() if is_instance_valid(card) else null
		if entry.consumable and is_instance_valid(card) and discard_target != Vector2.INF and ui != null:
			_deck.discard(entry.data)
			card.reparent(ui, true)   # out of the wrapper into global space, keep size
			if is_instance_valid(holder):
				holder.queue_free()
			card.tween_position(discard_target, 0.35, true)
			card.tween_scale(Vector2(0.1, 0.1), 0.35)
			flying.append(card)
		else:
			if entry.consumable:
				_deck.discard(entry.data)
			if is_instance_valid(holder):
				holder.queue_free()   # frees the card child with it
			elif is_instance_valid(card):
				card.queue_free()
		_slot_nodes[j].show_placeholder(true)
		_plan[j] = null

	if flying.size() > 0:
		await get_tree().create_timer(0.4).timeout
		for card in flying:
			if is_instance_valid(card):
				card.queue_free()

	if _player != null:
		_player.regen_energy()
	if _enemy != null:
		_enemy.regen_energy()
	_draw_to_hand_size()
	_update_pile_info()

	if _player.is_dead() or _enemy.is_dead():
		_game_over()
	else:
		_begin_plan()


func _game_over() -> void:
	_clear_enemy_intent()
	_clear_plan_displays()
	_phase = Phase.RESOLVE
	if _lock_in != null:
		_lock_in.disabled = true
	if _enemy.is_dead() and not _player.is_dead():
		_show_win_reward()
	else:
		var banner := get_node_or_null("UI/Banner") as Label
		if banner != null:
			banner.text = "You lose!" if _player.is_dead() else "Draw!"
			banner.visible = true
		var ui := get_node_or_null("UI") as CanvasLayer
		if ui != null:
			var btn := Button.new()
			btn.text = "Return to Map"
			btn.position = Vector2(860.0, 596.0)
			btn.size = Vector2(200.0, 44.0)
			btn.pressed.connect(func(): get_tree().change_scene_to_file(MAP_SCENE))
			ui.add_child(btn)


# ── Card effects (shared by resolution) ───────────────────────────────────────
func _do_action(data: CardData, actor: Token) -> bool:
	if data == null or actor == null:
		return false
	match data.type:
		CardData.CardType.MOVE:
			actor.play_card(data)
			actor.move_to_cell(actor.current_cell + data.move_direction)
			return true
		CardData.CardType.ATTACK:
			if not actor.spend_energy(data.cost):
				return false
			actor.play_card(data)
			var facing := actor.get_facing()
			var dmg := data.damage
			if actor == _player:
				dmg += _player_damage_bonus
				if _player_crit_chance > 0 and (randi() % 100) < _player_crit_chance:
					dmg *= 2
			# Use affected_cells for targeting; fall back to 1 cell ahead if empty.
			var offsets: Array = data.affected_cells if not data.affected_cells.is_empty() \
				else [Vector2i(1, 0)]
			var already_hit: Array[Token] = []
			for offset in offsets:
				var actual := Vector2i(offset.x * facing.x, offset.y)
				var target := _token_at(actor.current_cell + actual, actor)
				if target != null and target not in already_hit:
					target.take_damage(dmg)
					already_hit.append(target)
			# Apply facing-relative step if the card has one (e.g. back_shot).
			if data.step_direction != Vector2i.ZERO:
				var step := Vector2i(data.step_direction.x * facing.x, data.step_direction.y)
				actor.move_to_cell(actor.current_cell + step)
			return true
		CardData.CardType.SKILL:
			if not actor.spend_energy(data.cost):
				return false
			actor.play_card(data)
			if data.energy_gain > 0:
				actor.gain_energy(data.energy_gain)
			return true
		_:
			return false


# ── Helpers ───────────────────────────────────────────────────────────────────
func _next_free_slot() -> int:
	for i in range(MAX_SLOTS):
		if _plan[i] == null:
			return i
	return -1


func _draw_to_hand_size() -> void:
	if _hand == null or _deck == null:
		return
	var deck_panel := get_node_or_null("UI/DeckPile") as Control
	var from_pos := Vector2.INF
	if deck_panel != null:
		from_pos = deck_panel.global_position + deck_panel.size * 0.5 - CARD_SIZE * 0.5
	while _hand.card_count() < HAND_SIZE:
		var card_data := _deck.draw_one()
		if card_data == null:
			break
		_hand.add_card(card_data, from_pos)
		_update_pile_info()
		await get_tree().create_timer(0.1).timeout


func _token_at(cell: Vector2i, exclude: Token) -> Token:
	var board := get_node_or_null("Board") as Board
	if board == null:
		return null
	for child in board.get_children():
		if child is Token and child != exclude and child.current_cell == cell:
			return child
	return null


func _update_pile_info() -> void:
	if _deck == null:
		return
	var deck_label := get_node_or_null("UI/DeckPile/Label") as Label
	if deck_label != null:
		deck_label.text = "%d" % _deck.draw_count()
	var discard_label := get_node_or_null("UI/DiscardPile/Label") as Label
	if discard_label != null:
		discard_label.text = "%d" % _deck.discard_count()


# ── Plan display — card-back reveal during RESOLVE ────────────────────────────

const PLAN_CARD_SCENE := preload("res://scenes/battle/plan_card.tscn")
const _CARD_W   := 130.0   # matches the plan slot size
const _CARD_H   := 195.0
const _CARD_GAP := 145.0   # center-to-center spacing between slots

## Parent for the reveal cards, in the world's default canvas — above the board
## but BELOW the UI CanvasLayer and every popup (deck/discard, inventory, stats,
## card viewer), so those always cover the reveal.
func _reveal_root() -> Control:
	var r := get_node_or_null("RevealRoot") as Control
	if r == null:
		r = Control.new()
		r.name = "RevealRoot"
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(r)
	return r


func _show_plan_displays() -> void:
	_clear_plan_displays()   # drop the previous round's reveal before showing this one
	var root := _reveal_root()
	# Both rows sit at the left-center of the battlefield, player above enemy.
	const LEFT_X := 30.0
	var player_y := 258.0
	var enemy_y := player_y + _CARD_H + 62.0
	# Framed box behind the two rows (added first so it draws behind the cards).
	var deco := _build_reveal_box(root, LEFT_X, player_y, enemy_y)
	# Player row (revealed slots 0..2)
	for i in MAX_SLOTS:
		var cd: CardData = _plan[i].data if _plan[i] != null else null
		_resolve_display.append(_add_reveal_card(root, cd, _player,
				Vector2(LEFT_X + i * _CARD_GAP, player_y)))
	# Enemy row (revealed slots MAX_SLOTS+0 .. MAX_SLOTS+2)
	for i in MAX_SLOTS:
		var cd: CardData = _enemy_plan[i] if i < _enemy_plan.size() else null
		_resolve_display.append(_add_reveal_card(root, cd, _enemy,
				Vector2(LEFT_X + i * _CARD_GAP, enemy_y)))
	# Row labels appended AFTER the 6 cards so slot indexing stays intact.
	_resolve_display.append(_plan_row_label(root, "You",
			Vector2(LEFT_X, player_y - 26.0), Color(0.60, 0.90, 1.0)))
	_resolve_display.append(_plan_row_label(root, "Enemy",
			Vector2(LEFT_X, enemy_y - 26.0), Color(1.0, 0.62, 0.60)))
	# Box parts tracked last (they're already behind the cards in the tree).
	for d in deco:
		_resolve_display.append(d)


## Framed backdrop for the reveal: a rounded box with a title and a divider
## between the You / Enemy rows. Added to `root` before the cards so it sits
## behind them; returns its parts for lifetime tracking.
func _build_reveal_box(root: Node, left_x: float, player_y: float, enemy_y: float) -> Array:
	var pad_x := 16.0
	var box_left := left_x - pad_x
	var box_w := 2.0 * _CARD_GAP + _CARD_W + pad_x * 2.0
	var box_top := player_y - 58.0
	var box_bottom := enemy_y + _CARD_H + 14.0

	var box := Panel.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.position = Vector2(box_left, box_top)
	box.size = Vector2(box_w, box_bottom - box_top)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.07, 0.11, 0.90)
	sb.border_color = Color(0.40, 0.46, 0.58, 0.75)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(16)
	sb.shadow_color = Color(0.0, 0.0, 0.0, 0.55)
	sb.shadow_size = 8
	box.add_theme_stylebox_override("panel", sb)
	root.add_child(box)

	var title := Label.new()
	title.text = "Last Round"
	title.position = Vector2(box_left, box_top + 8.0)
	title.size = Vector2(box_w, 22.0)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	title.add_theme_constant_override("outline_size", 3)
	title.modulate = Color(0.74, 0.80, 0.92)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(title)

	var div := ColorRect.new()
	div.color = Color(0.35, 0.40, 0.50, 0.5)
	div.position = Vector2(box_left + 14.0, player_y + _CARD_H + 9.0)
	div.size = Vector2(box_w - 28.0, 2.0)
	div.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(div)

	return [box, title, div]


## One reveal card. Hovering it enlarges the card and highlights the cells that
## card would hit/reach on the board, from its caster's position and facing.
func _add_reveal_card(parent: Node, cd: CardData, token: Token, pos: Vector2) -> PlanCard:
	var card: PlanCard = PLAN_CARD_SCENE.instantiate()
	parent.add_child(card)
	card.setup(cd)
	card.position = pos
	if cd != null:
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		card.mouse_entered.connect(_on_reveal_hover.bind(cd, token, card))
		card.mouse_exited.connect(_on_reveal_unhover)
	else:
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return card


func _on_reveal_hover(cd: CardData, token: Token, card: Control) -> void:
	_show_reveal_tooltip(cd, card)
	_highlight_for(cd, token)


func _on_reveal_unhover() -> void:
	_hide_reveal_tooltip()
	clear_range_highlight()


## Highlight the board cells a card affects, from `token`'s cell — mirroring
## _do_action: MOVE is absolute (uses move_direction), ATTACK is facing-relative.
func _highlight_for(cd: CardData, token: Token) -> void:
	if cd == null or token == null:
		return
	var board := get_node_or_null("Board") as Board
	if board == null:
		return
	var is_move := cd.type == CardData.CardType.MOVE
	var cells: Array[Vector2i] = []
	if is_move:
		# Moves apply move_direction in absolute board space (no facing flip).
		if cd.move_direction != Vector2i.ZERO:
			cells.append(cd.move_direction)
		for offset in cd.affected_cells:
			cells.append(offset)
	else:
		var fx := token.get_facing().x
		for offset in cd.affected_cells:
			cells.append(Vector2i(offset.x * fx, offset.y))
	if cells.is_empty():
		return
	board.highlight_cells(cells, token.current_cell, is_move)


# ── Enlarged card tooltip (hover a reveal card) ───────────────────────────────

func _reveal_tooltip_layer() -> CanvasLayer:
	var l := get_node_or_null("RevealTooltipLayer") as CanvasLayer
	if l == null:
		l = CanvasLayer.new()
		l.name = "RevealTooltipLayer"
		l.layer = 15
		add_child(l)
	return l


func _show_reveal_tooltip(cd: CardData, card: Control) -> void:
	_hide_reveal_tooltip()
	if cd == null:
		return
	const BIG := Vector2(260.0, 390.0)
	# Full-size card in a wrapper scaled up — enlarged with no distortion.
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.scale = BIG / CARD_SIZE
	var gc: GameCard = CARD_SCENE.instantiate()
	gc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gc.focus_mode = Control.FOCUS_NONE
	gc.undraggable = true
	gc.data = cd
	holder.add_child(gc)
	gc.card_size = CARD_SIZE
	gc.set_anchors_preset(Control.PRESET_TOP_LEFT, false)
	gc.position = Vector2.ZERO
	gc.scale = Vector2.ONE
	# Centre the enlarged card on the hovered reveal card, clamped on-screen.
	var center := card.global_position + card.size * 0.5
	var pos := center - BIG * 0.5
	pos.x = clampf(pos.x, 10.0, 1920.0 - BIG.x - 10.0)
	pos.y = clampf(pos.y, 10.0, 1080.0 - BIG.y - 10.0)
	holder.position = pos
	_reveal_tooltip_layer().add_child(holder)
	_reveal_tooltip = holder


func _hide_reveal_tooltip() -> void:
	if is_instance_valid(_reveal_tooltip):
		_reveal_tooltip.queue_free()
	_reveal_tooltip = null


func _plan_row_label(parent: Node, text: String, pos: Vector2, color: Color) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.position = pos
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	lbl.add_theme_constant_override("outline_size", 4)
	lbl.modulate = color
	parent.add_child(lbl)
	return lbl


## Dim inactive slots; flip the active slot pair face-up. Awaitable.
func _reveal_slot_indicators(slot: int) -> void:
	for i in MAX_SLOTS:
		var active := (i == slot)
		var dim := Color.WHITE if active else Color(0.30, 0.30, 0.30)
		if i < _resolve_display.size():
			_resolve_display[i].modulate = dim
		var ei := MAX_SLOTS + i
		if ei < _resolve_display.size():
			_resolve_display[ei].modulate = dim
	if slot < _resolve_display.size():
		(_resolve_display[slot] as PlanCard).flip()
	if MAX_SLOTS + slot < _resolve_display.size():
		(_resolve_display[MAX_SLOTS + slot] as PlanCard).flip()
	await get_tree().create_timer(0.32).timeout   # flip takes 0.30 s


func _clear_plan_displays() -> void:
	_hide_reveal_tooltip()
	clear_range_highlight()
	for c in _resolve_display:
		if is_instance_valid(c):
			c.queue_free()
	_resolve_display.clear()




# ── Positioning helpers ───────────────────────────────────────────────────────

## Nudge tokens sideways when they share a cell so neither is hidden.
## Called right after the move phase of each slot (tweens are done).
func _update_sharing() -> void:
	if _player == null or _enemy == null:
		return
	if _player.current_cell == _enemy.current_cell:
		_player.visual_offset = Vector2(-SHARE_OFFSET, 0.0)
		_enemy.visual_offset  = Vector2( SHARE_OFFSET, 0.0)
	else:
		_player.visual_offset = Vector2.ZERO
		_enemy.visual_offset  = Vector2.ZERO
	_player.apply_visual_offset()
	_enemy.apply_visual_offset()


## Keep tokens facing each other; flips when one passes the other.
## Same cell → always face inward to match the left/right nudge ordering.
func _update_facing() -> void:
	if _player == null or _enemy == null:
		return
	if _player.current_cell == _enemy.current_cell:
		# Shared cell: player nudged left, enemy nudged right — face inward.
		_player.facing = Vector2i(1, 0)
		_enemy.facing  = Vector2i(-1, 0)
	else:
		var dx := _enemy.current_cell.x - _player.current_cell.x
		if dx > 0:
			_player.facing = Vector2i(1, 0)
			_enemy.facing  = Vector2i(-1, 0)
		elif dx < 0:
			_player.facing = Vector2i(-1, 0)
			_enemy.facing  = Vector2i(1, 0)
		# dx == 0 but different row: keep whichever facing they had
	_player.queue_redraw()
	_enemy.queue_redraw()


# ── Combat feedback ───────────────────────────────────────────────────────────

func _spawn_damage_number(token: Token, amount: int) -> void:
	_spawn_float_text(token, "-%d" % amount, Color(1.0, 0.22, 0.22), 34)


## Floating combat text over a token: drifts up and fades out.
func _spawn_float_text(token: Token, text: String, color: Color, font_size: int) -> void:
	var ui := get_node_or_null("UI") as CanvasLayer
	if ui == null:
		return
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	lbl.add_theme_constant_override("outline_size", 6)
	# token.global_position is design-space screen coords (no camera in this scene)
	# Slight random x nudge so back-to-back numbers don't stack exactly.
	lbl.position = token.global_position + Vector2(-18.0 + randf_range(-14.0, 14.0), -90.0)
	ui.add_child(lbl)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(lbl, "position:y", lbl.position.y - 72.0, 0.9)
	tween.tween_property(lbl, "modulate:a", 0.0, 0.9)
	await tween.finished
	if is_instance_valid(lbl):
		lbl.queue_free()


# ── Win reward overlay ────────────────────────────────────────────────────────

func _show_win_reward() -> void:
	# Coin amount scales with node difficulty.
	var node_type := MapNode.Type.FIGHT
	if GameState.current_node_id >= 0 and GameState.has_map():
		node_type = GameState.map_nodes[GameState.current_node_id].type

	# Dojo: no card/equipment reward — the prize is a free upgrade back on the map.
	if node_type == MapNode.Type.DOJO:
		GameState.coins += randi_range(15, 25)
		GameState.dojo_reward_pending = true
		GameState.battle_tier_override = -1
		get_tree().change_scene_to_file(MAP_SCENE)
		return

	# Tier override also raises the reward tier (e.g. secret elite).
	if GameState.battle_tier_override != -1:
		node_type = GameState.battle_tier_override as MapNode.Type

	var coins_earned: int
	match node_type:
		MapNode.Type.ELITE: coins_earned = randi_range(75, 100)
		MapNode.Type.BOSS:  coins_earned = randi_range(150, 200)
		_:                  coins_earned = randi_range(30, 50)

	# Bounty contract: triple coins if the fight ended fast enough.
	if GameState.bounty_rounds > 0 and _round <= GameState.bounty_rounds:
		coins_earned *= 3
	coins_earned *= GameState.coin_mult

	# Consume one-shot battle modifiers.
	GameState.battle_tier_override = -1
	GameState.bounty_rounds = 0
	GameState.coin_mult = 1

	# Build reward choices: FIGHT → 3 cards, ELITE → 2 cards + 1 equip, BOSS → 1 card + 2 equip.
	var card_count: int
	var equip_count: int
	match node_type:
		MapNode.Type.BOSS:  card_count = 1; equip_count = 2
		MapNode.Type.ELITE: card_count = 2; equip_count = 1
		_:                  card_count = 3; equip_count = 0
	var card_pool: Array = CardData.reward_pool().duplicate()
	card_pool.shuffle()
	var choices: Array = []
	for i in mini(card_count, card_pool.size()):
		choices.append((card_pool[i] as CardData).duplicate())
	for i in equip_count:
		var drop := EquipmentData.random_drop()
		if drop != null:
			choices.append(drop)

	# Full-screen overlay (CanvasLayer so it appears above everything).
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

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.offset_left   = -440.0
	vbox.offset_right  =  440.0
	vbox.offset_top    = -320.0
	vbox.offset_bottom =  320.0
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 28)
	root.add_child(vbox)

	var title_lbl := Label.new()
	title_lbl.text = "Victory!"
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 56)
	title_lbl.modulate = Color(1.0, 0.87, 0.2)
	vbox.add_child(title_lbl)

	var coins_row := HBoxContainer.new()
	coins_row.alignment = BoxContainer.ALIGNMENT_CENTER
	coins_row.add_theme_constant_override("separation", 16)
	vbox.add_child(coins_row)

	var earned_lbl := Label.new()
	earned_lbl.text = "+ %d coins" % coins_earned
	earned_lbl.add_theme_font_size_override("font_size", 30)
	earned_lbl.modulate = Color(1.0, 0.85, 0.1)
	coins_row.add_child(earned_lbl)

	var div_lbl := Label.new()
	div_lbl.text = "|"
	div_lbl.add_theme_font_size_override("font_size", 30)
	div_lbl.modulate = Color(0.6, 0.6, 0.6)
	coins_row.add_child(div_lbl)

	var total_lbl := Label.new()
	total_lbl.text = "Total: %d" % (GameState.coins + coins_earned)
	total_lbl.add_theme_font_size_override("font_size", 30)
	coins_row.add_child(total_lbl)

	var pick_lbl := Label.new()
	pick_lbl.text = "Flip a reward to reveal it, then Take Reward."
	pick_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pick_lbl.add_theme_font_size_override("font_size", 20)
	pick_lbl.modulate = Color(0.80, 0.80, 0.80)
	vbox.add_child(pick_lbl)

	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 40)
	vbox.add_child(hbox)

	# Action row: Take (enabled once a reward is selected) + Skip (coins only).
	var action_row := HBoxContainer.new()
	action_row.alignment = BoxContainer.ALIGNMENT_CENTER
	action_row.add_theme_constant_override("separation", 20)
	vbox.add_child(action_row)

	var take_btn := Button.new()
	take_btn.text = "Take Reward"
	take_btn.add_theme_font_size_override("font_size", 18)
	take_btn.disabled = true
	action_row.add_child(take_btn)

	var skip_all := Button.new()
	skip_all.text = "Skip — keep coins only"
	skip_all.add_theme_font_size_override("font_size", 15)
	skip_all.pressed.connect(func():
		GameState.coins += coins_earned
		overlay.queue_free()
		_advance_floor_if_boss()
		get_tree().change_scene_to_file(MAP_SCENE)
	)
	action_row.add_child(skip_all)

	# Build the selectable reward tiles (actual card visuals / item icons).
	var tiles: Array = []
	var selected := {"item": null}
	for item in choices:
		var tile := _make_reward_tile(item)
		hbox.add_child(tile["node"])
		tiles.append(tile)

	# Clicking a tile reveals it (flip) and selects it: glow the choice with the
	# gold outline, un-glow the rest, and arm Take.
	for tile in tiles:
		var this_tile: Dictionary = tile
		(this_tile["button"] as Button).pressed.connect(func():
			(this_tile["reveal"] as Callable).call()
			selected["item"] = this_tile["item"]
			for t in tiles:
				(t["set_selected"] as Callable).call(t == this_tile)
			take_btn.disabled = false
		)

	take_btn.pressed.connect(func():
		var it = selected["item"]
		if it == null:
			return
		if it is CardData:
			_on_reward_chosen(it as CardData, coins_earned, overlay)
		else:
			_on_equipment_chosen(it as EquipmentData, coins_earned, overlay)
	)


## One reward tile. Starts face-down (a "?" card back); clicking it flips to
## reveal the real card visual (for CardData) or item icon (for EquipmentData).
## When selected a soft halo glows AROUND the card edges (drawn behind it, so the
## card face stays crisp). Equipment shows its details on hover once revealed.
## Returns { node, button, set_selected, reveal, item }.
func _make_reward_tile(item) -> Dictionary:
	const W := 200.0
	const H := 300.0
	var wrap := Control.new()
	wrap.custom_minimum_size = Vector2(W, H)
	wrap.size          = Vector2(W, H)
	wrap.pivot_offset  = Vector2(W * 0.5, H * 0.5)

	# Halo glow — behind everything, so its shadow only shows around the edges.
	var glow := Panel.new()
	glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	style.set_corner_radius_all(10)
	style.shadow_color = Color(0, 0, 0, 0)   # invisible until selected
	style.shadow_size  = 0
	glow.add_theme_stylebox_override("panel", style)
	wrap.add_child(glow)

	# Face-down back (visible until revealed).
	var back := Panel.new()
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bs := StyleBoxFlat.new()
	bs.bg_color = Color(0.11, 0.09, 0.16)
	bs.set_corner_radius_all(10)
	bs.set_border_width_all(3)
	bs.border_color = Color(0.52, 0.42, 0.18)
	back.add_theme_stylebox_override("panel", bs)
	var q := Label.new()
	q.text = "?"
	q.add_theme_font_size_override("font_size", 96)
	q.modulate = Color(0.42, 0.32, 0.13)
	q.set_anchors_preset(Control.PRESET_FULL_RECT)
	q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	q.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	q.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.add_child(q)
	wrap.add_child(back)

	# Front content (hidden until revealed) — fills the tile so the halo hugs it.
	var front := VBoxContainer.new()
	front.set_anchors_preset(Control.PRESET_FULL_RECT)
	front.alignment = BoxContainer.ALIGNMENT_CENTER
	front.add_theme_constant_override("separation", 6)
	front.mouse_filter = Control.MOUSE_FILTER_IGNORE
	front.visible = false
	wrap.add_child(front)

	if item is CardData:
		var card: GameCard = CARD_SCENE.instantiate()
		card.data = item as CardData
		card.undraggable = true
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE   # clicks go to the overlay button
		card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		front.add_child(card)
	else:
		var ed := item as EquipmentData
		var tile := InventoryOverlay.make_tile(ed, 150.0)
		tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tile.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		front.add_child(tile)

		var name_lbl := Label.new()
		name_lbl.text = "%s%s" % [ed.equipment_name, EquipmentData.enchant_tag(ed)]
		name_lbl.add_theme_font_size_override("font_size", 16)
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		name_lbl.modulate = EquipmentData.rarity_color(ed.rarity)
		front.add_child(name_lbl)

		var stat_lbl := Label.new()
		stat_lbl.text = EquipmentData.stat_summary(ed)
		stat_lbl.add_theme_font_size_override("font_size", 13)
		stat_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		stat_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		stat_lbl.modulate = Color(0.88, 0.88, 0.6)
		front.add_child(stat_lbl)

	# Transparent click layer covering the whole tile (drawn last = on top).
	var btn := Button.new()
	btn.flat = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	wrap.add_child(btn)

	# Flip-reveal, once, with a "card opening" scale animation.
	var revealed := [false]
	var reveal := func() -> void:
		if revealed[0]:
			return
		revealed[0] = true
		if item is EquipmentData:
			btn.tooltip_text = EquipmentData.tooltip(item as EquipmentData)  # details on hover
		var tw := wrap.create_tween().set_trans(Tween.TRANS_SINE)
		tw.tween_property(wrap, "scale:x", 0.0, 0.12).set_ease(Tween.EASE_IN)
		tw.tween_callback(func(): back.hide(); front.show())
		tw.tween_property(wrap, "scale:x", 1.0, 0.14).set_ease(Tween.EASE_OUT)

	# Toggle the halo glow around the card on selection (card face untouched).
	var set_selected := func(on: bool) -> void:
		if on:
			style.shadow_color = Color(1.0, 0.82, 0.28, 0.85)
			style.shadow_size  = 26
		else:
			style.shadow_color = Color(0, 0, 0, 0)
			style.shadow_size  = 0

	return {"node": wrap, "button": btn, "set_selected": set_selected, "reveal": reveal, "item": item}


func _advance_floor_if_boss() -> void:
	if GameState.current_node_id < 0 or not GameState.has_map():
		return
	if GameState.map_nodes[GameState.current_node_id].type == MapNode.Type.BOSS:
		GameState.floor_num += 1
		GameState.map_nodes = []
		# Old node ids mean nothing on the next floor's map — without this the
		# new map would open focused on a random node instead of START.
		GameState.current_node_id = -1


func _on_reward_chosen(cd: CardData, coins_earned: int, overlay: CanvasLayer) -> void:
	GameState.coins += coins_earned
	GameState.deck.append(cd.duplicate())
	overlay.queue_free()
	_advance_floor_if_boss()
	get_tree().change_scene_to_file(MAP_SCENE)


func _on_equipment_chosen(ed: EquipmentData, coins_earned: int, overlay: CanvasLayer) -> void:
	GameState.coins += coins_earned
	# Rewards always go to the inventory; equipping is a deliberate act there.
	GameState.inventory.append(ed)
	overlay.queue_free()
	_advance_floor_if_boss()
	get_tree().change_scene_to_file(MAP_SCENE)


# ── Equipment application ─────────────────────────────────────────────────────

func _apply_equipment() -> void:
	if _player == null:
		return
	# Cursed shrine penalty — reduces max HP for the whole run.
	if GameState.max_hp_curse > 0:
		_player.max_hp = maxi(5, _player.max_hp - GameState.max_hp_curse)
		_player.hp = mini(_player.hp, _player.max_hp)
	# Aggregate all stats from every equipped slot so scrolled cross-stat items work.
	for item in GameState.equipment.values():
		var ed := item as EquipmentData
		if ed == null:
			continue
		if ed.max_hp_bonus > 0:
			_player.max_hp += ed.max_hp_bonus
			_player.heal(ed.max_hp_bonus)
		if ed.max_energy_bonus > 0:
			_player.max_energy += ed.max_energy_bonus
			_player.gain_energy(ed.max_energy_bonus)
		_player_damage_bonus += ed.damage_bonus
		_player_crit_chance  += ed.crit_chance


# ── TEMP debug input (1/2 damage enemy/player, 3/4 player energy; arrows queue a move)
func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if _move_keys.has(event.keycode):
		var i := _next_free_slot()
		if i >= 0:
			_on_slot_dropped(i, {"data": _move_keys[event.keycode], "consumable": false})
		return
	match event.keycode:
		KEY_1: if _enemy: _enemy.take_damage(5)
		KEY_2: if _player: _player.take_damage(5)
		KEY_3: if _player: _player.spend_energy(2)
		KEY_4: if _player: _player.gain_energy(3)


# ── Range highlight (called by GameCard on hover/drag) ────────────────────

func show_range_highlight(cd: CardData) -> void:
	if _player == null or cd == null or cd.affected_cells.is_empty():
		return
	var board := get_node_or_null("Board") as Board
	if board == null:
		return
	var is_move := cd.type == CardData.CardType.MOVE
	board.highlight_cells(cd.affected_cells, _player.current_cell, is_move)


func clear_range_highlight() -> void:
	var board := get_node_or_null("Board") as Board
	if board:
		board.clear_highlight()
