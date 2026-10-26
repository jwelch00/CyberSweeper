# CyberSweeper

Infinite, no-guessing Minesweeper with a cyberpunk look, for Windows, macOS and Linux. Three links, a draining signal bar, and never a coin flip. Made with Claude.

**Status: milestone 1 of 6** (core logic, solver, no-50/50 generator, tests). There's no playable window yet; that's milestone 3. See `SPEC.md` for the full brief and `design/` for the look.

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
    game_state.gd      the API bots and UI call: reveal / chord / flag / tick
    rules.gd           loads data/tuning.json
  data/tuning.json     every gameplay number (placeholders until milestone 2)
  tests/               test runner, unit tests, property suite
tools/run_tests.py     runs the suites, property games in parallel
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

That's the **fast** suite: unit tests plus 200 property games, about a minute and a half on 6 cores. Other suites:

```bash
python tools/run_tests.py --suite gate
python tools/run_tests.py --suite unit
python tools/run_tests.py --suite property --driver sloppy --games 50 --moves 300
```

- `gate` is unit tests plus 3,000 property games of 400 moves (1,000 per driver). It must pass before any milestone is called done. It takes about 30 minutes with `--jobs 8`.
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

## How the no-50/50 guarantee works

- The board is stored in 16×16 chunks. A chunk's first draft comes from the seed, with mine density rising slowly with depth.
- A chunk **locks** as soon as the player can see anything that depends on it. Locked chunks never change.
- Before a chunk locks, the generator runs the solver forward from exactly what the player can see. The solver must be able to decrypt every safe cell in that chunk. If it can't, cells the player knows nothing about get re-rolled near the stuck spot, and the move is re-tried.
- The solver is monotone: learning more never un-proves a cell. So a proof made when a chunk locks stays true for the rest of the run, whatever the player does next. That includes mine hits, chords and wrong flags.
- Clicking far outside the explored area is a voluntary guess. The chunks it touches lock as "islands" without a proof.
- **Backstop:** if the solver ever finds no provably safe frontier cell, the next frontier click that isn't a proven mine is made safe. It does this by moving hidden mines so that every revealed number still matches. This should never happen, and it's logged if it does.

A seed plus the move log reproduces a run exactly. Two players on the same seed share the start and most of the board, but can drift apart where one of them needed a reroll.

## Building

Exports for Windows, macOS and Linux arrive in milestone 5.
