class_name EquipmentData
extends Resource

enum Slot { WEAPON, OFFHAND, CHEST, HELM, SHOES, ITEM }

enum Rarity { COMMON, UNCOMMON, RARE, UNIQUE, LEGENDARY, MYSTERY }

static func rarity_color(r: int) -> Color:
	match r:
		Rarity.COMMON:    return Color(0.72, 0.72, 0.72)
		Rarity.UNCOMMON:  return Color(0.30, 0.82, 0.38)
		Rarity.RARE:      return Color(0.28, 0.60, 0.95)
		Rarity.UNIQUE:    return Color(0.92, 0.55, 0.15)
		Rarity.LEGENDARY: return Color(0.98, 0.82, 0.10)
		Rarity.MYSTERY:   return Color(0.78, 0.18, 0.88)
	return Color(0.72, 0.72, 0.72)

static func rarity_name(r: int) -> String:
	match r:
		Rarity.COMMON:    return "Common"
		Rarity.UNCOMMON:  return "Uncommon"
		Rarity.RARE:      return "Rare"
		Rarity.UNIQUE:    return "Unique"
		Rarity.LEGENDARY: return "Legendary"
		Rarity.MYSTERY:   return "???"
	return "Common"

const SLOT_NAMES := {0: "Weapon", 1: "Offhand", 2: "Chest", 3: "Helm", 4: "Shoes", 5: "Item"}

## True when this piece goes in an equipment slot. ITEM-slot pieces
## (keys, quest items…) sit in the inventory and can never be equipped.
static func is_equippable(ed: EquipmentData) -> bool:
	return ed.slot != Slot.ITEM

## Random-drop pool: every equippable piece. ITEM-slot pieces are excluded —
## they are granted by specific events (e.g. scavenging), not rolled as loot.
static func loot_pool() -> Array:
	return all().filter(func(e): return is_equippable(e))

## Drop chance per rarity tier in percent, COMMON → LEGENDARY. Sums to 100.
const RARITY_WEIGHTS := [40, 30, 17, 10, 3]

## Weighted rarity roll, shifted up by `boost` tiers (capped at LEGENDARY).
static func roll_rarity(boost: int = 0) -> int:
	var roll := randi() % 100
	var acc := 0
	var tier := 0
	for r in RARITY_WEIGHTS.size():
		acc += RARITY_WEIGHTS[r]
		if roll < acc:
			tier = r
			break
	return mini(tier + boost, Rarity.LEGENDARY)

## All equippable items of one rarity tier.
static func of_rarity(r: int) -> Array:
	return loot_pool().filter(func(e): return e.rarity == r)

## Fresh copy of a random drop: weighted rarity first, then a random item
## within that tier. Steps down a tier if the rolled one has no items.
static func random_drop(rarity_boost: int = 0) -> EquipmentData:
	var tier := roll_rarity(rarity_boost)
	var pool := of_rarity(tier)
	while pool.is_empty() and tier > 0:
		tier -= 1
		pool = of_rarity(tier)
	if pool.is_empty():
		return null
	return (pool.pick_random() as EquipmentData).duplicate()

## One-line stat summary, e.g. "(+3 dmg)".
static func stat_summary(ed: EquipmentData) -> String:
	if ed.damage_bonus     > 0: return "(+%d dmg)"      % ed.damage_bonus
	if ed.block_per_turn   > 0: return "(+%d blk/rnd)"  % ed.block_per_turn
	if ed.max_hp_bonus     > 0: return "(+%d HP)"       % ed.max_hp_bonus
	if ed.max_energy_bonus > 0: return "(+%d energy)"   % ed.max_energy_bonus
	if ed.crit_chance      > 0: return "(+%d%% crit)"   % ed.crit_chance
	return ""

## " ✦+N" suffix for enchanted items, empty otherwise.
static func enchant_tag(ed: EquipmentData) -> String:
	return " ✦+%d" % ed.enchant_level if ed.enchant_level > 0 else ""

