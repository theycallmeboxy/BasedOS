#!/bin/sh
# Developer update, run ON the device under BasedOS:
#   update-basedos.sh <dir with rootfs.squashfs [initrd.uimg]>
# Writes the rootfs to the slot that is not running (rootfs.squashfs / rootfs-b.squashfs on p1),
# checks it, then flips /boot/basedos/slot. Reboot to use it; flip the slot file back to undo.
# The running root is a loop mount of the other file, so it is never overwritten in place.
set -eu
SRC=${1:?usage: $0 <dir>}
B=/boot/basedos
die() { echo "ERROR: $*" >&2; exit 1; }

[ -f /etc/baseos-release ] && grep -q '^BASEOS_NAME=BasedOS$' /etc/baseos-release || die "not running BasedOS"
grep -q '^/dev/mmcblk0p1 /boot ' /proc/mounts || die "/boot isn't eMMC p1"
[ -s "$SRC/rootfs.squashfs" ] || die "missing $SRC/rootfs.squashfs"

cur=$(cat $B/slot 2>/dev/null || true)
if [ "$cur" = b ]; then new=""; newfile=rootfs.squashfs; else new=b; newfile=rootfs-b.squashfs; fi

mount -o remount,rw /boot
trap 'sync; mount -o remount,ro /boot' EXIT
cp "$SRC/rootfs.squashfs" "$B/$newfile.part"
sync
[ "$(md5sum < "$SRC/rootfs.squashfs")" = "$(md5sum < "$B/$newfile.part")" ] || die "copy mismatch"
mv "$B/$newfile.part" "$B/$newfile"
if [ -s "$SRC/initrd.uimg" ]; then
	cp "$SRC/initrd.uimg" "$B/initrd.uimg.part" && mv "$B/initrd.uimg.part" "$B/initrd.uimg"
fi
if [ -n "$new" ]; then echo "$new" > $B/slot.part; mv $B/slot.part $B/slot; else rm -f $B/slot; fi
sync
echo "running slot: ${cur:-a}; next boot: ${new:-a} ($newfile). Reboot to switch."
