#!/bin/sh
# Developer update, run ON the device under BasedOS:
#   update-basedos.sh <dir with rootfs.squashfs [initrd.uimg] [boot.scr]>
# Writes the rootfs (the system layer) beside the running one as basedos/rootfs.new, verified from
# the eMMC, as a .bosupd does; the initrd puts it in place at the next start (the running image
# can't be replaced while it's in use). Like a .bosupd, a rootfs made for another stock build (its
# needs-stock) is refused (docs/plan.md, Architecture). Reboot to use it; one that never reaches
# rcS sends the device to stock after three tries (setup's Repair puts a release back).
set -eu
SRC=${1:?usage: $0 <dir>}
B=/boot/basedos
die() { echo "ERROR: $*" >&2; exit 1; }

grep -q '^BASEOS_NAME=BasedOS$' /etc/baseos-release 2>/dev/null || die "not running BasedOS"
grep -q '^/dev/mmcblk0p1 /boot ' /proc/mounts || die "/boot isn't eMMC p1"
[ -s "$SRC/rootfs.squashfs" ] || die "missing $SRC/rootfs.squashfs"

# Write .new, sync, re-read from the card, rename, sync: a power cut leaves old or new, never short.
put() {
	cp "$1" "$2.new" || die "copy to $2.new failed"
	sync
	echo 3 > /proc/sys/vm/drop_caches
	[ "$(md5sum < "$1")" = "$(md5sum < "$2.new")" ] || { rm -f "$2.new"; die "$2.new does not match"; }
	mv "$2.new" "$2" || die "rename to $2 failed"
	sync
}

# needs <image> <what>: its usr/share/basedos/needs-<what>: the stock build it's made for (empty
# for an older BasedOS, made for a vendor set), the initrd interface it needs (empty: 1).
needs() {
	mkdir -p /tmp/.needs
	mount -t squashfs -o ro,loop "$1" /tmp/.needs || die "$1 does not mount"
	cat "/tmp/.needs/usr/share/basedos/needs-$2" 2>/dev/null || true
	umount /tmp/.needs
}
new_stock=$(needs "$SRC/rootfs.squashfs" stock)
new_initrd=$(needs "$SRC/rootfs.squashfs" initrd)
case "$new_initrd" in ''|*[!0-9]*) new_initrd=1 ;; esac
# The interface an initrd gives (its image name, "BasedOS initrd abi N"; plain "BasedOS initrd": 1),
# for the initrd this leaves in place.
abi_of() {
	n=$(dd if="$1" bs=32 skip=1 count=1 2>/dev/null | tr -d '\000')
	case "$n" in "BasedOS initrd abi "*) n=${n#BasedOS initrd abi }; case "$n" in ''|*[!0-9]*) echo 0 ;; *) echo "$n" ;; esac ;;
	"BasedOS initrd") echo 1 ;; *) echo 0 ;; esac
}
if [ -s "$SRC/initrd.uimg" ]; then have_initrd=$(abi_of "$SRC/initrd.uimg"); else have_initrd=$(abi_of "$B/initrd.uimg"); fi
[ "$new_initrd" -le "$have_initrd" ] ||
	die "the new rootfs needs initrd interface $new_initrd; the initrd would be $have_initrd (add the new initrd.uimg)"

mount -o remount,rw /boot
trap 'sync; mount -o remount,ro /boot || echo "WARNING: /boot stayed read-write" >&2' EXIT
[ -n "$new_stock" ] && [ "$new_stock" = "$(cat /stock/etc/os-release 2>/dev/null | sed -n 's/^BUILD_ID="\{0,1\}\([0-9a-f]*\)"\{0,1\}$/\1/p')" ] ||
	die "the new rootfs is made for stock build '$new_stock', not this device's"
put "$SRC/rootfs.squashfs" "$B/rootfs.new"
# The initrd and boot.scr are BasedOS's boot files: a bad one stops every boot, so each
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
	# Stock's own, from where an older install kept it (BasedOS's folder) to beside its place, where
	# this boot script looks for it.
	if [ -f "$B/boot.scr.stock" ] && [ ! -f /boot/boot.scr.stock ]; then
		put "$B/boot.scr.stock" /boot/boot.scr.stock
	fi
	[ -f /boot/boot.scr.stock ] && rm -f "$B/boot.scr.stock"
	# The old one in BasedOS's folder, not beside stock's files: uninstall removes basedos/ whole.
	replace "$SRC/boot.scr" /boot/boot.scr "$B/boot.scr.prev"
fi
# What the two-slot layout left: the second slot and its pointer (not while it's the running one).
grep -qs '/basedos/rootfs-b.squashfs' /sys/block/loop*/loop/backing_file || rm -f "$B/rootfs-b.squashfs"
rm -f "$B/slot"
sync
echo "installed as $B/rootfs.new (for stock $new_stock): reboot to put it in place."
