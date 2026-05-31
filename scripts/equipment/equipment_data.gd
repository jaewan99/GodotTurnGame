class_name EquipmentData
extends Resource

enum Slot { WEAPON, OFFHAND, CHEST, HELM, SHOES }

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
