# CardGame — Godot 4.6 Project

Inuyasha-inspired turn-based card game. WeGo (simultaneous) combat on a grid (Board defaults to 3×3, but `battlefield.tscn` overrides it to **5×3**), Slay-the-Spire-style run progression on a radial map.

## Quick file map

```
scenes/map/
  map.tscn          ← overworld (main scene)
  battlefield.tscn  ← battle arena
  token.tscn        ← player/enemy combatant piece
scenes/battle/
  hand.tscn         ← 5-card arc at the bottom
  move_pool.tscn    ← 4 directional cards (non-consumable)
  plan_slot.tscn    ← drag-drop planning slot
scenes/cards/
  card.tscn         ← visual card node (200×300, anchor-based layout, japan frame)
scenes/ui/
  combatant_hud.tscn
  card_viewer.tscn  ← modal card browser (bag/deck/discard)

scripts/
  game_state.gd     ← AUTOLOAD: persists coins, deck, map_nodes, current_node_id, cards_removed, equipment
  equipment/
    equipment_data.gd ← EquipmentData Resource (Slot enum, stat fields). ALL_PATHS = full reward pool.
  map/
    map.gd          ← map scene controller + event overlay (forge, remove, scavenge) + equipment panel
    map_generator.gd← radial graph builder (5+7+1 nodes)
    map_node.gd     ← MapNode Resource (id, type, pos, connections, visited)
    map_node_ui.gd  ← circular Button per node (visited/reachable/locked states)
    battlefield.gd  ← battle controller + WeGo turn loop. Joins "battlefield" group for range highlight.
    board.gd        ← grid (@tool, configurable columns/rows; 5×3 in battle). highlight_cells() / clear_highlight() for card range preview.
    token.gd        ← combatant (HP, energy, block, movement, facing) + character-art layout. current_cell: Vector2i.
  battle/
    deck.gd         ← draw/discard pile (auto-reshuffle when draw empty)
    hand.gd         ← 5-card arc layout manager
    move_pool.gd    ← permanent directional card tray
    plan_slot.gd    ← drop target + clear-downstream logic
  cards/
    card.gd         ← GameCard extends simple_cards.Card (drag, shine, tilt, range preview)
    card_data.gd    ← CardData Resource (id, name, cost, type, damage, affected_cells, art, level, etc.)
  ui/
    combatant_hud.gd← HP/energy bars + energy preview on card hover
    card_viewer.gd  ← modal card grid viewer

assets/cards/
  japan_warrior/
    japan_front.png       ← card frame (842×1264, transparent center, ratio 1:1.5)
    japan_back.png        ← face-down card back
    portrait/
      slash1.png          ← default portrait (used by slash + heavy_slash)
  general/
    energyicon.png        ← blue hex gem shown next to cost number

data/cards/
  cards.json        ← all card definitions (id, cost, type, damage, affected_cells, art path, etc.)
```

## Card visual system

### card.tscn / card.gd
`GameCard` extends `simple_cards.Card` (a Button). All visuals are **direct children** with anchor-based layout — changing `card_size` (export) resizes everything proportionally.

Default size: **200×300** (matches japan_front.png 1:1.5 ratio).

Node tree:
```
Card (Button)
  Art         ← portrait TextureRect, drawn behind frame
  Frame       ← japan_front.png overlay (full card)
  NameLabel   ← top strip between pillars
  EnergyIcon  ← blue gem TextureRect, top-left
  CostLabel   ← child of EnergyIcon, cost number
  DescriptionLabel ← lower panel, full width
  Shine       ← ColorRect with card_shine.gdshader, topmost
```

`_setup_layout()` is a no-op — bypasses simple_cards SubViewport registry entirely. Art and labels are populated by `_refresh()` from `CardData`.

**Resizing**: set `card_size` export or `custom_minimum_size` in the scene. All children reflow via anchors automatically.

### CardData (card_data.gd)
Loaded from `data/cards/cards.json` via `CardData.all()` (cached). Key fields:
- `affected_cells: Array[Vector2i]` — cells hit relative to player (0,0). y=-1=up, y=+1=down.
- `art: Texture2D` — loaded from `"art"` path in JSON. Falls back to `slash1.png` if null.
- `level: int` — non-exported, starts 0; only live deck copies carry a level (forge system).
- MOVE cards: `affected_cells` auto-filled from `move_direction` if not set in JSON.

### Range highlight (board.gd + battlefield.gd)
When a card is hovered or dragged in the hand:
1. `card.gd._on_game_focused()` → `_send_range_preview(data)`
2. Finds `"battlefield"` group node → `battlefield.show_range_highlight(cd)`
3. Reads `_player.current_cell` → `board.highlight_cells(affected_cells, origin, is_move)`
4. `board.queue_redraw()` draws colored overlay on affected cells

Colors: 🔴 red = attack, 🟢 green = move. Clears on `card_unfocused`.

## Architecture

### Turn loop (battlefield.gd)
`PLAN → RESOLVE → CLEANUP → PLAN …`
- **PLAN**: player drags cards into 3 ordered slots (left-to-right, no gaps). Lock In triggers RESOLVE.
- **RESOLVE**: slots 0→1→2, moves before attacks per slot. Death checked between slots.
- **CLEANUP**: played cards fly to discard, energy regens, hand refills to 5, loop back to PLAN.
- `_game_over()`: on win → `_show_win_reward()` overlay; on lose/draw → banner label.

### Map traversal (map.gd)
A node is **reachable** if connected to at least one visited node and not yet visited itself.
Rings: START (1) → FIGHT×5 (r=190) → mixed×7 (r=380) → BOSS (r=540).

