## GameButton
## Icon button with a styled rounded background, hover scale, and press feedback.
## Drop this script on any Button node — it builds and animates its own style.
class_name GameButton
extends Button

const _HOVER_SCALE  := Vector2(1.12, 1.12)
const _NORMAL_SCALE := Vector2(1.0,  1.0)
const _PRESS_SCALE  := Vector2(0.93, 0.93)
const _TWEEN_SPEED  := 0.10


func _ready() -> void:
	flat         = true
	expand_icon  = true
	pivot_offset = custom_minimum_size / 2.0

	mouse_entered.connect(_on_hover_in)
	mouse_exited.connect(_on_hover_out)
	button_down.connect(_on_press)
	button_up.connect(_on_release)


func _on_hover_in() -> void:
	_tween_scale(_HOVER_SCALE)


func _on_hover_out() -> void:
	_tween_scale(_NORMAL_SCALE)


func _on_press() -> void:
	_tween_scale(_PRESS_SCALE)


func _on_release() -> void:
	_tween_scale(_HOVER_SCALE if is_hovered() else _NORMAL_SCALE)


func _tween_scale(target: Vector2) -> void:
	var tw := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "scale", target, _TWEEN_SPEED)
