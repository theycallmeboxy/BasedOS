#!/bin/sh
# basedos-setup: install BasedOS on a GKD 350H Ultra, or only back up its eMMC. Run it ON the
# device, under stock ROCKNIX, over SSH (ssh root@<device>; stock's root has no password), from
# the BasedOS release folder:
#
#   sh basedos-setup.sh
#
# It asks everything first (where to install, whether to back up the eMMC, which SD card), shows
# what it will do and asks for one typed confirmation; only then does it write anything, and it
# runs to the end without asking more.
#
#   SD card   BasedOS on the card alone: partitions (basedos: boot files, hidden; data: BasedOS's
#             /data, hidden; BASEOS: the rest, the drive you put spruce on). The eMMC isn't
#             written. With the card in, the device starts BasedOS; without it, stock.
#   eMMC      BasedOS next to stock on the eMMC (stock's files stay; BasedOS's maintenance menu
#             can switch back or uninstall).
#   backup    the whole eMMC, compressed, in basedos-emmc-backup-<date>/ on the card (2 GB parts,
#             SHA256SUMS, a README on restoring), checked against what was read. Before either
#             install (optional), or on its own (choice 3: no install; the card isn't erased).
#
# For an install, the vendor set (the stock kernel, DTBs, modules, firmware and GPU drivers BasedOS
# runs on; docs/plan.md, Architecture) is harvested here from stock's own files, by the recipe in
# this release, with every file's hash checked: stock files are never in a release.
#
# Not interactive: --target sd|emmc|backup, --backup or --no-backup, --card <CID> (the card's ID, as
# shown), --yes. Every check still runs, and the card must have that ID.
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
STOCK_P1=/flash
T=/tmp/basedos-setup            # RAM: an SD install writes nothing to the eMMC
SDC=2a310000.mmc                # the SD slot's controller
EMMCC=2a330000.mmc              # the eMMC's

TARGET="" BACKUP="" CARD_WANT="" YES=""
while [ $# -gt 0 ]; do
	case "$1" in
	--target) TARGET=$2; shift ;;
	--backup) BACKUP=yes ;;
	--no-backup) BACKUP=no ;;
	--card) CARD_WANT=$2; shift ;;
	--yes) YES=1 ;;
	*) echo "unknown option $1" >&2; exit 2 ;;
	esac
	shift
done

say() { printf '%s\n' "$*"; }
step() { printf '\n== %s\n' "$*"; }
die() { printf '\nSTOPPED: %s\n' "$*" >&2; cleanup; exit 1; }
cleanup() {
	for m in "$T"/mnt/*; do grep -q " $m " /proc/mounts && umount "$m" 2>/dev/null; done
	[ -n "${ES_STOPPED:-}" ] && systemctl start essway 2>/dev/null
	ES_STOPPED=""
}
trap 'cleanup' INT TERM
ask() {  # ask <prompt> <var>
	printf '%s ' "$1"
	read -r "$2" || die "no answer (run it from an SSH terminal, or use the options)"
}

# disk_of <controller>: the mmcblk disk on it.
disk_of() {
	for b in /sys/block/mmcblk*; do
		case "$b" in *boot*|*rpmb*) continue ;; esac
		case "$(readlink -f "$b")" in */$1/*) echo "${b##*/}"; return ;; esac
	done
}

# ---------------------------------------------------------------------------------------------
# Phase 1: checks and questions. Nothing is written.

step "Checking"
[ "$(id -u)" = 0 ] || die "run it as root (ssh root@<device>)"
EMMC=$(disk_of $EMMCC)
[ "$EMMC" = mmcblk0 ] || die "this doesn't look like a GKD 350H Ultra (no eMMC at mmcblk0)"
grep -q "^/dev/${EMMC}p1 $STOCK_P1 " /proc/mounts || die "run it on stock ROCKNIX ($STOCK_P1 isn't the eMMC's p1)"
if [ -z "$TARGET" ]; then
	say ""
	say "What do you want to do?"
	say "  1) install BasedOS on an SD card: BasedOS on the card alone; the eMMC (stock) isn't touched"
	say "  2) install BasedOS on the eMMC, next to stock"
	say "  3) only back up the eMMC to an SD card (no install; nothing on the card is erased)"
	ask "Choose 1, 2 or 3:" _a
	case "$_a" in 1) TARGET=sd ;; 2) TARGET=emmc ;; 3) TARGET=backup ;; *) die "no choice made" ;; esac
