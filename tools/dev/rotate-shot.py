#!/usr/bin/env python3
"""Turn a native 1440x1600 drm-screenshot.py PNG the way the GKD is held (90 deg clockwise),
at half size, with no image libraries:  rotate-shot.py in.png out.png"""
import struct, sys, zlib
d = open(sys.argv[1], 'rb').read(); p = 8; idat = b''
while p < len(d):
    n, = struct.unpack('>I', d[p:p + 4]); t = d[p + 4:p + 8]
    if t == b'IHDR': w, h = struct.unpack('>II', d[p + 8:p + 16])
    if t == b'IDAT': idat += d[p + 8:p + 8 + n]
    p += 12 + n
raw = zlib.decompress(idat); stride = w * 3 + 1
rows = [raw[y * stride + 1:(y + 1) * stride] for y in range(h)]
out = [bytes(b''.join(rows[h - 1 - u][v * 3:v * 3 + 3] for u in range(0, h, 2))) for v in range(0, w, 2)]
W, H = len(out[0]) // 3, len(out)
def chunk(t, dd): return struct.pack('>I', len(dd)) + t + dd + struct.pack('>I', zlib.crc32(t + dd))
open(sys.argv[2], 'wb').write(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', W, H, 8, 2, 0, 0, 0))
    + chunk(b'IDAT', zlib.compress(b''.join(b'\0' + r for r in out))) + chunk(b'IEND', b''))
