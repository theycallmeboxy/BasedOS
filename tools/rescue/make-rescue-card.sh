#!/bin/sh
# Build a GKD 350H Ultra rescue SD card, ON the device, from the device's own
# stock files. Runs on stock (booted from eMMC) with the card in the SD slot.
#
#   make-rescue-card.sh probe              show the card; writes nothing
#   make-rescue-card.sh write <card CID>   ERASE that card and build the rescue card
#   make-rescue-card.sh finish             unmount the card and reboot into it
#
# Needs in /tmp/rescue-files (pushed from the PC): boot.scr from
# mkbootscr-card.py and the three DTBs from dtb-swap-mmc.py.
#
# The card gets stock's own layout: MBR; the eMMC's loader (sectors 64-32767,
# copied; note: tested 2026-11-20, the boot ROM never starts a loader from the card, so this
# copy doesn't help if the eMMC's loader is damaged);
# p1 vfat at 32768 with stock's Image and SYSTEM plus the card boot.scr and
# DTBs (aliases swapped so the card is mmcblk0); p2 ext4 to the end holding a
# copy of stock's /storage (Wi-Fi, SSH and settings carry over).
#
# The eMMC is only ever read. Every write goes to the card, which must be on
# the SD controller (2a310000.mmc), be type SD, and match the CID given.
set -eu
CARD=mmcblk1
EMMC=mmcblk0
FILES=/tmp/rescue-files
MNT=/run/rescue-card

die() { echo "ERROR: $*" >&2; exit 1; }

check_devices() {
	readlink -f /sys/block/$EMMC | grep -q '/2a330000\.mmc/' || die "$EMMC is not the eMMC controller"
	[ "$(cat /sys/block/$EMMC/device/type)" = MMC ] || die "$EMMC is not type MMC"
	[ -e /sys/block/$CARD ] || die "no card in the SD slot"
	readlink -f /sys/block/$CARD | grep -q '/2a310000\.mmc/' || die "$CARD is not on the SD controller"
	[ "$(cat /sys/block/$CARD/device/type)" = SD ] || die "$CARD is not type SD"
	[ ! -e /sys/block/${CARD}boot0 ] || die "$CARD has boot partitions; that's an eMMC"
}

card_info() {
	d=/sys/block/$CARD
	echo "card /dev/$CARD: $(cat $d/device/name) cid=$(cat $d/device/cid)"
	echo "  size $(( $(cat $d/size) / 2048 )) MiB ($(cat $d/size) sectors)"
	echo "  partitions:"; grep " ${CARD}p" /proc/partitions || echo "  (none)"
	blkid /dev/${CARD}p* 2>/dev/null | sed 's/^/  /' || true
	echo "  mounted:"; grep "^/dev/$CARD" /proc/mounts | sed 's/^/  /' || echo "  (nothing)"
}

check_devices
case "${1:-}" in
probe)
	card_info
	echo "eMMC /dev/$EMMC: $(cat /sys/block/$EMMC/device/name), will only be read"
	du -sh --exclude=./games-external --exclude=./roms /storage 2>/dev/null || du -sh /storage
	exit 0 ;;
write)
	[ "$(cat /sys/block/$CARD/device/cid)" = "${2:-}" ] || die "card CID doesn't match; run probe first"
	;;
finish)
	# udev's queue is still held from 'write', so stock's automount can't grab
	# the new card partitions; reboot rather than release it.
	[ -e $MNT/p2/.rescue-card ] || die "no rescue card mounted at $MNT/p2"
	sync
	umount $MNT/p1 $MNT/p2
	rmdir $MNT/p1 $MNT/p2 $MNT
	echo "card unmounted; rebooting into it"
	reboot
	exit 0 ;;
*) die "usage: $0 probe | write <card CID> | finish" ;;
esac