## Multi-line hover tooltip with the full stat breakdown.
## Always shows the enchant level (✦+0 when unenchanted) so enchanted
## and unenchanted copies of the same item are distinguishable.
static func tooltip(ed: EquipmentData) -> String:
	var lines: Array[String] = []
	lines.append("%s  ✦+%d" % [ed.equipment_name, ed.enchant_level])
	lines.append("Slot: %s  |  Rarity: %s" % [
		SLOT_NAMES.get(ed.slot, "?"), rarity_name(ed.rarity)
	])
	lines.append("Max Enchants: %d" % ed.max_enchant)
	lines.append("─────────────────────")
	if not is_equippable(ed): lines.append("Cannot be equipped.")
	if ed.damage_bonus     != 0: lines.append("Damage Bonus:  +%d" % ed.damage_bonus)
	if ed.block_per_turn   != 0: lines.append("Block/Round:   +%d" % ed.block_per_turn)
	if ed.max_hp_bonus     != 0: lines.append("Max HP:        +%d" % ed.max_hp_bonus)
	if ed.max_energy_bonus != 0: lines.append("Max Energy:    +%d" % ed.max_energy_bonus)
	if ed.crit_chance      != 0: lines.append("Crit Chance:   +%d%%" % ed.crit_chance)
	if ed.enchant_level    >  0: lines.append("Enchanted: ✦×%d" % ed.enchant_level)
	return "\n".join(lines)

static var _cache: Array = []

static func all() -> Array:
	if _cache.is_empty():
		_cache = _load_json()
	return _cache

static func by_id(p_id: StringName) -> EquipmentData:
	for ed in all():
		if ed.id == p_id:
			return ed
	return null

static func _load_json() -> Array:
	var file := FileAccess.open("res://data/equipment/equipment.json", FileAccess.READ)
	if file == null:
		push_error("EquipmentData: cannot open res://data/equipment/equipment.json")
		return []
	var data = JSON.parse_string(file.get_as_text())
	if not data is Array:
		push_error("EquipmentData: equipment.json root must be an array")
		return []
	var result: Array = []
	for d in data:
		# Entries without an "id" are section dividers ("_comment"), not items.
		if not d.has("id"):
			continue
		result.append(_from_dict(d))
	return result

static func _from_dict(d: Dictionary) -> EquipmentData:
	var ed := EquipmentData.new()
	ed.id              = StringName(d.get("id", ""))
	ed.equipment_name  = d.get("equipment_name", "")
	ed.description     = d.get("description", "")
	ed.slot            = d.get("slot", 0)
	ed.rarity          = d.get("rarity", 0)
	ed.damage_bonus    = d.get("damage_bonus", 0)
	ed.block_per_turn  = d.get("block_per_turn", 0)
	ed.max_hp_bonus    = d.get("max_hp_bonus", 0)
	ed.max_energy_bonus = d.get("max_energy_bonus", 0)
	ed.crit_chance     = d.get("crit_chance", 0)
	ed.max_enchant     = d.get("max_enchant", 3)
	ed.is_active       = d.get("isActive", false)
	return ed

@export var id: StringName = &""
@export var equipment_name: String = "New Equipment"
@export_multiline var description: String = ""
@export var slot: Slot = Slot.WEAPON
@export var rarity: Rarity = Rarity.COMMON

@export_group("Stats")
@export var damage_bonus: int = 0       # WEAPON  — added to all attack damage
@export var block_per_turn: int = 0     # OFFHAND — block refreshed at start of each round
@export var max_hp_bonus: int = 0       # CHEST   — added to player max HP at battle start
@export var max_energy_bonus: int = 0   # HELM    — added to player max energy at battle start
@export var crit_chance: int = 0        # SHOES   — % chance to deal double damage (0–100)
## Total upgrade cap (forge enchants + scroll boosts), scales with rarity.
@export var max_enchant: int = 3
@export var is_active: bool = false

## Tracks how many times this item was successfully enchanted at an Enchant node.
## Scales enchant cost and success rate. Non-exported so templates stay at 0.
var enchant_level: int = 0
