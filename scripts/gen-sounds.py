#!/usr/bin/env python3
"""Synthesises Volt's 28 sounds into NotchBuddy/Resources/sounds/.

VoltaDock's character is a little battery, so its voice is electric: chirps,
zaps, charge-up sweeps and small square-ish blips. Everything is generated
here from plain maths (standard library only), so the sounds are VoltaDock's
own and can be tweaked and regenerated:

    python3 scripts/gen-sounds.py

Both apps use these files: the Mac app bundles the folder and the Windows app
serves it (see windows/vite.config.ts, SOUNDS_DIR). Output is 48 kHz, 16-bit
stereo WAV, the format the players already expect. The apps play them at a low
master volume (0.12 by default), so peaks here are fairly loud on purpose.
"""

import math
import os
import random
import struct
import wave

SR = 48_000
OUT = os.path.join(os.path.dirname(__file__), "..", "NotchBuddy", "Resources", "sounds")
TAU = 2 * math.pi


def note(name: str) -> float:
    """'A4' → 440 Hz."""
    names = {"C": -9, "D": -7, "E": -5, "F": -4, "G": -2, "A": 0, "B": 2}
    n = names[name[0]]
    rest = name[1:]
    if rest.startswith("#"):
        n += 1
        rest = rest[1:]
    elif rest.startswith("b"):
        n -= 1
        rest = rest[1:]
    return 440.0 * 2 ** ((n + (int(rest) - 4) * 12) / 12)


def osc(kind: str, phase: float) -> float:
    s = math.sin(phase)
    if kind == "sine":
        return s
    if kind == "tri":
        return 2 / math.pi * math.asin(s)
    if kind == "soft":  # rounded square: a bit buzzy, never harsh
        return math.tanh(3.2 * s) / math.tanh(3.2)
    raise ValueError(kind)


def env(t: float, dur: float, attack: float, release: float) -> float:
    if t < 0 or t > dur:
        return 0.0
    a = min(1.0, t / attack) if attack > 0 else 1.0
    r = min(1.0, (dur - t) / release) if release > 0 else 1.0
    return a * r


class Track:
    def __init__(self, dur: float):
        self.n = int(dur * SR)
        self.buf = [0.0] * self.n

    def tone(self, start, dur, f0, f1=None, kind="soft", amp=0.5, attack=0.004,
             release=None, curve=1.0, vib=0.0, vib_rate=6.0, decay=0.0):
        """Pitch glides f0 → f1 (exponential-ish with `curve`), optional vibrato and decay."""
        f1 = f0 if f1 is None else f1
        release = dur * 0.6 if release is None else release
        i0 = int(start * SR)
        phase = 0.0
        for i in range(int(dur * SR)):
            j = i0 + i
            if j >= self.n:
                break
            t = i / SR
            k = (t / dur) ** curve
            f = f0 * (f1 / f0) ** k
            if vib:
                f *= 1 + vib * math.sin(TAU * vib_rate * t)
            phase += TAU * f / SR
            g = env(t, dur, attack, release) * (math.exp(-decay * t) if decay else 1.0)
            self.buf[j] += amp * g * osc(kind, phase)

    def noise(self, start, dur, amp=0.3, tone=0.5, seed=1, attack=0.002, decay=30.0):
        """Filtered noise burst — `tone` 0 (dark) … 1 (bright)."""
        rnd = random.Random(seed)
        i0 = int(start * SR)
        lp = 0.0
        a = 0.05 + 0.9 * tone
        for i in range(int(dur * SR)):
            j = i0 + i
            if j >= self.n:
                break
            t = i / SR
            lp += a * (rnd.uniform(-1, 1) - lp)
            g = env(t, dur, attack, dur * 0.3) * math.exp(-decay * t)
            self.buf[j] += amp * g * lp

    def crackle(self, start, dur, amp=0.25, rate=90.0, seed=7):
        """Sparse electric clicks."""
        rnd = random.Random(seed)
        i0 = int(start * SR)
        for i in range(int(dur * SR)):
            j = i0 + i
            if j >= self.n:
                break
            if rnd.random() < rate / SR:
                for k in range(48):
                    if j + k < self.n:
                        self.buf[j + k] += amp * math.exp(-k / 8) * (1 if k % 2 == 0 else -1) * (1 - i / (dur * SR))

    def write(self, name: str, peak: float):
        m = max(1e-9, max(abs(x) for x in self.buf))
        scale = peak / m
        frames = bytearray()
        for x in self.buf:
            v = int(max(-32767, min(32767, x * scale * 32767)))
            frames += struct.pack("<hh", v, v)
        with wave.open(os.path.join(OUT, f"{name}.wav"), "wb") as w:
            w.setnchannels(2)
            w.setsampwidth(2)
            w.setframerate(SR)
            w.writeframes(bytes(frames))


