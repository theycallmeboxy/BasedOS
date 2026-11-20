#!/bin/sh
# Full rootfs build (vendor and system layers) in WSL from the repo on /mnt/e.
set -eu
REPO=/mnt/e/projects/spruceOS-gkd350hultra/basedos
W=$HOME/basedos-work
STOCK=$REPO/prepared/rocknix-20260613-c8ed06c
mkdir -p "$W"
# The stock build's name, without the carriage return a Windows-written BUILD file carries.
tr -d '\r' < "$STOCK/BUILD" > "$W/STOCK_BUILD"
# Stock's root, unpacked once (the vendor harvest and lib32-gaps read it).
[ -d "$W/stock-root/usr/lib" ] || sh "$REPO/tools/wsl/unpack-stock.sh" "$STOCK/SYSTEM" "$W/stock-root"

# sdl2_current <prepared dir> <arch>: 0 if that SDL2 build is of the SDL and librga commits and
# the patches tools/sdl2 has now (its build-info records them), so it needn't be built again.
sdl2_current() {
	_i=$1/libSDL2.build-info
	[ -f "$_i" ] || return 1
	_a=$(sed -n 's/^arch //p' "$_i")
	[ "${_a:-aarch64}" = "$2" ] || return 1
	for _c in SDL_COMMIT:SDL RGA_COMMIT:librga; do
		_v=$(sed -n "s/^${_c%%:*}=\([0-9a-f]*\).*/\1/p" "$REPO/tools/sdl2/build.sh")
		grep -q "^${_c#*:} $_v " "$_i" || return 1
	done
	_n=0
	for _p in "$REPO"/tools/sdl2/patches/sdl2-patch*; do
		grep -qx "patch ${_p##*/} $(sha256sum < "$_p" | cut -c1-16)" "$_i" || return 1
		_n=$((_n + 1))
	done
	[ "$(grep -c '^patch ' "$_i")" -eq "$_n" ]
}

sdl2_current "$REPO/prepared/sdl2" aarch64 || {
	echo "--- SDL2 (64-bit): building (missing or out of date)"
	rm -rf "$REPO/prepared/sdl2"
	bash "$REPO/tools/sdl2/build.sh" "$STOCK/SYSTEM" "$REPO/prepared/sdl2" 270
}
# BasedOS's userland (glibc, OpenSSH, wpa_supplicant and wpa_cli, ALSA, ...): about an hour the first
# time, then only what changed.
bash "$REPO/tools/buildroot/build.sh" build
# Its 32-bit libraries for PortMaster's 32-bit ports (docs/lib32.md), and SDL2 for them, built with
# that root's toolchain.
bash "$REPO/tools/buildroot/build.sh" --armhf build
sdl2_current "$REPO/prepared/sdl2-armhf" armhf || {
	echo "--- SDL2 (32-bit): building (missing or out of date)"
	rm -rf "$REPO/prepared/sdl2-armhf"
	SDL2_ARCH=armhf bash "$REPO/tools/sdl2/build.sh" "$STOCK/SYSTEM" "$REPO/prepared/sdl2-armhf" 270
}
[ -f "$REPO/prepared/bash/build-info" ] ||
	bash "$REPO/tools/bash/build.sh" "$REPO/prepared/bash"
STOCK_P1=$STOCK sh "$REPO/tools/wsl/build-rootfs.sh" "$REPO" "$W" "$REPO/prepared/alpine/busybox.static" "$REPO/prepared/alpine/busybox.list"
VENDOR_ID=$(sed -n 's/^BASEOS_VENDOR=//p' "$W/system/etc/baseos-release")
mkdir -p "$REPO/out"
cp "$W/rootfs.squashfs" "$REPO/out/rootfs.squashfs"
# The vendor set stays local: built from your own stock, never published (NOTICE.md).
rm -rf "$REPO"/out/vendor-*
cp -r "$W/vendor-$VENDOR_ID" "$REPO/out/"
# The update payload: the system layer and the initrd, nothing of stock's (publishable).
python3 "$REPO/tools/mkboot.py" initrd "$REPO/prepared/alpine/busybox.static" "$W/initrd.uimg.new" >/dev/null
mv "$W/initrd.uimg.new" "$REPO/out/initrd.uimg"
# BasedOS's own boot script (initrd/boot.cmd), and boot.env naming the vendor set it boots
# (setup puts both on the boot partition; not in a payload: the vendor set doesn't change).
rm -f "$W/boot.scr.new"
python3 "$REPO/tools/mkboot.py" script "$REPO/initrd/boot.cmd" "$W/boot.scr.new"
mv "$W/boot.scr.new" "$REPO/out/boot.scr"
echo "basedos_vendor=$VENDOR_ID" > "$REPO/out/boot.env"
# The recovery card's initrd and boot script (tools/recovery), and the setup script itself: with
# rootfs.squashfs, initrd.uimg and boot.scr, that's the release folder basedos-setup runs from.
# release.info: what basedos-setup checks before it asks anything or downloads the rest: this
# build, the vendor set it's built on, and the stock build's kernel and DTB hashes (the recipe's
# p1 lines), so the device's own stock can be matched first.
REC=$W/system/usr/share/basedos/vendor-recipe
{
	sed -n 's/^BASEOS_\(VERSION\|BUILD\|VENDOR\)=/\1=/p' "$W/system/etc/baseos-release"
	grep '^STOCK_BUILD=' "$REC"
	awk '$1 == "F" && $5 ~ /^p1:/ { sub(/^p1:/, "", $5); print "P1", $3, $5 }' "$REC"
} > "$REPO/out/release.info"
[ "$(grep -c '^P1 ' "$REPO/out/release.info")" -ge 1 ] || { echo "release.info: no p1 hashes" >&2; exit 1; }
sh "$REPO/tools/recovery/build.sh" "$REPO" "$W" "$REPO/prepared/alpine/busybox.static" "$REPO/out"
cp "$REPO/tools/basedos-setup.sh" "$REPO/out/basedos-setup.sh"
rm -f "$REPO"/out/baseos-*.bosupd
python3 "$REPO/tools/mkupdate.py" "$W/rootfs.squashfs" "$REPO/out/initrd.uimg" 	"$(sed -n 's/^BASEOS_VENDOR=//p' "$W/system/etc/baseos-release")" "$(cat "$REPO/VERSION")" 	"$(sed -n 's/^BASEOS_BUILD=//p' "$W/system/etc/baseos-release")" "$REPO/out"
for r in harvest-report.txt base32-report.txt lib32-gaps.txt; do
	cp "$W/$r" "$REPO/out/$r" 2>/dev/null || true
done
