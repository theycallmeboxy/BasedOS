#!/bin/sh
# basedos-setup: set up BasedOS on a GKD 350H Ultra. Run it ON the device, under stock ROCKNIX,
# over SSH (ssh -t root@<device>; stock's root has no password). The script on its own is enough:
# it reads its release's release.info first, and downloads the rest of the release (checked
# against the release's SHA256SUMS) only after you've confirmed. Nothing is needed on a PC:
#
#   curl -fsSL -o /tmp/basedos-setup.sh <the release's basedos-setup.sh URL> && sh /tmp/basedos-setup.sh
#
# (Run from a folder that already holds the release files, it uses those instead.)
#
# What it offers depends on what's on the device:
#
#   Install    BasedOS on the built-in storage (eMMC), next to stock (docs/plan.md, Architecture):
#              BasedOS's folder in stock's boot partition, its data in stock's data partition, its
#              boot script in place of stock's (kept). Stock's own files are used in place (its
#              kernel, device trees and SYSTEM) and never changed. Also finishes an install that
#              was interrupted.
#   Repair     BasedOS installed: this release's system layer, initrd and boot script put back,
#              its settings kept and its boot counter cleared. For a BasedOS that no longer starts
#              (the device then boots stock), or to go back to this release. A disabled BasedOS
#              stays disabled.
#   Uninstall  BasedOS (or what an unfinished install or uninstall left) removed: stock's boot
#              script back, BasedOS's folder, data and Ports entries gone. Stock is as it was.
#   Recovery card (always): a backup of the built-in storage as it is now, by region (the
#              partition table, the bootloader, p1, p2; together the whole main area, byte for
#              byte), a small recovery system that starts from the card and puts it back
#              (tools/recovery), and what a maskrom restore from a PC needs (Rockchip's USB loader
#              and the steps). It needs the device's own bootloader to start: a lost bootloader
#              takes maskrom and a PC, with the card's bootloader.img (docs/recovery.md).
#
# Install, Repair and Uninstall offer a recovery card first.
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
	[ -n "${P1_RW:-}" ] && { sync; mount -o remount,ro $STOCK_P1 2>/dev/null; }
	P1_RW=""
	[ -n "${CARD_LOCKED:-}" ] && exec 4<&-
	CARD_LOCKED=""
	[ -n "${UDEV_HELD:-}" ] && udevadm control --start-exec-queue 2>/dev/null
	UDEV_HELD=""
	[ -n "${ES_STOPPED:-}" ] && systemctl start essway 2>/dev/null
	ES_STOPPED=""
}
# Ctrl-C (or the SSH session going away): clean up and stop. Before phase 2 nothing has been
# written; during it, a card or an install may be left part-done: setup run again erases the card
# again, or replaces the unfinished install's folder (stock's boot script is switched last).
interrupted() {
	printf '\n%sSTOPPED%s (interrupted): %s\n' "$C_RED" "$C_0" \
		"$([ -n "${PHASE2:-}" ] && echo "part-way through; run setup again to finish or redo it" || echo "nothing was written")" >&2
	cleanup
	grep -q " $T/" /proc/mounts || rm -rf "$T"
	exit 130
}
trap interrupted INT TERM HUP
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
fetch() { curl -fsSL --retry 3 -o "$2" "$1"; }  # fetch <url> <file>
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
for c in awk sed tr cut sort grep head dd tee mkfifo md5sum sha256sum zstd parted partprobe blkid flock \
	mkfs.vfat udevadm systemctl wpa_passphrase mount umount df du sync curl cat ls wc sleep cp mv rm mkdir \
	chmod date id dirname readlink od; do
	command -v $c >/dev/null 2>&1 || miss="$miss $c"
done
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

