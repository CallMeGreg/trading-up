"""Small offline DSP building blocks; Python standard library only."""

import math
import random
from array import array
from collections import deque


SR = 48000
TAU = 2 * math.pi


def hz(midi):
    return 440 * 2 ** ((midi - 69) / 12)


def silence(duration):
    return array("d", [0.0]) * round(duration * SR)


def fade(signal, attack=0.003, release=0.025):
    out = array("d", signal)
    a = min(len(out), max(2, round(attack * SR)))
    r = min(len(out), max(2, round(release * SR)))
    for i in range(a):
        out[i] *= math.sin(i / (a - 1) * math.pi / 2) ** 2
    for i in range(r):
        out[-1 - i] *= math.sin(i / (r - 1) * math.pi / 2) ** 2
    return out


def normalize(signal, peak=0.8):
    maximum = max(map(abs, signal), default=0)
    if maximum == 0:
        raise ValueError("Cannot normalize a silent source")
    return array("d", (x * peak / maximum for x in signal))


def lowpass(signal, cutoff):
    coefficient = 1 - math.exp(-TAU * cutoff / SR)
    first = second = 0.0
    out = array("d")
    for x in signal:
        first += coefficient * (x - first)
        second += coefficient * (first - second)
        out.append(second)
    return out


def highpass(signal, cutoff):
    coefficient = math.exp(-TAU * cutoff / SR)
    previous = state = 0.0
    out = array("d")
    for x in signal:
        state = coefficient * (state + x - previous)
        previous = x
        out.append(state)
    return out


def resample(signal, speed):
    if not 0.45 <= speed <= 2.2:
        raise ValueError(f"Unsupported source speed: {speed}")
    # Filtering before speeding a source up avoids folding its top end down.
    source = lowpass(signal, min(14000, 15000 / speed))
    out = array("d")
    for i in range(int((len(source) - 1) / speed)):
        position = i * speed
        index = int(position)
        fraction = position - index
        out.append(source[index] * (1 - fraction) + source[index + 1] * fraction)
    return fade(out, 0.0015, 0.012)


def modal(note, duration, rng, material="glass", softness=0.5):
    """Damped, slightly inharmonic resonances; no square/saw wave oscillators."""
    tables = {
        "glass": ((1, 1), (2.004, 0.36), (2.756, 0.17), (4.07, 0.11), (5.43, 0.06)),
        "wood": ((1, 1), (1.59, 0.42), (2.14, 0.25), (3.29, 0.12)),
        "metal": ((1, 1), (1.48, 0.30), (2.09, 0.25), (2.77, 0.18), (4.31, 0.07)),
    }
    out = silence(duration)
    fundamental = hz(note) * rng.uniform(0.996, 1.004)
    for ratio, amplitude in tables[material]:
        frequency = fundamental * ratio
        if frequency > 14000:
            continue
        decay = (5.2 + ratio * (2.0 + softness * 2)) / duration
        step = TAU * frequency / SR
        phase = rng.uniform(-0.08, 0.08)
        gain = amplitude / (1 + softness * (ratio - 1))
        multiplier = math.exp(-decay / SR)
        envelope = gain
        for i in range(len(out)):
            out[i] += math.sin(phase) * envelope
            phase += step
            envelope *= multiplier
    return fade(out, 0.002 + softness * 0.004, min(0.06, duration / 4))


def bloom(notes, duration, rng, lift=False):
    """Soft, detuned harmonic body with integrated pitch drift and a bowed onset."""
    out = silence(duration)
    for note in notes:
        for detune, gain in ((-0.003, 0.16), (0.002, 0.16)):
            frequency = hz(note) * (1 + detune)
            phase = rng.uniform(0, TAU)
            step = TAU * frequency / SR
            modulation_phase = rng.uniform(0, TAU)
            for i in range(len(out)):
                t = i / SR
                position = t / duration
                envelope = math.sin(math.pi * position) ** (1.4 if lift else 2.2)
                drift = 1 + 0.0018 * math.sin(TAU * 3.1 * t + modulation_phase)
                phase += step * drift
                voice = math.sin(phase) + 0.20 * math.sin(2 * phase) + 0.065 * math.sin(3 * phase)
                out[i] += voice * gain * envelope / math.sqrt(len(notes))
    return fade(out, min(duration / 3, 0.13), min(duration / 3, 0.22))


