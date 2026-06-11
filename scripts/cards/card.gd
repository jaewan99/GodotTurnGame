## GameCard
## Visual card node. Extends simple_cards' Card (Button) for smooth drag behaviour,
## but uses direct scene children for visuals instead of the SubViewport layout system.
class_name GameCard
extends Card

const ENERGY_HUD_GROUP := "player_energy_hud"
const SHINE_SHADER     := preload("res://shaders/card_shine.gdshader")
const DEFAULT_PORTRAIT := preload("res://assets/cards/japan_warrior/portrait/slash1.png")

## Change this one value to resize the card — all children scale via anchors.
@export var card_size: Vector2 = Vector2(200, 300):
	set(v):
		card_size = v
		custom_minimum_size = v
		size = v
		pivot_offset = v / 2.0
		center_pos   = v / 2.0

var consumable: bool = true

var data: CardData:
	get: return card_data as CardData
	set(value):
		card_data = value
		if is_node_ready():
			_refresh()

@onready var _name_label: Label        = $NameIcon/NameLabel
@onready var _cost_label: Label        = $EnergyIcon/CostLabel
@onready var _description_label: Label = $DescIcon/DescriptionLabel
@onready var _art: TextureRect         = $Art
@onready var _shine: ColorRect         = $Shine


## Skip the SubViewport layout registry — visuals live in direct scene children.
func _setup_layout(_no_anim: bool = false) -> void:
	pass


## Override to skip tween_rotation(0) after drag — hand._layout handles arc rotation.
func _on_button_up() -> void:
	_released = true
	if holding:
		holding = false
		set_process(false)
		CG.current_held_item = null
		drag_ended.emit(self)
		if not _is_owned():
			tween_scale()
		_on_mouse_exited()
		_on_focus_exited()
		if is_hovered():
			_on_mouse_entered()
		if has_focus():
			_on_focus_entered()
	else:
		card_clicked.emit(self)


func _card_ready() -> void:
	flat = true
	self_modulate.a = 1
	card_size = card_size
	var mat := ShaderMaterial.new()
	mat.shader = SHINE_SHADER
	mat.set_shader_parameter("shine_pos", Vector2(0.5, -1.0))
	_shine.material = mat
	_refresh()
	card_focused.connect(_on_game_focused)
	card_unfocused.connect(_on_game_unfocused)


func _process(delta: float) -> void:
	super(delta)
	if not focused:
		return
	var uv := (get_local_mouse_position() / size).clamp(Vector2.ZERO, Vector2.ONE)
	if _shine and _shine.material:
		_shine.material.set_shader_parameter("shine_pos", uv)
	var tilt := (uv - Vector2(0.5, 0.5)) * 2.0
	scale = Vector2(1.0 - absf(tilt.x) * 0.03, 1.0 - absf(tilt.y) * 0.02)


func _on_game_focused() -> void:
	modulate = Color(1.15, 1.15, 1.15)
	_send_energy_preview(_energy_delta())
	_send_range_preview(data)


func _on_game_unfocused() -> void:
	modulate = Color.WHITE
	scale = Vector2.ONE
	if _shine and _shine.material:
		_shine.material.set_shader_parameter("shine_pos", Vector2(0.5, -1.0))
	_send_energy_preview(0)
	_send_range_preview(null)


func _refresh() -> void:
	if data == null:
		return
	if _name_label:
		_name_label.text = data.card_name
	if _cost_label:
		_cost_label.text = str(data.cost)
	if _description_label:
		_description_label.text = data.description
	if _art:
		_art.texture = data.art if data.art else DEFAULT_PORTRAIT


# ── Range highlight — shown on the battlefield board, not on the card ──────

func _send_range_preview(cd: CardData) -> void:
	var bf := get_tree().get_first_node_in_group("battlefield")
	if bf == null:
		return
	if cd != null and not cd.affected_cells.is_empty():
		bf.show_range_highlight(cd)
	else:
		bf.clear_range_highlight()


# ── Energy preview ─────────────────────────────────────────────────────────

func _energy_delta() -> int:
	if data == null or data.type == CardData.CardType.MOVE:
		return 0
	return data.energy_gain - data.cost


func _send_energy_preview(delta: int) -> void:
	var hud := get_tree().get_first_node_in_group(ENERGY_HUD_GROUP)
	if hud != null and hud.has_method("set_energy_preview"):
		hud.set_energy_preview(delta)
