## PlanSlot
## One of the 3 ordered action slots. Shows icon_three_card.png as a dimmed
## placeholder when empty. Glows when a card is dragged over it.
## Click the slot to clear it (emits `cleared`).
@tool
class_name PlanSlot
extends Panel

signal dropped(index: int, payload: Dictionary)
signal cleared(index: int)

@export var index: int = 0

var _droppable: bool = true
var _card_dragging: bool = false
var _filled: bool = false

@onready var _bg: TextureRect = $SlotBg


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	CG.holding_card.connect(_on_holding_card)
	_set_glow(false)


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if _card_dragging and not _filled and _droppable:
		_set_glow(true)


func show_placeholder(empty: bool) -> void:
	_filled = not empty
	_bg.visible = empty
	if empty:
		_set_glow(false)


func set_droppable(on: bool) -> void:
	_droppable = on
	var mat := _bg.material as ShaderMaterial
	if mat:
		mat.set_shader_parameter("droppable", on)


func _set_glow(on: bool) -> void:
	var mat := _bg.material as ShaderMaterial
	if mat:
		mat.set_shader_parameter("active", on)


func _on_holding_card(card: Card) -> void:
	var game_card := card as GameCard
	if game_card == null:
		return
	_card_dragging = true
	game_card.drag_ended.connect(_on_drag_ended, CONNECT_ONE_SHOT)


func _on_drag_ended(card: GameCard) -> void:
	_card_dragging = false
	_set_glow(false)
	if not _droppable:
		return
	if Rect2(global_position, size).has_point(get_global_mouse_position()):
		dropped.emit(index, {"data": card.data, "consumable": card.consumable, "card": card})


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton \
			and event.button_index == MOUSE_BUTTON_LEFT \
			and event.pressed:
		cleared.emit(index)
