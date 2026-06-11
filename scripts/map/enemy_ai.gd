## EnemyAI
## Base AI: aggressive chaser. Moves toward the player each slot and attacks
## when adjacent. Subclasses override decide() for different behaviours.
class_name EnemyAI
extends RefCounted

const MAX_SLOTS := 3


func decide(enemy: Token, player: Token, moves_by_dir: Dictionary,
		attack: CardData, recover: CardData) -> Array:
	var plan: Array = []
	if enemy == null or player == null:
		return plan

	var facing     := enemy.get_facing()
	var sim_cell   := enemy.current_cell
	var sim_energy := enemy.energy

	for _i in range(MAX_SLOTS):
		if sim_cell + facing == player.current_cell:
			if sim_energy >= attack.cost:
				plan.append(attack)
				sim_energy -= attack.cost
			else:
				plan.append(recover)
				sim_energy += recover.energy_gain
		else:
			var mv := _move_toward(sim_cell, player.current_cell, moves_by_dir)
			if mv != null:
				plan.append(mv)
				sim_cell += mv.move_direction
			elif sim_energy >= attack.cost:
				plan.append(attack)
				sim_energy -= attack.cost
			else:
				plan.append(recover)
				sim_energy += recover.energy_gain

	return plan


func _move_toward(from: Vector2i, to: Vector2i, moves_by_dir: Dictionary) -> CardData:
	var dx := to.x - from.x
	var dy := to.y - from.y
	var dir := Vector2i.ZERO
	if absi(dx) >= absi(dy) and dx != 0:
		dir = Vector2i(signi(dx), 0)
	elif dy != 0:
		dir = Vector2i(0, signi(dy))
	if dir == Vector2i.ZERO:
		return null
	return moves_by_dir.get(dir) as CardData


# ── Archer AI ─────────────────────────────────────────────────────────────────
## Keeps its distance. Attacks with a ranged card from 1–2 cells away.
## Retreats when the player closes to melee range.
class ArcherAI extends EnemyAI:

	func decide(enemy: Token, player: Token, moves_by_dir: Dictionary,
			attack: CardData, recover: CardData) -> Array:
		var plan: Array = []
		if enemy == null or player == null:
			return plan

		var facing     := enemy.get_facing()
		var sim_cell   := enemy.current_cell
		var sim_energy := enemy.energy

		for _i in range(MAX_SLOTS):
			var diff          := player.current_cell - sim_cell
			var forward_dist  := diff.x * facing.x   # positive = player ahead
			var side_dist     := absi(diff.y)

			var in_range  := side_dist == 0 and forward_dist >= 1 and forward_dist <= 2
			var too_close := side_dist == 0 and forward_dist == 1

			if too_close:
				# Retreat one step away from the player.
				var away: CardData = moves_by_dir.get(Vector2i(-facing.x, 0))
				if away != null:
					plan.append(away)
					sim_cell += Vector2i(-facing.x, 0)
				elif sim_energy >= attack.cost:
					plan.append(attack)
					sim_energy -= attack.cost
				else:
					plan.append(recover)
					sim_energy += recover.energy_gain
			elif in_range and sim_energy >= attack.cost:
				plan.append(attack)
				sim_energy -= attack.cost
			else:
				var mv := _move_toward(sim_cell, player.current_cell, moves_by_dir)
				if mv != null:
					plan.append(mv)
					sim_cell += mv.move_direction
				elif sim_energy >= attack.cost:
					plan.append(attack)
					sim_energy -= attack.cost
				else:
					plan.append(recover)
					sim_energy += recover.energy_gain

		return plan


# ── Boss AI ───────────────────────────────────────────────────────────────────
## Waits until it can burst twice in a row, then unloads both attacks.
## Falls back to recovering when it can't afford the burst threshold.
class BossAI extends EnemyAI:

	func decide(enemy: Token, player: Token, moves_by_dir: Dictionary,
			attack: CardData, recover: CardData) -> Array:
		var plan: Array = []
		if enemy == null or player == null:
			return plan

		var facing     := enemy.get_facing()
		var sim_cell   := enemy.current_cell
		var sim_energy := enemy.energy

		for _i in range(MAX_SLOTS):
			var adjacent    := sim_cell + facing == player.current_cell
			var burst_ready := sim_energy >= attack.cost * 2

			if adjacent and burst_ready:
				plan.append(attack)
				sim_energy -= attack.cost
			elif adjacent:
				# Building up energy for the burst.
				plan.append(recover)
				sim_energy += recover.energy_gain
			else:
				var mv := _move_toward(sim_cell, player.current_cell, moves_by_dir)
				if mv != null:
					plan.append(mv)
					sim_cell += mv.move_direction
				elif sim_energy >= attack.cost:
					plan.append(attack)
					sim_energy -= attack.cost
				else:
					plan.append(recover)
					sim_energy += recover.energy_gain

		return plan
