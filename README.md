# CyberSweeper

Infinite, no-guessing Minesweeper with a cyberpunk look, for Windows, macOS and Linux. Three links, a draining signal bar, and never a coin flip. Made with Claude.

**Status: milestone 3 of 6** (rendering, input, HUD, game feel). The gameplay screen is playable. The title, pause, settings, game-over, palettes and rivals screens, save data and Ghost mode's picker arrive in milestone 4. See `SPEC.md` for the full brief and `design/` for the look. Post-launch ideas (not scheduled) live in `IDEAS.md`.

## Playing

Open `game/project.godot` in Godot 4.7.2 and press **F5**, or run `godot --path game`. A run starts straight away: click anywhere to jack in.

| Input | Action |
| --- | --- |
| Left click | decrypt a cell |
| Left click on a number | chord (hold to preview its hidden neighbours) |
| Right click | flag (your opinion only; the game never reads flags) |
| Drag, WASD or arrow keys | pan |
| Mouse wheel | zoom (0.5× to 2×) |
| R | run it back (after a run ends) |
| F11 | fullscreen |
| M | mute sound |

**Dev keys until milestone 4 adds the screens:**

| Key | Action |
| --- | --- |
| F2 | cycle palettes |
| F3 | FPS and frame-time overlay |
| F6 | scanlines on/off |
| F7 | reduced motion on/off |
| F8 | switch between Arcade and Ghost mode (starts a new run) |
| Ctrl+E | end a Ghost run |

`godot --path game -- --mode ghost --seed 1234` starts a specific seed or mode.

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
    bot.gd             headless player: the three rivals and the tuning profiles
    session.gd         runs a GameState on a worker thread for the UI
  ui/                  the gameplay screen (reads the core only through Session)
    main.tscn          entry scene; also screenshot (--shot) and gallery modes
    game_view.gd       input, results -> visuals, effects
    board_view.gd      one-shader board, 256x256 wrap-around cell texture
    board.gdshader     every cell state, cipher drift, glow
    glyph_atlas.gd     digits, hex, flag and mine drawn once into textures
    hud/               cut-corner panels, signal meter, score, minimap
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

That's the **fast** suite: unit tests, the UI smoke test and 200 property games, about a minute and a half on 6 cores. The UI smoke test plays the real gameplay screen with real mouse and keyboard events and checks that the board always shows what the game knows. Other suites:

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

This renders seeded screenshots into `test-output/shots/`:
- every cell state in all six palettes, at 1× and 0.5×;
- gameplay in each palette;
- the zoom limits;
- Ghost mode;
- the real screen mid-play.

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
| expert | full solver, quicker than reference, fewer misclicks | | stands in for a strong human; checks NULL//SAINT is beatable (5.3% of its runs beat 7,640) |

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

**Current rival scores** (each bot's median run, approved 2026-10-26; details in `docs/tuning-report.md`):

| Rival | Score |
| --- | --- |
| script.kitty | 1,890 |
| mx_halcyon | 3,590 |
| NULL//SAINT | 7,640 |

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
