## MovePicker
## Fullscreen modal that appears when the player drops the Move placeholder card
## onto a plan slot. Shows the five directional move cards; clicking one emits
## move_chosen so the battlefield can place it. Clicking the backdrop cancels.
class_name MovePicker
extends Control

signal move_chosen(card_data: CardData)

const CARD_SCENE        := preload("res://scenes/cards/card.tscn")
const PICKER_CARD_SIZE  := Vector2(130, 185)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 0.65)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	bg.gui_input.connect(_on_bg_input)
	add_child(bg)

	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left   = -390.0
	panel.offset_right  =  390.0
	panel.offset_top    = -115.0
	panel.offset_bottom =  115.0
	add_child(panel)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)

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
