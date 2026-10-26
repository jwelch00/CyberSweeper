# CyberSweeper design

Everything here is the source of truth for how CyberSweeper looks. The mockups are HTML so they use the real fonts and tokens; the game should match them natively in Godot, not reuse the HTML.

Open `index.html` in a browser to browse every screen and re-skin it in any palette.

## Concept: the ciphertext field

The board is an encrypted data field. Hidden cells are raised "encrypted" chips with one cut corner and a faint hex byte that slowly re-rolls; revealing a cell decrypts it, and the byte scrambles into the number. Revealed cells sink into one continuous dark floor so the frontier reads instantly. That cipher grid is the one loud, signature idea; the HUD stays quiet and disciplined around it.

The structural motif is the **cut corner**: hidden cells cut top-left, panels and buttons cut top-left and bottom-right.

## Files

| Path | What it is |
| --- | --- |
| `png/title-signal.png` | Title screen |
| `png/gameplay-<palette>.png` | Gameplay HUD and board, once per palette |
| `png/game-over-signal.png` | Game over: score tally by number, rivals ladder, unlock card |
| `png/palettes.png` | Palette picker with locked and unlocked states |
| `png/components.png` | Every cell state, numbers in all palettes at 1× and 0.5× zoom, HUD pieces, type specimen, motion timings |
| `png/icon.png` | Icon concepts and size ladder |
| `png/download-page.png` | The public download page (1440px wide) |
| `mockups/*.html` | Live versions of the above. Add `?palette=hotwire` (or any palette id) to re-skin one |
| `tokens/palettes.json` | All colors for all five palettes, number ramps, unlock conditions, type scale, effect specs. **The game reads colors from here.** |
| `tokens/palettes.css` | The same palettes as CSS custom properties (generated from the JSON, used by the mockups and the download page) |
| `fonts/` | Chakra Petch (words) and Martian Mono (digits), TTF for Godot and WOFF2 for the web, with OFL license files |
| `icon/icon.svg` | Primary icon ("Black ice") |
| `icon/icon-small.svg` | Simplified icon for 32px and below |
| `icon/icon.ico`, `icon/icon.icns` | Ready-made Windows and macOS icon files |
| `icon/png/icon-<size>.png` | 16 to 1024px exports |
| `icon/concept-*.svg` | The two alternative concepts, kept for reference |
| `shared/` | CSS and the mockup board generator. Mockup-only: the board generator here does NOT enforce the no-50/50 rule |

## Palettes

| Id | Name | Unlock (placeholder thresholds) |
| --- | --- | --- |
| `signal` | Signal | Default |
| `hotwire` | Hotwire | Beat mx_halcyon (Runner rival) |
| `root-access` | Root access | Decrypt 10,000 tiles across all runs |
| `rustbelt` | Rustbelt | Reach depth 300 in one run |
| `icebreaker` | Icebreaker | Beat NULL//SAINT (Netrunner rival) |

Every number color clears 5.7:1 contrast against its palette's revealed floor.

## Type

- **Chakra Petch** 400–700: wordmark (700, caps, chromatic split), titles, menu items, buttons, labels. Labels are lowercase or sentence case, never tracked-out caps.
- **Martian Mono** 300–800: every digit the player reads. Cell numbers are 800 weight at 52% of the cell size.

## Placeholder content

Rival scores (640 / 2,180 / 5,960), file sizes, checksums and the 2,293 sample run are illustrative. Replace them with real numbers after the bot simulations and builds.
