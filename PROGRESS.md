# 프로젝트 진행 상황 (Project Progress)

> Living document — we update this as we build. Last updated: **2026-05-29**

## 1. Overview
A **2D turn-based card game**, inspired by the Inuyasha flash card game.
- **Engine:** Godot 4.6 (Forward+, GDScript)
- **First milestone:** Single-player vs AI (no networking yet)
- **Long-term goal:** Co-op PvE
- **Workflow:** Step-by-step, learning Godot along the way (coming from Unreal)

## 2. Decisions locked in
| Topic | Decision | Date |
|-------|----------|------|
| Dimension | 2D | 2026-05-29 |
| First opponent | Single-player vs AI | 2026-05-29 |
| Language | GDScript | 2026-05-29 |
| Order of work | Card + Map design first, logic after | 2026-05-29 |
| Art style | **Pixel art** (low effort, big free-asset supply) | 2026-05-29 |
| Resolution | Design at **1280×720** (16:9), stretch canvas_items / keep | 2026-05-29 |
| Turn system | **WeGo (simultaneous)**: 3 cards/turn, resolve **slot-by-slot** | 2026-05-29 |
| Enemy info | **Hidden** until reveal (no telegraph) | 2026-05-29 |
| Movement | **Free**, in a separate **movement tray** (NOT the hand), pops in plan phase | 2026-05-29 |
| Resource | **Energy pool** gates combat cards + energy-regen cards | 2026-05-29 |

## 3. Folder structure
```
새 게임 프로젝트/
├─ scenes/        # .tscn scene files (the "things" in the game)
│  ├─ cards/      #   card visuals
│  ├─ battle/     #   the battle/board scene
│  ├─ map/        #   overworld / level map
│  └─ ui/         #   menus, HUD
├─ scripts/       # .gd code files
│  ├─ cards/
│  ├─ battle/
│  ├─ map/
│  └─ autoload/   #   global singletons (like Unreal GameInstance/GameState)
├─ data/          # game data as Godot Resources (.tres)
│  ├─ cards/      #   one file per card definition
│  └─ enemies/
└─ assets/        # art, fonts, audio
   ├─ art/ (cards, characters, map, ui)
   ├─ fonts/
   └─ audio/ (sfx, music)
```

## 3b. Art guidelines (Pixel art)
**Engine is configured for pixel art:** texture filter = Nearest, stretch = canvas_items/keep.

**Design resolution:** 1280×720 (16:9). Set in Project Settings → Display → Window
(Viewport 1280×720, Stretch mode `canvas_items`, Aspect `keep`).

**Approach:** high-res 16:9 canvas (1280×720) with crisp UI text, and *small* pixel
sprites scaled up by whole numbers (×2, ×3, ×4) so pixels stay square. This keeps card
text readable while art stays pixel-crunchy.

**Recommended sprite sizes (native, before scaling):**
| Asset | Size | Notes |
|-------|------|-------|
| Board space icon / tile | 16×16 or 32×32 | |
| Character token (on board) | 32×32 or 32×48 | |
| Card illustration (inside frame) | 64×64 or 80×80 | |
| Card frame (UI) | designed at 150×210 | can be crisp, not pixel |

**Cohesion rule:** pick ONE fixed palette and use it for everything — even art from
different sources will match. Good starter palettes: *AAP-64*, *Endesga 32 (EDG32)*,
*Resurrect 64*, *Sweetie 16*.

**Where to get free assets (check license — prefer CC0):**
- **Kenney.nl** — CC0, no attribution, includes UI/card kits
- **itch.io** — search "pixel art asset pack" (many free); good for characters/tiles
- **OpenGameArt.org** — large library
- Theme searches: "feudal japan pixel", "samurai pixel", "rpg pixel characters"

**Editing tools (if needed):** LibreSprite (free) or Aseprite (paid).

## 3c. Game design — the core loop
**Type:** 2D grid card-battler with **WeGo (simultaneous)** resolution. Both sides commit
secretly, then everything plays out together. Symmetric → fair for future multiplayer.

