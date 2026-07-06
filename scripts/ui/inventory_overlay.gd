## InventoryOverlay
## Self-contained full-screen inventory viewer.
## Layout: EQUIPPED slots on the left half, ITEMS grid upper-right,
## SCROLLS grid lower-right. Icon-tile based (placeholder art: res://icon.svg).
## Usable from any scene:
##     InventoryOverlay.open(self)
## Clicking an item tile equips it (auto-swaps); clicking an equipped tile
## unequips it. Merging and scroll use live at the Forge map node, not here.
class_name InventoryOverlay
extends CanvasLayer

## Placeholder icon used for every item until real art exists.
const ICON_PATH := "res://icon.svg"

## Root folder for item art, organised in one subfolder per equipment slot
## plus "etc" (non-equippable items) and "scrolls". Drop a PNG named after
## the item's id (e.g. weapon/iron_sword.png, etc/key.png,
## scrolls/attack_scroll.png) and it is picked up automatically; items
## without art fall back to the tinted placeholder.
const ITEM_ART_DIR := "res://assets/items/"

## Slot (int) → art subfolder. ITEM-slot pieces live in "etc".
const ART_SUBDIRS := {0: "weapon", 1: "offhand", 2: "chest", 3: "helm", 4: "shoes", 5: "etc"}

## Art for an id inside one subfolder, or null when none exists yet.
static func icon_for(id: StringName, subdir: String) -> Texture2D:
	var path := "%s%s/%s.png" % [ITEM_ART_DIR, subdir, id]
	if ResourceLoader.exists(path):
		return load(path)
	return null

## Art for a piece of equipment (subfolder from its slot), or null.
static func equip_icon(ed: EquipmentData) -> Texture2D:
	return icon_for(ed.id, ART_SUBDIRS.get(ed.slot, "etc"))

## Art for a scroll, or null.
static func scroll_icon(sd: ScrollData) -> Texture2D:
	return icon_for(sd.id, "scrolls")

const TILE := 86.0          # square tile size (px)
const EQUIP_TILE := 96.0    # equipped slot tile size (px)

var _root: Control
## When true (opened during a battle) equip/unequip is disabled.
var _read_only: bool = false


static func open(parent: Node, read_only: bool = false) -> InventoryOverlay:
	var ov := InventoryOverlay.new()
	ov._read_only = read_only
	parent.add_child(ov)
	return ov


func _ready() -> void:
	layer = 10

	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 0.88)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	_rebuild()


func _rebuild() -> void:
	for c in _root.get_children():
		c.queue_free()

	var panel := Panel.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left   = -520.0
	panel.offset_right  =  520.0
	panel.offset_top    = -370.0
	panel.offset_bottom =  370.0
	_root.add_child(panel)

	var outer := VBoxContainer.new()
	outer.set_anchors_preset(Control.PRESET_FULL_RECT)
	outer.offset_left = 16; outer.offset_right  = -16
	outer.offset_top  = 10; outer.offset_bottom = -12
	outer.add_theme_constant_override("separation", 8)
	panel.add_child(outer)

	# ── Header ────────────────────────────────────────────────────────────────
	var hdr := HBoxContainer.new()
	outer.add_child(hdr)

	var title_lbl := Label.new()
	title_lbl.text = "INVENTORY"
	title_lbl.add_theme_font_size_override("font_size", 26)
	title_lbl.modulate = Color(0.88, 0.82, 1.0)
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr.add_child(title_lbl)

	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.add_theme_font_size_override("font_size", 16)
	close_btn.pressed.connect(func(): queue_free())
	hdr.add_child(close_btn)

	outer.add_child(HSeparator.new())

	# ── Body: left = equipped, right = items / scrolls ────────────────────────
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	outer.add_child(body)

	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(430, 0)
	left.add_theme_constant_override("separation", 8)
	body.add_child(left)
	_build_equipped(left)

	body.add_child(VSeparator.new())

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	body.add_child(right)
	_build_items(right)
	right.add_child(HSeparator.new())
	_build_scrolls(right)


# ── Left half: equipped slots ─────────────────────────────────────────────────

