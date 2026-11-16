#!/usr/bin/env python3
"""Swap the mmc0/mmc1 aliases in a GKD 350H Ultra device tree blob.

  dtb-swap-mmc.py <in.dtb> <out.dtb>

Stock aliases: mmc0 = /mmc@2a330000 (eMMC), mmc1 = /mmc@2a310000 (SD slot).
The kernel numbers mmcblk devices by these aliases, and stock's initramfs
mounts /dev/mmcblk0p1 and p2 by name. With the aliases swapped, a card booted
in the SD slot becomes mmcblk0 and the eMMC becomes mmcblk1, which stock's
automount ignores (it skips disks that have boot0, "might be Android").

Only the two property values in /aliases change (same length), so the blob's
layout and size are untouched. Refuses anything that doesn't look like stock.
"""
import struct
import sys

EMMC, SD = b"/mmc@2a330000", b"/mmc@2a310000"
FDT_BEGIN_NODE, FDT_END_NODE, FDT_PROP, FDT_NOP, FDT_END = 1, 2, 3, 4, 9


def alias_props(blob):
    magic, total, off_struct, off_strings = struct.unpack_from(">IIII", blob, 0)
    if magic != 0xD00DFEED or total != len(blob):
        sys.exit("not a device tree blob (or truncated)")
    found, path, pos = {}, [], off_struct
    while True:
        (tok,) = struct.unpack_from(">I", blob, pos)
        pos += 4
        if tok == FDT_BEGIN_NODE:
            end = blob.index(b"\0", pos)
            path.append(blob[pos:end].decode())
            pos = (end + 1 + 3) & ~3
        elif tok == FDT_END_NODE:
            path.pop()
        elif tok == FDT_PROP:
            length, nameoff = struct.unpack_from(">II", blob, pos)
            pos += 8
            name_end = blob.index(b"\0", off_strings + nameoff)
            name = blob[off_strings + nameoff:name_end].decode()
            if path == ["", "aliases"] and name in ("mmc0", "mmc1"):
                found[name] = (pos, length)
            pos = (pos + length + 3) & ~3
        elif tok == FDT_NOP:
            pass
        elif tok == FDT_END:
            return found
        else:
            sys.exit(f"bad FDT token {tok} at {pos - 4}")


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    blob = bytearray(open(sys.argv[1], "rb").read())
    props = alias_props(blob)
    want = {"mmc0": EMMC, "mmc1": SD}
    for name, value in want.items():
        if name not in props:
            sys.exit(f"/aliases/{name} not found")
        pos, length = props[name]
        if bytes(blob[pos:pos + length]) != value + b"\0":
            sys.exit(f"/aliases/{name} is {bytes(blob[pos:pos + length])!r}, expected stock {value!r}")
    for name, value in (("mmc0", SD), ("mmc1", EMMC)):
        pos, length = props[name]
        blob[pos:pos + length] = value + b"\0"
    check = alias_props(blob)
    assert bytes(blob[check["mmc0"][0]:][:14]) == SD + b"\0"
    assert bytes(blob[check["mmc1"][0]:][:14]) == EMMC + b"\0"
    with open(sys.argv[2], "xb") as f:
        f.write(blob)
    print(f"{sys.argv[2]}: mmc0 -> {SD.decode()} (SD), mmc1 -> {EMMC.decode()} (eMMC)")


if __name__ == "__main__":
    main()
