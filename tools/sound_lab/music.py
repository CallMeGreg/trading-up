"""Original Trading Up scores and offline instruments (Python standard library).

The scores are explicit note sequences; no musical samples, pretrained audio
models, or generative-audio services are used.
Notes use MIDI numbers; melody entries are (beat within bar, note, held beats).
Each sixteen-bar score has a small recurring hook, an answering phrase, and a
second eight-bar variation. D-major extensions leave space for the game's SFX.

Rendering is circular, not a song with its ends faded out: every note and echo
wrap-adds into the period. The room receives two complete periods and we retain
the second, after more than twenty reverb decay times of filter warm-up.
"""

import math
import random
from array import array
from dataclasses import dataclass
from functools import lru_cache

from .dsp import SR, TAU, hz, room


AAC_FRAME = 1024
BEATS_PER_BAR = 4
BARS = 16
LICENSE = "Original composition; no third-party musical content"


@dataclass(frozen=True)
class Chord:
    root: int
    voices: tuple


@dataclass(frozen=True)
class Score:
    id: str
    mode: str
    title: str
    description: str
    tempo: int
    recommended: bool
    color: str
    chords: tuple
    melody: tuple
    seed: int

    @property
    def frames(self):
        # A whole number of AAC access units prevents trailing partial-frame
        # padding. The tiny tempo adjustment is reported, never hidden by trim.
        return round(BARS * BEATS_PER_BAR * 60 * SR / self.tempo / AAC_FRAME) * AAC_FRAME

    @property
    def duration(self):
        return self.frames / SR

    @property
    def bpm(self):
        return BARS * BEATS_PER_BAR * 60 / self.duration

    @property
    def beat_seconds(self):
        return self.duration / (BARS * BEATS_PER_BAR)


D9 = Chord(38, (54, 57, 61, 64))
D69 = Chord(38, (54, 57, 59, 64))
DF = Chord(42, (57, 61, 62, 64))
BM9 = Chord(35, (54, 57, 61, 62))
G9 = Chord(43, (54, 57, 59, 62))
G6 = Chord(43, (55, 59, 62, 64))
EM9 = Chord(40, (55, 59, 62, 66))
FM7 = Chord(42, (52, 57, 61, 64))
A13 = Chord(45, (55, 59, 61, 66))
ASUS = Chord(45, (55, 59, 62, 64))
AC = Chord(37, (52, 57, 59, 64))


