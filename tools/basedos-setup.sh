#!/bin/sh
# basedos-setup: set up BasedOS on a GKD 350H Ultra. Run it ON the device, under stock ROCKNIX,
# over SSH (ssh -t root@<device>; stock's root has no password). The script on its own is enough:
# it reads its release's release.info first, and downloads the rest of the release (checked
# against the release's SHA256SUMS) only after you've confirmed. Nothing is needed on a PC:
#
#   wget -O /tmp/basedos-setup.sh <the release's basedos-setup.sh URL> && sh /tmp/basedos-setup.sh
#
# (Run from a folder that already holds the release files, it uses those instead.)
#
# Two choices:
#
#   1. Install BasedOS on the built-in storage (eMMC), next to stock (docs/plan.md,
#      Architecture): BasedOS's folder in stock's boot partition, its data in stock's data
#      partition, its boot script in place of stock's (kept). Stock's own files are used in place
#      (its kernel, device trees and SYSTEM) and never changed. A recovery card first is
#      recommended and offered in the same run.
#   2. Make a recovery SD card: a backup of the built-in storage as it is now, and a small recovery
#      system that starts from the card and puts it back (tools/recovery). It needs the device's
#      own bootloader to start (nothing on a card can replace that: a lost bootloader takes
#      maskrom and a PC, docs/recovery.md).
#
# It states its requirements first, checks every tool and stock's files, asks everything, shows a
# numbered summary and asks for the typed confirmations (capitals don't matter); only then does it
# download or write anything, and it runs to the end without asking more.
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
# The release this script belongs to (tools/wsl/release.sh writes it in).
RELEASE_TAG=@RELEASE_TAG@
RELEASE_URL=https://github.com/theycallmeboxy/BasedOS/releases/download/$RELEASE_TAG
STOCK_P1=/flash
T=/tmp/basedos-setup            # RAM: nothing of setup's own goes on the eMMC
DL=$T/release
SDC=2a310000.mmc                # the SD slot's controller
EMMCC=2a330000.mmc              # the eMMC's

# Colours, on a terminal only.
if [ -t 1 ]; then
	C_B=$(printf '\033[1m') C_DIM=$(printf '\033[2m') C_RED=$(printf '\033[1;31m') C_GRN=$(printf '\033[1;32m')
	C_YEL=$(printf '\033[1;33m') C_CYN=$(printf '\033[1;36m') C_0=$(printf '\033[0m')
else
	C_B="" C_DIM="" C_RED="" C_GRN="" C_YEL="" C_CYN="" C_0=""
fi
say() { printf '%s\n' "$*"; }
step() { printf '\n%s== %s%s\n' "$C_CYN" "$*" "$C_0"; }
ok() { printf '%s  ok%s  %s\n' "$C_GRN" "$C_0" "$*"; }
warn() { printf '%s  !!%s  %s\n' "$C_YEL" "$C_0" "$*"; }
item() { n=$((n + 1)); printf '  %s%d.%s %s\n' "$C_B" "$n" "$C_0" "$*"; }
die() {
	printf '\n%sSTOPPED:%s %s\n' "$C_RED" "$C_0" "$*" >&2
	cleanup
	grep -q " $T/" /proc/mounts || rm -rf "$T"
	exit 1
}
cleanup() {
	for m in $(awk -v t="$T/mnt/" 'index($2, t) == 1 { print $2 }' /proc/mounts | sort -r); do umount "$m" 2>/dev/null; done
	[ -n "${UDEV_HELD:-}" ] && udevadm control --start-exec-queue 2>/dev/null
	UDEV_HELD=""
	[ -n "${ES_STOPPED:-}" ] && systemctl start essway 2>/dev/null
	ES_STOPPED=""
}
trap 'cleanup' INT TERM
ask() {  # ask <prompt> <var>
	printf '%s%s%s ' "$C_B" "$1" "$C_0"
	read -r "$2" || die "no answer (run it from an SSH terminal: ssh -t)"
}
yes_no() {  # yes_no <question> <default y|n>: 0 for yes
	if [ "$2" = y ]; then ask "$1 [Y/n]:" _yn; case "$_yn" in n|N|no|No|NO) return 1 ;; esac; return 0; fi
	ask "$1 [y/N]:" _yn; case "$_yn" in y|Y|yes|Yes|YES) return 0 ;; esac; return 1
}
confirm() {  # confirm <word> <what>: the typed confirmation, in any capitals
	printf '%s' "$C_YEL"
	ask "Type $1 to $2 (capitals don't matter; anything else stops):" _a
	printf '%s' "$C_0"
	[ "$(printf '%s' "$_a" | tr a-z A-Z)" = "$1" ] || die "not confirmed; nothing was written"
}

