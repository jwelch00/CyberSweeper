#!/usr/bin/env python3
"""Runs CyberSweeper's headless test suites. Works on Windows, macOS and Linux.

    python tools/run_tests.py                 # fast: unit + UI smoke + 200 property games
    python tools/run_tests.py --suite gate    # unit + UI smoke + 3,000 property games (milestone gate)
    python tools/run_tests.py --suite unit
    python tools/run_tests.py --suite property --driver sloppy --games 50 --moves 300

Godot is found via --godot, the GODOT environment variable, .tools/ in the repo,
or godot / godot4 on PATH. Property games run in parallel worker processes at
low CPU priority. Exit code is non-zero if anything failed.
"""
from __future__ import annotations

import argparse
import concurrent.futures as cf
import json
import os
import platform
import shutil
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GAME = ROOT / "game"
OUT = ROOT / "test-output"

SUITES = {
    # driver -> (games, moves)
    "fast": {"perfect": (80, 300), "sloppy": (60, 300), "wanderer": (60, 300)},
    "gate": {"perfect": (1000, 400), "sloppy": (1000, 400), "wanderer": (1000, 400)},
}
ERROR_MARKERS = ("SCRIPT ERROR", "Parse Error", "Compile Error", "Assertion failed")


def find_godot(explicit: str | None) -> str:
    cands: list[str] = []
    if explicit:
        cands.append(explicit)
    if os.environ.get("GODOT"):
        cands.append(os.environ["GODOT"])
    tools = ROOT / ".tools"
    if tools.is_dir():
        if platform.system() == "Windows":
            cands += [str(p) for p in sorted(tools.glob("Godot_v4*_console.exe"))]
            cands += [str(p) for p in sorted(tools.glob("Godot_v4*.exe"))]
        else:
            cands.append(str(tools / "godot"))
            cands += [str(p) for p in sorted(tools.glob("Godot_v4*"))]
    for name in ("godot4", "godot", "Godot_v4.7.2-stable_win64_console.exe"):
        found = shutil.which(name)
        if found:
            cands.append(found)
    for c in cands:
        if Path(c).is_file():
            return c
    sys.exit("Godot not found. Pass --godot PATH or set GODOT (see README).")


def low_priority_kwargs() -> dict:
    if platform.system() == "Windows":
        return {"creationflags": subprocess.BELOW_NORMAL_PRIORITY_CLASS}
    return {"preexec_fn": lambda: os.nice(19)}


def run_godot(godot: str, args: list[str], timeout: int, headless: bool = True) -> tuple[int, str]:
    cmd = [godot] + (["--headless"] if headless else []) + ["--path", str(GAME)] + args
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout,
                           encoding="utf-8", errors="replace", **low_priority_kwargs())
    except subprocess.TimeoutExpired as e:
        def text(b) -> str:
            return b.decode("utf-8", "replace") if isinstance(b, bytes) else (b or "")
        return 124, text(e.stdout) + text(e.stderr) + f"\nTIMEOUT after {timeout}s"
    out = p.stdout + p.stderr
    code = p.returncode
    if code == 0 and any(m in out for m in ERROR_MARKERS):
        code = 3
    return code, out


def ensure_import(godot: str) -> None:
    # Builds Godot's class cache so class_name scripts resolve headless.
    code, out = run_godot(godot, ["--import"], 600)
    if any(m in out for m in ERROR_MARKERS):
        print(out)
        sys.exit("Godot reported script errors during import.")


def run_unit(godot: str) -> bool:
    print("== unit tests")
    code, out = run_godot(godot, ["-s", "res://tests/run_tests.gd", "--", "--suite", "unit"], 1800)
    for line in out.splitlines():
        if line.startswith("Godot Engine"):
            continue
        if line.strip().startswith("ok "):
            continue
        if line.strip():
            print("  " + line)
    return code == 0


def run_ui_smoke(godot: str) -> bool:
    print("== ui smoke (the real gameplay screen, driven by input events)")
    code, out = run_godot(godot, ["--resolution", "1920x1080", "-s", "res://tests/ui_smoke.gd"], 600)
    for line in out.splitlines():
        if line.startswith("FAIL") or line.startswith("ui smoke") or "SCRIPT ERROR" in line:
            print("  " + line)
    return code == 0


def pct(hist: dict, q: float) -> float | None:
    items = sorted((int(k), v) for k, v in hist.items())
    n = sum(v for _, v in items)
    if n == 0:
        return None
    acc = 0
    for k, v in items:
        acc += v
        if acc >= q * n:
            return k / 10.0
    return items[-1][0] / 10.0