# What's on the built-in storage now:
#   installed  BasedOS's boot script is the active one, or BasedOS is disabled (its own saved, for
#              "Enable BasedOS": DISABLED).
#   partial    a BasedOS folder with neither: an install that didn't finish (interrupted before it
#              switched the boot script).
#   leftovers  no folder, but BasedOS's data or Ports entries (an uninstall that didn't finish).
#   broken     BasedOS's boot script with no BasedOS folder: it can't start BasedOS, and stock's own
#              script went with the folder.
# scr_ok <file>: a whole U-Boot script image: its magic, the type "script", and the size its header
# gives (as basedos-boot checks them).
scr_ok() {
	[ -s "$1" ] || return 1
	[ "$(dd if="$1" bs=4 count=1 2>/dev/null | od -An -tx1 | tr -d ' \n')" = 27051956 ] || return 1
	[ "$(dd if="$1" bs=1 skip=30 count=1 2>/dev/null | od -An -tu1 | tr -d ' \n')" = 6 ] || return 1
	_len=$(dd if="$1" bs=1 skip=12 count=4 2>/dev/null | od -An -tu1 | awk '{print (($1*256+$2)*256+$3)*256+$4}')
	[ "$(wc -c < "$1" | tr -d ' ')" = "$((_len + 64))" ]
}
is_basedos_scr() { dd if="$1" bs=64 skip=1 2>/dev/null | grep -q "rdinit=/basedos/init"; }
B=$STOCK_P1/basedos
BD=/storage/basedos-data
PORTS=/storage/games-internal/roms/ports
# Every place BasedOS has put its Ports entries, and their names (older ones too).
PORTS_DIRS="$PORTS /storage/roms/ports /storage/.config/modules"
PORTS_NAMES="Enable BasedOS.sh|Disable BasedOS.sh|Uninstall BasedOS.sh|Return to BasedOS.sh"
any_entry() {
	for _d in $PORTS_DIRS; do
		_IFS=$IFS; IFS='|'
		for _n in $PORTS_NAMES; do [ -f "$_d/$_n" ] && { IFS=$_IFS; return 0; }; done
		IFS=$_IFS
	done
	return 1
}
# stock's boot script as BasedOS saved it: a whole script, and not BasedOS's.
stock_saved_ok() { scr_ok $B/boot.scr.stock && ! is_basedos_scr $B/boot.scr.stock; }
STATE=none DISABLED=""
if is_basedos_scr $STOCK_P1/boot.scr; then
	if [ -d "$B" ]; then STATE=installed; else STATE=broken; fi
elif [ -f "$B/boot.scr.basedos" ]; then
	STATE=installed DISABLED=1
elif [ -d "$B" ]; then
	STATE=partial
elif [ -d "$BD" ] || any_entry; then
	STATE=leftovers
fi
INSTALLED=""; [ $STATE = installed ] && INSTALLED=1
[ $STATE = broken ] &&
	die "$STOCK_P1/boot.scr is BasedOS's, but BasedOS's folder (with stock's own boot script) is gone: the recovery card restores the built-in storage (docs/recovery.md)"
say ""
case $STATE in
installed)
	if [ -n "$DISABLED" ]; then say "BasedOS is installed, and disabled (stock starts)."
	else say "BasedOS is installed."; fi ;;
partial) say "An earlier BasedOS install didn't finish (stock starts; $B is left)." ;;
leftovers) say "BasedOS isn't installed, but its settings or Ports entries are left from before." ;;
esac
# The choices for what's there: "<target>|<label>" lines.
case $STATE in
none) CHOICES="install|Install BasedOS on the built-in storage, next to stock" ;;
leftovers) CHOICES="install|Install BasedOS on the built-in storage, next to stock
uninstall|Remove what's left of BasedOS (its settings and Ports entries)" ;;
partial) CHOICES="install|Install BasedOS, replacing the unfinished install
uninstall|Remove the unfinished install" ;;
installed) CHOICES="repair|Repair BasedOS: put BasedOS $VERSION back, keeping its settings
uninstall|Uninstall BasedOS: remove it and its settings (stock stays as it is)" ;;
esac
CHOICES="$CHOICES
recovery|Make a recovery SD card (it can put the built-in storage back as it is now)"
say ""
say "${C_B}What do you want to do?${C_0}"
_n=0
echo "$CHOICES" | while IFS='|' read -r _t _l; do _n=$((_n + 1)); say "  $_n) $_l"; done
_max=$(echo "$CHOICES" | wc -l)
ask "Choose 1 to $_max:" _a
case "$_a" in ''|*[!0-9]*) die "no choice made" ;; esac
[ "$_a" -ge 1 ] && [ "$_a" -le "$_max" ] || die "no choice made"
TARGET=$(echo "$CHOICES" | sed -n "${_a}p" | cut -d'|' -f1)
# Uninstalling an enabled BasedOS puts stock's saved boot script back: it must be whole.
if [ "$TARGET" = uninstall ] && is_basedos_scr $STOCK_P1/boot.scr && ! stock_saved_ok; then
	die "BasedOS's copy of stock's boot script ($B/boot.scr.stock) is missing or damaged, so stock's can't be put back: the recovery card restores the built-in storage (docs/recovery.md)"
