## MapNodeUI
## An icon-only Button representing one node on the map.
## Three visual states driven by refresh():
##   visited   — green tint, disabled (already explored)
##   reachable — full white, clickable
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

	_apply_flat_style()

	var icon_path := _icon_path(map_node.type)
	if ResourceLoader.exists(icon_path):
		icon = load(icon_path)
		icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
		expand_icon = true
		add_theme_constant_override("icon_max_width", int(RADIUS * 1.6))
		add_theme_color_override("icon_normal_color",   Color.WHITE)
		add_theme_color_override("icon_hover_color",    Color(0.55, 0.55, 0.55))
		add_theme_color_override("icon_pressed_color",  Color(0.35, 0.35, 0.35))
		add_theme_color_override("icon_disabled_color", Color(0.30, 0.30, 0.30))
		text = ""
	else:
		text = _label(map_node.type)
		add_theme_font_size_override("font_size", 10)
		for state_name in ["font_color", "font_hover_color",
				"font_pressed_color", "font_focus_color", "font_disabled_color"]:
			add_theme_color_override(state_name, Color.WHITE)

	pressed.connect(func(): node_clicked.emit(data))

	if map_node.type == MapNode.Type.BOSS:
		var bigger := Vector2(RADIUS * 2.6, RADIUS * 2.6)
		custom_minimum_size = bigger
		size                = bigger
		pivot_offset        = bigger / 2.0
		position            = map_node.pos - bigger / 2.0

	refresh(false)


func refresh(reachable: bool) -> void:
	if data.visited and data.always_accessible:
		# Visited but still open for re-entry (shop / enchant before used)
		modulate = Color(0.60, 0.85, 1.0)
		disabled  = false
	elif data.visited:
		modulate = Color(0.55, 1.0, 0.55)
		disabled  = true
	elif reachable:
		modulate = Color.WHITE
		disabled  = false
	else:
		modulate = Color(0.22, 0.22, 0.22, 0.75)
		disabled  = true


func _apply_flat_style() -> void:
	var empty := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		add_theme_stylebox_override(state, empty)


static func _color(type: MapNode.Type) -> Color:
	match type:
		MapNode.Type.START: return Color("3d9e40")
		MapNode.Type.FIGHT: return Color("c94040")
		MapNode.Type.ELITE: return Color("7b1fa2")
		MapNode.Type.SHOP:  return Color("c9a020")
		MapNode.Type.REST:  return Color("2e7d82")
		MapNode.Type.EVENT: return Color("6a1b9a")
		MapNode.Type.BOSS:     return Color("b71c1c")
		MapNode.Type.ENCHANT:  return Color("1565c0")
		MapNode.Type.FORGE:    return Color("bf5f1f")
		MapNode.Type.MYSTERY:  return Color("546e7a")
		MapNode.Type.GAMBLE:   return Color("ad1457")
		MapNode.Type.TREASURE: return Color("e6b422")
		MapNode.Type.SHRINE:   return Color("4a148c")
		MapNode.Type.DOJO:     return Color("33691e")
		MapNode.Type.BOUNTY:   return Color("a0522d")
		MapNode.Type.SECRET:   return Color("00897b")
	return Color.GRAY


static func _icon_path(type: MapNode.Type) -> String:
	const BASE := "res://assets/map/nodes/"
	match type:
		MapNode.Type.START:    return BASE + "start.png"
		MapNode.Type.FIGHT:    return BASE + "fight.png"
		MapNode.Type.ELITE:    return BASE + "elite.png"
		MapNode.Type.SHOP:     return BASE + "shop.png"
		MapNode.Type.REST:     return BASE + "rest.png"
		MapNode.Type.EVENT:    return BASE + "event.png"
		MapNode.Type.BOSS:     return BASE + "boss.png"
		MapNode.Type.ENCHANT:  return BASE + "enchant.png"
		MapNode.Type.FORGE:    return BASE + "forge.png"
		MapNode.Type.MYSTERY:  return BASE + "mystery.png"
		MapNode.Type.GAMBLE:   return BASE + "gamble.png"
		MapNode.Type.TREASURE: return BASE + "treasure.png"
		MapNode.Type.SHRINE:   return BASE + "shrine.png"
		MapNode.Type.DOJO:     return BASE + "dojo.png"
		MapNode.Type.BOUNTY:   return BASE + "bounty.png"
		MapNode.Type.SECRET:   return BASE + "secret.png"
	return ""


static func _label(type: MapNode.Type) -> String:
	match type:
		MapNode.Type.START: return "Start"
		MapNode.Type.FIGHT: return "Fight"
		MapNode.Type.ELITE: return "Elite"
		MapNode.Type.SHOP:  return "Shop"
		MapNode.Type.REST:  return "Wizard"
		MapNode.Type.EVENT: return "Event"
		MapNode.Type.BOSS:     return "BOSS"
		MapNode.Type.ENCHANT:  return "Enchant"
		MapNode.Type.FORGE:    return "Forge"
		MapNode.Type.MYSTERY:  return "?"
		MapNode.Type.GAMBLE:   return "Gamble"
		MapNode.Type.TREASURE: return "Chest"
		MapNode.Type.SHRINE:   return "Shrine"
		MapNode.Type.DOJO:     return "Dojo"
		MapNode.Type.BOUNTY:   return "Bounty"
		MapNode.Type.SECRET:   return "Secret"
	return "?"
