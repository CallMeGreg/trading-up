"""Three original Classic bass/percussion loops, with Soft Circuit selected.

There are no lead, chord, arpeggio or melodic echo voices. Slow four-bar root
changes and restrained drum variations give each 32-bar groove room to repeat.
All instruments are offline standard-library synthesis, not sampled content.
"""

import math
import random
from array import array
from collections import Counter
from dataclasses import dataclass
from functools import lru_cache

from .dsp import SR, TAU, hz, lowpass
from .music import AAC_FRAME, LoopMix, percussion
from .neon_dead_drop import Event, arrangement_sha256, drum


@dataclass(frozen=True)
class Score:
    id: str
    title: str
    description: str
    tempo: int
    groove: str
    roots: tuple
    seed: int
    mode: str = "classic"
    recommended: bool = False
    bars: int = 32

    @property
    def frames(self):
        return round(self.bars * 240 * SR / self.tempo / AAC_FRAME) * AAC_FRAME

    @property
    def duration(self):
        return self.frames / SR

    @property
    def bpm(self):
        return self.bars * 240 / self.duration

    @property
    def beat(self):
        return self.duration / (self.bars * 4)


SCORES = (
    Score(
        "classic-pocket-change", "Pocket Change",
        "Classic candidate / 108 BPM shuffled pocket: muted warm bass, soft kicks, "
        "rim taps and brushed shakers. A loose, gently syncopated groove with slow "
        "root changes and no lead melody; the most laid-back of the three.",
        108, "shuffle", (35, 35, 31, 33, 35, 35, 40, 33), 108731,
    ),
    Score(
        "classic-soft-circuit", "Soft Circuit",
        "Selected Classic / 116 BPM soft four-on-the-floor: rounded electronic "
        "bass, cushioned kick and subdued offbeat hats. An even, unhurried pulse "
        "related to Gauntlet's rhythm bed, with no lead, chord stabs or build-ups.",
        116, "straight", (38, 38, 33, 35, 38, 38, 31, 33), 116947, recommended=True,
    ),
    Score(
        "classic-velvet-current", "Velvet Current",
        "Classic candidate / 124 BPM half-time drift: deep smooth bass, a spacious "
        "broken kick pattern, soft brushed backbeats and low hand-drum-like taps. "
        "A relaxed 62 BPM feel with no lead melody or attention-grabbing fills.",
        124, "halftime", (40, 40, 35, 35, 38, 38, 33, 35), 124853,
    ),
)
SCORE_IDS = frozenset(score.id for score in SCORES)
DRUM_VOICES = frozenset(("kick", "rim", "brush", "shaker", "hat", "open", "snare", "tom", "low_tom"))
INSTRUMENT_COUNTS = {
    "shuffle": {"bass": 144, "brush": 68, "kick": 80, "low_tom": 4, "rim": 68, "shaker": 260},
    "straight": {"bass": 128, "hat": 260, "kick": 128, "open": 64, "rim": 68, "snare": 68},
    "halftime": {"bass": 128, "brush": 36, "kick": 80, "low_tom": 36, "rim": 36, "shaker": 132, "tom": 32},
}
BASS_PATTERNS = {
    "shuffle": (
        ((.08, 0, .60, 1), (.82, 0, .36, .65), (1.66, 7, .28, .53),
         (2.08, 0, .65, .88), (2.86, 12, .24, .40)),
        ((.08, 0, .72, 1), (1.16, 0, .40, .62), (2.08, 0, .58, .88),
         (3.58, 7, .35, .49)),
    ),
    "straight": (
        ((.56, 0, .48, 1), (1.56, 0, .40, .80), (2.56, 0, .48, .93),
         (3.56, 12, .38, .48)),
        ((.56, 0, .48, 1), (1.56, 7, .36, .55), (2.56, 0, .48, .93),
         (3.56, 0, .44, .76)),
    ),
    "halftime": (
        ((.04, 0, 1.10, 1), (1.78, 0, .44, .59), (2.70, 7, .52, .47),
         (3.38, 0, .62, .70)),
        ((.04, 0, 1.18, 1), (1.54, 0, .48, .55), (2.76, 12, .36, .34),
         (3.38, 0, .62, .70)),
    ),
}


