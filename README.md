# CardGame — Inuyasha-inspired Turn-Based Card Game

A Godot 4.6 roguelike deckbuilder. **WeGo** (simultaneous-planning) combat on a 3×3 grid, with Slay-the-Spire-style run progression across a radial map.

## Gameplay

- **Combat** — Plan up to 3 ordered actions each round, then lock in and watch them resolve simultaneously against the enemy. Moves resolve before attacks within each slot.
- **Map** — Travel a radial node graph: `START → 5 fights → 7 mixed nodes → BOSS`. A node is reachable once it connects to a node you've already visited.
- **Deck** — Draw/discard hand of 5 cards, plus a permanent tray of directional move cards. Earn card and equipment rewards after each victory.
- **Equipment** — 5 slots (weapon, offhand, chest, helm, shoes) granting damage, block, HP, energy, and crit bonuses.
- **Events** — Forge cards to boost damage, remove weak cards, or scavenge ruins for equipment.

## Turn loop

`PLAN → RESOLVE → CLEANUP → PLAN …`

- **PLAN** — drag cards into 3 ordered slots (left-to-right, no gaps); Lock In begins resolution.
- **RESOLVE** — slots resolve 0→1→2, moves before attacks, death checked between slots.
- **CLEANUP** — played cards fly to discard, energy regens, hand refills, loop repeats.

## Project structure

```
scenes/        map, battlefield, tokens, cards, hand, HUD, UI
scripts/
  game_state.gd   autoload — persists coins, deck, map, equipment across scenes
  map/            map generation, traversal, battlefield turn loop, board, tokens
  battle/         deck, hand, move pool, planning slots
  cards/          card visuals + CardData resource
  equipment/      EquipmentData resource
  ui/             HUD, card viewer
data/           card and equipment resource definitions (.tres)
```

See [CLAUDE.md](./CLAUDE.md) for detailed architecture notes.

## Running

Open the project in **Godot 4.6** and run the main scene (`scenes/map/map.tscn`).

## Built with

- [Godot Engine 4.6](https://godotengine.org/)
- `simple_cards` / `godot_card_layout` addon for card layout and drag-drop

## License

MIT — see [LICENSE](./addons/godot_card_layout/LICENSE.md).
