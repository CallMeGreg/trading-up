#!/usr/bin/env python3
"""Publish the explicitly approved Studio soundboard renders into the app.

Render source changes first with tools/generate_sound_lab.py. Approval pins the
exact audio hashes; regeneration never silently approves a changed sound.

    python3 tools/generate_sfx.py --list
    python3 tools/generate_sfx.py
    python3 tools/generate_sfx.py --check
    python3 tools/generate_sfx.py --approve-studio  # only after explicit approval
"""

import argparse
import json
from pathlib import Path

from generate_sound_lab import LAB, ROOT, digest, read_manifest


DESTINATION = ROOT / "TradingUp" / "Audio" / "SFX"
APPROVAL = LAB / "studio-approval.json"
NAMES = {"pack_purchase": "purchase", "foil": "foil_shimmer", "sell_card": "coin"}


def approved_files():
    manifest = read_manifest()
    approval = json.loads(APPROVAL.read_text())
    if approval.get("schemaVersion") != 1 or approval.get("direction") != "studio":
        raise ValueError("Expected an explicit Studio approval")
    cues = manifest["cues"]
    if set(approval["sounds"]) != {cue["id"] for cue in cues}:
        raise ValueError("The action catalogue changed and requires review")
    files = {}
    for cue in cues:
        takes = cue["audio"]["studio"]
        if approval["sounds"][cue["id"]] != [take["sha256"] for take in takes]:
            raise ValueError(f"Studio audio changed for {cue['id']}; audition and obtain approval before publishing")
        base = NAMES.get(cue["id"], cue["id"])
        for index, take in enumerate(takes):
            name = base if index == 0 else f"{base}_{index + 1:02d}"
            source = LAB / take["file"]
            data = source.read_bytes()
            if digest(data) != take["sha256"]:
                raise ValueError(f"Candidate was edited outside its generator: {source}")
            files[name + ".wav"] = data
    return files


def approve_studio():
    manifest = read_manifest()
    approval = {
        "schemaVersion": 1,
        "direction": "studio",
        "decision": "Project owner selected Studio for every SFX on 2026-09-09.",
        "sounds": {cue["id"]: [take["sha256"] for take in cue["audio"]["studio"]]
                   for cue in manifest["cues"]},
    }
    APPROVAL.write_text(json.dumps(approval, indent=2) + "\n")
    print(f"Pinned the explicitly requested Studio selection for {len(approval['sounds'])} actions.")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--list", action="store_true")
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--approve-studio", action="store_true")
    args = parser.parse_args()
    if args.approve_studio:
        approve_studio()
        return
    files = approved_files()
    if args.list:
        print("\n".join(files))
        return
    if args.check:
        if {path.name for path in DESTINATION.glob("*.wav")} != set(files):
            raise ValueError("Missing or unexpected shipping sound files")
        for name, data in files.items():
            if (DESTINATION / name).read_bytes() != data:
                raise ValueError(f"Shipping sound does not match its Studio approval: {name}")
        print(f"PASS: all {len(files)} shipping WAVs exactly match the approved Studio takes.")
        return
    DESTINATION.mkdir(parents=True, exist_ok=True)
    for name, data in files.items():
        (DESTINATION / name).write_bytes(data)
    print(f"Published {len(files)} approved Studio WAVs for {len(read_manifest()['cues'])} actions.")


if __name__ == "__main__":
    main()
