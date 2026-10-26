#!/usr/bin/env python3
"""Synthesizes CyberSweeper's sound effects into game/assets/sfx/*.wav.

    python tools/make_sfx.py

Every sound is generated here from sine, square, saw and noise, so they are
original to this project (see CREDITS.md). Deterministic: same files every run.
"""
from __future__ import annotations

import math
import random
import struct
import wave
from pathlib import Path

RATE = 44100
OUT = Path(__file__).resolve().parent.parent / "game" / "assets" / "sfx"
rng = random.Random(1)


def env(t: float, attack: float, decay: float) -> float:
    if t < attack:
        return t / attack
    return math.exp(-(t - attack) / decay)


def tone(freq0: float, freq1: float, dur: float, shape: str = "sine", vol: float = 0.3,
         attack: float = 0.002, decay: float = 0.04) -> list[float]:
    out, phase = [], 0.0
    n = int(dur * RATE)
    for i in range(n):
        t = i / RATE
        f = freq0 + (freq1 - freq0) * (i / n)
        phase += 2 * math.pi * f / RATE
        if shape == "sine":
            s = math.sin(phase)
        elif shape == "square":
            s = 1.0 if math.sin(phase) >= 0 else -1.0
        else:  # saw
            s = 2.0 * ((phase / (2 * math.pi)) % 1.0) - 1.0
        out.append(s * vol * env(t, attack, decay))
    return out


def noise(dur: float, vol: float, decay: float, hp: float = 0.0) -> list[float]:
    out, prev = [], 0.0
    for i in range(int(dur * RATE)):
        x = rng.uniform(-1, 1)
        y = x - hp * prev   # crude high-pass when hp > 0
        prev = x
        out.append(y * vol * env(i / RATE, 0.001, decay))
    return out


def crush(xs: list[float], bits: int = 6, hold: int = 3) -> list[float]:
    q = 2 ** (bits - 1)
    out, last = [], 0.0
    for i, x in enumerate(xs):
        if i % hold == 0:
            last = round(x * q) / q
        out.append(last)
    return out


def mix(*tracks: list[float], at: list[float] | None = None) -> list[float]:
    at = at or [0.0] * len(tracks)
    n = max(int(a * RATE) + len(t) for a, t in zip(at, tracks))
    out = [0.0] * n
    for a, t in zip(at, tracks):
        o = int(a * RATE)
        for i, s in enumerate(t):
            out[o + i] += s
    return out


def save(name: str, xs: list[float]) -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    peak = max(1e-9, max(abs(x) for x in xs))
    k = 0.9 / peak if peak > 0.9 else 1.0
    with wave.open(str(OUT / f"{name}.wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, x * k)) * 32767)) for x in xs))
    print(f"wrote {name}.wav ({len(xs) / RATE * 1000:.0f} ms)")


def main() -> None:
    save("reveal", mix(tone(900, 1350, 0.05, "sine", 0.35, decay=0.018),
                       tone(1800, 2700, 0.03, "sine", 0.08, decay=0.01)))
    save("cascade", mix(*[tone(f, f * 1.02, 0.06, "sine", 0.28, decay=0.025) for f in (660, 880, 1100, 1320)],
                        noise(0.12, 0.05, 0.05, hp=0.9), at=[0.0, 0.028, 0.056, 0.084, 0.0]))
    save("flag", mix(noise(0.025, 0.25, 0.006, hp=0.95), tone(2400, 2200, 0.03, "sine", 0.25, decay=0.008)))
    save("hit", mix(tone(140, 45, 0.26, "sine", 0.6, decay=0.09),
                    crush(noise(0.22, 0.45, 0.06), bits=5, hold=4),
                    crush(tone(320, 80, 0.18, "square", 0.18, decay=0.05), bits=4, hold=6)))
    save("link", crush(mix(tone(620, 150, 0.38, "saw", 0.32, decay=0.16),
                           tone(310, 75, 0.38, "square", 0.12, decay=0.16)), bits=6, hold=2))
    save("low", mix(tone(1200, 1200, 0.07, "square", 0.09, decay=0.04),
                    tone(900, 900, 0.07, "square", 0.09, decay=0.04), at=[0.0, 0.09]))
    save("end", mix(*[tone(f, f * 0.99, 0.3, "saw", 0.2, attack=0.005, decay=0.12) for f in (440, 349, 262)],
                    at=[0.0, 0.16, 0.32]))


if __name__ == "__main__":
    main()
