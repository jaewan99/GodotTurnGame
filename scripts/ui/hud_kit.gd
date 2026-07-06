## HudKit
## Shared HUD building blocks used by both the map and battlefield scenes:
## the translucent panel style, icon-tinted HUD buttons, the procedural
## sumi-e ink background material, and the player stat-sheet overlay.
class_name HudKit
extends RefCounted

const HUD_ICON_DIR := "res://assets/ui/hud/"
const TOKEN_SCENE := preload("res://scenes/map/token.tscn")


## Translucent dark panel style shared by HUD elements (borderless).
static func style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.03, 0.04, 0.06, 0.72)
	s.set_corner_radius_all(8)
	s.content_margin_left = 14.0
	s.content_margin_right = 14.0
	s.content_margin_top = 7.0
	s.content_margin_bottom = 7.0
	return s


## HUD icon texture by name (assets/ui/hud/<name>.png), or null when missing.
static func icon(icon_name: String) -> Texture2D:
	var path := "%s%s.png" % [HUD_ICON_DIR, icon_name]
	if ResourceLoader.exists(path):
		return load(path)
	return null


## Recolors a silhouette icon to a flat tint, keeping its alpha shape.
## Needed because the source art is black — modulate can't brighten black.
static func tinted(tex: Texture2D, tint: Color) -> Texture2D:
	var img := tex.get_image()
	img.convert(Image.FORMAT_RGBA8)
	for y in img.get_height():
		for x in img.get_width():
			var a := img.get_pixel(x, y).a
			img.set_pixel(x, y, Color(tint.r, tint.g, tint.b, a))
	return ImageTexture.create_from_image(img)


static func button(label: String, icon_name: String = "",
		icon_tint: Color = Color.WHITE) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.add_theme_font_size_override("font_size", 26)
	var hover := style()
	hover.bg_color = Color(0.10, 0.11, 0.15, 0.85)
	btn.add_theme_stylebox_override("normal", style())
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", hover)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	if icon_name != "":
		var tex := icon(icon_name)
		if tex != null:
			btn.icon = tinted(tex, icon_tint)
			btn.expand_icon = true
			btn.add_theme_constant_override("icon_max_width", 30)
			for state in ["icon_normal_color", "icon_hover_color",
					"icon_pressed_color", "icon_focus_color"]:
				btn.add_theme_color_override(state, Color.WHITE)
	return btn


## Coins + floor panel matching the map's top-left HUD. The coins Label is
## named "CoinsLabel" (shows just the number when a coin icon exists, else
## "Coins: N") so callers can find it for live updates. Returns the panel.
static func coins_floor_panel() -> PanelContainer:
	var gs := (Engine.get_main_loop() as SceneTree).root.get_node("/root/GameState")

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", style())

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	panel.add_child(hbox)

	var prefix := "Coins: "
	var coin_tex := icon("coin")
	if coin_tex != null:
		var coin_icon := TextureRect.new()
		coin_icon.texture = tinted(coin_tex, Color(1.0, 0.85, 0.25))
		coin_icon.custom_minimum_size = Vector2(33, 33)
		coin_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		coin_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		hbox.add_child(coin_icon)
		prefix = ""

	var coins_label := Label.new()
	coins_label.name = "CoinsLabel"
	coins_label.add_theme_font_size_override("font_size", 30)
	coins_label.modulate = Color(1.0, 0.85, 0.25)
	coins_label.text = prefix + str(gs.coins)
	hbox.add_child(coins_label)

	var sep := Label.new()
	sep.text = "|"
	sep.add_theme_font_size_override("font_size", 27)
	sep.modulate = Color(1.0, 1.0, 1.0, 0.25)
	hbox.add_child(sep)

	var floor_lbl := Label.new()
	floor_lbl.text = "Floor %d" % gs.floor_num
	floor_lbl.add_theme_font_size_override("font_size", 30)
	floor_lbl.modulate = Color(0.85, 0.85, 0.90)
	hbox.add_child(floor_lbl)

	return panel