SCORES = (
    Score(
        "classic-sunlit-sleeves", "classic", "Sunlit Sleeves",
        "Recommended Classic: a conversational felt-key hook, softly strummed "
        "nylon, rounded bass and pocket-sized brushes. Warm major-nine voicings "
        "open into a gentle answering phrase, then return with a new ending.",
        86, True, "felt", (
            D9, D9, BM9, BM9, G9, G9, ASUS, A13,
            DF, DF, EM9, EM9, G9, G6, ASUS, A13,
        ), (
            ((0.5, 66, .65), (1.5, 69, .45), (2.25, 76, .6), (3.0, 74, .85)),
            ((.75, 73, .6), (1.75, 69, 1.5)),
            ((.5, 66, .7), (1.5, 69, .45), (2.25, 74, .6), (3.0, 73, .8)),
            ((.75, 71, 1.0), (2.5, 66, .85)),
            ((.25, 67, .7), (1.5, 71, .65), (2.75, 74, .85)),
            ((.5, 71, .65), (1.5, 69, .5), (2.75, 66, 1.0)),
            ((.5, 64, .65), (1.75, 66, .65), (3.0, 71, .7)),
            ((.5, 73, .7), (1.75, 69, 1.25)),
            ((.5, 66, .65), (1.5, 69, .45), (2.25, 76, .6), (3.0, 74, .85)),
            ((.75, 73, .6), (1.75, 69, 1.0), (3.25, 66, .4)),
            ((.5, 67, .65), (1.5, 71, .45), (2.25, 76, .65)),
            ((.5, 74, .75), (2.0, 71, 1.3)),
            ((.25, 69, .7), (1.5, 71, .65), (2.75, 74, .85)),
            ((.5, 71, .65), (1.5, 69, .5), (2.75, 67, .9)),
            ((.5, 66, .65), (1.75, 64, .75), (3.0, 69, .6)),
            ((.5, 71, .65), (1.75, 73, .75), (3.25, 64, .5)),
        ), 76123,
    ),
    Score(
        "classic-paper-lanterns", "classic", "Paper Lanterns",
        "Classic alternate: a finger-picked nylon melody with little felt-key "
        "replies, unhurried brushed percussion and a warm walking answer in the "
        "bass. More intimate and acoustic than Sunlit Sleeves.",
        82, False, "nylon", (
            D69, D69, FM7, FM7, G9, G9, EM9, ASUS,
            BM9, BM9, G9, G6, D9, DF, EM9, A13,
        ), (
            ((.25, 69, .75), (1.25, 71, .4), (2.0, 66, 1.15)),
            ((.75, 64, .5), (1.75, 66, .6), (3.0, 69, .65)),
            ((.25, 69, .75), (1.25, 73, .4), (2.0, 69, 1.1)),
            ((.75, 66, .75), (2.25, 64, 1.15)),
            ((.25, 71, .7), (1.25, 74, .45), (2.25, 69, 1.0)),
            ((.75, 67, .5), (1.75, 66, .5), (3.0, 62, .65)),
            ((.25, 64, .75), (1.5, 66, .45), (2.5, 71, .85)),
            ((.75, 69, .9), (2.5, 64, .85)),
            ((.25, 69, .75), (1.25, 71, .4), (2.0, 66, 1.15)),
            ((.75, 62, .5), (1.75, 66, .6), (3.0, 69, .65)),
            ((.25, 71, .75), (1.25, 74, .4), (2.0, 69, 1.1)),
            ((.75, 67, .75), (2.25, 64, 1.15)),
            ((.25, 66, .7), (1.25, 69, .45), (2.25, 76, .9)),
            ((.75, 74, .5), (1.75, 73, .6), (3.0, 69, .65)),
            ((.25, 67, .7), (1.5, 66, .45), (2.5, 64, .8)),
            ((.75, 64, .65), (2.0, 66, .55), (3.0, 64, .6)),
        ), 76147,
    ),
    Score(
        "gauntlet-quiet-resolve", "gauntlet", "Quiet Resolve",
        "Recommended Gauntlet: a rounded wooden-mallet hook over muted keys, "
        "a gently moving bass line and quiet cloth-and-rim percussion. Descending "
        "bass harmony and an open second phrase give momentum without urgency.",
        106, True, "mallet", (
            D69, D69, AC, AC, BM9, BM9, G9, ASUS,
            EM9, EM9, FM7, FM7, G6, G9, ASUS, A13,
        ), (
            ((.25, 66, .5), (1.0, 69, .4), (1.75, 71, .6), (3.0, 69, .55)),
            ((.25, 76, .7), (1.75, 74, .6), (3.0, 69, .55)),
            ((.25, 66, .5), (1.0, 69, .4), (1.75, 71, .6), (3.0, 73, .55)),
            ((.25, 76, .7), (1.75, 73, 1.0)),
            ((.25, 66, .5), (1.0, 69, .4), (1.75, 71, .6), (3.0, 74, .55)),
            ((.25, 73, .7), (1.75, 71, .6), (3.0, 66, .55)),
            ((.25, 67, .5), (1.0, 71, .4), (2.0, 74, .7)),
            ((.25, 71, .55), (1.25, 69, .55), (2.75, 64, .7)),
            ((.25, 67, .5), (1.0, 71, .4), (1.75, 74, .6), (3.0, 71, .55)),
            ((.25, 76, .7), (1.75, 74, .6), (3.0, 71, .55)),
            ((.25, 66, .5), (1.0, 69, .4), (1.75, 73, .6), (3.0, 69, .55)),
            ((.25, 76, .7), (1.75, 73, 1.0)),
            ((.25, 67, .5), (1.0, 69, .4), (1.75, 71, .6), (3.0, 74, .55)),
            ((.25, 71, .7), (1.75, 69, .6), (3.0, 66, .55)),
            ((.25, 64, .5), (1.0, 66, .4), (2.0, 71, .7)),
            ((.25, 73, .55), (1.25, 69, .55), (2.75, 64, .7)),
        ), 76213,
    ),
    Score(
        "gauntlet-northbound", "gauntlet", "Northbound",
        "Gauntlet alternate: a soft, syncopated nylon hook, broad felt-key "
        "responses and a half-time brushed pocket. A little more spacious and "
        "reflective, with a subtly busier bass in the second half.",
        102, False, "travel", (
            D9, D69, G9, G9, BM9, BM9, ASUS, A13,
            DF, DF, EM9, EM9, G9, G6, ASUS, A13,
        ), (
            ((.5, 69, .5), (1.25, 66, .45), (2.5, 74, .85)),
            ((.25, 73, .5), (1.5, 69, .6), (3.0, 66, .6)),
            ((.5, 71, .5), (1.25, 67, .45), (2.5, 74, .85)),
            ((.25, 71, .5), (1.5, 69, 1.0)),
            ((.5, 69, .5), (1.25, 66, .45), (2.5, 74, .85)),
            ((.25, 73, .5), (1.5, 71, .6), (3.0, 66, .6)),
            ((.5, 64, .5), (1.25, 66, .45), (2.5, 71, .85)),
            ((.25, 73, .5), (1.5, 69, 1.0)),
            ((.5, 69, .5), (1.25, 66, .45), (2.5, 76, .85)),
            ((.25, 74, .5), (1.5, 73, .6), (3.0, 69, .6)),
            ((.5, 71, .5), (1.25, 67, .45), (2.5, 76, .85)),
            ((.25, 74, .5), (1.5, 71, 1.0)),
            ((.5, 71, .5), (1.25, 69, .45), (2.5, 74, .85)),
            ((.25, 71, .5), (1.5, 69, .6), (3.0, 67, .6)),
            ((.5, 66, .5), (1.25, 64, .45), (2.5, 69, .85)),
            ((.25, 71, .5), (1.5, 73, .7), (3.0, 64, .6)),
        ), 76253,
    ),
)


