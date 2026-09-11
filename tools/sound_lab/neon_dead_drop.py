"""The selected Neon Dead Drop arrangement, without its brass accompaniment.

The original audition's melody, replies, bass, drums, timing and synthesis are
preserved. Events include echoes; their fingerprint pins the original score
after removing only the 448 brass events.
"""

import hashlib
import json
import math
import random
from array import array
from collections import Counter
from dataclasses import dataclass
from functools import lru_cache
from typing import NamedTuple

from .dsp import SR, TAU
from .music import AAC_FRAME, LoopMix


@dataclass(frozen=True)
class Score:
    id: str
    mode: str
    title: str
    description: str
    tempo: int
    recommended: bool
    bars: int
    root: int
    harmony: tuple
    hook: tuple
    answer: tuple
    seed: int

    @property
    def frames(self):
        return round(self.bars * 4 * 60 * SR / self.tempo / AAC_FRAME) * AAC_FRAME

    @property
    def duration(self):
        return self.frames / SR

    @property
    def bpm(self):
        return self.bars * 240 / self.duration

    @property
    def beat(self):
        return self.duration / (self.bars * 4)


SCORE = Score(
    "gauntlet-neon-dead-drop", "gauntlet", "Neon Dead Drop",
    "Selected Gauntlet / arcade drive: the original FM-pluck melody, octave bass "
    "and four-on-the-floor drums, with the offbeat brass accompaniment removed. "
    "A bass-led pocket makes room before the fuller final hook.",
    148, True, 32, 30,
    ((0, "m9"), (8, "maj9"), (10, "6"), (7, "7"),
     (5, "m9"), (0, "m9"), (8, "maj9"), (7, "7")),
    (
        ((0, 12, .22), (.75, 7, .23), (1.25, 3, .23), (2.5, 10, .28), (3.25, 7, .34)),
        ((.25, 8, .3), (1, 12, .26), (1.75, 15, .3), (2.5, 14, .25), (3.25, 12, .34)),
        ((0, 14, .22), (.75, 10, .23), (1.25, 7, .23), (2.5, 5, .28), (3.25, 10, .34)),
        ((.25, 11, .32), (1, 7, .3), (2, 4, .34), (2.75, 11, .3), (3.5, 14, .2)),
        ((.25, 8, .28), (1, 12, .3), (1.75, 17, .3), (2.5, 15, .28), (3.25, 12, .3)),
        ((0, 12, .22), (.75, 7, .23), (1.25, 3, .23), (2.5, 14, .28), (3.25, 10, .34)),
        ((.25, 12, .25), (1, 15, .25), (1.75, 14, .28), (2.75, 8, .45)),
        ((.25, 11, .3), (1, 14, .3), (2, 16, .32), (3, 11, .28), (3.5, 7, .2)),
    ),
    (
        ((.5, 7, .45), (1.75, 3, .4), (3, 10, .4)),
        ((.5, 8, .55), (2, 12, .55), (3.25, 15, .25)),
        ((.5, 10, .45), (1.75, 7, .4), (3, 5, .4)),
        ((.5, 11, .55), (2, 7, .6)),
        ((.25, 8, .42), (1.5, 5, .45), (2.75, 12, .55)),
        ((.5, 7, .45), (1.75, 10, .4), (3, 14, .4)),
        ((.5, 12, .4), (1.75, 8, .55), (3, 7, .3)),
        ((.5, 11, .55), (2, 14, .45), (3.25, 11, .3)),
    ),
    911148,
)

VOICINGS = {
    "m9": (15, 19, 22, 26),
    "maj9": (16, 19, 23, 26),
    "6": (16, 19, 21, 26),
    "7": (16, 19, 22, 26),
}
TONAL_VOICES = ("bass", "pluck", "string")
ARRANGEMENT_SHA256 = "726153e7f7561929737c1b07258145dd83ff7d079a4d12412e11fdd9dd430d9e"
INSTRUMENT_COUNTS = {
    "bass": 272, "clap": 64, "crash": 4, "hat": 256, "kick": 124,
    "open": 68, "pluck": 650, "snare": 104, "string": 8, "tom": 16,
}


class Event(NamedTuple):
    voice: str
    pitch: int
    gate_ms: int
    variation: int
    seconds: float
    gain: float
    pan: float
    send: float