def impact(duration, rng, weight=1.0):
    """Pitched low body plus midrange harmonics that survive a phone speaker."""
    out = silence(duration)
    phase = 0.0
    for i in range(len(out)):
        t = i / SR
        frequency = (65 + 130 * math.exp(-t * 45)) / weight
        phase += TAU * frequency / SR
        envelope = math.exp(-t * 15 / weight)
        skin = rng.uniform(-1, 1) * math.exp(-t * 190) * 0.22
        body = math.sin(phase) + 0.30 * math.sin(2 * phase) + 0.15 * math.sin(3 * phase)
        out[i] = body * envelope * 0.65 + skin
    return fade(out, 0.002, 0.045)


def air(duration, rng, start=600, end=6000, shape="swell"):
    """Moving filtered noise with irregular amplitude, not a static white hiss."""
    out = silence(duration)
    first = second = slow = 0.0
    wobble = rng.uniform(0, TAU)
    for i in range(len(out)):
        position = i / max(1, len(out) - 1)
        cutoff = start * (end / start) ** position
        coefficient = 1 - math.exp(-TAU * cutoff / SR)
        white = rng.uniform(-1, 1)
        first += coefficient * (white - first)
        second += coefficient * (first - second)
        slow += 0.025 * (second - slow)
        if shape == "swell":
            envelope = math.sin(math.pi * position) ** 1.7
        elif shape == "reverse":
            envelope = position ** 1.6
        elif shape == "fall":
            envelope = math.exp(-position * 6)
        else:
            raise ValueError(f"Unknown air envelope: {shape}")
        modulation = 0.72 + 0.18 * math.sin(position * 37 + wobble) + 0.1 * math.sin(position * 113)
        out[i] = (second - slow) * envelope * modulation
    return fade(out, 0.004, 0.025)


class Mix:
    def __init__(self, duration):
        self.left = silence(duration)
        self.right = silence(duration)

    def add(self, signal, at=0, gain=1, pan=0):
        if at < 0 or not -1 <= pan <= 1:
            raise ValueError("Invalid layer placement")
        offset = round(at * SR)
        need = offset + len(signal) - len(self.left)
        if need > 0:
            self.left.extend([0.0] * need)
            self.right.extend([0.0] * need)
        left_gain = math.cos((pan + 1) * math.pi / 4) * gain
        right_gain = math.sin((pan + 1) * math.pi / 4) * gain
        for i, x in enumerate(signal, offset):
            self.left[i] += x * left_gain
            self.right[i] += x * right_gain

    def grains(self, source, duration, rng, at=0, gain=0.1, density=30, reverse=False):
        """Windowed fragments of physical foley make irregular, moving detail."""
        count = max(2, round(duration * density))
        for k in range(count):
            progress = k / (count - 1)
            size = min(len(source), round(rng.uniform(0.012, 0.043) * SR))
            offset = rng.randrange(max(1, len(source) - size + 1))
            grain = array("d", source[offset:offset + size])
            if reverse:
                grain.reverse()
            for i in range(size):
                grain[i] *= math.sin(math.pi * i / max(1, size - 1)) ** 2
            envelope = math.sin(math.pi * (0.04 + progress * 0.92)) ** 0.7
            pan = math.sin(progress * TAU + rng.uniform(-0.2, 0.2)) * 0.55
            self.add(grain, at + progress * duration, gain * envelope, pan)


def _allpass(signal, delay, feedback):
    memory = [0.0] * delay
    out = array("d")
    index = 0
    for x in signal:
        stored = memory[index]
        y = stored - feedback * x
        memory[index] = x + feedback * y
        out.append(y)
        index = (index + 1) % delay
    return out


