#!/bin/sh
# Build BasedOS's two root images. Runs in WSL (needs real symlinks, python3, mksquashfs).
# Usage: build-rootfs.sh <repo> <work dir> <busybox.static> <busybox.list>
#   <work>/stock-root must hold the unpacked stock SYSTEM (tools/wsl/unpack-stock.sh), and
#   $BR_TARGET (default ~/basedos-br/out/target) BasedOS's own Buildroot root
#   (tools/buildroot/build.sh build).
#
# The root is two read-only layers, stacked by the initrd with overlayfs (docs/plan.md):
#   vendor    only what manifest/harvest.list takes from stock: the closed GPU drivers, the
#             firmware and the stock kernel's modules (docs/vendor-minimal.md). Built from your own
#             device's firmware, never published. Named by a hash of its contents (VENDOR_ID), so
#             the same stock build always gives the same id.
#   system    everything of BasedOS's own, on top: its userland from its Buildroot root
#             (manifest/base.list: glibc, OpenSSH, wpa_supplicant, ALSA, ...), BusyBox, the overlay,
#             SDL2, librga, bash, the boot tools and identity files.
#             It names the vendor layer it was built against (usr/share/basedos/needs-vendor);
#             a .bosupd carries this one alone.
# Outputs in <work>: vendor-<id>.squashfs, rootfs.squashfs (the system layer; the slot files
# keep their names), and rootfs/ (the two merged, for the checks and tools that want one tree).
set -eu
REPO=$1 W=$2 BB=$3 BBLIST=$4
VEN=$W/vendor SYS=$W/system OUT=$W/rootfs BASE=$W/base
BR_TARGET=${BR_TARGET:-$HOME/basedos-br/out/target}
VERSION=$(cat "$REPO/VERSION")
BUILD=$(git -C "$REPO" describe --always --dirty 2>/dev/null || echo unknown)
case $BUILD in *dirty) BUILD="$BUILD-$(date -u +%Y%m%d%H%M)" ;; esac

rm -rf "$VEN" "$SYS" "$OUT" "$BASE" "$W"/vendor-*.squashfs "$W/rootfs.squashfs"
mkdir -p "$VEN" "$SYS" "$BASE"
chmod 755 "$VEN" "$SYS"

echo "--- base: BasedOS's userland from its Buildroot root"
[ -d "$BR_TARGET/usr/lib" ] || { echo "no Buildroot root at $BR_TARGET (tools/buildroot/build.sh build)" >&2; exit 1; }
python3 "$REPO/tools/harvest.py" "$BR_TARGET" "$REPO/manifest/base.list" "$BASE" --report "$W/base-report.txt"

echo "--- vendor: harvest"
# The blobs' own libraries (libstdc++, libwayland, glibc) are BasedOS's: --provided.
python3 "$REPO/tools/harvest.py" "$W/stock-root" "$REPO/manifest/harvest.list" "$VEN" --provided "$BASE" 	--report "$W/harvest-report.txt"
mkdir -p "$VEN/usr/share/basedos"
VENDOR_ID=$(cd "$VEN" && find . \( -type f -o -type l \) | LC_ALL=C sort | while read -r f; do
	if [ -L "$f" ]; then echo "L $f $(readlink "$f")"; else echo "F $f $(sha256sum < "$f" | cut -c1-64) $(stat -c %a "$f")"; fi
done | sha256sum | cut -c1-12)
cat > "$VEN/usr/share/basedos/vendor-release" <<EOF
VENDOR_ID=$VENDOR_ID
STOCK_BUILD=$(cat "$W/STOCK_BUILD" 2>/dev/null || echo unknown)
EOF
echo "vendor $VENDOR_ID"

echo "--- system: skeleton"
cd "$SYS"
mkdir -p usr/bin usr/sbin usr/lib usr/share/basedos etc dev proc sys run tmp var data boot root mnt/SDCARD
ln -s usr/bin bin
ln -s usr/sbin sbin
ln -s usr/lib lib
# Buildroot's glibc (aarch64) searches /lib64 and /usr/lib64 by default, as its own root links
# them to lib; without them a program started without LD_LIBRARY_PATH (rcS's e2fsck) finds only
# what's in its RUNPATH.
ln -s usr/lib lib64
ln -s lib usr/lib64
ln -s SDCARD mnt/sdcard

