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
var _intent_displays: Array[Control] = []  # enemy intent chips shown during PLAN phase
var _all_cards: Array[CardData] = []  # full collection for the bag view
var _card_viewer: CardViewer
# Hand cards discarding on lock-in; freed at the start of _cleanup().
var _discarding_hand_cards: Array[GameCard] = []

# Move placeholder + picker
var _ai: EnemyAI
var _enemy_attack_card: CardData
var _enemy_recover_card: CardData

var _move_placeholder: GameCard
var _move_placeholder_home := Vector2(1640.0, 845.0)
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
	if _enemy != null:
		_enemy.hit.connect(func(amount: int): _spawn_damage_number(_enemy, amount))

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
		_lock_in.mouse_entered.connect(_on_lock_in_hover.bind(true))
		_lock_in.mouse_exited.connect(_on_lock_in_hover.bind(false))

	_hide_btn = get_node_or_null("UI/HideButton") as Button
	if _hide_btn != null:
		_hide_btn.pressed.connect(_on_toggle_hide)
		_hide_btn.mouse_entered.connect(_on_hide_hover.bind(true))
		_hide_btn.mouse_exited.connect(_on_hide_hover.bind(false))

	var pause_btn := get_node_or_null("UI/BattleHUD/PauseButton") as Button
	if pause_btn != null:
		pause_btn.pressed.connect(_on_pause_toggle)

	var bag_btn := get_node_or_null("UI/BattleHUD/BagButton") as Button
	if bag_btn != null:
		bag_btn.pressed.connect(_on_bag_pressed)

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
	_clear_plan_displays()
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


## Show/hide all the card-planning UI. Hidden during the fight so the player can
## just watch the board; shown again in the plan phase.
func _set_planning_ui_visible(on: bool) -> void:
	for path in ["UI/Hand", "UI/PlanBar", "UI/LockInButton", "UI/HideButton"]:
		var n := get_node_or_null(path) as CanvasItem
		if n != null:
			n.visible = on
	if _move_placeholder != null:
		_move_placeholder.visible = on


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
		_hand.take_card(card)
	else:
		card = CARD_SCENE.instantiate()
		card.consumable = false
		card.data = data

	var slot = _slot_nodes[index]
	slot.add_child(card)
	card.set_anchors_preset(Control.PRESET_TOP_LEFT, false)
	card.position     = Vector2.ZERO
	card.rotation     = 0.0
	card.scale        = Vector2.ONE
	card.pivot_offset = Vector2.ZERO
	card.size         = CARD_SIZE
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE  # let clicks reach the slot (to clear)
	card.move_to_front()
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
	slot.add_child(card)
	card.set_anchors_preset(Control.PRESET_TOP_LEFT, false)
	card.position     = Vector2.ZERO
	card.rotation     = 0.0
	card.scale        = Vector2.ONE
	card.pivot_offset = Vector2.ZERO
	card.size         = CARD_SIZE
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.show_placeholder(false)
	_plan[index] = {"data": cd, "consumable": false, "card": card}
	_refresh_lock_in()


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
		if is_instance_valid(card) and card.get_parent() == slot:
			slot.remove_child(card)
		if entry.consumable and is_instance_valid(card):
			card.mouse_filter = Control.MOUSE_FILTER_STOP
			card.size = CARD_SIZE
			_hand.return_card(card)
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


func _on_lock_in_hover(is_hovered: bool) -> void:
	var mat := _lock_in.material as ShaderMaterial
	if mat and mat.get_shader_parameter("active"):
		mat.set_shader_parameter("hovered", is_hovered)


func _refresh_lock_in() -> void:
	var n := 0
	for entry in _plan:
		if entry != null:
			n += 1
	if _lock_in != null:
		var ready := n == MAX_SLOTS
		_lock_in.disabled = not ready
		var mat := _lock_in.material as ShaderMaterial
		if mat:
			mat.set_shader_parameter("active", ready)
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

func _on_hide_hover(is_hovered: bool) -> void:
	var mat := _hide_btn.material as ShaderMaterial
	if mat:
		mat.set_shader_parameter("hovered", is_hovered)


