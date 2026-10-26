#!/usr/bin/env python3
"""Copies the design assets the game uses from design/ into game/assets/.

    python tools/sync_design.py          # copy (only files that changed)
    python tools/sync_design.py --check  # exit 1 if any copy is missing or differs

design/ stays the source of truth and is never modified. The game reads
colors only from game/assets/tokens/palettes.json, which must match
design/tokens/palettes.json byte for byte.
"""
from __future__ import annotations

import argparse
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DESIGN = ROOT / "design"
ASSETS = ROOT / "game" / "assets"

FILES = [
    ("tokens/palettes.json", "tokens/palettes.json"),
    ("fonts/OFL-ChakraPetch.txt", "fonts/OFL-ChakraPetch.txt"),
    ("fonts/OFL-MartianMono.txt", "fonts/OFL-MartianMono.txt"),
] + [(f"fonts/ChakraPetch-{w}.ttf", f"fonts/ChakraPetch-{w}.ttf") for w in (400, 500, 600, 700)] \
  + [(f"fonts/MartianMono-{w}.ttf", f"fonts/MartianMono-{w}.ttf") for w in (300, 400, 600, 800)]


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()
    bad = []
    for src, dst in FILES:
        s, d = DESIGN / src, ASSETS / dst
        same = d.exists() and d.read_bytes() == s.read_bytes()
        if args.check:
            if not same:
                bad.append(dst)
        elif not same:
            d.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(s, d)
            print(f"copied {src}")
    if args.check:
        if bad:
            print("out of date: " + ", ".join(bad) + " (run tools/sync_design.py)")
            return 1
        print(f"all {len(FILES)} design assets match")
    return 0


if __name__ == "__main__":
    sys.exit(main())
