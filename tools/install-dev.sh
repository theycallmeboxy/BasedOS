#!/bin/sh
# Developer install of BasedOS v0 next to stock, run ON the device under stock.
#   install-dev.sh <dir with rootfs.squashfs, initrd.uimg, boot.scr, rk3576-gkd-atom.dtb>
#   install-dev.sh revert      put stock's boot.scr back (stock boots again)
#
# Adds /flash/basedos/ (p1) and /storage/basedos-data/ (p2), swaps boot.scr and
# keeps stock's copy in /flash/basedos/boot.scr.stock. BasedOS's panel DTB (60 Hz,
# mkboot.py dtb) goes in /flash/basedos/; stock's SYSTEM, Image, DTBs and /storage
# stay as they are.
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

# put <src> <dst>: replace dst so that a power cut at any point leaves either the old or the
# new file, never a short one: write dst.new, sync, re-read it from the card (not the page
# cache), then rename over dst and sync again.
put() {
	cp "$1" "$2.new" || die "copy to $2.new failed"
	sync
	echo 3 > /proc/sys/vm/drop_caches
	[ "$(md5sum < "$1")" = "$(md5sum < "$2.new")" ] || { rm -f "$2.new"; die "$2.new does not match $1"; }
	mv "$2.new" "$2" || die "rename to $2 failed"
	sync
}

if [ "${1:-}" = revert ]; then
	[ -f $P1/basedos/boot.scr.stock ] || die "no saved stock boot.scr"
	rw; put $P1/basedos/boot.scr.stock $P1/boot.scr; ro
	echo "stock boot.scr restored; reboot to boot stock"
	exit 0
fi

SRC=${1:?usage: $0 <dir> | revert}
[ -d /storage/.cache ] || die "install from stock (it reads stock's /storage)"
for f in rootfs.squashfs initrd.uimg boot.scr rk3576-gkd-atom.dtb; do [ -s "$SRC/$f" ] || die "missing $SRC/$f"; done
[ "$(md5sum < $P1/boot.scr)" = "$(md5sum < $SRC/boot.scr)" ] && echo "(BasedOS boot.scr already installed)"

rw
trap ro EXIT
mkdir -p $P1/basedos
if [ ! -f $P1/basedos/boot.scr.stock ]; then
	# Never save BasedOS's own script as "stock": revert would then be a no-op.
	dd if=$P1/boot.scr bs=72 skip=1 2>/dev/null | grep -q "BasedOS" &&
		die "boot.scr is already BasedOS's and there is no saved stock copy"
	put $P1/boot.scr $P1/basedos/boot.scr.stock
fi
# The rootfs, initrd and DTB first; boot.scr, which switches the device over, only once they verify.
put "$SRC/rootfs.squashfs" $P1/basedos/rootfs.squashfs
put "$SRC/initrd.uimg" $P1/basedos/initrd.uimg
put "$SRC/rk3576-gkd-atom.dtb" $P1/basedos/rk3576-gkd-atom.dtb
put "$SRC/boot.scr" $P1/boot.scr
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
		# connman stores the SSID as hex (SSID=) and the passphrase in clear. Write the SSID as
		# hex and the key as wpa_passphrase's 64-hex PSK, both unquoted, so quotes or
		# backslashes in either can't break the file. Open networks get key_mgmt=NONE.
		for s in /storage/.cache/connman/wifi_*/settings; do
			[ -f "$s" ] || continue
			name=$(sed -n 's/^Name=//p' "$s" | head -1)
			ssid=$(sed -n 's/^SSID=//p' "$s" | head -1)
			pass=$(sed -n 's/^Passphrase=//p' "$s" | head -1)
			[ -n "$ssid" ] || continue
			if [ -n "$pass" ]; then
				psk=$(wpa_passphrase "$name" "$pass" | sed -n 's/^[[:space:]]*psk=\([0-9a-f]\{64\}\)$/\1/p')
				[ -n "$psk" ] || { echo "skipping $name: wpa_passphrase failed" >&2; continue; }
				printf 'network={\n\tssid=%s\n\tpsk=%s\n}\n' "$ssid" "$psk"
			else
				printf 'network={\n\tssid=%s\n\tkey_mgmt=NONE\n}\n' "$ssid"
			fi
		done
	} > $DATA/wpa_supplicant.conf
	echo "wpa_supplicant.conf: $(grep -c 'network=' $DATA/wpa_supplicant.conf) network(s) from connman"
fi
echo "p2: $(ls -A $DATA | tr '\n' ' ')"
echo "installed. Reboot to start BasedOS. To go back: $0 revert (from stock or BasedOS)."
