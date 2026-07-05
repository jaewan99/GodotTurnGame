## Token
## A combatant piece on the grid: it has a CELL position, HP, and an ENERGY pool
## (energy is what it spends to play combat cards). ONE scene is reused for the
## player and the enemy.
##
## Shows a colored pixel placeholder + HP/Energy bars until you give it real art.
## `@tool` so it previews live in the editor.
@tool
class_name Token
extends Node2D

enum Team { PLAYER, ENEMY }

# ── Identity ────────────────────────────────────────────────────────────────
@export var display_name: String = "Token":
	set(value):
		display_name = value
		_refresh()

@export var team: Team = Team.PLAYER:
	set(value):
		team = value
		queue_redraw()

## Which grid cell this token starts on: x = column, y = row.
@export var start_cell: Vector2i = Vector2i(0, 1)

# ── Stats ───────────────────────────────────────────────────────────────────
@export_group("Stats")
@export var max_hp: int = 30:
	set(value):
		max_hp = maxi(1, value)
		if Engine.is_editor_hint():
			hp = max_hp        # keep the preview full while editing
		_refresh()

@export var max_energy: int = 10:
	set(value):
		max_energy = maxi(0, value)
		_refresh()

## Energy the token starts a battle with.
@export var start_energy: int = 5

## Energy gained each cleanup phase.
@export var energy_regen: int = 2

# ── Presentation ──────────────────────────────────────────────────────────────
@export var sprite_texture: Texture2D:
	set(value):
		sprite_texture = value
		_refresh()

@export_group("Placeholder look")
@export var box_size: float = 48.0:
	set(value):
		box_size = value
		queue_redraw()

const PLAYER_COLOR := Color(0.30, 0.65, 1.0)
const ENEMY_COLOR := Color(0.95, 0.35, 0.35)

# ── Signals (so the UI / battle logic can react) ──────────────────────────────
signal hp_changed(hp: int, max_hp: int)
signal energy_changed(energy: int, max_energy: int)
signal block_changed(block: int)
## Emitted when block absorbed part or all of an incoming hit.
signal blocked(amount: int)
signal died
signal hit(amount: int)

# ── Runtime state ─────────────────────────────────────────────────────────────
var hp: int
var energy: int
## Block absorbs incoming damage before HP. Refreshed at the start of each round
## (reset to 0 then re-granted by the offhand equipment).
var block: int = 0
## Set by the Battlefield so the token knows which board it lives on.
var board: Board
## Which cell the token is currently on.
var current_cell: Vector2i
## Direction this token is currently facing. Set by Battlefield after each move.
var facing: Vector2i = Vector2i(1, 0)
## Horizontal nudge applied when sharing a cell. Set by Battlefield.
var visual_offset: Vector2 = Vector2.ZERO

@onready var _sprite: Sprite2D = $Sprite
@onready var _name_label: Label = $NameLabel


func _ready() -> void:
	current_cell = start_cell
	hp = max_hp
	energy = start_energy
	facing = Vector2i(1, 0) if team == Team.PLAYER else Vector2i(-1, 0)
	_refresh()


# ── Stat changes ──────────────────────────────────────────────────────────────
func take_damage(amount: int) -> void:
	if amount <= 0:
		return
	if block > 0:
		var absorbed := mini(block, amount)
		block -= absorbed
		amount -= absorbed
		block_changed.emit(block)
		blocked.emit(absorbed)
	if amount <= 0:
		return
	hp = maxi(0, hp - amount)
	hp_changed.emit(hp, max_hp)
	_refresh()
	hit.emit(amount)
	_flash_red()
	if hp == 0:
		died.emit()


func _flash_red() -> void:
	if Engine.is_editor_hint():
		return
	var tween := create_tween()
	tween.tween_property(self, "modulate", Color(1.0, 0.2, 0.2), 0.06)
	tween.tween_property(self, "modulate", Color.WHITE, 0.22)


func heal(amount: int) -> void:
	hp = mini(max_hp, hp + amount)
	hp_changed.emit(hp, max_hp)
	_refresh()


func is_dead() -> bool:
	return hp <= 0


## Can this token afford a card that costs `amount` energy?
func can_afford(amount: int) -> bool:
	return energy >= amount


func spend_energy(amount: int) -> bool:
	if not can_afford(amount):
		return false
	energy -= amount
	energy_changed.emit(energy, max_energy)
	_refresh()
	return true


func gain_energy(amount: int) -> void:
	energy = mini(max_energy, energy + amount)
	energy_changed.emit(energy, max_energy)
	_refresh()


## Called during cleanup each turn.
func regen_energy() -> void:
	gain_energy(energy_regen)


# ── Visuals ───────────────────────────────────────────────────────────────────
func _refresh() -> void:
	if not is_node_ready():
		return
	_sprite.texture = sprite_texture
	_sprite.visible = sprite_texture != null
	_name_label.text = display_name
	queue_redraw()


func _draw() -> void:
	# Body: placeholder block (only when there's no real sprite yet).
	# HP/Energy are shown in the top-corner HUD, not here.
	if sprite_texture == null:
		var col := PLAYER_COLOR if team == Team.PLAYER else ENEMY_COLOR
		var half := box_size * 0.5
		var rect := Rect2(-half, -half, box_size, box_size)
		draw_rect(rect, col, true)
		draw_rect(rect, col.darkened(0.5), false, 2.0)

	# Small triangle showing which direction this token is facing.
	if facing.x != 0:
		var fx := float(facing.x)
		draw_colored_polygon(PackedVector2Array([
			Vector2(fx * 13.0,  0.0),   # tip
			Vector2(fx * -5.0, -8.0),   # base top
			Vector2(fx * -5.0,  8.0),   # base bottom
		]), Color(1.0, 1.0, 1.0, 0.82))


# ── Facing / Movement ─────────────────────────────────────────────────────────
## Which way this token faces. Updated by Battlefield after every move.
func get_facing() -> Vector2i:
	return facing


## Move this token onto a grid cell. Animates at runtime, snaps in editor.
## visual_offset is baked in so shared-cell nudges survive movement.
func move_to_cell(cell: Vector2i, animate := true) -> void:
	if board == null:
		return
	if not board.in_bounds(cell.x, cell.y):
		return
	current_cell = cell
	var target := board.get_cell_position(cell.x, cell.y) + visual_offset
	if animate and not Engine.is_editor_hint():
		var tween := create_tween()
		tween.set_trans(Tween.TRANS_SINE)
		tween.tween_property(self, "position", target, 0.3)
	else:
		position = target


## Apply visual_offset instantly (called by Battlefield after sharing changes).
func apply_visual_offset() -> void:
	if board == null:
		return
	position = board.get_cell_position(current_cell.x, current_cell.y) + visual_offset
