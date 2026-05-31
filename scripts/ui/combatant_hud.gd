## CombatantHUD
## A Tekken-style status panel for one combatant: name + HP bar + energy bar.
## It binds to a Token and updates itself whenever that token's stats change
## (via the token's `hp_changed` / `energy_changed` signals).
##
## Set `mirrored = true` for the right-side (enemy) panel: the name right-aligns
## and the bars drain toward the center, like a fighting game.
extends Control

@export var mirrored: bool = false

# Cached values we draw from (kept in sync via the token's signals).
var _name: String = "?"
var _hp: int = 0
var _max_hp: int = 1
var _energy: int = 0
var _max_energy: int = 1
var _preview_delta: int = 0   # hovered card's energy change (preview overlay)

@onready var _name_label: Label = $NameLabel
@onready var _hp_label: Label = $HPLabel
@onready var _energy_label: Label = $EnergyLabel

const HP_FILL := Color(0.20, 0.85, 0.30)
const HP_BACK := Color(0.10, 0.10, 0.10, 0.85)
const EN_FILL := Color(0.30, 0.60, 1.00)
const EN_BACK := Color(0.10, 0.10, 0.10, 0.85)
const BORDER := Color(0, 0, 0, 0.9)


func _ready() -> void:
	# Name on the combatant's side, HP number on the opposite end of the row.
	var side := HORIZONTAL_ALIGNMENT_RIGHT if mirrored else HORIZONTAL_ALIGNMENT_LEFT
	var opposite := HORIZONTAL_ALIGNMENT_LEFT if mirrored else HORIZONTAL_ALIGNMENT_RIGHT
	_name_label.horizontal_alignment = side
	_hp_label.horizontal_alignment = opposite
	_energy_label.horizontal_alignment = side
	_redraw_labels()


## Connect this HUD to a token and seed the current values.
func bind(token: Token) -> void:
	_name = token.display_name
	_hp = token.hp
	_max_hp = token.max_hp
	_energy = token.energy
	_max_energy = token.max_energy
	token.hp_changed.connect(_on_hp_changed)
	token.energy_changed.connect(_on_energy_changed)
	_redraw_labels()
	queue_redraw()


func _on_hp_changed(hp: int, max_hp: int) -> void:
	_hp = hp
	_max_hp = max_hp
	_redraw_labels()
	queue_redraw()


func _on_energy_changed(energy: int, max_energy: int) -> void:
	_energy = energy
	_max_energy = max_energy
	_redraw_labels()
	queue_redraw()


## Preview a pending energy change on the bar (called by Card on hover).
## Negative = will be spent (red), positive = will be gained (green), 0 = none.
func set_energy_preview(delta: int) -> void:
	_preview_delta = delta
	queue_redraw()


func _redraw_labels() -> void:
	if not is_node_ready():
		return
	_name_label.text = _name
	_hp_label.text = "%d / %d" % [_hp, _max_hp]
	_energy_label.text = "%d / %d" % [_energy, _max_energy]


func _draw() -> void:
	var pad := 10.0
	var w := size.x - pad * 2.0
	var hp_rect := Rect2(pad, 34.0, w, 20.0)
	var en_rect := Rect2(pad, 56.0, w, 14.0)
	_draw_bar(hp_rect, float(_hp) / float(maxi(_max_hp, 1)), HP_FILL, HP_BACK)
	_draw_bar(en_rect, float(_energy) / float(maxi(_max_energy, 1)), EN_FILL, EN_BACK)
	_draw_energy_preview(en_rect)


## Overlay showing the hovered card's effect: red chunk = energy to be spent
## (rightmost of the current fill), green chunk = energy to be gained (beyond it).
func _draw_energy_preview(rect: Rect2) -> void:
	if _preview_delta == 0 or _max_energy <= 0:
		return
	var unit := rect.size.x / float(_max_energy)
	if _preview_delta < 0:
		var consumed := mini(-_preview_delta, _energy)
		var x0 := rect.position.x + float(_energy - consumed) * unit
		draw_rect(Rect2(Vector2(x0, rect.position.y), Vector2(consumed * unit, rect.size.y)),
			Color(1.0, 0.3, 0.3, 0.85), true)
	else:
		var added := mini(_preview_delta, _max_energy - _energy)
		var x0 := rect.position.x + float(_energy) * unit
		draw_rect(Rect2(Vector2(x0, rect.position.y), Vector2(added * unit, rect.size.y)),
			Color(0.4, 1.0, 0.5, 0.8), true)


func _draw_bar(rect: Rect2, ratio: float, fill: Color, back: Color) -> void:
	ratio = clampf(ratio, 0.0, 1.0)
	draw_rect(rect, back, true)
	if ratio > 0.0:
		var fill_w := rect.size.x * ratio
		var fill_rect := Rect2(rect.position, Vector2(fill_w, rect.size.y))
		if mirrored:
			# Drain toward the center: keep the fill anchored to the right edge.
			fill_rect.position.x = rect.position.x + rect.size.x - fill_w
		draw_rect(fill_rect, fill, true)
	draw_rect(rect, BORDER, false, 2.0)
