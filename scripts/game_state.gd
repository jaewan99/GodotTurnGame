## GameState
## Autoload singleton that persists run data across scene changes.
## Lives for the whole session; reset it to start a new run.
extends Node

const MAX_FLOORS := 3

var coins: int = 1
var floor: int = 1
var deck: Array[CardData] = []
var map_nodes: Array[MapNode] = []
var current_node_id: int = -1
## Increments each time the player removes a card at an Event node.
## Used to scale the removal cost: 50 × (cards_removed + 1).
var cards_removed: int = 0
## Equipped items. Key = EquipmentData.Slot (int), value = EquipmentData.
## Missing key or null value means that slot is empty.
var equipment: Dictionary = {}
## Unequipped equipment pieces stored between runs.
var inventory: Array[EquipmentData] = []
## Scrolls collected during the run.
var scrolls: Array = []   # Array[ScrollData] — untyped to avoid autoload parse-order issues


func has_map() -> bool:
	return map_nodes.size() > 0


func has_deck() -> bool:
	return deck.size() > 0


func reset() -> void:
	coins = 1
	floor = 1
	deck = []
	map_nodes = []
	current_node_id = -1
	cards_removed = 0
	equipment = {}
	inventory = []
	scrolls   = []
