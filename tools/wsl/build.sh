#!/bin/sh
# Full rootfs build (vendor and system layers) in WSL from the repo on /mnt/e.
set -eu
REPO=/mnt/e/projects/spruceOS-gkd350hultra/basedos
W=$HOME/basedos-work
cp "$REPO/prepared/rocknix-20260613-c8ed06c/BUILD" "$W/STOCK_BUILD"
[ -f "$REPO/prepared/sdl2/libSDL2.build-info" ] ||
	bash "$REPO/tools/sdl2/build.sh" "$REPO/prepared/rocknix-20260613-c8ed06c/SYSTEM" "$REPO/prepared/sdl2" 270
[ -f "$REPO/prepared/wpa_cli/build-info" ] ||
	bash "$REPO/tools/wpa_cli/build.sh" "$REPO/prepared/wpa_cli"
sh "$REPO/tools/wsl/build-rootfs.sh" "$REPO" "$W" "$REPO/prepared/alpine/busybox.static" "$REPO/prepared/alpine/busybox.list"
mkdir -p "$REPO/out"
cp "$W/rootfs.squashfs" "$REPO/out/rootfs.squashfs"
# The vendor layer stays local: built from your own stock, never published (NOTICE.md).
rm -f "$REPO"/out/vendor-*.squashfs
cp "$W"/vendor-*.squashfs "$REPO/out/"
# The update payload: the system layer and the initrd, nothing of stock's (publishable).
python3 "$REPO/tools/mkboot.py" initrd "$REPO/prepared/alpine/busybox.static" "$W/initrd.uimg.new" >/dev/null
mv "$W/initrd.uimg.new" "$REPO/out/initrd.uimg"
# The boot script (not in the payload: install-dev.sh and update-basedos.sh put it on p1).
rm -f "$W/boot.scr.new"
python3 "$REPO/tools/mkboot.py" bootscr "$REPO/prepared/rocknix-20260613-c8ed06c/boot.scr" "$W/boot.scr.new" >/dev/null
mv "$W/boot.scr.new" "$REPO/out/boot.scr"
rm -f "$REPO"/out/baseos-*.bosupd
python3 "$REPO/tools/mkupdate.py" "$W/rootfs.squashfs" "$REPO/out/initrd.uimg" 	"$(sed -n 's/^BASEOS_VENDOR=//p' "$W/system/etc/baseos-release")" "$(cat "$REPO/VERSION")" 	"$(sed -n 's/^BASEOS_BUILD=//p' "$W/system/etc/baseos-release")" "$REPO/out"
cp "$W/harvest-report.txt" "$REPO/out/harvest-report.txt" 2>/dev/null || true
