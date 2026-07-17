# Swordsman — art assets

The player character. **One whole image** — sword drawn in, not a separate
piece. Assigned to `PlayerToken.sprite_texture` in `scenes/map/battlefield.tscn`.
The enemy token still uses the placeholder box. Token-side layout (scale, flip,
anchoring, `art_offset`) lives in `scripts/map/token.gd`; see the "Character art"
note in the project `CLAUDE.md`.

## Folders

| Folder | What goes in it |
|--------|-----------------|
| `source/` | Raw AI generations, full-res. Working masters — never referenced by the game. Carries a `.gdignore` so Godot skips importing them. |
| `parts/` | Unused. Kept for a future cutout rig. |
| `weapons/` | Unused. Kept for a future swappable-weapon setup. |
| `fx/` | Glow / trail / hit-flash overlays. |

## Conventions

- **Authoring size:** 2× the on-screen size — ~300 px tall, displayed at
  `Token.art_scale = 0.5` → ~150 px on screen, in the board's 140 px cell
  (`cell_size` in `scripts/map/board.gd`).
- **Downscale from `source/` with Lanczos + a light unsharp mask.** Never let
  the GPU handle more than a ~2× minification — its mipmap chain is box-filtered
  and turns fine linework to mush. That blur is not fixable with filter settings.
- **View:** three-quarter, facing **right**. Flipped horizontally for facing
  left (`Token.facing.x`), which mirrors the whole `Art` node.
- **No cast shadows** in the art — the character moves between grid cells.
- **Generate on flat green and key it out.** Prompting "transparent background"
  makes most models paint a checkerboard instead of producing real alpha.

## Anchoring

`Token._layout_art()` feet-anchors the sprite: the texture's bottom edge rests on
the token's origin (the cell centre) rather than straddling it.

`Token.art_offset` (texture pixels) nudges on top of that. It exists because a
raised blade pads one side of the image, so the *image* centre is not the
*character* centre — without `art_offset.x` he stands off-centre in his cell.
Current art needs **`(35, 0)`**; re-measure if the artwork changes.

## Filtering

The art is minified on screen, so **mipmaps are required** — without them it
aliases into sparkly noise. `swordman.png.import` sets `mipmaps/generate=true`,
and the `Art` node sets `texture_filter = 4` (linear + mipmaps), which child
sprites inherit.
