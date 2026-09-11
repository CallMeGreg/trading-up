"""Original Trading Up scores and offline instruments (Python standard library).

The scores are explicit note sequences; no musical samples, pretrained audio
models, or generative-audio services are used.
Notes use MIDI numbers; melody entries are (beat within bar, note, held beats).
Each sixteen-bar score has a challenger hook, a quieter answer, and a second
eight-bar variation. D major and its relative B minor share the SFX palette;
brief dominant chords add tension without turning the loop into a boss fanfare.

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
    def bars(self):
        return BARS

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
BM9 = Chord(35, (54, 57, 61, 62))
G6 = Chord(43, (55, 59, 62, 64))
A13 = Chord(45, (55, 59, 61, 66))
ASUS = Chord(45, (55, 59, 62, 64))
BM7 = Chord(35, (54, 57, 59, 62))
EM7 = Chord(40, (55, 59, 62, 64))
FS7 = Chord(42, (58, 61, 64, 66))
B7 = Chord(35, (51, 57, 59, 66))


SCORES = (
    Score(
        "classic-sunlit-sleeves", "classic", "Sunlit Sleeves",
        "Classic alternate / challenger mix: a playful rounded-reed hook, "
        "springy bass and soft plucked arpeggios. A friendly turn-based duel "
        "rather than a boss fight, with quieter answers and no piercing lead.",
        108, False, "rival", (
            D69, BM7, G6, ASUS, EM7, G6, D9, FS7,
            BM7, G6, D69, A13, EM7, G6, ASUS, A13,
        ), (
            ((0, 66, .32), (.5, 69, .32), (1.25, 71, .42), (2, 76, .4), (2.75, 74, .48), (3.5, 69, .25)),
            ((.25, 71, .5), (1, 74, .38), (1.75, 73, .35), (2.5, 69, .65)),
            ((0, 67, .32), (.5, 71, .32), (1.25, 74, .5), (2.25, 71, .35), (3, 69, .5)),
            ((.25, 66, .55), (1.25, 64, .7), (3, 69, .4)),
            ((.5, 67, .65), (1.75, 71, .65), (3, 66, .45)),
            ((.5, 67, .55), (1.75, 64, 1.1)),
            ((.25, 66, .45), (1.25, 69, .5), (2.5, 64, .65)),
            ((.5, 66, .55), (2, 64, .6), (3.25, 70, .3)),
            ((0, 71, .32), (.5, 74, .32), (1.25, 73, .42), (2, 76, .4), (2.75, 74, .48), (3.5, 66, .25)),
            ((.25, 67, .5), (1, 71, .38), (1.75, 74, .35), (2.5, 71, .65)),
            ((0, 66, .32), (.5, 69, .32), (1.25, 76, .5), (2.25, 74, .35), (3, 73, .5)),
            ((.25, 71, .55), (1.25, 69, .7), (3, 64, .4)),
            ((.5, 67, .65), (1.75, 71, .65), (3, 74, .45)),
            ((.5, 71, .55), (1.75, 67, 1.1)),
            ((.25, 69, .45), (1.25, 66, .5), (2.5, 64, .65)),
            ((.5, 71, .55), (2, 69, .6), (3.25, 64, .3)),
        ), 76123,
    ),
    Score(
        "classic-paper-lanterns", "classic", "Paper Lanterns",
        "Selected Classic / tactical mix: a warm wooden-mallet question and "
        "answer, nimble bass and little nylon figures. Minor-key curiosity "
        "with a lighter, more spacious rhythm for long collecting sessions.",
        104, True, "tactical", (
            BM7, G6, D69, ASUS, EM7, BM7, G6, FS7,
            BM9, G6, D9, A13, EM7, G6, ASUS, FS7,
        ), (
            ((.25, 66, .32), (.75, 71, .4), (1.5, 74, .45), (2.5, 73, .35), (3.25, 69, .35)),
            ((.5, 71, .55), (1.5, 67, .4), (2.75, 64, .65)),
            ((.25, 66, .32), (.75, 69, .4), (1.5, 74, .45), (2.5, 76, .35), (3.25, 73, .35)),
            ((.5, 71, .55), (1.5, 69, .4), (2.75, 64, .65)),
            ((.75, 67, .6), (2.25, 71, .85)),
            ((.5, 66, .55), (1.75, 62, 1.0)),
            ((.5, 64, .5), (1.5, 67, .5), (2.75, 71, .55)),
            ((.5, 70, .55), (2, 66, .6), (3.25, 70, .3)),
            ((.25, 66, .32), (.75, 71, .4), (1.5, 74, .45), (2.5, 76, .35), (3.25, 73, .35)),
            ((.5, 74, .55), (1.5, 71, .4), (2.75, 67, .65)),
            ((.25, 69, .32), (.75, 66, .4), (1.5, 74, .45), (2.5, 73, .35), (3.25, 69, .35)),
            ((.5, 71, .55), (1.5, 73, .4), (2.75, 69, .65)),
            ((.75, 67, .6), (2.25, 64, .85)),
            ((.5, 67, .55), (1.75, 71, 1.0)),
            ((.5, 69, .5), (1.5, 66, .5), (2.75, 64, .55)),
            ((.5, 66, .55), (2, 64, .6), (3.25, 70, .3)),
        ), 76147,
    ),
    Score(
        "gauntlet-quiet-resolve", "gauntlet", "Quiet Resolve",
        "Gauntlet alternate / battle mix: a soft-brass challenger motif, "
        "a pulsing B-minor bass line and quick plucked replies. Brief tom fills "
        "and dominant-chord turns add resolve; quieter phrases keep it repeat-friendly.",
        120, False, "battle", (
            BM7, BM9, G6, FS7, EM7, B7, EM7, FS7,
            BM7, G6, D69, A13, EM7, G6, BM7, FS7,
        ), (
            ((0, 71, .3), (.5, 66, .3), (1, 74, .4), (1.75, 73, .35), (2.5, 69, .4), (3.25, 66, .3)),
            ((.25, 71, .45), (1, 74, .32), (1.5, 76, .32), (2.25, 78, .5), (3.25, 73, .3)),
            ((0, 74, .3), (.5, 71, .3), (1, 69, .4), (1.75, 67, .35), (2.5, 66, .4), (3.25, 67, .3)),
            ((.25, 73, .4), (1, 70, .4), (2, 66, .6), (3.25, 70, .3)),
            ((.5, 67, .5), (1.5, 71, .45), (2.75, 76, .6)),
            ((.5, 75, .65), (2.25, 71, .85)),
            ((.5, 74, .5), (1.5, 71, .45), (2.75, 67, .6)),
            ((.5, 66, .6), (2, 64, .55), (3.25, 70, .3)),
            ((0, 71, .3), (.5, 66, .3), (1, 74, .4), (1.75, 76, .35), (2.5, 73, .4), (3.25, 69, .3)),
            ((.25, 71, .45), (1, 74, .32), (1.5, 71, .32), (2.25, 67, .5), (3.25, 69, .3)),
            ((0, 74, .3), (.5, 69, .3), (1, 66, .4), (1.75, 69, .35), (2.5, 76, .4), (3.25, 74, .3)),
            ((.25, 73, .4), (1, 71, .4), (2, 69, .6), (3.25, 64, .3)),
            ((.5, 67, .5), (1.5, 71, .45), (2.75, 74, .6)),
            ((.5, 71, .65), (2.25, 67, .85)),
            ((.5, 66, .5), (1.5, 62, .45), (2.75, 66, .6)),
            ((.5, 70, .6), (2, 73, .55), (3.25, 66, .3)),
        ), 76213,
    ),
    Score(
        "gauntlet-northbound", "gauntlet", "Northbound",
        "Gauntlet alternate / scout mix: a nimble nylon hook over a walking "
        "minor-key pulse, warm reed answers and a half-time drum pocket. "
        "Forward-looking challenge energy with more space than the battle mix.",
        116, False, "travel", (
            BM7, D69, G6, ASUS, EM7, G6, BM7, FS7,
            BM9, G6, D9, A13, EM7, G6, ASUS, FS7,
        ), (
            ((0, 66, .3), (.75, 71, .35), (1.5, 69, .4), (2.25, 74, .4), (3, 73, .4)),
            ((.25, 69, .45), (1, 66, .3), (1.75, 74, .4), (2.75, 76, .55)),
            ((0, 67, .3), (.75, 71, .35), (1.5, 69, .4), (2.25, 74, .4), (3, 71, .4)),
            ((.25, 69, .55), (1.75, 66, .55), (3, 64, .4)),
            ((.5, 67, .6), (2, 71, .7)),
            ((.5, 71, .5), (1.75, 67, .55), (3, 64, .4)),
            ((.75, 66, .55), (2.25, 62, .8)),
            ((.5, 64, .6), (2, 66, .6), (3.25, 70, .3)),
            ((0, 66, .3), (.75, 71, .35), (1.5, 74, .4), (2.25, 76, .4), (3, 73, .4)),
            ((.25, 74, .45), (1, 71, .3), (1.75, 67, .4), (2.75, 69, .55)),
            ((0, 69, .3), (.75, 66, .35), (1.5, 74, .4), (2.25, 73, .4), (3, 69, .4)),
            ((.25, 71, .55), (1.75, 73, .55), (3, 69, .4)),
            ((.5, 67, .6), (2, 74, .7)),
            ((.5, 71, .5), (1.75, 69, .55), (3, 67, .4)),
            ((.75, 66, .55), (2.25, 64, .8)),
            ((.5, 66, .6), (2, 64, .6), (3.25, 70, .3)),
        ), 76253,
    ),
)


def validate_scores():
    assert len(SCORES) == 4 and len({s.id for s in SCORES}) == 4
    for mode in ("classic", "gauntlet"):
        assert sum(s.mode == mode for s in SCORES) == 2
        assert sum(s.mode == mode and s.recommended for s in SCORES) == (1 if mode == "classic" else 0)
    for score in SCORES:
        assert len(score.chords) == len(score.melody) == BARS
        assert 30 <= score.duration <= 50
        assert score.frames % AAC_FRAME == 0
        assert abs(score.bpm - score.tempo) < .04
        assert score.color in ("rival", "tactical", "battle", "travel")
        # Dominant thirds are brief tension colors, not a new tonal center.
        palette = (1, 2, 3, 4, 6, 7, 9, 10, 11)
        for chord, phrase in zip(score.chords, score.melody):
            for note in (chord.root, *chord.voices):
                assert note % 12 in palette
            assert 1 <= len(phrase) <= 7
            assert list(phrase) == sorted(phrase)
            for beat, note, held in phrase:
                assert 0 <= beat < 4 and 0 < held <= 2
                assert 60 <= note <= 78 and note % 12 in palette
        for bar in (5, 7, 13, 15):
            assert len(score.melody[bar]) <= 3
            assert sum(held for _, _, held in score.melody[bar]) < 2.2


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
    release = {"felt": .9, "nylon": .65, "mallet": .75, "bass": .3, "pad": 1.6,
               "reed": .38, "brass": .42, "pulse": .3}[kind]
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
        vibrato = .0012 * math.sin(TAU * 4.8 * t + drift_phase) * min(1, t / .3) if kind in ("reed", "brass") else 0
        phase += step * (1 + vibrato)
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
        elif kind in ("reed", "brass"):
            bloom = 1 - math.exp(-t * 42)
            body = .25 if kind == "reed" else .42
            sound = (
                .66 * math.sin(phase + body * bloom * math.sin(phase * 2))
                + .12 * math.sin(phase * 1.0009 + .16)
                + .10 * math.sin(phase * 2.001) * bloom
                + .045 * math.sin(phase * 3.002) * math.exp(-t * 2.5)
            )
            envelope = min(1, t / .016) * (.8 + .2 * math.exp(-t * 5))
            envelope *= math.exp(-max(0, t - gate) * 15)
        elif kind == "pulse":
            # A short, band-limited pulse/pluck: no square-wave edge or buzzer sustain.
            sound = (
                .67 * math.sin(phase)
                + .17 * math.sin(phase * 2.001) * math.exp(-t * 7)
                + .11 * math.sin(phase * 3.002) * math.exp(-t * 11)
                + .025 * math.sin(phase * 5.001) * math.exp(-t * 18)
            )
            envelope = min(1, t / .009) * math.exp(-t * 3)
            envelope *= math.exp(-max(0, t - gate) * 20)
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


@lru_cache(maxsize=28)
def percussion(kind, variation):
    rng = random.Random(4409 + variation * 173 + sum(map(ord, kind)))
    duration = {"kick": .34, "brush": .22, "rim": .13, "shaker": .095,
                "tom": .27, "low_tom": .32}[kind]
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
        elif kind in ("tom", "low_tom"):
            frequency = 142 if kind == "tom" else 106
            phase += TAU * frequency * (1 + .12 * math.exp(-t * 30)) / SR
            sound = (.55 * math.sin(phase) + .17 * math.sin(phase * 1.58)) * math.exp(-t * 20)
            sound += (fast - slow) * .10 * math.exp(-t * 55)
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

    def finish(self, decay=1.25, wet=.38, saturation=.85, rms_db=-24):
        # No zero-state filter restart at the loop. More than one full musical
        # period of pre-roll makes the omitted older room state < -150 dBFS.
        two_periods = array("d", self.send) * 2
        wet_left, wet_right = room(two_periods, two_periods, decay=decay, wet=wet)
        for i in range(self.frames):
            self.left[i] += wet_left[self.frames + i] - self.send[i]
            self.right[i] += wet_right[self.frames + i] - self.send[i]
        del two_periods, wet_left, wet_right, self.send
        for channel in (self.left, self.right):
            dc = sum(channel) / self.frames
            for i, sample in enumerate(channel):
                channel[i] = math.tanh((sample - dc) * saturation) / saturation
        peak = max(max(map(abs, self.left)), max(map(abs, self.right)))
        rms = math.sqrt(sum(x * x for channel in (self.left, self.right) for x in channel) / (2 * self.frames))
        gain = min(10 ** (rms_db / 20) / rms, 10 ** (-8.5 / 20) / peak)
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
    lead, lead_gain, comp_kind, comp_gain, arp_kind, arp_gain = {
        "rival": ("reed", .143, "nylon", .092, "pulse", .037),
        "tactical": ("mallet", .137, "felt", .050, "nylon", .090),
        "battle": ("brass", .139, "felt", .052, "pulse", .039),
        "travel": ("nylon", .390, "felt", .046, "pulse", .029),
    }[score.color]

    def note(kind, pitch, at, held, gain, pan=0, send=.3, echo=False, articulation=0):
        signal = voice(kind, pitch, round(held * beat_seconds * 1000), articulation)
        position = at * beat_seconds
        mix.add(signal, position, gain, pan, send)
        if echo:
            mix.add(signal, position + .75 * beat_seconds, gain * .105, -.32, .18)
            mix.add(signal, position + 1.5 * beat_seconds, gain * .045, .35, .12)

    for bar, (chord, melody) in enumerate(zip(score.chords, score.melody)):
        start = bar * 4
        breathing = bar % 8 >= 4
        phrase_gain = (1.0, .77, .96, .81)[bar // 4]
        comp = ((.03, 1.3, 1.0), (2.25, .85, .68)) if breathing else ((.03, .65, 1.0), (1.75, .45, .62), (3, .45, .70))
        for beat, held, accent in comp:
            for index, pitch in enumerate(chord.voices):
                pan = -.24 + index * .12
                note(comp_kind, pitch, start + beat + index * .012, held,
                     comp_gain * accent * phrase_gain * rng.uniform(.93, 1.04), pan, .28,
                     articulation=(bar + index) % 3)
        if bar % 2 == 0:
            # Carry only shared tones across a chord change, not a suspended
            # minor third rubbing against the next dominant's major third.
            shared = [pitch for pitch in chord.voices if pitch in score.chords[bar + 1].voices]
            for index, pitch in enumerate(shared):
                pan = 0 if len(shared) == 1 else -.35 + .7 * index / (len(shared) - 1)
                note("pad", pitch, start - .16, 7.4, .014, pan, .38)

        arp_beats = (.5, 2.5) if breathing else (.5, 1, 1.5, 2.5, 3.5)
        if score.color in ("tactical", "travel") and not breathing:
            arp_beats = (.5, 1.5, 2.5, 3.5)
        for index, beat in enumerate(arp_beats):
            pitch = chord.voices[(index + bar % 2) % len(chord.voices)]
            note(arp_kind, pitch + (12 if index % 3 == 1 else 0),
                 start + beat, .23 if not breathing else .38,
                 arp_gain * phrase_gain * (1 if index % 2 == 0 else .72),
                 -.3 if index % 2 == 0 else .3, .22, articulation=bar % 3)

        if breathing:
            bass = [(0, chord.root, .8, .144), (1.5, chord.root + 7, .35, .090),
                    (2.5, chord.root + 12, .4, .077)]
        else:
            bass = [(0, chord.root, .4, .144), (.75, chord.root + 12, .27, .081),
                    (1.5, chord.root + 7, .32, .105), (2, chord.root, .38, .126),
                    (2.75, chord.root + 12, .27, .078)]
        if bar % 2 == 1:
            bass.append((3.5, score.chords[(bar + 1) % BARS].root, .3, .071))
        for beat, pitch, held, gain in bass:
            note("bass", pitch, start + beat + .006, held, gain * phrase_gain, send=.025)

        for index, (beat, pitch, held) in enumerate(melody):
            gain = lead_gain * phrase_gain * (1.0 if index == 0 else .87) * rng.uniform(.95, 1.04)
            note(lead, pitch, start + beat + rng.uniform(-.005, .005), held, gain,
                 .055 if bar < 8 else -.055, .31, breathing, (index + bar // 4) % 3)
        if bar in (5, 13):
            answer_kind = "reed" if lead == "nylon" else "felt"
            for at, pitch in ((3, chord.voices[1] + 12), (3.5, chord.voices[0] + 12)):
                note(answer_kind, pitch, start + at, .25, .039, -.24, .3)

        kicks = (0, 2.5) if breathing or not active else (0, 1.5, 2.75)
        for index, beat in enumerate(kicks):
            gain = (.089 if index == 0 else .053) * phrase_gain * (1 if active else .84)
            mix.add(percussion("kick", bar % 4), (start + beat) * beat_seconds, gain, send=.035)
        backbeats = (2,) if score.color in ("tactical", "travel") or breathing else (1, 3)
        for index, beat in enumerate(backbeats):
            offset = (start + beat + .012) * beat_seconds
            mix.add(percussion("brush", (bar + index) % 4), offset, .108 * phrase_gain, .13, .12)
            mix.add(percussion("rim", bar % 4), offset + .005,
                    (.048 if active else .030) * phrase_gain, -.16, .12)
        if bar in (3, 11):
            for beat, kind, gain in ((3.25, "tom", .044), (3.5, "tom", .032), (3.75, "low_tom", .052)):
                mix.add(percussion(kind, bar % 4), (start + beat) * beat_seconds,
                        gain * (1 if active else .65), -.12 if kind == "tom" else .12, .1)
        shaker_beats = (1.5, 3.5) if breathing else (.5, 1.5, 2.5, 3.5)
        for index, beat in enumerate(shaker_beats):
            # Soft offbeat breaths, never a bright sixteenth-note hi-hat wall.
            mix.add(percussion("shaker", (bar + index) % 4),
                    (start + beat + .012 + rng.uniform(-.004, .004)) * beat_seconds,
                    (.018 if active else .014) * phrase_gain * rng.uniform(.75, 1.06),
                    (-1) ** index * .28, .06)
    left, right = mix.finish()
    voice.cache_clear()
    assert mix.wrapped_events >= 5
    return left, right, {"events": mix.events, "wrappedEvents": mix.wrapped_events}
