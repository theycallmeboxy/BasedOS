#!/usr/bin/env python3
"""Mainline experiment: the display pipeline's registers, for comparing the stock BSP kernel
(where the panel works) with the mainline one.

  regdump.py dump <out dir>          on the device (stock BSP kernel), as root: 32-bit reads
                                     from /dev/mem, one <name>.bin per block
  regdump.py diff <bsp dir> <mainline dir>
                                     on the PC: every 32-bit word that differs

The mainline probe (probe-init) dumps the same blocks with dd, into <log>/regs/.
"""
import mmap
import os
import struct
import sys

# name, base, length. Keep in step with REGS in probe-init.
BLOCKS = [
    ("dsi2", 0x27D80000, 0x400),        # DSI2 host
    ("dcphy", 0x2B020000, 0x4000),      # MIPI DC-PHY
    ("vop", 0x27D00000, 0x3000),        # VOP2 (VP0 drives the panel)
    ("vo0_grf", 0x2601A000, 0x100),     # the DSI's GRF
    ("dcphy_grf", 0x26034000, 0x100),   # the DC-PHY's GRF
]


def dump(out):
    os.makedirs(out, exist_ok=True)
    fd = os.open("/dev/mem", os.O_RDONLY | os.O_SYNC)
    for name, base, length in BLOCKS:
        page = base & ~(mmap.PAGESIZE - 1)
        m = mmap.mmap(fd, length + base - page, mmap.MAP_SHARED, mmap.PROT_READ, offset=page)
        words = memoryview(m)[base - page:base - page + length].cast("I")
        data = struct.pack(f"<{len(words)}I", *[words[i] for i in range(len(words))])
        words.release()
        m.close()
        with open(os.path.join(out, name + ".bin"), "wb") as f:
            f.write(data)
        print(f"{name}: {length:#x} bytes at {base:#x}")
    os.close(fd)


def diff(a, b):
    for name, base, length in BLOCKS:
        try:
            x = open(os.path.join(a, name + ".bin"), "rb").read()
            y = open(os.path.join(b, name + ".bin"), "rb").read()
        except OSError as e:
            print(f"{name}: {e}")
            continue
        n = min(len(x), len(y)) // 4
        rows = []
        for i in range(n):
            u, v = struct.unpack_from("<I", x, i * 4)[0], struct.unpack_from("<I", y, i * 4)[0]
            if u != v:
                rows.append(f"  {base + i * 4:#010x} (+{i * 4:#05x})  bsp {u:#010x}  mainline {v:#010x}")
        print(f"== {name}: {len(rows)} of {n} words differ")
        print("\n".join(rows))


if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[1] == "dump":
        dump(sys.argv[2])
    elif len(sys.argv) == 4 and sys.argv[1] == "diff":
        diff(sys.argv[2], sys.argv[3])
    else:
        sys.exit(__doc__)
