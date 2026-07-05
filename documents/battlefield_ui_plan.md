# Battlefield UI overhaul plan (7/4)

Goal: bring the battle screen up to the same presentation level as the map —
fix the broken composition, replace the programmer-art HP bars with a lively
Diablo-style horizontal fluid bar, and add combat feedback.

## Problems observed (screenshot 7/4)

1. **Plan slots overlap the board.** `plan_bar.tscn` is anchored dead-center
   (960, 540) — the 3 stone card frames sit on top of the 5×3 grid.
2. **Enemy intent chips overlap the enemy HUD.** Chips are hardcoded at
   (1560, 66+) in `battlefield.gd:_show_enemy_intent`, colliding with the
   HUD bars (y 16–92).
3. **HUD labels collide.** "5 / 10" energy text sits on the bar edge; HP text
   floats far from the bar; no panel background so text fights the arena.
4. **Top bar is off-center and unstyled.** BattleHUD (Pause / Round 1 / bag)
   uses hardcoded offsets 780–1217, plain text, lowercase "bag".
5. **Flat olive background** (0.18, 0.23, 0.16) — clashes with the map's dark
   ink look.
6. **No combat feedback** — damage numbers, block visibility.

## Changes

### 1. Composition (battlefield.tscn)
- Background → dark ink `(0.075, 0.085, 0.115)` to match the map scene.
- PlanBar → right column: scale 0.7, moved beside the board
  (visual ~1345–1790 × 390–600). Board stays center stage.
- LockInButton → below the plan bar (right side, y ~630–850).
- BattleHUD → anchored top-center (anchor 0.5, offsets ±220).

### 2. Fluid HP bar (`shaders/fluid_bar.gdshader`)
Horizontal liquid, Diablo-orb feel:
- Wavy fill front (two overlaid sines, amplitude scales toward mid-fill).
- Depth gradient (dark at bottom), moving slosh highlight bands, edge glow
  at the liquid front, procedural drifting bubbles.
- **Ghost damage trail**: red-tinted segment between current HP and a
  `ghost` value that lerps down after hits (classic fighting-game drain).
- `mirrored` uniform so the enemy bar drains toward screen center.
- Same shader reused for the energy bar (blue palette, calmer amplitude,
  no ghost).

### 3. CombatantHUD redesign (combatant_hud.gd)
- Translucent rounded panel behind everything (same style family as map HUD).
- Row 1: name (side) + HP numbers (opposite).
- HP fluid bar (26 px), energy fluid bar (14 px) with small energy text.
- **Block badge**: shield chip at the bar's inner end, visible when block > 0
  (fixes "block is invisible" from the backlog). Token gains a
  `block_changed` signal.
- Energy preview chunks (card-hover) preserved, drawn on an overlay child.

### 4. Enemy intent chips (battlefield.gd)
- Moved below the enemy HUD (y ~150), aligned to its left edge, same chip
  styling but consistent with the HUD panel look.

### 5. Combat feedback (battlefield.gd + token.gd)
- Floating damage numbers on `Token.hit` (red, drift up, fade).
- Heal/energy floaters where applicable.
- Existing red hit-flash kept.

## Later / not in this pass
- Arena background art (texture slot like the map's `background_texture`).
- Marching-ants animation on reachable plan flow, phase transition banner.
- Card hover zoom in hand; deck/discard pile counters restyle.