def make() -> dict:
    s = {}

    # ── Small UI sounds ──────────────────────────────────────────────────────
    t = Track(0.07); t.tone(0, 0.06, 2600, 2200, "sine", decay=60); s["hover"] = (t, 0.05)
    t = Track(0.06); t.tone(0, 0.05, 3200, 2800, "tri", decay=80); t.noise(0, 0.01, 0.2, 1.0, decay=400); s["tick"] = (t, 0.08)
    t = Track(0.1); t.tone(0, 0.09, 1800, 2100, "tri", decay=25); s["blip"] = (t, 0.06)
    t = Track(0.2); t.tone(0, 0.19, 1300, 2200, "soft", amp=0.35, decay=12); s["wink"] = (t, 0.2)
    t = Track(0.22); t.tone(0, 0.2, 900, 260, "sine", curve=0.5, decay=10); s["pop"] = (t, 0.3)

    # ── Island open / close ──────────────────────────────────────────────────
    t = Track(0.35)
    t.tone(0, 0.32, 520, 1250, "tri", curve=0.7, release=0.15)
    t.crackle(0.05, 0.2, 0.12, rate=60)
    s["peek"] = (t, 0.18)
    t = Track(0.32); t.tone(0, 0.12, note("E5"), kind="soft", amp=0.3); t.tone(0.1, 0.2, note("B5"), kind="soft", amp=0.3, decay=8); s["open"] = (t, 0.15)
    t = Track(0.3); t.tone(0, 0.12, note("B5"), kind="soft", amp=0.3); t.tone(0.1, 0.18, note("E5"), kind="soft", amp=0.3, decay=10); s["close"] = (t, 0.1)

    # ── Greeting: charge up, then two happy chirps ───────────────────────────
    t = Track(0.85)
    t.tone(0, 0.42, 220, 1100, "soft", amp=0.35, curve=1.6, release=0.05)
    t.crackle(0.1, 0.32, 0.15, rate=120)
    t.tone(0.46, 0.12, note("E6"), kind="tri", amp=0.5, decay=6)
    t.tone(0.6, 0.22, note("A6"), kind="tri", amp=0.5, decay=8)
    s["greet"] = (t, 0.5)

    # ── Pokes ────────────────────────────────────────────────────────────────
    t = Track(0.4)
    t.noise(0, 0.08, 0.6, 0.8, seed=3, decay=50)
    t.tone(0, 0.3, 170, 70, "sine", amp=0.8, decay=9)
    t.crackle(0.02, 0.2, 0.3, rate=200, seed=4)
    s["slap"] = (t, 0.5)
    t = Track(0.5); t.tone(0, 0.45, 420, 240, "soft", amp=0.4, vib=0.06, vib_rate=18); s["annoyed"] = (t, 0.3)
    t = Track(1.0)
    t.tone(0, 0.95, 700, 300, "tri", vib=0.25, vib_rate=5, release=0.3)
    t.tone(0, 0.95, 520, 900, "sine", amp=0.25, vib=0.2, vib_rate=7, release=0.3)
    s["dizzy"] = (t, 0.35)

    # ── Claude Code states ───────────────────────────────────────────────────
    t = Track(0.35); t.tone(0, 0.08, 1100, kind="soft", amp=0.3, decay=30); t.tone(0.14, 0.12, 1480, kind="soft", amp=0.3, decay=25); s["work"] = (t, 0.15)
    t = Track(0.45)
    for i, f in enumerate([note("G5"), note("D6"), note("A5")]):
        t.tone(i * 0.13, 0.12, f, kind="sine", amp=0.4, decay=18)
    s["think"] = (t, 0.15)
    t = Track(0.5); t.tone(0, 0.18, 1500, kind="sine", decay=14); t.tone(0.2, 0.25, 1500, kind="sine", amp=0.35, decay=14); s["search"] = (t, 0.15)
    t = Track(0.88)
    for i, f in enumerate([880, 1320, 880]):
        t.tone(i * 0.22, 0.2, f, f * 1.03, "soft", amp=0.45, decay=8)
        t.crackle(i * 0.22, 0.08, 0.2, rate=300, seed=10 + i)
    s["approval"] = (t, 0.5)
    t = Track(0.65); t.tone(0, 0.18, note("E5"), kind="tri"); t.tone(0.2, 0.4, note("A5"), note("D6"), "tri", curve=2.5); s["question"] = (t, 0.35)
    t = Track(0.45); t.tone(0, 0.14, note("G5"), kind="tri", decay=6); t.tone(0.12, 0.3, note("C6"), kind="tri", decay=6); s["approve"] = (t, 0.3)
    t = Track(1.15)
    for i, n in enumerate(["C5", "E5", "G5", "C6"]):
        t.tone(i * 0.11, 0.3 if i < 3 else 0.7, note(n), kind="tri", amp=0.45, decay=4)
    t.crackle(0.45, 0.5, 0.12, rate=80, seed=21)
    s["finish"] = (t, 0.5)
    t = Track(0.8); t.tone(0, 0.3, 330, 300, "soft", amp=0.5); t.tone(0.34, 0.42, 247, 200, "soft", amp=0.5, decay=3); s["error"] = (t, 0.4)
    t = Track(0.7); t.tone(0, 0.65, 800, 140, "soft", amp=0.4, curve=0.6, release=0.2); t.crackle(0.3, 0.3, 0.12, rate=40, seed=31); s["rate"] = (t, 0.3)
    t = Track(0.5); t.tone(0, 0.22, note("E5"), kind="sine", amp=0.4); t.tone(0.2, 0.3, note("B4"), kind="sine", amp=0.4, decay=5); s["sleep"] = (t, 0.15)
    t = Track(0.75); t.tone(0, 0.72, 700, 260, "sine", vib=0.03, vib_rate=5, release=0.3); s["yawn"] = (t, 0.2)

    # ── Emotes ───────────────────────────────────────────────────────────────
    t = Track(0.8)
    for i, n in enumerate(["A4", "C#5", "E5"]):
        t.tone(i * 0.12, 0.6 - i * 0.12, note(n), kind="sine", amp=0.35, vib=0.01, vib_rate=6)
    s["love"] = (t, 0.3)
    t = Track(0.88)
    for i, (n, d) in enumerate([("G4", 0.1), ("C5", 0.1), ("E5", 0.1), ("G5", 0.45)]):
        t.tone(i * 0.11, d, note(n), kind="soft", amp=0.35, decay=3)
    s["proud"] = (t, 0.35)

    # ── Files ────────────────────────────────────────────────────────────────
    t = Track(0.75); t.tone(0, 0.5, 520, 110, "sine", amp=0.7, curve=0.5); t.tone(0.42, 0.08, 300, 500, "sine", amp=0.4); t.tone(0.55, 0.08, 320, 560, "sine", amp=0.3); s["gulp"] = (t, 0.35)
    t = Track(0.5); t.noise(0, 0.45, 0.6, 0.6, seed=5, attack=0.15, decay=4); t.tone(0.05, 0.38, 600, 1600, "sine", amp=0.25, curve=1.5); s["send"] = (t, 0.25)
    t = Track(0.9)
    t.noise(0, 0.02, 0.4, 1.0, seed=8, decay=200)
    t.tone(0.05, 0.16, note("D5"), kind="tri", decay=8)
    t.tone(0.2, 0.5, note("A5"), kind="tri", decay=5)
    t.crackle(0.2, 0.3, 0.1, rate=60, seed=9)
    s["attach"] = (t, 0.3)
    return s


if __name__ == "__main__":
    sounds = make()
    assert len(sounds) == 28, len(sounds)
    for name, (track, peak) in sorted(sounds.items()):
        track.write(name, peak)
        print(f"{name}.wav")
