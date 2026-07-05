## CombatantHUD
## A Tekken-style status panel for one combatant: translucent panel with
## name row, a Diablo-style liquid HP bar (with trailing damage ghost),
## a calmer liquid energy bar, and a block badge when block > 0.
##
## Set `mirrored = true` for the right-side (enemy) panel: the name
## right-aligns and the bars drain toward the center, fighting-game style.
extends Control

@export var mirrored: bool = false

const FLUID_SHADER := preload("res://shaders/fluid_bar.gdshader")

const PAD := 10.0
const HP_RECT := Rect2(PAD, 27.0, 420.0, 26.0)   # width fixed up in _ready
const EN_RECT := Rect2(PAD, 57.0, 420.0, 13.0)

# Cached values we draw from (kept in sync via the token's signals).
var _name: String = "?"
var _hp: int = 0
var _max_hp: int = 1
var _energy: int = 0
var _max_energy: int = 1
var _block: int = 0
var _preview_delta: int = 0    # hovered card's energy change (preview overlay)

# Ghost trail: HP ratio that lags behind after damage.
var _ghost: float = 1.0
var _ghost_wait: float = 0.0

var _hp_rect: Rect2
var _en_rect: Rect2
var _hp_mat: ShaderMaterial
var _en_mat: ShaderMaterial
var _overlay: Control

@onready var _name_label: Label = $NameLabel
@onready var _hp_label: Label = $HPLabel
@onready var _energy_label: Label = $EnergyLabel


func _ready() -> void:
	var w := size.x - PAD * 2.0
	_hp_rect = Rect2(PAD, HP_RECT.position.y, w, HP_RECT.size.y)
	_en_rect = Rect2(PAD, EN_RECT.position.y, w, EN_RECT.size.y)

	# ── Liquid bars (behind the labels) ──────────────────────────────────────
	_hp_mat = ShaderMaterial.new()
	_hp_mat.shader = FLUID_SHADER
	_hp_mat.set_shader_parameter("mirrored", mirrored)
	var hp_bar := ColorRect.new()
	hp_bar.material = _hp_mat
	hp_bar.position = _hp_rect.position
	hp_bar.size = _hp_rect.size
	hp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hp_bar)
	move_child(hp_bar, 0)

	_en_mat = ShaderMaterial.new()
	_en_mat.shader = FLUID_SHADER
	_en_mat.set_shader_parameter("mirrored", mirrored)
	_en_mat.set_shader_parameter("liquid_color", Color(0.25, 0.55, 0.95))
	_en_mat.set_shader_parameter("liquid_deep", Color(0.06, 0.16, 0.42))
	_en_mat.set_shader_parameter("ghost_color", Color(0, 0, 0, 0))
	_en_mat.set_shader_parameter("wave_amp", 0.012)
	_en_mat.set_shader_parameter("wave_speed", 1.6)
	_en_mat.set_shader_parameter("bubbles", 0.4)
	var en_bar := ColorRect.new()
	en_bar.material = _en_mat
	en_bar.position = _en_rect.position
	en_bar.size = _en_rect.size
	en_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(en_bar)
	move_child(en_bar, 1)

	# Overlay for borders, energy preview and the block badge (above bars,
	# below the text labels).
	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)
	move_child(_overlay, 2)

	# ── Label layout ─────────────────────────────────────────────────────────
	var side := HORIZONTAL_ALIGNMENT_RIGHT if mirrored else HORIZONTAL_ALIGNMENT_LEFT
	var opposite := HORIZONTAL_ALIGNMENT_LEFT if mirrored else HORIZONTAL_ALIGNMENT_RIGHT

	_name_label.horizontal_alignment = side
	_name_label.position = Vector2(PAD, 2.0)
	_name_label.size = Vector2(w, 22.0)
	_name_label.add_theme_font_size_override("font_size", 17)

	_hp_label.horizontal_alignment = opposite
	_hp_label.position = Vector2(PAD, 4.0)
	_hp_label.size = Vector2(w, 20.0)
	_hp_label.add_theme_font_size_override("font_size", 15)
	_hp_label.modulate = Color(0.95, 0.95, 0.95)

	_energy_label.horizontal_alignment = opposite
	_energy_label.position = Vector2(PAD + 6.0, _en_rect.position.y - 1.0)
	_energy_label.size = Vector2(w - 12.0, _en_rect.size.y + 2.0)
	_energy_label.add_theme_font_size_override("font_size", 11)
	_energy_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_energy_label.add_theme_constant_override("outline_size", 4)

	_redraw_labels()


## Connect this HUD to a token and seed the current values.
func bind(token: Token) -> void:
	_name = token.display_name
	_hp = token.hp
	_max_hp = token.max_hp
	_energy = token.energy
	_max_energy = token.max_energy
	_block = token.block
	_ghost = _ratio()
	token.hp_changed.connect(_on_hp_changed)
	token.energy_changed.connect(_on_energy_changed)
	token.block_changed.connect(_on_block_changed)
	_redraw_labels()
	queue_redraw()


func _ratio() -> float:
	return float(_hp) / float(maxi(_max_hp, 1))


