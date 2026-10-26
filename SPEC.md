# CYBERSWEEPER — project brief

Build CYBERSWEEPER: an arcade-style, infinite-board Minesweeper with a sleek cyberpunk look. Read this whole brief and look through `design/` (start with `design/README.md` and the PNGs in `design/png/`), then use plan mode to propose an architecture and milestone plan before writing any code. Stop for my review at the end of each milestone.

## Vocabulary (use these words in the UI and code)
- **Links**: the player's lives. You start with 3.
- **Signal**: the draining timer bar. Revealing cells refills it.
- **Decrypt**: reveal. Hidden cells are "encrypted" and show a faint hex byte.
- **Rivals**: the bot scores on the local leaderboard. Rookie = `script.kitty`, Runner = `mx_halcyon`, Netrunner = `NULL//SAINT`.
- **Depth**: distance in cells from the starting cell.

## Core game
- Infinite, procedurally generated board, generated in seeded chunks so runs are reproducible. Camera pans and zooms (drag, scroll wheel, WASD). Zoom range 0.5× to 2×.
- The first click always opens a zero region.
- 3 links. Revealing a mine costs a link; that mine stays revealed as a marked hazard and play continues. 0 links = game over.
- Score = the sum of the numbers on every numbered cell the player uncovered (zeros score 0; cells revealed by cascades count).
- Controls: left click reveals, right click flags, left-clicking a number whose flags are all placed chords its neighbors.
- Pressure (required, because a perfect player could otherwise play forever): the signal bar drains over time and refills as cells are revealed; signal at 0 costs a link and refills the bar. Mine density rises slowly with depth. If you have a better idea, propose it in the plan.
- **Pure minesweeper (core rule):** gameplay stays pure minesweeper. No power-ups, upgrades, pickups or perks, in a run or between runs. The only resources are the 3 links and the signal timer (Ghost mode drops the timer). Visual effects are feel, never rules. Separate opt-in modes in IDEAS.md (Versus, mutators) may change those two resources, but never add new ones.

## No 50/50s (hard requirement)
- At every moment of every game, at least one unrevealed cell next to the revealed area must be provably safe from the visible information (numbers and revealed mines). Flags are player opinions and must NOT count as information.
- Write a deterministic solver: single-cell rules, subset/difference rules, and exact constraint enumeration over the local frontier. Use it during generation: only commit new territory when the solver confirms progress is possible, and reroll that territory otherwise.
- Backstop: if the solver ever finds zero provably safe frontier cells, the next frontier cell the player clicks is guaranteed safe (rearrange still-hidden mines consistently with everything revealed). This should never trigger; log it if it does.
- Clicking far outside the explored area is a voluntary guess and is allowed.
- Property tests: thousands of seeded games driven by the solver, asserting the invariant after every move, including after mine hits.

## Architecture
- Game logic (board, generation, solver, rules, scoring) is a pure module with no rendering dependencies, so it runs headless for tests and bots.
- Stack: Godot 4 (latest stable) + GDScript, unless you can justify something better. Requirements: native exports for Windows, macOS (universal), and Linux x86_64; no installer, runtime, or dependencies for players. Download, unzip, run. Record the exact Godot version in the README.
- My dev machine is Windows; my server is Red Hat Linux. Builds must work from Windows (Linux is a bonus). Make the build script cross-platform (Python, or a .ps1 plus a .sh).
- Stay at 60 fps while panning across very large explored areas: render only visible chunks, and draw cells in bulk (TileMapLayer, MultiMesh or custom `_draw`/shader), not one Node per cell.