fi

REC=no
if [ "$TARGET" != recovery ]; then
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
case $TARGET in
install)
	item "Install BasedOS $VERSION on the built-in storage, next to stock."
	[ $STATE = partial ] && say "     ${C_DIM}(An earlier install didn't finish: its folder, $B, is replaced.)${C_0}"
	[ $STATE = leftovers ] && say "     ${C_DIM}(BasedOS's settings left from before are kept.)${C_0}" ;;
repair)
	item "Put BasedOS $VERSION's system, initrd and boot script back. Its settings stay."
	[ -n "$DISABLED" ] && say "     ${C_DIM}(It stays disabled: 'Enable BasedOS' in stock's Ports starts it.)${C_0}"
	if [ -z "$DISABLED" ] && ! stock_saved_ok; then
		warn "BasedOS's copy of stock's boot script is missing or damaged: Repair can't bring it back, so Disable and Uninstall won't work. The recovery card restores the built-in storage."
	fi ;;
uninstall)
	if [ $STATE = installed ]; then item "Uninstall BasedOS: stock's boot script back, BasedOS's files and settings removed."
	else item "Remove what's left of BasedOS: its folder, settings and Ports entries."; fi ;;
esac
[ "$TARGET" != recovery ] && [ "$REC" = yes ] && say "     ${C_DIM}(Only after the recovery card is made and checked.)${C_0}"
say ""
[ -n "$CARD" ] && confirm ERASE "erase this $SIZE_GB GB card"
if [ "$TARGET" != recovery ]; then
	say ""
	say "This modifies the device's built-in storage. If something goes wrong, the device may not start"
	say "until it's restored$([ "$REC" = yes ] && echo " with the recovery card" || echo " from a backup (docs/recovery.md)")."
	_w=$(echo "$TARGET" | tr a-z A-Z)
	confirm "$_w" "confirm that you understand this, know the risks, and have a backup"
fi

# ---------------------------------------------------------------------------------------------
# Phase 2: no more questions.
PHASE2=1

# The rest of the release, now (Uninstall alone needs none of it).
[ "$REC" = yes ] || [ "$TARGET" = install ] || [ "$TARGET" = repair ] && step "Getting BasedOS $VERSION"
if [ "$REC" = yes ]; then
	for f in recovery-initrd.uimg recovery.scr rk3576_usb_loader_ddr1.13_usbplug1.04.bin LICENSE.rkbin.txt; do release_file $f; done
fi
if [ "$TARGET" = install ] || [ "$TARGET" = repair ]; then
	for f in rootfs.squashfs initrd.uimg boot.scr; do release_file $f; done
	mkdir -p "$T/mnt/rootfs"
	mount -t squashfs -o ro,loop "$HERE/rootfs.squashfs" "$T/mnt/rootfs" || die "$HERE/rootfs.squashfs does not mount"
	[ "$(cat "$T/mnt/rootfs/usr/share/basedos/needs-stock" 2>/dev/null)" = "$STOCK_ID" ] ||
		die "rootfs.squashfs isn't made for this stock build"
	umount "$T/mnt/rootfs"
fi
[ "$REC" = yes ] || [ "$TARGET" = install ] || [ "$TARGET" = repair ] && ok "downloaded and checked"

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

