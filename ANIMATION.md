# Character Animation Guide (start here if you're new to this)

This explains, step by step, how to turn the battlefield player/enemy pieces from
plain colored boxes into real animated characters. No prior animation experience
needed — just follow it top to bottom.

---

## 0. The 30-second mental model

- A character animation in Godot 2D is just **a list of images (frames) shown in
  order fast**, like a flipbook. `idle_00.png → idle_01.png → idle_02.png …`
- All the frames for one character live in a single **`SpriteFrames`** resource.
  Inside it you make several named animations: `idle`, `slash`, `hurt`, etc.
- The game piece (the "token") shows that `SpriteFrames` with an
  **`AnimatedSprite2D`** node. The code I wired up tells it *which* animation to
  play and *when* (e.g. play `slash` when you play the Slash card).
- **You provide the images. Godot + the code do the rest.** Until you add images,
  the game still runs and just shows the old colored box — nothing breaks.

Art is drawn **facing RIGHT**. The piece flips itself when facing left, so you
only ever animate one direction.

---

## 1. Where your image files go

I already made these folders. Put your PNG frames inside the matching one:

```
assets/art/characters/
  player/
    idle/          REQUIRED. The default standing/breathing loop.
    slash/         plays when the Slash card resolves
    heavy_slash/   plays when the Heavy Slash card resolves
    focus/         plays when the Focus card resolves
    move/          plays when a move card resolves
    hurt/          plays when hit and survives
    death/         plays when HP hits 0 (freezes on last frame)
  enemy/
    idle/          REQUIRED.
    attack/        the enemy's generic attack
    move/
    hurt/
    death/
```

**Naming:** name frames so they sort in order — `idle_00.png`, `idle_01.png`,
`idle_02.png`, … Two digits keeps them ordered past 9 frames.

You can instead use **one sprite sheet image** (all frames in a grid in a single
PNG). Godot can slice it — covered in step 3.

**Minimum to see something working:** just `player/idle` and `enemy/idle`.
Everything else is optional and can be added later, one animation at a time.

---

## 2. Which animation plays when (the naming rules)

The code chooses a card's animation like this:

1. First it looks for an animation **named exactly after the card's id** —
   `slash`, `heavy_slash`, `focus`. (Ids live in `data/cards/cards.json`.)
2. If there isn't one, it uses a **generic fallback by card type:**
   - any ATTACK card → `attack`
   - any SKILL card  → `focus`
   - any MOVE card   → `move`

Plus three automatic ones the code triggers by itself: `idle`, `hurt`, `death`.

**Any animation you don't make is simply skipped** — the piece just stays on
idle. So the enemy really only needs `idle` + `attack` to start.

| Animation name | Loops? | Plays when…                                    |
|----------------|--------|------------------------------------------------|
| `idle`         | YES    | default, and after any other animation finishes|
| `slash`        | no     | Slash card                                     |
| `heavy_slash`  | no     | Heavy Slash card                               |
| `focus`        | no     | Focus card (and any other SKILL)               |
| `attack`       | no     | any attack card without its own animation      |
| `move`         | no     | any move card                                  |
| `hurt`         | no     | took damage and lived                          |
| `death`        | no     | HP reached 0 (holds the last frame)            |

> Rule of thumb: **only `idle` loops.** Everything else plays once and the code
> returns the character to idle automatically.

---

## 3. Building the animation in the Godot editor (the important part)

Do this once for the player, then again for the enemy.

1. Open the scene **`scenes/map/battlefield.tscn`** (double-click it in the
   FileSystem panel, bottom-left).

2. In the **Scene** panel (top-left), expand `Board` and click **`PlayerToken`**.

3. Look at the **Inspector** (right side). Find the property named **`Frames`**
   (it's an empty slot that says `<empty>` or "SpriteFrames").
   - Click the dropdown/slot → choose **New SpriteFrames**.
   - Now click on the SpriteFrames resource you just made. A **SpriteFrames**
     editor panel opens at the **bottom** of the screen.

4. In that bottom SpriteFrames panel:
   - On the left is a list of animations with a default one called `default`.
     Double-click it and **rename it to `idle`**.
   - With `idle` selected, click the **"Add frames from a file"** button (looks
     like a small picture/film icon in that panel's toolbar). Select all your
     `player/idle/idle_00.png … idle_NN.png` files at once. They appear as a row
     of thumbnails.
   - Set **Speed (FPS)** — try `8` to start (higher = faster). Higher FPS is
     smoother but needs more frames.
   - Make sure the **Loop** toggle is **ON** for `idle`.

5. Add the next animation:
   - Click the **"Add Animation"** button (the "+" / new-animation icon in the
     animation list, top-left of that panel).
   - Rename it exactly, e.g. `slash`.
   - Add its frames from `player/slash/`.
   - Set FPS, and turn **Loop OFF** (it should play once).
   - Repeat for each animation you have art for (`heavy_slash`, `focus`, `move`,
     `hurt`, `death`).

6. **(Optional but recommended) save it as a file** so you can reuse it: click
   the `Frames` resource in the Inspector, hit the little dropdown → **Save As**,
   and save to `assets/art/characters/player/player_frames.tres`.

7. **Do steps 2–6 again for `EnemyToken`** (make its own SpriteFrames with at
   least `idle` and `attack`).

### Using a sprite sheet instead of separate files
In step 4, use **"Add frames from a Sprite Sheet"** instead. A dialog lets you
set how many horizontal/vertical frames the sheet has; Godot slices it for you.

---

## 4. Test it

Press **Play** (F5). The pieces should stand in their `idle` loop. Play cards:
- Slash → the player's `slash` (or `attack`) animation fires, then returns to idle.
- Moving → `move`. Getting hit → `hurt`. Dying → `death`.

If a piece looks the wrong size or is off-center, select the token in the scene
and adjust its **Transform → Scale / Position** (the old placeholder was 48px).

---

## 5. Troubleshooting

| Problem | Likely cause / fix |
|--------|--------------------|
| Still shows a colored box | No `Frames` assigned, or the assigned SpriteFrames has no frames in `idle`. |
| An action does nothing visually | That animation name doesn't exist or has 0 frames — it's safely skipped. Check the name matches the table exactly (lowercase). |
| Animation plays once then freezes | `Loop` was left ON for a one-shot, or OFF for `idle`. Only `idle` loops. |
| Character faces the wrong way | Art must be drawn facing RIGHT; the code flips it for left. |
| Animation too fast/slow | Change **Speed (FPS)** in the SpriteFrames panel. |

---

## 6. What the code already does for you (no need to touch)

- `scripts/map/token.gd` — holds the `Frames` slot, plays the right animation via
  `play_card()`, handles `hurt`/`death`, and flips for facing.
- `scripts/map/battlefield.gd` — calls the animation when a card resolves, for
  both player and enemy.
- `scenes/map/token.tscn` — has the `AnimatedSprite2D` node ("Anim").

You only ever add images and build the SpriteFrames in the editor.