## Visual design (source of truth: `design/`)
- Match the mockups in `design/png/` for layout, color, type and feel. The HTML in `design/mockups/` shows exact sizes and states; open `design/index.html` in a browser to browse them. Don't port the HTML; rebuild the look natively in Godot.
- **Colors**: load every color from `design/tokens/palettes.json` (copy it into the project and read it at runtime, or generate a resource from it). Never hand-copy hex values into scenes.
- **Fonts**: `design/fonts/` has Chakra Petch (UI words) and Martian Mono (every digit) as TTF and WOFF2, a Noto Sans JP Bold subset for the few Japanese words, plus their OFL licenses. Bundle the license files with the game.
- **Cells**: hidden cells are raised chips with one cut corner (top-left) and a faint hex byte; revealed cells form one continuous dark floor with glowing numbers. See `design/png/components.png` for every state, including mine hit, wrong flag and chord preview.
- **Signature effect**: the cipher bytes on hidden cells re-roll in a slow diagonal wave, and on reveal a byte scrambles for ~120ms then resolves into the number. Timings for all motion are in the components sheet.
- **Effects**: subtle scanlines (toggle in settings), vignette, neon glow on numbers and accents, chromatic-aberration split on the wordmark, screen shake on link loss. Respect a reduced-motion setting (freeze cipher drift, no shake).
- **Art direction v2 and motion** (`design/README.md`, `design/MOTION.md`): the board is the corporation's clean lattice (chunk crosshairs, chunk IDs, edge rulers, hazard-stripe mine hits with no popup text); the HUD is the player's jagged street deck. MOTION.md specifies the boot breach, title cards, sandevistan cascades, strain, mine hit, datamosh transitions and micro-text, plus reduce-motion and reduce-flashing settings.
- Numbers must stay legible at every zoom level in every palette. Cell numbers never render below 11px.
- Optional synthy SFX: generate them yourself or use CC0 assets only, and list their licenses.

## Screens
Title, gameplay, pause, settings, game over, palettes, rivals. Mockups exist for title, gameplay, game over and palettes; build pause, settings and rivals in the same language (panels with cut corners, Chakra Petch for words, Martian Mono for digits).
- Game over shows the score tally broken down by number value (count × value per number, then the total), run stats, the rival ladder with the player's run slotted in, and any palette unlocked this run.
- Game over's **Run it back (R)** and **Main menu (Esc)** are clickable buttons as well as keys.

## Palettes and unlockables
- Six palettes, defined in `design/tokens/palettes.json`: Signal (default), Hotwire, Root access, Rustbelt, Icebreaker, and Plaintext.
- **Plaintext** (`"accessibility": true`) is the colorblind-safe palette.
  - It's a **pre-launch requirement** (milestone 4).
  - It's always unlocked: `null` in `game/data/unlocks.json`, like Signal.
  - The palette picker shows it with a small "Colorblind-safe" tag.
- Unlocks (thresholds approved after milestone 2, stored in `game/data/unlocks.json`; Arcade runs only):
  - Hotwire = beat the Runner rival.
  - Root access = decrypt 25,000 tiles across all runs.
  - Rustbelt = reach depth 120 in one run.
  - Icebreaker = beat the Netrunner rival.
- Locked palettes show an "encrypted" preview, the unlock condition and progress (see `design/png/palettes.png`).
- Save unlocks, settings, cumulative stats and local high scores to the OS-appropriate user data folder (`user://`). Fully offline: no network calls, ever.

## Accessibility (milestone 4, pre-launch)
- Color is never the only cue anywhere in the UI. Every state must also differ by shape, text or position, in every palette. This covers:
  - signal states;
  - lost links;
  - mine hits vs flags;
  - wrong flags;
  - hover vs chord preview;
  - locked vs unlocked palettes;
  - rival beaten vs not;
  - the minimap's categories.
- Already true after milestone 3:
  - Signal states change the meter's label as well as its color ("signal", "signal low", "signal critical").
  - Lost links are outlined with a slash; live links are filled.
  - Hits and flags are different glyphs, and hits also get a box.
  - Wrong flags get an X.
  - Hover gets an outline.
- Still to fix in milestone 4:
  - The chord preview is a tint only.
  - The minimap tells zeros, numbers, flags and hits apart by color only.
  - Check every new screen the same way.
- Plaintext must keep numbers 1–4 distinct under protanopia, deuteranopia and tritanopia (per its design notes). Every palette keeps the 5.7:1 number contrast, which a unit test already enforces.

## Bot simulations and rivals
- Headless bots at 3 skill levels, each with a per-move think time and an error rate so the signal pressure matters:
  - ROOKIE (`script.kitty`): single-cell deductions only, slow, occasionally guesses or misclicks.
  - RUNNER (`mx_halcyon`): adds subset rules, medium speed, low error rate.
  - NETRUNNER (`NULL//SAINT`): full solver, fast, rare errors.
