## Hand
## Holds the ATTACK / SKILL cards drawn from the deck. Lays them out in a
## circular fan arc at the bottom of the screen.
## When a card drag ends without landing on a slot, the deferred `_layout`
## call re-positions it back to its arc position.
class_name Hand
extends Control

const CARD_SCENE  := preload("res://scenes/cards/card.tscn")
const CARD_W      := 150.0
const CARD_H      := 210.0
const ARC_RADIUS  := 1200.0
const ARC_SPREAD  := 25.0
const MAX_HAND_SIZE := 5
const ARC_CENTER_X := 960.0

@export var cards: Array[CardData] = []
var _cards: Array[GameCard] = []
## Ever-increasing stamp assigned to each card so it can return to its original
## left-to-right position after a trip to a plan slot.
var _order_seq: int = 0


func _ready() -> void:
	for data in cards:
		add_card(data)


## from_pos: screen-space position the card should fly FROM (deck pile center).
## Leave as Vector2.INF to place it instantly at the arc position.
func add_card(data: CardData, from_pos: Vector2 = Vector2.INF) -> void:
	var card: GameCard = CARD_SCENE.instantiate()
	card.data = data  # must be set before add_child so Card._ready() sees it
	add_child(card)
	_connect_drag(card)
	card.set_meta("hand_order", _order_seq)
	_order_seq += 1
	_cards.append(card)
	if from_pos != Vector2.INF:
		card.position = from_pos         # start at deck; _layout will tween to arc
		_layout(true)
	else:
		_layout()


func remove_card(card: GameCard) -> void:
	_cards.erase(card)
	if is_instance_valid(card):
		card.queue_free()
	_layout()


## Pull a card OUT of the hand without freeing it (it's moving into a slot).
## Keep its hand_order stamp so return_card can restore its original position.
func take_card(card: GameCard) -> void:
	_cards.erase(card)
	if card.get_parent() == self:
		remove_child(card)
	_layout(true)


## Put a card back into the hand (e.g. when its slot was cleared), restoring it
## to its original left-to-right position rather than the far right.
## from_global: the card's screen position in its slot, so the fly-back animates
## from the slot rather than from wherever the reparent leaves it.
func return_card(card: GameCard, from_global: Vector2 = Vector2.INF) -> void:
	var parent := card.get_parent()
	if parent != null and parent != self:
		parent.remove_child(card)          # detach from its slot/wrapper first
	if card.get_parent() != self:
		add_child(card)
	if from_global != Vector2.INF:
		card.global_position = from_global   # animate the fly-back from the slot
	card.pivot_offset = Vector2(CARD_W * 0.5, 0.0)
	card.rotation     = 0.0
	card.scale        = Vector2.ONE
	if not _cards.has(card):
		if not card.has_meta("hand_order"):
			card.set_meta("hand_order", _order_seq)
			_order_seq += 1
		_insert_by_order(card)
		_connect_drag(card)
	_layout(true)


## Insert a returning card so _cards stays ordered by each card's hand_order.
func _insert_by_order(card: GameCard) -> void:
	var order: int = card.get_meta("hand_order", _order_seq)
	var idx := _cards.size()
	for i in _cards.size():
		if int(_cards[i].get_meta("hand_order", 0)) > order:
			idx = i
			break
	_cards.insert(idx, card)


func card_count() -> int:
	return _cards.size()


## Remove all cards from the hand's tracking list without freeing the nodes.
## Cards stay in the scene tree so callers can animate them before freeing.
func detach_all_cards() -> Array[GameCard]:
	var all := _cards.duplicate()
	_cards.clear()
	return all


func _connect_drag(card: GameCard) -> void:
	if not card.drag_ended.is_connected(_on_card_drag_ended):
		card.drag_ended.connect(_on_card_drag_ended)


## If the drag ended without a slot accepting the card, re-layout next frame
## so the card snaps back to its arc position. Deferred so that slot handlers
## (which may call take_card) run first in the same frame.
func _on_card_drag_ended(card: Card) -> void:
	var game_card := card as GameCard
	if game_card != null and game_card in _cards:
		call_deferred("_layout", true)  # animate=true: smooth tween back to arc


func _layout(animate: bool = false) -> void:
	var n := _cards.size()
	if n == 0:
		return

	var step_deg  := ARC_SPREAD / float(MAX_HAND_SIZE - 1)
	var total_deg := step_deg * float(n - 1)
	var start_deg := -total_deg * 0.5

	for i in n:
		# Keep draw order matching hand order so left cards sit behind right
		# cards — otherwise a card returned from a slot (added last) would cover
		# the cards to its right.
		move_child(_cards[i], i)
		var deg   := start_deg + step_deg * float(i) if n > 1 else 0.0
		var rad   := deg_to_rad(deg - 90.0)
		var pos   := Vector2(ARC_CENTER_X, ARC_RADIUS) + Vector2(cos(rad), sin(rad)) * ARC_RADIUS
		pos.x -= CARD_W * 0.5
		_cards[i].pivot_offset = Vector2(CARD_W * 0.5, 0.0)
		if animate:
			_cards[i].tween_position(pos, 0.2)
			_cards[i].tween_rotation(deg, 0.2)
		else:
			_cards[i].position = pos
			_cards[i].rotation = deg_to_rad(deg)