echo "--- system: base"
cp -a "$BASE/." "$SYS/"
# Frontends (spruce's asound-setup.sh) write ~/.asoundrc, which upstream alsa-lib's alsa.conf
# loads (ROCKNIX's loaded /storage/.config/asound.conf instead, which BasedOS had to edit).
grep -q '~/.asoundrc' usr/share/alsa/alsa.conf ||
	{ echo "alsa.conf doesn't load ~/.asoundrc; check it" >&2; exit 1; }

echo "--- system: sdl2"
# BasedOS's own SDL2 and librga (tools/sdl2/build.sh). Buildroot's SDL2 came along as SDL2_image's
# dependency; it is replaced, not kept beside.
rm -f usr/lib/libSDL2-2.0.so.0.*
S=$REPO/prepared/sdl2
SDL=$(cd "$S" && ls libSDL2-2.0.so.0.*.*) RGA=$(cd "$S" && ls librga.so.*.*.*)
install -m 755 "$S/$SDL" "$S/$RGA" usr/lib/
ln -sf "$SDL" usr/lib/libSDL2-2.0.so.0
# The unversioned name too: pysdl2 (PortMaster's GUI) takes an exact libSDL2-2.0.so in any folder of
# its path before a versioned one, so without it PortMaster's own SDL2, which doesn't turn the
# panel, won over this one.
ln -sf libSDL2-2.0.so.0 usr/lib/libSDL2-2.0.so
ln -sf "$RGA" usr/lib/librga.so.1
python3 - "$REPO/tools" "$SYS/usr/lib" "$VEN/usr/lib" "$SDL" "$RGA" <<'EOF'
import os, sys
sys.path.insert(0, sys.argv[1])
from harvest import elf_needed
mine, vendor = sys.argv[2], sys.argv[3]
have = lambda n: os.path.exists(os.path.join(mine, n)) or os.path.lexists(os.path.join(vendor, n))
missing = [n for f in sys.argv[4:] for n in elf_needed(os.path.join(mine, f)) if not have(n)]
if missing:
    sys.exit("sdl2: missing " + " ".join(sorted(set(missing))))
EOF
grep -h '^sha256\|  lib' "$S/libSDL2.build-info" | head -3

echo "--- system: GL library names"
# The Mali package's unversioned names, as stock's /usr/lib/mali/ carries them beside each library:
# programs built against them (PortMaster's Weston, for one) ask for libGLESv2.so, not .so.2. The
# targets are the vendor layer's files.
for l in libEGL.so:libEGL.so.1 libGLESv1_CM.so:libGLESv1_CM.so.1 libGLESv2.so:libGLESv2.so.2 \
	libgbm.so:libgbm.so.1 libwayland-egl.so:libwayland-egl.so.1 libmali-hook.so:libmali-hook.so.1 \
	libmali-bifrost-g52-g24p0-wayland-gbm.so:libmali.so.1; do
	[ -e "$VEN/usr/lib/${l#*:}" ] || { echo "vendor layer has no ${l#*:}" >&2; exit 1; }
	ln -sf "${l#*:}" "usr/lib/${l%%:*}"
done

echo "--- system: bash"
# PortMaster and its ports run on bash (tools/bash/build.sh); stock has none. Linked against
# glibc only.
install -m 755 "$REPO/prepared/bash/bash" usr/bin/bash
install -D -m 644 "$REPO/prepared/bash/COPYING" usr/share/licenses/bash/COPYING

