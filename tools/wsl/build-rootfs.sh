#!/bin/sh
# Build BasedOS's root image, the system layer. Runs in WSL (needs real symlinks, python3,
# mksquashfs).
# Usage: build-rootfs.sh <repo> <work dir> <busybox.static> <busybox.list>
#   <work>/stock-root must hold the unpacked stock SYSTEM (tools/wsl/unpack-stock.sh), and
#   $BR_TARGET (default ~/basedos-br/out/target) BasedOS's own Buildroot root
#   (tools/buildroot/build.sh build), and $BR32_TARGET (default ~/basedos-br/out-armhf/target)
#   its 32-bit one (build.sh --armhf build).
#
# BasedOS runs next to stock on the eMMC and uses stock's own files in place (docs/plan.md,
# Architecture): U-Boot loads stock's kernel and DTBs from stock's boot partition, and the initrd
# mounts stock's own SYSTEM read-only at /stock. What BasedOS takes from stock
# (manifest/harvest.list: the closed GPU drivers, the firmware, the kernel's modules) is a link in
# the system layer into /stock, never a copy, so nothing of stock's is ever in a BasedOS image.
# The system layer is pinned to the stock build those links were made against (its BUILD_ID, in
# usr/share/basedos/needs-stock); the initrd refuses any other stock.
#
#   system    everything of BasedOS's own: its userland from its Buildroot root
#             (manifest/base.list: glibc, OpenSSH, wpa_supplicant, ALSA, ...), BusyBox, the overlay,
#             SDL2, librga, bash, the boot tools and identity files, and the links into /stock.
#             A .bosupd carries it.
#   stock     what the links point at, harvested here only as a build-time view (<work>/vendor):
#             the checks below and the merged view use it; it never leaves the PC.
# Outputs in <work>: rootfs.squashfs (the system layer, as it is on the device), and
# rootfs/ (the system layer with stock's linked files in place, for the checks and tools that want
# one tree).
set -eu
set -eu
REPO=$1 W=$2 BB=$3 BBLIST=$4
VEN=$W/vendor SYS=$W/system OUT=$W/rootfs BASE=$W/base
BR_TARGET=${BR_TARGET:-$HOME/basedos-br/out/target}
BR32_TARGET=${BR32_TARGET:-$HOME/basedos-br/out-armhf/target}
VERSION=$(cat "$REPO/VERSION")
BUILD=$(git -C "$REPO" describe --always --dirty 2>/dev/null || echo unknown)
# --dirty sees only tracked files. Untracked or ignored files in what the build copies or builds
# from (the overlay, the initrds, the SDL2 patches...) go into the image too: they make it dirty
# as well, so a build with them can't carry a clean release name.
case $BUILD in
*-dirty) ;;
*) [ -n "$(git -C "$REPO" status --porcelain --ignored --untracked-files=all -- overlay initrd tools/recovery \
	tools/boot-ui tools/sdl2 tools/bash buildroot manifest 2>/dev/null | grep -v '__pycache__')" ] && BUILD="$BUILD-dirty" ;;
esac
case $BUILD in *dirty) BUILD="$BUILD-$(date -u +%Y%m%d%H%M)" ;; esac

rm -rf "$VEN" "$SYS" "$OUT" "$BASE" "$W"/vendor-* "$W/rootfs.squashfs"
mkdir -p "$VEN" "$SYS" "$BASE"
chmod 755 "$VEN" "$SYS"

echo "--- base: BasedOS's userland from its Buildroot root"
[ -d "$BR_TARGET/usr/lib" ] || { echo "no Buildroot root at $BR_TARGET (tools/buildroot/build.sh build)" >&2; exit 1; }
python3 "$REPO/tools/harvest.py" "$BR_TARGET" "$REPO/manifest/base.list" "$BASE" --report "$W/base-report.txt"

