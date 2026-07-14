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
## Set true when the player dies; the main menu reads it to show a death notice.
var player_died: bool = false


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
	player_died = false


# ── Save / Load ───────────────────────────────────────────────────────────────
## The run is persisted to a JSON file under user://. Because every data resource
## (cards, equipment, scrolls, map nodes) is rebuilt from JSON templates by id, we
## only store each item's id plus the fields that change at runtime (forge levels,
## enchant stats, node visited flags, …) and reconstruct the rest on load.

const SAVE_PATH := "user://savegame.json"
const SAVE_VERSION := 1


func has_save_file() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func delete_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)


## Serialise the whole run and write it to disk. Returns true on success.
func save_game() -> bool:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("GameState: cannot open %s for writing" % SAVE_PATH)
		return false
	file.store_string(JSON.stringify(to_save_dict(), "\t"))
	file.close()
	return true


## Read the save file and repopulate the run. Returns true on success.
func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return false
	var data = JSON.parse_string(file.get_as_text())
	file.close()
	if not data is Dictionary:
		push_error("GameState: save file is malformed")
		return false
	apply_save_dict(data)
	return true


func to_save_dict() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"coins": coins,
		"floor_num": floor_num,
		"current_node_id": current_node_id,
		"cards_removed": cards_removed,
		"max_hp_curse": max_hp_curse,
		"deck": deck.map(_card_to_dict),
		"inventory": inventory.map(_equip_to_dict),
		"scrolls": scrolls.map(_scroll_to_dict),
		"equipment": equipment.values().map(_equip_to_dict),
		"map_nodes": map_nodes.map(_node_to_dict),
	}


func apply_save_dict(d: Dictionary) -> void:
	coins           = int(d.get("coins", 1))
	floor_num       = int(d.get("floor_num", 1))
	current_node_id = int(d.get("current_node_id", -1))
	cards_removed   = int(d.get("cards_removed", 0))
	max_hp_curse    = int(d.get("max_hp_curse", 0))

	deck = []
	for cd_dict in d.get("deck", []):
		var cd := _card_from_dict(cd_dict)
		if cd != null:
			deck.append(cd)

	inventory = []
	for ed_dict in d.get("inventory", []):
		var ed := _equip_from_dict(ed_dict)
		if ed != null:
			inventory.append(ed)

	scrolls = []
	for sd_dict in d.get("scrolls", []):
		var sd := _scroll_from_dict(sd_dict)
		if sd != null:
			scrolls.append(sd)

	equipment = {}
	for ed_dict in d.get("equipment", []):
		var ed := _equip_from_dict(ed_dict)
		if ed != null:
			equipment[ed.slot] = ed

	map_nodes = []
	for n_dict in d.get("map_nodes", []):
		map_nodes.append(_node_from_dict(n_dict))

	# One-shot battle modifiers never persist across a save/load.
	battle_tier_override = -1
	bounty_rounds = 0
	coin_mult = 1
	dojo_reward_pending = false
	player_died = false


# ── Resource (de)serialisers ──────────────────────────────────────────────────

func _card_to_dict(cd: CardData) -> Dictionary:
	return {"id": String(cd.id), "level": cd.level, "upgrades": cd.upgrades, "damage": cd.damage}


func _card_from_dict(d: Dictionary) -> CardData:
	var base := CardData.by_id(StringName(d.get("id", "")))
	if base == null:
		return null
	var cd: CardData = base.duplicate()
	cd.level    = int(d.get("level", 0))
	cd.upgrades = int(d.get("upgrades", 0))
	cd.damage   = int(d.get("damage", cd.damage))
	return cd


func _equip_to_dict(ed: EquipmentData) -> Dictionary:
	return {
		"id": String(ed.id),
		"damage_bonus": ed.damage_bonus,
		"block_per_turn": ed.block_per_turn,
		"max_hp_bonus": ed.max_hp_bonus,
		"max_energy_bonus": ed.max_energy_bonus,
		"crit_chance": ed.crit_chance,
		"enchant_level": ed.enchant_level,
	}


func _equip_from_dict(d: Dictionary) -> EquipmentData:
	var base := EquipmentData.by_id(StringName(d.get("id", "")))
	if base == null:
		return null
	var ed: EquipmentData = base.duplicate()
	ed.damage_bonus     = int(d.get("damage_bonus", ed.damage_bonus))
	ed.block_per_turn   = int(d.get("block_per_turn", ed.block_per_turn))
	ed.max_hp_bonus     = int(d.get("max_hp_bonus", ed.max_hp_bonus))
	ed.max_energy_bonus = int(d.get("max_energy_bonus", ed.max_energy_bonus))
	ed.crit_chance      = int(d.get("crit_chance", ed.crit_chance))
	ed.enchant_level    = int(d.get("enchant_level", ed.enchant_level))
	return ed


func _scroll_to_dict(sd: ScrollData) -> Dictionary:
	return {"id": String(sd.id)}


func _scroll_from_dict(d: Dictionary) -> ScrollData:
	var base := ScrollData.by_id(StringName(d.get("id", "")))
	return base.duplicate() if base != null else null


func _node_to_dict(n: MapNode) -> Dictionary:
	return {
		"id": n.id,
		"type": int(n.type),
		"pos": [n.pos.x, n.pos.y],
		"connections": n.connections.duplicate(),
		"visited": n.visited,
		"always_accessible": n.always_accessible,
		"shop_stocked": n.shop_stocked,
		"shop_stock_equip": n.shop_stock_equip.map(_equip_to_dict),
		"shop_stock_scrolls": n.shop_stock_scrolls.map(_scroll_to_dict),
		"secret_revealed": n.secret_revealed,
	}


func _node_from_dict(d: Dictionary) -> MapNode:
	var n := MapNode.new()
	n.id = int(d.get("id", 0))
	n.type = int(d.get("type", MapNode.Type.FIGHT))
	var p = d.get("pos", [0, 0])
	n.pos = Vector2(p[0], p[1])
	var conns: Array[int] = []
	for c in d.get("connections", []):
		conns.append(int(c))
	n.connections = conns
	n.visited = bool(d.get("visited", false))
	n.always_accessible = bool(d.get("always_accessible", false))
	n.shop_stocked = bool(d.get("shop_stocked", false))
	n.secret_revealed = bool(d.get("secret_revealed", false))
	for ed_dict in d.get("shop_stock_equip", []):
		var ed := _equip_from_dict(ed_dict)
		if ed != null:
			n.shop_stock_equip.append(ed)
	for sd_dict in d.get("shop_stock_scrolls", []):
		var sd := _scroll_from_dict(sd_dict)
		if sd != null:
			n.shop_stock_scrolls.append(sd)
	return n