func _build_equipped(parent: VBoxContainer) -> void:
	parent.add_child(_section_label("EQUIPPED"))

	for slot_int in [0, 1, 2, 3, 4]:
		var ed := GameState.equipment.get(slot_int) as EquipmentData

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		parent.add_child(row)

		row.add_child(make_tile(ed, EQUIP_TILE, slot_int))

		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_child(info)

		var slot_lbl := Label.new()
		slot_lbl.text = EquipmentData.SLOT_NAMES.get(slot_int, "?")
		slot_lbl.add_theme_font_size_override("font_size", 13)
		slot_lbl.modulate = Color(0.55, 0.55, 0.60)
		info.add_child(slot_lbl)

		var name_lbl := Label.new()
		name_lbl.add_theme_font_size_override("font_size", 16)
		if ed != null:
			name_lbl.text = "%s  ✦+%d" % [ed.equipment_name, ed.enchant_level]
			name_lbl.modulate = EquipmentData.rarity_color(ed.rarity)
		else:
			name_lbl.text = "— empty —"
			name_lbl.modulate = Color(0.4, 0.4, 0.4)
		info.add_child(name_lbl)

		if ed != null:
			var stat_lbl := Label.new()
			stat_lbl.text = EquipmentData.stat_summary(ed)
			stat_lbl.add_theme_font_size_override("font_size", 13)
			stat_lbl.modulate = Color(0.85, 0.85, 0.6)
			info.add_child(stat_lbl)

			if not _read_only:
				var unequip_btn := Button.new()
				unequip_btn.text = "Unequip"
				unequip_btn.add_theme_font_size_override("font_size", 12)
				var cap_slot: int = slot_int
				var cap_ed := ed
				unequip_btn.pressed.connect(func():
					GameState.equipment.erase(cap_slot)
					GameState.inventory.append(cap_ed)
					_rebuild()
				)
				row.add_child(unequip_btn)


# ── Upper right: items grid ───────────────────────────────────────────────────

func _build_items(parent: VBoxContainer) -> void:
	parent.add_child(_section_label("ITEMS  (%d)" % GameState.inventory.size()))
	if _read_only:
		var note := Label.new()
		note.text = "Equipment is locked during battle."
		note.add_theme_font_size_override("font_size", 12)
		note.modulate = Color(0.75, 0.6, 0.5)
		parent.add_child(note)

	var scr := ScrollContainer.new()
	scr.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scr.size_flags_stretch_ratio = 0.6
	parent.add_child(scr)

	if GameState.inventory.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "No items. Click an item tile to equip it."
		empty_lbl.modulate = Color(0.5, 0.5, 0.5)
		empty_lbl.add_theme_font_size_override("font_size", 13)
		scr.add_child(empty_lbl)
		return

	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	scr.add_child(grid)

	for item in GameState.inventory:
		var ed := item as EquipmentData
		if ed == null:
			continue
		var tile := make_tile(ed, TILE)
		if EquipmentData.is_equippable(ed) and not _read_only:
			var cap_ed := ed
			tile.pressed.connect(func():
				var old := GameState.equipment.get(cap_ed.slot) as EquipmentData
				if old != null:
					GameState.inventory.append(old)
				GameState.equipment[cap_ed.slot] = cap_ed
				GameState.inventory.erase(cap_ed)
				_rebuild()
			)
		grid.add_child(tile)


# ── Lower right: scrolls grid ─────────────────────────────────────────────────

func _build_scrolls(parent: VBoxContainer) -> void:
	var hdr := HBoxContainer.new()
	parent.add_child(hdr)
	var lbl := _section_label("SCROLLS  (%d)" % GameState.scrolls.size())
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr.add_child(lbl)
	var hint := Label.new()
	hint.text = "use at Forge"
	hint.add_theme_font_size_override("font_size", 12)
	hint.modulate = Color(0.5, 0.5, 0.5)
	hdr.add_child(hint)

	var scr := ScrollContainer.new()
	scr.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scr.size_flags_stretch_ratio = 0.4
	parent.add_child(scr)

	if GameState.scrolls.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "No scrolls in inventory."
		empty_lbl.modulate = Color(0.5, 0.5, 0.5)
		empty_lbl.add_theme_font_size_override("font_size", 13)
		scr.add_child(empty_lbl)
		return

	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	scr.add_child(grid)

	for scroll in GameState.scrolls:
		var sd: ScrollData = scroll as ScrollData
		if sd == null:
			continue
		grid.add_child(make_scroll_tile(sd))


# ── Tile builders ─────────────────────────────────────────────────────────────

