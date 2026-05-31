class_name ScrollData
extends Resource

enum StatType { DAMAGE, BLOCK, MAX_HP, MAX_ENERGY, CRIT }

static var _cache: Array = []

static func all() -> Array:
	if _cache.is_empty():
		_cache = _load_json()
	return _cache

static func by_id(p_id: StringName) -> ScrollData:
	for sd in all():
		if sd.id == p_id:
			return sd
	return null

static func _load_json() -> Array:
	var file := FileAccess.open("res://data/scrolls/scrolls.json", FileAccess.READ)
	if file == null:
		push_error("ScrollData: cannot open res://data/scrolls/scrolls.json")
		return []
	var data = JSON.parse_string(file.get_as_text())
	if not data is Array:
		push_error("ScrollData: scrolls.json root must be an array")
		return []
	var result: Array = []
	for d in data:
		result.append(_from_dict(d))
	return result

static func _from_dict(d: Dictionary) -> ScrollData:
	var sd := ScrollData.new()
	sd.id             = StringName(d.get("id", ""))
	sd.scroll_name    = d.get("scroll_name", "")
	sd.description    = d.get("description", "")
	sd.stat_type      = d.get("stat_type", 0)
	sd.boost_amount   = d.get("boost_amount", 1)
	sd.success_chance = d.get("success_chance", 70)
	sd.destroy_chance = d.get("destroy_chance", 20)
	return sd

@export var id: StringName = &""
@export var scroll_name: String = "Scroll"
@export_multiline var description: String = ""
@export var stat_type: int = 0   # StatType enum value
@export var boost_amount: int = 1
@export var success_chance: int = 70
@export var destroy_chance: int = 20


func stat_label() -> String:
	match stat_type:
		StatType.DAMAGE:     return "Atk Dmg"
		StatType.BLOCK:      return "Block/Rnd"
		StatType.MAX_HP:     return "Max HP"
		StatType.MAX_ENERGY: return "Max Energy"
		StatType.CRIT:       return "Crit %"
	return "?"


func stat_color() -> Color:
	match stat_type:
		StatType.DAMAGE:     return Color(0.95, 0.35, 0.30)
		StatType.BLOCK:      return Color(0.30, 0.65, 0.95)
		StatType.MAX_HP:     return Color(0.30, 0.88, 0.45)
		StatType.MAX_ENERGY: return Color(0.75, 0.35, 0.95)
		StatType.CRIT:       return Color(0.95, 0.85, 0.20)
	return Color(0.75, 0.75, 0.75)
