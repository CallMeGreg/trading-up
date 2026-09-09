#!/usr/bin/env python3
"""Prepare the small CC0 foley selection from a locally downloaded Kenney ZIP.

This is a one-time source-preparation tool, not part of normal regeneration.
It requires an existing FFmpeg executable. It does not download or install
anything, and never extracts arbitrary archive paths.
"""

import argparse
import hashlib
import io
import json
import re
import shutil
import subprocess
import sys
import tempfile
import wave
import zipfile
from array import array
from pathlib import Path
from urllib.parse import urlparse


ROOT = Path(__file__).resolve().parent.parent
LAB = ROOT / "docs" / "sound-lab"
SELECTION = {
    "card": ("card-place-1", "card-place-2", "card-place-3"),
    "slide": ("card-slide-1", "card-slide-2", "card-slide-3"),
    "fan": ("card-fan-1", "card-fan-2"),
    "chip": ("chips-collide-1", "chips-collide-2", "chips-collide-3"),
    "stack": ("chips-stack-1", "chips-stack-2", "chips-stack-3"),
    "wrapper": ("cards-pack-open-1", "cards-pack-open-2"),
    "draw": ("cards-pack-take-out-1", "cards-pack-take-out-2"),
}


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def trim_pcm(data):
    with wave.open(io.BytesIO(data), "rb") as source:
        if (source.getnchannels(), source.getsampwidth(), source.getframerate()) != (1, 2, 48000):
            raise ValueError("FFmpeg did not produce the expected 48 kHz / 16-bit / mono PCM")
        pcm = array("h")
        pcm.frombytes(source.readframes(source.getnframes()))
    if sys.byteorder != "little":
        pcm.byteswap()
    peak = max(map(abs, pcm), default=0)
    if peak < 100:
        raise ValueError("Unexpectedly silent source recording")
    threshold = max(40, peak * 0.006)
    active = [i for i, value in enumerate(pcm) if abs(value) >= threshold]
    first = max(0, active[0] - 144)
    last = min(len(pcm), active[-1] + 481)
    trimmed = pcm[first:last]
    if sys.byteorder != "little":
        trimmed.byteswap()
    destination = io.BytesIO()
    with wave.open(destination, "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(48000)
        output.writeframes(trimmed.tobytes())
    return destination.getvalue(), first, len(pcm) - last


def prepare(archive_path, expected_sha, download_url):
    if not re.fullmatch(r"[a-fA-F0-9]{64}", expected_sha):
        raise ValueError("Supply the audited archive's complete SHA-256 digest")
    parsed = urlparse(download_url)
    if parsed.scheme != "https" or not parsed.netloc:
        raise ValueError("Record the exact HTTPS download URL linked by the official source")
    archive_data = archive_path.read_bytes()
    if sha256(archive_data) != expected_sha.lower():
        raise ValueError("Archive SHA-256 mismatch; no sources were written")
    ffmpeg = shutil.which("ffmpeg")
    if not ffmpeg:
        raise RuntimeError("FFmpeg is required for source preparation only. Use the included PCM sources for normal generation.")
    version = subprocess.run([ffmpeg, "-version"], check=True, capture_output=True, text=True).stdout.splitlines()[0]
    files = []
    prepared = {}
    with zipfile.ZipFile(io.BytesIO(archive_data)) as archive, tempfile.TemporaryDirectory(prefix="tu-sound-source-") as directory:
        names = archive.namelist()
        licenses = [name for name in names if Path(name).name.lower() == "license.txt"]
        if len(licenses) != 1:
            raise ValueError("Expected exactly one supplied License.txt in the source archive")
        license_data = archive.read(licenses[0])
        license_text = license_data.decode("utf-8-sig")
        if "creativecommons.org/publicdomain/zero/1.0" not in license_text or "Kenney" not in license_text:
            raise ValueError("Source license is not the expected Kenney CC0 dedication")
        for group, stems in SELECTION.items():
            for stem in stems:
                matches = [name for name in names if Path(name).stem == stem and Path(name).suffix.lower() in (".ogg", ".wav")]
                if len(matches) != 1:
                    raise ValueError(f"Expected one recording named {stem}, found {matches}")
                member = matches[0]
                if archive.getinfo(member).file_size > 8 * 1024 * 1024:
                    raise ValueError(f"Unexpectedly large source recording: {member}")
                raw = archive.read(member)
                source_path = Path(directory) / ("input" + Path(member).suffix)
                output_path = Path(directory) / "converted.wav"
                source_path.write_bytes(raw)
                subprocess.run([
                    ffmpeg, "-hide_banner", "-loglevel", "error", "-nostdin", "-y",
                    "-i", str(source_path), "-ac", "1", "-ar", "48000",
                    "-c:a", "pcm_s16le", str(output_path),
                ], check=True)
                data, trim_start, trim_end = trim_pcm(output_path.read_bytes())
                relative = f"sources/audio/{stem}.wav"
                prepared[relative] = data
                files.append({
                    "group": group,
                    "file": relative,
                    "sourceMember": member,
                    "sourceSha256": sha256(raw),
                    "sha256": sha256(data),
                    "trimmedStartFramesAt48000Hz": trim_start,
                    "trimmedEndFramesAt48000Hz": trim_end,
                })
    license_file = "licenses/kenney-casino-audio.txt"
    provenance = {
        "schemaVersion": 1,
        "author": "Kenney",
        "pack": "Casino Audio",
        "sourcePage": "https://kenney.nl/assets/casino-audio",
        "downloadURL": download_url,
        "archiveSha256": expected_sha.lower(),
        "license": "CC0-1.0",
        "licenseURL": "https://creativecommons.org/publicdomain/zero/1.0/legalcode",
        "licenseFile": license_file,
        "licenseSha256": sha256(license_data),
        "modifications": "Selected recordings converted to 48 kHz 16-bit mono PCM; leading/trailing silence trimmed with 3 ms / 10 ms margins. No source normalization.",
        "preparationTool": version,
        "files": files,
    }
    # Validate/convert the whole selection before replacing any committed source.
    for relative, data in prepared.items():
        destination = LAB / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(data)
    license_path = LAB / license_file
    license_path.parent.mkdir(parents=True, exist_ok=True)
    license_path.write_bytes(license_data)
    (LAB / "sources" / "provenance.json").write_text(json.dumps(provenance, indent=2) + "\n")
    print(f"Prepared {len(files)} CC0 source recordings, the original license and provenance.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive", type=Path, help="The original Casino Audio ZIP downloaded from Kenney")
    parser.add_argument("--archive-sha256", required=True, help="SHA-256 of the audited download")
    parser.add_argument("--download-url", required=True, help="Exact official download URL, recorded for provenance")
    args = parser.parse_args()
    prepare(args.archive, args.archive_sha256, args.download_url)


if __name__ == "__main__":
    main()
