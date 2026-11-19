#!/usr/bin/env python3
"""Which libraries do a frontend's binaries need that neither BasedOS nor the card provides?

  needs-check.py <basedos rootfs dir> <card root> [<stock root>]

Scans the card's 64-bit ELF files under the paths spruce runs on BasedOS (flip/bin, flip/lib,
App/PyUI/dll, bin64), resolves every DT_NEEDED against the card's own library dirs and the
rootfs's /usr/lib, and lists what is missing, and whether the stock rootfs has it (so it can be
added to manifest/harvest.list).
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from harvest import elf_needed  # noqa: E402

# RetroArch and the standalone emulators too: spruce's ra64.universal links libudev.so.1, which a
# check of the spruce/ folders alone missed (2026-11-19).
CARD_BIN = ["spruce/flip/bin", "spruce/bin64", "RetroArch", "Emu"]
CARD_LIB = ["spruce/flip/lib", "App/PyUI/dll"]


def main():
    rootfs, card = sys.argv[1], sys.argv[2]
    stock = sys.argv[3] if len(sys.argv) > 3 else None
    have = set()
    for d in [os.path.join(rootfs, "usr/lib")] + [os.path.join(card, d) for d in CARD_LIB]:
        if os.path.isdir(d):
            have.update(os.listdir(d))
    missing = {}
    for d in CARD_BIN + CARD_LIB:
        top = os.path.join(card, d)
        for root, _dirs, files in os.walk(top):
            for f in files:
                p = os.path.join(root, f)
                if os.path.islink(p):
                    continue
                for lib in elf_needed(p) or []:
                    if lib not in have:
                        missing.setdefault(lib, []).append(os.path.relpath(p, card))
    for lib in sorted(missing):
        users = missing[lib]
        where = ""
        if stock:
            where = "stock has it" if os.path.lexists(os.path.join(stock, "usr/lib", lib)) else "NOT in stock"
        print(f"{lib:32} {where:14} needed by {len(users)}: {', '.join(users[:3])}{' ...' if len(users) > 3 else ''}")
    print(f"{len(missing)} missing")


if __name__ == "__main__":
    main()