## Square icon tile for a piece of equipment (or an empty slot when ed == null).
## Rarity-colored border, placeholder icon, ✦+N badge, full tooltip on hover.
## Static so other screens (forge, shop…) can build matching tiles.
static func make_tile(ed: EquipmentData, tile_size: float, empty_slot: int = -1) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(tile_size, tile_size)

	var border := EquipmentData.rarity_color(ed.rarity) if ed != null \
			else Color(0.30, 0.30, 0.34)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var s := StyleBoxFlat.new()
		s.bg_color = Color(0.10, 0.10, 0.13) if state != "hover" else Color(0.16, 0.16, 0.20)
		s.set_border_width_all(2)
		s.border_color = border if state != "hover" else border.lightened(0.3)
		s.set_corner_radius_all(8)
		btn.add_theme_stylebox_override(state, s)

	if ed != null:
		var icon := TextureRect.new()
		var art := equip_icon(ed)
		icon.texture = art if art != null else load(ICON_PATH)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.set_anchors_preset(Control.PRESET_FULL_RECT)
		icon.offset_left = 12; icon.offset_right = -12
		icon.offset_top = 12; icon.offset_bottom = -12
		if art == null:
			icon.modulate = EquipmentData.rarity_color(ed.rarity)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(icon)

		if ed.enchant_level > 0:
			var badge := Label.new()
			badge.text = "✦+%d" % ed.enchant_level
			badge.add_theme_font_size_override("font_size", 11)
			badge.modulate = Color(1.0, 0.9, 0.4)
			badge.set_anchors_preset(Control.PRESET_TOP_RIGHT)
			badge.offset_left = -40.0; badge.offset_right = -4.0
			badge.offset_top = 2.0; badge.offset_bottom = 18.0
			badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
			btn.add_child(badge)

		btn.tooltip_text = EquipmentData.tooltip(ed)
	else:
		var slot_lbl := Label.new()
		slot_lbl.text = EquipmentData.SLOT_NAMES.get(empty_slot, "?")
		slot_lbl.add_theme_font_size_override("font_size", 11)
		slot_lbl.modulate = Color(0.35, 0.35, 0.38)
		slot_lbl.set_anchors_preset(Control.PRESET_CENTER)
		slot_lbl.grow_horizontal = Control.GROW_DIRECTION_BOTH
		slot_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		slot_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(slot_lbl)
		btn.disabled = true
		btn.tooltip_text = "Empty %s slot" % EquipmentData.SLOT_NAMES.get(empty_slot, "?")

	return btn


## Square icon tile for a scroll, tinted by its stat color.
## Static so other screens (forge) can build matching tiles.
static func make_scroll_tile(sd: ScrollData, tile_size: float = TILE) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(tile_size, tile_size)

	# Border follows rarity like equipment tiles; the placeholder icon
	# keeps the stat color so scroll types stay distinguishable.
	var border: Color = EquipmentData.rarity_color(sd.rarity)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var s := StyleBoxFlat.new()
		s.bg_color = Color(0.10, 0.10, 0.13) if state != "hover" else Color(0.16, 0.16, 0.20)
		s.set_border_width_all(2)
		s.border_color = border if state != "hover" else border.lightened(0.3)
		s.set_corner_radius_all(8)
		btn.add_theme_stylebox_override(state, s)

	var icon := TextureRect.new()
	var art := scroll_icon(sd)
	icon.texture = art if art != null else load(ICON_PATH)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon.offset_left = 12; icon.offset_right = -12
	icon.offset_top = 12; icon.offset_bottom = -12
	if art == null:
		icon.modulate = sd.stat_color()
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(icon)

	var boost := Label.new()
	boost.text = "+%d" % sd.boost_amount
	boost.add_theme_font_size_override("font_size", 12)
	boost.modulate = Color(1.0, 1.0, 1.0, 0.9)
	boost.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	boost.offset_left = -34.0; boost.offset_right = -4.0
	boost.offset_top = -20.0; boost.offset_bottom = -2.0
	boost.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	boost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(boost)

	btn.tooltip_text = "%s\nRarity: %s\n+%d %s\n%d%% success  /  %d%% destroy on fail\n(use at the Forge node)" % [
		sd.scroll_name, EquipmentData.rarity_name(sd.rarity),
		sd.boost_amount, sd.stat_label(),
		sd.success_chance, sd.destroy_chance,
	]
	return btn


# ── Helpers ───────────────────────────────────────────────────────────────────

func _section_label(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.modulate = Color(0.75, 0.70, 0.90)
	return lbl
