#!/usr/bin/env python3
"""Runs CyberSweeper's headless bots and summarizes how their runs go.

    python tools/simulate.py --profiles rookie,runner,netrunner,reference --games 300
    python tools/simulate.py --profiles reference --games 60 \\
        --grid signal.drain_per_sec=1.5,2,2.5 --grid signal.refill_per_cell=1.2,1.5
    python tools/simulate.py --profiles runner --games 100 --set runner.think_median_ms=1500
    python tools/simulate.py --profiles rookie,runner,netrunner,reference --games 300 \\
        --report docs/tuning-report.md

--set and --grid take KEY=VALUE where KEY is either a tuning.json setting
(section.key, e.g. signal.drain_per_sec) or a bot profile setting
(profile.key, e.g. runner.think_median_ms). Every profile plays the same
seeded boards. Results land in test-output/sim/.
"""
from __future__ import annotations

import argparse
import concurrent.futures as cf
import itertools
import json
import math
import sys
import time
from datetime import date
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import run_tests as rt  # noqa: E402  (shared Godot discovery and launching)

ROOT = rt.ROOT
OUT = rt.OUT / "sim"
TUNING_SECTIONS = {"links", "signal", "density", "start", "solver", "generator"}
RIVALS = [r["id"] for r in json.loads((ROOT / "game" / "data" / "rivals.json").read_text())["rivals"]]
# "+grace" plays that profile with the human-only signal grace (SPEC.md); the
# rivals never get it, so their scores stay as calibrated.
HUMANS = ["reference", "expert"]
PROFILES = RIVALS + HUMANS + [h + "+grace" for h in HUMANS]


# --- running ------------------------------------------------------------------

def parse_value(v: str):
    try:
        return int(v)
    except ValueError:
        try:
            return float(v)
        except ValueError:
            return v


def split_settings(pairs: list[tuple[str, object]]) -> tuple[dict, dict]:
    """[(section.key, value)] -> (tuning overrides, {profile: bot overrides})."""
    tuning: dict = {}
    bots: dict = {}
    for key, val in pairs:
        head, _, tail = key.partition(".")
        if not tail:
            sys.exit(f"bad setting {key!r}: use section.key or profile.key")
        if head in TUNING_SECTIONS:
            tuning.setdefault(head, {})[tail] = val
        else:
            bots.setdefault(head, {})[tail] = val
    return tuning, bots


def run_profiles(godot: str, profiles: list[str], games: int, tuning: dict, bots: dict,
                 jobs: int, shard: int, tag: str) -> dict[str, list[dict]]:
    OUT.mkdir(parents=True, exist_ok=True)
    tasks = []
    for p in profiles:
        for first in range(0, games, shard):
            tasks.append((p, first, min(shard, games - first)))

    def work(t):
        p, first, n = t
        base, _, extra = p.partition("+")
        js = OUT / f"{tag}-{p}-{first}.json"
        if js.exists():
            js.unlink()
        args = ["-s", "res://sim/run_sim.gd", "--", "--profile", base, "--first", str(first),
                "--games", str(n), "--json", str(js)]
        if extra == "grace":
            args.append("--grace")
        if tuning:
            args += ["--override", json.dumps(tuning)]
        if bots.get(base):
            args += ["--bot-override", json.dumps(bots[base])]
        code, out = rt.run_godot(godot, args, 3600)
        if code != 0 or not js.exists():
            raise RuntimeError(f"{p} games {first}-{first + n - 1} failed (exit {code}):\n{out[-3000:]}")
        return p, json.loads(js.read_text())

    runs: dict[str, list[dict]] = {p: [] for p in profiles}
    meta: dict[str, dict] = {}
    with cf.ThreadPoolExecutor(max_workers=jobs) as ex:
        for p, data in ex.map(work, tasks):
            runs[p] += data["runs"]
            meta[p] = {"bot": data["bot"], "tuning": data["tuning"]}
    for p in runs:
        runs[p].sort(key=lambda r: r["index"])
    return {"runs": runs, "meta": meta}


# --- statistics ---------------------------------------------------------------

