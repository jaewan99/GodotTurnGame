## PlanCard
## The card shown during the RESOLVE phase for each plan slot.
## Starts face-down (Back visible). Call flip() to animate the reveal.
class_name PlanCard
extends Control

const CARD_SCENE := preload("res://scenes/cards/card.tscn")
const NATIVE_CARD := Vector2(200.0, 300.0)   # card's undistorted design size

@onready var _back  : Control = $Back
@onready var _front : Control = $Front

var _card: GameCard


func _ready() -> void:
	pivot_offset = size / 2.0
	# Children ignore the mouse so the PlanCard root receives hover events.
	_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_front.mouse_filter = Control.MOUSE_FILTER_IGNORE


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
	# Build the real GameCard at its native size inside a wrapper scaled to fit
	# — same trick as the plan slots, so it fills the card with no distortion.
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.scale = size / NATIVE_CARD
	_front.add_child(holder)

	_card = CARD_SCENE.instantiate()
	_card.consumable    = false
	_card.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	_card.focus_mode    = Control.FOCUS_NONE
	_card.data          = cd
	holder.add_child(_card)
	_card.card_size     = NATIVE_CARD
	_card.set_anchors_preset(Control.PRESET_TOP_LEFT, false)
	_card.position      = Vector2.ZERO
	_card.scale         = Vector2.ONE


## Squish on X, swap sides, un-squish.
func flip() -> void:
	if _back == null or not _back.visible:
		return
	var tw := create_tween().set_trans(Tween.TRANS_SINE)
	tw.tween_property(self, "scale:x", 0.0, 0.15).set_ease(Tween.EASE_IN)
	tw.tween_callback(func(): _back.hide(); _front.show())
	tw.tween_property(self, "scale:x", 1.0, 0.15).set_ease(Tween.EASE_OUT)
