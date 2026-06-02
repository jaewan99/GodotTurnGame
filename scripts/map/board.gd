## Board
## A grid battlefield (like a chessboard). Cells are addressed by (col, row),
## starting at (0, 0) in the top-left. Default 3×3.
##
## The grid is drawn centered on this node's origin, so place the Board node
## wherever you want the center of the battlefield to be.
##
## `@tool` so it draws live in the editor — change columns/rows/cell size and
## watch it update.
@tool
class_name Board
extends Node2D

@export var columns: int = 3:
	set(value):
		columns = maxi(1, value)
		queue_redraw()
@export var rows: int = 3:
	set(value):
		rows = maxi(1, value)
		queue_redraw()
@export var cell_size: float = 140.0:
	set(value):
		cell_size = value
		queue_redraw()

@export_group("Look")
@export var cell_fill: Color = Color(0.12, 0.14, 0.10, 0.6):
	set(value): cell_fill = value; queue_redraw()
@export var line_color: Color = Color(1, 1, 1, 0.5):
	set(value): line_color = value; queue_redraw()
@export var line_width: float = 3.0:
	set(value): line_width = value; queue_redraw()

# ── Range highlight state (set by Battlefield) ────────────────────────────
var _highlight_cells: Array[Vector2i] = []
var _highlight_origin: Vector2i = Vector2i(-1, -1)   # player's current cell
var _highlight_is_move: bool = false


func _draw() -> void:
	for row in range(rows):
		for col in range(columns):
			var center := get_cell_position(col, row)
			var half := cell_size * 0.5
			var rect := Rect2(center - Vector2(half, half), Vector2(cell_size, cell_size))
			draw_rect(rect, cell_fill, true)               # cell background
			draw_rect(rect, line_color, false, line_width) # cell border

	# Draw range highlight overlay on top
	if _highlight_cells.is_empty() or _highlight_origin == Vector2i(-1, -1):
		return

	var hit_col  := Color(0.95, 0.25, 0.15, 0.45) if not _highlight_is_move \
				 else Color(0.20, 0.85, 0.40, 0.45)
	var hit_border := Color(1.0, 0.5, 0.3, 0.85) if not _highlight_is_move \
				   else Color(0.4, 1.0, 0.5, 0.85)

	for offset in _highlight_cells:
		var target_cell := _highlight_origin + offset
		if not in_bounds(target_cell.x, target_cell.y):
			continue
		var center := get_cell_position(target_cell.x, target_cell.y)
		var half := cell_size * 0.5
		var rect := Rect2(center - Vector2(half, half), Vector2(cell_size, cell_size))
		draw_rect(rect, hit_col, true)
		draw_rect(rect, hit_border, false, line_width + 1.0)


## Local position (relative to this Board node) of a cell's CENTER.
func get_cell_position(col: int, row: int) -> Vector2:
	var grid_size := Vector2(columns * cell_size, rows * cell_size)
	return Vector2((col + 0.5) * cell_size, (row + 0.5) * cell_size) - grid_size * 0.5


## Is (col, row) a real cell on the grid?
func in_bounds(col: int, row: int) -> bool:
	return col >= 0 and col < columns and row >= 0 and row < rows


## Show which cells a card would affect, given the player's current cell.
func highlight_cells(cells: Array[Vector2i], origin: Vector2i, is_move: bool) -> void:
	_highlight_cells = cells
	_highlight_origin = origin
	_highlight_is_move = is_move
	queue_redraw()


## Remove the range highlight.
func clear_highlight() -> void:
	_highlight_cells = []
	_highlight_origin = Vector2i(-1, -1)
	queue_redraw()