echo "--- base: the 32-bit libraries, from the 32-bit Buildroot root, into /usr/lib32"
# PortMaster's 32-bit ports (docs/lib32.md). That root has them in /usr/lib; they move to
# /usr/lib32, where its loader looks (buildroot/external.mk) and stock had them.
[ -d "$BR32_TARGET/usr/lib" ] || { echo "no 32-bit Buildroot root at $BR32_TARGET (tools/buildroot/build.sh --armhf build)" >&2; exit 1; }
rm -rf "$W/base32"
python3 "$REPO/tools/harvest.py" "$BR32_TARGET" "$REPO/manifest/base32.list" "$W/base32" --lib32 /usr/lib --report "$W/base32-report.txt"
stray=$(cd "$W/base32" && find . -mindepth 1 ! -path ./usr ! -path ./usr/lib ! -path './usr/lib/*')
[ -z "$stray" ] || { echo "base32 outside /usr/lib: $stray" >&2; exit 1; }
mkdir -p "$BASE/usr/lib32"
cp -a "$W/base32/usr/lib/." "$BASE/usr/lib32/"
# What stock's /usr/lib32 has and this doesn't (ports may load it): a note, not a failure.
python3 "$REPO/tools/lib32-gaps.py" "$W/stock-root" "$BASE" > "$W/lib32-gaps.txt" || true

echo "--- stock: what BasedOS uses of it"
# A build-time view only ($VEN): on the device these stay in stock's SYSTEM, linked from /stock.
# The blobs' own libraries (libstdc++, libwayland, glibc) are BasedOS's: --provided.
python3 "$REPO/tools/harvest.py" "$W/stock-root" "$REPO/manifest/harvest.list" "$VEN" --provided "$BASE" \
	--report "$W/harvest-report.txt" --sources "$W/stock-sources.txt"