def arrange(score=SCORE):
    events = []
    rng = random.Random(score.seed)

    def note(kind, pitch, position, gate, gain, pan=0, send=.16, echo=False):
        gate_ms = round(gate * score.beat * 1000)
        events.append(Event(kind, pitch, gate_ms, 0, position * score.beat, gain, pan, send))
        if echo:
            events.append(Event(kind, pitch, gate_ms, 0, (position + .75) * score.beat,
                                gain * .13, -.38, .12))
            events.append(Event(kind, pitch, gate_ms, 0, (position + 1.5) * score.beat,
                                gain * .052, .38, .09))

    def hit(kind, position, gain, pan=0, variant=0):
        send = .018 if kind == "kick" else .12 if kind in ("snare", "clap", "tom") else .035
        events.append(Event(kind, 0, 0, variant % 4, position * score.beat, gain, pan, send))

    for bar in range(score.bars):
        phrase = bar % 8
        section = bar // 8
        start = bar * 4
        offset, quality = score.harmony[phrase]
        root = score.root + offset
        next_root = score.root + score.harmony[(phrase + 1) % 8][0]
        bridge = section == 2
        final = section == score.bars // 8 - 1
        lift = 1.04 if final else .89 if bridge else 1

        bass_pattern = ((.08, 0, .28, 1), (.5, 12, .22, .76),
                        (1.08, 0, .28, .9), (1.75, 7, .21, .72),
                        (2.08, 0, .28, 1), (2.5, 12, .22, .78),
                        (3.08, 0, .26, .92))
        for at, semitones, gate, accent in bass_pattern:
            note("bass", root + semitones, start + at, gate, .285 * accent * lift, send=.012)
        note("bass", next_root - 1, start + 3.5, .18, .19 * lift, send=.01)
        if phrase % 2:
            note("bass", next_root, start + 3.75, .16, .17 * lift, send=.01)

        phrase_notes = score.answer[phrase] if bridge else score.hook[phrase]
        base = score.root + 36
        for index, (at, semitones, gate) in enumerate(phrase_notes):
            variation = .97 if index % 2 else 1.04
            position = start + at
            note("pluck", base + semitones, position, gate,
                 .235 * variation * lift, -.07, .21, echo=True)
            if final and phrase in (0, 2, 4, 6) and index in (0, 2):
                note("string", base + semitones - 12, position + .015, gate, .052, .28, .16)

        reply_at = (1, 3.5) if bridge else (.5, 1.5, 2.75, 3.75)
        chord = VOICINGS[quality]
        for index, at in enumerate(reply_at):
            pitch = root + chord[(index + phrase) % 4] + 12
            note("pluck", pitch, start + at, .18, .057 * lift,
                 -.42 if index % 2 else .42, .15, echo=phrase % 2 == 1)
        if final and phrase in (1, 5):
            for at, interval in ((2.75, 7), (3.25, 10), (3.75, 12)):
                note("pluck", base + interval, start + at, .18, .051, .28, .14)

        kicks = (0, 2) if bridge and phrase in (0, 1) else (0, 1, 2, 3)
        for index, at in enumerate(kicks):
            hit("kick", start + at, (.47 if index == 0 else .405) * lift, variant=phrase)
        for at in (1, 3):
            hit("snare", start + at, .43 * lift, .055, phrase)
            hit("clap", start + at + .012, .14 * lift, -.12, phrase + 1)
        for at in ((2.75,) if phrase % 2 else (.75,)):
            hit("snare", start + at, .081 * lift, -.10, phrase + 1)
        for index in range(8):
            at = index * 4 / 8
            accent = .78 if index % 2 == 0 else 1
            hit("hat", start + at, .155 * accent * lift * rng.uniform(.91, 1.04),
                -.26 if index % 2 else .24, index + phrase)
        for at in (1.5, 3.5):
            hit("open", start + at, .16 * lift, .28, phrase)
        if phrase in (3, 7):
            for index, (at, kind, gain) in enumerate(
                    ((3.25, "snare", .12), (3.5, "tom", .18), (3.75, "tom", .22))):
                hit(kind, start + at, gain * lift, -.24 + index * .16, 3 - index)
        if phrase == 0:
            hit("crash", start, .13 if bar == 0 else .16, -.28, section)
        if phrase == 7:
            hit("open", start + 3.875, .115, .31, section)
    return tuple(events)


def arrangement_sha256(events):
    encoded = json.dumps(events, separators=(",", ":"), allow_nan=False).encode()
    return hashlib.sha256(encoded).hexdigest()


def validate_score(score=SCORE):
    assert score.bars == 32 and score.tempo == 148 and score.frames == 2_490_368
    assert score.frames % AAC_FRAME == 0 and abs(score.bpm - score.tempo) < .04
    assert len(score.harmony) == len(score.hook) == len(score.answer) == 8
    events = arrange(score)
    assert Counter(event.voice for event in events) == INSTRUMENT_COUNTS
    assert arrangement_sha256(events) == ARRANGEMENT_SHA256, "Neon's retained arrangement changed"


def _end_window(index, count, release=.018):
    remaining = (count - 1 - index) / SR
    return .5 - .5 * math.cos(math.pi * remaining / release) if remaining < release else 1


