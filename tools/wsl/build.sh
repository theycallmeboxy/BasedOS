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
cp "$W/harvest-report.txt" "$REPO/out/harvest-report.txt" 2>/dev/null || true
