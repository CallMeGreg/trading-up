#!/usr/bin/env python3
"""Pick an available iPhone simulator name for `xcodebuild test`.

Reads `xcrun simctl list devices available iOS -j` from stdin and prints the
name of the first available iPhone simulator it finds. Runner images change
their pre-installed simulators over time, so we look this up at run time
instead of hardcoding a device name (e.g. "iPhone 16") that could disappear.
"""
import json
import sys


def main() -> int:
    data = json.load(sys.stdin)
    for devices in data["devices"].values():
        for device in devices:
            if device.get("isAvailable", True) and device["name"].startswith("iPhone"):
                print(device["name"])
                return 0
    return 1


if __name__ == "__main__":
    sys.exit(main())