func _on_toggle_hide() -> void:
	var plan_bar := get_node_or_null("UI/PlanBar") as CanvasItem
	var show := not (plan_bar != null and plan_bar.visible)
	if plan_bar != null:
		plan_bar.visible = show
	if _hide_btn != null:
		var mat := _hide_btn.material as ShaderMaterial
		if mat:
			mat.set_shader_parameter("active", not show)
			mat.set_shader_parameter("hovered", false)


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
	var ui := get_node_or_null("UI") as CanvasLayer
	if ui == null:
		return
	_clear_enemy_intent()

	var header := Label.new()
	header.text = "Enemy intent:"
	header.add_theme_font_size_override("font_size", 13)
	header.modulate = Color(0.85, 0.50, 0.50)
	header.position = Vector2(1560.0, 66.0)
	ui.add_child(header)
	_intent_displays.append(header)

	for i in _enemy_plan.size():
		var cd: CardData = _enemy_plan[i]
		var chip := Panel.new()
		chip.size = Vector2(110.0, 36.0)
		chip.position = Vector2(1560.0 + i * 118.0, 86.0)

		var style := StyleBoxFlat.new()
		style.corner_radius_top_left     = 6
		style.corner_radius_top_right    = 6
		style.corner_radius_bottom_left  = 6
		style.corner_radius_bottom_right = 6
		style.set_border_width_all(1)

		var lbl := Label.new()
		lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 13)
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE

		if cd == null:
			style.bg_color     = Color(0.12, 0.12, 0.12)
			style.border_color = Color(0.28, 0.28, 0.28)
			lbl.text = "—"
		elif cd.type == CardData.CardType.MOVE:
			style.bg_color     = Color(0.06, 0.20, 0.09)
			style.border_color = Color(0.22, 0.68, 0.32)
			lbl.modulate = Color(0.40, 1.0, 0.55)
			var dir := cd.move_direction
			var arrow := "→" if dir.x > 0 else "←" if dir.x < 0 else "↓" if dir.y > 0 else "↑"
			lbl.text = "%s Move" % arrow
		elif cd.type == CardData.CardType.ATTACK:
			style.bg_color     = Color(0.22, 0.05, 0.05)
			style.border_color = Color(0.80, 0.20, 0.20)
			lbl.modulate = Color(1.0, 0.42, 0.42)
			lbl.text = "⚔ %d dmg" % cd.damage
		else:
			style.bg_color     = Color(0.06, 0.10, 0.24)
			style.border_color = Color(0.25, 0.52, 0.90)
			lbl.modulate = Color(0.55, 0.75, 1.0)
			lbl.text = "✦ +%d" % cd.energy_gain

		chip.add_theme_stylebox_override("panel", style)
		chip.add_child(lbl)
		ui.add_child(chip)
		_intent_displays.append(chip)


func _clear_enemy_intent() -> void:
	for c in _intent_displays:
		if is_instance_valid(c):
			c.queue_free()
	_intent_displays.clear()


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

	_cleanup()


func _cleanup() -> void:
	# PlanBar was hidden during resolve; reveal it so slot cards can animate.
	var plan_bar := get_node_or_null("UI/PlanBar") as CanvasItem
	if plan_bar != null:
		plan_bar.visible = true

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
		if entry.consumable:
			_deck.discard(entry.data)
			if is_instance_valid(card) and discard_target != Vector2.INF:
				card.tween_position(discard_target, 0.35, true)
				card.tween_scale(Vector2(0.1, 0.1), 0.35)
				flying.append(card)
			elif is_instance_valid(card):
				card.queue_free()
		elif is_instance_valid(card):
			card.queue_free()   # non-consumable slot duplicate — just remove it
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
			actor.move_to_cell(actor.current_cell + data.move_direction)
			return true
		CardData.CardType.ATTACK:
			if not actor.spend_energy(data.cost):
				return false
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
const _CARD_W   := 100.0
const _CARD_H   := 140.0
const _CARD_GAP := 110.0   # center-to-center spacing between slots

