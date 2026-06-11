## EnemyData
## Defines stats and AI type for each enemy. Loaded from data/enemies/enemies.json.
## Use by_node_type() to get the right enemy for a map node, and create_ai() to
## instantiate the matching AI.
class_name EnemyData
extends Resource

static var _cache: Array = []

static func all() -> Array:
	if _cache.is_empty():
		_cache = _load_json()
	return _cache

static func by_id(p_id: StringName) -> EnemyData:
	for ed in all():
		if (ed as EnemyData).id == p_id:
			return ed
	return null

## Returns the right enemy definition for a given map node type.
static func by_node_type(type: int) -> EnemyData:
	match type:
		MapNode.Type.BOSS:  return by_id(&"big_boss")
		MapNode.Type.ELITE: return by_id([&"swordsman", &"bowman"].pick_random())
		_:                  return by_id([&"swordsman", &"bowman"].pick_random())

## Instantiates the correct EnemyAI subclass for a given ai_type string.
static func create_ai(ai_type: String) -> EnemyAI:
	match ai_type:
		"archer": return EnemyAI.ArcherAI.new()
		"boss":   return EnemyAI.BossAI.new()
		_:        return EnemyAI.new()

static func _load_json() -> Array:
	var file := FileAccess.open("res://data/enemies/enemies.json", FileAccess.READ)
	if file == null:
		push_error("EnemyData: cannot open res://data/enemies/enemies.json")
		return []
	var data = JSON.parse_string(file.get_as_text())
	if not data is Array:
		push_error("EnemyData: enemies.json root must be an array")
		return []
	var result: Array = []
	for d in data:
		result.append(_from_dict(d))
	return result

static func _from_dict(d: Dictionary) -> EnemyData:
	var ed := EnemyData.new()
	ed.id           = StringName(d.get("id", ""))
	ed.enemy_name   = d.get("enemy_name", "Enemy")
	ed.max_hp       = d.get("max_hp", 30)
	ed.max_energy   = d.get("max_energy", 6)
	ed.start_energy = d.get("start_energy", 3)
	ed.energy_regen = d.get("energy_regen", 2)
	ed.ai_type      = d.get("ai_type", "aggressive")
	ed.attack_id    = StringName(d.get("attack_id", "slash"))
	ed.recover_id   = StringName(d.get("recover_id", "focus"))
	return ed

@export var id: StringName = &""
@export var enemy_name: String = "Enemy"
@export var max_hp: int = 30
@export var max_energy: int = 6
@export var start_energy: int = 3
@export var energy_regen: int = 2
@export var ai_type: String = "aggressive"
@export var attack_id: StringName = &"slash"
@export var recover_id: StringName = &"focus"