# disk_of <controller>: the mmcblk disk on it.
disk_of() {
	for b in /sys/block/mmcblk*; do
		case "$b" in *boot*|*rpmb*) continue ;; esac
		case "$(readlink -f "$b")" in */$1/*) echo "${b##*/}"; return ;; esac
	done
}
kib_used() { df -k "$1" | awk 'NR == 2 { print $3 }'; }
mib_up() { echo $(( ($1 + 1023) / 1024 )); }                         # KiB -> MiB, rounded up
gb() { echo $(( ($1 * 1048576 + 999999999) / 1000000000 )); }        # MiB -> GB (as cards are sold)
# a_card <MiB>: "a 16 GB card", "an 8 GB card": the smallest common size that holds it (a card
# holds about 93 % of its label).
a_card() {
	for _c in 8 16 32 64 128 256; do
		[ $(( _c * 1000000000 * 93 / 100 / 1048576 )) -ge "$1" ] && break
	done
	case $_c in 8) echo "an $_c GB card" ;; *) echo "a $_c GB card" ;; esac
}
fetch() {  # fetch <url> <file>
	if command -v curl >/dev/null 2>&1; then curl -fsSL --retry 3 -o "$2" "$1"
	elif command -v wget >/dev/null 2>&1; then wget -q -O "$2" "$1"
	else return 1; fi
}
# release_file <name>: the release's file in $HERE, downloaded from the release into RAM when it
# isn't beside the script, checked against the release's SHA256SUMS either way.
release_file() {
	if [ ! -s "$HERE/$1" ]; then
		case "$RELEASE_TAG" in @*) die "this copy of the script belongs to no release: run it from a release folder" ;; esac
		[ "$HERE" = "$DL" ] || { HERE=$DL; rm -rf "$DL"; mkdir -p "$DL"; }
		[ -s "$DL/SHA256SUMS" ] || fetch "$RELEASE_URL/SHA256SUMS" "$DL/SHA256SUMS" ||
			die "can't download $RELEASE_URL/SHA256SUMS (is Wi-Fi up?)"
		fetch "$RELEASE_URL/$1" "$DL/$1" || die "can't download $RELEASE_URL/$1 (is Wi-Fi up?)"
	fi
	[ -s "$HERE/SHA256SUMS" ] || return 0
	_w=$(awk -v f="$1" '$2 == f || $2 == "*" f { print $1 }' "$HERE/SHA256SUMS")
	[ ${#_w} -eq 64 ] || die "the release's SHA256SUMS doesn't list $1"
	[ "$(sha256sum < "$HERE/$1" | cut -c1-64)" = "$_w" ] || die "$1 doesn't match the release's SHA256SUMS"
}

# ---------------------------------------------------------------------------------------------
# Phase 1: requirements, questions, the card, confirmations. Nothing is written or downloaded
# but release.info (a few KB).

step "Checking"
[ "$(id -u)" = 0 ] || die "run it as root (ssh -t root@<device>)"
EMMC=$(disk_of $EMMCC)
[ "$EMMC" = mmcblk0 ] || die "this doesn't look like a GKD 350H Ultra (no eMMC at mmcblk0)"
grep -q "^/dev/${EMMC}p1 $STOCK_P1 " /proc/mounts || die "run it on stock ROCKNIX ($STOCK_P1 isn't the eMMC's p1)"
rm -rf "$T"; mkdir -p "$T" || die "can't make $T"

# Every tool setup uses, before anything else (stock's own: a missing one stops it here, not
# halfway through).
miss=""
for c in awk sed tr cut sort grep head dd tee mkfifo md5sum sha256sum zstd parted partprobe blkid \
	mkfs.vfat udevadm systemctl wpa_passphrase mount umount df sync; do
	command -v $c >/dev/null 2>&1 || miss="$miss $c"
done
command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1 || miss="$miss curl-or-wget"
[ -z "$miss" ] || die "stock is missing tools setup needs:$miss"
ok "stock has every tool setup uses"

# This release, and the stock build it runs on: its BUILD_ID, then the files BasedOS boots and
# mounts in place (stock's kernel, DTBs, SYSTEM), each against release.info's SHA-256.
release_file release.info
INFO=$HERE/release.info
VERSION=$(sed -n 's/^VERSION=//p' "$INFO") BUILD=$(sed -n 's/^BUILD=//p' "$INFO")
STOCK_BUILD=$(sed -n 's/^STOCK_BUILD=//p' "$INFO" | tr -d '\r') STOCK_ID=$(sed -n 's/^STOCK_BUILD_ID=//p' "$INFO")
[ -n "$VERSION" ] && [ -n "$STOCK_ID" ] && grep -q '^P1 ' "$INFO" || die "release.info is incomplete"
HAVE_ID=$(sed -n 's/^BUILD_ID="\{0,1\}\([0-9a-f]*\)"\{0,1\}$/\1/p' /etc/os-release)
[ "$HAVE_ID" = "$STOCK_ID" ] ||
	die "this device's stock is build ${HAVE_ID:-unknown}; BasedOS $VERSION is made for $STOCK_BUILD ($STOCK_ID)"
say "checking stock's files (about half a minute)..."
grep '^P1 ' "$INFO" | while read -r _k _sha _f; do
	[ "$(sha256sum < "$STOCK_P1/$_f" 2>/dev/null | cut -c1-64)" = "$_sha" ] || { echo "$_f"; break; }
done > "$T/mismatch"
[ -s "$T/mismatch" ] && die "stock's $(cat "$T/mismatch") isn't the file BasedOS $VERSION is made for"
ok "stock $STOCK_BUILD: its kernel, device trees and SYSTEM are the ones BasedOS $VERSION is made for"

# Power: 30 %, or the charger in.
PCT="" CHG=""
for _p in /sys/class/power_supply/*; do
	case "$(cat $_p/type 2>/dev/null)" in
	Battery)
		PCT=$(cat $_p/capacity 2>/dev/null)
		case "$(cat $_p/status 2>/dev/null)" in Charging|Full) CHG=1 ;; esac ;;
	*) [ "$(cat $_p/online 2>/dev/null)" = 1 ] && CHG=1 ;;
	esac
done

# The recovery card's size: the backup, about what's in use on the eMMC's filesystems, compressed,
# with room to spare (the real size is known only once it's made; a card that fills up stops it
# cleanly), and the recovery files.
BK_MIB=$(( $(mib_up $(( $(kib_used $STOCK_P1) + $(kib_used /storage) ))) + 1024 ))
REC_MIB=$(( BK_MIB + 512 ))

say ""
say "${C_B}BasedOS $VERSION setup for the GKD 350H Ultra${C_0}$(case "$RELEASE_TAG" in @*) ;; *) echo " ${C_DIM}(release $RELEASE_TAG)${C_0}" ;; esac)"
say ""
say "${C_B}Before you start:${C_0}"
say "  - Stock ROCKNIX $(echo "$STOCK_BUILD" | sed 's/^rocknix-//'): this device has it."
if [ -n "$CHG" ]; then say "  - Power: the charger is in."
else say "  - Power: at least 30 % battery, or the charger plugged in (now ${PCT:-?} %)."; fi
say "  - Wi-Fi: setup downloads BasedOS (about 35 MB)."
say "  - For a recovery card: an SD card you can erase, of at least $(gb $REC_MIB) GB ($(a_card $REC_MIB) will do)."
say "    Everything on it is lost."
say "  - About 5 to 25 minutes. Don't power off or take the card out while it runs."
[ -n "$CHG" ] || [ -z "$PCT" ] || [ "$PCT" -ge 30 ] || die "the battery is at $PCT %: charge it, or plug the charger in, then run setup again"

INSTALLED=""
[ -d "$STOCK_P1/basedos" ] && INSTALLED=1
say ""
say "${C_B}What do you want to do?${C_0}"
if [ -n "$INSTALLED" ]; then
	say "  1) ${C_DIM}Install BasedOS: it's installed already (to reinstall, uninstall it first: its maintenance menu, hold Select at power-on)${C_0}"
else
	say "  1) Install BasedOS on the built-in storage, next to stock"
fi
say "  2) Make a recovery SD card (it can put the built-in storage back as it is now)"
ask "Choose 1 or 2:" _a
case "$_a" in
1) [ -z "$INSTALLED" ] || die "BasedOS is installed already: uninstall it first (its maintenance menu: hold Select at power-on)"
	TARGET=install ;;
2) TARGET=recovery ;;
*) die "no choice made" ;;
esac

REC=no
if [ "$TARGET" = install ]; then
	say ""
	say "This changes the built-in storage. A recovery card first is recommended: it starts on its"
	say "own and can put the built-in storage back as it is now, without a PC."
	yes_no "Make a recovery card first?" y && REC=yes
else
	REC=yes
fi

# The card, if there's to be one. It's erased first.
CARD=""
if [ "$REC" = yes ]; then
	NEED_GB=$(gb $REC_MIB)
	say ""
	say "The recovery card needs an SD card of at least $NEED_GB GB ($(a_card $REC_MIB) will do). ${C_B}Everything on it is lost.${C_0}"
	while :; do
		CARD=$(disk_of $SDC)
		if [ -z "$CARD" ]; then
			say "Insert the card. ${C_DIM}(waiting for a card; Ctrl-C to stop)${C_0}"
			while [ -z "$(disk_of $SDC)" ]; do sleep 1; done
			sleep 2
			CARD=$(disk_of $SDC)
		fi
		SIZE_MIB=$(( $(cat /sys/block/$CARD/size) / 2048 ))
		SIZE_GB=$(( $(cat /sys/block/$CARD/size) * 512 / 1000000000 ))
		_n=$(ls -d /sys/block/$CARD/${CARD}p* 2>/dev/null | wc -l)
		_l=$(blkid -s LABEL -o value /dev/${CARD}p* 2>/dev/null | tr '\n' ',' | sed 's/,$//; s/,/, /g')
		say ""
		if [ "$_n" -eq 0 ]; then say "Card: ${C_B}$SIZE_GB GB SD card${C_0}, empty."
		else say "Card: ${C_B}$SIZE_GB GB SD card${C_0}, with $_n partition$([ "$_n" -gt 1 ] && echo s)${_l:+ ($_l)}: it will be erased."; fi
		problem=""
		[ "$(cat /sys/block/$CARD/device/type 2>/dev/null)" != SD ] && problem="it isn't an SD card"
		[ -z "$problem" ] && [ "$SIZE_MIB" -lt "$REC_MIB" ] && problem="it's $SIZE_GB GB; at least $NEED_GB GB is needed"
		[ -z "$problem" ] && break
		warn "This card won't do: $problem."
		say "Take it out and insert another (Ctrl-C to stop)."
		while [ -n "$(disk_of $SDC)" ]; do sleep 1; done
	done
fi

# The summary and the confirmations.
step "About to"
n=0
if [ "$REC" = yes ]; then
	item "Erase the $SIZE_GB GB card."
	item "Back up the built-in storage onto it (up to $(gb $BK_MIB) GB)."
	item "Make it a recovery card."
	[ -n "$INSTALLED" ] && say "     ${C_DIM}(BasedOS is on the built-in storage now: the card would restore it as it is, with BasedOS.)${C_0}"
fi
if [ "$TARGET" = install ]; then
	item "Install BasedOS $VERSION on the built-in storage, next to stock."
	[ "$REC" = yes ] && say "     ${C_DIM}(Only after the recovery card is made and checked.)${C_0}"
fi
say ""
[ -n "$CARD" ] && confirm ERASE "erase this $SIZE_GB GB card"
if [ "$TARGET" = install ]; then
	say ""
	say "This modifies the device's built-in storage. If something goes wrong, the device may not start"
	say "until it's restored$([ "$REC" = yes ] && echo " with the recovery card" || echo " from a backup (docs/recovery.md)")."
	confirm INSTALL "confirm that you understand this, know the risks, and have a backup"
fi

# ---------------------------------------------------------------------------------------------
# Phase 2: no more questions.

# The rest of the release, now.
step "Getting BasedOS $VERSION"
if [ "$REC" = yes ]; then release_file recovery-initrd.uimg; release_file recovery.scr; fi
if [ "$TARGET" = install ]; then
	for f in rootfs.squashfs initrd.uimg boot.scr; do release_file $f; done
	mkdir -p "$T/mnt/rootfs"
	mount -t squashfs -o ro,loop "$HERE/rootfs.squashfs" "$T/mnt/rootfs" || die "$HERE/rootfs.squashfs does not mount"
	[ "$(cat "$T/mnt/rootfs/usr/share/basedos/needs-stock" 2>/dev/null)" = "$STOCK_ID" ] ||
		die "rootfs.squashfs isn't made for this stock build"
	umount "$T/mnt/rootfs"
fi
ok "downloaded and checked"

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

# backup_emmc <drive>: a full backup of the built-in storage's main area in <drive>/backup/, images
# only: GKD350HUltra-eMMC-<date>.img.zst.001, .002, ..., byte for byte from sector 0, in 2000 MiB
# pieces, each read straight from the eMMC (dd skip/count) and zstd-compressed on its own (zstd
# decompresses them back to back as one stream; every piece carries zstd's own checksum). The MD5
# of what's read is taken on the way (one md5sum on a FIFO), and the backup is read back and
# checked against it. Sets BK_NAME and BK_MD5 (the whole image), BK_REST_MD5 (all of it but the
# bootloader, sectors 64..32767: what a recovery card writes back) and BK_LOADER_MD5.
backup_emmc() {
	step "Backing up the built-in storage"
	BK_DIR=$1/backup
	BK_NAME=GKD350HUltra-eMMC-$(date +%Y%m%d-%H%M)
	mkdir -p "$BK_DIR" || die "can't write $BK_DIR"
	sync
	w0=$(awk '{ print $5 }' /sys/block/$EMMC/${EMMC}p2/stat)
	_bytes=$(( $(cat /sys/block/$EMMC/size) * 512 ))
	_piece=500                              # 4 MiB blocks: 2000 MiB a piece
	_np=$(( (_bytes + _piece * 4194304 - 1) / (_piece * 4194304) ))
	rm -f "$T/fifo"; mkfifo "$T/fifo"
	md5sum < "$T/fifo" | cut -c1-32 > "$T/read.md5" & _m=$!
	exec 3> "$T/fifo"
	_i=0
	while [ $_i -lt $_np ]; do
		say "reading and compressing part $((_i + 1)) of $_np..."
		dd if=/dev/$EMMC bs=4M skip=$((_i * _piece)) count=$_piece 2>/dev/null | tee /dev/fd/3 |
			zstd -3 -T0 -q -c > "$BK_DIR/$BK_NAME.img.zst.$(printf '%03d' $((_i + 1)))" ||
			{ exec 3>&-; die "the backup didn't complete (is the card full?)"; }
		_i=$((_i + 1))
	done
	exec 3>&-
	wait $_m
	w1=$(awk '{ print $5 }' /sys/block/$EMMC/${EMMC}p2/stat)
	sync
	echo 3 > /proc/sys/vm/drop_caches
	say "checking the backup (reading it back from the card)..."
	BK_MD5=$(cat "$T/read.md5")
	rm -f "$T/fifo" "$T/read.md5"
	# Read back once: the whole image's MD5, and the MD5 without the bootloader (head -c reads
	# exactly that much of the stream).
	mkfifo "$T/fifo"
	md5sum < "$T/fifo" | cut -c1-32 > "$T/back.md5" & _m=$!
	BK_REST_MD5=$(cat "$BK_DIR/$BK_NAME.img.zst."* | zstd -dc -q | tee "$T/fifo" |
		{ head -c 32768; head -c $(( (32768 - 64) * 512 )) > /dev/null; cat; } | md5sum | cut -c1-32)
	wait $_m
	[ ${#BK_MD5} -eq 32 ] && [ "$(cat "$T/back.md5")" = "$BK_MD5" ] ||
		die "the backup on the card doesn't read back as the built-in storage was read"
	rm -f "$T/fifo" "$T/back.md5"
	BK_LOADER_MD5=$(dd if=/dev/$EMMC bs=512 skip=64 count=$((32768 - 64)) 2>/dev/null | md5sum | cut -c1-32)
	[ "$w0" = "$w1" ] || warn "stock wrote to its data while this copied; the backup is the built-in storage as it was read."
	sync
	ok "backup made and checked: $(du -sk "$BK_DIR" | awk '{ printf "%.1f", $1 * 1024 / 1e9 }') GB"
}

# The recovery card: MBR, one FAT32 partition (U-Boot reads FAT, not exFAT), bootable.
if [ "$REC" = yes ]; then
	step "Making the recovery card"
	dd if=/dev/zero of="$D" bs=1M count=8 conv=fsync 2>/dev/null
	parted -s "$D" mklabel msdos mkpart primary fat32 1MiB 100% set 1 boot on || die "parted failed"
	partprobe "$D" 2>/dev/null
	_i=0; while [ ! -b ${D}p1 ] && [ $_i -lt 20 ]; do sleep 0.5; _i=$((_i + 1)); done
	[ -b ${D}p1 ] || die "the new partition didn't appear"
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
	# What the recovery system checks before it restores: the backup's name, its MD5s, and the
	# eMMC it's of (its ID and size).
	cat > "$T/backup.info" <<EOF
NAME=$BK_NAME
IMG_MD5=$BK_MD5
REST_MD5=$BK_REST_MD5
LOADER_MD5=$BK_LOADER_MD5
EMMC_CID=$(cat /sys/block/$EMMC/device/cid)
EMMC_SECTORS=$(cat /sys/block/$EMMC/size)
DATE=$(date '+%Y-%m-%d %H:%M')
STOCK=$(. /etc/os-release 2>/dev/null; echo "stock ${OS_NAME:-?} ${OS_VERSION:-?} ($(echo "${BUILD_ID:-?}" | cut -c1-7))")$([ -n "$INSTALLED" ] && echo ", with BasedOS")
EOF
	put "$T/backup.info" "$C/recovery/backup.info"
	cat > "$C/RECOVERY.txt" <<EOF
BasedOS recovery card for one GKD 350H Ultra, made $(date) by basedos-setup.

With this card in, the device starts the restore screen instead of its own system. It checks the
backup, then puts the built-in storage back as it was when this card was made, but only once you
tap A, B, X and Y in that order. Tapping power powers off without writing anything. Take the
card out to start normally.

It needs the device's own bootloader to start. If that's gone, nothing on a card helps: maskrom
and a PC can restore this same backup (BasedOS's docs/recovery.md).

Keep this card as it is. backup/ holds the backup: the built-in storage's main area, byte for
byte, in numbered pieces (join them in order, then zstd -d, for a plain image a PC can write).
EOF
	# Its boot script last: until it's there, the card doesn't boot.
	put "$HERE/recovery.scr" "$C/boot.scr"
	sync
	umount "$C" || die "can't unmount the recovery card"
	ok "recovery card ready"
fi

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

if [ "$TARGET" = install ]; then
	step "Installing BasedOS on the built-in storage"
	mount -o remount,rw $STOCK_P1 || die "can't write $STOCK_P1"
	B=$STOCK_P1/basedos
	mkdir -p "$B"
	dd if=$STOCK_P1/boot.scr bs=64 skip=1 2>/dev/null | grep -q "rdinit=/basedos/init" &&
		die "$STOCK_P1/boot.scr is BasedOS's, but there's no BasedOS folder: put stock's back first"
	put $STOCK_P1/boot.scr "$B/boot.scr.stock"
	put "$HERE/rootfs.squashfs" "$B/rootfs.squashfs"
	put "$HERE/initrd.uimg" "$B/initrd.uimg"
	# BasedOS's boot script last: it switches the device over.
	put "$HERE/boot.scr" $STOCK_P1/boot.scr
	mount -o remount,ro $STOCK_P1
	seed_data /storage/basedos-data
	sync
	ok "installed"
	if [ "$REC" = yes ]; then
		RESULT="BasedOS $VERSION is installed next to stock. Power off, take the recovery card out (keep it safe: with it in, the device starts the restore screen), and power on to start BasedOS."
	else
		RESULT="BasedOS $VERSION is installed next to stock. Restart to start it."
	fi
else
	RESULT="The recovery card is ready. Power off and take it out; keep it safe. To restore the built-in storage: power off, put the card in, power on, and follow the screen."
fi

# The card stays out of stock's automounter until the next power-on: released now, it would mount
# the new card's partition and write to it.
[ -n "${UDEV_HELD:-}" ] && UDEV_HELD=""
cleanup
# setup's own folder in RAM, once nothing is mounted under it.
grep -q " $T/" /proc/mounts || rm -rf "$T"
step "Done"
say "${C_GRN}$RESULT${C_0}"
exit 0
