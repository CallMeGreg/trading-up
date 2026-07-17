#!/usr/bin/env python3
"""Trading Up sound effects — deterministic, dependency-free SFX synthesis.

Every sound the app plays is synthesized here from scratch using only the Python
standard library (no numpy/scipy), so the whole SFX set can be regenerated on any
machine with just `python3`. Output is 16-bit mono PCM WAV at 44.1 kHz written to
`TradingUp/Audio/SFX/`, where the Xcode file-system-synchronized target bundles
them automatically. The app plays them via `SoundManager` (see
TradingUp/Audio/SoundManager.swift).

Design goals: short, punchy, on-brand for a collectible-card game. The app keeps a
deliberately minimal set — a purchase chime when you buy a pack, a sparkly shimmer
for foil pulls, and a coin chime when cards are sold. Everything is peak-normalized
and fenced with short fades so there are no clicks.

Usage:
  python3 tools/generate_sfx.py            # (re)generate every SFX into the app
  python3 tools/generate_sfx.py --list     # print the sounds that will be written
"""
import math
import os
import struct
import sys
import wave

SR = 44100
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "TradingUp", "Audio", "SFX")

# ------------------------------------------------------------------ note helpers

# Equal-tempered frequency for a MIDI-ish note name (A4 = 440).
_NOTE_BASE = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}


def hz(name):
    """'A4' -> 440.0, 'C#5' -> 554.37, etc."""
    letter = name[0].upper()
    i = 1
    semitone = _NOTE_BASE[letter]
    if len(name) > 1 and name[1] in "#b":
        semitone += 1 if name[1] == "#" else -1
        i = 2
    octave = int(name[i:])
    midi = semitone + (octave + 1) * 12
    return 440.0 * (2.0 ** ((midi - 69) / 12.0))


# ------------------------------------------------------------------ buffer utils

def buf(dur):
    return [0.0] * int(SR * dur)


def _idx(t):
    return int(t * SR)


def add(dst, src, at=0.0, gain=1.0):
    """Mix src into dst starting at time `at` (seconds), extending dst if needed."""
    start = _idx(at)
    need = start + len(src)
    if need > len(dst):
        dst.extend([0.0] * (need - len(dst)))
    for i, s in enumerate(src):
        dst[start + i] += s * gain
    return dst


# ------------------------------------------------------------------- envelopes

def env_exp(n, decay=8.0, attack=0.004):
    """Fast linear attack into an exponential decay. Length n samples."""
    out = [0.0] * n
    a = max(1, int(attack * SR))
    for i in range(n):
        amp = math.exp(-decay * i / SR)
        if i < a:
            amp *= i / a
        out[i] = amp
    return out


def env_ar(n, attack, release):
    """Linear attack / linear release plateau envelope."""
    out = [0.0] * n
    a = max(1, int(attack * SR))
    r = max(1, int(release * SR))
    for i in range(n):
        if i < a:
            out[i] = i / a
        elif i > n - r:
            out[i] = max(0.0, (n - i) / r)
        else:
            out[i] = 1.0
    return out


# --------------------------------------------------------------------- voices

def sine(freq, dur, decay=6.0, attack=0.004, vibrato=0.0, vib_hz=6.0):
    n = int(SR * dur)
    e = env_exp(n, decay, attack)
    out = [0.0] * n
    for i in range(n):
        t = i / SR
        f = freq * (1.0 + vibrato * math.sin(2 * math.pi * vib_hz * t))
        out[i] = math.sin(2 * math.pi * f * t) * e[i]
    return out


def bell(freq, dur, partials=((1, 1.0), (2.01, 0.5), (2.99, 0.34),
                              (4.2, 0.22), (5.4, 0.14)), decay=5.0):
    """Inharmonic additive tone — metallic/bell-like, great for chimes & coins."""
    n = int(SR * dur)
    out = [0.0] * n
    for ratio, amp in partials:
        e = env_exp(n, decay * (0.6 + 0.5 * ratio), attack=0.003)
        w = 2 * math.pi * freq * ratio
        for i in range(n):
            out[i] += math.sin(w * i / SR) * e[i] * amp
    return _norm(out)


def brass(freq, dur, decay=3.2, harmonics=9, vibrato=0.008):
    """Bright harmonic tone (1/n partials) for triumphant fanfares."""
    n = int(SR * dur)
    e = env_exp(n, decay, attack=0.012)
    out = [0.0] * n
    for i in range(n):
        t = i / SR
        f = freq * (1.0 + vibrato * math.sin(2 * math.pi * 5.5 * t))
        s = 0.0
        for h in range(1, harmonics + 1):
            s += math.sin(2 * math.pi * f * h * t) / h
        out[i] = s * e[i]
    return _norm(out)


