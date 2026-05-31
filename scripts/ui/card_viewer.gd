class_name CardViewer
extends Control

const CARD_SCENE := preload("res://scenes/cards/card.tscn")

@onready var _title: Label = $Panel/VBox/Header/TitleLabel
@onready var _grid: HFlowContainer = $Panel/VBox/Scroll/Grid
@onready var _close: Button = $Panel/VBox/Header/CloseButton


func _ready() -> void:
	visible = false
	_close.pressed.connect(hide)


func show_cards(title: String, cards: Array) -> void:
	_title.text = title
	for child in _grid.get_children():
		child.queue_free()
	for data in cards:
		if data == null:
			continue
		var card: GameCard = CARD_SCENE.instantiate()
		card.data = data  # set before add_child so Card._ready() picks up the layout name
		card.undraggable = true
		_grid.add_child(card)
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	show()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		hide()
		get_viewport().set_input_as_handled()
