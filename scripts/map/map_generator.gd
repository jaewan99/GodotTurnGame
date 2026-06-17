## MapGenerator
## Builds a radial "mind-map" graph for one floor with a variable number
## of rings (layers). Floor 1 has BASE_RINGS rings; each later floor adds one.
##
##   Ring 0 (1 node)      — START at screen centre
##   Ring 1               — inner combat ring (FIGHT, sprinkle of MYSTERY)
##   Rings 2..N           — mixed rings: guaranteed utilities + weighted fillers
##   Boss   (1 node)      — BOSS, one ring beyond the outermost
##
## Connections:
##   START → all ring-1
##   Each ring-r node → 2 nearest ring-(r+1) nodes
##   3 nearest outermost-ring nodes → BOSS
##   ~30 % chance of a same-ring lateral edge for the web feel
class_name MapGenerator
extends RefCounted

## Distance (px) between consecutive rings. The map's overall size is
## RING_SPACING × (ring count + 1); pan around it on the map screen.
const RING_SPACING := 190.0

## Number of rings on floor 1. Each floor past the first adds one more ring,
## so the map physically grows as the run progresses.
const BASE_RINGS := 3

## Weighted pool used to fill the non-guaranteed outer-ring slots.
## More entries = more likely to appear.
const FILLER_POOL: Array = [
	MapNode.Type.FIGHT,    MapNode.Type.FIGHT,   MapNode.Type.FIGHT,
	MapNode.Type.MYSTERY,  MapNode.Type.MYSTERY, MapNode.Type.MYSTERY,
	MapNode.Type.EVENT,    MapNode.Type.EVENT,
	MapNode.Type.TREASURE, MapNode.Type.TREASURE,
	MapNode.Type.GAMBLE,   MapNode.Type.GAMBLE,
	MapNode.Type.DOJO,
	MapNode.Type.BOUNTY,
	MapNode.Type.SHRINE,
]

## Chance (%) that the floor hides a SECRET node.
const SECRET_CHANCE := 70

