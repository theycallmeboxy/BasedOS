#!/bin/sh
# basedos-setup: set up BasedOS on a GKD 350H Ultra. Run it ON the device, under stock ROCKNIX,
# over SSH (ssh root@<device>; stock's root has no password), from the BasedOS release folder:
#
#   sh basedos-setup.sh
#
# Three choices:
#
#   1. Install BasedOS to the eMMC, next to stock (stock's files stay; BasedOS's maintenance menu
#      can switch back or uninstall). It recommends making a recovery card (3) first, and offers
#      to, in the same run.
#   2. Create a BasedOS SD card: BasedOS on the card alone; the eMMC is NOT modified. Partitions:
#      basedos (boot files, hidden), data (BasedOS's /data, hidden), BASEOS (the rest: the drive
#      the frontend, spruce, is copied to later from a PC). Optionally a copy of stock on the card
#      too (dual boot: the maintenance menu starts it once), and a backup of the eMMC on BASEOS.
#   3. Create a recovery SD card: a backup of the whole eMMC as it is now, and a small recovery
#      system that boots from the card and, when A is held, writes the eMMC back byte for byte
#      (tools/recovery). No PC needed, then or later.
#
# It asks everything first, shows what it will do and asks for the typed confirmations; only then
# does it write anything, and it runs to the end without asking more.
#
# For an install, the vendor set (the stock kernel, DTBs, modules, firmware and GPU drivers BasedOS
# runs on; docs/plan.md, Architecture) is harvested here from stock's own files, by the recipe in
# this release, with every file's hash checked: stock files are never in a release.
#
# Not interactive: --target emmc|sd|recovery, and
#   emmc: --recovery-card or --no-recovery-card
#   sd:   --dual-boot or --no-dual-boot, --backup or --no-backup
#   any card: --card <CID> (the card's ID, as shown)
# and --yes. Every check still runs, and the card must have that ID.
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
STOCK_P1=/flash
T=/tmp/basedos-setup            # RAM: nothing of setup's own goes on the eMMC
SDC=2a310000.mmc                # the SD slot's controller
EMMCC=2a330000.mmc              # the eMMC's
GiB=1073741824

TARGET="" REC="" DUAL="" BACKUP="" CARD_WANT="" YES=""
while [ $# -gt 0 ]; do
	case "$1" in
	--target) TARGET=$2; shift ;;
	--recovery-card) REC=yes ;;
	--no-recovery-card) REC=no ;;
	--dual-boot) DUAL=yes ;;
	--no-dual-boot) DUAL=no ;;
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
	for m in $(awk -v t="$T/mnt/" 'index($2, t) == 1 { print $2 }' /proc/mounts | sort -r); do umount "$m" 2>/dev/null; done
	[ -n "${UDEV_HELD:-}" ] && udevadm control --start-exec-queue 2>/dev/null
	UDEV_HELD=""
	[ -n "${ES_STOPPED:-}" ] && systemctl start essway 2>/dev/null
	ES_STOPPED=""
}
trap 'cleanup' INT TERM
ask() {  # ask <prompt> <var>
	printf '%s ' "$1"
	read -r "$2" || die "no answer (run it from an SSH terminal, or use the options)"
}
yes_no() {  # yes_no <question> <default y|n>: 0 for yes
	if [ "$2" = y ]; then ask "$1 [Y/n]:" _yn; case "$_yn" in n|N|no|No) return 1 ;; esac; return 0; fi
	ask "$1 [y/N]:" _yn; case "$_yn" in y|Y|yes|Yes) return 0 ;; esac; return 1
}
confirm() {  # confirm <word> <what>: the typed confirmation
	if [ -n "$YES" ]; then return 0; fi
	ask "Type $1 to $2 (anything else stops):" _a
	[ "$_a" = "$1" ] || die "not confirmed; nothing was written"
}

