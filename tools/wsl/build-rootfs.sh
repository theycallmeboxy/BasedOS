#!/bin/sh
# Build BasedOS's two root images. Runs in WSL (needs real symlinks, python3, mksquashfs).
# Usage: build-rootfs.sh <repo> <work dir> <busybox.static> <busybox.list>
#   <work>/stock-root must hold the unpacked stock SYSTEM (tools/wsl/unpack-stock.sh).
#
# The root is two read-only layers, stacked by the initrd with overlayfs (docs/plan.md):
#   vendor    only what manifest/harvest.list takes from stock (and the libraries those need).
#             Built from your own device's firmware, never published. Named by a hash of its
#             contents (VENDOR_ID), so the same stock build always gives the same id.
#   system    everything of BasedOS's own, on top: BusyBox, the overlay, SDL2, librga, wpa_cli,
#             the boot tools, identity files, and BasedOS's edits of stock files as whole copies.
#             It names the vendor layer it was built against (usr/share/basedos/needs-vendor);
#             a .bosupd carries this one alone.
# Outputs in <work>: vendor-<id>.squashfs, rootfs.squashfs (the system layer; the slot files
# keep their names), and rootfs/ (the two merged, for the checks and tools that want one tree).
set -eu
REPO=$1 W=$2 BB=$3 BBLIST=$4
VEN=$W/vendor SYS=$W/system OUT=$W/rootfs
VERSION=$(cat "$REPO/VERSION")
BUILD=$(git -C "$REPO" describe --always --dirty 2>/dev/null || echo unknown)
case $BUILD in *dirty) BUILD="$BUILD-$(date -u +%Y%m%d%H%M)" ;; esac

rm -rf "$VEN" "$SYS" "$OUT" "$W"/vendor-*.squashfs "$W/rootfs.squashfs"
mkdir -p "$VEN" "$SYS"
chmod 755 "$VEN" "$SYS"

echo "--- vendor: harvest"
python3 "$REPO/tools/harvest.py" "$W/stock-root" "$REPO/manifest/harvest.list" "$VEN"
# ROCKNIX's PipeWire defaults: BasedOS runs no PipeWire. Left out of the vendor layer rather
# than hidden by whiteouts in the system one.
rm -f "$VEN/usr/share/alsa/alsa.conf.d/50-pipewire.conf" "$VEN/usr/share/alsa/alsa.conf.d/99-pipewire-default.conf"
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
ln -s SDCARD mnt/sdcard

# BasedOS's edits of stock files, as whole files in its own layer.
# ROCKNIX's alsa.conf loads /storage/.config/asound.conf instead of ~/.asoundrc. BasedOS runs no
# PipeWire, and frontends (spruce's asound-setup.sh) write ~/.asoundrc, so put upstream
# alsa-lib's behaviour back.
grep -q '"/storage/.config/asound.conf"' "$VEN/usr/share/alsa/alsa.conf" ||
	{ echo "alsa.conf no longer has the ROCKNIX hook line; check it" >&2; exit 1; }
mkdir -p usr/share/alsa
sed 's#"/storage/.config/asound.conf"#"~/.asoundrc"#' "$VEN/usr/share/alsa/alsa.conf" > usr/share/alsa/alsa.conf

echo "--- system: sdl2"
# BasedOS's own SDL2 and librga (tools/sdl2/build.sh), over stock's SDL2.
S=$REPO/prepared/sdl2
SDL=$(cd "$S" && ls libSDL2-2.0.so.0.*.*) RGA=$(cd "$S" && ls librga.so.*.*.*)
install -m 755 "$S/$SDL" "$S/$RGA" usr/lib/
ln -sf "$SDL" usr/lib/libSDL2-2.0.so.0
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

echo "--- system: wpa_cli"
# The frontend's Wi-Fi tool (tools/wpa_cli/build.sh); stock has wpa_supplicant without it.
install -m 755 "$REPO/prepared/wpa_cli/wpa_cli" usr/bin/wpa_cli
install -D -m 644 "$REPO/prepared/wpa_cli/COPYING" usr/share/licenses/wpa_cli/COPYING

echo "--- system: busybox"
# Links only where neither layer has the file: a stock tool beats BusyBox's applet, and
# BasedOS's own (the overlay) beats both.
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
chmod 755 etc/init.d/* usr/sbin/poweroff usr/sbin/mount-frontend usr/sbin/frontend-session usr/sbin/basedos-suspend usr/sbin/basedos-update usr/share/udhcpc/default.script
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
