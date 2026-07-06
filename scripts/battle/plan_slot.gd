## PlanSlot
## One of the 3 ordered action slots. Renders as a plain rounded frame that
## brightens when it's the next droppable slot and glows gold when a card is
## dragged over it. Click the slot to clear it (emits `cleared`).
@tool
class_name PlanSlot
extends Panel

signal dropped(index: int, payload: Dictionary)
signal cleared(index: int)

@export var index: int = 0

var _droppable: bool = true
var _card_dragging: bool = false
var _filled: bool = false
var _glow: bool = false
# Snapshot of "was this the next-free slot when the drag began". Frozen at
# drag-start so that mounting a card in an earlier slot (which flips this slot
# to droppable mid-emission) can't make this slot grab the same card too.
var _accepts_this_drag: bool = false


func _ready() -> void:
	_refresh_style()
	if Engine.is_editor_hint():
		return
	CG.holding_card.connect(_on_holding_card)


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	var want := _card_dragging and not _filled and _droppable
	if want != _glow:
		_glow = want
		_refresh_style()


func show_placeholder(empty: bool) -> void:
	_filled = not empty
	if not empty:
		_glow = false
	_refresh_style()


func set_droppable(on: bool) -> void:
	if on == _droppable:
		return
	_droppable = on
	_refresh_style()


## Rebuild the slot's frame to match its current state.
func _refresh_style() -> void:
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(12)
	if _filled:
		# A card fills the slot and covers the frame entirely.
		sb.bg_color = Color(0, 0, 0, 0)
		sb.border_color = Color(0, 0, 0, 0)
	elif _glow:
		sb.bg_color = Color(0.95, 0.80, 0.30, 0.18)
		sb.border_color = Color(1.0, 0.86, 0.38, 0.95)
		sb.set_border_width_all(3)
	elif _droppable:
		# The next slot to fill: brighter, inviting.
		sb.bg_color = Color(0.14, 0.16, 0.20, 0.55)
		sb.border_color = Color(0.62, 0.70, 0.85, 0.90)
		sb.set_border_width_all(2)
	else:
		# A later slot, not yet fillable.
		sb.bg_color = Color(0.09, 0.10, 0.13, 0.45)
		sb.border_color = Color(0.32, 0.36, 0.44, 0.70)
		sb.set_border_width_all(2)
	add_theme_stylebox_override("panel", sb)


func _on_holding_card(card: Card) -> void:
	var game_card := card as GameCard
	if game_card == null:
		return
	_card_dragging = true
	_accepts_this_drag = _droppable and not _filled
	game_card.drag_ended.connect(_on_drag_ended, CONNECT_ONE_SHOT)


func _on_drag_ended(card: GameCard) -> void:
	_card_dragging = false
	_glow = false
	_refresh_style()
	var accepts := _accepts_this_drag
	_accepts_this_drag = false
	if not accepts:
		return
	if Rect2(global_position, size).has_point(get_global_mouse_position()):
		dropped.emit(index, {"data": card.data, "consumable": card.consumable, "card": card})


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton \
			and event.button_index == MOUSE_BUTTON_LEFT \
			and event.pressed:
		cleared.emit(index)
