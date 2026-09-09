#!/usr/bin/env python3
"""Compose and verify Trading Up's original, circular background music.

Requires Python 3 and the already-installed offline ffmpeg/ffprobe executables.
No packages, samples, network, model weights, or plugins are used. Instrument
and score source lives in tools/sound_lab/music.py; shared DSP is read-only.

    python3 tools/generate_music.py
    python3 tools/generate_music.py --check
    python3 tools/generate_music.py --check --render-pcm

Generation writes four AAC-LC auditions and byte-identical copies of only the
two recommended tracks into the app. No WAV files are retained. Scratch files
live under the repository's ignored build/music-render directory and are
removed on success or failure.

The actual tempo is adjusted by < 0.04 BPM so each 16-bar period contains a
whole number of 1024-frame AAC access units. Encoding receives three periods;
the middle period is losslessly remuxed with an MP4 edit list, retaining decoder
pre-roll but excluding priming and padding from presentation. This avoids both
zero-context encoding at the musical seam and a silent tail. Validation decodes
the result WITHOUT duration trimming and insists on the exact PCM frame count.

--check verifies source/output hashes, score constraints, stored pre-encode
seam measurements, AAC edit-list/packet timing, decoded peaks/seams and format.
--render-pcm additionally recomposes every cue to verify the PCM hashes and
seams directly. It does not rewrite assets. Regeneration is deterministic on
the same Python/math and ffmpeg build; a different AAC encoder build can change
compressed bytes. Browser/app gapless playback still depends on the player
honoring MP4 edit lists; these files cannot prevent a player scheduling a gap.

These are intentionally quiet beds (approximately -24 dBFS RMS, peak ceiling
-8.5 dBFS before AAC). The app starts at 28% music volume under the SFX.
"""

import argparse
import hashlib
import json
import math
import os
import re
import shutil
import subprocess
import sys
from array import array
from pathlib import Path

from sound_lab.music import AAC_FRAME, BARS, LICENSE, SCORES, SR, render, validate_scores


ROOT = Path(__file__).resolve().parents[1]
AUDITIONS = ROOT / "docs/sound-lab/music"
APP = ROOT / "TradingUp/Audio/Music"
CATALOG = ROOT / "docs/sound-lab/music-catalog.js"
SCRATCH = ROOT / "build/music-render"
SOURCE_FILES = ("tools/generate_music.py", "tools/sound_lab/music.py", "tools/sound_lab/dsp.py")
PREFIX = "globalThis.SOUND_LAB_MUSIC = "


def require(condition, message):
    if not condition:
        raise ValueError(message)


def run(command, **kwargs):
    result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, **kwargs)
    if result.returncode:
        raise RuntimeError(f"{Path(command[0]).name} failed: {result.stderr.decode(errors='replace')[-4000:]}")
    return result


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def source_hashes():
    return {name: sha256(ROOT / name) for name in SOURCE_FILES}


def db(value):
    return 20 * math.log10(max(value, 1e-12))


def interleave(left, right):
    samples = array("f", [0]) * (len(left) * 2)
    samples[0::2], samples[1::2] = left, right
    if sys.byteorder != "little":
        samples.byteswap()
    return samples.tobytes()