## Procedural sumi-e ink backdrop material (shader + simplex noise texture).
static func ink_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/map_ink_bg.gdshader")
	# Simplex-fbm noise for organic cloud shapes (value noise looks square).
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 5
	noise.frequency = 0.006
	var noise_tex := NoiseTexture2D.new()
	noise_tex.noise = noise
	noise_tex.seamless = true
	noise_tex.width = 512
	noise_tex.height = 512
	mat.set_shader_parameter("noise_tex", noise_tex)
	return mat


# ── Player stat sheet ─────────────────────────────────────────────────────────

## Full player stat sheet overlay: what the next battle will start with.
## Mirrors battlefield._apply_equipment (base token stats + gear − curses).
static func show_stats(parent: Node) -> void:
	var gs := parent.get_node("/root/GameState")

	var overlay := CanvasLayer.new()
	overlay.layer = 10
	parent.add_child(overlay)
	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 0.84)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(bg)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(root)

	# Base values from the Token scene defaults — battles start from these.
	var t := TOKEN_SCENE.instantiate() as Token
	var base_hp: int = t.max_hp
	var base_energy: int = t.max_energy
	var start_energy: int = t.start_energy
	var regen: int = t.energy_regen
	t.free()

	# Aggregate equipment exactly like battlefield._apply_equipment.
	var hp_bonus := 0
	var energy_bonus := 0
	var dmg := 0
	var crit := 0
	var block := 0
	for item in gs.equipment.values():
		var ed := item as EquipmentData
		if ed == null:
			continue
		hp_bonus     += ed.max_hp_bonus
		energy_bonus += ed.max_energy_bonus
		dmg          += ed.damage_bonus
		crit         += ed.crit_chance
		block        += ed.block_per_turn

	var curse: int = gs.max_hp_curse
	var max_hp := maxi(5, base_hp - curse) + hp_bonus

	var vbox := EventTemplates.result_flash(root, 300.0)

	var title := Label.new()
	title.text = "Stats"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	title.modulate = Color(0.55, 0.85, 0.75)
	vbox.add_child(title)

	var hp_detail := "%d base" % base_hp
	if hp_bonus > 0:
		hp_detail += "  +%d gear" % hp_bonus
	if curse > 0:
		hp_detail += "  −%d curse" % curse
	_row(vbox, "Max HP", "%d   (%s)" % [max_hp, hp_detail], Color(0.45, 0.95, 0.55))
	_row(vbox, "Block per round", "+%d" % block, Color(0.55, 0.78, 1.0))
	_row(vbox, "Attack damage bonus", "+%d" % dmg, Color(1.0, 0.55, 0.45))
	_row(vbox, "Crit chance", "%d%%" % crit, Color(1.0, 0.9, 0.4))
	_row(vbox, "Max energy", "%d   (%d base%s)" % [base_energy + energy_bonus,
			base_energy, "  +%d gear" % energy_bonus if energy_bonus > 0 else ""],
			Color(0.5, 0.7, 1.0))
	_row(vbox, "Battle start energy", "%d,  +%d regen each round" % [
			start_energy + energy_bonus, regen])
	if curse > 0:
		_row(vbox, "Active curse", "−%d max HP for this run" % curse,
				Color(1.0, 0.42, 0.38))

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 10)
	vbox.add_child(spacer)

	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.add_theme_font_size_override("font_size", 20)
	close_btn.custom_minimum_size = Vector2(0, 48)
	close_btn.pressed.connect(func(): overlay.queue_free())
	vbox.add_child(close_btn)


static func _row(vbox: VBoxContainer, label_text: String, value_text: String,
		value_col: Color = Color(0.92, 0.92, 0.95)) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	vbox.add_child(row)
	var l := Label.new()
	l.text = label_text
	l.add_theme_font_size_override("font_size", 18)
	l.modulate = Color(0.62, 0.62, 0.68)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var v := Label.new()
	v.text = value_text
	v.add_theme_font_size_override("font_size", 18)
	v.modulate = value_col
	row.add_child(v)