func _show_plan_displays() -> void:
	var ui := get_node_or_null("UI") as CanvasLayer
	if ui == null:
		return
	# Player row: below PlayerHUD, top-left (y=100)
	for i in MAX_SLOTS:
		var cd: CardData = _plan[i].data if _plan[i] != null else null
		var card: PlanCard = PLAN_CARD_SCENE.instantiate()
		ui.add_child(card)
		card.setup(cd)
		card.position = Vector2(20.0 + i * _CARD_GAP, 100.0)
		_resolve_display.append(card)
	# Enemy row: below EnemyHUD, top-right (y=100)
	for i in MAX_SLOTS:
		var cd: CardData = _enemy_plan[i] if i < _enemy_plan.size() else null
		var card: PlanCard = PLAN_CARD_SCENE.instantiate()
		ui.add_child(card)
		card.setup(cd)
		card.position = Vector2(1580.0 + i * _CARD_GAP, 100.0)
		_resolve_display.append(card)


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
	var ui := get_node_or_null("UI") as CanvasLayer
	if ui == null:
		return
	var lbl := Label.new()
	lbl.text = "-%d" % amount
	lbl.add_theme_font_size_override("font_size", 34)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.22, 0.22))
	# token.global_position is design-space screen coords (no camera in this scene)
	lbl.position = token.global_position + Vector2(-18.0, -90.0)
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
	var equip_pool: Array = EquipmentData.all().duplicate()
	equip_pool.shuffle()
	var choices: Array = []
	for i in mini(card_count, card_pool.size()):
		choices.append((card_pool[i] as CardData).duplicate())
	for i in mini(equip_count, equip_pool.size()):
		choices.append((equip_pool[i] as EquipmentData).duplicate())

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
	pick_lbl.text = "Flip a reward to reveal it — then take it or pass."
	pick_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pick_lbl.add_theme_font_size_override("font_size", 20)
	pick_lbl.modulate = Color(0.80, 0.80, 0.80)
	vbox.add_child(pick_lbl)

	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 40)
	vbox.add_child(hbox)

	var flip_state: Array = [false]
	for item in choices:
		if item is CardData:
			hbox.add_child(_make_reward_card(item as CardData, coins_earned, overlay, flip_state))
		else:
			hbox.add_child(_make_reward_equipment(item as EquipmentData, coins_earned, overlay, flip_state))

	# Skip button — take coins only, no card
	var skip_all := Button.new()
	skip_all.text = "Skip — keep coins only"
	skip_all.add_theme_font_size_override("font_size", 15)
	skip_all.pressed.connect(func():
		GameState.coins += coins_earned
		overlay.queue_free()
		_advance_floor_if_boss()
		get_tree().change_scene_to_file(MAP_SCENE)
	)
	vbox.add_child(skip_all)


## Face-down card; clicking it flips to reveal the front.
## Only the FIRST card flipped gets Take/Pass buttons — the rest are info-only.
func _make_reward_card(cd: CardData, coins_earned: int, overlay: CanvasLayer,
		flip_state: Array) -> Control:
	const W := 200.0; const H := 300.0
	var container := Control.new()
	container.custom_minimum_size = Vector2(W, H)
	container.size                = Vector2(W, H)
	container.pivot_offset        = Vector2(W * 0.5, H * 0.5)

	# Back (face-down)
	var back := Panel.new()
	back.name = "Back"; back.position = Vector2.ZERO; back.size = Vector2(W, H)
	back.mouse_filter = Control.MOUSE_FILTER_STOP
	var bs := StyleBoxFlat.new()
	bs.bg_color     = Color(0.11, 0.09, 0.16)
	bs.border_width_left = 2; bs.border_width_right  = 2
	bs.border_width_top  = 2; bs.border_width_bottom = 2
	bs.border_color = Color(0.52, 0.42, 0.18)
	bs.corner_radius_top_left    = 8; bs.corner_radius_top_right    = 8
	bs.corner_radius_bottom_left = 8; bs.corner_radius_bottom_right = 8
	back.add_theme_stylebox_override("panel", bs)
	var q := Label.new()
	q.text = "?"; q.add_theme_font_size_override("font_size", 72)
	q.modulate = Color(0.42, 0.32, 0.13)
	q.set_anchors_preset(Control.PRESET_FULL_RECT)
	q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	q.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	back.add_child(q)
	container.add_child(back)

	# Front (hidden until flip)
	var front := _make_reward_card_front(cd, W, H, coins_earned, overlay, container)
	front.name = "Front"; front.visible = false
	container.add_child(front)

	# Hover glow + click-to-flip
	back.mouse_entered.connect(func(): container.modulate = Color(1.25, 1.20, 1.10))
	back.mouse_exited.connect(func():  container.modulate = Color.WHITE)
	back.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			var is_first: bool = not flip_state[0]
			flip_state[0] = true
			# Hide action buttons on cards that are not the first flip.
			var actions := front.find_child("Actions", true, false)
			if actions != null:
				actions.visible = is_first
			_flip_reward_card(container)
	)
	return container


