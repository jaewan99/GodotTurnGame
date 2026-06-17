## GameState
## Autoload singleton that persists run data across scene changes.
## Lives for the whole session; reset it to start a new run.
extends Node

const MAX_FLOORS := 3

var coins: int = 1
var floor_num: int = 1
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

# ── Battle modifiers (set by map nodes, consumed by battlefield) ──────────────
## Permanent max-HP reduction for this run (cursed shrine).
var max_hp_curse: int = 0
## Overrides the enemy tier for the next battle (-1 = use node type).
var battle_tier_override: int = -1
## Bounty contract: win within this many rounds → coins ×3 (0 = no bounty).
var bounty_rounds: int = 0
## Coin reward multiplier for the next battle (secret elite etc.).
var coin_mult: int = 1
## Set after winning a Dojo battle; map shows the free-upgrade overlay.
var dojo_reward_pending: bool = false


func has_map() -> bool:
	return map_nodes.size() > 0


func has_deck() -> bool:
	return deck.size() > 0


func reset() -> void:
	coins = 1
	floor_num = 1
	deck = []
	map_nodes = []
	current_node_id = -1
	cards_removed = 0
	equipment = {}
	inventory = []
	scrolls   = []
	max_hp_curse = 0
	battle_tier_override = -1
	bounty_rounds = 0
	coin_mult = 1
	dojo_reward_pending = false
