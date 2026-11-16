#!/bin/sh
# Full eMMC backup of the GKD 350H Ultra (stock ROCKNIX) to this PC over SSH.
# READ-ONLY on the device: it reads block devices and writes nothing there,
# not even temp files.
#
#   cd <repo root>; export MSYS_NO_PATHCONV=1 GKD_HOST=<ip or name> GKD_PASS=
#   sh tools/dev/backup-emmc.sh <empty output dir>
#
# Output: <disk>.img (whole user area), <disk>boot0/1.img, partition table,
# device-md5.txt, SHA256SUMS, and a VERIFIED or MISMATCH line at the end.
# /storage is mounted read-write while this runs; the script records its write
# counter before and after so you can see whether the image is a clean snapshot.
set -eu
here=$(dirname "$0")
G="${PYTHON:-.venv/Scripts/python} $here/gkdssh.py"
out=${1:?output dir}
[ -e "$out" ] && [ -n "$(ls -A "$out")" ] && { echo "$out is not empty" >&2; exit 1; }
mkdir -p "$out"

# Find the eMMC by what it is (type MMC on the eMMC controller), not by number.
disk=$($G run 'for d in /sys/block/mmcblk*; do case $d in *boot*|*rpmb*) continue;; esac
	[ "$(cat $d/device/type 2>/dev/null)" = MMC ] && readlink -f $d | grep -q 2a330000.mmc && basename $d; done')
[ -n "$disk" ] || { echo "no eMMC found" >&2; exit 1; }
echo "eMMC is /dev/$disk"

$G run "cat /proc/partitions; blkid; for f in name manfid oemid date fwrev life_time pre_eol_info; do echo \$f=\$(cat /sys/block/$disk/device/\$f); done; cat /sys/block/$disk/size" > "$out/device-info.txt"
stat_p2() { $G run "cat /sys/block/$disk/${disk}p2/stat"; }
echo "before: $(stat_p2)" > "$out/p2-writes.txt"

for b in boot0 boot1; do
	$G dump "cat /dev/${disk}$b" "$out/${disk}$b.img"
done
$G dump "dd if=/dev/$disk bs=4M 2>/dev/null | zstd -1 -T4 -q -c" "$out/$disk.img" --zstd | tee "$out/dump-result.txt"
echo "after: $(stat_p2)" >> "$out/p2-writes.txt"

echo "hashing on the device (reads the whole eMMC again)..."
# Whole disk only: hashing the mounted /storage partition device returns
# some of ext4's in-memory metadata instead of the on-disk bytes.
$G run "md5sum < /dev/$disk | sed 's/-\$/$disk/'" > "$out/device-md5.txt"
cat "$out/device-md5.txt"

cd "$out"
pc=$(md5sum "$disk.img" | cut -d' ' -f1)
dev=$(awk -v d="$disk" '$2==d {print $1}' device-md5.txt)
sha256sum -- *.img > SHA256SUMS
if [ "$pc" = "$dev" ]; then echo "VERIFIED: $disk.img md5 $pc matches the device"
else echo "MISMATCH: image $pc, device $dev (see p2-writes.txt: was /storage written during the copy?)"; exit 1; fi