func _flip_reward_card(container: Control) -> void:
	var back  := container.get_node_or_null("Back")  as Control
	var front := container.get_node_or_null("Front") as Control
	if back == null or front == null or not back.visible:
		return
	container.modulate = Color.WHITE
	var tw := container.create_tween().set_trans(Tween.TRANS_SINE)
	tw.tween_property(container, "scale:x", 0.0, 0.15).set_ease(Tween.EASE_IN)
	tw.tween_callback(func(): back.hide(); front.show())
	tw.tween_property(container, "scale:x", 1.0, 0.15).set_ease(Tween.EASE_OUT)


func _make_reward_card_front(cd: CardData, W: float, H: float,
		coins_earned: int, overlay: CanvasLayer, container: Control) -> Panel:
	var type_color := Color(0.4, 0.4, 0.4)
	var type_tag: Dictionary = {
		CardData.CardType.ATTACK: "ATTACK", CardData.CardType.SKILL:  "SKILL",
		CardData.CardType.POWER:  "POWER",  CardData.CardType.MOVE:   "MOVE",
	}
	if cd != null:
		match cd.type:
			CardData.CardType.ATTACK: type_color = Color(0.82, 0.25, 0.25)
			CardData.CardType.SKILL:  type_color = Color(0.25, 0.56, 0.88)
			CardData.CardType.POWER:  type_color = Color(0.65, 0.25, 0.88)
			CardData.CardType.MOVE:   type_color = Color(0.25, 0.76, 0.38)

	var panel := Panel.new()
	panel.position = Vector2.ZERO; panel.size = Vector2(W, H)
	var fs := StyleBoxFlat.new()
	fs.bg_color     = Color(0.07, 0.06, 0.05)
	fs.border_width_left = 2; fs.border_width_right  = 2
	fs.border_width_top  = 2; fs.border_width_bottom = 2
	fs.border_color = type_color
	fs.corner_radius_top_left    = 8; fs.corner_radius_top_right    = 8
	fs.corner_radius_bottom_left = 8; fs.corner_radius_bottom_right = 8
	panel.add_theme_stylebox_override("panel", fs)

	var vbox := VBoxContainer.new()
	vbox.position = Vector2(10.0, 10.0); vbox.size = Vector2(W - 20.0, H - 20.0)
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	var name_lbl := Label.new()
	name_lbl.text = cd.card_name if cd != null else "?"
	name_lbl.add_theme_font_size_override("font_size", 18)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(name_lbl)
	vbox.add_child(HSeparator.new())

	var type_lbl := Label.new()
	type_lbl.text = type_tag.get(cd.type, "?") if cd != null else ""
	type_lbl.add_theme_font_size_override("font_size", 12)
	type_lbl.modulate = type_color
	type_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(type_lbl)

	var cost_lbl := Label.new()
	cost_lbl.text = "Cost: %d" % (cd.cost if cd != null else 0)
	cost_lbl.add_theme_font_size_override("font_size", 13)
	cost_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(cost_lbl)

	if cd != null and cd.description.length() > 0:
		vbox.add_child(HSeparator.new())
		var desc_lbl := Label.new()
		desc_lbl.text = cd.description
		desc_lbl.add_theme_font_size_override("font_size", 12)
		desc_lbl.modulate = Color(0.82, 0.82, 0.82)
		desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(desc_lbl)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)
	vbox.add_child(HSeparator.new())

	# Take / Pass buttons (hidden on non-first flips via the "Actions" name)
	var btn_row := HBoxContainer.new()
	btn_row.name = "Actions"
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 8)
	vbox.add_child(btn_row)

	var take_btn := Button.new()
	take_btn.text = "Take it"
	take_btn.add_theme_font_size_override("font_size", 14)
	take_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	take_btn.pressed.connect(func():
		_flip_other_reward_cards(container)
		await get_tree().create_timer(0.35).timeout
		_on_reward_chosen(cd, coins_earned, overlay)
	)
	btn_row.add_child(take_btn)

	var pass_btn := Button.new()
	pass_btn.text = "Pass"
	pass_btn.add_theme_font_size_override("font_size", 14)
	pass_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pass_btn.pressed.connect(func():
		container.modulate = Color(0.40, 0.40, 0.40)
		take_btn.disabled = true
		pass_btn.disabled = true
		_flip_other_reward_cards(container)
	)
	btn_row.add_child(pass_btn)

	return panel