- Run each bot across 100+ seeded games and report score distributions (median, p90, max). Use the results to tune signal drain/refill and density so a decent human's run lasts roughly 5–15 minutes.
- Rivals must be challenging but beatable. Each rival's score is that bot's **median** run, not its best. NETRUNNER thinks at a human pace (no faster than ~0.5s per move) so it wins on logic, not reflexes.
- Target feel: script.kitty falls within your first few runs, mx_halcyon takes some practice, and NULL//SAINT is a real stretch goal that a strong player can beat within a few hours of play. Report the numbers and propose the three rival scores for my approval before locking them in.
- Seed the local leaderboard with the approved rival scores, and update the placeholders shown in the design (640 / 2,180 / 5,960) and on the download page.

## Icon (already designed)
- `design/icon/icon.svg` is the primary icon; `icon-small.svg` is the simplified version for 32px and below.
- Ready-made exports: `design/icon/icon.ico` (16–256), `design/icon/icon.icns` (16–1024), and PNGs in `design/icon/png/`. Wire them into the Godot project icon, the window icon, and all three export presets.

## Distribution
- A build script that outputs `CyberSweeper-windows.zip`, `CyberSweeper-macos.zip`, and `CyberSweeper-linux.tar.gz`, plus a `SHA256SUMS` file.
- macOS builds are unsigned: use Godot's ad-hoc signing so Apple silicon will run them.
- A static download page: a single self-contained `index.html` matching `design/png/download-page.png` (inline CSS and JS, self-hosted fonts, no external CDNs), with per-OS download buttons, the visitor's OS detected and highlighted, a real screenshot, controls, rival scores, per-OS run notes, and the checksums filled in by the build script.
- Per-OS run notes: Windows = SmartScreen "More info → Run anyway"; macOS = on first launch go to System Settings → Privacy & Security → Open Anyway (macOS 15+; right-click → Open works on older versions); Linux = `chmod +x` if needed.
- The page and builds will be hosted on my home Red Hat Linux server with nginx. Write a deploy script (run on the server) and instructions covering copying files over from Windows, file placement, nginx config, SELinux contexts (`restorecon`), and firewalld. Do not run anything against the server yourself.

## Ghost mode (milestone 4)
- A second game mode. Arcade stays the main mode.
- Same infinite no-50/50 board and 3 links, but no signal timer at all.
- Since a careful player could go forever, add an "End run" action that ends the run and banks the score.
- Nothing in Ghost mode counts toward any palette unlock. That covers beating rivals, the total-tiles count, and best depth, so Ghost runs don't add to the cumulative stats either.
- Ghost mode gets its own separate leaderboard of the player's best Ghost runs (score, tiles, depth, date), with no rivals on it. The Arcade leaderboard and rivals stay Arcade-only.
- No levels or daily challenges.
- Add a mode picker after "Jack in" on the title screen.
- The HUD hides the signal meter in Ghost mode.
- Build milestone 3 with modes in mind so they aren't bolted on later.

## Rival flavor text (milestone 4)
Each rival in `game/data/rivals.json` has a `bio`, a `taunt` and a `beaten` line. NULL//SAINT also has a `bio_after_beaten`.
- **Rivals screen:** each rival's bio sits under their name and score. NULL//SAINT switches to `bio_after_beaten` permanently once the player has beaten her.
- **Game over, if the run beat a rival for the first time:** show that rival's `beaten` line, alongside the unlock card when there is one.
- **Game over, otherwise:** show the `taunt` line of the next rival above the player's score.
- **Style:** a quiet one-line quote in ink-dim, not a big banner.
- **Arcade only:** Ghost runs never beat rivals, so they never trigger these lines.

## Milestones (stop after each)
1. Core logic, solver, no-50/50 generator, tests
2. Bot simulations and difficulty-tuning report
3. Rendering, input, HUD, game feel (match `design/`)
4. Palettes (including Plaintext), unlocks, save data, rivals leaderboard, remaining screens, Ghost mode, accessibility pass (see above and below)
5. Icon wiring and cross-platform builds
6. Download page and deploy script

Keep README.md current with how to build, test, and run everything.