def arrange(score):
    events = []
    rng = random.Random(score.seed)

    def hit(kind, position, gain, pan=0, variation=0):
        send = .022 if kind == "kick" else .11 if kind in ("brush", "rim", "snare") else .065
        events.append(Event(kind, 0, 0, variation % 4, position * score.beat, gain, pan, send))

    for bar in range(score.bars):
        start = bar * 4
        root = score.roots[bar // 4]
        lift = (1, .96, .91, .97)[bar // 8]
        for at, interval, gate, accent in BASS_PATTERNS[score.groove][bar % 2]:
            events.append(Event(
                "bass", root + interval, round(gate * score.beat * 1000), 0,
                (start + at) * score.beat, .29 * accent * lift, 0, .015,
            ))

        if score.groove == "shuffle":
            kicks = ((0, 1), (1.68, .53), (2.08, .80)) if bar % 2 == 0 else ((0, 1), (2.16, .83))
            for at, accent in kicks:
                hit("kick", start + at, .29 * accent * lift, variation=bar)
            for at in (1.06, 3.06):
                hit("rim", start + at, .135 * lift, -.18, bar)
                hit("brush", start + at + .02, .13 * lift, .17, bar + 1)
            for index in range(8):
                at = index * .5 + (.075 if index % 2 else .006)
                hit("shaker", start + at, .088 * lift * (.58 if index % 2 == 0 else 1)
                    * rng.uniform(.91, 1.04), -.28 if index % 2 else .25, index + bar)
            if bar % 8 == 7:
                for kind, at, gain, pan in (("low_tom", 3.5, .042, -.18), ("brush", 3.625, .040, .14),
                                            ("rim", 3.8125, .031, -.18), ("shaker", 3.875, .037, .25)):
                    hit(kind, start + at, gain * lift, pan, bar)
        elif score.groove == "straight":
            for index in range(4):
                hit("kick", start + index, (.265 if index == 0 else .225) * lift, variation=bar)
            for at in (1, 3):
                hit("snare", start + at + .008, .118 * lift, .10, bar)
                hit("rim", start + at + .018, .052 * lift, -.16, bar + 1)
            for index in range(8):
                hit("hat", start + index * .5, .074 * lift * (.59 if index % 2 == 0 else 1)
                    * rng.uniform(.94, 1.03), -.23 if index % 2 else .22, index + bar)
            for at in (1.5, 3.5):
                hit("open", start + at, .063 * lift, .24, bar)
            if bar % 8 == 7:
                hit("snare", start + 3.75, .030 * lift, -.13, bar + 1)
                hit("hat", start + 3.875, .037 * lift, .22, bar)
                hit("rim", start + 3.875, .028 * lift, -.16, bar)
        else:
            kicks = ((0, 1), (1.75, .56), (3.25, .70)) if bar % 2 == 0 else ((0, 1), (2.75, .61))
            for at, accent in kicks:
                hit("kick", start + at, .30 * accent * lift, variation=bar)
            hit("brush", start + 2.025, .23 * lift, .14, bar)
            hit("rim", start + 2.035, .073 * lift, -.17, bar + 1)
            for index, at in enumerate((.5, 1.5, 2.5, 3.5)):
                hit("shaker", start + at + .018, .077 * lift * rng.uniform(.86, 1.03),
                    -.29 if index % 2 else .27, index + bar)
            for at, kind, gain in ((.75, "low_tom", .080), (3.125, "tom", .050)):
                hit(kind, start + at, gain * lift, -.18 if kind == "low_tom" else .18, bar)
            if bar % 8 == 7:
                for kind, at, gain, pan in (("low_tom", 3.5, .043, -.18), ("brush", 3.75, .053, .14),
                                            ("shaker", 3.875, .032, .27), ("rim", 3.875, .030, -.17)):
                    hit(kind, start + at, gain * lift, pan, bar)
    return tuple(events)


def arrangement_details(score):
    events = arrange(score)
    counts = dict(sorted(Counter(event.voice for event in events).items()))
    return {
        "events": len(events), "instruments": counts, "kickCount": counts["kick"],
        "arrangementSha256": arrangement_sha256(events),
    }


def validate_score(score):
    assert score in SCORES and score.mode == "classic"
    assert score.recommended == (score.id == "classic-soft-circuit")
    assert score.bars == 32 and len(score.roots) == 8
    assert score.groove in BASS_PATTERNS
    assert 60 <= score.duration <= 72 and score.frames % AAC_FRAME == 0
    assert abs(score.bpm - score.tempo) < .04
    assert all(30 <= root <= 40 and root % 12 in (2, 4, 7, 9, 11) for root in score.roots)
    events = arrange(score)
    assert events == arrange(score), f"{score.id}: non-deterministic arrangement"
    assert Counter(event.voice for event in events) == INSTRUMENT_COUNTS[score.groove]
    assert all(event.voice in DRUM_VOICES | {"bass"} for event in events)
    bass_notes = [event for event in events if event.voice == "bass"]
    assert all(30 <= event.pitch <= 52 and 0 < event.gate_ms < 700 for event in bass_notes)
    assert all(event.pitch == event.gate_ms == 0 for event in events if event.voice != "bass")
    for event in events:
        assert 0 <= event.seconds < score.duration
        assert 0 < event.gain <= .30 and -.3 <= event.pan <= .3 and 0 <= event.send <= .11
        assert 0 <= event.variation < 4


def validate_scores():
    assert len(SCORES) == len(SCORE_IDS) == 3
    assert sum(score.recommended for score in SCORES) == 1
    assert {score.tempo for score in SCORES} == {108, 116, 124}
    assert {score.groove for score in SCORES} == set(BASS_PATTERNS)
    assert len({arrangement_sha256(arrange(score)) for score in SCORES}) == 3
    for score in SCORES:
        validate_score(score)


def _end_window(index, count, release=.025):
    remaining = (count - 1 - index) / SR
    return .5 - .5 * math.cos(math.pi * remaining / release) if remaining < release else 1


@lru_cache(maxsize=128)
def bass(groove, midi, gate_ms):
    gate = gate_ms / 1000
    attack, release = {"shuffle": (.012, .25), "straight": (.008, .22), "halftime": (.018, .34)}[groove]
    count = round((gate + release) * SR)
    step = TAU * hz(midi) / SR
    out = array("f", [0]) * count
    for index in range(count):
        t = index / SR
        phase = step * index
        if groove == "shuffle":
            sound = (.78 * math.sin(phase) + .20 * math.sin(phase * 2) * math.exp(-t * 4)
                     + .075 * math.sin(phase * 3) * math.exp(-t * 9))
        elif groove == "straight":
            sound = (.74 * math.sin(phase + .12 * math.exp(-t * 10) * math.sin(phase * 2))
                     + .24 * math.sin(phase * 2) * math.exp(-t * 7)
                     + .10 * math.sin(phase * 3) * math.exp(-t * 10)
                     + .035 * math.sin(phase * 4) * math.exp(-t * 20))
        else:
            sound = (.88 * math.sin(phase) + .12 * math.sin(phase * 2) * math.exp(-t * 2)
                     + .040 * math.sin(phase * 3) * math.exp(-t * 6))
        envelope = math.sin(min(1, t / attack) * math.pi / 2) ** 2
        envelope *= (.84 + .16 * math.exp(-t * 5)) * math.exp(-max(0, t - gate) * 22)
        out[index] = sound * envelope * _end_window(index, count)
    return out


@lru_cache(maxsize=96)
def bed_drum(groove, kind, variation):
    electronic = groove == "straight" and kind in ("kick", "hat", "open", "snare")
    signal = drum(kind, variation) if electronic else percussion(kind, variation)
    cutoff = {"shuffle": 3800, "straight": 4600, "halftime": 3200}[groove]
    if kind in ("kick", "tom", "low_tom"):
        cutoff = 1600
    softened = lowpass(signal, cutoff)
    return array("f", (sample * _end_window(index, len(softened), .012)
                       for index, sample in enumerate(softened)))


def render(score):
    validate_score(score)
    bass.cache_clear()
    bed_drum.cache_clear()
    mix = LoopMix(score.frames)
    for event in arrange(score):
        signal = (bass(score.groove, event.pitch, event.gate_ms) if event.voice == "bass"
                  else bed_drum(score.groove, event.voice, event.variation))
        mix.add(signal, event.seconds, event.gain, event.pan, event.send)
    left, right = mix.finish(decay=.80, wet=.24, saturation=.86, rms_db=-24.5)
    bass.cache_clear()
    bed_drum.cache_clear()
    assert mix.wrapped_events >= 5, f"{score.id}: expected carried bass/percussion tails"
    return left, right, {**arrangement_details(score), "wrappedEvents": mix.wrapped_events}