# disk_of <controller>: the mmcblk disk on it.
disk_of() {
	for b in /sys/block/mmcblk*; do
		case "$b" in *boot*|*rpmb*) continue ;; esac
		case "$(readlink -f "$b")" in */$1/*) echo "${b##*/}"; return ;; esac
	done
}
kib_used() { df -k "$1" | awk 'NR == 2 { print $3 }'; }
# kib_except <dir> <name>...: KiB in <dir>, without the named top-level entries.
kib_except() {
	_d=$1; shift
	_t=0
	for _e in "$_d"/* "$_d"/.[!.]*; do
		[ -e "$_e" ] || continue
		_n=${_e##*/}; _skip=""
		for _x in "$@"; do [ "$_n" = "$_x" ] && _skip=1; done
		[ -n "$_skip" ] || _t=$((_t + $(du -sk "$_e" | cut -f1)))
	done
	echo $_t
}
gib_up() { echo $(( ($1 + 1048575) / 1048576 )); }   # KiB -> whole GiB, rounded up

# ---------------------------------------------------------------------------------------------
# Phase 1: checks and questions. Nothing is written.

step "Checking"
[ "$(id -u)" = 0 ] || die "run it as root (ssh root@<device>)"
EMMC=$(disk_of $EMMCC)
[ "$EMMC" = mmcblk0 ] || die "this doesn't look like a GKD 350H Ultra (no eMMC at mmcblk0)"
grep -q "^/dev/${EMMC}p1 $STOCK_P1 " /proc/mounts || die "run it on stock ROCKNIX ($STOCK_P1 isn't the eMMC's p1)"
STOCK_DESC=$(. /etc/os-release 2>/dev/null; _b=${BUILD_ID:-unknown}; echo "stock ${OS_NAME:-?} ${OS_VERSION:-?} ($(echo "$_b" | cut -c1-7))")
say "$STOCK_DESC, eMMC $(( $(cat /sys/block/$EMMC/size) / 2097152 )) GB"

if [ -z "$TARGET" ]; then
	say ""
	say "What do you want to do?"
	say "  1) Install BasedOS to the eMMC, next to stock"
	say "  2) Create a BasedOS SD card (the eMMC is not modified)"
	say "  3) Create a recovery SD card (it can restore the eMMC to how it is now, byte for byte)"
	ask "Choose 1, 2 or 3:" _a
	case "$_a" in 1) TARGET=emmc ;; 2) TARGET=sd ;; 3) TARGET=recovery ;; *) die "no choice made" ;; esac
fi
case "$TARGET" in emmc|sd|recovery) ;; *) die "--target must be emmc, sd or recovery" ;; esac

if [ "$TARGET" = emmc ]; then
	[ -d "$STOCK_P1/basedos" ] &&
		die "BasedOS is already on the eMMC; uninstall it first (BasedOS's maintenance menu: hold Select at power-on)"
	if [ -z "$REC" ]; then
		say ""
		say "This changes the built-in eMMC. Making a recovery card first is recommended: it boots"
		say "on its own and can put the eMMC back exactly as it is now, without a PC."
		if yes_no "Make a recovery card first?" y; then REC=yes; else REC=no; fi
	fi
fi
[ "$TARGET" = recovery ] && REC=yes
[ "$TARGET" = emmc ] || [ "$REC" = yes ] || REC=no

if [ "$TARGET" = sd ]; then
	say ""
	say "BasedOS goes on the SD card alone. THE eMMC WILL NOT BE MODIFIED: without the card the"
	say "device starts stock, as now. Your frontend (spruce) is copied later, from your PC, to the"
	say "card's BASEOS drive."
	if [ -z "$DUAL" ]; then
		say ""
		say "Dual boot: a copy of stock goes on the card too, and BasedOS's maintenance menu (hold"
		say "Select at power-on) can start it once, from the card, whatever is on the eMMC."
		if yes_no "Dual boot stock from the card?" n; then DUAL=yes; else DUAL=no; fi
	fi
	if [ -z "$BACKUP" ]; then
		say ""
		say "A backup image of the eMMC (stock, as it is now) can go on the card's BASEOS drive,"
		say "for you to copy to your PC."
		if yes_no "Save a backup image of stock?" n; then BACKUP=yes; else BACKUP=no; fi
	fi
