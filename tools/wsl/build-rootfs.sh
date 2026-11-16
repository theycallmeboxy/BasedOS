#!/bin/sh
# Build the BasedOS rootfs squashfs. Runs in WSL (needs real symlinks, python3,
# mksquashfs). Usage: build-rootfs.sh <repo> <work dir> <busybox.static> <busybox.list>
#   <work>/stock-root must hold the unpacked stock SYSTEM (tools/wsl/unpack-stock.sh).
# Order matters: harvest first, then BusyBox links only where nothing harvested
# sits, then the BasedOS overlay on top, then the generated identity files.
set -eu
REPO=$1 W=$2 BB=$3 BBLIST=$4
OUT=$W/rootfs
VERSION=$(cat "$REPO/VERSION")
BUILD=$(git -C "$REPO" describe --always --dirty 2>/dev/null || echo unknown)
case $BUILD in *dirty) BUILD="$BUILD-$(date -u +%Y%m%d%H%M)" ;; esac

rm -rf "$OUT" "$W/rootfs.squashfs"
mkdir -p "$OUT"
cd "$OUT"
mkdir -p usr/bin usr/sbin usr/lib etc dev proc sys run tmp var data boot root mnt/SDCARD
ln -s usr/bin bin
ln -s usr/sbin sbin
ln -s usr/lib lib
ln -s SDCARD mnt/sdcard

echo "--- harvest"
python3 "$REPO/tools/harvest.py" "$W/stock-root" "$REPO/manifest/harvest.list" "$OUT"
mv "$W/harvest-report.txt" "$W/harvest-report.txt" 2>/dev/null || true

echo "--- busybox"
install -m 755 "$BB" usr/bin/busybox
n=0
while read -r p; do
	p=${p#/}
	case $p in bin/*|sbin/*) p=usr/$p ;; esac
	[ -e "$p" ] || [ -L "$p" ] && continue
	mkdir -p "$(dirname "$p")"
	ln -s /usr/bin/busybox "$p"
	n=$((n + 1))
done < "$BBLIST"
echo "$n busybox links"

echo "--- overlay"
cp -a "$REPO/overlay/." "$OUT/"
find "$OUT/etc" "$OUT/usr/lib/basedos" "$OUT/usr/share/udhcpc" -type f -exec chmod 644 {} +
chmod 755 etc/init.d/* usr/sbin/mount-frontend usr/sbin/frontend-session usr/share/udhcpc/default.script
chmod 600 etc/shadow
chmod 700 root
ln -sf /run/resolv.conf etc/resolv.conf
ln -sf /run/machine-id etc/machine-id

echo "--- identity"
cat > etc/baseos-release <<EOF
BASEOS=1
BASEOS_NAME=BasedOS
BASEOS_PLATFORM=rk3576
BASEOS_TARGET=gkd350hultra
BASEOS_DEVICE=gkd350hultra
BASEOS_MODEL="GKD 350H Ultra"
BASEOS_MODEL_STRING=GKD350HUltra
BASEOS_PANEL_ROTATION_CCW=270
BASEOS_WIFI=true
BASEOS_BLUETOOTH=false
BASEOS_VERSION=$VERSION
BASEOS_BUILD=$BUILD
BASEOS_STOCK=$(cat "$W/STOCK_BUILD" 2>/dev/null || echo unknown)
EOF
cat > etc/os-release <<EOF
ID=basedos
NAME="BasedOS"
VERSION_ID=$VERSION
PRETTY_NAME="BasedOS $VERSION (GKD 350H Ultra)"
EOF

echo "--- squashfs"
mksquashfs "$OUT" "$W/rootfs.squashfs" -noappend -all-root -comp zstd -Xcompression-level 15 -b 256K -quiet
ls -l "$W/rootfs.squashfs"
grep -E "^BASEOS_(VERSION|BUILD)=" etc/baseos-release
