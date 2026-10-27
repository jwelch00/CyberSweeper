# CyberSweeper

Infinite, no-guessing Minesweeper with a cyberpunk look, for Windows, macOS and Linux. Three links, a draining signal bar, and never a coin flip. Made with Claude.

**Status: milestone 4 of 6** (palettes, unlocks, save data, rivals, every screen, Ghost mode, accessibility). The whole game is playable: the boot, the title, the mode picker, Arcade and Ghost runs, pause, the full game over, palettes, rivals and settings, with progress saved between launches. Milestone 5 is icons and the cross-platform builds. See `SPEC.md` for the full brief and `design/` for the look (art direction v2 and `design/MOTION.md`). Post-launch ideas (not scheduled) live in `IDEAS.md`.

## Playing

Open `game/project.godot` in Godot 4.7.2 and press **F5**, or run `godot --path game`. The boot plays (any key or click skips it), then the title: **Jack in** (Enter), pick **Arcade** or **Ghost**, and the first click opens the run.

| Input | Action |
| --- | --- |
| Left click | decrypt a cell |
| Left click on a number | chord (hold to preview its hidden neighbours) |
| Right click | flag (your opinion only; the game never reads flags) |
| Drag, WASD or arrow keys | pan |
| Mouse wheel | zoom (0.5× to 2×) |
| Esc | pause (Resume, Settings, End run, Main menu); back, on every menu |
| Ctrl+E | end a Ghost run |
| R or Run it back | new run (game over) |
| Esc or Main menu | back to the title (game over) |
| E or Equip | equip a palette unlocked this run (game over) |
| Arrow keys or WASD, Enter | every menu (the mouse works too) |
| F11 | fullscreen |
| F3 | FPS and frame-time overlay |
| M | mute sound |

## Save data

Settings and progress save to the user data folder as they change, and nothing ever leaves your machine:
- Windows: `%APPDATA%\CyberSweeper`
- macOS: `~/Library/Application Support/CyberSweeper`
- Linux: `~/.local/share/CyberSweeper`

`settings.json` holds the settings and palette; `profile.json` holds Arcade stats, unlocked palettes, rivals beaten and the top 10 runs per mode. Ghost runs only go on the Ghost leaderboard. Writes go to a temp file first, and a file that won't load is kept as `.bad` while the game starts fresh. Delete the folder to start over. `--save-dir DIR` points the game at another folder; the tests and screenshots always use scratch folders under `test-output/`.

Command-line flags go after `--`, for example `godot --path game -- --skip-boot`:

| Flag | Effect |
| --- | --- |
| `--mode ghost`, `--seed 1234` | straight into a run with that mode or seed |
| `--skip-boot` | start at the title |
| `--bootseed N`, `--breach clean\|one\|99\|double` | pick the boot breach (the motion lab's `?bootseed=` and `?breach=`) |
| `--jackedoff` | force the 1-in-10,000 boot card |
| `--reduce-motion`, `--reduce-flashing` | the accessibility settings (reduce motion also follows the OS setting until you set it) |
| `--save-dir DIR` | use another save folder |

## Motion

Everything in `design/MOTION.md` is in, with the timings from `design/shared/fx.js` (`game/ui/fx/motion.gd`; a test checks they agree):
- **Boot:** the log, the breach (a 9×5 board solving itself, the session key cracking, hex dumps), ACCESS DENIED setbacks rolled from a per-launch boot seed (clean 40%, one 40%, the 99% agony 15%, double 5%), KEY ACCEPTED, then the JACKED IN card. One boot in 10,000 says JACKED OFF.
- **Title cards:** JACKED IN, RIVAL DOWN (Arcade only, once per rival), NEW BEST (against this session's best until milestone 4 saves one) and LINK SEVERED. Mid-run cards never take input.
- **Sandevistan cascade:** round reveal rings 22 ms apart; cascades of 12+ cells leave three drifting afterimages per cell.
- **Strain:** one link left, or the signal under 10%, is strain 1; both is strain 2. The red edge beats, HUD labels corrupt, frame ghosts show; at strain 2 the HUD jitters and splits and tear lines cross the screen. The board is never touched. The faint low-signal edge pulse (from 30% shown) stays as the step before strain.
- **Mine hit:** a hazard tile that slams in and marches, a danger flash, three tear lines, the shake, and the link block shattering. No popup text.
- **Datamosh** on every screen change, and **micro-text** (the PKT counter, chunk IDs, rulers).
- **Reduce motion** makes effects instant and strain a steady red edge plus a STRAIN tag; **reduce flashing** drops every full-screen flash. Nothing flashes more than 3 times a second (`ui/fx/flash_guard.gd`).

The visor curvature (MOTION.md calls it optional) is left out: it would mean rendering the HUD off-screen, which loses the blurred-board panel backgrounds and resamples the 9 px micro-text into blur.

## Engine version

**Godot 4.7.2-stable** (official build `4.7.2.stable.official.ed1daf0bf`), the standard build, not the .NET one. Get it from https://godotengine.org/download/archive/4.7.2-stable/ or the GitHub release `4.7.2-stable`. Check the zip against the release's `SHA512-SUMS.txt`.

The game makes no network calls of any kind.

## Layout

```
game/                  Godot project (open game/project.godot in the editor)
  core/                pure game logic: no nodes, no rendering, runs headless
    board.gd           infinite chunked board, numbers, cascades
    solver.gd          the reference solver (3 tiers)
    generator.gd       mine placement, chunk proofs, repairs, backstop
    game_state.gd      the API bots and UI call: reveal / chord / flag / tick / end_run
    move_log.gd        every call in order, plus replay files (version, tuning hash, timed actions)
    rules.gd           loads data/tuning.json
    profile.gd         saved progress: stats, unlocks, rivals beaten, leaderboards, flavor lines
    save_store.gd      settings.json and profile.json in the user folder, written atomically
    bot.gd             headless player: the three rivals and the tuning profiles
    session.gd         runs a GameState on a worker thread for the UI
  ui/                  the screens (read the core only through Session)
    main.tscn          entry scene; also screenshot (--shot) and gallery modes
    screen_flow.gd     boot -> title -> game -> game over, datamosh between them
    screens/           boot (breach), title, mode picker, pause, settings, palettes, rivals, game over
                       (deck.gd is their shared drawing kit, menu_screen.gd their mouse/keyboard list)
    game_view.gd       the gameplay screen: input, results -> visuals, effects
    board_view.gd      one-shader board, 256x256 wrap-around cell texture
    board.gdshader     every cell state (hazard-stripe hits too), cipher drift, glow
    lattice_layer.gd   the corp's chunk crosshairs, chunk IDs, seams and edge rulers
    glyph_atlas.gd     digits, hex, flag and mine drawn once into textures
    hud/               jagged street-deck panels (jag.gd ports CS.jagPoints), links, signal, score, minimap
    fx/                motion timings, breach plan, title cards, datamosh, afterimages, strain, flash guard
  assets/              fonts + OFL, palettes.json (copied from design/), sfx
  data/
    tuning.json        every gameplay number (tuned in milestone 2)
    bots.json          bot profiles: tier, think time, error rates
    rivals.json        approved rival scores for the leaderboard
    unlocks.json       palette unlock conditions (approved thresholds)
  sim/run_sim.gd       headless bot runs
  tests/               test runner, unit tests, property suite, ui_smoke.gd
tools/
  run_tests.py         runs the suites, property games in parallel
  simulate.py          runs the bots, tunes, writes the tuning report
  sync_design.py       copies palettes and fonts from design/ (--check verifies)
  js_reference.mjs     records design/shared/*.js outputs the ports are tested against (needs node)
  make_sfx.py          synthesizes the sound effects
  shots.py             renders comparison screenshots into test-output/shots/
docs/tuning-report.md  bot results behind the current tuning and rival scores
design/                reference designs (read-only)
```

## Setup

Python 3.9+ runs the test tool. Point it at Godot in one of these ways (it checks them in this order):

1. `--godot PATH`
2. the `GODOT` environment variable
3. the repo's `.tools/` folder (gitignored)
4. `godot4` or `godot` on your PATH

**Windows:** unzip `Godot_v4.7.2-stable_win64.exe.zip` into `.tools\`. Use the `_console.exe` it contains, which prints test output to the terminal:

```powershell
$env:GODOT = "$PWD\.tools\Godot_v4.7.2-stable_win64_console.exe"
```

**Linux:** unzip `Godot_v4.7.2-stable_linux.x86_64.zip` into `.tools/`, then run `ln -s Godot_v4.7.2-stable_linux.x86_64 .tools/godot`.

## Running the tests

From the repo root:

```bash
python tools/run_tests.py
```

That's the **fast** suite: unit tests, the UI smoke test and 200 property games, about a minute and a half on 6 cores. The UI smoke test plays the real screens with real mouse and keyboard events: the boot and its skip, the title, a run (checking that the board always shows what the game knows), mine hits and strain, LINK SEVERED, the game-over buttons and Ghost mode. It also opens every menu: the mode picker, pause, settings (checking the save), palettes (equipping one, refusing a locked one), rivals, and a game over that unlocks a palette. It steps the motion clock by hand, so cards and transitions are deterministic, and saves into a scratch folder. Other suites:

```bash
python tools/run_tests.py --suite gate
python tools/run_tests.py --suite unit
python tools/run_tests.py --suite property --driver sloppy --games 50 --moves 300
```

- `gate` is unit tests, the UI smoke test and 3,000 property games of 400 moves (1,000 per driver). It must pass before any milestone is called done. It takes about 17 minutes with `--jobs 8`.
- `--jobs N` sets the worker count. The default is half your cores.
- Workers run at low CPU priority.
- The exit code is non-zero if anything fails, including any Godot script error in the output.

You can also call Godot directly. Run the import once first so `class_name` scripts resolve:

```bash
godot --headless --path game --import
godot --headless --path game -s res://tests/run_tests.gd -- --suite unit
godot --headless --path game -s res://tests/run_tests.gd -- --suite property --driver perfect --games 20 --moves 300
```

### What the property suite checks

Each game starts at a random spot, then plays 300–400 moves with link loss turned off so it keeps exploring. There are three play styles:

- **perfect:** only clicks provably safe cells.
- **sloppy:** also guesses frontier cells (mine hits), drops random flags, and chords on them (bad chords hit mines).
- **wanderer:** sloppy plus voluntary clicks far outside the explored area.

After every move, the suite checks with a fresh solver that some frontier cell is provably safe. The fresh solver sees only revealed numbers and revealed mines, never flags. That's the no-50/50 rule.

Every 25 moves it also checks that:

- revealed numbers and locked chunks never changed;
- the score equals the sum of the revealed numbers;
- the game's incremental solver agrees with a fresh one.

Every 100 moves, it re-runs every chunk proof against what the player can see now.

The suite fails if any of these fail, or if the backstop ever fires.

Results go to `test-output/report.json`. Each failure writes `test-output/failures/<driver>-<n>.json` with the seed, a map and the full move log. Replay one with:

```bash
godot --headless --path game -s res://tests/run_tests.gd -- --suite replay --file ../test-output/failures/sloppy-12.json
```

Report columns: **locks** is chunks locked, and **proofs** is how many of them were proven fully solvable. **Pockets** are chunks the generator couldn't prove. They still keep the no-50/50 rule, but some cells in them may never become provable, so this should be 0. **Near isl** counts pockets next to a far-click island; they come from the player's own guess. **Islands** are chunks locked by a far click, which are allowed and unproven.

## Screenshots

```bash
python tools/shots.py
```

This renders seeded screenshots, with the motion clock pinned, into `test-output/shots/`:
- every cell state in all six palettes, at 1× and 0.5×;
- gameplay in each palette, strain 2 with a hazard tile, a cascade mid-wave;
- the zoom limits and Ghost mode;
- the boot at ACCESS DENIED and KEY ACCEPTED, the JACKED IN and JACKED OFF cards;
- the title, the mode picker, pause, settings, palettes and both rivals boards (with a sample profile);
- the game over as in the mockup, one that unlocks a palette, and a banked Ghost run;
- a datamosh in both halves;
- the real screens driven by input (`ui-*.png`).

It needs a display. On a headless Linux box, point `DISPLAY` at an Xvfb.

Colors come only from `game/assets/tokens/palettes.json`, a byte-for-byte copy of `design/tokens/palettes.json`. Run `python tools/sync_design.py` after design changes, and `--check` to verify the copy; a unit test checks it too.

## Bots, rivals and tuning

Four headless bots play the real game through the same `GameState` API the UI will use. Each sees only revealed numbers and mines, through its own solver limited to its tier. It spends simulated think time before every move, so the signal bar drains while it thinks.

| Bot | Logic | Pace | Role |
| --- | --- | --- | --- |
| script.kitty | single-cell rules only, never chords | slow, occasional misclicks and guesses | Rookie rival |
| mx_halcyon | adds subset rules, chords | medium, low error rate | Runner rival |
| NULL//SAINT | full solver, chords | never faster than 0.5 s a move, rare errors | Netrunner rival |
| reference | like Runner but slower and sloppier | | stands in for a decent human; sets the run-length target |
| expert | full solver, quicker than reference, fewer misclicks | | stands in for a strong human; sets how beatable NULL//SAINT is (19% of its runs beat 7,000) |

Run them:

```bash
python tools/simulate.py --games 300
python tools/simulate.py --profiles reference --games 60 --grid signal.drain_per_sec=1.6,2.0,2.4
python tools/simulate.py --profiles runner,reference --games 100 --set runner.think_median_ms=1900
python tools/simulate.py --games 300 --sensitivity --report docs/tuning-report.md
```

- `--set` and `--grid` take a `tuning.json` setting (`signal.drain_per_sec`) or a bot setting (`runner.think_median_ms`).
- Every profile plays the same seeded boards, and a run is reproducible from its seed.
- The last command regenerates the report.

**Current rival scores** (each bot's median run, approved 2026-10-26; details in `docs/tuning-report.md`). NULL//SAINT is the final boss: a decent player never beats her, and a strong one does about one run in five.

| Rival | Score |
| --- | --- |
| script.kitty | 1,890 |
| mx_halcyon | 3,590 |
| NULL//SAINT | 7,000 |

A reference ("decent human") run lasts a median 9.5 minutes, 6.6–11.3 for most runs, and scores a median 2,960.

**The signal bar runs on a false scale** (`signal.display_curve` in `tuning.json`). It drains faster than the real signal while there's plenty left, then slower and slower toward empty:

| Bar shows | Real signal left |
| --- | --- |
| 50% | 80% |
| 30% | 66% |
| 10% | 39% |

The low (30%) and critical (10%) marks, the meter's pulse and the red vignette that creeps in from the screen edges all follow the bar you see. Only the display changes; the real drain the bots were tuned on is the same.

**Palette unlocks** live in `game/data/unlocks.json`. Signal (the default) and **Plaintext** (colorblind-safe) are always unlocked. The rest unlock from Arcade runs only:
- **Hotwire:** beat mx_halcyon.
- **Root access:** decrypt 25,000 tiles across all runs.
- **Rustbelt:** reach depth 120 in one run.
- **Icebreaker:** beat NULL//SAINT.

`design/tokens/palettes.json` still lists the old placeholder thresholds. The game reads unlocks from `unlocks.json`.

## How the no-50/50 guarantee works

- The board is stored in 16×16 chunks. A chunk's first draft comes from the seed, with mine density rising slowly with depth.
- A chunk **locks** as soon as the player can see anything that depends on it. Locked chunks never change.
- Before a chunk locks, the generator runs the solver forward from exactly what the player can see. The solver must be able to decrypt every safe cell in that chunk. If it can't, cells the player knows nothing about get re-rolled near the stuck spot, and the move is re-tried.
- The solver is monotone: learning more never un-proves a cell. So a proof made when a chunk locks stays true for the rest of the run, whatever the player does next. That includes mine hits, chords and wrong flags.
- Clicking far outside the explored area is a voluntary guess. The chunks it touches lock as "islands" without a proof.
- **Backstop:** if the solver ever finds no provably safe frontier cell, the next frontier click that isn't a proven mine is made safe. It does this by moving hidden mines so that every revealed number still matches. This should never happen, and it's logged if it does.

A seed plus the move log reproduces a run exactly. The log is also replay-ready: `MoveLog.to_replay()` gives the version, tuning hash, mode, seed, every action with its run time, and the final score, and `MoveLog.play_replay()` reproduces the run from just that. The signal drain is an exact integer integral, so the result doesn't depend on frame timing. The replay viewer itself is a post-launch idea (`IDEAS.md`). Two players on the same seed share the start and most of the board, but can drift apart where one of them needed a reroll.

## Building

Exports for Windows, macOS and Linux arrive in milestone 5.
