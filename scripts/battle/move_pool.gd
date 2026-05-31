## MovePool
## Four permanent directional cards pinned to fixed positions on the right side.
## Non-consumable: dropping one into a slot creates a duplicate; the original
## always snaps back to its home position after drag.
##
## Using a plain Control (not ScrollContainer) so:
##   • no clip rect — cards stay visible anywhere on screen during drag
##   • no scroll gesture interception — drag works on the first touch
class_name MovePool
extends Control

const CARD_SCENE := preload("res://scenes/cards/card.tscn")

const MOVE_IDS: Array[StringName] = [
	&"move_up", &"move_down", &"move_left", &"move_right", &"do_nothing",
]

const CARD_H    := 210.0
const CARD_STEP := 154.0   # (826 - 210) / 4 — exactly fits 5 cards in the pool panel

var _homes: Array[Vector2] = []


func _ready() -> void:
	for i in MOVE_IDS.size():
		var card: GameCard = CARD_SCENE.instantiate()
		card.consumable = false
		card.data = CardData.by_id(MOVE_IDS[i])
		add_child(card)
		var home := Vector2(0.0, CARD_STEP * i)
		card.position = home
		_homes.append(home)
		card.drag_started.connect(_on_card_drag_started)
		card.drag_ended.connect(_on_card_drag_ended)


func _on_card_drag_started(card: Card) -> void:
	# Absolute z so the dragged card renders over all other UI in the same CanvasLayer.
	card.z_as_relative = false
	card.z_index = 100


func _on_card_drag_ended(card: Card) -> void:
	var idx := card.get_index()
	card.z_as_relative = true
	card.z_index = 0
	card.rotation = 0.0
	card.scale    = Vector2.ONE
	if idx >= 0 and idx < _homes.size():
		card.position = _homes[idx]