@lru_cache(maxsize=256)
def instrument(kind, midi, gate_ms):
    gate = gate_ms / 1000
    release = {"bass": .10, "pluck": .32, "string": .21}[kind]
    count = round((gate + release) * SR)
    frequency = 440 * 2 ** ((midi - 69) / 12)
    out = array("f", [0]) * count
    phase = second = 0.0
    for index in range(count):
        t = index / SR
        step = TAU * frequency / SR
        phase += step
        second += step * 1.0025
        if kind == "bass":
            bright = math.exp(-t * 12)
            sound = (.76 * math.sin(phase)
                     + (.27 + .13 * bright) * math.sin(2 * phase)
                     + (.13 + .08 * bright) * math.sin(3 * phase)
                     + .085 * bright * math.sin(4 * phase)
                     + .042 * bright * math.sin(5 * phase))
            sound = math.tanh(sound * 1.35) / 1.35
            envelope = min(1, t / .0035) * (.78 + .22 * math.exp(-t * 8))
            envelope *= math.exp(-max(0, t - gate) * 55)
        elif kind == "pluck":
            modulation = .9 * math.exp(-t * 18)
            sound = (.70 * math.sin(phase + modulation * math.sin(2 * phase))
                     + .13 * math.sin(second)
                     + .14 * math.sin(3 * phase) * math.exp(-t * 13)
                     + .038 * math.sin(5 * phase) * math.exp(-t * 25))
            envelope = min(1, t / .003) * math.exp(-t * 5.5)
            envelope *= math.exp(-max(0, t - gate) * 18)
        else:
            sound = (.68 * math.sin(phase)
                     + .19 * math.sin(2 * phase) * math.exp(-t * 12)
                     + .13 * math.sin(3 * phase) * math.exp(-t * 19)
                     + .065 * math.sin(4 * phase) * math.exp(-t * 26)
                     + .04 * math.sin(6 * phase) * math.exp(-t * 34))
            envelope = min(1, t / .0025) * math.exp(-t * 7)
            envelope *= math.exp(-max(0, t - gate) * 27)
        out[index] = sound * envelope * _end_window(index, count)
    return out


@lru_cache(maxsize=64)
def drum(kind, variation=0):
    rng = random.Random(88419 + 97 * variation + sum(map(ord, kind)))
    duration = {"kick": .34, "snare": .25, "hat": .075, "open": .28,
                "clap": .23, "tom": .28, "crash": .85}[kind]
    count = round(duration * SR)
    out = array("f", [0]) * count
    fast = low = metal = phase = 0.0
    for index in range(count):
        t = index / SR
        noise = rng.uniform(-1, 1)
        fast += .61 * (noise - fast)
        low += .115 * (fast - low)
        metal += .45 * (noise - metal)
        band = fast - low
        if kind == "kick":
            phase += TAU * (49 + 94 * math.exp(-t * 43)) / SR
            sound = (.84 * math.sin(phase) + .19 * math.sin(2 * phase)) * math.exp(-t * 17)
            sound += band * .16 * math.exp(-t * 160)
            sound = math.tanh(sound * 1.3) / 1.3
        elif kind in ("snare", "clap"):
            if kind == "snare":
                body = (.31 * math.sin(TAU * (188 + variation * 3) * t)
                        + .11 * math.sin(TAU * 327 * t)) * math.exp(-t * 35)
                sound = body + band * (.65 * math.exp(-t * 24) + .16 * math.exp(-t * 65))
            else:
                burst = sum(math.exp(-(t - onset) * 220) if t >= onset else 0
                            for onset in (0, .010, .023))
                sound = band * (.46 * burst + .37 * math.exp(-t * 27))
        elif kind in ("hat", "open", "crash"):
            high = (noise - metal) * .49
            high += .04 * sum(math.sin(TAU * frequency * t) for frequency in (4217, 5933, 7907))
            sound = high * math.exp(-t * {"hat": 61, "open": 15, "crash": 6}[kind])
            if kind == "crash":
                sound += band * .12 * math.exp(-t * 8)
        else:
            phase += TAU * (123 + variation * 22 + 43 * math.exp(-t * 40)) / SR
            sound = (.62 * math.sin(phase) + .16 * math.sin(phase * 1.51)) * math.exp(-t * 19)
            sound += band * .08 * math.exp(-t * 80)
        out[index] = sound * min(1, t / .0016) * _end_window(index, count, .010)
    return out


def render(score=SCORE):
    validate_score(score)
    instrument.cache_clear()
    events = arrange(score)
    mix = LoopMix(score.frames)
    for event in events:
        signal = (instrument(event.voice, event.pitch, event.gate_ms)
                  if event.voice in TONAL_VOICES else drum(event.voice, event.variation))
        mix.add(signal, event.seconds, event.gain, event.pan, event.send)
    left, right = mix.finish(decay=.88, wet=.29, saturation=.92, rms_db=-23.0)
    instrument.cache_clear()
    assert mix.wrapped_events >= 5
    return left, right, {
        "events": mix.events, "wrappedEvents": mix.wrapped_events,
        "kickCount": INSTRUMENT_COUNTS["kick"], "instruments": dict(INSTRUMENT_COUNTS),
        "arrangementSha256": arrangement_sha256(events),
    }