def validate_scores():
    assert len(SCORES) == 4 and len({s.id for s in SCORES}) == 4
    for mode in ("classic", "gauntlet"):
        assert sum(s.mode == mode for s in SCORES) == 2
        assert sum(s.mode == mode and s.recommended for s in SCORES) == 1
    for score in SCORES:
        assert len(score.chords) == len(score.melody) == BARS
        assert 30 <= score.duration <= 50
        assert score.frames % AAC_FRAME == 0
        assert abs(score.bpm - score.tempo) < .04
        for chord, phrase in zip(score.chords, score.melody):
            for note in (chord.root, *chord.voices):
                assert note % 12 in (1, 2, 4, 6, 7, 9, 11)
            assert 1 <= len(phrase) <= 5
            for beat, note, held in phrase:
                assert 0 <= beat < 4 and 0 < held <= 2
                assert 60 <= note <= 78 and note % 12 in (1, 2, 4, 6, 7, 9, 11)


def _end_window(index, count, release_frames=1200):
    remaining = count - 1 - index
    if remaining < release_frames:
        return .5 - .5 * math.cos(math.pi * remaining / release_frames)
    return 1.0


@lru_cache(maxsize=112)
def voice(kind, note, held_ms, articulation=0):
    """Small physical/harmonic instruments, with independent body and release."""
    gate = held_ms / 1000
    rng = random.Random(note * 373 + articulation * 1259 + sum(map(ord, kind)))
    frequency = hz(note)
    release = {"felt": .9, "nylon": .65, "mallet": .75, "bass": .3, "pad": 1.6}[kind]
    count = round((gate + release) * SR)
    out = array("f", [0.0]) * count
    step = TAU * frequency / SR

    if kind == "nylon":
        # Fractional-delay Karplus–Strong string. The all-pass compensates the
        # half-sample loop-filter delay rather than rounding musical pitches.
        period = SR / frequency - .5
        length = math.floor(period)
        fraction = period - length
        coefficient = (1 - fraction) / (1 + fraction)
        excitation = [rng.uniform(-1, 1) for _ in range(length)]
        pick = max(1, round(length * (.19 + articulation * .025)))
        memory = [excitation[i] - excitation[(i - pick) % length] for i in range(length)]
        smooth = 0.0
        for _ in range(3):
            for i in range(length):
                smooth += .42 * (memory[i] - smooth)
                memory[i] = smooth
        maximum = max(map(abs, memory))
        memory = [x / maximum * .64 for x in memory]
        previous = memory[-1]
        previous_input = previous_output = 0.0
        decay = math.exp(-1 / (frequency * (1.5 + .16 * articulation)))
        index = 0
        for i in range(count):
            stored = memory[index]
            filtered = .5 * (stored + previous)
            previous = stored
            tuned = coefficient * filtered + previous_input - coefficient * previous_output
            previous_input, previous_output = filtered, tuned
            memory[index] = tuned * decay
            index = (index + 1) % length
            t = i / SR
            envelope = min(1, t / .006) * math.exp(-max(0, t - gate) * 9)
            out[i] = stored * envelope * _end_window(i, count)
        return out

    phase = rng.uniform(-.04, .04)
    drift_phase = rng.uniform(0, TAU)
    filtered_noise = 0.0
    for i in range(count):
        t = i / SR
        phase += step
        if kind == "felt":
            hammer = (.55 + articulation * .09) * math.exp(-t * 8)
            sound = (
                .70 * math.sin(phase + hammer * math.sin(2 * phase))
                + .15 * math.sin(phase * 1.0013 + .12)
                + .11 * math.sin(phase * 2.0005) * math.exp(-t * 2.8)
                + .045 * math.sin(phase * 3.002) * math.exp(-t * 5.5)
            )
            envelope = min(1, t / .009) * math.exp(-t / 1.8)
            envelope *= math.exp(-max(0, t - gate) * 8.5)
        elif kind == "mallet":
            sound = (
                .78 * math.sin(phase)
                + .12 * math.sin(phase * 1.999) * math.exp(-t * 5)
                + (.12 + .015 * articulation) * math.sin(phase * 4.003) * math.exp(-t * 12)
                + .02 * math.sin(phase * 9.98) * math.exp(-t * 28)
            )
            sound *= .96 + .04 * math.sin(TAU * 4.7 * t + drift_phase)
            envelope = min(1, t / .007) * math.exp(-t * 2.4)
            envelope *= math.exp(-max(0, t - gate) * 8)
        elif kind == "bass":
            sound = (
                .66 * math.sin(phase)
                + .25 * math.sin(2 * phase) * math.exp(-t * 1.7)
                + .11 * math.sin(3 * phase) * math.exp(-t * 3)
                + .025 * math.sin(4 * phase) * math.exp(-t * 8)
            )
            envelope = min(1, t / .015) * math.exp(-t * .75)
            envelope *= math.exp(-max(0, t - gate) * 22)
        else:
            sound = (
                .48 * math.sin(phase * .9987 + drift_phase)
                + .48 * math.sin(phase * 1.0011 - drift_phase)
                + .09 * math.sin(phase * 2.001)
                + .035 * math.sin(phase * 3.0007)
            )
            envelope = math.sin(min(1, t / .48) * math.pi / 2) ** 2
            if t > gate:
                envelope *= math.cos(min(1, (t - gate) / release) * math.pi / 2) ** 2
            envelope *= .93 + .07 * math.sin(TAU * .31 * t + drift_phase)
        if kind in ("felt", "bass") and t < .05:
            filtered_noise += .11 * (rng.uniform(-1, 1) - filtered_noise)
            sound += filtered_noise * .025 * math.exp(-t * 90)
        out[i] = sound * envelope * _end_window(i, count)
    return out