def room(left, right, decay, wet):
    """Damped combs and all-pass diffusion, with asymmetric stereo early reflections."""
    mono = highpass(array("d", ((l + r) * 0.5 for l, r in zip(left, right))), 380)
    results = []
    for channel, dry in enumerate((left, right)):
        reverberant = silence(len(dry) / SR)
        for seconds in (0.0297, 0.0371, 0.0411, 0.0437):
            delay = round(seconds * SR) + channel * 43
            memory = [0.0] * delay
            feedback = 10 ** (-3 * delay / SR / decay)
            filtered = 0.0
            index = 0
            for i, x in enumerate(mono):
                stored = memory[index]
                filtered += 0.42 * (stored - filtered)
                memory[index] = x + filtered * feedback
                reverberant[i] += stored * 0.25
                index = (index + 1) % delay
        reverberant = _allpass(reverberant, round(0.0051 * SR) + channel * 19, 0.62)
        reverberant = _allpass(reverberant, round(0.0017 * SR) + channel * 11, 0.57)
        out = array("d", dry)
        for i, x in enumerate(reverberant):
            out[i] += x * wet
        for seconds, gain in ((0.011, 0.16), (0.019, 0.11), (0.031, 0.07)):
            offset = round(seconds * SR) + channel * 59
            for i in range(offset, len(out)):
                out[i] += mono[i - offset] * gain * wet
        results.append(out)
    return results


def master(mix, target_db, peak_db, rng):
    """DC removal, gentle transient control, category gain and TPDF quantization."""
    channels = [highpass(channel, 45) for channel in (mix.left, mix.right)]
    envelope = 0.0
    attack = math.exp(-1 / (0.002 * SR))
    release = math.exp(-1 / (0.055 * SR))
    for i, (left, right) in enumerate(zip(*channels)):
        level = max(abs(left), abs(right))
        coefficient = attack if level > envelope else release
        envelope = coefficient * envelope + (1 - coefficient) * level
        compression = (0.45 / envelope) ** 0.45 if envelope > 0.45 else 1
        for channel in channels:
            channel[i] = math.tanh(channel[i] * compression * 1.12) / 1.12

    peak = max(max(map(abs, channel)) for channel in channels)
    if peak < 0.00001:
        raise ValueError("Rendered sound is silent")
    gate = peak * 0.018
    active = [x for channel in channels for x in channel if abs(x) > gate]
    rms = math.sqrt(sum(x * x for x in active) / len(active))
    gain = 10 ** (target_db / 20) / rms
    ceiling = 10 ** (peak_db / 20)
    peaks = [max(abs(l), abs(r)) * gain for l, r in zip(*channels)]
    window = deque()
    lookahead = round(0.0015 * SR)
    recovery = math.exp(-1 / (0.028 * SR))
    limiting = 1.0
    # Look ahead at the physical transients instead of turning an entire gesture
    # down to accommodate one chip click. Stereo stays linked and image-stable.
    future = 0
    for i in range(len(peaks)):
        while future < min(len(peaks), i + lookahead + 1):
            while window and peaks[window[-1]] <= peaks[future]:
                window.pop()
            window.append(future)
            future += 1
        while window and window[0] < i:
            window.popleft()
        upcoming = peaks[window[0]]
        needed = min(1.0, ceiling / max(upcoming, 1e-12))
        limiting = min(needed, recovery * limiting + (1 - recovery) * needed)
        for channel in channels:
            channel[i] *= gain * limiting
    channels = [fade(channel, 0.002, 0.055) for channel in channels]
    pcm = array("h")
    for i, (left, right) in enumerate(zip(*channels)):
        for x in (left, right):
            dither = (rng.random() - rng.random()) / 32768
            value = round((x + dither) * 32767)
            if i == 0 or i == len(channels[0]) - 1:
                value = 0
            if abs(value) > 32767:
                raise ValueError("Master clipped; lower the category peak limit")
            pcm.append(value)
    return pcm


def seeded(key):
    # Unlike hash(), a string seed is stable across Python processes.
    return random.Random(key)
