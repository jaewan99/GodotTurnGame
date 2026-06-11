## MapNodeUI
## A circular Button representing one node on the map.
## Three visual states driven by refresh():
##   visited   — green tint, disabled (already explored)
##   reachable — full colour, clickable
##   locked    — dark/dim, disabled (not connected to any visited node)
class_name MapNodeUI
extends Button

const RADIUS := 30.0

var data: MapNode
signal node_clicked(node: MapNode)


func setup(map_node: MapNode) -> void:
	data = map_node

	var sz := Vector2(RADIUS * 2.0, RADIUS * 2.0)
	custom_minimum_size = sz
	size                = sz
	pivot_offset        = sz / 2.0
	position            = map_node.pos - sz / 2.0

	text = _label(map_node.type)
	add_theme_font_size_override("font_size", 10)
	for state_name in ["font_color", "font_hover_color",
			"font_pressed_color", "font_focus_color", "font_disabled_color"]:
		add_theme_color_override(state_name, Color.WHITE)

	_apply_round_style(_color(map_node.type))

	pressed.connect(func(): node_clicked.emit(data))

	if map_node.type == MapNode.Type.BOSS:
		var bigger := Vector2(RADIUS * 2.6, RADIUS * 2.6)
		custom_minimum_size = bigger
		size                = bigger
		pivot_offset        = bigger / 2.0
		position            = map_node.pos - bigger / 2.0
		add_theme_font_size_override("font_size", 12)

	refresh(false)


func refresh(reachable: bool) -> void:
	if data.visited:
		modulate = Color(0.55, 1.0, 0.55)
		disabled  = true
	elif reachable:
		modulate = Color.WHITE
		disabled  = false
	else:
		modulate = Color(0.22, 0.22, 0.22, 0.75)
		disabled  = true


func _apply_round_style(base: Color) -> void:
	var r := int(RADIUS)
	for pair in [
		["normal",   base],
		["hover",    base.lightened(0.25)],
		["pressed",  base.darkened(0.25)],
		["disabled", base.darkened(0.40)],
		["focus",    base.lightened(0.15)],
	]:
		var s := StyleBoxFlat.new()
		s.corner_radius_top_left     = r
		s.corner_radius_top_right    = r
		s.corner_radius_bottom_left  = r
		s.corner_radius_bottom_right = r
		s.bg_color       = pair[1] as Color
		s.border_width_top    = 2
		s.border_width_right  = 2
		s.border_width_bottom = 2
		s.border_width_left   = 2
		s.border_color   = Color(1, 1, 1, 0.25)
		add_theme_stylebox_override(pair[0], s)


static func _color(type: MapNode.Type) -> Color:
	match type:
		MapNode.Type.START: return Color("3d9e40")
		MapNode.Type.FIGHT: return Color("c94040")
		MapNode.Type.ELITE: return Color("7b1fa2")
		MapNode.Type.SHOP:  return Color("c9a020")
		MapNode.Type.REST:  return Color("2e7d82")
		MapNode.Type.EVENT: return Color("6a1b9a")
		MapNode.Type.BOSS:  return Color("b71c1c")
	return Color.GRAY


static func _label(type: MapNode.Type) -> String:
	match type:
		MapNode.Type.START: return "Start"
		MapNode.Type.FIGHT: return "Fight"
		MapNode.Type.ELITE: return "Elite"
		MapNode.Type.SHOP:  return "Shop"
		MapNode.Type.REST:  return "Wizard"
		MapNode.Type.EVENT: return "Event"
		MapNode.Type.BOSS:  return "BOSS"
	return "?"