### Turn loop
1. **PLAN** (both sides at once, **hidden**): each side places up to **3 cards** into 3
   ordered slots, then "Lock In". The AI commits blind; its cards stay hidden until reveal.
2. **RESOLVE**: slots play out **one at a time** (slot 1 → 2 → 3). Within a slot, both
   sides' cards happen together, and **moves resolve before attacks**.
   - **Death is checked between slots.** If a side hits 0 HP in slot 1, slots 2–3 are
     cancelled and the battle **ends immediately**.
   - **Mutual kill = draw** (both can take damage in the same slot).
3. **CLEANUP**: move cards stay in hand; damage/skill cards → discard; **energy regens**
   a little; draw back up to hand size.

### Cards & resources
- **Movement is NOT in the hand.** It lives in its own **movement tray** that appears
  during the plan phase (directional + specials like double-dash, horizontal). Free, always
  available — a bad draw can never strand the player, and the hand stays uncluttered as more
  move types are added.
- **The hand holds only ATTACK / MAGIC cards** drawn from the deck (these cost energy).
- A slot can be filled by **either** a move (from the tray) **or** a card (from the hand).
- **Energy/mana pool** gates damage & skill cards (stops attack-spamming).
  - Starting values (**TUNABLE**): max **10**, start **5**, **+2 regen per cleanup**.
  - Example costs: basic attack 3, strong attack 5, same-cell special 6.
  - **Energy-regen cards**: spend a slot to restore energy (e.g. **+4**).
  - (Same system on a 0–100 scale if preferred: max 100, regen ~15/cleanup.)
- So: **3 slots/turn** = how many actions; **energy** = whether you can afford combat ones.

### Grid interaction
- Tokens **can share a cell** (no bounce-back).
- **Same-cell special attack**: a card that triggers when player & enemy are on the same cell.
- Attacks will have grid range/patterns (adjacent / line / area) — positioning decides hits.
- The enemy plays move + attack cards from its **own** hand, just like the player.

## 4. Roadmap
### Phase 0 — Foundation  ⏳ in progress
- [x] Folder structure
- [x] Progress doc
- [x] `CardData` resource (the data shape of a card) — *draft, will refine once mechanics are known*
- [x] `Card` visual scene + script
- [x] Battlefield/map design (landscape background + **grid** board)
  - `scenes/map/battlefield.tscn`, `scripts/map/board.gd`
  - Board = a **chess-like grid** (default 3×3), cells addressed by (col, row); draws live in editor (`@tool`)
  - Landscape is a placeholder ColorRect for now — swap in art later

### Phase 0.5 — Tokens on the board  ✅
- [x] Reusable `Token` scene + script (`scenes/map/token.tscn`, `scripts/map/token.gd`)
  - Team-colored pixel placeholder; accepts real `sprite_texture` later
  - `move_to_cell(Vector2i)` — animates between cells at runtime, snaps in editor
- [x] Battlefield places tokens on their `start_cell` (live in editor) via `battlefield.gd`
- [x] Player (Inuyasha, left-middle `(0,1)`) + Enemy (right-middle `(2,1)`) on the 3×3 grid

### Phase 1 — Card system  ⏳ in progress
- [x] `CardData` learned a **MOVE** action (`move_direction: Vector2i`, type `MOVE`)
- [x] Four directional card assets: Up/Down/Left/Right (`data/cards/move_*.tres`)
- [x] Cards are **clickable** (emit `played`) with hover feedback — *click-to-play*
- [x] **Hand** at bottom of battlefield (`scenes/battle/hand.tscn`) shows the cards
- [x] Playing a direction card moves the player token on the grid (clamped at edges)
- [ ] Finalize remaining card data fields once combat mechanics are described
- [ ] (Later) drag-and-drop for targeted cards

### Phase 2 — Battle state (HP / energy / deck)
- [x] HP + energy on tokens (data + signals) — `take_damage/heal/spend_energy/...`,
      `hp_changed`/`energy_changed`/`died`
- [x] **Tekken-style HUD** (`scenes/ui/combatant_hud.tscn`) — player top-left, enemy
	  top-right (mirrored, drains toward center); binds to a token's signals
