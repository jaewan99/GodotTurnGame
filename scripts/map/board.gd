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


func _draw() -> void:
	for row in range(rows):
		for col in range(columns):
			var center := get_cell_position(col, row)
			var half := cell_size * 0.5
			var rect := Rect2(center - Vector2(half, half), Vector2(cell_size, cell_size))
			draw_rect(rect, cell_fill, true)               # cell background
			draw_rect(rect, line_color, false, line_width) # cell border


## Local position (relative to this Board node) of a cell's CENTER.
func get_cell_position(col: int, row: int) -> Vector2:
	var grid_size := Vector2(columns * cell_size, rows * cell_size)
	return Vector2((col + 0.5) * cell_size, (row + 0.5) * cell_size) - grid_size * 0.5


## Is (col, row) a real cell on the grid?
func in_bounds(col: int, row: int) -> bool:
	return col >= 0 and col < columns and row >= 0 and row < rows
