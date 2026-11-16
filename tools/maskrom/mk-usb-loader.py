#!/usr/bin/env python3
"""Build a Rockchip maskrom USB loader (the file `rkdeveloptool db` / RKDevTool
"Download Boot" sends) from rkbin's DDR init and usbplug blobs.

  mk-usb-loader.py <chip e.g. 3576> <ddr.bin> <usbplug.bin> <out.bin>
  mk-usb-loader.py --check <existing loader.bin>   rebuild its 471/472 part and compare

Layout follows Rockchip's own loaders for NEWIDB chips (checked against the
RK3568 MiniLoaderAll.bin that ships with RKDevTool): an "LDR " header, 471
entries "UsbHead" (an RKNS v2 header naming the DDR and usbplug images with
SHA-256 hashes) + DDR, a 472 entry with the usbplug, RC4 off, every blob
padded to 2 KiB, Rockchip CRC32 at the end.

It deliberately has NO flash-loader entries, so this file can only be
downloaded to RAM in maskrom; tools can't use it to write a loader to the eMMC.
"""
import datetime
import hashlib
import struct
import sys

BLK = 2048


def pad(b):
    return b + b"\0" * (-len(b) % BLK)


def rkcrc(data):
    tab = []
    for i in range(256):
        c = i << 24
        for _ in range(8):
            c = ((c << 1) ^ 0x04C10DB7) & 0xFFFFFFFF if c & 0x80000000 else (c << 1) & 0xFFFFFFFF
        tab.append(c)
    crc = 0
    for x in data:
        crc = ((crc << 8) & 0xFFFFFFFF) ^ tab[((crc >> 24) ^ x) & 0xFF]
    return crc


# [BOOT1_PARAM] WORD_n from rkbin's RKBOOT/<chip>MINIALL.ini; WORD_n lands at
# header offset 88 + 4*n (verified: RK3576's WORD_2=0x100 is byte 96-99 in
# boot_merger 1.38's output; RK3568's ini has none).
BOOT1_PARAM = {"3576": {2: 0x100}}


def usbhead(ddr, plug, chip=None):
    h = bytearray(BLK)
    struct.pack_into("<4s4sII", h, 0, b"RKNS", b"\0" * 4, (2 << 16) + 384, 1)  # 2 images, SHA-256
    for n, word in BOOT1_PARAM.get(chip, {}).items():
        struct.pack_into("<I", h, 88 + 4 * n, word)
    off = 4
    for i, img in enumerate((ddr, plug)):
        n = len(img) // 512
        struct.pack_into("<IIII", h, 120 + i * 88, (n << 16) + off, 0xFFFFFFFF, 0, i + 1)
        h[120 + i * 88 + 24:120 + i * 88 + 56] = hashlib.sha256(img).digest()
        off += n
    h[1536:1568] = hashlib.sha256(bytes(h[:1536])).digest()
    return bytes(h)


def entry(typ, name, off, size, delay):
    n = name.encode("utf-16le")[:40].ljust(40, b"\0")
    return struct.pack("<BI", 57, typ) + n + struct.pack("<III", off, size, delay)


def build(chip, ddr, plug, name_ddr, name_plug):
    ddr, plug = pad(ddr), pad(plug)
    head = usbhead(ddr, plug, chip)
    hdr_len, ent = 0x66, 57
    o471, o472 = hdr_len, hdr_len + 2 * ent
    data0 = o472 + ent
    blobs = [head, ddr, plug]
    offs = [data0, data0 + len(head), data0 + len(head) + len(ddr)]
    now = datetime.datetime.now()
    hdr = struct.pack("<IHII HBBBBB 4s BIB BIB BIB BB", 0x2052444C, hdr_len, 0x0101, 0x01000000,
                      now.year, now.month, now.day, now.hour, now.minute, now.second,
                      chip.encode()[::-1], 2, o471, ent, 1, o472, ent, 0, data0 + sum(map(len, blobs)), ent,
                      0, 1) + b"\0" * 57
    assert len(hdr) == hdr_len
    body = (hdr + entry(1, "UsbHead", offs[0], len(head), 1) + entry(1, name_ddr, offs[1], len(ddr), 1)
            + entry(2, name_plug, offs[2], len(plug), 0) + b"".join(blobs))
    return body + struct.pack("<I", rkcrc(body))


def check(path):
    b = open(path, "rb").read()
    o471 = struct.unpack_from("<I", b, 26)[0]
    o472 = struct.unpack_from("<I", b, 32)[0]
    def ent_data(o):
        off, size = struct.unpack_from("<II", b, o + 45)
        return b[off:off + size]
    head, ddr, plug = ent_data(o471), ent_data(o471 + 57), ent_data(o472)
    chip = b[21:25][::-1].decode()
    mine = usbhead(ddr, plug, chip)
    print("UsbHead rebuilt identically:", mine == head)
    print("file CRC ok:", rkcrc(b[:-4]) == struct.unpack("<I", b[-4:])[0])
    return mine == head


def main():
    if len(sys.argv) == 3 and sys.argv[1] == "--check":
        sys.exit(0 if check(sys.argv[2]) else 1)
    if len(sys.argv) != 5:
        sys.exit(__doc__)
    chip, ddr_p, plug_p, out = sys.argv[1:]
    ddr, plug = open(ddr_p, "rb").read(), open(plug_p, "rb").read()
    name = lambda p: p.replace("\\", "/").rsplit("/", 1)[-1][:20]
    blob = build(chip, ddr, plug, name(ddr_p), name(plug_p))
    with open(out, "xb") as f:
        f.write(blob)
    print(f"{out}: {len(blob)} bytes, RK{chip}, DDR {len(ddr)} B, usbplug {len(plug)} B, no flash entries")
    check(out)


if __name__ == "__main__":
    main()
