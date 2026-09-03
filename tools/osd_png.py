#!/usr/bin/env python3
"""Turn the OSD text bitmaps that menu_test writes (128x64 of '#'/'.')
into PNGs, scaled up, so a screen can be looked at.  No PIL: a PNG is
zlib and a few struct.packs.

  osd_png.py build/menu/*.txt        -> the same names with .png
"""
import struct, sys, zlib

SCALE = 3
FG = (230, 230, 230)
BG = (20, 40, 90)

def png(path, rows):
    h = len(rows) * SCALE
    w = len(rows[0]) * SCALE
    raw = bytearray()
    for r in rows:
        line = bytearray(b"\x00")
        for c in r:
            line += bytes(FG if c == "#" else BG) * SCALE
        raw += line * SCALE
    def chunk(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
    out = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
    out += chunk(b"IDAT", zlib.compress(bytes(raw), 9)) + chunk(b"IEND", b"")
    open(path, "wb").write(out)

for f in sys.argv[1:]:
    rows = [l.rstrip("\n") for l in open(f) if l.strip()]
    png(f[:-4] + ".png", rows)
