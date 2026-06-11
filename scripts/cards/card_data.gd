## CardData
## The *data* shape of a single card — no visuals, no behaviour, just values.
## In Unreal terms this is like a Data Asset / struct you fill in per card.
##
## Because it `extends Resource` and has `class_name`, Godot lets you create
## ".tres" files of this type right-click → New Resource → CardData, and edit
## every field in the Inspector. We'll make one .tres per real card later.
##
## NOTE: This is a DRAFT. The combat fields (damage/block/...) are placeholders
## until we lock down the actual game rules. Easy to change later.
@tool
class_name CardData
extends CardResource

## What kind of action the card represents.
enum CardType {
	ATTACK,  ## deals damage
	SKILL,   ## utility / defense / buff
	POWER,   ## lasting effect
	MOVE,    ## moves the player's token on the grid
}

@export_group("Identity")
@export var id: StringName = &""              ## unique key, e.g. &"inuyasha_slash"
@export var card_name: String = "New Card"    ## shown to the player
@export_multiline var description: String = "" ## rules text

@export_group("Cost & Type")
@export var cost: int = 1                      ## energy needed to play it
@export var type: CardType = CardType.ATTACK

## Tracks how many times this specific instance has been forged at the Event node.
## Not exported — .tres template files always start at 0; only live deck copies carry a level.
var level: int = 0

@export_group("Effect (draft)")
@export var damage: int = 0                    ## damage dealt, if any (ATTACK)
@export var block: int = 0                     ## defense gained, if any
@export var energy_gain: int = 0               ## energy restored (SKILL, e.g. Focus)
## For MOVE cards: how far/which way to move on the grid.
## x = columns (右+/左-), y = rows (下+/上-). e.g. Down = (0, 1), Up = (0, -1).
@export var move_direction: Vector2i = Vector2i.ZERO

## Optional movement applied when this card is played, relative to the actor's facing.
## x: -1=backward  +1=forward   y: -1=up  +1=down
## Works on any card type (ATTACK, SKILL, …). Zero = no step.
@export var step_direction: Vector2i = Vector2i.ZERO

## Which cells this card affects, relative to the player at (0,0).
## x: -1=left  0=center  +1=right
## y: -1=up    0=same row +1=down
## e.g. slash hits the cell directly in front → [(0,-1)]
## Empty array = no target display (passive / move cards show their move_direction instead)
@export var affected_cells: Array[Vector2i] = []

@export_group("Presentation")
@export var art: Texture2D                     ## the card's illustration

## Pool membership — set by JSON loader, not stored in .tres files.
var in_reward_pool: bool = false
var starter_count: int = 0

# ── JSON data layer ──────────────────────────────────────────────────────────

static var _cache: Array = []

static func all() -> Array:
	if _cache.is_empty():
		_cache = _load_json()
	return _cache

static func by_id(p_id: StringName) -> CardData:
	for cd in all():
		if cd.id == p_id:
			return cd
	return null

## Cards that can appear as battle rewards.
static func reward_pool() -> Array:
	return all().filter(func(cd: CardData) -> bool: return cd.in_reward_pool)

## Expanded starter deck — each card duplicated starter_count times.
static func starter_deck() -> Array:
	var result: Array = []
	for cd in all():
		for _i in cd.starter_count:
			result.append(cd.duplicate())
	return result

static func _load_json() -> Array:
	var file := FileAccess.open("res://data/cards/cards.json", FileAccess.READ)
	if file == null:
		push_error("CardData: cannot open res://data/cards/cards.json")
		return []
	var data = JSON.parse_string(file.get_as_text())
	if not data is Array:
		push_error("CardData: cards.json root must be an array")
		return []
	var result: Array = []
	for d in data:
		result.append(_from_dict(d))
	return result

static func _from_dict(d: Dictionary) -> CardData:
	var cd := CardData.new()
	cd.id            = StringName(d.get("id", ""))
	cd.card_name     = d.get("card_name", "")
	cd.description   = d.get("description", "")
	cd.cost          = d.get("cost", 0)
	cd.type          = d.get("type", 0)
	cd.damage        = d.get("damage", 0)
	cd.block         = d.get("block", 0)
	cd.energy_gain   = d.get("energy_gain", 0)
	var dir          = d.get("move_direction", [0, 0])
	cd.move_direction = Vector2i(dir[0], dir[1])
	var step          = d.get("step", [0, 0])
	cd.step_direction = Vector2i(step[0], step[1])
	cd.in_reward_pool = d.get("reward", false)
	cd.starter_count  = d.get("starter", 0)
	var art_path: String = d.get("art", "")
	if art_path != "":
		cd.art = load(art_path)
	for cell in d.get("affected_cells", []):
		cd.affected_cells.append(Vector2i(cell[0], cell[1]))
	# MOVE cards: if no affected_cells, treat move_direction as the target cell
	if cd.affected_cells.is_empty() and cd.move_direction != Vector2i.ZERO:
		cd.affected_cells.append(cd.move_direction)
	return cd