### Run persistence (GameState autoload)
`GameState` (scripts/game_state.gd) survives scene changes. Contains:
- `coins: int`
- `deck: Array[CardData]` — source of truth for the player's deck
- `map_nodes: Array[MapNode]` — generated once, reused on map re-entry (visited flags preserved)
- `current_node_id: int` — which node triggered the current battle
- `cards_removed: int` — counts Event-node removals; scales remove cost (`50 × (cards_removed + 1)`)

**Flow**: click node → `GameState.current_node_id = node.id` → battle scene → win → reward overlay → card chosen → `GameState.deck.append(cd.duplicate())` → return to map → map restores `_nodes = GameState.map_nodes`.

**Important**: every CardData added to `GameState.deck` must be `.duplicate()`d so each instance is independent (forge levels are per-instance, not per-template).

### Card reward (battlefield.gd `_show_win_reward`)
- Coins: FIGHT 30–50, ELITE 75–100, BOSS 150–200 (`randi_range`)
- Shows 3 shuffled cards from reward pool (cards with `"reward": true` in cards.json)
- Picking a card appends `cd.duplicate()` to `GameState.deck` and switches to map scene

### Equipment system
`EquipmentData` resource — 5 slots, one per slot can be equipped at a time (overwrites on re-equip):

| Slot | Stat | .tres |
|------|------|-------|
| WEAPON (0) | `damage_bonus` — added to every player attack | iron_sword (+3) |
| OFFHAND (1) | `block_per_turn` — block refreshed at round start | wooden_shield (+2) |
| CHEST (2) | `max_hp_bonus` — applied at battle start via `heal()` | leather_chest (+10) |
| HELM (3) | `max_energy_bonus` — applied at battle start via `gain_energy()` | iron_helm (+1) |
| SHOES (4) | `crit_chance` — % chance to double attack damage | swift_boots (+15%) |

`GameState.equipment: Dictionary` — int slot → EquipmentData (missing key = empty slot).

`battlefield._apply_equipment()` called at end of `_ready()` — reads GameState.equipment, boosts max_hp/max_energy, sets `_player_damage_bonus` and `_player_crit_chance`. Applied before `_begin_plan()`.

Block mechanics: `Token.block: int` absorbs damage before HP in `take_damage()`. `_begin_plan()` resets to 0 then sets `block = offhand.block_per_turn`.

Reward drops (battlefield `_show_win_reward`):
- FIGHT: 3 cards
- ELITE: 2 cards + 1 equipment
- BOSS: 1 card + 2 equipment

Equipment uses same flip-reveal mechanic as cards. "Equip" button calls `_on_equipment_chosen`, which sets `GameState.equipment[slot]` and returns to map.

### Event node (map.gd)
Two options presented as a full-screen overlay:

**Forge a Card** — `_build_forge_select` / `_build_forge_result`
- Cost: `50 × (card.level + 1)` coins per attempt
- Success rates (indexed by current level): `[100, 80, 65, 50, 35, 20, 10]`% (caps at 10% past lv6)
- On success: `card.damage += 2`, `card.level += 1`. On failure: `card.level += 1` only. Coins spent either way.
- `CardData.level: int` is a non-exported var (starts at 0 on all .tres templates; only live deck instances carry a level).

**Scavenge Ruins** — `_build_scavenge_result`
- Shows one random equipment piece (free)
- "Take it" sets `GameState.equipment[slot]` and calls `_refresh_equipment_panel()`

**Remove a Card** — `_build_remove_select`
- Cost: `50 × (GameState.cards_removed + 1)` coins (50g first, 100g second, …)
- Removes the chosen card from `GameState.deck`, increments `GameState.cards_removed`
- Disabled when deck size ≤ 1

### Drag-drop pattern (simple_cards addon)
Card `_get_drag_data()` → slot `_drop_data()`. Payload: `{ "data": CardData, "consumable": bool, "card": GameCard }`. Move cards are duplicated (non-consumable); hand cards transfer ownership.

### Key patterns
- `@tool` on Board, Token — live editor placement; gated with `if Engine.is_editor_hint(): return`
- Labels/Controls inside plan slots get `mouse_filter = MOUSE_FILTER_IGNORE` so clicks reach the slot
- Energy preview: cards emit hover signal → `player_energy_hud` group → HUD shows red/green chunk
- Range preview: cards emit hover signal → `battlefield` group → board draws cell overlay
- All overlays are built as `CanvasLayer` (layer 10) added directly to the scene; screens swap by calling `_clear_children(root)` then rebuilding
- Textures use `texture_filter = 4` (LINEAR_WITH_MIPMAPS) + `mipmaps/generate=true` in .import files

## Adding a new card
1. Add entry to `data/cards/cards.json` with `id`, `card_name`, `description`, `cost`, `type`, `affected_cells`, and optionally `art` (res:// path to portrait PNG)
2. Drop portrait PNG into `assets/cards/japan_warrior/portrait/` — Godot auto-imports it
3. If `"reward": true`, card appears in battle reward pool automatically

## What is NOT yet implemented
- Rest / Shop node logic (toast placeholder)
- Persistent save between app launches (GameState resets on quit)
- Win screen "Return to map" button after lose/draw
- Card upgrade display in HUD / card viewer (level is tracked but not shown on the card visual)
- Block is not shown in the HUD (functional but invisible to player)
- Equipment panel on map is display-only; no swapping/selling UI yet
- More equipment pieces (only 5 starter items)
- More card portraits (slash1.png used as fallback for all cards without art)
- Name banner and description banner PNG assets (planned, not yet created)
