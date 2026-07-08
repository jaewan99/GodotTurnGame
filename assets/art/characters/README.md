# Character animation guide

The battlefield player/enemy pieces (`scenes/map/token.tscn` → `scripts/map/token.gd`)
now render an **`AnimatedSprite2D`** driven by a **`SpriteFrames`** resource.
Until you assign one, they fall back to the old colored placeholder box, so the
game keeps running while you add art incrementally.

Art is authored **facing RIGHT**. The token flips horizontally on its own when it
faces left, so you only draw/animate one direction.

## 1. Drop your frames in

Put each animation's PNG frames in its folder (name them so they sort in order,
e.g. `idle_00.png`, `idle_01.png`, …). You can also use a single sprite sheet if
you prefer — Godot's SpriteFrames editor can slice it.

```
assets/art/characters/
  player/
    idle/          ← REQUIRED. Loops. The default pose.
    slash/         ← plays when the "slash" card resolves
    heavy_slash/   ← plays when the "heavy_slash" card resolves
    focus/         ← plays when the "focus" (SKILL) card resolves
    move/          ← plays when any move card resolves
    hurt/          ← plays when hit (and survives)
    death/         ← plays when HP hits 0 (does NOT loop back to idle)
  enemy/
    idle/          ← REQUIRED. Loops.
    attack/        ← generic attack (enemy has no per-card art)
    move/
    hurt/
    death/
```

## 2. Animation names → what triggers them

The token picks an animation for a played card like this
(`token.gd` → `_anim_for_card`):

1. An animation **named exactly after the card id** — `slash`, `heavy_slash`,
   `focus` (see `data/cards/cards.json` for ids). Use these for bespoke moves.
2. Otherwise a **generic per-type** animation: any ATTACK → `attack`,
   any SKILL → `focus`, any MOVE → `move`.

So the enemy only needs `attack`; the player can have `slash` / `heavy_slash`
for distinct swings but will use `attack` for anything you didn't make art for.
Plus the automatic ones: `idle`, `hurt`, `death`. **Any animation you don't
create is simply skipped** — no crash, it just stays on idle.

| Animation   | Loops? | Fired by                                      |
|-------------|--------|-----------------------------------------------|
| `idle`      | ✅ yes | default / after any one-shot finishes         |
| `slash`     | no     | `slash` card                                  |
| `heavy_slash`| no    | `heavy_slash` card                            |
| `focus`     | no     | `focus` card (and any other SKILL fallback)   |
| `attack`    | no     | any ATTACK card with no id-specific animation |
| `move`      | no     | any move card                                 |
| `hurt`      | no     | taking damage and surviving                   |
| `death`     | no     | HP reaches 0 (stays on last frame)            |

## 3. Build the SpriteFrames resource (in the Godot editor)

1. Open `scenes/map/battlefield.tscn`.
2. Select `Board/PlayerToken`. In the Inspector find the script's **`Frames`**
   property (a `SpriteFrames` slot). Click it → **New SpriteFrames**, then click
   the resource to open the **SpriteFrames** panel at the bottom.
3. In that panel: use the "+" to add an animation, **rename it exactly** to one
   of the names in the table above (e.g. `idle`). Click "Add frames from files"
   (the film-strip icon) and pick that animation's PNGs, or "Add frames from
   sprite sheet".
4. Set the **FPS** and toggle **Loop** — ON for `idle`, **OFF** for every
   one-shot (`slash`, `hurt`, `death`, …). Only `idle` loops.
5. Repeat for each animation. When done, right-click the SpriteFrames resource
   → **Save As** into e.g. `assets/art/characters/player/player_frames.tres` so
   it's reusable.
6. Repeat 2–5 for `Board/EnemyToken` (or duplicate the .tres and swap frames).

That's it — press Play. Cards will drive the matching animation and the piece
returns to `idle` automatically. Tune position/scale with the token's transform
in the scene if the art size differs from the old 48px box.
