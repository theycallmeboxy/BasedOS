#!/bin/sh
# Developer install of BasedOS v0 next to stock, run ON the device under stock.
#   install-dev.sh <dir with rootfs.squashfs, initrd.uimg, boot.scr>
#   install-dev.sh revert      put stock's boot.scr back (stock boots again)
#
# Adds /flash/basedos/ (p1) and /storage/basedos-data/ (p2), swaps boot.scr and
# keeps stock's copy in /flash/basedos/boot.scr.stock. Stock's SYSTEM, Image,
# DTBs and /storage stay as they are.
# Copies stock's SSH host keys (same fingerprint) and its saved Wi-Fi network
# (connman -> wpa_supplicant.conf) into basedos-data. Those stay on the device.
set -eu
DATA=/storage/basedos-data
die() { echo "ERROR: $*" >&2; exit 1; }

[ "$(readlink -f /sys/block/mmcblk0 | grep -o 2a330000.mmc)" = 2a330000.mmc ] || die "mmcblk0 isn't the eMMC"
# eMMC p1 is /flash under stock and /boot under BasedOS.
P1=$(awk '$1 == "/dev/mmcblk0p1" { print $2; exit }' /proc/mounts)
[ -n "$P1" ] || die "eMMC p1 isn't mounted (running from the rescue card?)"

rw() { mount -o remount,rw $P1; }
ro() { sync; mount -o remount,ro $P1; }

if [ "${1:-}" = revert ]; then
	[ -f $P1/basedos/boot.scr.stock ] || die "no saved stock boot.scr"
	rw; cp $P1/basedos/boot.scr.stock $P1/boot.scr; ro
	echo "stock boot.scr restored; reboot to boot stock"
	exit 0
fi

SRC=${1:?usage: $0 <dir> | revert}
[ -d /storage/.cache ] || die "install from stock (it reads stock's /storage)"
for f in rootfs.squashfs initrd.uimg boot.scr; do [ -s "$SRC/$f" ] || die "missing $SRC/$f"; done
[ "$(md5sum < $P1/boot.scr)" = "$(md5sum < $SRC/boot.scr)" ] && echo "(BasedOS boot.scr already installed)"

rw
trap ro EXIT
mkdir -p $P1/basedos
[ -f $P1/basedos/boot.scr.stock ] || cp $P1/boot.scr $P1/basedos/boot.scr.stock
cp "$SRC/rootfs.squashfs" $P1/basedos/rootfs.squashfs.new && mv $P1/basedos/rootfs.squashfs.new $P1/basedos/rootfs.squashfs
cp "$SRC/initrd.uimg" $P1/basedos/initrd.uimg
cp "$SRC/boot.scr" $P1/boot.scr
sync
for f in rootfs.squashfs initrd.uimg; do
	[ "$(md5sum < "$SRC/$f")" = "$(md5sum < $P1/basedos/$f)" ] || die "$f copy mismatch"
done
[ "$(md5sum < "$SRC/boot.scr")" = "$(md5sum < $P1/boot.scr)" ] || die "boot.scr copy mismatch"
echo "p1: $(ls $P1/basedos | tr '\n' ' ')"

mkdir -p $DATA/ssh
chmod 700 $DATA/ssh
for k in /storage/.cache/ssh/ssh_host_ed25519_key /storage/.cache/ssh/ssh_host_rsa_key; do
	[ -f $k ] && [ ! -f $DATA/ssh/${k##*/} ] && cp $k $k.pub $DATA/ssh/ 2>/dev/null || true
done
chmod 600 $DATA/ssh/*_key 2>/dev/null || true

if [ ! -f $DATA/wpa_supplicant.conf ]; then
	umask 077
	{
		echo "ctrl_interface=/run/wpa_supplicant"
		echo "update_config=0"
		for s in /storage/.cache/connman/wifi_*/settings; do
			[ -f "$s" ] || continue
			awk -F= '/^Name=/{n=substr($0,6)} /^Passphrase=/{p=substr($0,12)}
				END{ if (n != "" && p != "") printf "network={\n\tssid=\"%s\"\n\tpsk=\"%s\"\n}\n", n, p }' "$s"
		done
	} > $DATA/wpa_supplicant.conf
	echo "wpa_supplicant.conf: $(grep -c 'network=' $DATA/wpa_supplicant.conf) network(s) from connman"
fi
echo "p2: $(ls -A $DATA | tr '\n' ' ')"
echo "installed. Reboot to start BasedOS. To go back: $0 revert (from stock or BasedOS)."
