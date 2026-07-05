## EventTemplates
## Shared layout builders for every map-event overlay. Six formats:
##   A scroll_split    — art left, kakemono scroll panel right (narration events)
##   B dialogue_split  — portrait left, speech panel right (someone talks to you)
##   C choice_frame    — title/desc top, choices dealt as cards (choice_card)
##   D merchant_split  — emblem strip left, functional list panel right (shops)
##   E result_flash    — compact centered outcome panel
##   F poster          — parchment wanted-poster panel (bounty)
##
## Every builder returns the VBoxContainer the caller pours its content into.
## Art: drop PNGs into assets/events/ named after the art key (wizard.png,
## merchant.png, gambler.png, demon.png, master.png, shrine.png, mystery.png,
## event.png, forge.png, enchant.png, bounty.png…). Until art exists, the
## matching map-node icon is shown as a dim placeholder emblem.
class_name EventTemplates
extends RefCounted

const ART_DIR := "res://assets/events/"

# Panel rects, expressed as offsets from screen center (1920×1080 design).
const SPLIT_ART_OFFS := [-820.0, -350.0, -280.0, 350.0]      # 540×700 left panel
const SPLIT_PANEL_OFFS := [-220.0, -370.0, 820.0, 370.0]     # 1040×740 right panel
const MERCH_ART_OFFS := [-900.0, -370.0, -560.0, 370.0]      # 340×740 left strip
const MERCH_PANEL_OFFS := [-520.0, -430.0, 900.0, 430.0]     # 1420×860 right panel


## Event art by key (assets/events/<key>.png), or null when not added yet.
static func art(key: String) -> Texture2D:
	var path := "%s%s.png" % [ART_DIR, key]
	if ResourceLoader.exists(path):
		return load(path)
	return null


# ── A: scroll split ───────────────────────────────────────────────────────────

static func scroll_split(root: Control, art_key: String, fallback_icon: String = "") -> VBoxContainer:
	_art_panel(root, SPLIT_ART_OFFS, art_key, fallback_icon)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.115, 0.10, 0.072, 0.97)
	style.border_color = Color(0.34, 0.25, 0.13)
	style.border_width_top = 10
	style.border_width_bottom = 10
	style.border_width_left = 2
	style.border_width_right = 2
	style.set_corner_radius_all(6)
	var panel := _offset_panel(root, SPLIT_PANEL_OFFS, style)
	return _content_vbox(panel, 54.0, 40.0, true)


# ── B: dialogue split ─────────────────────────────────────────────────────────

static func dialogue_split(root: Control, art_key: String, speaker: String,
		accent: Color, fallback_icon: String = "") -> VBoxContainer:
	_art_panel(root, SPLIT_ART_OFFS, art_key, fallback_icon)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.04, 0.06, 0.85)
	style.set_corner_radius_all(12)
	var panel := _offset_panel(root, SPLIT_PANEL_OFFS, style)

	# Speaker nameplate pinned to the panel's top-left.
	var plate := Label.new()
	plate.text = speaker
	plate.add_theme_font_size_override("font_size", 34)
	plate.modulate = accent
	plate.position = Vector2(46.0, 26.0)
	panel.add_child(plate)

	var rule := ColorRect.new()
	rule.color = Color(accent.r, accent.g, accent.b, 0.35)
	rule.position = Vector2(46.0, 76.0)
	rule.size = Vector2(SPLIT_PANEL_OFFS[2] - SPLIT_PANEL_OFFS[0] - 92.0, 2.0)
	panel.add_child(rule)

	var vbox := _content_vbox(panel, 54.0, 46.0, true)
	vbox.offset_top = 96.0
	return vbox


# ── C: choice cards ───────────────────────────────────────────────────────────

## Title + description at the top; returns the HBox the choice cards go into.
static func choice_frame(root: Control, title: String, desc: String,
		accent: Color) -> HBoxContainer:
	var head := VBoxContainer.new()
	head.set_anchors_preset(Control.PRESET_CENTER)
	head.offset_left = -560.0; head.offset_right = 560.0
	head.offset_top = -390.0;  head.offset_bottom = -230.0
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_theme_constant_override("separation", 10)
	root.add_child(head)

	var title_lbl := Label.new()
	title_lbl.text = title
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 52)
	title_lbl.modulate = accent
	head.add_child(title_lbl)

	var desc_lbl := Label.new()
	desc_lbl.text = desc
	desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_lbl.add_theme_font_size_override("font_size", 19)
	desc_lbl.modulate = Color(0.78, 0.78, 0.78)
	head.add_child(desc_lbl)

	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_CENTER)
	row.offset_top = -160.0
	row.offset_bottom = 200.0
	row.grow_horizontal = Control.GROW_DIRECTION_BOTH
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 28)
	root.add_child(row)
	return row