@lru_cache(maxsize=20)
def percussion(kind, variation):
    rng = random.Random(4409 + variation * 173 + sum(map(ord, kind)))
    duration = {"kick": .34, "brush": .22, "rim": .13, "shaker": .095}[kind]
    count = round(duration * SR)
    out = array("f", [0.0]) * count
    fast = slow = phase = 0.0
    for i in range(count):
        t = i / SR
        noise = rng.uniform(-1, 1)
        fast += .38 * (noise - fast)
        slow += .045 * (fast - slow)
        if kind == "kick":
            phase += TAU * (48 + 36 * math.exp(-t * 48)) / SR
            sound = (.65 * math.sin(phase) + .14 * math.sin(2 * phase)) * math.exp(-t * 17)
            sound += fast * .11 * math.exp(-t * 100)
            attack = .006
        elif kind == "brush":
            envelope = (1 - math.exp(-t * 150)) * math.exp(-t * 24)
            sound = (fast - slow) * envelope * (.64 + .17 * math.sin(TAU * 27 * t))
            sound += .025 * math.sin(TAU * 183 * t) * math.exp(-t * 40)
            attack = .008
        elif kind == "rim":
            sound = (
                .18 * math.sin(TAU * 823 * t)
                + .12 * math.sin(TAU * 1371 * t)
                + .045 * math.sin(TAU * 2162 * t)
            ) * math.exp(-t * 72) + (fast - slow) * .09 * math.exp(-t * 100)
            attack = .003
        else:
            envelope = math.sin(math.pi * t / duration) ** 1.8
            sound = (noise - fast) * envelope * .27
            attack = .003
        out[i] = sound * min(1, t / attack) * _end_window(i, count, 400)
    return out