# The eMMC's main area as four regions back to back, the whole of it: the partition table (sectors
# 0..63), the bootloader (64 up to p1), p1 and p2 (to the end). R_<n>_START and R_<n>_SECTORS for
# n = 0..3; setup stops if the layout isn't that (stock's is), so a backup is always the whole
# main area. p1 and p2 start on a 4 MiB boundary (the reads and the recovery card's writes are in
# 4 MiB blocks).
regions() {
	_t=$(parted -s /dev/$EMMC unit s print 2>/dev/null)
	_p1s=$(echo "$_t" | awk '$1 == 1 { sub(/s$/, "", $2); print $2 }')
	_p1e=$(echo "$_t" | awk '$1 == 1 { sub(/s$/, "", $3); print $3 }')
	_p2s=$(echo "$_t" | awk '$1 == 2 { sub(/s$/, "", $2); print $2 }')
	_p2e=$(echo "$_t" | awk '$1 == 2 { sub(/s$/, "", $3); print $3 }')
	_end=$(( $(cat /sys/block/$EMMC/size) - 1 ))
	[ -n "$_p1s" ] && [ -n "$_p2e" ] && [ "$(echo "$_t" | awk '$1 ~ /^[0-9]+$/' | wc -l)" -eq 2 ] ||
		die "the built-in storage doesn't have stock's two partitions"
	[ "$_p2s" -eq $((_p1e + 1)) ] && [ "$_p2e" -eq "$_end" ] && [ "$_p1s" -gt 64 ] &&
		[ $((_p1s % 8192)) -eq 0 ] && [ $((_p2s % 8192)) -eq 0 ] ||
		die "the built-in storage's partitions aren't laid out as stock's (p1 $_p1s-$_p1e, p2 $_p2s-$_p2e)"
	R_0_START=0 R_0_SECTORS=64
	R_1_START=64 R_1_SECTORS=$((_p1s - 64))
	R_2_START=$_p1s R_2_SECTORS=$((_p1e - _p1s + 1))
	R_3_START=$_p2s R_3_SECTORS=$((_p2e - _p2s + 1))
}