else
	DUAL=no
	BACKUP=$REC
fi

# The release: BasedOS for an install, the recovery files for a recovery card.
need=""
[ "$TARGET" != recovery ] && need="rootfs.squashfs initrd.uimg boot.scr"
[ "$REC" = yes ] && need="$need recovery-initrd.uimg recovery.scr"
for f in $need; do
	[ -s "$HERE/$f" ] || die "the release folder ($HERE) has no $f"
done
if [ "$TARGET" != recovery ]; then
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

# Sizes, in GiB. The backup: about what's in use on the eMMC's filesystems, compressed, with room
# to spare (the real size is known only once it's made; a card that fills up stops it cleanly).
BK_GB=$(( $(gib_up $(( $(kib_used $STOCK_P1) + $(kib_used /storage) ))) + 1 ))
# Dual boot: stock's boot files (all of p1 but BasedOS's) and a copy of its /storage (not its
# ROMs), each with room to grow.
STOCK_KIB=0 STORE_KIB=0
if [ "$DUAL" = yes ]; then
	STOCK_KIB=$(kib_except $STOCK_P1 basedos)
	STORE_KIB=$(kib_except /storage games-external roms basedos-data)
fi
P1_MIB=1024 P2_MIB=512
[ "$DUAL" = yes ] && P1_MIB=$(( 1024 + $(gib_up $STOCK_KIB) * 1024 )) && P2_MIB=$(( 512 + 2048 + $(gib_up $STORE_KIB) * 1024 ))
case "$TARGET" in
recovery|emmc) NEED_GB=$BK_GB ;;
sd)
	NEED_GB=$(( (P1_MIB + P2_MIB) / 1024 + 2 ))
	[ "$BACKUP" = yes ] && NEED_GB=$((NEED_GB + BK_GB)) ;;
esac

# The card, if there's to be one. Every card this makes is erased first.
CARD=""
if [ "$TARGET" = sd ] || [ "$REC" = yes ]; then
	if [ "$TARGET" = sd ]; then WHAT="The BasedOS card"; else WHAT="The recovery card"; fi
	say ""
	say "$WHAT needs an SD card of at least $NEED_GB GB. ALL DATA ON IT WILL BE LOST."
	while :; do
		CARD=$(disk_of $SDC)
		if [ -z "$CARD" ]; then
			say "Insert the card. (waiting for a card; Ctrl-C to stop)"
			while [ -z "$(disk_of $SDC)" ]; do sleep 1; done
			sleep 2
			CARD=$(disk_of $SDC)
		fi
		CID=$(cat /sys/block/$CARD/device/cid)
		SIZE_GB=$(( $(cat /sys/block/$CARD/size) / 2097152 ))
		NAME="$(cat /sys/block/$CARD/device/name 2>/dev/null) ($(cat /sys/block/$CARD/device/manfid 2>/dev/null))"
		say ""
		say "Card: $NAME, $SIZE_GB GB, ID $CID. On it now:"
		blkid /dev/${CARD}p* 2>/dev/null | sed 's/^/  /'
		problem=""
		[ -n "$CARD_WANT" ] && [ "$CID" != "$CARD_WANT" ] && problem="it isn't the card --card names ($CARD_WANT)"
		[ -z "$problem" ] && [ "$(cat /sys/block/$CARD/device/type 2>/dev/null)" != SD ] && problem="it isn't an SD card"
		[ -z "$problem" ] && [ "$SIZE_GB" -lt "$NEED_GB" ] && problem="it's $SIZE_GB GB; at least $NEED_GB GB is needed"
		[ -z "$problem" ] && break
		[ -n "$CARD_WANT" ] && die "card not usable: $problem"
		say "This card won't do: $problem."
		say "Take it out and insert another (Ctrl-C to stop)."
		while [ -n "$(disk_of $SDC)" ]; do sleep 1; done
	done
