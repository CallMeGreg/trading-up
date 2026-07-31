#!/usr/bin/env python3
"""Minimal, dependency-free PNG reader.

Only handles what this repo's generated assets and simulator screenshots
actually are: non-interlaced, 8-bit-per-channel, colour type 2 (RGB) or 6
(RGBA). That's enough to check the App Store submission rules without pulling
in Pillow.
"""
import struct
import zlib

CHANNELS = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}


class PNG:
    def __init__(self, path):
        self.path = path
        with open(path, "rb") as fh:
            data = fh.read()
        if data[:8] != b"\x89PNG\r\n\x1a\n":
            raise ValueError(f"{path}: not a PNG")

        self.width, self.height = struct.unpack(">II", data[16:24])
        self.bit_depth = data[24]
        self.color_type = data[25]
        self.interlace = data[28]
        self._idat = b""
        self.chunks = []

        offset = 8
        while offset < len(data):
            (length,) = struct.unpack(">I", data[offset:offset + 4])
            kind = data[offset + 4:offset + 8].decode("latin1")
            body = data[offset + 8:offset + 8 + length]
            self.chunks.append(kind)
            if kind == "IDAT":
                self._idat += body
            offset += 12 + length

        self._rows = None

    @property
    def has_alpha(self):
        return self.color_type in (4, 6) or "tRNS" in self.chunks

    def pixel(self, x, y):
        """(r, g, b) at x, y."""
        row = self._decoded()[y]
        n = CHANNELS[self.color_type]
        base = x * n
        return tuple(row[base:base + 3])

    def _decoded(self):
        if self._rows is not None:
            return self._rows
        if self.bit_depth != 8 or self.color_type not in (2, 6) or self.interlace:
            raise ValueError(f"{self.path}: unsupported PNG variant for pixel reads")

        n = CHANNELS[self.color_type]
        stride = self.width * n
        raw = zlib.decompress(self._idat)
        rows, previous = [], bytearray(stride)
        pos = 0
        for _ in range(self.height):
            filter_type = raw[pos]
            line = bytearray(raw[pos + 1:pos + 1 + stride])
            pos += 1 + stride
            for i in range(stride):
                left = line[i - n] if i >= n else 0
                up = previous[i]
                up_left = previous[i - n] if i >= n else 0
                if filter_type == 1:
                    line[i] = (line[i] + left) & 0xFF
                elif filter_type == 2:
                    line[i] = (line[i] + up) & 0xFF
                elif filter_type == 3:
                    line[i] = (line[i] + (left + up) // 2) & 0xFF
                elif filter_type == 4:
                    p = left + up - up_left
                    pa, pb, pc = abs(p - left), abs(p - up), abs(p - up_left)
                    best = left if (pa <= pb and pa <= pc) else (up if pb <= pc else up_left)
                    line[i] = (line[i] + best) & 0xFF
            rows.append(line)
            previous = line
        self._rows = rows
        return rows
