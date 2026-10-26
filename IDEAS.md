# Ideas (post-launch, not scheduled)

Logged so they aren't lost. Nothing here is built or promised; each needs its own plan and approval first.

## Versus mode

The player races a rival bot live, on mirrored copies of the same seeded board, under a fixed match timer of about 3 minutes. Highest score wins.

- **Mine hits** don't cost a link. Instead there's a short lockout (no input for a moment) and a score penalty.
- **Speech bubbles:** rivals pop snarky bubbles on match start, on mine hits (theirs and yours), on lead changes, after big cascades, and in the final 10 seconds. Each rival has their own voice:
  - **script.kitty:** a chaotic tsundere catgirl.
  - **mx_halcyon:** curt and dry.
  - **NULL//SAINT:** cold, and rarely speaks.
- **Later:** a shared-board "chaos" variant, where both race on one board.

### Notes for whoever builds it

- **Mirrored boards must be identical.** Today a board depends on the seed *and* on what the player has uncovered. Repairs re-roll mines the player knows nothing about, so two players on one seed share most of the board but can drift apart. A fair race can't allow that. Options:
  - pre-generate the match area up front with one player-independent generation pass (a 3-minute match covers a bounded area, so this is cheap);
  - or run one generator for both boards and apply each repair to both.

  Either way, the no-50/50 guarantee has to hold for both players at once.
- **Bots on screen.** `Bot` already plays through the same `GameState` API as a person and sees only what a person sees. `Session` already runs a `GameState` on a worker thread and streams `MoveResult`s that a `BoardView` turns into visuals. What's missing is a way to step a bot one action at a time and stream each result, with its think time mapped to real time, so a second `BoardView` can show the rival playing live. Keep `Bot` free of rendering and of batch-only assumptions so that stays easy.
- **New rules:** a match timer instead of the signal, plus the lockout and penalty instead of links. These are another game mode, like Ghost (`GameState.Mode`). Rivals' scores and unlocks would stay Arcade-only unless decided otherwise.
- **Speech bubbles** would be driven by game events (`MoveResult` already reports hits, cascades and score changes), with per-rival line pools in data, like the flavor text in `rivals.json`.

## Replay files and a replay viewer

- **What a replay stores:**
  - the seed, game version, tuning hash and mode;
  - every action in order (reveal, flag or chord; the cell; ms since start);
  - the final score.

  Playing it back must reproduce the same score exactly, so replays double as score verification.
- **Viewer:**
  - play and pause;
  - step forward and back one move;
  - speed from 0.5× to 8×;
  - a scrubbable timeline;
  - jump to a mine hit.
- **Saving:** from the game-over screen, into `user://replays`.
- **Mismatches:** if a replay's version or tuning hash doesn't match the current build, say so instead of playing it wrong.

**Already done (milestone 3, so this stays easy):**
- `MoveLog` records everything above, and `MoveLog.to_replay()` produces the file contents.
- `MoveLog.play_replay()` reproduces a run from its actions and their times alone.
- `MoveLog.replay_problem()` explains why a replay from another version or tuning can't be played.
- The signal drain is now an exact integer integral, and the moment a run ends is computed to the millisecond. So a replay gives the same score, links, board and end time however the time between actions is sliced; `tests/unit/test_replay.gd` checks this.
- Stepping backward can simply re-run from the start to move N, which is fast.
- **Still to build:** the save/load files and the viewer UI.

## Share card

On game over, a "Copy share card" button renders an image and copies it to the system clipboard. The card shows the wordmark, score, mode, palette, depth, time, and the explored-area shape from the minimap. It must **not** be saved as a file anywhere.

**Godot can't do this out of the box.** Godot 4.7.2 can put *text* on the clipboard and *read* an image from it (`clipboard_set`, `clipboard_get_image`, `clipboard_has_image`), but it has no way to *write* an image (no `clipboard_set_image`), on any platform. Workarounds, none of which write a file:

1. **A small native plugin (GDExtension)** that calls each OS's clipboard directly:
   - Windows: put PNG/DIB data on the clipboard;
   - macOS: put PNG data on the pasteboard;
   - Linux: the game itself serves the image when another app asks for it (X11 selection or Wayland data source).

   It's the most reliable option. It costs a native build per platform, including macOS universal, in the milestone 5 build pipeline. On Linux the image stays on the clipboard only while the game is running, unless a clipboard manager keeps it; that's normal Linux behavior.
2. **Hand the PNG bytes to a built-in OS helper through a pipe:**
   - Windows: PowerShell with .NET's clipboard;
   - macOS: `osascript` in JavaScript mode, calling the pasteboard;
   - Linux: `wl-copy` or `xclip`, if installed.

   It's cheaper to build but more fragile: it depends on what's installed and spawns a process.
3. **Fallback everywhere:** copy a one-line text summary (score, mode, depth, time) and show the card on screen so the player can screenshot it.

Decide between 1 and 2 before building. Either way, keep 3 as the fallback.

## More ideas

### Gameplay
- **Race your ghost:** a faded replay of your personal best plays on the same seed alongside you. This needs identical boards for both, like Versus mode, and replays make it straightforward.
- **Mutators:** optional run modifiers with score multipliers and their own leaderboard:
  - Iron link: 1 link, 2× score.
  - No flags.
  - Blackout: numbers fade 5 s after they're revealed.
- **Sectors:** as depth increases, the board passes through named sectors ("Sector 7 // Cold storage"), with subtle visual shifts like a tint or a different cipher glyph style, so an infinite board still feels like a journey.
- **Landmarks:** rare authored structures inside the procedural board, such as a wide zero "data lake" or a dense "firewall" band, still validated by the no-50/50 solver.
- **Beacons:** checkpoints at depth milestones that refill the signal or restore one link, giving runs mid-term goals.
- **Data shards:** very rare tiles that drop a line of lore when decrypted: rival backstory, what the grid is, who NULL//SAINT really is. They're collectible, with a lore log in the menu.
- **Rival rematches:** after you beat a rival, they come back later with a higher score and a new taunt, so the chase never fully ends.

### Learning tools (the solver already exists, so these are cheap)
- **Hint button in Ghost mode:** highlights one provably safe cell.
- **"Why was that safe?":** in Ghost mode and the replay viewer, highlight the numbers that prove a cell is safe or a mine.
- **Death recap on game over:** show the mine that cost the last link and whether it was provable, with the proving numbers highlighted.
- **Interactive tutorial:** a short guided board that teaches reveal, flag, chord, the signal, and the no-guessing promise.

### Progression and meta
- **Achievements that unlock cosmetics** (not palettes): mine glyph styles, cursor styles, synth sound packs. For example: "chord a 50+ tile cascade", "reach depth 100 without placing a flag".
- **Stats page:** lifetime tiles, counts per number, deaths by mine vs signal, average and best depth, and run history with minimap thumbnails.
- **Custom palettes:** load extra palette JSON files from a user folder using the same schema as `palettes.json`, validated for contrast (the existing 5.7:1 check) before use.

### Feel and polish
- **Reactive music:** synthwave layers that add tension as the signal drops, and a separate lo-fi track for Ghost mode.
- **Controller and Steam Deck support:** cursor movement, reveal, flag and chord on buttons.
- **CRT effect:** an optional curvature and phosphor-bloom toggle.
- **Easter egg:** a tiny pixel cat named Kamille (he/him) who occasionally strolls across the HUD and naps on the minimap.

### Online (much later, and only after a security review)
- **Leaderboards through the existing Discord bot.** Players submit replay files, the bot re-simulates them in a sandbox to verify the score (replays are built for exactly this), then posts the board. Outbound connections only; no new open ports on the home server.
- **Share seeds with friends.** Known answer to "does the same seed always give the same board?": **not across different play paths.** The generator re-rolls mines the player knows nothing about when a new area needs repair, and what it repairs depends on what that player has uncovered. Two players on one seed share the start and most of the board, but can differ wherever one run needed a repair the other didn't. Only identical play reproduces identical boards, which is how replays work. Truly shareable seeds would need the player-independent generation noted under Versus mode.
