#!/bin/sh
# Developer update, run ON the device under BasedOS:
#   update-basedos.sh <dir with rootfs.squashfs [initrd.uimg] [rk3576-gkd-atom.dtb] [boot.scr]>
# Writes the rootfs to the slot that is NOT running (rootfs.squashfs / rootfs-b.squashfs on p1),
# verifies it from the card, then points /boot/basedos/slot at it. Reboot to use it; the
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

mount -o remount,rw /boot
trap 'sync; mount -o remount,ro /boot || echo "WARNING: /boot stayed read-write" >&2' EXIT
put "$SRC/rootfs.squashfs" "$B/$newfile"
# The initrd is not A/B, but boot.scr boots stock if U-Boot rejects it.
[ -s "$SRC/initrd.uimg" ] && put "$SRC/initrd.uimg" "$B/initrd.uimg"
# Nor is the panel DTB: boot.scr falls back to stock's when it can't load ours, and boots stock
# (with stock's DTB) when booti rejects it.
[ -s "$SRC/rk3576-gkd-atom.dtb" ] && put "$SRC/rk3576-gkd-atom.dtb" "$B/rk3576-gkd-atom.dtb"
# boot.scr last, and only BasedOS's own (mkboot.py bootscr): never stock's, which would leave BasedOS.
if [ -s "$SRC/boot.scr" ]; then
	dd if="$SRC/boot.scr" bs=72 skip=1 2>/dev/null | grep -q "BasedOS" || die "$SRC/boot.scr isn't BasedOS's"
	put "$SRC/boot.scr" /boot/boot.scr
fi
if [ "$new" = b ]; then
	echo b > "$B/slot.new" && sync && mv "$B/slot.new" "$B/slot"
else
	rm -f "$B/slot"
fi
sync
echo "running slot: $running; next boot: $new ($newfile). Reboot to switch."
