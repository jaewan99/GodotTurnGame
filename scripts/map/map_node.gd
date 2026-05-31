class_name MapNode
extends Resource

enum Type { START, FIGHT, ELITE, SHOP, REST, EVENT, BOSS }

var id: int = 0
var type: Type = Type.FIGHT
var pos: Vector2 = Vector2.ZERO
var connections: Array[int] = []
var visited: bool = false