static func generate(floor_num: int = 1, rng_seed: int = 0) -> Array[MapNode]:
	var rng := RandomNumberGenerator.new()
	if rng_seed == 0:
		rng.randomize()
	else:
		rng.seed = rng_seed

	var center := Vector2(960.0, 540.0)
	var nodes: Array[MapNode] = []

	# ── Ring 0: START ────────────────────────────────────────────────────────
	var start := _node(0, MapNode.Type.START, center)
	start.visited = true
	nodes.append(start)

	var ring_count := BASE_RINGS + (floor_num - 1)

	# ── Per-ring node counts (rings hold more nodes the further out) ─────────
	var ring_counts: Array[int] = []
	for r in range(1, ring_count + 1):
		ring_counts.append(rng.randi_range(4, 5) + r)

	# ── Types for outer rings (2..N): guaranteed utilities + fillers ─────────
	# Every floor always has shop/enchant/forge/rest; elites scale with floor.
	var outer_slots := 0
	for r in range(1, ring_count):
		outer_slots += ring_counts[r]
	var outer_types: Array = [
		MapNode.Type.SHOP, MapNode.Type.ENCHANT,
		MapNode.Type.FORGE, MapNode.Type.REST,
	]
	for i in floor_num:
		outer_types.append(MapNode.Type.ELITE)
	while outer_types.size() < outer_slots:
		outer_types.append(FILLER_POOL[rng.randi_range(0, FILLER_POOL.size() - 1)])
	outer_types.resize(outer_slots)
	_shuffle(outer_types, rng)

	# ── Spawn the rings ───────────────────────────────────────────────────────
	var rings: Array = []   # rings[r] = Array of node ids in ring r (0-based)
	var type_cursor := 0
	for r in ring_count:
		var count: int = ring_counts[r]
		var radius := RING_SPACING * (r + 1)
		var ids: Array = []
		for i in count:
			var t: MapNode.Type
			if r == 0:
				t = MapNode.Type.FIGHT
				if floor_num >= 2 and rng.randi_range(0, 99) < 20:
					t = MapNode.Type.MYSTERY
			else:
				t = outer_types[type_cursor]
				type_cursor += 1
			var angle := (TAU / count) * i + rng.randf_range(-0.2, 0.2)
			var n := _node(nodes.size(), t,
					center + Vector2(cos(angle), sin(angle)) * radius)
			if t not in [MapNode.Type.FIGHT, MapNode.Type.ELITE, MapNode.Type.BOSS]:
				n.always_accessible = true
			ids.append(n.id)
			nodes.append(n)
		rings.append(ids)

	# ── Boss node — one ring beyond the outermost ─────────────────────────────
	var boss_angle := rng.randf_range(0.0, TAU)
	var boss := _node(nodes.size(), MapNode.Type.BOSS,
			center + Vector2(cos(boss_angle), sin(boss_angle)) * (RING_SPACING * (ring_count + 1)))
	nodes.append(boss)

	# ── Secret node (maybe) — tucked between two random adjacent rings ────────
	# Invisible until an adjacent node is visited or an event marks it;
	# a faint glint hints at its position.
	if rng.randi_range(0, 99) < SECRET_CHANCE:
		var gap := rng.randi_range(0, ring_count - 2)
		var s_angle := rng.randf_range(0.0, TAU)
		var s_radius := RING_SPACING * (gap + 1.5)
		var secret := _node(nodes.size(), MapNode.Type.SECRET,
				center + Vector2(cos(s_angle), sin(s_angle)) * s_radius)
		nodes.append(secret)
		# Connect to the nearest node of each neighboring ring so it's discoverable.
		_connect(secret, nodes[_nearest(nodes, rings[gap], secret.pos)])
		_connect(secret, nodes[_nearest(nodes, rings[gap + 1], secret.pos)])

	# ── Connections ──────────────────────────────────────────────────────────

	# START → all ring-1
	for id in rings[0]:
		_connect(nodes[0], nodes[id])

	# Each ring-r node → 2 nearest ring-(r+1) nodes
	for r in range(ring_count - 1):
		for id in rings[r]:
			var sorted: Array = rings[r + 1].duplicate()
			var from_id: int = id
			sorted.sort_custom(func(a, b):
				return nodes[from_id].pos.distance_to(nodes[a].pos) \
					 < nodes[from_id].pos.distance_to(nodes[b].pos))
			for k in mini(2, sorted.size()):
				_connect(nodes[from_id], nodes[sorted[k]])

	# 3 nearest outermost-ring nodes → BOSS
	var outer: Array = rings[ring_count - 1].duplicate()
	outer.sort_custom(func(a, b):
		return nodes[a].pos.distance_to(boss.pos) \
			 < nodes[b].pos.distance_to(boss.pos))
	for k in mini(3, outer.size()):
		_connect(nodes[outer[k]], boss)

	# Lateral edges within each ring (adjacent pairs)
	for r in ring_count:
		var ids: Array = rings[r]
		for i in ids.size():
			if rng.randf() < 0.30:
				_connect(nodes[ids[i]], nodes[ids[(i + 1) % ids.size()]])

	return nodes


# ── Helpers ───────────────────────────────────────────────────────────────────

static func _node(id: int, type: MapNode.Type, pos: Vector2) -> MapNode:
	var n := MapNode.new()
	n.id   = id
	n.type = type
	n.pos  = pos
	return n


static func _nearest(nodes: Array[MapNode], ids: Array, pos: Vector2) -> int:
	var best: int = ids[0]
	for id in ids:
		if nodes[id].pos.distance_to(pos) < nodes[best].pos.distance_to(pos):
			best = id
	return best


static func _connect(a: MapNode, b: MapNode) -> void:
	if not a.connections.has(b.id):
		a.connections.append(b.id)
	if not b.connections.has(a.id):
		b.connections.append(a.id)


static func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]; arr[i] = arr[j]; arr[j] = tmp
