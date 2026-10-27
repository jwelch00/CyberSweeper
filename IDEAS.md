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

## Lore encyclopedia

Some nodes on the board are specially highlighted. Decrypting one unlocks a lore drop in a new encyclopedia section of the menu. Entries can also unlock by beating rivals and by reaching milestones such as total score or depth.

- **Where the lore starts:** the rival lines already drop hints (`game/data/rivals.json`): Tetsukage and its secure lattice, OXIDE writing half its ICE, the nine seconds the lattice went dark, VESPER's old run with NULL//SAINT and the run VESPER keeps pinned. Entries can fill these threads in, while the lines stay hints.
- **Unlock sources:**
  - **Highlighted nodes** (data shards) on the board;
  - **Rivals:** beating each one unlocks their entry. `Profile.beaten` already records this;
  - **Milestones:** best depth and total tiles are already tracked (palette unlocks use them); total score and runs played would be new stats. `unlocks.json`'s rule types (`beat_rival`, `total_tiles`, `depth`) could be reused for entries.
- **Encyclopedia screen:** categories such as the rivals, Tetsukage and the lattice. Locked entries show encrypted text, like a locked palette's preview, and new ones get the "New" tag.

### Notes for whoever builds it

- **A highlight must say nothing about mines.** If highlights only went on safe cells, each one would be a free, guaranteed-safe click: a pickup, which the core rule forbids. Place them from a hash of the seed and the cell, independent of the mine layout, so some sit on mines.
  - A highlighted safe cell decrypts when it's revealed.
  - A highlighted mine decrypts once the revealed numbers prove it's a mine. The solver can already tell. Flags never count, so a wrong flag can't unlock anything.

  Either way the reward is for reading the board, never for guessing.
- **Feel, never rules:** no score bonus, no signal refill beyond a normal decrypt, no effect on the links. Rival scores and their calibration stay untouched.
- **Rarity and determinism:** a few per run at most (one per so many chunks), the same cells for the same seed. Which entry a shard gives could be the next locked one, so shards never repeat.
- **To decide:** whether Ghost runs can find shards. Ghost counts toward no unlocks today (SPEC.md).
- **Save data:** a `lore` list of unlocked ids and an `unseen` list for the "New" tag, the same pattern as palettes in `Profile`.
- **Content:** a `lore.json` with each entry's id, category, title, text and unlock rule, tested like `rivals.json`: every entry reachable, the text fits its screen.

## Live hacking events

The lore: every run is a scheduled hacking event, hosted by a fringe netrunner group. Everyone in the event keeps playing until they get iced, and the rivals are in the same event as you, so the board is live.

- **Scores move every run.** After each run, every rival's score is a fresh draw near their typical score, and that's the end-game leaderboard. There's never a set number to beat: you can score 7,013 and still lose to a NULL//SAINT who posted 7,020 tonight. It'll feel unfair, and that's how it goes.
- **A live HUD leaderboard** under the score. Every rival starts the run at 0 and climbs while you play. They swap places now and then, with some obvious skyrockets and stragglers.
- **VESPER and NULL//SAINT** run neck and neck at the top until you beat them.
- **ICED:** once you pass a rival, their score keeps rising a little, then their row is crossed out with ICED over it.
- **The game over** shows the event's final standings.

### Notes for whoever builds it

- **The rivals' climbs can come from real bot runs.** `tools/simulate.py` already plays each rival's bot through the real game, in simulated time. Recording score over time for a few dozen runs per rival gives real curves: cascades are the skyrockets, slow thinkers the stragglers. Each run picks one curve per rival from its seed, so a seed always gives the same event and replays still verify.
- **Keep the draws honest:**
  - draw each rival's final score from that bot's own score spread, narrowed so it reads as a good or bad night, not a different rival;
  - never react to the player's score (no rubber-banding), or it stops feeling like a busy event and starts feeling rigged.

  The one exception is the ICED moment: after you pass someone they creep up a little, but never back past you.