fi
case "$TARGET" in sd|emmc|backup) ;; *) die "--target must be sd, emmc or backup" ;; esac
[ "$TARGET" = backup ] && BACKUP=yes

# An install: this release, and whether this device's stock is the build it's for.
if [ "$TARGET" != backup ]; then
	for f in rootfs.squashfs initrd.uimg boot.scr; do
		[ -s "$HERE/$f" ] || die "the release folder ($HERE) has no $f"
	done
	mkdir -p "$T/mnt/rootfs" "$T/mnt/stock"
	mount -t squashfs -o ro,loop "$HERE/rootfs.squashfs" "$T/mnt/rootfs" || die "$HERE/rootfs.squashfs does not mount"
	R=$T/mnt/rootfs
	VENDOR=$(cat "$R/usr/share/basedos/needs-vendor" 2>/dev/null)
	RECIPE=$R/usr/share/basedos/vendor-recipe
	VERSION=$(sed -n 's/^BASEOS_VERSION=//p' "$R/etc/baseos-release")
	BUILD=$(sed -n 's/^BASEOS_BUILD=//p' "$R/etc/baseos-release")
	[ -n "$VENDOR" ] && [ -s "$RECIPE" ] || die "this release has no vendor recipe (too old for basedos-setup)"
	STOCK_BUILD=$(sed -n 's/^STOCK_BUILD=//p' "$RECIPE")
	# The stock build: the recipe's own hashes of stock's kernel and DTBs (fast; the harvest checks
	# every other file too).
	grep '^F .* p1:' "$RECIPE" | while read -r _k _m _sha _dst _src; do
		[ "$(sha256sum < "$STOCK_P1/${_src#p1:}" | cut -c1-64)" = "$_sha" ] || { echo "${_src#p1:}"; break; }
	done > "$T/mismatch"
	[ -s "$T/mismatch" ] && die "this device's stock firmware isn't the build this BasedOS release is for ($STOCK_BUILD: $(cat "$T/mismatch") differs)"
	say "BasedOS $VERSION ($BUILD), for stock $STOCK_BUILD: this device matches."
fi

if [ "$TARGET" = emmc ] && [ -d "$STOCK_P1/basedos" ]; then
	die "BasedOS is already on the eMMC; uninstall it first (BasedOS's maintenance menu: hold Select at power-on)"
fi
if [ -z "$BACKUP" ]; then
	say ""
	say "Save a backup of the whole eMMC (stock, as it is now) to the SD card first? About 4 GB;"
	say "it can put the device back exactly as it is today (docs/recovery.md)."
	ask "Back up first? [Y/n]:" _a
	case "$_a" in n|N|no) BACKUP=no ;; *) BACKUP=yes ;; esac
fi

