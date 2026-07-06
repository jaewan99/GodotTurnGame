## MovePicker
## Appears when the player drops the Move placeholder card onto a plan slot.
## Shows the five directional move cards in a strip along the bottom of the
## screen (only the bottom band is dimmed). Clicking one emits move_chosen;
## clicking anywhere else cancels.
class_name MovePicker
extends Control

signal move_chosen(card_data: CardData)

const CARD_SCENE        := preload("res://scenes/cards/card.tscn")
# Card at its native 2:3 ratio, sized to sit inside the 30% bottom band with
# clear margin above and below.
const PICKER_CARD_SIZE  := Vector2(162, 243)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	# Invisible full-screen catcher: click anywhere outside the cards to cancel.
	var catcher := Control.new()
	catcher.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	catcher.mouse_filter = Control.MOUSE_FILTER_STOP
	catcher.gui_input.connect(_on_bg_input)
	add_child(catcher)

	# Dim only the bottom ~30% of the screen where the cards sit.
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.72)
	dim.anchor_left = 0.0
	dim.anchor_right = 1.0
	dim.anchor_top = 0.7
	dim.anchor_bottom = 1.0
	dim.offset_left = 0.0
	dim.offset_right = 0.0
	dim.offset_top = 0.0
	dim.offset_bottom = 0.0
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(_on_bg_input)
	add_child(dim)

	# Card row, centered horizontally along the bottom with padding.
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 28)
	row.anchor_left = 0.5
	row.anchor_right = 0.5
	row.anchor_top = 1.0
	row.anchor_bottom = 1.0
	row.grow_horizontal = Control.GROW_DIRECTION_BOTH
	row.grow_vertical = Control.GROW_DIRECTION_BEGIN
	row.offset_bottom = -40.0   # centers the cards in the band (margin top & bottom)
	add_child(row)

	for id in MovePool.MOVE_IDS:
		var card: GameCard = CARD_SCENE.instantiate()
		card.consumable  = false
		card.data        = CardData.by_id(id)
		card.card_size   = PICKER_CARD_SIZE
		card.undraggable = true
		card.card_clicked.connect(_on_card_clicked)
		row.add_child(card)


func _on_bg_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed:
		hide()


func _on_card_clicked(card: Card) -> void:
	hide()
	move_chosen.emit((card as GameCard).data)