- [x] **Deck** (`scripts/battle/deck.gd`): draw pile + discard, reshuffle when empty
- [x] Hand fills from the deck up to hand size (5); playing a card consumes it → discard
- [x] **Energy** spend on combat cards (`can_afford`/`spend_energy`); **Focus** regen card
- [x] TEMP **End Turn** button: regen energy + draw back up; deck/discard counter label
- [x] Sample combat cards: **Slash** (cost 3, dmg 6), **Heavy Slash** (cost 5, dmg 10),
	  **Focus** (cost 0, +4 energy). Attacks hit the **cell in front** (facing-based).

### Phase 3 — WeGo turn loop & AI
- [x] Movement tray (directional + specials) that pops in the plan phase — replaces the
	  TEMP arrow-key movement
- [x] 3-slot planning bar + "Lock In" (each slot = a move OR a hand card; click slot to clear)
- [x] Energy budget check while planning; real spend/regen during resolve/cleanup
- [x] Slot-by-slot resolution (symmetric engine): moves before attacks; death check between slots
- [x] Win / lose / **draw** banner
- [x] **(3b)** AI commits 3 cards blind: steps toward the player, attacks the cell in
	  front, Focuses when it can't afford an attack → real simultaneous combat
- [x] "Not enough energy!" toast (~2.5s) when an unaffordable card is dropped
- [ ] **(3c)** Attack cards with grid range/patterns (adjacent / line / area); same-cell special

### Phase 4 — Polish & later
- [ ] Art, animation, audio
- [ ] Co-op networking

## 5. Open questions (tuning / details, not blockers)
1. **Energy numbers** — exact max / start / regen, and card costs (current values are a
   starting guess; easy to retune). Small 0–10 scale or 0–100 scale.
2. **HP values** — player/enemy starting HP, attack damage amounts.
3. **Deck details** — deck size (~20–30), hand size, cards drawn per turn.
4. **Attack patterns** — which range shapes exist (adjacent / line / area / same-cell).
5. **Art** — landscape image + card art + character tokens (placeholders for now).

## 6. Progress log
- **2026-05-29** — Slots now fill **left-to-right only**: only the first empty slot accepts a
  drop; later empty slots are disabled (`set_droppable`) and dimmed. Prevents gap bugs.
- **2026-05-29** — Layout: moved **Lock In** above the Hide button (center), and split the
  pile counter into a **Discard pile** (bottom-left) and **Deck pile** (bottom-right), each a
  small panel showing its count.
- **2026-05-29** — Added a top-center bar between the HUDs: **Pause** (left, works while the
  tree is paused via PROCESS_MODE_ALWAYS + dim overlay), **Round N** (center, increments each
  turn), **Bag** (right, placeholder button → toast for now; will list all move + attack cards).
- **2026-05-29** — HUD now shows **energy as a number** (`X / Y`) under the bar. Hovering a
  card **previews its energy change on the player's energy bar**: a red chunk = energy to be
  spent, green chunk = energy to be gained. Card → HUD is decoupled via the
  `player_energy_hud` group + `set_energy_preview(delta)`.
- **2026-05-29** — Card UI (slots, hand, move pool, Lock In/Hide buttons) now **auto-hides
  during the RESOLVE phase** so the player just watches the fight, and reappears in PLAN
  (`_set_planning_ui_visible`).
- **2026-05-29** — **Step 3b**: enemy AI now fills `_enemy_plan` blind each turn (move
  toward player → attack cell-in-front → Focus if broke), so combat is truly simultaneous
  (trades + mutual-kill draws possible). Added a "Not enough energy!" center toast (~2.5s)
  when dropping an unaffordable card. The resolution engine was unchanged — just fed the
  enemy's plan, as designed.
- **2026-05-29** — **Step 3a polish 2**: slots now hold the **actual full-size card**
  (3 fixed card-sized slots). Hand cards move into the slot (return on clear); move cards
  **duplicate on drag** (original stays in the pool). Drag ghost is a full-size card. Added
  a **Hide** button (top-middle) that toggles the slots + move pool so you can see the board.
