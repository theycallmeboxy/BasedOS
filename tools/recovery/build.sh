#!/bin/sh
# The recovery card's boot files (tools/build.sh runs this; basedos-setup puts them on the card):
#
#   build.sh <repo> <work dir> <busybox.static> <out dir>
#
#   <out>/recovery-initrd.uimg   /recovery/init (tools/recovery/init), BusyBox, a static zstd
#                                decompressor, the boot screen and keys, and their licences
#   <out>/recovery.scr           the card's boot.scr (tools/recovery/boot.cmd)
#
# All of it is BasedOS's own or open source built here; nothing of stock's (the card gets stock's
# kernel and device trees from the device itself, when it's made). zstd is built from the
# release tarball Buildroot keeps in ~/basedos-br-dl, checked against upstream's published hash.
set -eu
REPO=$1 W=$2 BB=$3 OUT=$4
ZV=1.5.7
ZSHA=eb33e51f49a15e023950cd7825ca74a4a2b43db8354825ac24fc1b7ee09e6fa3
ZTAR=${BR2_DL_DIR:-$HOME/basedos-br-dl}/zstd/zstd-$ZV.tar.gz

echo "--- recovery card: zstd $ZV (static, decompressor)"
[ -f "$ZTAR" ] || { echo "no $ZTAR (tools/buildroot/build.sh sources downloads it)" >&2; exit 1; }
echo "$ZSHA  $ZTAR" | sha256sum -c --quiet
ZS=$W/recovery-src/zstd-$ZV
if [ ! -x "$ZS/programs/zstd-decompress" ]; then
	rm -rf "$W/recovery-src"; mkdir -p "$W/recovery-src"
	tar xzf "$ZTAR" -C "$W/recovery-src"
	make -s -C "$ZS/programs" -j"$(nproc)" zstd-decompress CC=aarch64-linux-gnu-gcc LDFLAGS=-static >/dev/null
fi

D=$W/recovery-initrd
rm -rf "$D"; mkdir -p "$D/licenses"
cp "$REPO/tools/recovery/init" "$D/init"
cp "$BB" "$D/busybox"
cp "$ZS/programs/zstd-decompress" "$D/zstd"
aarch64-linux-gnu-strip "$D/zstd"
aarch64-linux-gnu-gcc -O2 -static -Wall -o "$D/basedos-splash" "$REPO/tools/boot-ui/basedos-splash.c"
aarch64-linux-gnu-gcc -O2 -static -Wall -o "$D/basedos-keys" "$REPO/tools/boot-ui/basedos-keys.c"
aarch64-linux-gnu-strip "$D/basedos-splash" "$D/basedos-keys"
cp "$ZS/LICENSE" "$D/licenses/zstd-LICENSE"
cp "$REPO/tools/boot-ui/OFL-Terminus.txt" "$D/licenses/OFL-Terminus.txt"
file "$D/zstd" "$D/basedos-splash" "$D/basedos-keys" | grep -v 'statically linked' && { echo "not static" >&2; exit 1; }

rm -f "$OUT/recovery-initrd.uimg" "$OUT/recovery.scr"
python3 "$REPO/tools/mkboot.py" recovery-initrd "$D" "$OUT/recovery-initrd.uimg"
python3 "$REPO/tools/mkboot.py" script "$REPO/tools/recovery/boot.cmd" "$OUT/recovery.scr"
