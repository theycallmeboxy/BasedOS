#!/usr/bin/env python3
"""md5 of byte regions of a disk image, to compare against the device.

  region-md5.py <image> <name>:<start_sector>:<sectors> [...]

Matching device command for each region:
  dd if=/dev/mmcblk0 bs=512 skip=<start> count=<sectors> | md5sum
(or md5sum /dev/mmcblk0pN for a whole partition, which is much faster).
"""
import hashlib
import sys


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    with open(sys.argv[1], "rb") as f:
        for spec in sys.argv[2:]:
            name, start, count = spec.split(":")
            f.seek(int(start) * 512)
            left = int(count) * 512
            h = hashlib.md5()
            while left:
                buf = f.read(min(left, 8 << 20))
                if not buf:
                    sys.exit(f"{name}: image ends early")
                h.update(buf)
                left -= len(buf)
            print(f"{h.hexdigest()}  {name}", flush=True)


if __name__ == "__main__":
    main()
