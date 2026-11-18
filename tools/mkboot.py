#!/usr/bin/env python3
"""Make BasedOS's boot files from the device's own stock boot.scr.

  mkboot.py initrd <busybox.static> <out initrd.uimg>
  mkboot.py bootscr <stock boot.scr> <out boot.scr>
  mkboot.py dtb <stock rk3576-gkd-atom.dtb> <out rk3576-gkd-atom.dtb>

initrd: a gzip cpio (newc) holding /basedos/init and /basedos/busybox, wrapped
as a legacy U-Boot ramdisk image. The kernel unpacks it over its built-in
initramfs; rdinit=/basedos/init runs ours and leaves stock's /init intact.

bootscr: stock's script (loads Image and the DTB from mmc 0:1, picks the DTB by
hdmi_detect) plus: rdinit=/basedos/init on every bootargs, the initrd loaded
from p1, BasedOS's panel DTB (basedos/rk3576-gkd-atom.dtb) ahead of stock's,
and booti with it. Same legacy wrapper layout as stock's.

dtb: stock's built-in-panel DTB with the panel at 60 Hz instead of 59.11 Hz
(PANEL_60HZ below). Two 32-bit values change in place; nothing else.
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
    # Stock's loglevel=7 undoes "quiet": every boot message goes to the serial console and the
    # framebuffer console as it is printed. Warnings and worse still do.
    if s.count("loglevel=7") != 2:
        sys.exit("stock boot.scr isn't the expected one (loglevel=7 twice)")
    s = s.replace("loglevel=7", "loglevel=4")
    # The built-in panel's DTB: BasedOS's own (mkboot.py dtb, 60 Hz) when it's on p1, else stock's.
    # The HDMI and USB-DP DTBs have no panel and stay stock's. Stock's file is never touched, so
    # install-dev.sh revert still boots stock with stock's DTB.
    panel = "load mmc 0:1 ${fdt_addr_r} rk3576-gkd-atom.dtb\n"
    if s.count(panel) != 1:
        sys.exit("stock boot.scr doesn't load rk3576-gkd-atom.dtb once")
    s = s.replace(panel,
                  "if load mmc 0:1 ${fdt_addr_r} basedos/rk3576-gkd-atom.dtb; then\n"
                  "setenv basedos_fdt 1\n"
                  "else\n" + panel + "fi\n")
    # Stock picks bootargs and the DTB; then BasedOS adds its initrd. booti only returns when it
    # fails (e.g. the ramdisk's CRC), and load fails when the file is missing: either way, put
    # stock's bootargs back and boot stock's kernel without the initrd, so a bad or missing
    # initrd can never leave the eMMC unbootable. (This U-Boot has no iminfo to check first.)
    s = s.replace("booti ${kernel_addr_r} - ${fdt_addr_r}",
                  "setenv stock_bootargs \"${bootargs}\"\n"
                  "setenv bootargs \"${bootargs} rdinit=/basedos/init\"\n"
                  "if load mmc 0:1 ${ramdisk_addr_r} basedos/initrd.uimg; then\n"
                  "booti ${kernel_addr_r} ${ramdisk_addr_r} ${fdt_addr_r}\n"
                  "fi\n"
                  "echo \"BasedOS initrd missing or rejected: booting stock\"\n"
                  "setenv bootargs \"${stock_bootargs}\"\n"
                  "if test \"${basedos_fdt}\" = \"1\"; then\n"
                  "load mmc 0:1 ${fdt_addr_r} rk3576-gkd-atom.dtb\n"
                  "fi\n"
                  "booti ${kernel_addr_r} - ${fdt_addr_r}")
    if s.count("rdinit=/basedos/init") != 1 or s.count("booti ") != 2:
        sys.exit("boot.scr rewrite didn't land as expected")
    s = "# BasedOS: stock's boot script plus the BasedOS initrd (rdinit=/basedos/init), stock fallback\n" + s
    body = s.encode()
    data = struct.pack(">II", len(body), 0xFFFFFFFF) + body
    with open(out, "xb") as f:
        f.write(uimage(data, typ=6, arch=b[29]))
    print(f"{out}: {len(body)} byte script")


PANEL_TIMING = "/dsi@27d80000/panel@0/display-timings/timing0"
# The panel's mode asks for 172.26 MHz, which the VOP can't make: dclk_vp0 comes from GPLL
# (1188 MHz) by an integer divider, so it gets 1188/7 = 169.714 MHz and the panel ran at 59.11 Hz.
# The clock asked is now one the divider makes (in whole kHz, rounded up: the kernel rounds the
# mode to kHz and the clock framework then picks the closest rate at or below it, so 169714 kHz
# would land on 1188/8 = 148.5 MHz). The horizontal front porch shrinks so that the line takes
# as long as the panel's own mode says it should (1740 clocks at 172.26 MHz = 1714 at 169.714):
# 169.714 MHz / (1714 x 1650) = 60.01 Hz.
PANEL_60HZ = {"clock-frequency": (172260000, 169715000), "hfront-porch": (150, 124)}


def fdt_props(blob, path):
    """Offsets of the 4-byte cell values of every property of the node at path, by name."""
    magic, _, off_struct, off_strings = struct.unpack_from(">4I", blob)
    if magic != 0xD00DFEED:
        sys.exit("not a flattened device tree")
    want = [p for p in path.split("/") if p]
    stack, props, pos = [], {}, off_struct
    while True:
        tok = struct.unpack_from(">I", blob, pos)[0]
        pos += 4
        if tok == 1:  # FDT_BEGIN_NODE
            end = blob.index(b"\0", pos)
            stack.append(blob[pos:end].decode())
            pos = (end + 4) & ~3
        elif tok == 2:  # FDT_END_NODE
            stack.pop()
        elif tok == 3:  # FDT_PROP
            ln, nameoff = struct.unpack_from(">II", blob, pos)
            pos += 8
            if stack[1:] == want:
                name = blob[off_strings + nameoff:blob.index(b"\0", off_strings + nameoff)].decode()
                props[name] = (pos, ln)
            pos = (pos + ln + 3) & ~3
        elif tok == 4:  # FDT_NOP
            pass
        elif tok == 9:  # FDT_END
            return props
        else:
            sys.exit("bad FDT token %d" % tok)


def dtb(stock, out):
    b = bytearray(open(stock, "rb").read())
    props = fdt_props(b, PANEL_TIMING)
    for name, (old, new) in PANEL_60HZ.items():
        if name not in props or props[name][1] != 4:
            sys.exit(f"{PANEL_TIMING} has no 32-bit {name}")
        have = struct.unpack_from(">I", b, props[name][0])[0]
        if have != old:
            sys.exit(f"{name} is {have}, not stock's {old}: not the expected stock DTB")
        struct.pack_into(">I", b, props[name][0], new)
    with open(out, "xb") as f:
        f.write(b)
    print(f"{out}: panel at 60.01 Hz (" + ", ".join(f"{k} {o} -> {n}" for k, (o, n) in PANEL_60HZ.items()) + ")")


def main():
    if len(sys.argv) == 4 and sys.argv[1] == "initrd":
        initrd(sys.argv[2], sys.argv[3])
    elif len(sys.argv) == 4 and sys.argv[1] == "bootscr":
        bootscr(sys.argv[2], sys.argv[3])
    elif len(sys.argv) == 4 and sys.argv[1] == "dtb":
        dtb(sys.argv[2], sys.argv[3])
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
