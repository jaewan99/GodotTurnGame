## MapGenerator
## Builds a radial "mind-map" graph for one floor.
##   Ring 0 (1 node)  — START at screen centre
##   Ring 1 (5 nodes) — all FIGHT, radius 190
##   Ring 2 (7 nodes) — mixed types,  radius 380
##   Boss   (1 node)  — BOSS, radius 540, random outer angle
##
## Connections:
##   START → all ring-1
##   Each ring-1 → 2 nearest ring-2
##   3 nearest ring-2 → BOSS
##   ~35 % chance of a same-ring lateral edge for the web feel
class_name MapGenerator
extends RefCounted

static func generate(rng_seed: int = 0) -> Array[MapNode]:
	var rng := RandomNumberGenerator.new()
	if rng_seed == 0:
		rng.randomize()
	else:
		rng.seed = rng_seed

	var cx := 960.0
	var cy := 540.0
	var center := Vector2(cx, cy)

	var nodes: Array[MapNode] = []

	# ── Ring 0: START ────────────────────────────────────────────────────────
	var start := _node(0, MapNode.Type.START, center)
	start.visited = true
	nodes.append(start)

	# ── Ring 1: 5 FIGHT nodes ────────────────────────────────────────────────
	var r1_ids: Array[int] = []
	var r1_count := 5
	for i in r1_count:
		var angle := (TAU / r1_count) * i + rng.randf_range(-0.25, 0.25)
		var n := _node(nodes.size(), MapNode.Type.FIGHT,
				center + Vector2(cos(angle), sin(angle)) * 190.0)
		r1_ids.append(n.id)
		nodes.append(n)

	# ── Ring 2: 7 mixed nodes ────────────────────────────────────────────────
	var r2_types: Array = [
		MapNode.Type.FIGHT, MapNode.Type.FIGHT,
		MapNode.Type.EVENT, MapNode.Type.EVENT,
		MapNode.Type.SHOP,  MapNode.Type.REST,
		MapNode.Type.ELITE,
	]
	_shuffle(r2_types, rng)

	var r2_ids: Array[int] = []
	var r2_count := r2_types.size()
	for i in r2_count:
		var angle := (TAU / r2_count) * i + rng.randf_range(-0.18, 0.18)
		var n := _node(nodes.size(), r2_types[i],
				center + Vector2(cos(angle), sin(angle)) * 380.0)
		r2_ids.append(n.id)
		nodes.append(n)

	# ── Boss node ─────────────────────────────────────────────────────────────
	var boss_angle := rng.randf_range(0.0, TAU)
	var boss := _node(nodes.size(), MapNode.Type.BOSS,
			center + Vector2(cos(boss_angle), sin(boss_angle)) * 540.0)
	nodes.append(boss)

	# ── Connections ──────────────────────────────────────────────────────────

	# START → all ring-1
	for id in r1_ids:
		_connect(nodes[0], nodes[id])

	# Ring-1 → 2 nearest ring-2 each
	for id1 in r1_ids:
		var sorted := r2_ids.duplicate()
		sorted.sort_custom(func(a, b):
			return nodes[id1].pos.distance_to(nodes[a].pos) \
				 < nodes[id1].pos.distance_to(nodes[b].pos))
		for k in mini(2, sorted.size()):
			_connect(nodes[id1], nodes[sorted[k]])

	# 3 nearest ring-2 → BOSS
	var r2_by_boss := r2_ids.duplicate()
	r2_by_boss.sort_custom(func(a, b):
		return nodes[a].pos.distance_to(boss.pos) \
			 < nodes[b].pos.distance_to(boss.pos))
	for k in mini(3, r2_by_boss.size()):
		_connect(nodes[r2_by_boss[k]], boss)

	# Lateral edges within ring-1 (adjacent pairs)
	for i in r1_ids.size():
		if rng.randf() < 0.35:
			_connect(nodes[r1_ids[i]], nodes[r1_ids[(i + 1) % r1_ids.size()]])

	# Lateral edges within ring-2 (adjacent pairs)
	for i in r2_ids.size():
		if rng.randf() < 0.30:
			_connect(nodes[r2_ids[i]], nodes[r2_ids[(i + 1) % r2_ids.size()]])

	return nodes


# ── Helpers ───────────────────────────────────────────────────────────────────

static func _node(id: int, type: MapNode.Type, pos: Vector2) -> MapNode:
	var n := MapNode.new()
	n.id   = id
	n.type = type
	n.pos  = pos
	return n


static func _connect(a: MapNode, b: MapNode) -> void:
	if not a.connections.has(b.id):
		a.connections.append(b.id)
	if not b.connections.has(a.id):
		b.connections.append(a.id)


static func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]; arr[i] = arr[j]; arr[j] = tmp