for f in boot.scr rk3576-gkd-atom.dtb rk3576-gkd-atom-hdmi.dtb rk3576-gkd-atom-usbdp.dtb; do
	[ -s $FILES/$f ] || die "missing $FILES/$f"
done
size=$(cat /sys/block/$CARD/size)
[ "$size" -ge 23000000 ] || die "card is smaller than ~12 GB; too small for system, storage and the backup"

# Hold udev's automount off the card while it is rebuilt; restore on exit.
udevadm control --stop-exec-queue
cleanup() {
	set +e
	sync
	for m in $(grep -o "^/dev/$CARD[^ ]* [^ ]*" /proc/mounts | cut -d' ' -f2 | sort -r); do umount "$m"; done
	rmdir $MNT/p1 $MNT/p2 $MNT 2>/dev/null
	udevadm control --start-exec-queue
}
trap cleanup EXIT

echo "--- unmounting the card"
for m in $(grep -o "^/dev/$CARD[^ ]* [^ ]*" /proc/mounts | cut -d' ' -f2 | sort -r); do umount "$m"; done
! grep -q "^/dev/$CARD" /proc/mounts || die "card still mounted"

echo "--- partition table (MBR: p1 vfat 32768+6144000, p2 ext4 to the end)"
dd if=/dev/zero of=/dev/$CARD bs=1M count=32 conv=fsync 2>/dev/null
parted -s /dev/$CARD mklabel msdos \
	mkpart primary fat32 32768s 6176767s \
	mkpart primary ext4 6176768s 100%
echo "--- loader: copying the eMMC's sectors 64-32767 to the card"
dd if=/dev/$EMMC of=/dev/$CARD bs=512 skip=64 seek=64 count=32704 conv=fsync 2>/dev/null
[ "$(dd if=/dev/$EMMC bs=512 skip=64 count=32704 2>/dev/null | md5sum)" = \
  "$(dd if=/dev/$CARD bs=512 skip=64 count=32704 2>/dev/null | md5sum)" ] || die "loader copy mismatch"
partprobe /dev/$CARD 2>/dev/null || blockdev --rereadpt /dev/$CARD 2>/dev/null || true
sleep 2
[ -b /dev/${CARD}p1 ] && [ -b /dev/${CARD}p2 ] || die "card partitions didn't appear"

echo "--- filesystems"
mkfs.vfat -F 32 -n GKD-RESCUE /dev/${CARD}p1 >/dev/null
mkfs.ext4 -F -q -L GKD-RESCUE-ST /dev/${CARD}p2
mkdir -p $MNT/p1 $MNT/p2
mount /dev/${CARD}p1 $MNT/p1
mount /dev/${CARD}p2 $MNT/p2

echo "--- p1: stock Image and SYSTEM from /flash, card boot.scr and DTBs"
cp /flash/Image /flash/SYSTEM $MNT/p1/
cp $FILES/boot.scr $FILES/*.dtb $MNT/p1/
sync
for f in Image SYSTEM; do
	[ "$(md5sum < /flash/$f)" = "$(md5sum < $MNT/p1/$f)" ] || die "$f copy mismatch"
done

echo "--- p2: copy of stock /storage (without the ROM mounts)"
tar -C /storage --exclude=./games-external --exclude=./roms -cf - . | tar -C $MNT/p2 -xf -
mkdir -p $MNT/p2/games-external/roms $MNT/p2/roms
rm -f $MNT/p2/.please_resize_me $MNT/p2/.please_resize_roms_partition
echo "GKD 350H Ultra rescue card, built $(date -Iseconds) from $(grep ^BUILD_ID /etc/os-release)" > $MNT/p2/.rescue-card
mkdir -p $MNT/p2/rescue-backup
sync
df -h $MNT/p1 $MNT/p2
echo "--- done. The card stays mounted at $MNT/p2 for the backup copy, and udev's"
echo "    queue stays held. Next: '$0 finish' (unmounts and reboots), or reboot."
trap - EXIT
