## Deck
## A draw pile + discard pile of CardData. Plain object (not a node) — the
## battle controller owns one and asks it to draw/discard.
##
## When the draw pile empties, the discard pile is reshuffled back in
## (Slay-the-Spire style), so you never run out of cards.
class_name Deck
extends RefCounted

var draw_pile: Array[CardData] = []
var discard_pile: Array[CardData] = []


func _init(cards: Array[CardData] = []) -> void:
	draw_pile = cards.duplicate()
	draw_pile.shuffle()


## Draw one card. Returns null only if both piles are empty.
func draw_one() -> CardData:
	if draw_pile.is_empty():
		_reshuffle_discard_into_draw()
	if draw_pile.is_empty():
		return null
	return draw_pile.pop_back()


func discard(card: CardData) -> void:
	if card != null:
		discard_pile.append(card)


func draw_count() -> int:
	return draw_pile.size()


func discard_count() -> int:
	return discard_pile.size()


func _reshuffle_discard_into_draw() -> void:
	draw_pile = discard_pile.duplicate()
	discard_pile.clear()
	draw_pile.shuffle()