# backup_emmc <drive>: a full backup of the built-in storage's main area in <drive>/backup/, by
# region, images only:
#   <name>.0-partition-table.img        sectors 0..63, raw (32 KB)
#   <name>.1-bootloader.img             sectors 64 up to p1, raw (16 MB): what maskrom writes back
#                                       at 0x40 if the bootloader is ever lost
#   <name>.2-p1.img.zst.001, ...        p1, then p2, zstd in pieces of 2000 MiB of the eMMC, each
#   <name>.3-p2.img.zst.001, ...        piece its own stream (zstd decompresses them back to back)
# Laid end to end in name order (the .zst ones decompressed), they're the whole main area, byte for
# byte. Each region's MD5 is taken while it's read, and the backup is read back and checked against
# them. Sets BK_NAME and BK_MD5_0..3.
backup_emmc() {
	step "Backing up the built-in storage"
	regions
	BK_DIR=$1/backup
	BK_NAME=GKD350HUltra-eMMC-$(date +%Y%m%d-%H%M)
	mkdir -p "$BK_DIR" || die "can't write $BK_DIR"
	sync
	w0=$(awk '{ print $5 }' /sys/block/$EMMC/${EMMC}p2/stat)
	dd if=/dev/$EMMC of="$BK_DIR/$BK_NAME.0-partition-table.img" bs=512 count=$R_0_SECTORS 2>/dev/null ||
		die "couldn't read the partition table"
	dd if=/dev/$EMMC of="$BK_DIR/$BK_NAME.1-bootloader.img" bs=512 skip=$R_1_START count=$R_1_SECTORS 2>/dev/null ||
		die "couldn't read the bootloader"
	BK_MD5_0=$(md5sum < "$BK_DIR/$BK_NAME.0-partition-table.img" | cut -c1-32)
	BK_MD5_1=$(md5sum < "$BK_DIR/$BK_NAME.1-bootloader.img" | cut -c1-32)
	for r in 2 3; do
		eval "_start=\$R_${r}_START _sect=\$R_${r}_SECTORS"
		_label=p$((r - 1))
		_bytes=$((_sect * 512)) _piece=$((500 * 4194304))   # 2000 MiB of the eMMC a piece
		_np=$(( (_bytes + _piece - 1) / _piece ))
		rm -f "$T/fifo"; mkfifo "$T/fifo"
		md5sum < "$T/fifo" | cut -c1-32 > "$T/read.md5" & _m=$!
		exec 3> "$T/fifo"
		_i=0
		while [ $_i -lt $_np ]; do
			_left=$((_bytes - _i * _piece)); [ $_left -gt $_piece ] && _left=$_piece
			say "reading and compressing $_label, part $((_i + 1)) of $_np..."
			dd if=/dev/$EMMC bs=4M skip=$((_start / 8192 + _i * 500)) count=500 2>/dev/null | head -c $_left | tee /dev/fd/3 |
				zstd -3 -T0 -q -c > "$BK_DIR/$BK_NAME.$r-$_label.img.zst.$(printf '%03d' $((_i + 1)))" ||
				{ exec 3>&-; die "the backup didn't complete (is the card full?)"; }
			_i=$((_i + 1))
		done
		exec 3>&-
		wait $_m
		eval "BK_MD5_$r=\$(cat \"\$T/read.md5\")"
		rm -f "$T/fifo" "$T/read.md5"
	done
	w1=$(awk '{ print $5 }' /sys/block/$EMMC/${EMMC}p2/stat)
	sync
	echo 3 > /proc/sys/vm/drop_caches
	# The read-back: each region whole (its size in bytes) and as it was read (its MD5). The size
	# matters as much as the MD5: a read error from the eMMC ends that piece's read early without
	# stopping the pipeline, and the MD5 taken while reading is then of the short stream too.
	say "checking the backup (reading it back from the card)..."
	region_ok() {  # region_ok <n> <file or piece prefix> <raw|zst>
		eval "_want_md5=\$BK_MD5_$1 _want_bytes=\$((R_$1_SECTORS * 512))"
		[ ${#_want_md5} -eq 32 ] || return 1
		rm -f "$T/count"; mkfifo "$T/count"
		wc -c < "$T/count" > "$T/count.out" & _c=$!
		if [ "$3" = raw ]; then _got=$(tee "$T/count" < "$2" | md5sum | cut -c1-32)
		else _got=$(cat "$2".* | zstd -dc -q | tee "$T/count" | md5sum | cut -c1-32); fi
		wait $_c
		[ "$_got" = "$_want_md5" ] && [ "$(tr -d ' \n' < "$T/count.out")" = "$_want_bytes" ]
	}
	region_ok 0 "$BK_DIR/$BK_NAME.0-partition-table.img" raw &&
		region_ok 1 "$BK_DIR/$BK_NAME.1-bootloader.img" raw &&
		region_ok 2 "$BK_DIR/$BK_NAME.2-p1.img.zst" zst &&
		region_ok 3 "$BK_DIR/$BK_NAME.3-p2.img.zst" zst ||
		die "the backup on the card isn't the whole built-in storage as it was read (a read error on the eMMC, or the card)"
	rm -f "$T/count" "$T/count.out"
	[ "$w0" = "$w1" ] || warn "stock wrote to its data while this copied; the backup is the built-in storage as it was read."
	sync
	ok "backup made and checked: $(du -sk "$BK_DIR" | awk '{ printf "%.1f", $1 * 1024 / 1e9 }') GB"
}

# The recovery card: MBR, one FAT32 partition (U-Boot reads FAT, not exFAT), bootable.
if [ "$REC" = yes ]; then
	step "Making the recovery card"
	# The card held locked (BSD flock on the whole disk) while it's rebuilt: udevd re-reads a
	# disk's partition table on its own whenever a writer closes it (stock's 60-block.rules
	# "watch"), which removes and re-adds the partition under us; it leaves a locked disk alone
	# and holds its events back until the lock goes (systemd's block device locking).
	exec 4< "$D" && flock -x 4 || die "can't lock the card"
	CARD_LOCKED=1
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
	# What the recovery system checks before it restores: the backup's name, each region's start,
	# size and MD5, and the eMMC it's of (its ID and size).
	{
		echo "NAME=$BK_NAME"
		for r in 0 1 2 3; do
			eval "echo R${r}_START=\$R_${r}_START; echo R${r}_SECTORS=\$R_${r}_SECTORS; echo R${r}_MD5=\$BK_MD5_$r"
		done
		echo "EMMC_CID=$(cat /sys/block/$EMMC/device/cid)"
		echo "EMMC_SECTORS=$(cat /sys/block/$EMMC/size)"
		echo "DATE=$(date '+%Y-%m-%d %H:%M')"
		echo "STOCK=$(. /etc/os-release 2>/dev/null; echo "stock ${OS_NAME:-?} ${OS_VERSION:-?} ($(echo "${BUILD_ID:-?}" | cut -c1-7))")$([ -n "$INSTALLED" ] && echo ", with BasedOS")"
	} > "$T/backup.info"
	put "$T/backup.info" "$C/recovery/backup.info"
	# A maskrom restore from a PC, with nothing else needed: Rockchip's USB loader, its licence, and
	# the steps with this device's own sector numbers.
	mkdir -p "$C/maskrom"
	put "$HERE/rk3576_usb_loader_ddr1.13_usbplug1.04.bin" "$C/maskrom/rk3576_usb_loader_ddr1.13_usbplug1.04.bin"
	put "$HERE/LICENSE.rkbin.txt" "$C/maskrom/LICENSE.rkbin.txt"
	hex() { printf '0x%08X' "$1"; }
	cat > "$C/maskrom/MASKROM.txt" <<EOF
Restoring this GKD 350H Ultra from a PC, in maskrom (when the device won't start at all, or this
card can't start because the device's bootloader is gone).

What you need: this card's backup/ folder, this maskrom/ folder, a USB-A to USB-C cable (USB-C to
USB-C may not work), and on the PC either RKDevTool (Windows, from Rockchip) or rkdeveloptool
(Linux or macOS, open source).

1. Power off. Take this card out of the device (read it on the PC).
2. Connect the cable, hold Volume Down and press power. RKDevTool shows "Found One MASKROM Device";
   rkdeveloptool ld lists it.
3. Load the USB loader (into RAM only):
     RKDevTool: Advanced Function, Boot: maskrom/rk3576_usb_loader_ddr1.13_usbplug1.04.bin, Download.
     rkdeveloptool db maskrom/rk3576_usb_loader_ddr1.13_usbplug1.04.bin
4. Write what's needed, each at its sector (RKDevTool: Download Image, untick every row, Loader
   above all; one row per file with its address, Write by Address, Run. rkdeveloptool: wl).

   Only the bootloader lost (the device shows nothing at all, even with this card in):
     $BK_NAME.1-bootloader.img    at $(hex $R_1_START)   (rkdeveloptool wl $R_1_START <file>)

   Everything (as when this backup was made):
     $BK_NAME.0-partition-table.img   at $(hex $R_0_START)
     $BK_NAME.1-bootloader.img        at $(hex $R_1_START)
     p1.img                           at $(hex $R_2_START)   (rkdeveloptool wl $R_2_START <file>)
     p2.img                           at $(hex $R_3_START)   (rkdeveloptool wl $R_3_START <file>)
   p1.img and p2.img first: join each one's pieces in order and decompress them:
     Linux/macOS:  cat $BK_NAME.2-p1.img.zst.* | zstd -d -o p1.img
     Windows:      copy /b $BK_NAME.2-p1.img.zst.001 + ...002 + ... p1.img.zst, then zstd -d p1.img.zst
   (the same for p2). Laid end to end in name order, the four are the whole main area of the
   built-in storage, byte for byte.