fi

# Enough charge to finish: 30 %, or the charger in.
_cap="" _chg=""
for _p in /sys/class/power_supply/*; do
	case "$(cat $_p/type 2>/dev/null)" in
	Battery)
		_cap=$(cat $_p/capacity 2>/dev/null)
		case "$(cat $_p/status 2>/dev/null)" in Charging|Full) _chg=1 ;; esac ;;
	*) [ "$(cat $_p/online 2>/dev/null)" = 1 ] && _chg=1 ;;
	esac
done
[ -n "$_chg" ] || [ -z "$_cap" ] || [ "$_cap" -ge 30 ] || die "the battery is at $_cap %: charge it, or plug the charger in"

# The summary and the confirmations.
step "About to"
if [ "$REC" = yes ]; then
	say "Recovery card: ERASE the SD card ($NAME, $SIZE_GB GB, ID $CID), back up the whole eMMC"
	say "  onto it (about $BK_GB GB at most; stock's frontend stops while it copies), and make it"
	say "  boot into the restore screen. Keep it safe; it needs no PC."
	[ -d "$STOCK_P1/basedos" ] && say "  NOTE: BasedOS is on the eMMC now: the card restores the eMMC with it, as it is."
fi
if [ "$TARGET" = sd ]; then
	say "BasedOS card: ERASE the SD card ($NAME, $SIZE_GB GB, ID $CID) and put BasedOS $VERSION on it:"
	say "  basedos $((P1_MIB / 1024)) GB and data $((P2_MIB / 1024)).$((P2_MIB % 1024 * 10 / 1024)) GB (both hidden), BASEOS the rest."
	[ "$DUAL" = yes ] && say "  With a copy of stock (dual boot): its boot files and its /storage, without ROMs."
	[ "$BACKUP" = yes ] && say "  With a backup image of the eMMC on BASEOS (about $BK_GB GB at most)."
	say "  THE eMMC IS NOT MODIFIED."
fi
if [ "$TARGET" = emmc ]; then
	say "eMMC: install BasedOS $VERSION on the built-in eMMC, next to stock. Stock's files stay; its"
	say "  boot script is replaced by BasedOS's, and kept. THE eMMC WILL BE MODIFIED."
	[ "$REC" = yes ] && say "  This happens only after the recovery card is made and checked."
fi
say ""
[ -n "$YES" ] && [ -n "$CARD" ] && [ -z "$CARD_WANT" ] && die "--yes needs --card <ID> when a card is written"
[ -n "$CARD" ] && confirm ERASE "erase the card ($SIZE_GB GB, ID $CID)"
if [ "$TARGET" = emmc ]; then
	say ""
	say "Installing to the eMMC changes the device's built-in storage. If something goes wrong, the"
	say "device may not start until it's restored$([ "$REC" = yes ] && echo " (with the recovery card)" || echo " (from a backup: docs/recovery.md)")."
	confirm INSTALL "confirm that you understand the eMMC will be modified, you know the risks, and you have a backup"
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

# Stock's frontend stops while this runs (the backup reads a quiet eMMC; nothing competes), and
# stock's automounter is held off the card while it's rebuilt.
if systemctl is-active -q essway 2>/dev/null; then systemctl stop essway; ES_STOPPED=1; fi
if [ -n "$CARD" ]; then
	udevadm control --stop-exec-queue && UDEV_HELD=1
	for m in $(awk -v d="/dev/$CARD" 'index($1, d) == 1 { print $2 }' /proc/mounts | sort -r); do
		umount "$m" || die "can't unmount $m"
	done
	D=/dev/$CARD
fi

# new_parts <count>: wait for the card's new partitions.
new_parts() {
	partprobe "$D" 2>/dev/null
	_i=0; while [ ! -b ${D}p$1 ] && [ $_i -lt 20 ]; do sleep 0.5; _i=$((_i + 1)); done
	[ -b ${D}p$1 ] || die "the new partitions didn't appear"
}

# backup_emmc <dir on the card>: the whole eMMC, zstd in 2 GB parts, checked against an MD5 taken
# while reading, with its boot areas, its partition table, backup.info (what the recovery card
# checks) and SHA256SUMS. BK is the folder made.
backup_emmc() {
	step "Backing up the eMMC"
	BK=$1/basedos-emmc-backup-$(date +%Y%m%d-%H%M)
	mkdir -p "$BK" || die "can't write $BK"
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
		die "the backup didn't complete (is the card full?)"
	wait
	w1=$(awk '{ print $5 }' /sys/block/$EMMC/${EMMC}p2/stat)
	sync
	echo 3 > /proc/sys/vm/drop_caches
	say "checking the backup (reading it back from the card)..."
	want=$(cat "$T/read.md5")
	got=$(cat "$BK/$EMMC.img.zst."* | zstd -dc -q | md5sum | cut -c1-32)
	rm -f "$T/fifo" "$T/read.md5"
	[ ${#want} -eq 32 ] && [ "$want" = "$got" ] || die "the backup on the card doesn't read back as the eMMC was read"
	echo "$want  $EMMC.img" > "$BK/$EMMC.img.md5"
	cat > "$BK/backup.info" <<EOF
IMG=$EMMC.img
IMG_MD5=$want
EMMC_CID=$(cat /sys/block/$EMMC/device/cid)
EMMC_SECTORS=$(cat /sys/block/$EMMC/size)
DATE=$(date '+%Y-%m-%d %H:%M')
STOCK=$STOCK_DESC$([ -d "$STOCK_P1/basedos" ] && echo ", with BasedOS")
EOF
	cat > "$BK/README.txt" <<EOF
GKD 350H Ultra eMMC backup, $(date), $STOCK_DESC, made by basedos-setup.

$EMMC.img.zst.aa, .ab, ...   the whole eMMC ($EMMC.img), zstd-compressed, in 2 GB parts. Join
                   them in order (aa, ab, ac, ...) before decompressing:
                     Windows:  copy /b $EMMC.img.zst.aa + $EMMC.img.zst.ab + ... $EMMC.img.zst
                     Linux:    cat $EMMC.img.zst.* > $EMMC.img.zst
                   then  zstd -d $EMMC.img.zst  gives $EMMC.img (md5 in $EMMC.img.md5).
${EMMC}boot0.img, ${EMMC}boot1.img   the eMMC's hardware boot areas.
partitions.txt     the partition table, as parted printed it.
backup.info        what a BasedOS recovery card checks before restoring (this eMMC's ID and size).
SHA256SUMS         every file here.

On a BasedOS recovery card, the card restores it by itself. Otherwise, write $EMMC.img over the
whole eMMC: see BasedOS's docs/recovery.md (maskrom mode, or from a rescue card).
EOF
	(cd "$BK" && sha256sum $(ls | grep -v '^SHA256SUMS$') > SHA256SUMS)
	[ "$w0" = "$w1" ] || say "NOTE: stock's data partition was written to during the copy ($w0 -> $w1 sectors written): the image is the eMMC as it was read, and may differ there from the eMMC now."
	sync
	say "saved in $(basename "$BK") on the card"
}

# The recovery card: MBR, one FAT32 partition (U-Boot reads FAT, not exFAT), bootable.
if [ "$REC" = yes ]; then
	step "Making the recovery card"
	dd if=/dev/zero of="$D" bs=1M count=8 conv=fsync 2>/dev/null
	parted -s "$D" mklabel msdos mkpart primary fat32 1MiB 100% set 1 boot on || die "parted failed"
	new_parts 1
	mkfs.vfat -F 32 -n RECOVERY ${D}p1 >/dev/null || die "mkfs.vfat failed"
	mkdir -p "$T/mnt/card"
	mount -t vfat ${D}p1 "$T/mnt/card" || die "the new partition doesn't mount"
	C=$T/mnt/card
	backup_emmc "$C"
	mkdir -p "$C/recovery"
	# This device's own stock kernel and device trees (the recovery system runs on them).
	for f in Image rk3576-gkd-atom.dtb rk3576-gkd-atom-hdmi.dtb rk3576-gkd-atom-usbdp.dtb; do
		[ -f "$STOCK_P1/$f" ] || die "stock has no $STOCK_P1/$f"
		put "$STOCK_P1/$f" "$C/recovery/$f"
	done
	put "$HERE/recovery-initrd.uimg" "$C/recovery/initrd.uimg"
	basename "$BK" > "$T/backup"; put "$T/backup" "$C/recovery/backup"
	cat > "$C/RECOVERY.txt" <<EOF
BasedOS recovery card for one GKD 350H Ultra (eMMC ID $(cat /sys/block/$EMMC/device/cid)), made
$(date) by basedos-setup, from $STOCK_DESC.

With this card in, the device starts the restore screen instead of its own system. It checks the
backup, then puts the eMMC back exactly as it was when this card was made, but only once you hold
A for 5 seconds. B powers off without writing anything. Take the card out to start normally.

Keep this card as it is. $(basename "$BK")/ is the backup (its README.txt says how to restore it
from a PC as well).
EOF
	# Its boot script last: until it's there, the card doesn't boot.
	put "$HERE/recovery.scr" "$C/boot.scr"
	sync
	umount "$C" || die "can't unmount the recovery card"
	say "recovery card ready"
fi

# vendor_set: the vendor set harvested from this device's stock, in $VS.
vendor_set() {
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
}

# seed_data <BasedOS's data folder>: stock's SSH host keys and Wi-Fi networks, for BasedOS's own
# SSH and Wi-Fi (maintenance mode).
seed_data() {
	DATA=$1
	mkdir -p $DATA/ssh; chmod 700 $DATA/ssh
	for k in /storage/.cache/ssh/ssh_host_ed25519_key /storage/.cache/ssh/ssh_host_rsa_key; do
		[ -f $k ] && [ ! -f $DATA/ssh/${k##*/} ] && cp $k $k.pub $DATA/ssh/ 2>/dev/null
	done
	chmod 600 $DATA/ssh/*_key 2>/dev/null
	[ -f $DATA/wpa_supplicant.conf ] && return 0
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
}

if [ "$TARGET" = sd ]; then
	step "Partitioning the card"
	sgdisk --zap-all "$D" >/dev/null 2>&1
	# basedos: FAT, U-Boot's (legacy BIOS bootable, bit 2) and hidden (62, 63); data: ext4, hidden;
	# BASEOS: the rest. With dual boot, p1 and p2 also hold stock's files, as on the eMMC (stock's
	# init mounts the boot disk's p1 and p2).
	sgdisk -n 1:1MiB:+${P1_MIB}MiB -t 1:0700 -c 1:basedos -A 1:set:2 -A 1:set:62 -A 1:set:63 \
		-n 2:0:+${P2_MIB}MiB -t 2:8300 -c 2:data -A 2:set:62 -A 2:set:63 \
		-n 3:0:0 -t 3:0700 -c 3:BASEOS "$D" >/dev/null || die "sgdisk failed"
	new_parts 3
	mkfs.vfat -F 32 -n BASEDOS ${D}p1 >/dev/null || die "mkfs.vfat p1 failed"
	mkfs.ext4 -q -F -L basedos-data ${D}p2 || die "mkfs.ext4 p2 failed"
	mkfs.vfat -F 32 -n BASEOS ${D}p3 >/dev/null || die "mkfs.vfat p3 failed"
	mkdir -p "$T/mnt/p1" "$T/mnt/p2" "$T/mnt/card"
	mount -t vfat ${D}p1 "$T/mnt/p1" && mount -t ext4 ${D}p2 "$T/mnt/p2" && mount -t vfat ${D}p3 "$T/mnt/card" ||
		die "the new partitions don't mount"
	say "basedos ($P1_MIB MiB), data ($P2_MIB MiB), BASEOS ($(df -h "$T/mnt/card" | awk 'NR == 2 { print $2 }'))"
	[ "$BACKUP" = yes ] && backup_emmc "$T/mnt/card"
	vendor_set
	step "Writing BasedOS to the card"
	P=$T/mnt/p1
	if [ "$DUAL" = yes ]; then
		say "copying stock's boot files and its /storage (dual boot)..."
		for f in "$STOCK_P1"/*; do
			n=${f##*/}
			case "$n" in basedos|boot.scr|boot.scr.*) continue ;; esac
			if [ -d "$f" ]; then cp -a "$f" "$P/" || die "couldn't copy $f"
			else put "$f" "$P/$n"; fi
		done
		tar -C /storage --exclude=./games-external --exclude=./roms --exclude=./basedos-data -cf - . |
			tar -C "$T/mnt/p2" -xf - || die "couldn't copy stock's /storage"
		mkdir -p "$T/mnt/p2/games-external/roms" "$T/mnt/p2/roms"
		rm -f "$T/mnt/p2/.please_resize_me" "$T/mnt/p2/.please_resize_roms_partition"
	fi
	mkdir -p "$P/basedos/vendor-$VENDOR"
	for f in "$VS"/*; do put "$f" "$P/basedos/vendor-$VENDOR/${f##*/}"; done
	put "$HERE/rootfs.squashfs" "$P/basedos/rootfs.squashfs"
	put "$HERE/initrd.uimg" "$P/basedos/initrd.uimg"
	{ echo "basedos_vendor=$VENDOR"; [ "$DUAL" = yes ] && echo "basedos_card_stock=1"; } > "$T/boot.env"
	put "$T/boot.env" "$P/basedos/boot.env"
	mkdir -p "$T/mnt/p2/basedos-data"
	seed_data "$T/mnt/p2/basedos-data"
	cat > "$T/mnt/card/BasedOS.txt" <<EOF