# The stock build the links are made against: its BUILD_ID, the full commit (stock's
# /etc/os-release, which the initrd reads at /stock/etc/os-release on every boot).
STOCK_BUILD_ID=$(sed -n 's/^BUILD_ID="\{0,1\}\([0-9a-f]*\)"\{0,1\}$/\1/p' "$W/stock-root/etc/os-release")
[ ${#STOCK_BUILD_ID} -ge 7 ] || { echo "stock's /etc/os-release has no BUILD_ID" >&2; exit 1; }
STOCK_BUILD=$(cat "$W/STOCK_BUILD" 2>/dev/null || echo unknown)
echo "stock $STOCK_BUILD ($STOCK_BUILD_ID)"

echo "--- system: skeleton"
cd "$SYS"
# /stock: where the initrd mounts stock's SYSTEM, read-only.
mkdir -p usr/bin usr/sbin usr/lib usr/share/basedos etc dev proc sys run tmp var data boot root mnt/SDCARD stock
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
# And the development name, libSDL2.so: SoLoud's SDL2 back end (in Apotris, for one) doesn't link
# SDL but dlopens "SDL2.so", then "libSDL2.so". Without either it runs with no audio and its
# voice tables never made, and the game crashes on the first sound it stops (a game's start).
ln -sf libSDL2-2.0.so.0 usr/lib/libSDL2.so
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

echo "--- system: sdl2 (32-bit)"
# The same SDL2 and librga built for armhf (SDL2_ARCH=armhf tools/sdl2/build.sh), for 32-bit
# ports: without it they'd get no turned picture. Buildroot's 32-bit SDL2 is replaced the same way.
rm -f usr/lib32/libSDL2-2.0.so.0.*
S32=$REPO/prepared/sdl2-armhf
grep -q '^arch armhf$' "$S32/libSDL2.build-info" || { echo "$S32 is not an armhf SDL2 build" >&2; exit 1; }
SDL32=$(cd "$S32" && ls libSDL2-2.0.so.0.*.*) RGA32=$(cd "$S32" && ls librga.so.*.*.*)
install -m 755 "$S32/$SDL32" "$S32/$RGA32" usr/lib32/
ln -sf "$SDL32" usr/lib32/libSDL2-2.0.so.0
ln -sf libSDL2-2.0.so.0 usr/lib32/libSDL2-2.0.so
ln -sf libSDL2-2.0.so.0 usr/lib32/libSDL2.so
ln -sf "$RGA32" usr/lib32/librga.so.1
python3 - "$REPO/tools" "$SYS/usr/lib32" "$VEN/usr/lib32" "$SDL32" "$RGA32" <<'EOF'
import os, sys
sys.path.insert(0, sys.argv[1])
from harvest import elf_class, elf_needed
mine, vendor = sys.argv[2], sys.argv[3]
have = lambda n: os.path.exists(os.path.join(mine, n)) or os.path.lexists(os.path.join(vendor, n))
for f in sys.argv[4:]:
    if elf_class(os.path.join(mine, f)) != 32:
        sys.exit(f"sdl2 (32-bit): {f} is not 32-bit")
missing = [n for f in sys.argv[4:] for n in elf_needed(os.path.join(mine, f)) if not have(n)]
if missing:
    sys.exit("sdl2 (32-bit): missing " + " ".join(sorted(set(missing))))
EOF
# The loader where armhf programs ask for it (their PT_INTERP is /lib/ld-linux-armhf.so.3), as
# stock links it. PortMaster offers its 32-bit ports when it finds this or /usr/lib32.
ln -sf /usr/lib32/ld-linux-armhf.so.3 usr/lib/ld-linux-armhf.so.3

echo "--- system: GL library names"
# The Mali package's unversioned names, as stock's /usr/lib/mali/ carries them beside each library:
# programs built against them (PortMaster's Weston, for one) ask for libGLESv2.so, not .so.2. The
# targets are stock's files (links into /stock), 64-bit in /usr/lib and 32-bit in /usr/lib32.
for l in libEGL.so:libEGL.so.1 libGLESv1_CM.so:libGLESv1_CM.so.1 libGLESv2.so:libGLESv2.so.2 \
	libgbm.so:libgbm.so.1 libwayland-egl.so:libwayland-egl.so.1 libmali-hook.so:libmali-hook.so.1 \
	libmali-bifrost-g52-g24p0-wayland-gbm.so:libmali.so.1; do
	for d in usr/lib usr/lib32; do
		[ -e "$VEN/$d/${l#*:}" ] || { echo "stock's files have no $d/${l#*:}" >&2; exit 1; }
		ln -sf "${l#*:}" "$d/${l%%:*}"
	done
done

echo "--- system: bash"
# PortMaster and its ports run on bash (tools/bash/build.sh); stock has none. Linked against
# glibc only.
install -m 755 "$REPO/prepared/bash/bash" usr/bin/bash
install -D -m 644 "$REPO/prepared/bash/COPYING" usr/share/licenses/bash/COPYING

echo "--- system: busybox"
# Links only where neither BasedOS nor stock's linked files have it: a real tool (BasedOS's userland, or a stock
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
chmod 755 etc/init.d/* usr/sbin/poweroff usr/sbin/mount-frontend usr/sbin/frontend-session usr/sbin/basedos-suspend usr/sbin/basedos-update usr/sbin/basedos-udev usr/sbin/basedos-boot usr/sbin/basedos-menu usr/share/udhcpc/default.script
# Accounts are on /data (rcS seeds them from these defaults), so a frontend can add users.
chmod 644 usr/share/basedos/accounts/passwd usr/share/basedos/accounts/group
chmod 600 usr/share/basedos/accounts/shadow
for f in passwd group shadow; do ln -sf /data/etc/$f etc/$f; done
chmod 700 root

echo "--- system: links into /stock"
# Every file of the stock view becomes a link to its place in stock's SYSTEM, mounted at /stock
# (stock-sources.txt: its path there, links followed); stock's own links among them are kept as
# they are. BasedOS's own files win: a path the system layer already has is left alone, as the
# old overlay stacking did. usr/share/basedos/stock-links lists them for the device's checks.
python3 - "$SYS" "$VEN" "$W/stock-sources.txt" "$W/stock-root" <<'EOF'
import os, sys
sys_root, ven, sources, stock = sys.argv[1:]
src = {}
for line in open(sources, encoding="utf-8"):
    dst, s = line.rstrip("\n").split("\t")
    src[dst.lstrip("/")] = s.lstrip("/")
made, kept, mine = [], 0, 0
for root, dirs, files in os.walk(ven):
    for n in sorted(dirs + files):
        p = os.path.join(root, n)
        rel = os.path.relpath(p, ven)
        if os.path.isdir(p) and not os.path.islink(p):
            continue
        out = os.path.join(sys_root, rel)
        if os.path.lexists(out):
            mine += 1
            continue
        os.makedirs(os.path.dirname(out), exist_ok=True)
        if os.path.islink(p):
            os.symlink(os.readlink(p), out)
            kept += 1
        else:
            if rel not in src:
                sys.exit(f"links: no stock source for {rel}")
            if not os.path.isfile(os.path.join(stock, src[rel])):
                sys.exit(f"links: stock has no {src[rel]}")
            os.symlink("/stock/" + src[rel], out)
            made.append(f"{rel} /stock/{src[rel]}")
with open(os.path.join(sys_root, "usr/share/basedos/stock-links"), "w", encoding="utf-8") as f:
    f.write("".join(l + "\n" for l in made))
print(f"{len(made)} links into /stock, {kept} of stock's own links, {mine} paths BasedOS has itself")
EOF

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
# The stock build this system layer's links are made against (the initrd checks stock's).
echo "$STOCK_BUILD_ID" > usr/share/basedos/needs-stock
# The known stock builds' boot.scr hashes (manifest/stock-builds.txt): basedos-boot checks the
# saved stock script against them before it puts it back.
awk '$2 == "boot.scr" && length($1) == 64 { print $1 }' "$REPO/manifest/stock-builds.txt" > usr/share/basedos/stock-boot-scr.sha256
[ -s usr/share/basedos/stock-boot-scr.sha256 ] || { echo "no stock boot.scr hashes in manifest/stock-builds.txt" >&2; exit 1; }
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
BASEOS_STOCK=$STOCK_BUILD
BASEOS_STOCK_BUILD_ID=$STOCK_BUILD_ID
EOF
# What the device and setup read as text: no carriage returns (a Windows-written name once put
# one in BASEOS_STOCK).
for f in etc/baseos-release usr/share/basedos/needs-stock usr/share/basedos/stock-links; do
	[ -f "$f" ] || continue
	! grep -q "$(printf '\r')" "$f" || { echo "$f has a carriage return" >&2; exit 1; }
done
cat > etc/os-release <<EOF
ID=basedos
NAME="BasedOS"
VERSION_ID=$VERSION
PRETTY_NAME="BasedOS $VERSION (GKD 350H Ultra)"
EOF

echo "--- check: nothing of stock's in the system layer"
# The system layer is what gets published: no file in it may be a copy of a stock file (the
# links into /stock aren't files).
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
# The system layer with stock's linked files in place of the links, as the running system sees it.
cp -a "$SYS" "$OUT"
python3 - "$OUT" "$VEN" <<'EOF'
import os, shutil, sys
out, ven = sys.argv[1:]
n = 0
for root, dirs, files in os.walk(out):
    for f in files + dirs:
        p = os.path.join(root, f)
        if os.path.islink(p) and os.readlink(p).startswith("/stock/"):
            os.remove(p)
            shutil.copy2(os.path.join(ven, os.path.relpath(p, out)), p)
            n += 1
print(f"{n} stock files in place")
EOF
# /boot is the boot partition's mount point in the running system, not part of the root.
rm -rf "$OUT/boot"
mkdir -p "$OUT/boot"

echo "--- squashfs"
mksquashfs "$SYS" "$W/rootfs.squashfs" -noappend -all-root -comp zstd -Xcompression-level 15 -b 256K -quiet
ls -l "$W/rootfs.squashfs"
grep -E "^BASEOS_(VERSION|BUILD|STOCK)" "$SYS/etc/baseos-release"