- **"Beating" a rival needs a rule.** With the ICED moment, passing someone is final: they can't come back, so passing them is beating them, and that's when RIVAL DOWN plays. Rivals you never pass keep climbing to their final score, and the game over compares against that.
- **Unlocks:** Hotwire and Icebreaker say "beat mx_halcyon" and "beat NULL//SAINT". Decide whether that means beating that run's draw (a little luck) or keeping each rival's typical score as the fixed unlock line, with the event board as the drama. Either way, re-check the calibration (the expert bot beats NULL//SAINT about one run in five) with the simulator.
- **HUD space and calm:** eight rows is a lot under the score. A window like the game-over ladder fits better: the top rival, plus the rows around you. Place swaps should animate gently and follow reduce motion. ICED is text and a strike-through, never color alone.
- **Unchanged:** it's still pure minesweeper. The event is presentation: it adds no resource and changes no rule. Ghost mode stays rival-free. The Rivals screen keeps each rival's typical score and bio.
- **Lore hooks:**
  - the group running the events could be tied to the nine seconds the lattice went dark;
  - the game over could say ICED instead of LINK SEVERED. That changes `design/MOTION.md`'s card, so it needs a design proposal first.
- **Compared with Versus mode:** Versus races one rival on a mirrored board. An event races everyone, each on their own board, so it needs none of Versus's identical-board work.

## Signal grace near empty (a rebalance for humans)

When you're playing well but haven't landed a good chord or cascade, the signal still runs out, and that feels really bad. Humans sometimes need just a hair more thinking time than the bots.

- **The rule:** when the on-screen signal bar is at about 10–15%, uncovering any number of tiles freezes the bar for a few seconds (about 3 to start). One tile is enough. Chords and cascades count too.
- **Humans only:** the bots keep the original rule, so every rival's score stays exactly as it is (847 to 7,013).

### Notes for whoever builds it

- **Still pure minesweeper:** this only changes when the existing signal drains. It adds no resource and no pickup. It's Arcade only, since Ghost has no signal.
- **What the player sees:** the bar uses a false scale (`signal.display_curve`). Define the 10–15% band on the shown bar and convert it with the same curve, so it matches what's on screen.
- **Settings in `tuning.json`:** the band, the freeze length, and a switch that player runs turn on and bot runs leave off. The tuning hash then keeps replays with and without grace apart.
- **Exact for replays:** the freeze has to be part of the integer signal drain (`Rules.drained_u`) and the exact moment a run ends. That way a replay still reproduces the run to the millisecond however the frames fall (`tests/unit/test_replay.gd`).
- **Stacking:**
  - a reveal during a freeze restarts it at full length, without adding to it;
  - it can trigger again and again in one dip, because every trigger needs real progress and reveals refill the bar out of the band anyway.
- **Showing it:** the meter shows the hold with a "hold" tag next to "signal low" and the bar's drain stopped, never with color alone. The low-signal alarm pauses during the hold.
- **Rivals get easier, on purpose:** with the bots on the old rule, a person beats each rival a bit more often than the calibration says. Have `tools/simulate.py` measure how much: run the reference and expert profiles with grace on against the unchanged rival scores, and report the new beat rates next to the old ones.

## More ideas

### Gameplay
- **Race your ghost:** a faded replay of your personal best plays on the same seed alongside you. This needs identical boards for both, like Versus mode, and replays make it straightforward.
- **Mutators:** optional run modifiers with score multipliers and their own leaderboard. Like Ghost and Versus they're separate opt-in modes: they may change the links or the timer, but never add a power-up or a new resource (SPEC.md's core rule):
  - Iron link: 1 link, 2× score.
  - No flags.
  - Blackout: numbers fade 5 s after they're revealed.
- **Sectors:** as depth increases, the board passes through named sectors ("Sector 7 // Cold storage"), with subtle visual shifts like a tint or a different cipher glyph style, so an infinite board still feels like a journey.
- **Landmarks:** rare authored structures inside the procedural board, such as a wide zero "data lake" or a dense "firewall" band, still validated by the no-50/50 solver.
- **Rival rematches:** after you beat a rival, they come back later with a higher score and a new taunt, so the chase never fully ends. (VESPER and NULL//SAINT already have rematch *lines* for after you've beaten them; their scores don't change.)

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
