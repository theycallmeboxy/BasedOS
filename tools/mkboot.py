#!/usr/bin/env python3
"""Make BasedOS's boot files from the device's own stock boot.scr.

  mkboot.py initrd <busybox.static> <out initrd.uimg>
  mkboot.py bootscr <stock boot.scr> <out boot.scr>

initrd: a gzip cpio (newc) holding /basedos/init and /basedos/busybox, wrapped
as a legacy U-Boot ramdisk image. The kernel unpacks it over its built-in
initramfs; rdinit=/basedos/init runs ours and leaves stock's /init intact.

bootscr: stock's script (loads Image and the DTB from mmc 0:1, picks the DTB by
hdmi_detect) plus: rdinit=/basedos/init on every bootargs, the initrd loaded
from p1, and booti with it. Same legacy wrapper layout as stock's.
"""
import gzip
import io
import os
import struct
import sys
import time
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
MAGIC = 0x27051956


def uimage(data, typ, os_=5, arch=22, name=b""):
    hdr = bytearray(struct.pack(">7I4B32s", MAGIC, 0, int(time.time()), len(data), 0, 0,
                                zlib.crc32(data), os_, arch, typ, 0, name))
    hdr[4:8] = struct.pack(">I", zlib.crc32(hdr))
    return bytes(hdr) + data


def cpio_newc(entries):
    out = io.BytesIO()
    ino = 1
    for name, mode, data in entries + [("TRAILER!!!", 0, b"")]:
        nb = name.encode() + b"\0"
        hdr = b"070701" + b"".join(b"%08X" % v for v in (
            ino, mode, 0, 0, 1, int(time.time()), len(data), 0, 0, 0, 0, len(nb), 0))
        out.write(hdr + nb + b"\0" * (-(110 + len(nb)) % 4) + data + b"\0" * (-len(data) % 4))
        ino += 1
    return out.getvalue()


def initrd(busybox, out):
    init = open(os.path.join(HERE, "..", "initrd", "basedos", "init"), "rb").read().replace(b"\r\n", b"\n")
    bb = open(busybox, "rb").read()
    cpio = cpio_newc([("basedos", 0o40755, b""), ("basedos/init", 0o100755, init),
                      ("basedos/busybox", 0o100755, bb)])
    gz = gzip.compress(cpio, 9, mtime=0)
    with open(out, "xb") as f:
        f.write(uimage(gz, typ=3, name=b"BasedOS initrd"))  # IH_TYPE_RAMDISK, uncompressed wrapper
    print(f"{out}: cpio {len(cpio)} B, gzip {len(gz)} B")


def bootscr(stock, out):
    b = open(stock, "rb").read()
    size = struct.unpack_from(">I", b, 12)[0]
    data = b[64:64 + size]
    slen, term = struct.unpack_from(">II", data)
    if term != 0xFFFFFFFF:
        sys.exit("unexpected stock boot.scr layout")
    s = data[8:8 + slen].decode()
    if s.count('setenv bootargs "') != 2 or s.count("booti ${kernel_addr_r} - ${fdt_addr_r}") != 1:
        sys.exit("stock boot.scr isn't the expected 20260613 one")
    s = s.replace('net.iframes=0"', 'net.iframes=0 rdinit=/basedos/init"')
    s = s.replace("booti ${kernel_addr_r} - ${fdt_addr_r}",
                  "load mmc 0:1 ${ramdisk_addr_r} basedos/initrd.uimg\n"
                  "booti ${kernel_addr_r} ${ramdisk_addr_r} ${fdt_addr_r}")
    s = "# BasedOS: stock's boot script plus the BasedOS initrd (rdinit=/basedos/init)\n" + s
    body = s.encode()
    data = struct.pack(">II", len(body), 0xFFFFFFFF) + body
    with open(out, "xb") as f:
        f.write(uimage(data, typ=6, arch=b[29]))
    print(f"{out}: {len(body)} byte script")


def main():
    if len(sys.argv) == 4 and sys.argv[1] == "initrd":
        initrd(sys.argv[2], sys.argv[3])
    elif len(sys.argv) == 4 and sys.argv[1] == "bootscr":
        bootscr(sys.argv[2], sys.argv[3])
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
