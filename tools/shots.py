#!/usr/bin/env python3
"""Renders the screenshots used to compare the game against design/png/.

    python tools/shots.py            # everything, into test-output/shots/
    python tools/shots.py --quick    # gallery + one gameplay shot

Needs a display (any desktop; on a headless Linux box set DISPLAY to an Xvfb).
Shots come from seeded bot runs, so they are the same every time:
  gallery-1x.png / gallery-0.5x.png   every cell state in all six palettes
  gameplay-<palette>.png              a NULL//SAINT run at 1x zoom
  zoom-0.5x.png / zoom-2x.png         the same board at the zoom limits
  ghost.png                           Ghost mode (no signal meter)
  ui-*.png                            the real screen driven by input events
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import run_tests as rt  # noqa: E402

OUT = rt.OUT / "shots"
PALETTES = ["signal", "hotwire", "root-access", "rustbelt", "icebreaker", "plaintext"]
BASE = ["--rendering-driver", "opengl3", "--resolution", "1920x1080", "--audio-driver", "Dummy"]


def shot(godot: str, args: list[str]) -> bool:
    code, out = rt.run_godot(godot, BASE + ["--"] + args, 600, headless=False)
    saved = [l for l in out.splitlines() if l.startswith("saved")]
    for l in saved:
        print("  " + l.split(" ", 1)[1].split(str(rt.ROOT) + "/")[-1])
    if code != 0 or not saved:
        print(out[-2000:])
        return False
    return True


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--godot")
    ap.add_argument("--quick", action="store_true")
    args = ap.parse_args()
    godot = rt.find_godot(args.godot)
    rt.ensure_import(godot)
    OUT.mkdir(parents=True, exist_ok=True)
    run = ["--seed", "7", "--bot", "netrunner", "--turns", "300"]
    ok = shot(godot, ["--gallery", str(OUT / "gallery.png")])
    ok = shot(godot, ["--shot", str(OUT / "gameplay-signal.png"), "--pop"] + run) and ok
    if not args.quick:
        for p in PALETTES[1:]:
            ok = shot(godot, ["--shot", str(OUT / f"gameplay-{p}.png"), "--palette", p] + run) and ok
        ok = shot(godot, ["--shot", str(OUT / "zoom-0.5x.png"), "--zoom", "0.5"] + run) and ok
        ok = shot(godot, ["--shot", str(OUT / "zoom-2x.png"), "--zoom", "2.0"] + run) and ok
        ok = shot(godot, ["--shot", str(OUT / "ghost.png"), "--mode", "ghost"] + run) and ok
        code, out = rt.run_godot(godot, BASE[:-2] + ["-s", "res://tests/ui_smoke.gd", "--", "--shots", str(OUT)],
                                 1200, headless=False)
        print("  ui smoke: " + next((l for l in out.splitlines() if l.startswith("ui smoke")), "no result"))
        ok = ok and code == 0
    print("PASS" if ok else "FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
