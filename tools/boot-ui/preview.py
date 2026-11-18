#!/usr/bin/env python3
"""A basedos-splash preview (BASEDOS_SPLASH_PREVIEW raw XRGB8888, 1440x1600, the panel's native
layout) as a PNG, no image libraries:  preview.py <raw> <out.png>
Turn it the way the 350H Ultra is held with tools/dev/rotate-shot.py, as for real screenshots."""
import struct
import sys
import zlib

W, H = 1440, 1600
raw = open(sys.argv[1], "rb").read()
rows = b"".join(b"\0" + bytes(b for i in range(y * W * 4, (y + 1) * W * 4, 4)
                              for b in (raw[i + 2], raw[i + 1], raw[i])) for y in range(H))


def chunk(t, d):
    return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d))


png = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", W, H, 8, 2, 0, 0, 0))
       + chunk(b"IDAT", zlib.compress(rows, 6)) + chunk(b"IEND", b""))
open(sys.argv[2], "wb").write(png)