## Flip every sibling card that is still face-down (no action buttons on them).
## Finds siblings via the shared parent HBoxContainer — no array needed.
func _flip_other_reward_cards(current: Control) -> void:
	var hbox := current.get_parent()
	if hbox == null:
		return
	for i in hbox.get_child_count():
		var c := hbox.get_child(i) as Control
		if c == null or c == current:
			continue
		var back := c.get_node_or_null("Back") as Control
		if back == null or not back.visible:
			continue
		var front: Node = c.get_node_or_null("Front")
		if front != null:
			var actions: Node = front.find_child("Actions", true, false)
			if actions != null:
				actions.visible = false
		_flip_reward_card(c)


func _advance_floor_if_boss() -> void:
	if GameState.current_node_id < 0 or not GameState.has_map():
		return
	if GameState.map_nodes[GameState.current_node_id].type == MapNode.Type.BOSS:
		GameState.floor_num += 1
		GameState.map_nodes = []


func _on_reward_chosen(cd: CardData, coins_earned: int, overlay: CanvasLayer) -> void:
	GameState.coins += coins_earned
	GameState.deck.append(cd.duplicate())
	overlay.queue_free()
	_advance_floor_if_boss()
	get_tree().change_scene_to_file(MAP_SCENE)


func _on_equipment_chosen(ed: EquipmentData, coins_earned: int, overlay: CanvasLayer) -> void:
	GameState.coins += coins_earned
	var old := GameState.equipment.get(ed.slot) as EquipmentData
	if old != null:
		GameState.inventory.append(old)
	GameState.equipment[ed.slot] = ed
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


# ── Equipment reward card ─────────────────────────────────────────────────────

func _make_reward_equipment(ed: EquipmentData, coins_earned: int, overlay: CanvasLayer,
		flip_state: Array) -> Control:
	const W := 200.0; const H := 300.0
	var container := Control.new()
	container.custom_minimum_size = Vector2(W, H)
	container.size                = Vector2(W, H)
	container.pivot_offset        = Vector2(W * 0.5, H * 0.5)

	var back := Panel.new()
	back.name = "Back"; back.position = Vector2.ZERO; back.size = Vector2(W, H)
	back.mouse_filter = Control.MOUSE_FILTER_STOP
	var bs := StyleBoxFlat.new()
	bs.bg_color     = Color(0.11, 0.09, 0.16)
	bs.border_width_left = 2; bs.border_width_right  = 2
	bs.border_width_top  = 2; bs.border_width_bottom = 2
	bs.border_color = Color(0.52, 0.42, 0.18)
	bs.corner_radius_top_left    = 8; bs.corner_radius_top_right    = 8
	bs.corner_radius_bottom_left = 8; bs.corner_radius_bottom_right = 8
	back.add_theme_stylebox_override("panel", bs)
	var q := Label.new()
	q.text = "?"; q.add_theme_font_size_override("font_size", 72)
	q.modulate = Color(0.42, 0.32, 0.13)
	q.set_anchors_preset(Control.PRESET_FULL_RECT)
	q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	q.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	back.add_child(q)
	container.add_child(back)

	var front := _make_reward_equipment_front(ed, W, H, coins_earned, overlay, container)
	front.name = "Front"; front.visible = false
	container.add_child(front)

	back.mouse_entered.connect(func(): container.modulate = Color(1.25, 1.20, 1.10))
	back.mouse_exited.connect(func():  container.modulate = Color.WHITE)
	back.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			var is_first: bool = not flip_state[0]
			flip_state[0] = true
			var actions := front.find_child("Actions", true, false)
			if actions != null:
				actions.visible = is_first
			_flip_reward_card(container)
	)
	return container


