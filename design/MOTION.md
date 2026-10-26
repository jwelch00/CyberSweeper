# CyberSweeper motion spec

Every moving part of the game, what it looks like, when it fires, and exactly how long each beat takes.

**Where to see it**
- `motion/*.mp4`: one video per effect. The `-slow4x` versions play the same effect four times slower so you can see every frame.
- `motion/*-storyboard.png`: frame grids with timestamps.
- `mockups/motion.html`: a live lab. Open it in a browser and press the buttons to trigger each effect. Add `?palette=hotwire` (or any palette id) to re-skin it, or `?slow=4` to slow everything down.
- `shared/fx.js`: the prototype code. All timings live in `FX.T` at the top and match the tables below.

## The rule behind all of it

**Their software is perfect. Yours is falling apart.**

- **The board** is TETSUKAGE DATAWORKS' secure lattice: corporate, exact, sterile. It only ever moves cleanly: tiles reveal, numbers resolve, cipher bytes drift. It never jitters, glitches or tilts. Mine hits are flagged in the corp's own clean hazard style.
- **The HUD** is your street cyberdeck. All the grime lives here and at the screen edges: jagged frames, glitches, jitter, corruption.
- Gameplay stays **pure minesweeper**: no power-ups, no upgrades. Three links and a timer. Everything in this file is feel, never rules.

## Accessibility (applies to every effect)

- **Reduce motion** (setting; also honor the OS preference where available): no shake, no jitter, no slide-ins, no cipher drift, no afterimages, no datamosh. Effects become instant state changes. Strain becomes a static red edge plus a "STRAIN" label on the HUD.
- **Reduce flashing** (setting, on by default when reduce motion is on): no full-screen flash frames on title cards or mine hits.
- Never more than 3 flashes per second, anywhere.
- No effect is the only signal: links, signal state and mine hits are all readable from shape and text too.

---

## 1. Jack-in boot

**What it is:** the "I'm in" moment from every hacker movie, played straight.
1. On launch, a terminal log types itself out on black: deck boot, proxy chain, "spoofing corp handshake", the target lattice, "scanning for 50/50 traps ... none found".
2. The log dims and the **breach** takes center stage:
   - a tiny 9×5 minesweeper board solves itself in a diagonal sweep, with tiles scrambling hex bytes then decrypting into numbers and the mines getting flagged
   - a session key cracks character by character underneath
   - hex-dump windows pop open around it
   - depending on the boot seed, it may hit **ACCESS DENIED** along the way
   - then KEY ACCEPTED at 100%
3. The JACKED IN title card slams in, and everything datamoshes away into the title screen.

**Trigger:** game launch. Any key or click skips straight to the title screen.

### Breach variants (rolled from a per-launch boot seed)

A fresh random **boot seed** is picked every launch. It decides the session key text and whether, where and how hard the breach gets denied (`FX.breachPlan(seed)`), so the same seed always plays the same way. Force a variant in the lab with `?breach=clean|one|99|double` or a seed with `?bootseed=N`.

| Variant | Odds | What happens | Video |
| --- | --- | --- | --- |
| Clean | 40% | Straight run to 100%, no denial | `1-jack-in-boot-clean.mp4` |
| One setback | 40% | Denied at a random point between 25% and 90%, drops 8–22 points | `1-jack-in-boot.mp4` |
| The 99% agony | 15% | Climbs all the way to 99%, gets denied, drops 10–22 points, climbs back | `1-jack-in-boot-99.mp4`, slow-mo `1-jack-in-boot-slow3x.mp4` |
| Double setback | 5% | Denied twice: once at 20–50%, again 25–50 points later | `1-jack-in-boot-double.mp4` |

Each denial also rolls which proxy it retries through ("RETRYING VIA PROXY 2–9").

### Timeline

| Time | Beat |
| --- | --- |
| 0 | Black screen, first log line |
| +42 ms per line | Next line appears whole (no per-letter typing); block cursor moves to the end of the newest line; progress bar steps |
| ~500 ms | LINK ESTABLISHED (accent, bold) |
| +160 ms | Breach starts: the log fades to 25% over 200 ms, and the breach panel appears centered at 1.35x |
| climbing | Progress rises 1% per 9 ms (0 → 100% in 900 ms with no denials). Board tiles decrypt along the diagonal as progress passes them; undecrypted tiles re-roll their byte every frame. Key characters lock in left to right with progress (locked = accent with glow) and **un-lock** again if progress drops. Hex-dump windows pop open one by one (4-step vertical scale-in, 90 ms) and scroll a new line per frame |
| each denial, 260 ms | The counter holds at the stall % for the first 40%, then shows the drop. ACCESS DENIED stamp (danger, Chakra Petch 700) scales 1.25 → 1 in and back out. The board hue-shifts red and kicks 6 px sideways for 160 ms. Status reads RETRYING VIA PROXY n in danger, then returns to CRACKING SESSION KEY |
| 100% | Board flashes bright for 160 ms, status reads KEY ACCEPTED, hold 180 ms |
| then | JACKED IN title card (see 2), then datamosh into the title screen (see 7) |
| total | About 2.5 s (clean) to 3.3 s (double setback) before the title screen is interactive |