This card runs BasedOS $VERSION ($BUILD) on the GKD 350H Ultra: with it in, the device starts
BasedOS and the frontend on this drive; without it, the device's own system on the eMMC.

Put your frontend here, on this BASEOS drive (for spruce: copy spruce's files to it from your
PC). BasedOS's own files are on the card's hidden partitions: don't reformat the card, or it
stops being a BasedOS card.
EOF
	# BasedOS's boot script last: until it's there, the card doesn't boot.
	put "$HERE/boot.scr" "$P/boot.scr"
	sync
	for m in card p2 p1; do umount "$T/mnt/$m" || die "can't unmount the card's $m"; done
	RESULT="BasedOS $VERSION is on the card. Power off now, copy your frontend (spruce) onto the card's BASEOS drive from your PC, put the card back in and power on."
	[ "$BACKUP" = yes ] && RESULT="$RESULT The eMMC backup is in $(basename "$BK")/ on BASEOS: copy it to your PC and keep it."
elif [ "$TARGET" = emmc ]; then
	vendor_set
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
	seed_data /storage/basedos-data
	sync
	if [ "$REC" = yes ]; then
		RESULT="BasedOS $VERSION is installed next to stock. Power off, take the recovery card out (keep it safe: with it in, the device starts the restore screen), and power on to start BasedOS."
	else
		RESULT="BasedOS $VERSION is installed next to stock. Restart to start it."
	fi
else
	RESULT="The recovery card is ready. Power off and take it out; keep it safe. To restore the eMMC: power off, put the card in, power on, and follow the screen."
fi

rm -rf "${VS:-$T/none}" "$T/boot.env" "$T/backup" "$T/mismatch"
# The card stays out of stock's automounter until the next power-on: released now, it would mount
# the new card's partitions and write to them.
[ -n "${UDEV_HELD:-}" ] && UDEV_HELD="" && say "(stock's automounter stays paused until the device restarts)"
cleanup
step "Done"
say "$RESULT"
exit 0