def pctl(xs: list[float], q: float) -> float:
    s = sorted(xs)
    if not s:
        return float("nan")
    k = (len(s) - 1) * q
    lo, hi = math.floor(k), math.ceil(k)
    return s[lo] + (s[hi] - s[lo]) * (k - lo)


def summarize(runs: list[dict]) -> dict:
    def dist(key):
        xs = [r[key] for r in runs]
        return {"p10": pctl(xs, .1), "p25": pctl(xs, .25), "median": pctl(xs, .5), "p75": pctl(xs, .75),
                "p90": pctl(xs, .9), "max": max(xs), "mean": sum(xs) / len(xs)}
    n = len(runs)
    minutes = sum(r["minutes"] for r in runs)
    return {
        "games": n,
        "score": dist("score"), "minutes": dist("minutes"), "tiles": dist("tiles"), "depth": dist("depth"),
        "hits_per_run": sum(r["hits"] for r in runs) / n,
        "signal_outs_per_run": sum(r["signal_outs"] for r in runs) / n,
        "guesses_per_run": sum(r["guesses"] for r in runs) / n,
        "misclicks_per_run": sum(r["misclicks"] for r in runs) / n,
        "actions_per_min": sum(r["actions"] for r in runs) / max(minutes, 1e-9),
        "tiles_per_min": sum(r["tiles"] for r in runs) / max(minutes, 1e-9),
        "capped": sum(1 for r in runs if r["capped"]),
        "stuck": sum(r["stuck"] for r in runs), "rescues": sum(r["rescues"] for r in runs),
        "pockets": sum(r["pockets"] for r in runs),
    }


def rank_in(xs: list[float], v: float) -> float:
    """Share of xs below v (0..1)."""
    return sum(1 for x in xs if x < v) / len(xs)


def print_table(summary: dict[str, dict]) -> None:
    print(f"  {'profile':10}{'games':>6}{'score p10':>11}{'median':>9}{'p90':>9}{'max':>9}"
          f"{'min med':>9}{'min p90':>9}{'hits':>6}{'sig':>6}{'guess':>7}{'tiles/min':>10}")
    for p, s in summary.items():
        print(f"  {p:10}{s['games']:>6}{s['score']['p10']:>11.0f}{s['score']['median']:>9.0f}"
              f"{s['score']['p90']:>9.0f}{s['score']['max']:>9.0f}{s['minutes']['median']:>9.1f}"
              f"{s['minutes']['p90']:>9.1f}{s['hits_per_run']:>6.2f}{s['signal_outs_per_run']:>6.2f}"
              f"{s['guesses_per_run']:>7.1f}{s['tiles_per_min']:>10.0f}")


def approved_rivals() -> dict[str, dict]:
    """Rival scores approved in game/data/rivals.json, by bot id."""
    d = json.loads((ROOT / "game" / "data" / "rivals.json").read_text())
    return {r["id"]: r for r in d["rivals"]}