class LoopMix:
    def __init__(self, frames):
        self.frames = frames
        self.left = array("f", [0.0]) * frames
        self.right = array("f", [0.0]) * frames
        self.send = array("f", [0.0]) * frames
        self.wrapped_events = 0
        self.events = 0

    def add(self, signal, seconds, gain, pan=0, send=.25):
        assert -1 <= pan <= 1 and len(signal) <= self.frames
        offset = round(seconds * SR) % self.frames
        left = math.cos((pan + 1) * math.pi / 4) * gain
        right = math.sin((pan + 1) * math.pi / 4) * gain
        wet = gain * send
        self.events += 1
        if offset + len(signal) > self.frames:
            self.wrapped_events += 1
        first = min(len(signal), self.frames - offset)
        for begin, end, destination in ((0, first, offset), (first, len(signal), 0)):
            for i in range(begin, end):
                x = signal[i]
                j = destination + i - begin
                self.left[j] += x * left
                self.right[j] += x * right
                self.send[j] += x * wet

    def finish(self):
        # No zero-state filter restart at the loop. More than one full musical
        # period of pre-roll makes the omitted older room state < -150 dBFS.
        two_periods = array("d", self.send) * 2
        wet_left, wet_right = room(two_periods, two_periods, decay=1.25, wet=.38)
        for i in range(self.frames):
            self.left[i] += wet_left[self.frames + i] - self.send[i]
            self.right[i] += wet_right[self.frames + i] - self.send[i]
        del two_periods, wet_left, wet_right, self.send
        for channel in (self.left, self.right):
            dc = sum(channel) / self.frames
            for i, sample in enumerate(channel):
                channel[i] = math.tanh((sample - dc) * .85) / .85
        peak = max(max(map(abs, self.left)), max(map(abs, self.right)))
        rms = math.sqrt(sum(x * x for channel in (self.left, self.right) for x in channel) / (2 * self.frames))
        gain = min(10 ** (-23 / 20) / rms, 10 ** (-8.5 / 20) / peak)
        for channel in (self.left, self.right):
            # Saturation is memoryless and this second DC removal is periodic.
            dc = sum(channel) / self.frames
            for i, sample in enumerate(channel):
                channel[i] = (sample - dc) * gain
        return self.left, self.right


