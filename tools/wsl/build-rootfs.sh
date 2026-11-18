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

# ROCKNIX's alsa.conf loads /storage/.config/asound.conf instead of ~/.asoundrc, and its
# alsa.conf.d makes PipeWire the default PCM. BasedOS runs no PipeWire, and frontends (spruce's
# asound-setup.sh) write ~/.asoundrc, so put upstream alsa-lib's behaviour back.
grep -q '"/storage/.config/asound.conf"' usr/share/alsa/alsa.conf ||
	{ echo "alsa.conf no longer has the ROCKNIX hook line; check it" >&2; exit 1; }
sed -i 's#"/storage/.config/asound.conf"#"~/.asoundrc"#' usr/share/alsa/alsa.conf
rm -f usr/share/alsa/alsa.conf.d/50-pipewire.conf usr/share/alsa/alsa.conf.d/99-pipewire-default.conf

echo "--- sdl2"
# BasedOS's own SDL2 and librga (tools/sdl2/build.sh), in place of stock's SDL2.
S=$REPO/prepared/sdl2
SDL=$(cd "$S" && ls libSDL2-2.0.so.0.*.*) RGA=$(cd "$S" && ls librga.so.*.*.*)
install -m 755 "$S/$SDL" "$S/$RGA" usr/lib/
ln -sf "$SDL" usr/lib/libSDL2-2.0.so.0
ln -sf "$RGA" usr/lib/librga.so.1
python3 - "$REPO/tools" "$OUT/usr/lib" "$SDL" "$RGA" <<'EOF'
import os, sys
sys.path.insert(0, sys.argv[1])
from harvest import elf_needed
lib = sys.argv[2]
missing = [n for f in sys.argv[3:] for n in elf_needed(os.path.join(lib, f)) if not os.path.exists(os.path.join(lib, n))]
if missing:
    sys.exit("sdl2: missing " + " ".join(sorted(set(missing))))
EOF
grep -h '^sha256\|  lib' "$S/libSDL2.build-info" | head -3

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
chmod 755 etc/init.d/* usr/sbin/mount-frontend usr/sbin/frontend-session usr/sbin/basedos-shutdown-keys usr/sbin/basedos-suspend usr/share/udhcpc/default.script
# Accounts are on /data (rcS seeds them from these defaults), so a frontend can add users.
chmod 644 usr/share/basedos/accounts/passwd usr/share/basedos/accounts/group
chmod 600 usr/share/basedos/accounts/shadow
for f in passwd group shadow; do ln -sf /data/etc/$f etc/$f; done
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