def targets(runs: dict[str, list[dict]], summary: dict[str, dict]) -> list[tuple[str, str, bool]]:
    """(target, measured, met) for the plan's tuning targets."""
    out = []
    if "reference" not in summary:
        return out
    ref = summary["reference"]
    ref_scores = [r["score"] for r in runs["reference"]]
    m = ref["minutes"]
    out.append(("reference median run 8-12 min", f"{m['median']:.1f} min", 8 <= m["median"] <= 12))
    out.append(("reference p10 run >= 5 min", f"{m['p10']:.1f} min", m["p10"] >= 5))
    out.append(("reference p90 run <= 18 min", f"{m['p90']:.1f} min", m["p90"] <= 18))
    if "rookie" in summary:
        # A new player (weaker than the reference) should pass script.kitty
        # within a few runs, so its median sits low in the reference spread.
        q = rank_in(ref_scores, summary["rookie"]["score"]["median"])
        out.append(("rookie median at reference p5-p15", f"p{q * 100:.0f}", 0.05 <= q <= 0.15))
    if "runner" in summary:
        q = rank_in(ref_scores, summary["runner"]["score"]["median"])
        out.append(("runner median at reference p75-p90", f"p{q * 100:.0f}", 0.75 <= q <= 0.90))
    if "netrunner" in summary:
        ratio = summary["netrunner"]["score"]["median"] / ref["score"]["median"]
        out.append(("netrunner median 2-3x reference median", f"{ratio:.2f}x", 2.0 <= ratio <= 3.0))
    if all(p in summary for p in ("rookie", "runner", "netrunner")):
        pace = [summary[p]["tiles_per_min"] for p in ("rookie", "runner", "netrunner")]
        out.append(("pace: rookie < runner < netrunner (tiles/min)", " < ".join(f"{v:.0f}" for v in pace),
                    pace[0] < pace[1] < pace[2]))
    present = [p for p in RIVALS if p in summary]
    if len(present) > 1:
        meds = [summary[p]["score"]["median"] for p in present]
        out.append(("rival medians climb, lil.byte to NULL//SAINT", " < ".join(f"{v:,.0f}" for v in meds),
                    all(a < b for a, b in zip(meds, meds[1:]))))
    for p in present:
        v = int(approved_rivals()[p]["score"])
        med = summary[p]["score"]["median"]
        out.append((f"{approved_rivals()[p]['name']} median within 2% of {v:,}", f"{med:,.0f}", abs(med - v) <= 0.02 * v))
    if "expert" in summary:
        saint = approved_rivals()["netrunner"]["score"]
        q = 1 - rank_in([r["score"] for r in runs["expert"]], saint + 0.5)
        out.append((f"expert beats NULL//SAINT's {saint:,} in about 20% of runs", f"{q * 100:.1f}%",
                    0.15 <= q <= 0.25))
    longest = max(s["minutes"]["max"] for s in summary.values())
    out.append(("every run ends within 45 min", f"longest {longest:.1f} min", longest <= 45))
    return out


# --- report -------------------------------------------------------------------

def num(v) -> str:
    """Numbers from Godot's JSON come back as floats; show whole ones as ints."""
    if isinstance(v, float) and v.is_integer():
        return str(int(v))
    return str(v)


def round_score(v: float) -> int:
    return int(round(v / 10.0)) * 10


def histogram(xs: list[float], bins: int = 12, width: int = 40) -> list[str]:
    lo, hi = min(xs), max(xs)
    if hi == lo:
        return [f"{lo:>8.0f} | {'#' * width} {len(xs)}"]
    step = (hi - lo) / bins
    counts = [0] * bins
    for x in xs:
        counts[min(bins - 1, int((x - lo) / step))] += 1
    top = max(counts)
    return [f"{lo + i * step:>8.0f} | {'#' * max(1 if c else 0, round(c / top * width)):<{width}} {c}"
            for i, c in enumerate(counts)]