class _NoiseLP:
    """One-pole low-pass filtered white noise using a tiny LCG (deterministic)."""

    def __init__(self, seed=1):
        self.state = seed & 0xFFFFFFFF
        self.y = 0.0

    def _white(self):
        self.state = (1103515245 * self.state + 12345) & 0x7FFFFFFF
        return (self.state / 0x3FFFFFFF) - 1.0

    def run(self, n, cutoff_start, cutoff_end):
        out = [0.0] * n
        for i in range(n):
            frac = i / max(1, n - 1)
            cutoff = cutoff_start + (cutoff_end - cutoff_start) * frac
            a = math.exp(-2 * math.pi * cutoff / SR)
            self.y = (1 - a) * self._white() + a * self.y
            out[i] = self.y
        return out


def noise_swept(dur, c0, c1, decay=6.0, seed=1, hp=False):
    n = int(SR * dur)
    src = _NoiseLP(seed).run(n, c0, c1)
    if hp:  # crude high-pass: subtract the low-passed signal from a brighter copy
        lp = _NoiseLP(seed + 7).run(n, 400, 400)
        src = [s - 0.6 * l for s, l in zip(src, lp)]
    e = env_exp(n, decay, attack=0.002)
    return _norm([s * e[i] for i, s in enumerate(src)])


# --------------------------------------------------------------------- utility

def _norm(sig, peak=1.0):
    m = max((abs(x) for x in sig), default=0.0)
    if m < 1e-9:
        return sig
    k = peak / m
    return [x * k for x in sig]


def finalize(sig, gain=0.85, fade_in=0.003, fade_out=0.02):
    """Peak-normalize, apply headroom gain, and fence with fades."""
    sig = _norm(sig)
    n = len(sig)
    fi = max(1, int(fade_in * SR))
    fo = max(1, int(fade_out * SR))
    out = [0.0] * n
    for i in range(n):
        g = gain
        if i < fi:
            g *= i / fi
        if i > n - fo:
            g *= max(0.0, (n - i) / fo)
        out[i] = max(-1.0, min(1.0, sig[i] * g))
    return out


def write_wav(name, sig):
    path = os.path.join(OUT_DIR, name + ".wav")
    frames = bytearray()
    for s in sig:
        frames += struct.pack("<h", int(max(-1.0, min(1.0, s)) * 32767))
    with wave.open(path, "w") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(bytes(frames))
    return path, len(sig) / SR


# ------------------------------------------------------------------- the sounds

def s_purchase():
    b = buf(0.32)
    add(b, bell(hz("E5"), 0.16, decay=7), 0.0, 0.8)
    add(b, bell(hz("B5"), 0.20, decay=6), 0.09, 0.9)
    add(b, noise_swept(0.06, 6000, 2500, decay=25, seed=3, hp=True), 0.0, 0.25)
    return finalize(b, gain=0.7)


def _shimmer(dur, base=3000, seed=21):
    """A tremolo cluster of high partials — the 'sparkle' bed for foils/ultras."""
    n = int(SR * dur)
    out = [0.0] * n
    rng = _NoiseLP(seed)
    partials = [base * r for r in (1.0, 1.26, 1.5, 1.88, 2.34, 3.0)]
    for f in partials:
        detune = 1.0 + 0.01 * rng._white()
        phase = 2 * math.pi * (0.5 * rng._white() + 0.5)
        trem_hz = 7 + 6 * (rng._white() * 0.5 + 0.5)
        for i in range(n):
            t = i / SR
            trem = 0.5 + 0.5 * math.sin(2 * math.pi * trem_hz * t + phase)
            amp = math.exp(-2.5 * t) * trem
            out[i] += math.sin(2 * math.pi * f * detune * t) * amp
    return _norm(out)


def s_foil_shimmer():
    b = _shimmer(0.55, base=2600, seed=17)
    add(b, noise_swept(0.2, 9000, 6000, decay=10, seed=19, hp=True), 0.0, 0.2)
    return finalize(b, gain=0.6, fade_in=0.008, fade_out=0.07)


def s_coin():
    b = buf(0.3)
    add(b, bell(hz("B5"), 0.18, partials=((1, 1.0), (2.76, 0.6), (5.4, 0.3)), decay=9),
        0.0, 0.9)
    add(b, bell(hz("E6"), 0.22, partials=((1, 1.0), (2.76, 0.6), (5.4, 0.3)), decay=8),
        0.05, 0.85)
    return finalize(b, gain=0.65)


SOUNDS = {
    "purchase": s_purchase,
    "foil_shimmer": s_foil_shimmer,
    "coin": s_coin,
}


def main():
    if "--list" in sys.argv:
        for k in SOUNDS:
            print(k)
        return
    os.makedirs(OUT_DIR, exist_ok=True)
    print("Generating {} sound effects -> {}".format(len(SOUNDS), OUT_DIR))
    total = 0.0
    for name, fn in SOUNDS.items():
        path, dur = write_wav(name, fn())
        total += dur
        print("  {:16s} {:5.0f} ms".format(name + ".wav", dur * 1000))
    print("Done. {} files, {:.1f}s of audio.".format(len(SOUNDS), total))


if __name__ == "__main__":
    main()
