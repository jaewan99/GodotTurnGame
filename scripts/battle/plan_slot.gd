## PlanSlot
## One of the 3 ordered action slots. Listens for simple_cards drag events:
## when a GameCard is released with the cursor over this slot, emits `dropped`.
## Click the slot to clear it (emits `cleared`).
class_name PlanSlot
extends Panel

signal dropped(index: int, payload: Dictionary)
signal cleared(index: int)

@export var index: int = 0

var _droppable: bool = true

@onready var _label: Label = $Label


func _ready() -> void:
	CG.holding_card.connect(_on_holding_card)


func show_placeholder(empty: bool) -> void:
	if _label != null:
		_label.visible = empty


func set_droppable(on: bool) -> void:
	_droppable = on


func _on_holding_card(card: Card) -> void:
	var game_card := card as GameCard
	if game_card == null:
		return
	game_card.drag_ended.connect(_on_drag_ended, CONNECT_ONE_SHOT)


func _on_drag_ended(card: GameCard) -> void:
	if not _droppable:
		return
	if Rect2(global_position, size).has_point(get_global_mouse_position()):
		dropped.emit(index, {"data": card.data, "consumable": card.consumable, "card": card})


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton \
			and event.button_index == MOUSE_BUTTON_LEFT \
			and event.pressed:
		cleared.emit(index)