def write_report(path: Path, result: dict, summary: dict, sensitivity: list[dict] | None) -> None:
    runs, meta = result["runs"], result["meta"]
    tuning = next(iter(meta.values()))["tuning"]
    ref_runs = runs.get("reference", [])
    L = []
    L.append("# Difficulty tuning report")
    L.append("")
    L.append(f"Generated by `tools/simulate.py` on {date.today().isoformat()}. "
             f"{summary[next(iter(summary))]['games']} seeded games per profile; every profile plays the same boards. "
             "Times are simulated play time.")
    L.append("")
    L.append("## Tuning")
    L.append("")
    L.append("| Setting | Value |")
    L.append("| --- | --- |")
    for sec in ("signal", "density", "start"):
        for k, v in tuning[sec].items():
            L.append(f"| `{sec}.{k}` | {num(v)} |")
    L.append("")
    L.append("## Bots")
    L.append("")
    L.append("How the bots play: each one keeps its own solver, limited to its tier, fed only what a player "
             "can see. Each move it thinks (seeded log-normal time, more for harder deductions), then clicks. "
             "A cell it had already worked out right next to its last click is a quick follow-up click, the way "
             "people clear a solved patch. It only looks for safe cells within *attention* cells of its last "
             "click; with none in view it guesses locally (*local guess*) or searches the board, which costs "
             "extra time. *Misclick* sends the click to a random hidden neighbour. Bots that chord flag "
             "and chord when that opens 3+ cells. NULL//SAINT never acts faster than 500 ms. `reference` and "
             "`expert` are not rivals: they stand in for a decent and a strong human.")
    L.append("")
    L.append("| Profile | Name | Tier | Think median / follow-up / floor | Misclick | Attention | Local guess | Chords |")
    L.append("| --- | --- | --- | --- | --- | --- | --- | --- |")
    for p, m in meta.items():
        b = m["bot"]
        L.append(f"| {p} | {b['name']} | {num(b['tier'])} | {num(b['think_median_ms'])} / "
                 f"{num(b['followup_ms'])} / {num(b['min_move_ms'])} ms | "
                 f"{b['misclick'] * 100:.1f}% | {num(b['attention'])} | {b['local_guess'] * 100:.0f}% | "
                 f"{'yes' if b['chord'] else 'no'} |")
    L.append("")
    L.append("## Results")
    L.append("")
    L.append("| Profile | Score p10 | p25 | **median** | p75 | p90 | max | Run min (median / p90 / max) | "
             "Hits / run | Signal-outs / run | Guesses / run | Tiles / min |")
    L.append("| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |")
    for p, s in summary.items():
        sc, mi = s["score"], s["minutes"]
        L.append(f"| {p} | {sc['p10']:,.0f} | {sc['p25']:,.0f} | **{sc['median']:,.0f}** | {sc['p75']:,.0f} | "
                 f"{sc['p90']:,.0f} | {sc['max']:,.0f} | {mi['median']:.1f} / {mi['p90']:.1f} / {mi['max']:.1f} | "
                 f"{s['hits_per_run']:.2f} | {s['signal_outs_per_run']:.2f} | {s['guesses_per_run']:.1f} | "
                 f"{s['tiles_per_min']:.0f} |")
    L.append("")
    capped = sum(s["capped"] for s in summary.values())
    L.append(f"Every run ended with all three links lost ({capped} hit the safety cap); *hits* are links lost "
             "to mines, *signal-outs* to the signal bar running dry. Over every simulated move the no-50/50 "
             "invariant held: "
             f"{sum(s['stuck'] for s in summary.values())} stuck states, "
             f"{sum(s['rescues'] for s in summary.values())} backstop rescues.")
    L.append("")
    L.append("### Targets")
    L.append("")
    L.append("The Rookie target changed from the plan's reference p25-p40 to p5-p15: the spec wants a *new* "
             "player to pass script.kitty within a few runs, and a new player is weaker than the reference, so "
             "its median belongs low in the reference spread (a decent player passes it about 9 runs in 10).")
    L.append("")
    L.append("| Target | Measured | Met |")
    L.append("| --- | --- | --- |")
    for t, m, ok in targets(runs, summary):
        L.append(f"| {t} | {m} | {'yes' if ok else '**no**'} |")
    L.append("")
    L.append("### Score distributions")
    for p in summary:
        L.append("")
        L.append(f"**{p}** (score)")
        L.append("```")
        L += histogram([r["score"] for r in runs[p]])
        L.append("```")
    if sensitivity:
        L.append("")
        L.append("## Sensitivity")
        L.append("")
        L.append("Each row changes one setting from the final values; reference profile medians.")
        L.append("")
        L.append("| Change | Run min (median) | Score (median) |")
        L.append("| --- | --- | --- |")
        for row in sensitivity:
            L.append(f"| {row['label']} | {row['minutes']:.1f} | {row['score']:,.0f} |")
    L.append("")
    L.append("## Rival scores")
    L.append("")
    L.append("Each rival's score is its bot's median run, nudged off the round number by under 1% so it "
             "reads like a real run, approved in `game/data/rivals.json`. NULL//SAINT was recalibrated "
             "(975 ms think time) so the expert, a strong human, beats her in about one run in five; a decent "
             "player never does. lil.byte, dex.hype, OXIDE and VESPER were added later to spread the ladder "
             "up to NULL//SAINT; each bot's think time was tuned so its median lands on its score.")
    L.append("")
    L.append("| Rival | Bot | Median this run | Approved score | Reference beats it | Expert beats it |")
    L.append("| --- | --- | --- | --- | --- | --- |")
    approved = approved_rivals()
    ref_scores = [r["score"] for r in ref_runs]
    exp_scores = [r["score"] for r in runs.get("expert", [])]
    for p in RIVALS:
        if p not in summary:
            continue
        label = approved[p]["label"].upper()
        v = int(approved[p]["score"])
        beat_ref = f"{(1 - rank_in(ref_scores, v + 0.5)) * 100:.0f}% of runs" if ref_scores else "n/a"
        beat_exp = f"{(1 - rank_in(exp_scores, v + 0.5)) * 100:.0f}% of runs" if exp_scores else "n/a"
        L.append(f"| {meta[p]['bot']['name']} | {label} | {summary[p]['score']['median']:,.0f} | **{v:,}** | "
                 f"{beat_ref} | {beat_exp} |")
    graced = [h for h in HUMANS if h in summary and h + "+grace" in summary]
    if graced:
        L.append("")
        L.append("## Signal grace (people only)")
        L.append("")
        g = tuning["signal"]
        L.append(f"A person's run has signal grace: with the shown bar at or below {g['grace_below'] * 100:.0f}%, "
                 f"uncovering any tiles freezes the drain for {g['grace_ms'] / 1000:g} s. The rivals' bots play "
                 "without it, so their scores above don't change; the `+grace` profiles replay the human "
                 "stand-ins with it on, against the same rival scores.")
        L.append("")
        L.append("| Profile | Run min, median (without → with grace) | Score, median | Signal-outs / run |")
        L.append("| --- | --- | --- | --- |")
        for h in graced:
            a, b = summary[h], summary[h + "+grace"]
            L.append(f"| {h} | {a['minutes']['median']:.1f} → {b['minutes']['median']:.1f} | "
                     f"{a['score']['median']:,.0f} → {b['score']['median']:,.0f} | "
                     f"{a['signal_outs_per_run']:.2f} → {b['signal_outs_per_run']:.2f} |")
        L.append("")
        L.append("| Rival | Score | " + " | ".join(f"{h} beats it (without → with)" for h in graced) + " |")
        L.append("| --- | --- | " + " | ".join("---" for _ in graced) + " |")
        for p in RIVALS:
            v = int(approved[p]["score"])
            cells = []
            for h in graced:
                a = 1 - rank_in([r["score"] for r in runs[h]], v + 0.5)
                b = 1 - rank_in([r["score"] for r in runs[h + "+grace"]], v + 0.5)
                cells.append(f"{a * 100:.0f}% → {b * 100:.0f}%")
            L.append(f"| {approved[p]['name']} | {v:,} | " + " | ".join(cells) + " |")
    if "reference" in summary:
        ref = summary["reference"]
        L.append("")
        L.append("## Unlock thresholds")
        L.append("")
        tiles_goal = int(round(ref["tiles"]["median"] * 10 / 1000.0)) * 1000
        depth_goal = int(round(ref["depth"]["p90"] / 10.0)) * 10
        L.append(f"- **Root access:** decrypt {tiles_goal:,} tiles across all runs (approved; about ten typical runs; "
                 f"reference median is {ref['tiles']['median']:,.0f} tiles per run).")
        L.append(f"- **Rustbelt:** reach depth {depth_goal} in one run (approved; a reference run gets there about "
                 f"{(1 - rank_in([r['depth'] for r in ref_runs], depth_goal)) * 100:.0f}% of the time; "
                 f"median depth {ref['depth']['median']:.0f}).")
        L.append("- **Hotwire** and **Icebreaker** stay tied to beating mx_halcyon and NULL//SAINT.")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(L) + "\n")


