# CyberSweeper — notes for Claude Code

CyberSweeper is an infinite-board, no-guessing Minesweeper with a cyberpunk look, built in Godot 4 for Windows, macOS and Linux, distributed as a download from a home Red Hat server.

## Read first
- `SPEC.md` is the full brief. Re-read it at the start of every milestone.
- `design/README.md` explains every design file. `design/png/` has the screens; `design/index.html` lets you browse the HTML mockups in any palette.

## How we work
- One milestone at a time, in the order SPEC.md lists. Plan first (plan mode), then build, then stop and summarize what's done, what's tested, and anything you decided on your own. Wait for my review before starting the next milestone.
- If the spec and the design disagree, or something in the spec turns out to be a bad idea, say so and ask instead of quietly picking.
- Keep `README.md` current: how to build, test and run, plus the exact Godot version.

## Hard rules
- No 50/50 guesses, ever (see SPEC.md). Flags never count as information. The property tests for this must pass before any milestone is called done.
- The game makes zero network calls. No telemetry, no update checks, no online leaderboards.
- All colors come from `design/tokens/palettes.json`. Don't hand-copy hex values.
- Game logic stays free of rendering code so tests and bots run headless.
- Treat `design/` as reference: don't edit or delete files in it. If a design change is needed, propose it.
- Never connect to, SSH into, or run commands against my server. Write the deploy script and instructions; I run them.
- Only CC0 or self-made audio and art, and OFL fonts (already in `design/fonts/`). List every third-party asset and its license in `CREDITS.md`.

## Environment
- My dev machine is Windows. Builds must work from Windows; keep scripts cross-platform.
- The server is Red Hat Linux with nginx, SELinux enforcing, and firewalld.