func _process(delta: float) -> void:
	# Ghost trail: hold briefly after a hit, then drain toward the real HP.
	var target := _ratio()
	if _ghost > target:
		if _ghost_wait > 0.0:
			_ghost_wait -= delta
		else:
			_ghost = move_toward(_ghost, target, delta * 0.45)
	else:
		_ghost = target

	if _hp_mat != null:
		_hp_mat.set_shader_parameter("fill", target)
		_hp_mat.set_shader_parameter("ghost", _ghost)
		# HP bar shifts hue as it empties: green → amber → red.
		var col: Color
		var deep: Color
		if target > 0.5:
			col = Color(0.18, 0.72, 0.30); deep = Color(0.04, 0.34, 0.12)
		elif target > 0.25:
			col = Color(0.85, 0.62, 0.15); deep = Color(0.42, 0.28, 0.03)
		else:
			col = Color(0.88, 0.22, 0.18); deep = Color(0.40, 0.05, 0.04)
		_hp_mat.set_shader_parameter("liquid_color", col)
		_hp_mat.set_shader_parameter("liquid_deep", deep)
	if _en_mat != null:
		_en_mat.set_shader_parameter("fill", float(_energy) / float(maxi(_max_energy, 1)))
		_en_mat.set_shader_parameter("ghost", 0.0)


func _on_hp_changed(hp: int, max_hp: int) -> void:
	if hp < _hp:
		_ghost_wait = 0.4
	_hp = hp
	_max_hp = max_hp
	_redraw_labels()


func _on_energy_changed(energy: int, max_energy: int) -> void:
	_energy = energy
	_max_energy = max_energy
	_redraw_labels()


func _on_block_changed(block: int) -> void:
	_block = block
	if is_instance_valid(_overlay):
		_overlay.queue_redraw()


## Preview a pending energy change on the bar (called by Card on hover).
## Negative = will be spent (red), positive = will be gained (green), 0 = none.
func set_energy_preview(delta: int) -> void:
	_preview_delta = delta
	if is_instance_valid(_overlay):
		_overlay.queue_redraw()


func _redraw_labels() -> void:
	if not is_node_ready():
		return
	_name_label.text = _name
	_hp_label.text = "%d / %d" % [_hp, _max_hp]
	_energy_label.text = "%d / %d" % [_energy, _max_energy]
	if is_instance_valid(_overlay):
		_overlay.queue_redraw()


# ── Drawing ───────────────────────────────────────────────────────────────────

func _draw() -> void:
	# Translucent panel behind everything (matches the map HUD style).
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.04, 0.06, 0.72)
	sb.set_corner_radius_all(8)
	draw_style_box(sb, Rect2(Vector2.ZERO, size))


func _draw_overlay() -> void:
	# Bar borders.
	_overlay.draw_rect(_hp_rect, Color(0, 0, 0, 0.9), false, 2.0)
	_overlay.draw_rect(_en_rect, Color(0, 0, 0, 0.9), false, 2.0)
	_draw_energy_preview(_en_rect)
	_draw_block_badge()


## Shield badge at the bar's inner end (the side facing screen center).
func _draw_block_badge() -> void:
	if _block <= 0:
		return
	var badge_size := Vector2(46.0, 22.0)
	var x := _hp_rect.end.x - badge_size.x - 4.0
	if mirrored:
		x = _hp_rect.position.x + 4.0
	var rect := Rect2(Vector2(x, _hp_rect.position.y + 2.0), badge_size)

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.16, 0.28, 0.48, 0.95)
	sb.border_color = Color(0.55, 0.75, 1.0, 0.9)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	_overlay.draw_style_box(sb, rect)

	# Tiny shield glyph: a kite shape at the badge's left.
	var sx := rect.position.x + 11.0
	var sy := rect.position.y + rect.size.y * 0.5
	_overlay.draw_colored_polygon(PackedVector2Array([
		Vector2(sx, sy - 6.0), Vector2(sx + 5.0, sy - 3.0),
		Vector2(sx, sy + 7.0), Vector2(sx - 5.0, sy - 3.0),
	]), Color(0.75, 0.88, 1.0))

	var font := ThemeDB.fallback_font
	_overlay.draw_string(font, Vector2(sx + 9.0, sy + 5.0), str(_block),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)


## Overlay showing the hovered card's effect: red chunk = energy to be spent
## (rightmost of the current fill), green chunk = energy to be gained.
func _draw_energy_preview(rect: Rect2) -> void:
	if _preview_delta == 0 or _max_energy <= 0:
		return
	var unit := rect.size.x / float(_max_energy)
	if _preview_delta < 0:
		var consumed := mini(-_preview_delta, _energy)
		var x0 := rect.position.x + float(_energy - consumed) * unit
		if mirrored:
			x0 = rect.end.x - float(_energy) * unit
		_overlay.draw_rect(Rect2(Vector2(x0, rect.position.y),
				Vector2(consumed * unit, rect.size.y)), Color(1.0, 0.3, 0.3, 0.85), true)
	else:
		var added := mini(_preview_delta, _max_energy - _energy)
		var x0 := rect.position.x + float(_energy) * unit
		if mirrored:
			x0 = rect.end.x - float(_energy + added) * unit
		_overlay.draw_rect(Rect2(Vector2(x0, rect.position.y),
				Vector2(added * unit, rect.size.y)), Color(0.4, 1.0, 0.5, 0.8), true)