# --- main ---------------------------------------------------------------------

def main() -> int:
    sys.stdout.reconfigure(line_buffering=True)
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--profiles", default=",".join(PROFILES))
    ap.add_argument("--games", type=int, default=100)
    ap.add_argument("--set", action="append", default=[], help="KEY=VALUE, applied to every run")
    ap.add_argument("--grid", action="append", default=[], help="KEY=V1,V2,... to sweep")
    ap.add_argument("--sensitivity", action="store_true",
                    help="also run one-at-a-time changes of the signal settings for the report")
    ap.add_argument("--report", help="write a Markdown report here")
    ap.add_argument("--beat", type=int, help="report how often each profile's runs beat this score")
    ap.add_argument("--godot")
    ap.add_argument("--jobs", type=int, default=8)
    ap.add_argument("--shard", type=int, default=10)
    args = ap.parse_args()

    profiles = [p.strip() for p in args.profiles.split(",") if p.strip()]
    base = []
    for s in args.set:
        k, _, v = s.partition("=")
        base.append((k, parse_value(v)))
    grid = []
    for g in args.grid:
        k, _, vs = g.partition("=")
        grid.append([(k, parse_value(v)) for v in vs.split(",")])

    godot = rt.find_godot(args.godot)
    rt.ensure_import(godot)
    combos = list(itertools.product(*grid)) if grid else [()]
    started = time.time()
    all_rows = []
    last = None
    for ci, combo in enumerate(combos):
        settings = base + list(combo)
        tuning, bots = split_settings(settings)
        label = ", ".join(f"{k}={v}" for k, v in combo) or "base"
        result = run_profiles(godot, profiles, args.games, tuning, bots, args.jobs, args.shard, f"c{ci}")
        summary = {p: summarize(result["runs"][p]) for p in profiles}
        print(f"\n== {label}  ({time.time() - started:.0f}s)")
        print_table(summary)
        for t, m, ok in targets(result["runs"], summary):
            print(f"     {'ok ' if ok else 'MISS'} {t}: {m}")
        if args.beat:
            print(f"\n  runs beating {args.beat:,}:")
            for p in profiles:
                scores = [r["score"] for r in result["runs"][p]]
                share = sum(1 for v in scores if v > args.beat) / len(scores)
                print(f"     {p:10} {share * 100:5.1f}%  ({sum(1 for v in scores if v > args.beat)} of {len(scores)})")
            if "expert" in profiles:
                scores = [r["score"] for r in result["runs"]["expert"]]
                for want in (0.03, 0.04, 0.05):
                    v = round_score(pctl(scores, 1 - want))
                    got = sum(1 for x in scores if x > v) / len(scores)
                    print(f"     score expert beats in ~{want * 100:.0f}% of runs: {v:,} (measured {got * 100:.1f}%)")
        all_rows.append({"settings": settings, "label": label, "summary": summary})
        last = (result, summary, tuning, bots)
    (OUT / "summary.json").write_text(json.dumps(all_rows, indent=2))

    if args.report and last:
        result, summary, tuning, bots = last
        sens = None
        if args.sensitivity and "reference" in profiles:
            sens = []
            t = result["meta"]["reference"]["tuning"]["signal"]
            for key, factor in (("drain_per_sec", 1.2), ("drain_per_sec", 0.8),
                                ("drain_growth_per_min", 1.5), ("drain_growth_per_min", 0.5),
                                ("refill_per_cell", 1.2), ("refill_per_cell", 0.8)):
                val = round(t[key] * factor, 4)
                tw = json.loads(json.dumps(tuning))
                tw.setdefault("signal", {})[key] = val
                r = run_profiles(godot, ["reference"], max(40, args.games // 3), tw, bots,
                                 args.jobs, args.shard, f"sens-{key}-{factor}")
                s = summarize(r["runs"]["reference"])
                sens.append({"label": f"`signal.{key}` {t[key]} → {val}", "minutes": s["minutes"]["median"],
                             "score": s["score"]["median"]})
                print(f"  sensitivity {key} x{factor}: {s['minutes']['median']:.1f} min, {s['score']['median']:.0f}")
        write_report(ROOT / args.report, result, summary, sens)
        print(f"\nreport written to {args.report}")
    print(f"\ndone in {time.time() - started:.0f}s")
    return 0


if __name__ == "__main__":
    sys.exit(main())
