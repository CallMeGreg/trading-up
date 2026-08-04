#!/usr/bin/env python3
"""Trading Up sound effects — deterministic, dependency-free SFX synthesis.

Every sound the app plays is synthesized here from scratch using only the Python
standard library (no numpy/scipy), so the whole SFX set can be regenerated on any
machine with just `python3`. Output is 16-bit mono PCM WAV at 44.1 kHz written to
`TradingUp/Audio/SFX/`, where the Xcode file-system-synchronized target bundles
them automatically. The app plays them via `SoundManager` (see
TradingUp/Audio/SoundManager.swift).

Design goals: short, punchy, on-brand for a collectible-card game. The set covers
the shop (a purchase chime when you buy a pack, a coin chime when cards are sold)
and the pack reveal (a paper-rip pack-open, a soft card-flip, an airy foil glisten,
and "achievement unlocked" stings for rare and ultra pulls). Everything is
peak-normalized and fenced with short fades so there are no clicks.

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


def s_pack_open():
    # Gritty paper/foil rip — two quick tears into an airy "shhh", seated with a
    # soft low settle. Mirrors the two-beat tear animation in SealedPackView.
    b = buf(0.46)
    add(b, noise_swept(0.14, 5000, 2200, decay=13, seed=8, hp=True), 0.00, 0.9)
    add(b, noise_swept(0.12, 4200, 1800, decay=14, seed=12, hp=True), 0.09, 0.8)
    add(b, noise_swept(0.26, 3200, 900, decay=6, seed=15, hp=True), 0.15, 0.7)
    add(b, sine(78, 0.18, decay=9, attack=0.002), 0.26, 0.32)
    return finalize(b, gain=0.72, fade_in=0.002, fade_out=0.06)


def s_card_flip():
    # Soft, dark "ffttt" as the next card slides up — two very quiet overlapping
    # low-passed brushes, kept short so a fast reveal doesn't wash out.
    b = buf(0.18)
    add(b, noise_swept(0.13, 2000, 900, decay=12, seed=101), 0.0, 0.55)
    add(b, noise_swept(0.10, 1500, 680, decay=16, seed=103), 0.03, 0.40)
    return finalize(b, gain=0.36, fade_in=0.007, fade_out=0.04)


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
    # Airy "glisten": a wide shimmer bed with a rising sparkle of high bells.
    b = _shimmer(0.8, base=2500, seed=52)
    for i, note in enumerate(("B5", "E6", "G#6", "B6", "D#7")):
        add(b, bell(hz(note), 0.18, decay=7), 0.04 + i * 0.07, 0.26)
    add(b, noise_swept(0.22, 10000, 7000, decay=9, seed=57, hp=True), 0.0, 0.16)
    return finalize(b, gain=0.58, fade_in=0.008, fade_out=0.1)


def s_rare():
    # "Achievement unlocked": an ascending C-E-G arpeggio resolving on a ringing
    # top note, with a faint sparkle tail.
    b = buf(0.7)
    add(b, bell(hz("C5"), 0.18, decay=7), 0.00, 0.70)
    add(b, bell(hz("E5"), 0.18, decay=7), 0.08, 0.75)
    add(b, bell(hz("G5"), 0.40, decay=5), 0.16, 0.92)
    add(b, _shimmer(0.30, base=3800, seed=211), 0.16, 0.13)
    return finalize(b, gain=0.72, fade_in=0.003, fade_out=0.06)


def s_ultra():
    # The rare motif made triumphant: a quick rising run into a big major chord
    # stab over a brass swell, a low boom and a shimmer tail.
    b = buf(1.25)
    add(b, sine(hz("A2"), 0.22, decay=6, attack=0.004), 0.0, 0.45)   # boom
    add(b, bell(hz("E5"), 0.16, decay=8), 0.05, 0.60)
    add(b, bell(hz("A5"), 0.16, decay=8), 0.12, 0.65)
    add(b, bell(hz("C#6"), 0.18, decay=8), 0.19, 0.68)
    for note, gn in (("A5", 0.80), ("C#6", 0.70), ("E6", 0.65)):     # chord stab
        add(b, bell(hz(note), 0.42, decay=5), 0.30, gn)
    add(b, brass(hz("A4"), 0.50, decay=2.9), 0.30, 0.40)
    add(b, brass(hz("E5"), 0.50, decay=2.9), 0.30, 0.30)
    add(b, _shimmer(0.55, base=3100, seed=241), 0.30, 0.38)
    return finalize(b, gain=0.72, fade_in=0.004, fade_out=0.13)


def s_coin():
    b = buf(0.3)
    add(b, bell(hz("B5"), 0.18, partials=((1, 1.0), (2.76, 0.6), (5.4, 0.3)), decay=9),
        0.0, 0.9)
    add(b, bell(hz("E6"), 0.22, partials=((1, 1.0), (2.76, 0.6), (5.4, 0.3)), decay=8),
        0.05, 0.85)
    return finalize(b, gain=0.65)


SOUNDS = {
    "purchase": s_purchase,
    "pack_open": s_pack_open,
    "card_flip": s_card_flip,
    "foil_shimmer": s_foil_shimmer,
    "rare": s_rare,
    "ultra": s_ultra,
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
