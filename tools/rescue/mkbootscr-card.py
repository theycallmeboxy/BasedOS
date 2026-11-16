#!/usr/bin/env python3
"""Make an SD-card boot.scr from the GKD's own stock boot.scr.

  mkbootscr-card.py <stock boot.scr> <out boot.scr>

Stock's script loads Image and the DTB from `mmc 0:1` (the eMMC in U-Boot's
numbering). The card's copy loads them from `mmc 1:1` (the SD slot) and is
otherwise unchanged. The legacy image wrapper is rebuilt in exactly stock's
layout (64-byte header, then the script length and 0xffffffff) because that
is what this U-Boot is known to accept.
"""
import struct
import sys
import zlib

MAGIC = 0x27051956


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    b = open(sys.argv[1], "rb").read()
    (magic, hcrc, tstamp, size, load, ep, dcrc, os_, arch, typ, comp, name) = \
        struct.unpack(">7I4B32s", b[:64])
    if magic != MAGIC or typ != 6 or comp != 0:
        sys.exit("not an uncompressed legacy script image")
    data = b[64:64 + size]
    if zlib.crc32(data) != dcrc:
        sys.exit("stock script data CRC mismatch")
    slen, term = struct.unpack(">II", data[:8])
    if term != 0xFFFFFFFF or 8 + slen != size:
        sys.exit("unexpected script layout; refusing to guess")
    script = data[8:]
    if script.count(b"load mmc 0:1 ") != 4 or b"mmc 1:" in script:
        sys.exit("stock script isn't the expected 20260613 one (4 loads from mmc 0:1)")
    script = (b"# GKD 350H Ultra rescue card: same as stock, but loads from the SD slot (mmc 1)\n"
              + script.replace(b"load mmc 0:1 ", b"load mmc 1:1 "))
    data = struct.pack(">II", len(script), 0xFFFFFFFF) + script
    hdr = bytearray(struct.pack(">7I4B32s", MAGIC, 0, tstamp, len(data), load, ep,
                                zlib.crc32(data), os_, arch, typ, comp, name))
    hdr[4:8] = struct.pack(">I", zlib.crc32(hdr))
    with open(sys.argv[2], "xb") as f:
        f.write(bytes(hdr) + data)
    print(f"{sys.argv[2]}: {len(script)} byte script, loads from mmc 1:1")


if __name__ == "__main__":
    main()
