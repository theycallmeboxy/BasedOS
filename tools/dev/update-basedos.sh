#!/bin/sh
# Developer update, run ON the device under BasedOS:
#   update-basedos.sh <dir with rootfs.squashfs [initrd.uimg] [boot.scr]>
# Writes the rootfs (the system layer) to the slot that is NOT running (rootfs.squashfs /
# rootfs-b.squashfs on p1), verifies it from the card, then points /boot/basedos/slot at it. Like
# a .bosupd, a rootfs made for another stock build (its needs-stock) is refused (docs/plan.md,
# Architecture). Reboot to use it; the
# initrd's boot counter falls back to the other slot if the new one never reaches rcS.
# The running slot is read from the loop device itself, not the slot file, so running this
# twice without rebooting can never overwrite the image that is running.
set -eu
SRC=${1:?usage: $0 <dir>}
B=/boot/basedos
die() { echo "ERROR: $*" >&2; exit 1; }

grep -q '^BASEOS_NAME=BasedOS$' /etc/baseos-release 2>/dev/null || die "not running BasedOS"
grep -q '^/dev/mmcblk0p1 /boot ' /proc/mounts || die "/boot isn't eMMC p1"
[ -s "$SRC/rootfs.squashfs" ] || die "missing $SRC/rootfs.squashfs"

running=""
for f in /sys/block/loop*/loop/backing_file; do
	case "$(cat "$f" 2>/dev/null)" in
		*/basedos/rootfs.squashfs) running=a ;;
		*/basedos/rootfs-b.squashfs) running=b ;;
	esac
done
[ -n "$running" ] || die "can't tell which rootfs slot is running"
want=$(head -c 2 $B/slot 2>/dev/null | tr -d '\n'); [ "$want" = b ] || want=a
[ "$want" = "$running" ] ||
	die "slot file already points at $want (running $running): reboot before updating again"
if [ "$running" = b ]; then new=a; newfile=rootfs.squashfs; else new=b; newfile=rootfs-b.squashfs; fi

# Write .new, sync, re-read from the card, rename, sync: a power cut leaves old or new, never short.
put() {
	cp "$1" "$2.new" || die "copy to $2.new failed"
	sync
	echo 3 > /proc/sys/vm/drop_caches
	[ "$(md5sum < "$1")" = "$(md5sum < "$2.new")" ] || { rm -f "$2.new"; die "$2.new does not match"; }
	mv "$2.new" "$2" || die "rename to $2 failed"
	sync
}

# The stock build an image is made for (empty for an older BasedOS, made for a vendor set).
needs_stock() {
	mkdir -p /tmp/.needs-stock
	mount -t squashfs -o ro,loop "$1" /tmp/.needs-stock || die "$1 does not mount"
	cat /tmp/.needs-stock/usr/share/basedos/needs-stock 2>/dev/null || true
	umount /tmp/.needs-stock
}
new_stock=$(needs_stock "$SRC/rootfs.squashfs")

mount -o remount,rw /boot
trap 'sync; mount -o remount,ro /boot || echo "WARNING: /boot stayed read-write" >&2' EXIT
[ -n "$new_stock" ] && [ "$new_stock" = "$(cat /stock/etc/os-release 2>/dev/null | sed -n 's/^BUILD_ID="\{0,1\}\([0-9a-f]*\)"\{0,1\}$/\1/p')" ] ||
	die "the new rootfs is made for stock build '$new_stock', not this device's"
put "$SRC/rootfs.squashfs" "$B/$newfile"
# The initrd and boot.scr are not A/B: the slot fallback can't undo them, so each
# one replaced keeps the file it replaces as <name>.prev (boot.scr's as basedos/boot.scr.prev). To
# go back (from SSH or maintenance mode):
#   mount -o remount,rw /boot; cp <name>.prev <name>; sync
# boot.scr boots stock (its own saved script) when it can't load BasedOS's kernel, DTB or initrd.
# A boot.scr that U-Boot can't run has no automatic way back: SSH and the .prev copy, or the
# rescue card.
# replace <src> <dst> [<where the old one goes>]: default <dst>.prev beside it.
replace() {
	if [ -f "$2" ] && ! cmp -s "$1" "$2"; then put "$2" "${3:-$2.prev}"; fi
	put "$1" "$2"
}
[ -s "$SRC/initrd.uimg" ] && replace "$SRC/initrd.uimg" "$B/initrd.uimg"
# boot.scr last, and only BasedOS's own (mkboot.py script): never stock's, which would leave BasedOS.
if [ -s "$SRC/boot.scr" ]; then
	scr=$(dd if="$SRC/boot.scr" bs=72 skip=1 2>/dev/null)
	case "$scr" in *"BasedOS"*"rdinit=/basedos/init"*) ;; *) die "$SRC/boot.scr isn't BasedOS's (mkboot.py script)" ;; esac
	# The old one in BasedOS's folder, not beside stock's files: uninstall removes basedos/ whole.
	replace "$SRC/boot.scr" /boot/boot.scr "$B/boot.scr.prev"
fi
if [ "$new" = b ]; then
	echo b > "$B/slot.new" && sync && mv "$B/slot.new" "$B/slot"
else
	rm -f "$B/slot"
fi
sync
echo "running slot: $running; next boot: $new ($newfile, for stock $new_stock). Reboot to switch."