# The card, if there's to be one, with what it must be and what happens to it.
CARD=""
if [ "$TARGET" = sd ] || [ "$BACKUP" = yes ]; then
	if [ "$TARGET" = sd ]; then
		NEED_GB=4; [ "$BACKUP" = yes ] && NEED_GB=8
		REQ="an SD card of at least $NEED_GB GB (more for spruce and games). EVERYTHING ON IT WILL BE ERASED."
	else
		NEED_GB=5
		REQ="an SD card with at least $NEED_GB GB free, FAT32 or exFAT. Nothing on it is erased; the backup goes in a new folder."
	fi
	while :; do
		CARD=$(disk_of $SDC)
		if [ -z "$CARD" ]; then
			say ""
			say "Insert $REQ"
			say "(waiting for a card; Ctrl-C to stop)"
			while [ -z "$(disk_of $SDC)" ]; do sleep 1; done
			sleep 2
			CARD=$(disk_of $SDC)
		fi
		CID=$(cat /sys/block/$CARD/device/cid)
		SIZE_GB=$(( $(cat /sys/block/$CARD/size) / 2097152 ))
		NAME="$(cat /sys/block/$CARD/device/name 2>/dev/null) ($(cat /sys/block/$CARD/device/manfid 2>/dev/null))"
		say ""
		say "Card: $NAME, $SIZE_GB GB, ID $CID"
		blkid /dev/${CARD}p* 2>/dev/null | sed 's/^/  /'
		problem=""
		[ -n "$CARD_WANT" ] && [ "$CID" != "$CARD_WANT" ] && problem="it isn't the card --card names ($CARD_WANT)"
		if [ -z "$problem" ] && [ "$TARGET" = sd ]; then
			[ "$SIZE_GB" -ge "$NEED_GB" ] || problem="it's $SIZE_GB GB; at least $NEED_GB GB is needed"
		elif [ -z "$problem" ]; then
			# The backup goes onto the card's first filesystem, as it is.
			BDEV=/dev/${CARD}p1; [ -b "$BDEV" ] || BDEV=/dev/$CARD
			mkdir -p "$T/mnt/card"
			grep -q " $T/mnt/card " /proc/mounts || mount -o rw "$BDEV" "$T/mnt/card" 2>/dev/null ||
				problem="its filesystem can't be mounted (format it FAT32 or exFAT on your PC)"
			if [ -z "$problem" ]; then
				_free=$(df -k "$T/mnt/card" | awk 'NR == 2 { print int($4 / 1048576) }')
				[ "$_free" -ge "$NEED_GB" ] || problem="it has $_free GB free; $NEED_GB GB is needed"
			fi
		fi
		[ -z "$problem" ] && break
		grep -q " $T/mnt/card " /proc/mounts && umount "$T/mnt/card"
		[ -n "$CARD_WANT" ] && die "card not usable: $problem"
		say "This card won't do: $problem."
		say "Take it out and insert another (Ctrl-C to stop)."
		while [ -n "$(disk_of $SDC)" ]; do sleep 1; done
	done
fi

# The summary and the one confirmation.
step "About to"
n=1
if [ "$TARGET" = sd ]; then
	say "$n. ERASE the SD card ($NAME, $SIZE_GB GB, ID $CID) and partition it for BasedOS"; n=$((n + 1))
fi
if [ "$BACKUP" = yes ]; then
	say "$n. back up the whole eMMC to the card (about 4 GB; stock's frontend stops while it copies)"; n=$((n + 1))
fi
[ "$TARGET" != backup ] && { say "$n. copy BasedOS's vendor set from this device's stock firmware (read only)"; n=$((n + 1)); }
if [ "$TARGET" = backup ]; then
	say "Nothing else: no install, and nothing on the card is erased."
	WORD=BACKUP
elif [ "$TARGET" = sd ]; then
	say "$n. write BasedOS $VERSION to the card. The eMMC isn't written."
	WORD=ERASE
else
	say "$n. install BasedOS $VERSION on the eMMC next to stock (stock's files stay; its boot script is kept)"
	WORD=INSTALL
fi
if [ -z "$YES" ]; then
	ask "Type $WORD to go ahead (anything else stops):" _a
	[ "$_a" = "$WORD" ] || die "not confirmed; nothing was written"
else
	[ -n "$CARD" ] && [ -z "$CARD_WANT" ] && die "--yes needs --card <ID> when a card is written"
fi

# ---------------------------------------------------------------------------------------------
# Phase 2: no more questions.

# put <src> <dst>: written as <dst>.new, synced, re-read (not from the page cache) and compared,
# then renamed.
put() {
	cp "$1" "$2.new" && sync && echo 3 > /proc/sys/vm/drop_caches &&
		[ "$(md5sum < "$1")" = "$(md5sum < "$2.new")" ] && mv "$2.new" "$2" && sync ||
		{ rm -f "$2.new"; die "couldn't write $2"; }
}

