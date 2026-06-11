## PlanCard
## The card shown during the RESOLVE phase for each plan slot.
## Starts face-down (Back visible). Call flip() to animate the reveal.
class_name PlanCard
extends Control

const CARD_SCENE := preload("res://scenes/cards/card.tscn")

@onready var _back  : Control = $Back
@onready var _front : Control = $Front

var _card: GameCard


func _ready() -> void:
	pivot_offset = size / 2.0


## Call once after instantiating to bind the CardData.
## Pass null to show an empty-slot indicator on the front.
func setup(cd: CardData) -> void:
	pivot_offset = size / 2.0
	if cd == null:
		# Empty slot — just show a dim dash label on the front.
		var lbl := Label.new()
		lbl.text = "—"
		lbl.modulate = Color(0.45, 0.45, 0.45)
		lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
		_front.add_child(lbl)
		return
	# Build the real GameCard inside the Front container.
	_card = CARD_SCENE.instantiate()
	_card.consumable    = false
	_card.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	_card.data          = cd
	_card.card_size     = size
	_front.add_child(_card)
	_card.set_anchors_preset(Control.PRESET_FULL_RECT)


## Squish on X, swap sides, un-squish.
func flip() -> void:
	if _back == null or not _back.visible:
		return
	var tw := create_tween().set_trans(Tween.TRANS_SINE)
	tw.tween_property(self, "scale:x", 0.0, 0.15).set_ease(Tween.EASE_IN)
	tw.tween_callback(func(): _back.hide(); _front.show())
	tw.tween_property(self, "scale:x", 1.0, 0.15).set_ease(Tween.EASE_OUT)
