#!/usr/bin/env python3
"""Mainline experiment: the files for a test SD card, in out/mainline/card/.

  mkcard.py

Copy the contents of out/mainline/card/ to the root of a FAT32 card (one partition). The
stock U-Boot runs a card's boot.scr ahead of the eMMC's (the rescue card relies on that), so
with the card in, the 350H Ultra boots the mainline kernel with the probe initrd
(tools/mainline/probe-init). The probe writes only to the card; it mounts the eMMC read-only
to run BasedOS's own wpa_supplicant and sshd (with brcmfmac and the stock Wi-Fi firmware). Without the card, or if any file is missing or rejected, it boots the eMMC as usual.

  boot.scr                          loads from mmc 1:1 (the SD slot)
  mainline/Image                    out/mainline/Image (tools/mainline/build.sh)
  mainline/rk3576-gkd-350h-ultra.dtb
  mainline/mali_kbase.ko            the Mali GPU driver (tools/mainline/build-mali.sh)
  mainline/probe.uimg               busybox, regdump, the Wi-Fi modules and probe-init: a plain
                                    cpio in a ramdisk wrapper
"""
import os
import shutil
import struct
import tarfile
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
from mkboot import cpio_newc, uimage  # noqa: E402

ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(ROOT, "out", "mainline")
CARD = os.path.join(OUT, "card")
DTB = "rk3576-gkd-350h-ultra.dtb"

# fbcon turned to read upright on the portrait panel; loglevel 7 so the panel shows the boot;
# panic=0 keeps a panic on the screen instead of ROCKNIX's reboot after 1 s.
BOOTARGS = ("console=ttyS0,1500000 console=tty0 earlycon fbcon=rotate:3 loglevel=7 "
            "ignore_loglevel consoleblank=0 panic=0 rdinit=/init")

SCRIPT = f"""# BasedOS mainline test card: ROCKNIX's mainline kernel with the probe initrd.
# Falls back to the eMMC's own boot.scr when a file is missing or booti returns, and boots
# the eMMC straight away when mainline/boot-emmc exists (tools/mainline/remote.sh stock).
setenv bootargs "{BOOTARGS}"
setenv mainline 1
if load mmc 1:1 ${{ramdisk_addr_r}} mainline/boot-emmc; then
echo "mainline test card: mainline/boot-emmc is set"
setenv mainline 0
fi
if test "${{mainline}}" = "1"; then
if load mmc 1:1 ${{kernel_addr_r}} mainline/Image; then
if load mmc 1:1 ${{fdt_addr_r}} mainline/{DTB}; then
if load mmc 1:1 ${{ramdisk_addr_r}} mainline/probe.uimg; then
booti ${{kernel_addr_r}} ${{ramdisk_addr_r}} ${{fdt_addr_r}}
fi
fi
fi
fi
echo "mainline test card: booting the eMMC instead"
load mmc 0:1 ${{scriptaddr}} boot.scr && source ${{scriptaddr}}
"""


def main():
    for f in ("Image", DTB):
        if not os.path.isfile(os.path.join(OUT, f)):
            sys.exit(f"missing {OUT}/{f}: run tools/mainline/build.sh first")
    shutil.rmtree(CARD, ignore_errors=True)
    os.makedirs(os.path.join(CARD, "mainline"))
    for f in ("Image", DTB):
        shutil.copy(os.path.join(OUT, f), os.path.join(CARD, "mainline", f))
    # The Mali GPU driver (tools/mainline/build-mali.sh), loaded by the probe from the card.
    if os.path.isfile(os.path.join(OUT, "mali_kbase.ko")):
        shutil.copy(os.path.join(OUT, "mali_kbase.ko"), os.path.join(CARD, "mainline", "mali_kbase.ko"))

    init = open(os.path.join(HERE, "probe-init"), "rb").read().replace(b"\r\n", b"\n")
    bb = open(os.path.join(ROOT, "prepared", "alpine", "busybox.static"), "rb").read()
    rd = open(os.path.join(OUT, "regdump"), "rb").read()  # tools/mainline/build.sh
    entries = [("bin", 0o40755, b""), ("bin/busybox", 0o100755, bb),
               ("bin/regdump", 0o100755, rd), ("init", 0o100755, init)]
    # brcmfmac and its modules.dep (tools/mainline/build.sh), at lib/modules/<release>/.
    with tarfile.open(os.path.join(OUT, "wifi-modules.tar")) as t:
        for m in t.getmembers():
            if m.isdir():
                entries.append((m.name, 0o40755, b""))
            elif m.isfile():
                entries.append((m.name, 0o100644, t.extractfile(m).read()))
    cpio = cpio_newc(entries)
    with open(os.path.join(CARD, "mainline", "probe.uimg"), "wb") as f:
        f.write(uimage(cpio, typ=3, name=b"BasedOS mainline probe"))  # IH_TYPE_RAMDISK

    script = SCRIPT.encode()
    data = struct.pack(">II", len(script), 0xFFFFFFFF) + script
    with open(os.path.join(CARD, "boot.scr"), "wb") as f:
        f.write(uimage(data, typ=6, name=b"BasedOS mainline test"))  # IH_TYPE_SCRIPT
    for d, _, fs in os.walk(CARD):
        for f in fs:
            p = os.path.join(d, f)
            print(f"{os.path.relpath(p, CARD):40} {os.path.getsize(p):>10}")


if __name__ == "__main__":
    main()