# The SD card's partitions first (an SD install's backup goes onto its BASEOS partition).
if [ "$TARGET" = sd ]; then
	step "Partitioning the card"
	for m in $(awk -v d="/dev/$CARD" 'index($1, d) == 1 { print $2 }' /proc/mounts); do umount "$m" || die "can't unmount $m"; done
	D=/dev/$CARD
	sgdisk --zap-all "$D" >/dev/null 2>&1
	# basedos: FAT, 1 GiB, U-Boot's (legacy BIOS bootable, bit 2) and hidden (62, 63); data: ext4,
	# 512 MiB, hidden; BASEOS: the rest.
	sgdisk -n 1:1MiB:+1GiB -t 1:0700 -c 1:basedos -A 1:set:2 -A 1:set:62 -A 1:set:63 \
		-n 2:0:+512MiB -t 2:8300 -c 2:data -A 2:set:62 -A 2:set:63 \
		-n 3:0:0 -t 3:0700 -c 3:BASEOS "$D" >/dev/null || die "sgdisk failed"
	partprobe "$D" 2>/dev/null
	_i=0; while [ ! -b ${D}p3 ] && [ $_i -lt 20 ]; do sleep 0.5; _i=$((_i + 1)); done
	[ -b ${D}p3 ] || die "the new partitions didn't appear"
	# Stock's automounter may pick the new partitions up; ours are mounted where this script says.
	sleep 2
	for m in $(awk -v d="$D" 'index($1, d) == 1 { print $2 }' /proc/mounts); do umount "$m"; done
	mkfs.vfat -F 32 -n BASEDOS ${D}p1 >/dev/null || die "mkfs.vfat p1 failed"
	mkfs.ext4 -q -F -L basedos-data ${D}p2 || die "mkfs.ext4 p2 failed"
	mkfs.vfat -F 32 -n BASEOS ${D}p3 >/dev/null || die "mkfs.vfat p3 failed"
	mkdir -p "$T/mnt/p1" "$T/mnt/p2" "$T/mnt/card"
	mount -t vfat ${D}p1 "$T/mnt/p1" && mount -t ext4 ${D}p2 "$T/mnt/p2" && mount -t vfat ${D}p3 "$T/mnt/card" ||
		die "the new partitions don't mount"
	say "basedos (1 GiB), data (512 MiB), BASEOS ($(df -h "$T/mnt/card" | awk 'NR == 2 { print $2 }'))"
fi

