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
