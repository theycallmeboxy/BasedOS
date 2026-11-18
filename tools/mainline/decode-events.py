#!/usr/bin/env python3
"""Mainline experiment: what the probe's button recording saw.

  decode-events.py <card>/mainline/logs/<n>

For each eventN.bin (raw struct input_event, 24 bytes on arm64), prints the device name from
input-devices.txt and every key press and the range of every axis.
"""
import os
import re
import struct
import sys

EV_KEY, EV_ABS = 1, 3
NAMES = {0x130: "BTN_SOUTH", 0x131: "BTN_EAST", 0x133: "BTN_NORTH", 0x134: "BTN_WEST",
         0x136: "BTN_TL", 0x137: "BTN_TR", 0x138: "BTN_TL2", 0x139: "BTN_TR2",
         0x13a: "BTN_SELECT", 0x13b: "BTN_START", 0x13c: "BTN_MODE", 0x13d: "BTN_THUMBL",
         0x13e: "BTN_THUMBR", 0x220: "BTN_DPAD_UP", 0x221: "BTN_DPAD_DOWN",
         0x222: "BTN_DPAD_LEFT", 0x223: "BTN_DPAD_RIGHT", 114: "KEY_VOLUMEDOWN",
         115: "KEY_VOLUMEUP", 116: "KEY_POWER"}


def names(log):
    out = {}
    try:
        text = open(os.path.join(log, "input-devices.txt")).read()
    except OSError:
        return out
    for block in text.split("\n\n"):
        n = re.search(r'N: Name="([^"]*)"', block)
        h = re.search(r"H: Handlers=.*?\b(event\d+)", block)
        if n and h:
            out[h.group(1)] = n.group(1)
    return out


def main():
    log = sys.argv[1]
    dev = names(log)
    for f in sorted(os.listdir(log)):
        m = re.match(r"(event\d+)\.bin$", f)
        if not m:
            continue
        data = open(os.path.join(log, f), "rb").read()
        keys, axes = [], {}
        for off in range(0, len(data) - 23, 24):
            _, _, typ, code, val = struct.unpack_from("<qqHHi", data, off)
            if typ == EV_KEY and val == 1:
                keys.append(NAMES.get(code, hex(code)))
            elif typ == EV_ABS:
                lo, hi = axes.get(code, (val, val))
                axes[code] = (min(lo, val), max(hi, val))
        print(f"{m.group(1)} ({dev.get(m.group(1), '?')}): {len(data) // 24} events")
        if keys:
            print("  pressed: " + " ".join(dict.fromkeys(keys)))
        for code, (lo, hi) in sorted(axes.items()):
            print(f"  axis {code}: {lo} .. {hi}")


if __name__ == "__main__":
    main()