**Log text** is in `FX.BOOT_LINES`. Timestamps are cosmetic. ok values are accent, warnings (unbounded, black ice) are warn, the Japanese words are 鉄影 (Tetsukage) and 接続 (connect).

**Easter egg:** 1 boot in 10,000 the card reads **JACKED OFF** instead of JACKED IN. Same timing, same subtitle, never explained or acknowledged. (`FX.T.boot.offChance`; force it in the lab with `?jackedoff`. See `png/easter-egg-jacked-off.png`.)

**Godot:** a full-screen Control with a monospace RichTextLabel; a Timer appends lines; any input skips.

## 2. Smash-cut title cards

**What it is:** a one-frame colored flash, then a thick diagonal band slams across the middle of the screen. The band holds huge skewed text with an offset outline copy, a small Japanese word and subtitle, and horizontal speed lines streaking through. It then exits by slicing into offset strips. Inspired by anime title smash-cuts.

| Card | When | Band color | Japanese | Subtitle |
| --- | --- | --- | --- | --- |
| JACKED IN | end of boot | accent | 接続完了 (connection complete) | TETSUKAGE // SECURE LATTICE |
| RIVAL DOWN | the moment your live score passes a rival's | accent | 撃破 (defeated) | rival name and score |
| NEW BEST | the moment your live score passes your personal best (once per run) | accent2 | 記録更新 (record updated) | score |
| LINK SEVERED | last link lost | danger | 切断 (disconnected) | final score; holds longer, then datamoshes into game over |

| Time | Beat |
| --- | --- |
| 0 | Flash: full screen in the band color at 50% opacity for 33 ms (2 frames). Skipped with reduce flashing |
| 33 ms | Band slams in: scaleX 1.18 → 1, scaleY 0.6 → 1 over 90 ms with overshoot. Text slides in from the right 120 px over 90 ms. Speed lines sweep right to left for the whole hold |
| 123 ms | Hold: 300 ms (LINK SEVERED: 900 ms) |
| 423 ms | Slice out: band and text cut into 3 strips, offset ±20 px, for 60 ms |
| ~480 ms | Gone |

**Layout:** band 40% of screen height, rotated −6°. Text Chakra Petch 700 at 210 px (at 1080p), skewX −10°, void-colored, with an outlined copy offset (14, 8) px in ink. Mid-run cards (RIVAL DOWN, NEW BEST) never take input away. The board stays clickable underneath.

**Godot:** a top CanvasLayer with an AnimationPlayer per card. The band is a rotated ColorRect or Polygon2D; the slice-out is a 3-strip mask in a tiny shader.

## 3. Sandevistan cascade

**What it is:** when a click opens a big empty region, the reveal ripples outward as a **round** wave. Every cell leaves three colored afterimages (accent2, accent, warn) that drift a little away from the click and fade, like the multi-colored frame trails of a speed implant. Small reveals don't get trails, just the normal reveal.

**Trigger:** any cascade of 12+ cells (`FX.T.cascade.minCells`).

| Time | Beat |
| --- | --- |
| 0 | Clicked cell reveals |
| every 22 ms | The next ring reveals. Rings are grouped by straight-line distance from the click (rounded), so the wavefront is a circle, not a square |
| per cell, at its reveal | The floor flashes from 45% accent back to floor over 260 ms. Three afterimage outlines spawn at 0, 40 and 80 ms, colored accent2, accent and warn, drifting 11, 22 and 33 px outward and scaling to 1.12 while fading over 360 ms |
| end | One "+N" popup for the whole cascade's score, in accent |

**Godot:** don't spawn nodes per cell. Store a reveal timestamp per cell (the board already animates reveals) and draw the three offset outlines in the board shader from `TIME - reveal_time`. The ring delay is just `reveal_time = click_time + round(distance) * 22 ms`.

## 4. Strain (cyberpsychosis)

**What it is:** when you're in trouble, your deck starts losing it. The edges of the screen bleed red in time with a heartbeat, HUD labels flicker into garbage characters, and at the worst level the HUD panels jitter, get a red/cyan chromatic split, the misregistered ghost outlines of the HUD frames show up, and colored tear lines rip across the screen. **The board itself is never touched.**

**Strain level = (links == 1 ? 1 : 0) + (signal < 10% ? 1 : 0)**

| Level | Looks like |
| --- | --- |
| 0 | Normal |
| 1 | Red edge vignette pulsing at 60 bpm (`beat` keyframes: bright, dip, second bump, fade). One HUD label corrupts to random glyphs for 90 ms every 3 s. HUD frame ghost outlines at 60% |
| 2 | Vignette stronger, 120 bpm. A label corrupts every 0.8 s for 140 ms. HUD panels jitter 1–2 px at 12 Hz. HUD numbers get a ±2 px red/cyan split. Scanlines double in strength. A 60 ms colored tear line crosses the screen every 1.5 s. Audio: heartbeat thump, music low-passed |

