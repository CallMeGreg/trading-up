#!/usr/bin/env python3
"""Render/check the review soundboard, never the app's shipping SFX.

    python3 tools/generate_sound_lab.py
    python3 tools/generate_sound_lab.py --list
    python3 tools/generate_sound_lab.py --check
    python3 tools/generate_sound_lab.py --check --rerender

All normal generation is offline, deterministic and Python-stdlib-only. See the
soundboard's source provenance for the separately prepared CC0 material audio.
"""

import argparse
import hashlib
import io
import json
import math
import sys
import wave
from array import array
from dataclasses import asdict
from pathlib import Path

from sound_lab.catalog import CUES, GROUPS, SCENES, STYLES, recommended_style
from sound_lab.dsp import SR, normalize
from sound_lab.recipes import render


ROOT = Path(__file__).resolve().parent.parent
LAB = ROOT / "docs" / "sound-lab"
CURRENT = LAB / "sources" / "legacy"
PREFIX = "globalThis.SOUND_LAB_MANIFEST = "
PACK_ID = "trading-up-materials-v1"


def digest(data):
    return hashlib.sha256(data).hexdigest()


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=True).encode()


def wav_bytes(pcm):
    samples = array("h", pcm)
    if sys.byteorder != "little":
        samples.byteswap()
    destination = io.BytesIO()
    with wave.open(destination, "wb") as output:
        output.setnchannels(2)
        output.setsampwidth(2)
        output.setframerate(SR)
        output.writeframes(samples.tobytes())
    return destination.getvalue()


def read_pcm(data):
    with wave.open(io.BytesIO(data), "rb") as source:
        if source.getsampwidth() != 2 or source.getcomptype() != "NONE":
            raise ValueError("Expected uncompressed 16-bit PCM")
        channels = source.getnchannels()
        rate = source.getframerate()
        frames = source.getnframes()
        raw = source.readframes(frames)
    if len(raw) != frames * channels * 2:
        raise ValueError("Truncated WAV data")
    pcm = array("h")
    pcm.frombytes(raw)
    if sys.byteorder != "little":
        pcm.byteswap()
    return pcm, channels, rate


def db(value):
    return round(20 * math.log10(max(value, 1e-12)), 3)