5. The tool resets the device when it's done (rkdeveloptool rd). Unplug USB; it starts.

RKDevTool's addresses here are sectors (512 bytes) from the start of the built-in storage, with
no offset. The bootloader-only write was tested on a unit (2026-11-20, RKDevTool); rkdeveloptool
with this loader has not been.
EOF
	cat > "$C/RECOVERY.txt" <<EOF
BasedOS recovery card for one GKD 350H Ultra, made $(date) by basedos-setup.

With this card in, the device starts the restore screen instead of its own system. It checks the
backup, then puts the built-in storage back as it was when this card was made, but only once you
tap A, B, X and Y in that order. Tapping power powers off without writing anything. Take the
card out to start normally.

It needs the device's own bootloader to start. If that's gone, maskrom and a PC restore it from
this same card: maskrom/MASKROM.txt.

Keep this card as it is. backup/ holds the backup, by region: the partition table, the
bootloader, p1 and p2 (in numbered pieces). Laid end to end in name order, they're the whole
built-in storage's main area, byte for byte.
EOF
	# Its boot script last: until it's there, the card doesn't boot.
	put "$HERE/recovery.scr" "$C/boot.scr"
	sync
	umount "$C" || die "can't unmount the recovery card"
	exec 4<&-; CARD_LOCKED=""
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