## One choice, styled as a card. Wire `pressed` at the call site.
static func choice_card(title: String, sub: String, accent: Color,
		icon: Texture2D = null) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(240.0, 330.0)

	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var s := StyleBoxFlat.new()
		s.bg_color = Color(0.085, 0.085, 0.115, 0.98) if state != "hover" \
				else Color(0.13, 0.13, 0.17, 0.98)
		s.set_border_width_all(2)
		var b := accent if state != "disabled" else Color(0.30, 0.30, 0.33)
		s.border_color = b if state != "hover" else b.lightened(0.35)
		s.set_corner_radius_all(12)
		btn.add_theme_stylebox_override(state, s)

	var inner := VBoxContainer.new()
	inner.set_anchors_preset(Control.PRESET_FULL_RECT)
	inner.offset_left = 16.0; inner.offset_right = -16.0
	inner.offset_top = 20.0;  inner.offset_bottom = -18.0
	inner.alignment = BoxContainer.ALIGNMENT_CENTER
	inner.add_theme_constant_override("separation", 12)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(inner)

	if icon != null:
		var tex := TextureRect.new()
		tex.texture = icon
		tex.custom_minimum_size = Vector2(0, 110.0)
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.add_child(tex)

	var title_lbl := Label.new()
	title_lbl.text = title
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_lbl.add_theme_font_size_override("font_size", 24)
	title_lbl.modulate = accent.lightened(0.25)
	title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(title_lbl)

	var sub_lbl := Label.new()
	sub_lbl.text = sub
	sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub_lbl.add_theme_font_size_override("font_size", 14)
	sub_lbl.modulate = Color(0.70, 0.70, 0.74)
	sub_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(sub_lbl)

	return btn


# ── D: merchant split ─────────────────────────────────────────────────────────

static func merchant_split(root: Control, art_key: String,
		fallback_icon: String = "") -> VBoxContainer:
	_art_panel(root, MERCH_ART_OFFS, art_key, fallback_icon)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.05, 0.07, 0.90)
	style.set_corner_radius_all(10)
	var panel := _offset_panel(root, MERCH_PANEL_OFFS, style)
	return _content_vbox(panel, 34.0, 22.0, false)


# ── E: result flash ───────────────────────────────────────────────────────────

static func result_flash(root: Control, half_h: float = 240.0) -> VBoxContainer:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.08, 0.95)
	style.border_color = Color(0.72, 0.58, 0.28, 0.55)
	style.set_border_width_all(1)
	style.set_corner_radius_all(14)
	var panel := _offset_panel(root,
			[-450.0, -half_h - 40.0, 450.0, half_h + 40.0], style)
	return _content_vbox(panel, 44.0, 34.0, true)


# ── F: wanted poster ──────────────────────────────────────────────────────────

static func poster(root: Control) -> VBoxContainer:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.80, 0.72, 0.55)
	style.border_color = Color(0.25, 0.18, 0.10)
	style.set_border_width_all(7)
	style.set_corner_radius_all(3)
	var panel := _offset_panel(root, [-320.0, -400.0, 320.0, 400.0], style)

	# Nail at the top of the poster.
	var nail := Label.new()
	nail.text = "●"
	nail.add_theme_font_size_override("font_size", 18)
	nail.modulate = Color(0.20, 0.16, 0.10)
	nail.set_anchors_preset(Control.PRESET_CENTER_TOP)
	nail.offset_top = 10.0
	nail.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.add_child(nail)

	return _content_vbox(panel, 44.0, 44.0, true)


# ── Internals ─────────────────────────────────────────────────────────────────

static func _offset_panel(root: Control, offs: Array, style: StyleBoxFlat) -> Panel:
	var panel := Panel.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = offs[0]
	panel.offset_top = offs[1]
	panel.offset_right = offs[2]
	panel.offset_bottom = offs[3]
	panel.add_theme_stylebox_override("panel", style)
	root.add_child(panel)
	return panel


static func _content_vbox(panel: Panel, margin_x: float, margin_y: float,
		centered: bool) -> VBoxContainer:
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = margin_x
	vbox.offset_right = -margin_x
	vbox.offset_top = margin_y
	vbox.offset_bottom = -margin_y
	if centered:
		vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 14)
	panel.add_child(vbox)
	return vbox


## Left-side art panel: event art when it exists, otherwise the map-node
## icon as a large dim emblem so the layout never looks broken.
static func _art_panel(root: Control, offs: Array, art_key: String,
		fallback_icon: String) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.08, 0.88)
	style.set_corner_radius_all(12)
	var panel := _offset_panel(root, offs, style)

	var tex := art(art_key)
	var dim := false
	if tex == null and fallback_icon != "" and ResourceLoader.exists(fallback_icon):
		tex = load(fallback_icon)
		dim = true
	if tex == null:
		return

	var rect := TextureRect.new()
	rect.texture = tex
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	if dim:
		# Placeholder emblem: inset and ghosted.
		rect.offset_left = 70.0; rect.offset_right = -70.0
		rect.offset_top = 70.0;  rect.offset_bottom = -70.0
		rect.modulate = Color(1.0, 1.0, 1.0, 0.20)
	else:
		rect.offset_left = 14.0; rect.offset_right = -14.0
		rect.offset_top = 14.0;  rect.offset_bottom = -14.0
	panel.add_child(rect)
