@tool
class_name GameCardLayout
extends CardLayout

const SHINE_SHADER := preload("res://shaders/card_shine.gdshader")

@onready var _name_label: Label = $SubViewport/NameLabel
@onready var _cost_label: Label = $SubViewport/CostLabel
@onready var _description_label: Label = $SubViewport/DescriptionLabel
@onready var _art: TextureRect = $SubViewport/Art
@onready var _shine: ColorRect = $SubViewport/Shine


func _layout_ready() -> void:
	super()
	if not Engine.is_editor_hint():
		var mat := ShaderMaterial.new()
		mat.shader = SHINE_SHADER
		mat.set_shader_parameter("shine_pos", Vector2(0.5, -1.0))
		_shine.material = mat


func _update_display() -> void:
	super()
	if not is_node_ready():
		return
	var data := card_resource as CardData
	if data == null:
		return
	if _name_label:
		_name_label.text = data.card_name
	if _cost_label:
		_cost_label.text = str(data.cost)
	if _description_label:
		_description_label.text = data.description
	if _art:
		_art.texture = data.art


func set_shine_pos(uv: Vector2) -> void:
	if _shine and _shine.material:
		_shine.material.set_shader_parameter("shine_pos", uv)
