class_name CardViewer
extends Control

const CARD_SCENE := preload("res://scenes/cards/card.tscn")

@onready var _title: Label = $Panel/VBox/Header/TitleLabel
@onready var _sections: VBoxContainer = $Panel/VBox/Scroll/Margin/Sections
@onready var _close: Button = $Panel/VBox/Header/CloseButton


func _ready() -> void:
	visible = false
	_close.pressed.connect(hide)


## Show a list of cards, split into an "Action Cards" section and a
## "Move Cards" section separated by a dashed line.
func show_cards(title: String, cards: Array) -> void:
	_title.text = title
	for child in _sections.get_children():
		child.queue_free()

	var actions: Array = []
	var moves: Array = []
	for data in cards:
		if data == null:
			continue
		if data.type == CardData.CardType.MOVE:
			moves.append(data)
		else:
			actions.append(data)

	_add_section("Action Cards", actions)
	if not moves.is_empty():
		_sections.add_child(_dashed_line())
		_add_section("Move Cards", moves)
	show()


## A titled row of cards. Skipped entirely when the list is empty.
func _add_section(label: String, cards: Array) -> void:
	if cards.is_empty():
		return
	var header := Label.new()
	header.text = "%s  (%d)" % [label, cards.size()]
	header.add_theme_font_size_override("font_size", 16)
	header.modulate = Color(0.80, 0.82, 0.92)
	_sections.add_child(header)

	var flow := HFlowContainer.new()
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flow.add_theme_constant_override("h_separation", 12)
	flow.add_theme_constant_override("v_separation", 12)
	_sections.add_child(flow)

	for data in cards:
		var card: GameCard = CARD_SCENE.instantiate()
		card.data = data  # set before add_child so Card._ready() picks up the layout name
		card.undraggable = true
		flow.add_child(card)
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE


## A thin dashed horizontal rule used to divide the two sections.
func _dashed_line() -> Control:
	var line := Control.new()
	line.custom_minimum_size = Vector2(0, 12)
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.draw.connect(func() -> void:
		var y := line.size.y * 0.5
		var x := 0.0
		while x < line.size.x:
			line.draw_line(Vector2(x, y), Vector2(x + 12.0, y), Color(0.55, 0.58, 0.66, 0.7), 2.0)
			x += 22.0
	)
	line.resized.connect(line.queue_redraw)
	return line


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		hide()
		get_viewport().set_input_as_handled()