def metrics(left, right):
    frames = len(left)
    require(frames == len(right) and frames > SR, "Invalid stereo PCM")
    require(all(math.isfinite(x) for channel in (left, right) for x in channel), "Non-finite PCM")
    peak = max(max(map(abs, left)), max(map(abs, right)))
    rms = math.sqrt(sum(x * x for channel in (left, right) for x in channel) / (2 * frames))
    boundary = max(abs(channel[0] - channel[-1]) for channel in (left, right))
    nearby_steps = []
    edge_rms = []
    for channel in (left, right):
        for part in (channel[:SR // 8], channel[-SR // 8:]):
            nearby_steps.extend(abs(b - a) for a, b in zip(part, part[1:]))
            edge_rms.append(math.sqrt(sum(x * x for x in part) / len(part)))
    nearby_steps.sort()
    p99 = nearby_steps[round((len(nearby_steps) - 1) * .99)]
    return {
        "frames": frames,
        "peakDBFS": round(db(peak), 6),
        "rmsDBFS": round(db(rms), 6),
        "boundaryStep": boundary,
        "nearbyStepP99": p99,
        "edgeRMSRatio": min(edge_rms) / rms,
        "dc": max(abs(sum(channel) / frames) for channel in (left, right)),
    }


def validate_metrics(values, label, encoded=False):
    require(-32 < values["rmsDBFS"] < -19, f"{label}: inappropriate music RMS")
    require(values["peakDBFS"] <= (-6.5 if encoded else -8.45), f"{label}: peak ceiling exceeded")
    require(values["edgeRMSRatio"] > .12, f"{label}: possible silence/fade at the loop boundary")
    require(values["dc"] < .0001, f"{label}: excessive DC offset")
    limit = max(.003 if not encoded else .006, values["nearbyStepP99"] * 2.5)
    require(values["boundaryStep"] <= limit,
            f"{label}: discontinuity {values['boundaryStep']:.6f} exceeds local sample-step limit {limit:.6f}")


def encode(ffmpeg, pcm, score, destination, work):
    extended = work / f"{score.id}-preroll.m4a"
    command = [
        ffmpeg, "-hide_banner", "-loglevel", "error", "-y", "-f", "f32le",
        "-ar", str(SR), "-ac", "2", "-i", "pipe:0", "-map_metadata", "-1",
        "-c:a", "aac", "-profile:a", "aac_low", "-b:a", "192k",
        "-aac_coder", "twoloop", "-use_editlist", "1", "-movie_timescale", str(SR),
        "-movflags", "+faststart", str(extended),
    ]
    # Streaming repeated PCM avoids large WAV or triple-period PCM artifacts.
    with subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE) as process:
        try:
            for _ in range(3):
                process.stdin.write(pcm)
            process.stdin.close()
            error = process.stderr.read()
            code = process.wait()
        except (BrokenPipeError, OSError):
            error = process.stderr.read()
            process.wait()
            raise RuntimeError(f"ffmpeg encoding failed: {error.decode(errors='replace')[-4000:]}")
    require(code == 0, f"ffmpeg encoding failed: {error.decode(errors='replace')[-4000:]}")
    preroll = AAC_FRAME / SR
    # Input seeking alone drops the preceding access unit. Keep it explicitly,
    # timestamp it before zero, and let the MP4 edit list discard its output.
    run([
        ffmpeg, "-hide_banner", "-loglevel", "error", "-y",
        "-ss", f"{score.duration - preroll:.12f}", "-i", str(extended),
        "-t", f"{score.duration + preroll:.12f}",
        "-map", "0:a:0", "-c:a", "copy", "-map_metadata", "-1",
        "-output_ts_offset", f"{-preroll:.12f}",
        "-avoid_negative_ts", "disabled", "-use_editlist", "1",
        "-movie_timescale", str(SR), "-movflags", "+faststart", str(destination),
    ])
    extended.unlink()


def inspect_audio(ffmpeg, ffprobe, path, score):
    probe = json.loads(run([
        ffprobe, "-v", "error", "-select_streams", "a:0", "-show_streams",
        "-show_format", "-show_packets", "-show_entries",
        "stream=codec_name,profile,sample_rate,channels,time_base,start_pts,duration_ts:"
        "format=duration,size:packet=pts,dts,duration,side_data_list",
        "-of", "json", str(path),
    ]).stdout)
    streams = probe["streams"]
    require(len(streams) == 1, f"{path.name}: expected one audio stream")
    stream = streams[0]
    require(stream["codec_name"] == "aac" and stream["profile"] == "LC", f"{path.name}: expected AAC-LC")
    require(int(stream["sample_rate"]) == SR and stream["channels"] == 2, f"{path.name}: expected 48 kHz stereo")
    require(stream["time_base"] == f"1/{SR}", f"{path.name}: incorrect audio time base")
    require(stream.get("start_pts", 0) == 0, f"{path.name}: presentation does not start at zero")
    require(stream["duration_ts"] == score.frames, f"{path.name}: stream duration includes padding")
    require(abs(float(probe["format"]["duration"]) - score.duration) < 1 / SR, f"{path.name}: container duration mismatch")
    packets = probe["packets"]
    require(packets[-1]["pts"] + packets[-1]["duration"] == score.frames, f"{path.name}: trailing AAC padding")
    for previous, current in zip(packets, packets[1:]):
        require(previous["pts"] + previous["duration"] == current["pts"], f"{path.name}: discontinuous packet timeline")
    skips = [
        item.get("skip_samples", 0)
        for packet in packets
        for item in packet.get("side_data_list", [])
        if item.get("side_data_type") == "Skip Samples"
    ]
    priming = sum(skips)
    require(packets[0]["pts"] <= 0 and priming == -packets[0]["pts"],
            f"{path.name}: encoder priming is not excluded by the edit list")
    require(priming >= AAC_FRAME, f"{path.name}: missing decoder pre-roll")

    raw = run([
        ffmpeg, "-hide_banner", "-loglevel", "error", "-i", str(path),
        "-map", "0:a:0", "-f", "f32le", "-c:a", "pcm_f32le", "pipe:1",
    ]).stdout
    require(len(raw) == score.frames * 8,
            f"{path.name}: decoder produced {len(raw) // 8} frames, expected {score.frames}; padding/gap detected")
    samples = array("f")
    samples.frombytes(raw)
    if sys.byteorder != "little":
        samples.byteswap()
    values = metrics(samples[0::2], samples[1::2])
    validate_metrics(values, path.name, encoded=True)
    loudness_result = run([
        ffmpeg, "-hide_banner", "-nostats", "-i", str(path),
        "-af", "ebur128=peak=true", "-f", "null", "-",
    ])
    summary = loudness_result.stderr.decode(errors="replace").rsplit("Summary:", 1)[-1]
    loudness = re.search(r"I:\s*(-?[\d.]+)\s*LUFS", summary)
    true_peak = re.search(r"Peak:\s*(-?[\d.]+)\s*dBFS", summary)
    require(loudness is not None and true_peak is not None, f"{path.name}: no loudness measurement")
    values["integratedLUFS"] = float(loudness.group(1))
    values["truePeakDBFS"] = float(true_peak.group(1))
    require(-29 <= values["integratedLUFS"] <= -19, f"{path.name}: loudness outside quiet-bed range")
    require(values["truePeakDBFS"] <= -6, f"{path.name}: AAC true-peak overshoot")
    values["primingFrames"] = priming
    values["paddingFrames"] = 0
    values["bytes"] = path.stat().st_size
    return values


def expected_track(score, digest):
    return {
        "id": score.id,
        "mode": score.mode,
        "title": score.title,
        "description": score.description,
        "bpm": round(score.bpm, 6),
        "duration": score.duration,
        "file": f"music/{score.id}.m4a",
        "sha256": digest,
        "recommended": score.recommended,
        "license": LICENSE,
    }


def print_result(score, pcm, decoded):
    print(
        f"  {score.title}: {score.duration:.6f}s / {score.bpm:.6f} BPM; "
        f"{decoded['bytes'] / 1024:.0f} KiB; {decoded['integratedLUFS']:.1f} LUFS; "
        f"true peak {decoded['truePeakDBFS']:.1f} dBFS\n"
        f"    seam PCM {pcm['boundaryStep']:.7f}, AAC {decoded['boundaryStep']:.7f}; "
        f"decoded {decoded['frames']} frames; priming {decoded['primingFrames']}, padding 0",
        flush=True,
    )


def check(ffmpeg, ffprobe, render_pcm):
    require(CATALOG.exists(), "Music catalog missing; run generation first")
    text = CATALOG.read_text()
    require(text.startswith(PREFIX) and text.rstrip().endswith(";"), "Unexpected music catalog wrapper")
    catalog = json.loads(text[len(PREFIX):].strip().removesuffix(";"))
    require(catalog["schemaVersion"] == 1, "Unsupported catalog schema")
    require(catalog["render"]["sourceSha256"] == source_hashes(), "Music sources changed; regenerate the assets")
    require(len(catalog["tracks"]) == len(SCORES), "Expected exactly four catalog tracks")
    require({p.name for p in AUDITIONS.glob("*.m4a")} == {s.id + ".m4a" for s in SCORES},
            "Unexpected/missing audition M4A files")
    require({p.name for p in APP.iterdir() if p.is_file()} == {"classic.m4a", "gauntlet.m4a"},
            "App Music directory must contain only the two recommended M4A files")
    for score, entry in zip(SCORES, catalog["tracks"]):
        path = AUDITIONS / f"{score.id}.m4a"
        require(entry == expected_track(score, sha256(path)), f"{score.id}: catalog metadata/hash mismatch")
        audit = catalog["render"]["tracks"][score.id]
        require(audit["bars"] == BARS and audit["frames"] == score.frames, f"{score.id}: loop design changed")
        require(audit["pcm"]["frames"] == score.frames and audit["wrappedEvents"] >= 5, f"{score.id}: tails not carried")
        validate_metrics(audit["pcm"], f"{score.id} stored PCM")
        if render_pcm:
            print(f"Recomposing {score.title} for PCM verification…", flush=True)
            left, right, events = render(score)
            raw = interleave(left, right)
            values = metrics(left, right)
            validate_metrics(values, f"{score.id} regenerated PCM")
            require(hashlib.sha256(raw).hexdigest() == audit["pcmSha256"], f"{score.id}: PCM hash changed")
            require(events["wrappedEvents"] == audit["wrappedEvents"], f"{score.id}: wrap count changed")
        decoded = inspect_audio(ffmpeg, ffprobe, path, score)
        if score.recommended:
            require(sha256(APP / f"{score.mode}.m4a") == entry["sha256"], f"{score.mode}: app copy differs from recommendation")
        print_result(score, audit["pcm"], decoded)
    print("Music check passed: four circular cues, two matching app defaults, exact decoded durations.", flush=True)


def generate(ffmpeg, ffprobe):
    # This process-specific directory never borrows an OS temporary directory.
    work = SCRATCH / str(os.getpid())
    work.mkdir(parents=True, exist_ok=False)
    AUDITIONS.mkdir(parents=True, exist_ok=True)
    APP.mkdir(parents=True, exist_ok=True)
    catalog = {
        "schemaVersion": 1,
        "tracks": [],
        "render": {
            "sourceSha256": source_hashes(),
            "sampleRate": SR,
            "channels": 2,
            "codec": "AAC-LC",
            "bitrate": 192000,
            "aacAccessUnitFrames": AAC_FRAME,
            "encoder": run([ffmpeg, "-version"]).stdout.decode().splitlines()[0],
            "loopMethod": "periodic wrap-add; two-period room warm-up; middle-of-three AAC encode with edit-list pre-roll",
            "tracks": {},
        },
    }
    try:
        for score in SCORES:
            print(f"Composing {score.title}…", flush=True)
            left, right, events = render(score)
            pcm_values = metrics(left, right)
            validate_metrics(pcm_values, f"{score.id} pre-encode PCM")
            raw = interleave(left, right)
            pcm_digest = hashlib.sha256(raw).hexdigest()
            del left, right
            staged = work / f"{score.id}.m4a"
            encode(ffmpeg, raw, score, staged, work)
            del raw
            decoded = inspect_audio(ffmpeg, ffprobe, staged, score)
            destination = AUDITIONS / staged.name
            staged.replace(destination)
            digest = sha256(destination)
            if score.recommended:
                shutil.copyfile(destination, APP / f"{score.mode}.m4a")
            catalog["tracks"].append(expected_track(score, digest))
            catalog["render"]["tracks"][score.id] = {
                "bars": BARS, "frames": score.frames, "nominalBPM": score.tempo,
                **events, "pcmSha256": pcm_digest, "pcm": pcm_values, "decoded": decoded,
            }
            print_result(score, pcm_values, decoded)
        staged_catalog = work / "music-catalog.js"
        staged_catalog.write_text(PREFIX + json.dumps(catalog, indent=2, ensure_ascii=False) + ";\n")
        staged_catalog.replace(CATALOG)
    finally:
        shutil.rmtree(work)
        if SCRATCH.exists() and not any(SCRATCH.iterdir()):
            SCRATCH.rmdir()
    print("Generated four auditions and only classic.m4a / gauntlet.m4a for app bundling.", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--check", action="store_true", help="validate all outputs without changing any assets")
    parser.add_argument("--render-pcm", action="store_true", help="with --check, recompose and verify pre-encode PCM hashes/seams")
    args = parser.parse_args()
    if args.render_pcm and not args.check:
        parser.error("--render-pcm requires --check")
    ffmpeg, ffprobe = shutil.which("ffmpeg"), shutil.which("ffprobe")
    if not ffmpeg or not ffprobe:
        parser.error("ffmpeg and ffprobe must already be installed; this generator never installs or downloads tools")
    validate_scores()
    try:
        if args.check:
            check(ffmpeg, ffprobe, args.render_pcm)
        else:
            generate(ffmpeg, ffprobe)
    except (OSError, ValueError, RuntimeError, KeyError, AssertionError) as error:
        print(f"Music generation/check failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