- **2026-05-29** — **Step 3a polish**: switched planning to **drag-and-drop** (Godot
  `_get_drag_data`/`_drop_data`). Move cards moved to a right-side **scrollable pool**
  (full-size, reusable, non-consumable); hand cards are consumable. Clearing a slot now
  **also clears every slot after it** (fixes the energy-dependency bug, e.g. Focus→Slash).
  New: `plan_slot.tscn/gd`, `move_pool.tscn/gd`; `card.gd` is now a drag source.
- **2026-05-29** — **Step 3a**: WeGo turn loop foundation. Added Phase state (PLAN/RESOLVE),
  a **movement tray** + **3 plan slots** + **Lock In**; clicking a hand card or move queues
  it into a slot (energy budget-checked). Built the **symmetric slot-by-slot resolution
  engine** (moves before attacks, death check between slots) and cleanup (discard/regen/
  redraw) + win/lose/draw banner. Enemy plan still empty — AI comes in 3b.
- **2026-05-29** — Project kickoff. Confirmed 2D / vs-AI / step-by-step. Created folder
  structure, this progress doc, and draft Card data + visual scene.
- **2026-05-29** — Clarified "map" = the battlefield (landscape + traversable board path).
  Built `battlefield.tscn` with a placeholder landscape and a self-drawing `Board` (path of
  spaces connected by lines, editable live in the editor).
- **2026-05-29** — Chose **pixel art**. Configured project for it (Nearest texture filter,
  canvas_items stretch / keep aspect). Added art guidelines: sprite sizes, fixed-palette
  rule, free asset sources.
- **2026-05-29** — Added reusable `Token` scene (placeholder pixel square, team color,
  `move_to_cell` with tween). Battlefield snaps tokens to board cells live in editor.
  Instanced a player (Inuyasha) and enemy token into the battlefield.
- **2026-05-29** — Reworked board from a path into a **chess-like grid** (3×3). Tokens now
  sit on grid cells; player on left-middle, enemy on right-middle.
- **2026-05-29** — Brought cards into the battlefield. Added MOVE card type + 4 directional
  cards (Up/Down/Left/Right). Chose **click-to-play** interaction. Cards are clickable and
  the Hand shows them at the bottom; clicking a card moves the player token that direction
  on the grid (edge moves are ignored). Run `scenes/map/battlefield.tscn` (F6) to play.
- **2026-05-29** — Chose **1280×720** design resolution. Updated battlefield background to
  1280×720 and recentered the board at (640, 360). (Viewport size to be set in Project
  Settings UI, since the editor reverts external project.godot edits.)
- **2026-05-29** — **Locked the core game design** (see §3c). WeGo simultaneous play: both
  sides commit 3 hidden cards, resolve slot-by-slot (moves before attacks), death checked
  between slots (early-out on slot-1 kill), mutual kill = draw. Tokens can share a cell;
  planned same-cell special attack. Energy pool gates combat cards (+ energy-regen cards);
  move cards free & permanent in hand. Enemy = symmetric, plays its own cards, hidden.
- **2026-05-29** — **Step 1**: added HP + Energy to `Token` (stats, methods, signals).
  Added TEMP debug keys in `battlefield.gd` (1/2 damage, 3/4 energy) — remove when the real
  turn loop lands.
- **2026-05-29** — Moved HP/energy off the tokens into a **Tekken-style HUD** in the top
  corners (`scenes/ui/combatant_hud.tscn`, reusable, `mirrored` flag for the enemy).
  Battlefield binds each HUD to its token.
- **2026-05-29** — Design change: **movement leaves the hand** → own tray that pops in the
  plan phase; hand is now attack/magic only. Cleared the hand of move cards; movement is on
  the **arrow keys** temporarily until the tray is built in Step 3.
- **2026-05-29** — **Step 2**: deck/energy economy. Added `Deck` (draw/discard + reshuffle),
  hand draws from it to size 5, playing a combat card spends energy + discards it. Sample
  cards Slash / Heavy Slash / Focus; attacks hit the **cell in front** (token `get_facing`).
  TEMP End-Turn button (regen energy + redraw) and a deck/discard counter. Still IGoUGo /
  immediate-play — Step 3 swaps in the real WeGo loop.