def measure(data):
    pcm, channels, rate = read_pcm(data)
    if not pcm:
        raise ValueError("Empty WAV")
    peak = max(map(abs, pcm)) / 32767
    if peak < 0.0001:
        raise ValueError("Silent or unusably quiet WAV")
    gate = peak * 0.018 * 32767
    active = [x / 32767 for x in pcm if abs(x) > gate]
    active_rms = math.sqrt(sum(x * x for x in active) / len(active))
    rms = math.sqrt(sum((x / 32767) ** 2 for x in pcm) / len(pcm))
    width = max(1, len(pcm) // 64)
    waveform = [
        round(max(map(abs, pcm[i * width:min(len(pcm), (i + 1) * width)]), default=0) / 32767 / peak, 4)
        for i in range(64)
    ]
    return {
        "sha256": digest(data),
        "duration": round(len(pcm) / channels / rate, 6),
        "sampleRate": rate,
        "channels": channels,
        "peakDb": db(peak),
        "activeRmsDb": db(active_rms),
        "rmsDb": db(rms),
        "waveform": waveform,
    }


def load_sources():
    provenance = json.loads((LAB / "sources" / "provenance.json").read_text())
    groups = {}
    for entry in provenance["files"]:
        path = LAB / entry["file"]
        data = path.read_bytes()
        if digest(data) != entry["sha256"]:
            raise ValueError(f"Source provenance hash mismatch: {path}")
        pcm, channels, rate = read_pcm(data)
        if channels != 1 or rate != SR:
            raise ValueError(f"Source must be 48 kHz mono: {path}")
        samples = normalize(array("d", (x / 32767 for x in pcm)), peak=0.8)
        groups.setdefault(entry["group"], []).append(samples)
    required = {"card", "slide", "fan", "chip", "stack", "wrapper", "draw"}
    if set(groups) != required:
        raise ValueError(f"Expected material groups {required}, found {set(groups)}")
    license_data = (LAB / provenance["licenseFile"]).read_bytes()
    if digest(license_data) != provenance["licenseSha256"]:
        raise ValueError("The included source license no longer matches its provenance")
    return groups, provenance


def options():
    return (
        {
            "name": "Original offline synthesis",
            "url": "https://docs.python.org/3/license.html",
            "license": "Python / PSF license. New project-authored DSP and sound designs.",
            "decision": "Included. Deterministic layers, no service, no third-party runtime or sample preset dependency.",
        },
        {
            "name": "Kenney / Casino Audio",
            "url": "https://kenney.nl/assets/casino-audio",
            "license": "Specific source audio: CC0 1.0. Commercial use and modification; attribution not required.",
            "decision": "Included as the physical card/chip foundation. Source selection, hashes and the supplied license are bundled.",
        },
        {
            "name": "Audacity",
            "url": "https://manual.audacityteam.org/man/faq_about_audacity.html",
            "license": "GPL editor; original audio exports are not made GPL by editing them.",
            "decision": "Optional offline finishing, not installed or shipped. Suitable for hand-editing, EQ and additional listening polish; imported audio still needs its own license.",
        },
        {
            "name": "Surge XT",
            "url": "https://surge-synthesizer.github.io/faq/",
            "license": "GPL-3.0 software. Official FAQ explicitly permits commercial sound exports, including factory-preset output.",
            "decision": "Best optional upgrade for bespoke resonant/waveguide/FM layers. Not installed or bundled. Export audio offline; do not embed the GPL engine. Imported third-party content still needs its own clearance.",
        },
        {
            "name": "SuperCollider",
            "url": "https://supercollider.github.io/",
            "license": "GPL-3.0 sound-synthesis environment; source material has separate rights.",
            "decision": "Optional offline procedural production. Powerful for resonators/granular textures, but unnecessary for regenerating these candidates. Not an app dependency.",
        },
        {
            "name": "Maximilian / C++ core",
            "url": "https://github.com/micknoise/Maximilian/blob/master/LICENSE.txt",
            "license": "MIT license for the inspected core, including commercial use with notice preservation.",
            "decision": "A permissive-code alternative if native C++ DSP becomes necessary. Not used here; the iOS app already has AVFoundation. This is not blanket clearance for every example, asset or optional dependency.",
        },
        {
            "name": "Faust",
            "url": "https://faustdoc.grame.fr/manual/faq/",
            "license": "LGPL compiler; generated-code obligations depend on selected DSP libraries and architecture-file exceptions.",
            "decision": "An offline DSP-authoring alternative, not a blanket permissive runtime recommendation. No Faust code or architecture is used in this prototype.",
        },
        {
            "name": "FFmpeg",
            "url": "https://ffmpeg.org/legal.html",
            "license": "LGPL-2.1-or-later, or GPL with selected build options. Offline conversion tool only.",
            "decision": "Offline source-PCM preparation and encoding of original music. No FFmpeg binary/library is included in the app. SFX rendering uses only Python.",
        },
    )


def render_cue(cue, sources):
    takes = []
    for style in STYLES:
        for index in range(cue.variants):
            pcm = render(cue, style, index, sources)
            measured = measure(wav_bytes(pcm))
            takes.append((style, pcm, measured["activeRmsDb"]))
    # Match the actual material gestures, not merely their peak amplitudes.
    # Downward-only matching preserves transients/headroom and avoids rewarding B
    # for being louder than A. Alternate takes receive the same comparison level.
    common_level = min(level for _, _, level in takes)
    result = {style: [] for style in STYLES}
    for style, pcm, level in takes:
        gain = 10 ** ((common_level - level) / 20)
        data = wav_bytes(array("h", (round(value * gain) for value in pcm)))
        result[style].append((data, measure(data)))
    return result


def render_pack():
    sources, provenance = load_sources()
    output = {
        "schemaVersion": 1,
        "id": PACK_ID,
        "styles": STYLES,
        "groups": GROUPS,
        "sampleRate": SR,
        "cues": [],
        "scenes": SCENES,
        "options": options(),
        "links": (
            {"name": "Included Kenney license", "url": provenance["licenseFile"]},
            {"name": "Source provenance & SHA-256 hashes", "url": "sources/provenance.json"},
            {"name": "CC0 1.0 legal text", "url": "https://creativecommons.org/publicdomain/zero/1.0/legalcode"},
            {"name": "Kenney commercial-use FAQ", "url": "https://kenney.nl/support"},
            {"name": "Surge's explicit audio-export rights", "url": "https://github.com/surge-synthesizer/surge-synthesizer.github.io/blob/master/src/content/pages/faq.mdx#L6-L12"},
            {"name": "GNU: software licenses and original output", "url": "https://www.gnu.org/licenses/gpl-faq.html#GPLOutput"},
        ),
    }
    total_bytes = 0
    count = 0
    for cue in CUES:
        entry = {key: value for key, value in asdict(cue).items()
                 if key not in ("recipe", "material", "notes", "duration", "legacy", "variants")}
        entry["recommended"] = recommended_style(cue)
        entry["audio"] = {}
        rendered = render_cue(cue, sources)
        for style in STYLES:
            takes = []
            for take, (data, measurements) in enumerate(rendered[style]):
                relative = f"audio/{style}/{cue.id}_{take + 1:02d}.wav"
                path = LAB / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(data)
                takes.append({"file": relative, **measurements})
                total_bytes += len(data)
                count += 1
            entry["audio"][style] = takes
        entry["current"] = None
        if cue.legacy:
            data = (CURRENT / f"{cue.legacy}.wav").read_bytes()
            relative = f"audio/current/{cue.legacy}.wav"
            path = LAB / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
            measured = measure(data)
            target_db = min(take["activeRmsDb"] for takes in entry["audio"].values() for take in takes)
            gain = min(1.0, 10 ** ((target_db - measured["activeRmsDb"]) / 20))
            entry["current"] = {
                "file": relative, "name": cue.legacy, "gain": round(gain, 6), **measured,
            }
        entry["revision"] = digest(canonical(entry))
        output["cues"].append(entry)
        print(f"  {cue.id:23s} A + B / {cue.variants} take(s)", flush=True)
    output["revision"] = digest(canonical(output))
    (LAB / "catalog.js").write_text(PREFIX + json.dumps(output, indent=2, ensure_ascii=True) + ";\n")
    print(f"Rendered {len(CUES)} actions / {count} candidate WAVs / {total_bytes / 1048576:.1f} MiB")
    print(f"Soundboard rendered; use generate_sfx.py to publish an approved selection. {LAB / 'index.html'}")


def read_manifest():
    text = (LAB / "catalog.js").read_text()
    if not text.startswith(PREFIX) or not text.endswith(";\n"):
        raise ValueError("Invalid generated catalogue wrapper")
    return json.loads(text[len(PREFIX):-2])


def check_pack(rerender=False):
    sources, _ = load_sources()
    manifest = read_manifest()
    revision = manifest.pop("revision")
    if digest(canonical(manifest)) != revision:
        raise ValueError("Catalogue revision does not match its contents")
    if manifest["id"] != PACK_ID or manifest["sampleRate"] != SR:
        raise ValueError("Unexpected sound pack or sample rate")
    expected_ids = {cue.id for cue in CUES}
    if len(expected_ids) != len(CUES) or len(manifest["cues"]) != len(CUES):
        raise ValueError("Cue count or IDs are inconsistent")
    actual_ids = {cue["id"] for cue in manifest["cues"]}
    if actual_ids != expected_ids:
        raise ValueError("The catalogue does not cover every defined action")
    definitions = {cue.id: cue for cue in CUES}
    fingerprints = set()
    expected_files = set()
    total = 0
    for entry in manifest["cues"]:
        cue_revision = entry.pop("revision")
        if digest(canonical(entry)) != cue_revision:
            raise ValueError(f"Cue revision mismatch: {entry['id']}")
        cue = definitions[entry["id"]]
        reproduced = render_cue(cue, sources) if rerender else None
        if set(entry["audio"]) != set(STYLES):
            raise ValueError(f"Missing A/B direction for {cue.id}")
        for style, takes in entry["audio"].items():
            if len(takes) != cue.variants:
                raise ValueError(f"Missing alternate takes for {cue.id}/{style}")
            for index, take in enumerate(takes):
                path = LAB / take["file"]
                data = path.read_bytes()
                if digest(data) != take["sha256"]:
                    raise ValueError(f"Candidate hash mismatch: {path}")
                if take["sha256"] in fingerprints:
                    raise ValueError(f"Duplicate audio masquerading as a new take: {path}")
                fingerprints.add(take["sha256"])
                expected_files.add(path)
                measured = measure(data)
                for key, value in measured.items():
                    if take[key] != value:
                        raise ValueError(f"Stale audio measurement {key}: {path}")
                pcm, channels, rate = read_pcm(data)
                if channels != 2 or rate != SR:
                    raise ValueError(f"Candidate must be 48 kHz stereo: {path}")
                if not 0.1 <= measured["duration"] <= 4:
                    raise ValueError(f"Unexpected duration: {path}")
                if measured["peakDb"] > -3.49 or measured["peakDb"] < -32:
                    raise ValueError(f"Peak outside audition headroom limits: {path}")
                if any(pcm[:2]) or any(pcm[-2:]):
                    raise ValueError(f"Nonzero waveform endpoint: {path}")
                for channel in (pcm[::2], pcm[1::2]):
                    if abs(sum(channel) / len(channel) / 32767) > 0.002:
                        raise ValueError(f"Excessive DC offset: {path}")
                left_energy = sum(x * x for x in pcm[::2])
                right_energy = sum(x * x for x in pcm[1::2])
                mono_energy = sum(((l + r) / 2) ** 2 for l, r in zip(pcm[::2], pcm[1::2]))
                if mono_energy < max(left_energy, right_energy) * 0.25:
                    raise ValueError(f"Excessive cancellation in mono: {path}")
                tail = pcm[-round(0.01 * SR) * 2:]
                if db(math.sqrt(sum((x / 32767) ** 2 for x in tail) / len(tail))) > -42:
                    raise ValueError(f"Tail ends too abruptly: {path}")
                if reproduced and reproduced[style][index][1]["sha256"] != take["sha256"]:
                    raise ValueError(f"Non-deterministic render: {path}")
                total += 1
        levels = [take["activeRmsDb"] for takes in entry["audio"].values() for take in takes]
        if max(levels) - min(levels) > 0.15:
            raise ValueError(f"A/B and alternate-take active RMS differs by more than 0.15 dB: {cue.id}")
        if cue.legacy:
            reference = entry["current"]
            path = LAB / reference["file"]
            if path.read_bytes() != (CURRENT / f"{cue.legacy}.wav").read_bytes():
                raise ValueError(f"Pre-redesign comparison no longer matches its archived source: {path}")
            if digest(path.read_bytes()) != reference["sha256"]:
                raise ValueError(f"Current-sound comparison hash mismatch: {path}")
            expected_files.add(path)
        elif entry["current"] is not None:
            raise ValueError(f"Invented current-sound comparison: {cue.id}")
    if set((LAB / "audio").rglob("*.wav")) != expected_files:
        raise ValueError("Uncatalogued or missing WAVs in the review audio directory")
    for scene in manifest["scenes"]:
        previous = -1
        for at, cue_id in scene["events"]:
            if cue_id not in expected_ids or at < previous:
                raise ValueError(f"Invalid scene event: {scene['id']}")
            previous = at
    if {path.stem for path in (LAB / "audio" / "current").glob("*.wav")} != {
        path.stem for path in CURRENT.glob("*.wav")
    }:
        raise ValueError("Not every archived pre-redesign sound has a comparison")
    print(f"PASS: {len(CUES)} action mappings, {total} distinct stereo WAVs, source/license hashes,")
    print("      A/B levels, headroom, fades, mono retention, scenes and all 7 pre-redesign comparisons.")
    if rerender:
        print(f"PASS: all {total} candidate WAVs reproduce byte-for-byte from the source recipes.")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--list", action="store_true", help="List proposed action coverage without rendering")
    parser.add_argument("--check", action="store_true", help="Check catalogue, provenance and every WAV")
    parser.add_argument("--rerender", action="store_true", help="With --check, reproduce every candidate in memory")
    args = parser.parse_args()
    if args.rerender and not args.check:
        parser.error("--rerender requires --check")
    if args.list:
        for cue in CUES:
            print(f"{cue.id:23s} {','.join(cue.modes):17s} {cue.title}")
    elif args.check:
        check_pack(args.rerender)
    else:
        render_pack()


if __name__ == "__main__":
    main()