# clear_flags: BasedOS's one-boot flags and its boot counter, left from before (a count from a
# BasedOS that didn't start would send the next boot to stock; an uninstall flag would remove it).
clear_flags() {
	rm -f $BD/boot-attempts $BD/boot-stock-once $BD/uninstall $BD/uninstall.new $BD/update/requested
}
# entries <name>...: those Ports entries from this release's system layer into stock's Ports, and
# the other BasedOS entries removed (they'd do the wrong thing in this state).
entries() {
	for _d in $PORTS_DIRS; do
		_IFS=$IFS; IFS='|'
		for _n in $PORTS_NAMES; do rm -f "$_d/$_n"; done
		IFS=$_IFS
	done
	mkdir -p "$T/mnt/rootfs" $PORTS
	if mount -t squashfs -o ro,loop "$HERE/rootfs.squashfs" "$T/mnt/rootfs"; then
		for e in "$@"; do
			cp "$T/mnt/rootfs/usr/share/basedos/stock/$e" "$PORTS/" && chmod 755 "$PORTS/$e" ||
				warn "couldn't put '${e%.sh}' in stock's Ports (BasedOS's maintenance menu has it too)"
		done
		umount "$T/mnt/rootfs"
	else
		warn "couldn't put BasedOS's entries in stock's Ports (BasedOS's maintenance menu has them too)"
	fi
}
# Developer leftovers in BasedOS's folder: the two-slot layout's second slot and pointer, a
# waiting update, copies kept by tools/dev/update-basedos.sh, unfinished writes.
dev_leftovers() {
	rm -f "$B/rootfs-b.squashfs" "$B/slot" "$B/rootfs.new" "$B/initrd.uimg.prev" "$B/boot.scr.prev" "$B"/*.new
	is_basedos_scr $STOCK_P1/boot.scr.prev 2>/dev/null && rm -f $STOCK_P1/boot.scr.prev
	return 0
}

case $TARGET in
install)
	step "Installing BasedOS on the built-in storage"
	# Checked again here (phase 1 did): stock's boot script must be stock's before it's saved.
	is_basedos_scr $STOCK_P1/boot.scr && die "$STOCK_P1/boot.scr is BasedOS's already: nothing was written"
	mount -o remount,rw $STOCK_P1 || die "can't write $STOCK_P1"
	P1_RW=1
	# An earlier install that didn't finish: stock's boot script is still stock's, so nothing boots
	# its folder; it's replaced.
	if [ $STATE = partial ]; then rm -rf "$B" || die "can't remove the unfinished install's $B"; fi
	mkdir -p "$B" || die "can't make $B"
	put $STOCK_P1/boot.scr "$B/boot.scr.stock"
	put "$HERE/rootfs.squashfs" "$B/rootfs.squashfs"
	put "$HERE/initrd.uimg" "$B/initrd.uimg"
	# BasedOS's boot script last: it switches the device over.
	put "$HERE/boot.scr" $STOCK_P1/boot.scr
	mount -o remount,ro $STOCK_P1
	P1_RW=""
	seed_data $BD
	clear_flags
	# "Disable BasedOS" and "Uninstall BasedOS" in stock's Ports (the folder stock's Ports reads:
	# /storage/roms is a bind of games-internal/roms), from this release's system layer, so BasedOS
	# can be disabled or removed from stock too.
	entries "Disable BasedOS.sh" "Uninstall BasedOS.sh"
	sync
	ok "installed"
	if [ "$REC" = yes ]; then
		RESULT="BasedOS $VERSION is installed next to stock. Power off, take the recovery card out (keep it safe: with it in, the device starts the restore screen), and power on to start BasedOS."
	else
		RESULT="BasedOS $VERSION is installed next to stock. Restart to start it."
	fi ;;
repair)
	step "Repairing BasedOS"
	mount -o remount,rw $STOCK_P1 || die "can't write $STOCK_P1"
	P1_RW=1
	# Disabled, stock's boot script is the active one: saved again if BasedOS's copy is gone.
	if [ -n "$DISABLED" ] && ! stock_saved_ok; then
		scr_ok $STOCK_P1/boot.scr && put $STOCK_P1/boot.scr "$B/boot.scr.stock"
	fi
	dev_leftovers
	put "$HERE/rootfs.squashfs" "$B/rootfs.squashfs"
	put "$HERE/initrd.uimg" "$B/initrd.uimg"
	# BasedOS's boot script last: where it's kept while disabled, else the active one.
	if [ -n "$DISABLED" ]; then put "$HERE/boot.scr" "$B/boot.scr.basedos"
	else put "$HERE/boot.scr" $STOCK_P1/boot.scr; fi
	mount -o remount,ro $STOCK_P1
	P1_RW=""
	seed_data $BD
	clear_flags
	if [ -n "$DISABLED" ]; then entries "Enable BasedOS.sh" "Uninstall BasedOS.sh"
	else entries "Disable BasedOS.sh" "Uninstall BasedOS.sh"; fi
	sync
	ok "repaired"
	if [ -n "$DISABLED" ]; then
		RESULT="BasedOS $VERSION is back in place, and still disabled: run 'Enable BasedOS' from stock's Ports to start it."
	elif [ "$REC" = yes ]; then
		RESULT="BasedOS $VERSION is repaired. Power off, take the recovery card out (keep it safe), and power on to start BasedOS."
	else
		RESULT="BasedOS $VERSION is repaired. Restart to start it."
	fi ;;
uninstall)
	step "Removing BasedOS"
	mount -o remount,rw $STOCK_P1 || die "can't write $STOCK_P1"
	P1_RW=1
	# Stock's boot script first, if BasedOS's is the active one (checked in phase 1).
	if is_basedos_scr $STOCK_P1/boot.scr; then put "$B/boot.scr.stock" $STOCK_P1/boot.scr; fi
	# Then BasedOS's files: nothing boots them any more.
	rm -rf "$B" || die "can't remove $B"
	is_basedos_scr $STOCK_P1/boot.scr.prev 2>/dev/null && rm -f $STOCK_P1/boot.scr.prev
	sync
	mount -o remount,ro $STOCK_P1
	P1_RW=""
	rm -rf $BD
	for _d in $PORTS_DIRS; do
		_IFS=$IFS; IFS='|'
		for _n in $PORTS_NAMES; do rm -f "$_d/$_n"; done
		IFS=$_IFS
	done
	sync
	ok "removed"
	if [ "$REC" = yes ]; then
		RESULT="BasedOS is uninstalled; stock is as it was. Power off and take the recovery card out (keep it safe)."
	else
		RESULT="BasedOS is uninstalled; stock is as it was."
	fi ;;
recovery)
	RESULT="The recovery card is ready. Power off and take it out; keep it safe. To restore the built-in storage: power off, put the card in, power on, and follow the screen." ;;
esac

# The card stays out of stock's automounter until the next power-on: released now, it would mount
# the new card's partition and write to it.
[ -n "${UDEV_HELD:-}" ] && UDEV_HELD=""
cleanup
# setup's own folder in RAM, once nothing is mounted under it.
grep -q " $T/" /proc/mounts || rm -rf "$T"
step "Done"
say "${C_GRN}$RESULT${C_0}"
exit 0