echo "--- system: busybox"
# Links only where neither layer has the file: a real tool (BasedOS's userland, or a vendor
# file) beats BusyBox's applet, and the overlay beats both.
install -m 755 "$BB" usr/bin/busybox
n=0
while read -r p; do
	p=${p#/}
	case $p in bin/*|sbin/*) p=usr/$p ;; esac
	{ [ -e "$p" ] || [ -L "$p" ] || [ -e "$VEN/$p" ] || [ -L "$VEN/$p" ] || [ -e "$REPO/overlay/$p" ]; } && continue
	mkdir -p "$(dirname "$p")"
	ln -s /usr/bin/busybox "$p"
	n=$((n + 1))
done < "$BBLIST"
echo "$n busybox links"

echo "--- system: overlay"
cp -a "$REPO/overlay/." "$SYS/"
find "$SYS" -name __pycache__ -prune -exec rm -rf {} +
# poweroff's wrapper (it notes which of the three was asked for) answers to all three names.
for a in reboot halt; do rm -f usr/sbin/$a; ln -s poweroff usr/sbin/$a; done
find "$SYS/etc" "$SYS/usr/lib/basedos" "$SYS/usr/share/udhcpc" "$SYS/usr/share/basedos" -type f -exec chmod 644 {} +
chmod 755 etc/init.d/* usr/sbin/poweroff usr/sbin/mount-frontend usr/sbin/frontend-session usr/sbin/basedos-suspend usr/sbin/basedos-update usr/sbin/basedos-udev usr/share/udhcpc/default.script
# Accounts are on /data (rcS seeds them from these defaults), so a frontend can add users.
chmod 644 usr/share/basedos/accounts/passwd usr/share/basedos/accounts/group
chmod 600 usr/share/basedos/accounts/shadow
for f in passwd group shadow; do ln -sf /data/etc/$f etc/$f; done
chmod 700 root

echo "--- system: boot screen and keys"
# BasedOS's own small static tools (tools/boot-ui); the boot screen's font comes from Terminus
# Font (OFL 1.1), whose notice and licence travel with it.
aarch64-linux-gnu-gcc -O2 -static -Wall -o usr/bin/basedos-splash "$REPO/tools/boot-ui/basedos-splash.c"
aarch64-linux-gnu-strip usr/bin/basedos-splash
# The boot keys' reader (every held key in one read).
aarch64-linux-gnu-gcc -O2 -static -Wall -o usr/bin/basedos-keys "$REPO/tools/boot-ui/basedos-keys.c"
aarch64-linux-gnu-strip usr/bin/basedos-keys
# Hold both volume keys 3 s: BasedOS's own clean shutdown (rcS starts it).
aarch64-linux-gnu-gcc -O2 -static -Wall -o usr/sbin/basedos-shutdown-keys "$REPO/tools/boot-ui/basedos-shutdown-keys.c"
aarch64-linux-gnu-strip usr/sbin/basedos-shutdown-keys
install -D -m 644 "$REPO/tools/boot-ui/OFL-Terminus.txt" usr/share/licenses/basedos-splash/OFL-Terminus.txt
ln -sf /run/resolv.conf etc/resolv.conf
ln -sf /run/machine-id etc/machine-id

echo "--- system: identity"
echo "$VENDOR_ID" > usr/share/basedos/needs-vendor
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
BASEOS_VENDOR=$VENDOR_ID
EOF
cat > etc/os-release <<EOF
ID=basedos
NAME="BasedOS"
VERSION_ID=$VERSION
PRETTY_NAME="BasedOS $VERSION (GKD 350H Ultra)"
EOF

echo "--- check: nothing of stock's in the system layer"
# The system layer is what gets published: no file in it may be a copy of a vendor file.
python3 - "$SYS" "$VEN" <<'EOF'
import hashlib, os, sys
sys_root, ven = sys.argv[1], sys.argv[2]
def digest(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()
vendor = set()
for root, _, files in os.walk(ven):
    for f in files:
        p = os.path.join(root, f)
        if os.path.isfile(p) and not os.path.islink(p) and os.path.getsize(p) > 0:
            vendor.add(digest(p))
bad = []
for root, _, files in os.walk(sys_root):
    for f in files:
        p = os.path.join(root, f)
        if os.path.isfile(p) and not os.path.islink(p) and os.path.getsize(p) > 0 and digest(p) in vendor:
            bad.append(os.path.relpath(p, sys_root))
if bad:
    sys.exit("system layer holds stock files: " + " ".join(bad))
print("ok")
EOF

echo "--- merged view"
# vendor, then system on top, as the initrd stacks them.
cp -a "$VEN" "$OUT"
cp -a "$SYS/." "$OUT/"

echo "--- squashfs"
mksquashfs "$VEN" "$W/vendor-$VENDOR_ID.squashfs" -noappend -all-root -comp zstd -Xcompression-level 15 -b 256K -quiet
mksquashfs "$SYS" "$W/rootfs.squashfs" -noappend -all-root -comp zstd -Xcompression-level 15 -b 256K -quiet
ls -l "$W/vendor-$VENDOR_ID.squashfs" "$W/rootfs.squashfs"
grep -E "^BASEOS_(VERSION|BUILD|VENDOR)=" "$SYS/etc/baseos-release"