func _make_reward_equipment_front(ed: EquipmentData, W: float, H: float,
		coins_earned: int, overlay: CanvasLayer, container: Control) -> Panel:
	var slot_colors := {
		EquipmentData.Slot.WEAPON:  Color(0.90, 0.50, 0.20),
		EquipmentData.Slot.OFFHAND: Color(0.25, 0.56, 0.88),
		EquipmentData.Slot.CHEST:   Color(0.25, 0.75, 0.45),
		EquipmentData.Slot.HELM:    Color(0.65, 0.25, 0.88),
		EquipmentData.Slot.SHOES:   Color(0.20, 0.80, 0.85),
	}
	var slot_labels := {
		EquipmentData.Slot.WEAPON:  "WEAPON",
		EquipmentData.Slot.OFFHAND: "OFFHAND",
		EquipmentData.Slot.CHEST:   "CHEST",
		EquipmentData.Slot.HELM:    "HELM",
		EquipmentData.Slot.SHOES:   "SHOES",
	}
	var slot_color: Color = slot_colors.get(ed.slot, Color(0.6, 0.6, 0.6))
	var slot_label: String = slot_labels.get(ed.slot, "EQUIP")
	var rarity_col := EquipmentData.rarity_color(ed.rarity)

	var panel := Panel.new()
	panel.position = Vector2.ZERO; panel.size = Vector2(W, H)
	var fs := StyleBoxFlat.new()
	fs.bg_color     = Color(0.07, 0.06, 0.05)
	fs.border_width_left = 2; fs.border_width_right  = 2
	fs.border_width_top  = 2; fs.border_width_bottom = 2
	fs.border_color = rarity_col
	fs.corner_radius_top_left    = 8; fs.corner_radius_top_right    = 8
	fs.corner_radius_bottom_left = 8; fs.corner_radius_bottom_right = 8
	panel.add_theme_stylebox_override("panel", fs)

	var vbox := VBoxContainer.new()
	vbox.position = Vector2(10.0, 10.0); vbox.size = Vector2(W - 20.0, H - 20.0)
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	var name_lbl := Label.new()
	name_lbl.text = ed.equipment_name
	name_lbl.add_theme_font_size_override("font_size", 18)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(name_lbl)

	var rarity_lbl := Label.new()
	rarity_lbl.text = EquipmentData.rarity_name(ed.rarity)
	rarity_lbl.add_theme_font_size_override("font_size", 12)
	rarity_lbl.modulate = rarity_col
	rarity_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(rarity_lbl)
	vbox.add_child(HSeparator.new())

	var type_lbl := Label.new()
	type_lbl.text = slot_label
	type_lbl.add_theme_font_size_override("font_size", 12)
	type_lbl.modulate = slot_color
	type_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(type_lbl)

	vbox.add_child(HSeparator.new())
	for stat in _equipment_stat_lines(ed):
		var sl := Label.new()
		sl.text = stat
		sl.add_theme_font_size_override("font_size", 14)
		sl.modulate = Color(0.90, 0.90, 0.60)
		sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(sl)

	if ed.description.length() > 0:
		vbox.add_child(HSeparator.new())
		var desc_lbl := Label.new()
		desc_lbl.text = ed.description
		desc_lbl.add_theme_font_size_override("font_size", 12)
		desc_lbl.modulate = Color(0.82, 0.82, 0.82)
		desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(desc_lbl)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)
	vbox.add_child(HSeparator.new())

	var btn_row := HBoxContainer.new()
	btn_row.name = "Actions"
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 8)
	vbox.add_child(btn_row)

	var take_btn := Button.new()
	take_btn.text = "Equip"
	take_btn.add_theme_font_size_override("font_size", 14)
	take_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	take_btn.pressed.connect(func():
		_flip_other_reward_cards(container)
		await get_tree().create_timer(0.35).timeout
		_on_equipment_chosen(ed, coins_earned, overlay)
	)
	btn_row.add_child(take_btn)

	var pass_btn := Button.new()
	pass_btn.text = "Pass"
	pass_btn.add_theme_font_size_override("font_size", 14)
	pass_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pass_btn.pressed.connect(func():
		container.modulate = Color(0.40, 0.40, 0.40)
		take_btn.disabled = true
		pass_btn.disabled = true
		_flip_other_reward_cards(container)
	)
	btn_row.add_child(pass_btn)

	return panel


## Returns a short list of stat strings for an equipment piece.
func _equipment_stat_lines(ed: EquipmentData) -> Array[String]:
	var lines: Array[String] = []
	if ed.damage_bonus    > 0: lines.append("+%d Attack Dmg"   % ed.damage_bonus)
	if ed.block_per_turn  > 0: lines.append("+%d Block / Round" % ed.block_per_turn)
	if ed.max_hp_bonus    > 0: lines.append("+%d Max HP"        % ed.max_hp_bonus)
	if ed.max_energy_bonus > 0: lines.append("+%d Max Energy"   % ed.max_energy_bonus)
	if ed.crit_chance     > 0: lines.append("+%d%% Crit Chance" % ed.crit_chance)
	return lines


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