def run_property(godot: str, plan: dict, jobs: int, shard: int) -> tuple[bool, dict]:
    OUT.mkdir(exist_ok=True)
    (OUT / "shards").mkdir(exist_ok=True)
    tasks = []
    for driver, (games, moves) in plan.items():
        for first in range(0, games, shard):
            n = min(shard, games - first)
            tasks.append((driver, first, n, moves))
    total_games = sum(g for g, _ in plan.values())
    print(f"== property: {total_games} games in {len(tasks)} shards, {jobs} workers")
    started = time.time()
    results: dict[str, list[dict]] = {d: [] for d in plan}
    problems: list[str] = []

    def work(t):
        driver, first, n, moves = t
        js = OUT / "shards" / f"{driver}-{first}.json"
        if js.exists():
            js.unlink()
        args = ["-s", "res://tests/run_tests.gd", "--", "--suite", "property", "--driver", driver,
                "--first", str(first), "--games", str(n), "--moves", str(moves),
                "--json", str(js), "--out", str(OUT)]
        code, out = run_godot(godot, args, 3600)
        data = json.loads(js.read_text()) if js.exists() else None
        return t, code, out, data

    done = 0
    with cf.ThreadPoolExecutor(max_workers=jobs) as ex:
        for t, code, out, data in ex.map(work, tasks):
            done += 1
            driver, first, n, _ = t
            if data is None or code not in (0, 1):
                problems.append(f"{driver} games {first}-{first + n - 1}: exit {code}\n{out[-3000:]}")
            if data is not None:
                results[driver].append(data)
                for f in data["failures"]:
                    problems.append(f"{driver} #{f['index']} (seed {f['seed']}) move {f['move']}: {f['msg']}\n    {f['file']}")
            if done % max(1, len(tasks) // 10) == 0 or done == len(tasks):
                print(f"  {done}/{len(tasks)} shards, {time.time() - started:.0f}s")

    report = {"suite_seconds": round(time.time() - started, 1), "drivers": {}}
    for driver, shards in results.items():
        tot: dict = {}
        gen: dict = {}
        hist: dict = {}
        fails = 0
        for d in shards:
            for k, v in d["total"].items():
                tot[k] = max(tot.get(k, 0), v) if k == "max_depth" else tot.get(k, 0) + v
            for k, v in d["gen"].items():
                gen[k] = gen.get(k, 0) + v
            for name, h in d["hist"].items():
                acc = hist.setdefault(name, {})
                for b, c in h.items():
                    acc[b] = acc.get(b, 0) + c
            fails += len(d["failures"])
        timing = {name: {q: pct(h, v) for q, v in (("p50", .5), ("p90", .9), ("p99", .99), ("max", 1.0))}
                  for name, h in hist.items()}
        report["drivers"][driver] = {"total": tot, "gen": gen, "failures": fails, "timing_ms": timing}
    (OUT / "report.json").write_text(json.dumps(report, indent=2))
    print_report(report)
    for p in problems[:20]:
        print("  FAIL " + p)
    if len(problems) > 20:
        print(f"  ... {len(problems) - 20} more")
    ok = not problems
    for r in report["drivers"].values():
        g = r["gen"]
        if g.get("rescues", 0) or g.get("unsound", 0) or g.get("contradictions", 0):
            ok = False
    return ok, report


def print_report(report: dict) -> None:
    print(f"\n  {'':10}{'games':>7}{'moves':>9}{'tiles':>10}{'hits':>7}{'locks':>7}{'proofs':>8}"
          f"{'pockets':>9}{'near isl':>9}{'islands':>9}{'rescues':>9}{'fails':>7}")
    for driver, r in report["drivers"].items():
        t, g = r["total"], r["gen"]
        print(f"  {driver:10}{t.get('games', 0):>7}{t.get('moves', 0):>9}{t.get('tiles', 0):>10}"
              f"{t.get('hits', 0):>7}{g.get('locks', 0):>7}{g.get('proofs', 0):>8}{g.get('pockets', 0):>9}"
              f"{g.get('pockets_near_island', 0):>9}{g.get('islands', 0):>9}{g.get('rescues', 0):>9}{r['failures']:>7}")
    print("\n  repairs (rounds): " + ", ".join(
        f"{d} local {r['gen'].get('repair_local', 0)} / chunk {r['gen'].get('repair_chunk', 0)} / "
        f"neighbour {r['gen'].get('repair_neighbour', 0)}" for d, r in report["drivers"].items()))
    print("\n  timing ms        p50     p90     p99     max")
    names = {"move": "move (all)", "txn": "reveal txn", "proof": "chunk proof", "check": "test check"}
    for driver, r in report["drivers"].items():
        for name in ("move", "proof"):
            tm = r["timing_ms"].get(name)
            if tm:
                print(f"  {driver[:8]:8} {names[name]:12}" + "".join(
                    f"{(tm[q] if tm[q] is not None else 0):8.1f}" for q in ("p50", "p90", "p99", "max")))
    print(f"\n  wall time {report['suite_seconds']}s; full report in test-output/report.json\n")


def main() -> int:
    # Print progress as it happens even when output goes to a file or pipe.
    sys.stdout.reconfigure(line_buffering=True)
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--suite", default="fast", choices=["fast", "gate", "unit", "property"])
    ap.add_argument("--godot")
    ap.add_argument("--jobs", type=int, default=max(1, (os.cpu_count() or 2) // 2))
    ap.add_argument("--shard", type=int, default=20, help="games per worker process")
    ap.add_argument("--driver", default="perfect", help="for --suite property")
    ap.add_argument("--games", type=int, default=20, help="for --suite property")
    ap.add_argument("--moves", type=int, default=300, help="for --suite property")
    args = ap.parse_args()

    godot = find_godot(args.godot)
    print(f"Godot: {godot}")
    ensure_import(godot)
    ok = True
    if args.suite in ("fast", "gate", "unit"):
        ok = run_unit(godot) and ok
        ok = run_ui_smoke(godot) and ok
    if args.suite in ("fast", "gate"):
        prop_ok, _ = run_property(godot, SUITES[args.suite], args.jobs, args.shard)
        ok = prop_ok and ok
    elif args.suite == "property":
        prop_ok, _ = run_property(godot, {args.driver: (args.games, args.moves)}, args.jobs, args.shard)
        ok = prop_ok and ok
    print("PASS" if ok else "FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
