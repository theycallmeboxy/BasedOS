#!/bin/sh
# Full BasedOS build (the system layer, the initrd, the boot scripts, the recovery card's files) in
# WSL from the repo on /mnt/e.
set -eu
REPO=/mnt/e/projects/spruceOS-gkd350hultra/basedos
W=$HOME/basedos-work
STOCK=$REPO/prepared/rocknix-20260613-c8ed06c
mkdir -p "$W"
# The stock build's name, without the carriage return a Windows-written BUILD file carries.
tr -d '\r' < "$STOCK/BUILD" > "$W/STOCK_BUILD"
# Stock's root, unpacked once (the links into /stock are made against it; lib32-gaps reads it).
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
sh "$REPO/tools/wsl/build-rootfs.sh" "$REPO" "$W" "$REPO/prepared/alpine/busybox.static" "$REPO/prepared/alpine/busybox.list"
STOCK_BUILD_ID=$(cat "$W/system/usr/share/basedos/needs-stock")
mkdir -p "$REPO/out"
cp "$W/rootfs.squashfs" "$REPO/out/rootfs.squashfs"
# (Older builds' vendor sets and boot.env: BasedOS no longer has either.)
rm -rf "$REPO"/out/vendor-* "$REPO/out/boot.env"
# The update payload: the system layer and the initrd, nothing of stock's (publishable).
python3 "$REPO/tools/mkboot.py" initrd "$REPO/prepared/alpine/busybox.static" "$W/initrd.uimg.new" >/dev/null
mv "$W/initrd.uimg.new" "$REPO/out/initrd.uimg"
# BasedOS's own boot script (initrd/boot.cmd; setup puts it in place of stock's).
rm -f "$W/boot.scr.new"
python3 "$REPO/tools/mkboot.py" script "$REPO/initrd/boot.cmd" "$W/boot.scr.new"
mv "$W/boot.scr.new" "$REPO/out/boot.scr"
# The recovery card's initrd and boot script (tools/recovery), and the setup script itself: with
# rootfs.squashfs, initrd.uimg and boot.scr, that's the release folder basedos-setup runs from.
# release.info: what basedos-setup checks before it asks anything or downloads the rest: this
# build, and the stock build it runs on (its BUILD_ID, and the SHA-256 of the stock files BasedOS
# boots and mounts: the kernel, the DTBs, SYSTEM), so the device's own stock is matched first.
{
	sed -n 's/^BASEOS_\(VERSION\|BUILD\)=/\1=/p' "$W/system/etc/baseos-release"
	echo "STOCK_BUILD=$(cat "$W/STOCK_BUILD")"
	echo "STOCK_BUILD_ID=$STOCK_BUILD_ID"
	for f in Image rk3576-gkd-atom.dtb rk3576-gkd-atom-hdmi.dtb rk3576-gkd-atom-usbdp.dtb SYSTEM; do
		echo "P1 $(sha256sum < "$STOCK/$f" | cut -c1-64) $f"
	done
} > "$REPO/out/release.info"
[ "$(grep -c '^P1 ' "$REPO/out/release.info")" -eq 5 ] || { echo "release.info: stock's file hashes missing" >&2; exit 1; }
# The RK3576 maskrom USB loader (Rockchip's rkbin DDR init and usbplug, packed by
# tools/maskrom/mk-usb-loader.py) and rkbin's licence: setup puts them on every recovery card, so a
# maskrom restore from a PC needs nothing else (docs/recovery.md). Distributable under rkbin's
# licence, which travels with it. Kept in prepared/maskrom/, checked against its known SHA-256.
USB_LOADER=rk3576_usb_loader_ddr1.13_usbplug1.04.bin
[ "$(sha256sum < "$REPO/prepared/maskrom/$USB_LOADER" | cut -c1-64)" = f2bac2f2e82ea0997d096aa7062629a3d1cc2af918d7c304db3610a93a82be97 ] ||
	{ echo "prepared/maskrom/$USB_LOADER missing or not the known build" >&2; exit 1; }
cp "$REPO/prepared/maskrom/$USB_LOADER" "$REPO/prepared/maskrom/LICENSE.rkbin.txt" "$REPO/out/"
sh "$REPO/tools/recovery/build.sh" "$REPO" "$W" "$REPO/prepared/alpine/busybox.static" "$REPO/out"
cp "$REPO/tools/basedos-setup.sh" "$REPO/out/basedos-setup.sh"
rm -f "$REPO"/out/baseos-*.bosupd
python3 "$REPO/tools/mkupdate.py" "$W/rootfs.squashfs" "$REPO/out/initrd.uimg" 	"$STOCK_BUILD_ID" "$(cat "$REPO/VERSION")" 	"$(sed -n 's/^BASEOS_BUILD=//p' "$W/system/etc/baseos-release")" "$REPO/out"
for r in harvest-report.txt base32-report.txt lib32-gaps.txt; do
	cp "$W/$r" "$REPO/out/$r" 2>/dev/null || true
done
