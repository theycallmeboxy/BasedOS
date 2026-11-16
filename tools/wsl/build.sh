#!/bin/sh
# Full v0 rootfs build in WSL from the repo on /mnt/e.
set -eu
REPO=/mnt/e/projects/spruceOS-gkd350hultra/basedos
W=$HOME/basedos-work
cp "$REPO/prepared/rocknix-20260613-c8ed06c/BUILD" "$W/STOCK_BUILD"
sh "$REPO/tools/wsl/build-rootfs.sh" "$REPO" "$W" "$REPO/prepared/alpine/busybox.static" "$REPO/prepared/alpine/busybox.list"
mkdir -p "$REPO/out"
cp "$W/rootfs.squashfs" "$REPO/out/rootfs.squashfs"
cp "$W/harvest-report.txt" "$REPO/out/harvest-report.txt" 2>/dev/null || true