Corruption glyph set: `▓▒░█▚▞#%&$@!?¥ΞΣ0123456789`, replacing about 65% of a label's characters, then restoring the original.

**Godot:** a `strain_level` uniform on the existing post_fx/vignette shaders for the pulse and tears. HUD jitter is an offset on the HUD CanvasLayer. Corruption swaps a Label's text briefly.

## 5. Micro-text

**What it is:** tiny, low-contrast technical text tucked into the HUD frames: serial numbers, revision, proxy chain, "NAV // DEAD RECKONING", barcodes, a packet counter. The board has its own corporate micro-text: chunk IDs like `LAT 03F4:019F` at every 16-cell chunk corner, registration crosshairs, faint chunk seams, and edge rulers with a tick per cell and coordinates per chunk.

**Motion:** almost none. The `PKT` counter in the signal panel ticks up every 180 ms. During strain, micro-text is part of the corruption pool. Chunk IDs and rulers scroll with the board like any other board content.

**Rules:** Martian Mono 300 at 9–11 px, ink-dim at ~75% opacity, never overlapping real information, never the only place something is said.

## 6. Mine hit

**What it is:** the screen takes a hit. A quick red flash, a few colored tear lines and a shake. The mine cell slams in as a hazard tile: diagonal warn/void stripes with the mine glyph on a dark octagon, the stripes marching for a moment before settling. One link block shatters into flying shards. No text popup.

| Time | Beat |
| --- | --- |
| 0 | Cell becomes a hazard tile, scale 1.35 → 1 and brightness 3 → 1 over 120 ms with overshoot. Full-screen danger flash at 22% for 60 ms (skipped with reduce flashing). 3 tear lines for 66 ms |
| 0–250 ms | Screen shake, 8 px decaying to 0 |
| 0–320 ms | The lost link block breaks into 5 shards that fly 22 px outward, spin and fade; the slot becomes a hatched, outlined empty block |
| 0–1.2 s | Hazard stripes march (2 cycles of 0.6 s), then stop. The tile stays a hazard tile for the rest of the run |
| if links is now 1 | Strain level goes up (see 4) |

**Godot:** a hit state in the board shader draws the stripes from cell UV (`fract((uv.x + uv.y) * 7.0 + march_time)`). Shake is a Camera2D offset. The flash goes through post_fx. Shards are a one-shot GPUParticles2D or 5 pooled Polygon2Ds.

## 7. Datamosh transitions

**What it is:** every screen change breaks the old screen into horizontal bands. Bands smear sideways at different speeds, some stretch vertically like corrupted video blocks, and colors hue-shift. The new screen then snaps in band by band from offset positions, bleeding color for a moment before it settles.

**Where:** boot → title, title → game, game → game over (after LINK SEVERED), game over → title or game, and between menus.

| Time | Beat |
| --- | --- |
| 0–180 ms | Old screen splits into 7 bands of slightly random height. Each slides up to ±140 px, about 30% of bands stretch vertically 1.6–3x, and all hue-rotate, saturate and gain contrast |
| 180–380 ms | New screen appears in the same bands, each starting up to ±120 px off and hue-shifted, snapping to place with a fast ease-out and a 0–60 ms random stagger. The old bands fade in 70 ms |
| 380 ms | Clean new screen, input enabled |

**Godot:** one full-screen shader. At transition start, grab the current frame into a texture. The shader samples it with per-band horizontal offsets driven by `progress`, plus channel split and hue shift. Past 0.47 it blends band-wise to the live new screen. No DOM-style cloning; the mockup only clones because it is HTML.

---

## HUD frames (static, but part of the look)

Inspired by the HUD language of Cyberpunk 2077, but original:
- **Jagged silhouettes**, from `CS.jagPoints` in `shared/screens.js`, seeded per panel:
  - uneven cut corners (big top-left and bottom-right, small elsewhere)
  - a notch bitten out of the top edge
  - sawtooth teeth near the top-right
  - a 45° jog that pulls the right edge in by 6 px
  - a 6 px step in the bottom edge
- **Line work:** 1 px hairline outline at 40% accent. Thick 3 px "hot" accent strokes on the top-left and bottom-right corners, ending in 4 px square terminals. Small ruler ticks near the bottom-right. A misregistered dashed ghost outline offset (4, 4) px in accent2 that only appears under strain.
- **Tags:** labels sit in small filled tags with the lower-right corner cut off (LINKS, SIGNAL, SCORE, LINK SEVERED).
- **Links** are three chunky memory blocks with a cut corner. A lost link is a hatched, outlined empty block.
- **Signal** uses a health-bar treatment: a big percentage readout, a slanted bar whose empty part is hatched, and 40 fine ticks underneath.
- **Visor curvature:** HUD clusters sit on a slight perspective, about 6°, tilted toward the center like they're projected in your optics. This is optional in Godot, since it needs a SubViewport or shader. Skip it if it fights readability.
- **Ribbon cable:** a thin three-line connector with 45° jogs and square terminals runs down the left edge between the top and bottom HUD clusters. Decoration only.
- **Slash hatching** (`.slashes`) fills dead space in headers.