if [ "$BACKUP" = yes ]; then
	step "Backing up the eMMC"
	STOCK_DESC=$(. /etc/os-release 2>/dev/null; _b=${BUILD_ID:-unknown}; echo "stock ${OS_NAME:-?} ${OS_VERSION:-?} ($(echo "$_b" | cut -c1-7))")
	BK=$T/mnt/card/basedos-emmc-backup-$(date +%Y%m%d-%H%M)
	mkdir -p "$BK" || die "can't write $BK"
	if systemctl is-active -q essway 2>/dev/null; then systemctl stop essway; ES_STOPPED=1; fi
	sync
	w0=$(awk '{ print $5 }' /sys/block/$EMMC/${EMMC}p2/stat)
	for b in boot0 boot1; do dd if=/dev/${EMMC}$b of="$BK/${EMMC}$b.img" bs=1M 2>/dev/null || die "couldn't read ${EMMC}$b"; done
	parted -s /dev/$EMMC unit s print > "$BK/partitions.txt" 2>/dev/null
	say "reading the eMMC ($(( $(cat /sys/block/$EMMC/size) / 2097152 )) GB) and compressing it..."
	# The MD5 of exactly what was read, taken on the way (a FIFO): the backup is checked against
	# that, not a second read, which stock's own writes in between could make differ.
	rm -f "$T/fifo"; mkfifo "$T/fifo"
	md5sum < "$T/fifo" | cut -c1-32 > "$T/read.md5" &
	dd if=/dev/$EMMC bs=4M 2>/dev/null | tee "$T/fifo" | zstd -3 -T0 -q -c | busybox split -b 2000m -a 2 - "$BK/$EMMC.img.zst." ||
		die "the backup didn't complete"
	wait
	w1=$(awk '{ print $5 }' /sys/block/$EMMC/${EMMC}p2/stat)
	[ -n "${ES_STOPPED:-}" ] && systemctl start essway; ES_STOPPED=""
	sync
	echo 3 > /proc/sys/vm/drop_caches
	say "checking the backup (reading it back from the card)..."
	want=$(cat "$T/read.md5")
	got=$(cat "$BK/$EMMC.img.zst."* | zstd -dc -q | md5sum | cut -c1-32)
	rm -f "$T/fifo" "$T/read.md5"
	[ ${#want} -eq 32 ] && [ "$want" = "$got" ] || die "the backup on the card doesn't read back as the eMMC was read"
	(cd "$BK" && sha256sum * > SHA256SUMS)
	echo "$want  $EMMC.img" > "$BK/$EMMC.img.md5"
	cat > "$BK/README.txt" <<EOF
GKD 350H Ultra eMMC backup, $(date), $STOCK_DESC, made by basedos-setup.

$EMMC.img.zst.aa, .ab, ...   the whole eMMC ($EMMC.img), zstd-compressed, in 2 GB parts. Join
                   them in order (aa, ab, ac, ...) before decompressing:
                     Windows:  copy /b $EMMC.img.zst.aa + $EMMC.img.zst.ab + ... $EMMC.img.zst
                     Linux:    cat $EMMC.img.zst.* > $EMMC.img.zst
                   then  zstd -d $EMMC.img.zst  gives $EMMC.img (md5 in $EMMC.img.md5).
${EMMC}boot0.img, ${EMMC}boot1.img   the eMMC's hardware boot areas.
partitions.txt     the partition table, as parted printed it.
SHA256SUMS         every file here.

To restore, write $EMMC.img over the whole eMMC: see BasedOS's docs/recovery.md (maskrom mode,
or from a rescue card). Keep this folder somewhere safe (copy it to your PC).
EOF
	[ "$w0" = "$w1" ] || say "NOTE: stock's data partition was written to during the copy ($w0 -> $w1 sectors written): the image is the eMMC as it was read, and may differ there from the eMMC now."
	sync
	say "saved in $(basename "$BK") on the card"
fi

if [ "$TARGET" = backup ]; then
	cleanup
	step "Done"
	say "The eMMC backup is on the card in $(basename "$BK")/. Keep the card, or copy the folder to your PC."
	exit 0
fi

step "Copying the vendor set from stock"
mount -t squashfs -o ro,loop "$STOCK_P1/SYSTEM" "$T/mnt/stock" || die "$STOCK_P1/SYSTEM does not mount"
V=$T/vendor
rm -rf "$V"; mkdir -p "$V"
_n=0
while read -r _k _a _b _c _d; do
	case "$_k" in
	F)
		case "$_d" in p1:*) _src=$STOCK_P1/${_d#p1:} ;; *) _src=$T/mnt/stock/$_d ;; esac
		mkdir -p "$V/${_c%/*}"
		cp "$_src" "$V/$_c" 2>/dev/null || die "stock has no $_d"
		[ "$(sha256sum < "$V/$_c" | cut -c1-64)" = "$_b" ] || die "$_d isn't the file this release expects"
		chmod "$_a" "$V/$_c"; _n=$((_n + 1)) ;;
	L)
		mkdir -p "$V/${_a%/*}"; ln -s "$_b" "$V/$_a"; _n=$((_n + 1)) ;;
	esac
done < "$RECIPE"
umount "$T/mnt/stock"
. "$R/usr/lib/basedos/vendor-id"
[ "$(vendor_id "$V")" = "$VENDOR" ] || die "the copied files don't give vendor set $VENDOR"
mkdir -p "$V/usr/share/basedos"
printf 'VENDOR_ID=%s\nSTOCK_BUILD=%s\n' "$VENDOR" "$STOCK_BUILD" > "$V/usr/share/basedos/vendor-release"
chmod 755 "$V"
# BasedOS's own mksquashfs, from this release (the same as the PC build's), with its libraries.
"$R/usr/lib/ld-linux-aarch64.so.1" --library-path "$R/usr/lib" "$R/usr/bin/mksquashfs" "$V" "$T/vendor.squashfs" \
	-noappend -all-root -comp zstd -Xcompression-level 15 -b 256K -quiet -no-progress -e boot || die "mksquashfs failed"
VS=$T/vendor-$VENDOR
rm -rf "$VS"; mkdir -p "$VS"
cp "$V"/boot/* "$VS/" && mv "$T/vendor.squashfs" "$VS/vendor.squashfs" || die "couldn't stage the vendor set"
rm -rf "$V"
say "vendor set $VENDOR ($_n files from stock $STOCK_BUILD)"

if [ "$TARGET" = sd ]; then
	step "Writing BasedOS to the card"
	P=$T/mnt/p1
	mkdir -p "$P/basedos/vendor-$VENDOR"
	for f in "$VS"/*; do put "$f" "$P/basedos/vendor-$VENDOR/${f##*/}"; done
	put "$HERE/rootfs.squashfs" "$P/basedos/rootfs.squashfs"
	put "$HERE/initrd.uimg" "$P/basedos/initrd.uimg"
	echo "basedos_vendor=$VENDOR" > "$T/boot.env"; put "$T/boot.env" "$P/basedos/boot.env"
	put "$HERE/boot.scr" "$P/boot.scr"
	mkdir -p "$T/mnt/p2/basedos-data"
	cat > "$T/mnt/card/BasedOS.txt" <<EOF
