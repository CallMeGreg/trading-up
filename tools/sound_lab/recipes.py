"""Layered material gestures, rather than one oscillator preset per action."""

from .dsp import Mix, SR, air, bloom, fade, impact, lowpass, master, modal, resample, room, seeded


def mix_targets(cue):
    if cue.id == "foil":
        return -29, -9
    if cue.group == "interface":
        return -25, -8
    if cue.optional:
        return -27, -9
    if cue.recipe in ("victory", "reveal") and cue.id not in ("rare", "trainer_unlock"):
        return -19.5, -3.5
    if cue.recipe == "defeat":
        return -24, -6
    if cue.recipe in ("touch", "slide", "place"):
        return -25, -7
    return -22, -5


def render(cue, style, take, sources):
    rng = seeded(f"trading-up/sound-lab/v1/{cue.id}/{style}/{take}")
    mythic = style == "mythic"
    duration = cue.duration
    short = cue.group == "interface" or cue.id in ("card_flip", "keep_card")
    tail = (0.07 if short else 0.36) if mythic else (0.035 if short else 0.15)
    mix = Mix(duration + tail)
    notes = cue.notes

    def sample(material=None, at=0, gain=0.6, pan=0, speed=1, limit=None):
        available = sources[material or cue.material]
        source = available[rng.randrange(len(available))]
        signal = resample(source, speed * rng.uniform(0.965, 1.035))
        if limit is not None:
            signal = fade(signal[:round(limit * SR)], 0.0015, 0.02)
        signal = lowpass(signal, 10000 if mythic else 6900)
        mix.add(signal, at, gain, pan)
        return signal

    def tone(note, at, length, gain=0.15, pan=0, material="glass"):
        signal = modal(note, length, rng, material, softness=0.30 if mythic else 0.75)
        mix.add(signal, at, gain, pan)
        return signal

    def wash(at, length, gain=0.12, reverse=False):
        signal = air(length, rng, 750, 8200 if mythic else 4400,
                     "reverse" if reverse else "swell")
        mix.add(signal, at, gain, -0.16 if reverse else 0.20)

    def chord(at, length, gain=0.45, pitches=None):
        voice = bloom(pitches or notes[:4], length, rng)
        mix.add(voice, at, gain, 0)
        if mythic:
            voice = bloom(tuple(n + 12 for n in (pitches or notes[-3:])), length * 0.85, rng)
            mix.add(voice, at + 0.02, gain * 0.25, 0.38)

    if cue.recipe == "touch":
        sample(gain=0.65, speed=1.18, limit=0.09)
        tone(notes[0] - 12, 0.004, 0.075, 0.1, material="wood")
        if len(notes) > 1:
            sample(at=0.065, gain=0.28, speed=1.32, limit=0.065)
            tone(notes[-1], 0.067, 0.10, 0.025)
        if mythic:
            wash(0.0, 0.11, 0.06)

    elif cue.recipe == "blocked":
        for i, note in enumerate(notes):
            sample(at=i * 0.115, gain=0.45 - i * 0.1, speed=0.72, limit=0.10)
            tone(note, i * 0.115, 0.19, 0.18, material="wood")
        wash(0.02, duration * 0.65, 0.055)

    elif cue.recipe == "slide":
        source = sample(gain=0.62, speed=1.10 if cue.id == "card_flip" else 0.82,
                        limit=duration * 0.63, pan=-0.12)
        sample("card", duration * 0.34, 0.30, 0.16, speed=1.15, limit=0.10)
        wash(0.015, duration * 0.58, 0.10 if mythic else 0.035)
        if notes:
            for i, note in enumerate(notes):
                tone(note, 0.025 + i * 0.038, duration * 0.68, 0.033)
        if mythic:
            mix.grains(source, duration * 0.35, rng, at=0.02, gain=0.07, density=35)

    elif cue.recipe == "place":
        sample("slide", gain=0.28, speed=1.12, limit=0.13, pan=-0.15)
        sample(at=0.05, gain=0.70, limit=0.20)
        tone(notes[0] - 12, 0.048, 0.21, 0.16, material="wood")
        for i, note in enumerate(notes[1:]):
            tone(note, 0.075 + i * 0.032, duration * 0.65, 0.045, 0.12)
        if mythic:
            wash(0.02, duration * 0.8, 0.08)

    elif cue.recipe == "tear":
        source = sample("wrapper", gain=0.75, speed=0.96, limit=0.48, pan=-0.16)
        mix.grains(source, 0.31, rng, at=0.015, gain=0.25, density=65)
        sample("wrapper", 0.145, 0.25, 0.16, speed=1.15, limit=0.23)
        for at, length, gain in ((0.01, 0.16, 0.12), (0.135, 0.18, 0.10), (0.29, 0.23, 0.04)):
            tear = air(length, rng, 8500, 1200, "fall")
            mix.add(tear, at, gain, rng.uniform(-0.2, 0.2))
        sample("card", 0.11, 0.55, 0.15, speed=1.40, limit=0.14)
        sample("draw", 0.28, 0.48, 0.2, speed=1.1, limit=0.34)
        sample("fan", 0.38, 0.26, -0.12, speed=1.2, limit=0.32)
        mix.add(impact(0.28, rng, 0.80), 0.31, 0.16 if mythic else 0.07)
        wash(0.17, 0.51, 0.10 if mythic else 0.02)

    elif cue.recipe == "glint":
        sample(gain=0.28, limit=0.20)
        for i, note in enumerate(notes):
            tone(note, 0.035 + i * 0.075, duration * 0.76,
                 0.105 if i == 0 else 0.055, (-1) ** i * 0.20)
        if mythic:
            chord(0.04, duration * 0.7, 0.25)
        wash(0.03, duration * 0.65, 0.06)

    elif cue.recipe == "shimmer":
        source = sources["chip"][0]
        mix.grains(source, duration * 0.64, rng, at=0.035, gain=0.14,
                   density=60, reverse=mythic)
        for i in range(11):
            note = notes[i % len(notes)] + rng.choice((-12, 0, 0, 7))
            at = 0.025 + i * 0.073 + rng.uniform(0, 0.023)
            tone(note, at, 0.43, 0.06 * (1 - i / 16), rng.uniform(-0.65, 0.65), "metal")
        chord(0.07, duration * 0.84, 0.55, tuple(n - 12 for n in notes))
        wash(0.035, duration * 0.70, 0.17)

    elif cue.recipe == "reveal":
        large = cue.id != "rare"
        wash(0, 0.19, 0.32 if mythic else 0.12, reverse=True)
        sample(at=0.035, gain=0.45 if large else 0.25, speed=0.82, limit=0.23)
        mix.add(impact(0.55 if large else 0.3, rng, 1.18 if large else 0.78),
                0.075, (0.7 if mythic else 0.36) if large else 0.20)
        chord(0.08, duration * 0.69, 1.20 if mythic else 0.68)
        for i, note in enumerate(notes[1:]):
            tone(note, 0.11 + i * 0.034, duration * 0.67,
                 0.19 / (1 + i * 0.16), (-1) ** i * (0.38 if mythic else 0.19))
        source = sources["chip"][0]
        mix.grains(source, duration * 0.53, rng, at=0.24, gain=0.10, density=28)
        for i in range(5 if large else 3):
            tone(notes[-1] + (12 if i % 2 else 7), 0.34 + i * 0.11,
                 0.48, 0.04, rng.uniform(-0.6, 0.6), "metal")
        wash(0.15, duration * 0.69, 0.18 if mythic else 0.045)

    elif cue.recipe == "coins":
        count = 5 if cue.id in ("bulk_sell", "round_payout") else 3
        sample("slide", gain=0.18, speed=1.2, limit=0.14)
        for i in range(count):
            at = 0.035 + i * (0.105 - i * 0.007) + rng.uniform(0, 0.008)
            sample(at=at, gain=0.46 / (1 + i * 0.25), speed=0.9 + i * 0.06,
                   limit=0.18, pan=(-1) ** i * 0.18)
            tone(notes[i % len(notes)], at + 0.003, 0.28, 0.06 / (1 + i * 0.4), material="metal")
        if cue.id == "catalyst_sell":
            wash(0.01, 0.34, 0.16)
            tone(notes[0] - 12, 0.02, 0.5, 0.07, -0.2)
        if mythic:
            chord(0.04, duration * 0.72, 0.22)

    elif cue.recipe == "purchase":
        sample("chip", gain=0.48, speed=1.13, limit=0.16)
        sample("card", 0.13, 0.65, 0.16, speed=0.8, limit=0.28)
        tone(notes[0], 0.015, 0.30, 0.07, material="metal")
        tone(notes[1], 0.14, 0.40, 0.055, 0.20)
        if mythic:
            chord(0.09, 0.41, 0.45)
            wash(0.07, 0.31, 0.13)

    elif cue.recipe == "stamp":
        sample("slide", gain=0.44, speed=0.82, limit=0.20, pan=-0.18)
        sample("chip", 0.14, 0.65, speed=0.83, limit=0.17)
        mix.add(impact(0.19, rng, 0.65), 0.14, 0.18)
        tone(notes[0], 0.14, 0.24, 0.12, material="wood")
        chord(0.11, duration * 0.60, 0.30 if mythic else 0.12)
        wash(0.03, 0.3, 0.08)

    elif cue.recipe == "grade":
        sample(gain=0.80, speed=0.94, limit=0.16)
        tone(notes[0] - 12, 0.008, 0.23, 0.18, material="wood")
        chord(0.06, duration * 0.78, 0.8 if mythic else 0.5)
        for i, note in enumerate(notes):
            tone(note, 0.06 + i * 0.032, duration * 0.73, 0.14, (-1) ** i * 0.15)
        if cue.id == "grade_high":
            tone(notes[-1] + 12, 0.25, 0.44, 0.035, 0.25)
        wash(0.04, duration * 0.72, 0.09)

    elif cue.recipe == "progress":
        count = 3 if cue.id in ("evolution_complete", "reward_reveal") else 2
        spacing = 0.23 if cue.id == "reward_reveal" else 0.105
        for i in range(count):
            sample(at=i * spacing, gain=0.40 + i * 0.05, speed=0.90 + i * 0.06,
                   limit=0.25, pan=(i - 1) * 0.18)
            tone(notes[min(i, len(notes) - 1)], i * spacing + 0.022,
                 duration * 0.55, 0.18, (i - 1) * 0.15)
        landing = (count - 1) * spacing
        chord(landing + 0.018, duration * 0.64, 1.0 if mythic else 0.60)
        mix.add(impact(0.30, rng, 0.9), landing, 0.29 if mythic else 0.12)
        tone(notes[-1] + 12, landing + 0.055, duration * 0.59, 0.06, 0.28)
        wash(landing, duration * 0.52, 0.14 if mythic else 0.03)

    elif cue.recipe == "unlock":
        sample("slide", gain=0.28, speed=0.8, limit=0.18, pan=-0.20)
        sample(at=0.085, gain=0.66, speed=0.92, limit=0.22)
        sample("chip", 0.19, 0.28, 0.20, speed=1.2, limit=0.12)
        tone(notes[0], 0.08, 0.34, 0.12, material="wood")
        for i, note in enumerate(notes[1:]):
            tone(note, 0.15 + i * 0.065, duration * 0.60, 0.10, (-1) ** i * 0.19)
        chord(0.12, duration * 0.72, 0.8 if mythic else 0.43)
        wash(0.06, duration * 0.65, 0.22 if mythic else 0.035)

    elif cue.recipe == "arrival":
        boss = cue.id == "boss_round"
        wash(0, duration * 0.28, 0.40 if mythic else 0.16, reverse=True)
        landing = 0.27 if boss else 0.10
        sample(at=landing, gain=0.40, speed=0.64, limit=0.3)
        mix.add(impact(0.68, rng, 1.3 if boss else 1.0), landing, 0.80 if mythic else 0.38)
        if boss:
            mix.add(impact(0.5, rng, 1.05), 0.54, 0.40 if mythic else 0.20)
        chord(landing, duration * 0.65, 1.3 if mythic else 0.60)
        for i, note in enumerate(notes[-3:]):
            tone(note + 12, landing + 0.015 * i, duration * 0.64, 0.11, (i - 1) * 0.22, "metal")
        wash(landing, duration * 0.63, 0.18 if mythic else 0.04)

    elif cue.recipe == "swap":
        sample("slide", gain=0.54, pan=-0.38, speed=0.88, limit=0.22)
        sample(at=0.15, gain=0.62, pan=0.32, speed=1.05, limit=0.23)
        tone(notes[0], 0.02, 0.26, 0.08, -0.28, "wood")
        for i, note in enumerate(notes[1:]):
            tone(note, 0.19 + i * 0.03, duration * 0.57, 0.10, 0.22)
        if mythic or cue.id == "catalyst_swap":
            wash(0.005, duration * 0.7, 0.20)
            chord(0.15, duration * 0.68, 0.42)

    elif cue.recipe == "aura":
        wash(0, duration * 0.8, 0.25)
        chord(0.015, duration * 0.81, 0.8 if mythic else 0.5)
        mix.grains(sources["slide"][0], 0.25, rng, gain=0.07, density=30)

    elif cue.recipe == "magic":
        attune = cue.id == "catalyst_attune"
        source = sample(gain=0.20, speed=0.75, limit=0.23)
        mix.grains(source, duration * 0.55, rng, at=0.015,
                   gain=0.55 if mythic else 0.34, density=70, reverse=attune)
        wash(0, 0.35, 0.30 if mythic else 0.11, reverse=attune)
        landing = 0.23 if attune else 0.065
        mix.add(impact(0.37, rng, 0.86), landing, 0.33 if mythic else 0.15)
        chord(landing, duration * 0.67, 1.1 if mythic else 0.58)
        for i, note in enumerate(notes):
            tone(note, landing + i * 0.027, duration * 0.68, 0.14, (-1) ** i * 0.38, "metal")
        tone(notes[-1] + 12, landing + 0.17, 0.66, 0.035, 0.40)

    elif cue.recipe == "victory":
        intimate = cue.id == "trainer_unlock"
        landing = 0.10
        wash(0, 0.28, 0.36 if mythic else 0.12, reverse=True)
        for i, at in enumerate((landing, 0.30, 0.64) if not intimate else (0.06, 0.24)):
            sample(at=at, gain=0.36, speed=0.70 + i * 0.12, limit=0.24, pan=(i - 1) * 0.13)
            mix.add(impact(0.56, rng, 1.22 - i * 0.1), at, (0.60 if mythic else 0.24) / (i + 1))
        chord(landing, duration * 0.80, 1.8 if mythic else 0.88)
        for i, note in enumerate(notes[1:]):
            tone(note, 0.14 + i * 0.060, duration * 0.59, 0.20, (-1) ** i * 0.35)
        for i, note in enumerate(notes[-3:]):
            tone(note + 12, 0.69 + i * 0.085, duration * 0.46, 0.062, (i - 1) * 0.52)
        wash(0.5, duration * 0.65, 0.21 if mythic else 0.045)
        mix.grains(sources["chip"][0], duration * 0.48, rng, at=0.66, gain=0.09, density=22)

    elif cue.recipe == "defeat":
        sample(gain=0.32, speed=0.68, limit=0.34)
        mix.add(impact(0.55, rng, 1.30), 0.025, 0.26 if mythic else 0.11)
        chord(0.06, duration * 0.81, 0.90 if mythic else 0.6)
        for i, note in enumerate(reversed(notes[-3:])):
            tone(note, 0.06 + i * 0.09, duration * 0.68, 0.09, (i - 1) * 0.17, "wood")
        wash(0.07, duration * 0.68, 0.10)

    else:
        raise ValueError(f"No sound recipe for {cue.id}: {cue.recipe}")

    # Short gestures remain dry even in B; longer events get an actual diffuse room.
    decay = (0.15 if short else 0.90) if mythic else (0.10 if short else 0.43)
    wet = (0.055 if short else 0.24) if mythic else (0.025 if short else 0.10)
    mix.left, mix.right = room(mix.left, mix.right, decay, wet)
    if not mythic:
        mix.left = lowpass(mix.left, 13000)
        mix.right = lowpass(mix.right, 13000)
    target_db, peak_db = mix_targets(cue)
    return master(mix, target_db, peak_db, rng)