def render(score):
    """Render one original score, including all carried instrument/room tails."""
    validate_scores()
    voice.cache_clear()
    mix = LoopMix(score.frames)
    rng = random.Random(score.seed)
    beat_seconds = score.beat_seconds
    active = score.mode == "gauntlet"

    def note(kind, pitch, at, held, gain, pan=0, send=.3, echo=False, articulation=0):
        signal = voice(kind, pitch, round(held * beat_seconds * 1000), articulation)
        position = at * beat_seconds
        mix.add(signal, position, gain, pan, send)
        if echo:
            mix.add(signal, position + .75 * beat_seconds, gain * .105, -.32, .18)
            mix.add(signal, position + 1.5 * beat_seconds, gain * .045, .35, .12)

    for bar, (chord, melody) in enumerate(zip(score.chords, score.melody)):
        start = bar * 4
        phrase_gain = (.93, 1.0, .97, .91)[bar // 4]
        # The harmonic bed is not the hook: sparse strums leave conversational
        # rests for the melody and for card/pack/grading sounds.
        if score.color == "felt":
            comp_kind, lead = "nylon", "felt"
            comp = ((.02, 1.65, .088), (2.4, .9, .071))
        elif score.color == "nylon":
            comp_kind, lead = "felt", "nylon"
            comp = ((.04, 1.5, .053), (2.55, .8, .044))
        elif score.color == "mallet":
            comp_kind, lead = "felt", "mallet"
            comp = ((.03, 1.0, .062), (1.75, .6, .038), (3.35, .4, .030))
        else:
            comp_kind, lead = "felt", "nylon"
            comp = ((.05, 1.6, .055), (2.15, .9, .045))
        for beat, held, gain in comp:
            for index, pitch in enumerate(chord.voices):
                pan = -.24 + index * .12
                note(comp_kind, pitch, start + beat + index * .018, held,
                     gain * phrase_gain * rng.uniform(.91, 1.04), pan, .38,
                     articulation=(bar + index) % 3)
        if bar % 2 == 0:
            for index, pitch in enumerate(chord.voices[:3]):
                note("pad", pitch, start - .16, 7.4, .022, -.42 + index * .42, .48)

        bass = [(0, chord.root, 1.6, .155), (2.45 if not active else 2.25, chord.root + 7, .8, .104)]
        if active and bar % 2 == 1:
            bass.append((3.5, score.chords[(bar + 1) % BARS].root, .36, .068))
        elif not active and bar in (3, 7, 11, 15):
            bass.append((3.55, score.chords[(bar + 1) % BARS].root, .35, .065))
        for beat, pitch, held, gain in bass:
            note("bass", pitch, start + beat + .009, held, gain * phrase_gain, send=.035)

        lead_gain = {"felt": .156, "nylon": .40, "mallet": .150, "travel": .385}[score.color]
        for index, (beat, pitch, held) in enumerate(melody):
            gain = lead_gain * phrase_gain * (1.0 if index == 0 else .86) * rng.uniform(.94, 1.04)
            note(lead, pitch, start + beat + rng.uniform(-.009, .009), held, gain,
                 .055 if bar < 8 else -.055, .43, True, (index + bar // 4) % 3)
        if bar in (3, 7, 11, 15):
            answer_kind = "felt" if lead == "nylon" else "nylon"
            answer_gain = .044 if answer_kind == "felt" else .11
            for at, pitch in ((2.85, chord.voices[1] + 12), (3.55, chord.voices[0] + 12)):
                note(answer_kind, pitch, start + at, .4, answer_gain, -.28, .5)

        kicks = (0, 2.5) if not active else (0, 1.75, 2.75)
        if score.color == "travel":
            kicks = (0, 2.75)
        for index, beat in enumerate(kicks):
            gain = (.072 if index == 0 else .043) * (1.05 if active else .85)
            mix.add(percussion("kick", bar % 4), (start + beat) * beat_seconds, gain, send=.035)
        backbeats = (1, 3) if score.color != "travel" else (2,)
        for index, beat in enumerate(backbeats):
            offset = (start + beat + .025) * beat_seconds
            mix.add(percussion("brush", (bar + index) % 4), offset, .105 if active else .088, .13, .16)
            if active or bar % 2 == 1:
                mix.add(percussion("rim", bar % 4), offset + .005, .055 if active else .032, -.16, .19)
        shaker_beats = (.5, 1.5, 2.5, 3.5)
        if active and bar % 4 in (1, 2):
            shaker_beats += (2.0, 3.0)
        for index, beat in enumerate(shaker_beats):
            # A small, late offbeat breath, not a constant bright hi-hat grid.
            swing = .035 if not active else .008
            mix.add(percussion("shaker", (bar + index) % 4),
                    (start + beat + swing + rng.uniform(-.006, .006)) * beat_seconds,
                    (.020 if active else .016) * rng.uniform(.72, 1.08), (-1) ** index * .28, .08)
    left, right = mix.finish()
    voice.cache_clear()
    assert mix.wrapped_events >= 5
    return left, right, {"events": mix.events, "wrappedEvents": mix.wrapped_events}