This card runs BasedOS $VERSION ($BUILD) on the GKD 350H Ultra: with it in, the device starts
BasedOS and the frontend on this drive; without it, stock.

Put your frontend here, on this BASEOS drive (for spruce: copy spruce's files to it from your
PC). BasedOS's own files are on the card's hidden partitions: don't reformat the card, or it
stops being a BasedOS card.
EOF
	sync
	for m in p1 p2 card; do umount "$T/mnt/$m" || die "can't unmount the card's $m"; done
	RESULT="BasedOS $VERSION is on the card. Next: copy your frontend (spruce) onto the BASEOS drive from your PC, put the card in, and restart."
else
	step "Installing BasedOS on the eMMC"
	mount -o remount,rw $STOCK_P1 || die "can't write $STOCK_P1"
	B=$STOCK_P1/basedos
	mkdir -p "$B/vendor-$VENDOR"
	dd if=$STOCK_P1/boot.scr bs=64 skip=1 2>/dev/null | grep -q "rdinit=/basedos/init" &&
		die "$STOCK_P1/boot.scr is BasedOS's, but there's no BasedOS folder: put stock's back first"
	put $STOCK_P1/boot.scr "$B/boot.scr.stock"
	for f in "$VS"/*; do put "$f" "$B/vendor-$VENDOR/${f##*/}"; done
	put "$HERE/rootfs.squashfs" "$B/rootfs.squashfs"
	put "$HERE/initrd.uimg" "$B/initrd.uimg"
	echo "basedos_vendor=$VENDOR" > "$T/boot.env"; put "$T/boot.env" "$B/boot.env"
	# BasedOS's boot script last: it switches the device over.
	put "$HERE/boot.scr" $STOCK_P1/boot.scr
	mount -o remount,ro $STOCK_P1
	DATA=/storage/basedos-data
	mkdir -p $DATA/ssh; chmod 700 $DATA/ssh
	for k in /storage/.cache/ssh/ssh_host_ed25519_key /storage/.cache/ssh/ssh_host_rsa_key; do
		[ -f $k ] && [ ! -f $DATA/ssh/${k##*/} ] && cp $k $k.pub $DATA/ssh/ 2>/dev/null
	done
	chmod 600 $DATA/ssh/*_key 2>/dev/null
	if [ ! -f $DATA/wpa_supplicant.conf ]; then
		(umask 077
		{
			echo "ctrl_interface=/run/wpa_supplicant"
			echo "update_config=0"
			for s in /storage/.cache/connman/wifi_*/settings; do
				[ -f "$s" ] || continue
				name=$(sed -n 's/^Name=//p' "$s" | head -1)
				ssid=$(sed -n 's/^SSID=//p' "$s" | head -1)
				pass=$(sed -n 's/^Passphrase=//p' "$s" | head -1)
				[ -n "$ssid" ] || continue
				if [ -n "$pass" ]; then
					psk=$(wpa_passphrase "$name" "$pass" | sed -n 's/^[[:space:]]*psk=\([0-9a-f]\{64\}\)$/\1/p')
					[ -n "$psk" ] && printf 'network={\n\tssid=%s\n\tpsk=%s\n}\n' "$ssid" "$psk"
				else
					printf 'network={\n\tssid=%s\n\tkey_mgmt=NONE\n}\n' "$ssid"
				fi
			done
		} > $DATA/wpa_supplicant.conf)
	fi
	sync
	RESULT="BasedOS $VERSION is installed next to stock. Restart to start it."
fi

rm -rf "$VS" "$T/boot.env" "$T/mismatch"
cleanup
step "Done"
say "$RESULT"
[ "$BACKUP" = yes ] && say "The eMMC backup is on the card in basedos-emmc-backup-*/: copy it to your PC and keep it."
exit 0
