#!/bin/sh
# basedos-setup: set up BasedOS on a GKD 350H Ultra. Run it ON the device, under stock ROCKNIX,
# over SSH (ssh root@<device>; stock's root has no password). The script on its own is enough:
# it reads its release's release.info first, and downloads the rest of the release (checked
# against the release's SHA256SUMS) only after you've confirmed. Nothing is needed on a PC:
#
#   wget -O /tmp/basedos-setup.sh <the release's basedos-setup.sh URL> && sh /tmp/basedos-setup.sh
#
# (Run from a folder that already holds the release files, it uses those instead.)
#
# Three choices:
#
#   1. Install BasedOS to the eMMC, next to stock (stock's files stay; BasedOS's maintenance menu
#      can switch back or uninstall). It recommends making a recovery card (3) first, and offers
#      to, in the same run.
#   2. Create a BasedOS SD card: BasedOS on the card alone; the eMMC is NOT modified, and from the
#      card it's never used: the card's boot script hides it from the kernel. GPT, made by stock's
#      parted (which numbers partitions in order): basedos (boot files; the only partition marked
#      legacy-bootable, which is what U-Boot boots), data (BasedOS's /data), BASEOS (the rest: the
#      frontend's drive), the first two marked no-automount. Optionally a copy of stock first, on
#      p1 and p2 (where stock's init looks; basedos is then p3), which the maintenance menu
#      starts once; a backup of the eMMC on BASEOS; and a frontend (spruce, ...) downloaded onto
#      BASEOS from its own upstream GitHub release, once one supports the device
#      (manifest/frontends.txt). The card stays in the device.
#   3. Create a recovery SD card: a backup of the whole eMMC as it is now, and a small recovery
#      system that boots from the card and, when A is held, writes the eMMC back byte for byte
#      (tools/recovery). No PC needed, then or later.
#
# Every card it makes also gets a copy of the eMMC's loader (sectors 64 to 32767, before any
# partition), as the rescue card had: the boot ROM uses it only if the eMMC's own loader is ever
# damaged. Nothing else on a card comes from the eMMC at boot.
#
# It states its requirements first (stock build, power, Wi-Fi, one card size that covers every
# choice), checks every tool it uses, asks everything, shows a numbered summary and asks for the
# typed confirmations (capitals don't matter); only then does it download or write anything,
# and it runs to the end without asking more.
#
# For an install, the vendor set (the stock kernel, DTBs, modules, firmware and GPU drivers BasedOS
# runs on; docs/plan.md, Architecture) is harvested here from stock's own files, by the recipe in
# this release, with every file's hash checked: stock files are never in a release.
#
# Not interactive: --target emmc|sd|recovery, and
#   emmc: --recovery-card or --no-recovery-card
#   sd:   --dual-boot or --no-dual-boot, --backup or --no-backup, --frontend <name> or --no-frontend
#   any card: --card <ID> (--card-id prints the inserted card's)
# and --yes. Every check still runs, and the card must have that ID.
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
# The release this script belongs to (tools/wsl/release.sh writes it in).
RELEASE_TAG=@RELEASE_TAG@
RELEASE_URL=https://github.com/theycallmeboxy/BasedOS/releases/download/$RELEASE_TAG
STOCK_P1=/flash
T=/tmp/basedos-setup            # RAM: nothing of setup's own goes on the eMMC
SDC=2a310000.mmc                # the SD slot's controller
EMMCC=2a330000.mmc              # the eMMC's

TARGET="" REC="" DUAL="" BACKUP="" FE="" CARD_WANT="" YES="" CARD_ID=""
while [ $# -gt 0 ]; do
	case "$1" in
	--target) TARGET=$2; shift ;;
	--recovery-card) REC=yes ;;
	--no-recovery-card) REC=no ;;
	--dual-boot) DUAL=yes ;;
	--no-dual-boot) DUAL=no ;;
	--backup) BACKUP=yes ;;
	--no-backup) BACKUP=no ;;
	--frontend) FE=$2; shift ;;
	--no-frontend) FE=no ;;
	--card) CARD_WANT=$2; shift ;;
	--card-id) CARD_ID=1 ;;
	--yes) YES=1 ;;
	*) echo "unknown option $1" >&2; exit 2 ;;
	esac
	shift
done

say() { printf '%s\n' "$*"; }
step() { printf '\n== %s\n' "$*"; }
die() { printf '\nSTOPPED: %s\n' "$*" >&2; cleanup; grep -q " $T/" /proc/mounts || rm -rf "$T"; exit 1; }
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
	if [ "$2" = y ]; then ask "$1 [Y/n]:" _yn; case "$_yn" in n|N|no|No|NO) return 1 ;; esac; return 0; fi
	ask "$1 [y/N]:" _yn; case "$_yn" in y|Y|yes|Yes|YES) return 0 ;; esac; return 1
}
confirm() {  # confirm <word> <what>: the typed confirmation, in any capitals
	[ -n "$YES" ] && return 0
	ask "Type $1 to $2 (capitals don't matter; anything else stops):" _a
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
mib_up() { echo $(( ($1 + 1023) / 1024 )); }                         # KiB -> MiB, rounded up
gb() { echo $(( ($1 * 1048576 + 999999999) / 1000000000 )); }        # MiB -> GB (as cards are sold)
# card_for <MiB>: the smallest common card size that holds it (a card holds about 93 % of its
# label in MiB-sized bytes, so 32 GB cards are about 29.8 GiB).
card_for() {
	for _c in 8 16 32 64 128 256 512; do
		[ $(( _c * 1000000000 * 93 / 100 / 1048576 )) -ge "$1" ] && { echo $_c; return; }
	done
	echo 1024
}
# a_card <MiB>: "a 16 GB card", "an 8 GB card".
a_card() { _c=$(card_for "$1"); case $_c in 8|8?|8??) echo "an $_c GB card" ;; *) echo "a $_c GB card" ;; esac; }
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
DL=$T/release

# ---------------------------------------------------------------------------------------------
# Phase 1: requirements, questions, the card, confirmations. Nothing is written or downloaded
# but release.info (a few KB).

if [ -n "$CARD_ID" ]; then
	_c=$(disk_of $SDC)
	[ -n "$_c" ] || { echo "no card in the slot" >&2; exit 1; }
	cat /sys/block/$_c/device/cid; exit 0
fi

step "Checking"
[ "$(id -u)" = 0 ] || die "run it as root (ssh root@<device>)"
EMMC=$(disk_of $EMMCC)
[ "$EMMC" = mmcblk0 ] || die "this doesn't look like a GKD 350H Ultra (no eMMC at mmcblk0)"
grep -q "^/dev/${EMMC}p1 $STOCK_P1 " /proc/mounts || die "run it on stock ROCKNIX ($STOCK_P1 isn't the eMMC's p1)"
rm -rf "$T"; mkdir -p "$T" || die "can't make $T"
STOCK_DESC=$(. /etc/os-release 2>/dev/null; _b=${BUILD_ID:-unknown}; echo "stock ${OS_NAME:-?} ${OS_VERSION:-?} ($(echo "$_b" | cut -c1-7))")

# Every tool setup uses, before anything else (stock's own: a missing one stops it here, not
# halfway through).
miss=""
for c in awk sed tr cut sort grep dd tee mkfifo md5sum sha256sum zstd parted partprobe blkid \
	mkfs.vfat mkfs.ext4 tar udevadm systemctl wpa_passphrase mount umount df du sync; do
	command -v $c >/dev/null 2>&1 || miss="$miss $c"
done
command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1 || miss="$miss curl-or-wget"
[ -z "$miss" ] || die "stock is missing tools setup needs:$miss"

# This release (release.info: its build, and stock's kernel and DTB hashes it was made for).
release_file release.info
INFO=$HERE/release.info
VERSION=$(sed -n 's/^VERSION=//p' "$INFO") BUILD=$(sed -n 's/^BUILD=//p' "$INFO")
VENDOR=$(sed -n 's/^VENDOR=//p' "$INFO") STOCK_BUILD=$(sed -n 's/^STOCK_BUILD=//p' "$INFO" | tr -d '\r')
[ -n "$VENDOR" ] && grep -q '^P1 ' "$INFO" || die "release.info is incomplete"
grep '^P1 ' "$INFO" | while read -r _k _sha _f; do
	[ "$(sha256sum < "$STOCK_P1/$_f" 2>/dev/null | cut -c1-64)" = "$_sha" ] || { echo "$_f"; break; }
done > "$T/mismatch"
[ -s "$T/mismatch" ] && die "this device's stock isn't the build this BasedOS release is for ($STOCK_BUILD; its $(cat "$T/mismatch") differs)"
# The frontends this release can download (FRONTEND <name> <repository> <asset> <first version>
# <unpacked %>, from manifest/frontends.txt): each one's latest upstream release, asked of GitHub
# now (a few KB), and offered only if it's a version that supports this device and GitHub gives
# its asset's SHA-256. $T/frontends: name|version|url|sha256|download MiB|download + unpacked MiB.
ver_ge() {  # ver_ge <a> <b>: 0 if version a >= b (v4.10.0 > v4.9.1)
	awk -v a="$1" -v b="$2" 'BEGIN { sub(/^[^0-9]*/, "", a); sub(/^[^0-9]*/, "", b)
		n = split(a, x, /[^0-9]+/); m = split(b, y, /[^0-9]+/)
		for (i = 1; i <= (n > m ? n : m); i++) { if (x[i] + 0 > y[i] + 0) exit 0; if (x[i] + 0 < y[i] + 0) exit 1 }
		exit 0 }'
}
: > "$T/frontends"
grep '^FRONTEND ' "$INFO" | while read -r _k _n _repo _glob _first _pct; do
	[ "$_first" = "-" ] && continue
	command -v jq >/dev/null 2>&1 || continue
	fetch "https://api.github.com/repos/$_repo/releases/latest" "$T/fe.json" || continue
	_tag=$(jq -r '.tag_name // empty' "$T/fe.json")
	[ -n "$_tag" ] && ver_ge "$_tag" "$_first" || continue
	_re="^$(printf '%s' "$_glob" | sed 's/[.]/\\./g; s/[*]/.*/g')\$"
	_a=$(jq -r --arg re "$_re" '[.assets[] | select(.name | test($re))][0] // empty | "\(.browser_download_url) \(.size) \(.digest // "-")"' "$T/fe.json")
	set -f; set -- $_a; set +f
	[ $# -eq 3 ] || continue
	case "$3" in sha256:????????????????????????????????????????????????????????????????) ;; *) continue ;; esac
	_dl=$(( ($2 + 1048575) / 1048576 ))
	echo "$_n|$_tag|$1|${3#sha256:}|$_dl|$(( _dl + _dl * _pct / 100 ))" >> "$T/frontends"
done
rm -f "$T/fe.json"
FE_COUNT=$(grep -c . "$T/frontends")
FE_MAX_MIB=$(awk -F'|' '$6 > m { m = $6 } END { print m + 0 }' "$T/frontends")
FE_MAX_DL=$(awk -F'|' '$5 > m { m = $5 } END { print m + 0 }' "$T/frontends")
FE_NAME="" FE_MIB=0
# fe_pick <line number>: the frontend chosen.
fe_pick() {
	IFS='|' read -r _n _v FE_URL FE_SHA FE_DL_MIB FE_MIB <<EOF
$(sed -n "${1}p" "$T/frontends")
EOF
	FE_NAME="$_n $_v"
}

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

# Sizes, in MiB. The backup: about what's in use on the eMMC's filesystems, compressed, with room
# to spare (the real size is known only once it's made; a card that fills up stops it cleanly).
# A copy of stock: its boot files (all of p1 but BasedOS's) and its /storage without ROMs, each
# with room to grow.
BK_MIB=$(( $(mib_up $(( $(kib_used $STOCK_P1) + $(kib_used /storage) ))) + 1024 ))
CS1_MIB=$(( 512 + $(mib_up $(kib_except $STOCK_P1 basedos)) ))
CS2_MIB=$(( 2048 + $(mib_up $(kib_except /storage games-external roms basedos-data)) ))
CS1_MIB=$(( (CS1_MIB + 255) / 256 * 256 )) CS2_MIB=$(( (CS2_MIB + 255) / 256 * 256 ))
BOOT_MIB=1024 DATA_MIB=512
sd_mib() {  # sd_mib <dual> <backup> <frontend>: what a BasedOS card needs
	_m=$(( 16 + BOOT_MIB + DATA_MIB + 1024 ))
	[ "$1" = yes ] && _m=$((_m + CS1_MIB + CS2_MIB))
	[ "$2" = yes ] && _m=$((_m + BK_MIB))
	[ "$3" = yes ] && _m=$((_m + FE_MIB))
	echo $_m
}
REC_MIB=$(( 16 + BK_MIB + 512 ))
FE_MIB=$FE_MAX_MIB
WORST_MIB=$(sd_mib yes yes $([ "$FE_COUNT" -gt 0 ] && echo yes || echo no))
FE_MIB=0

say ""
say "BasedOS $VERSION setup for the GKD 350H Ultra$(case "$RELEASE_TAG" in @*) ;; *) echo " (release $RELEASE_TAG)" ;; esac)"
say ""
say "Before you start:"
say "  - Stock ROCKNIX $(echo "$STOCK_BUILD" | sed 's/^rocknix-//'): this device has it."
if [ -n "$CHG" ]; then say "  - Power: the charger is in."
else say "  - Power: at least 30 % battery, or the charger plugged in (now ${PCT:-?} %)."; fi
say "  - Wi-Fi: setup downloads BasedOS (about 35 MB)$([ "$FE_COUNT" -gt 0 ] && echo ", and a frontend if you choose one (up to $(gb $FE_MAX_DL) GB)")."
say "  - An SD card you can erase: everything on it is lost. $(a_card $WORST_MIB | sed 's/^a/A/') covers every choice"
say "    (the largest, on this device, needs $(gb $WORST_MIB) GB); setup says what yours needs once you've chosen."
say "  - About 10 to 30 minutes. Don't power off or take the card out while it runs."
[ -n "$CHG" ] || [ -z "$PCT" ] || [ "$PCT" -ge 30 ] || die "the battery is at $PCT %: charge it, or plug the charger in, then run setup again"

if [ -z "$TARGET" ]; then
	say ""
	say "What do you want to do?"
	say "  1) Install BasedOS on the built-in storage (eMMC), next to stock"
	say "  2) Make a BasedOS SD card (the built-in storage isn't touched)"
	say "  3) Make a recovery SD card (it can put the built-in storage back as it is now)"
	ask "Choose 1, 2 or 3:" _a
	case "$_a" in 1) TARGET=emmc ;; 2) TARGET=sd ;; 3) TARGET=recovery ;; *) die "no choice made" ;; esac
fi
case "$TARGET" in emmc|sd|recovery) ;; *) die "--target must be emmc, sd or recovery" ;; esac

if [ "$TARGET" = emmc ]; then
	[ -d "$STOCK_P1/basedos" ] &&
		die "BasedOS is already on the eMMC; uninstall it first (BasedOS's maintenance menu: hold Select at power-on)"
	if [ -z "$REC" ]; then
		say ""
		say "This changes the built-in storage. A recovery card first is recommended: it starts on its"
		say "own and can put the built-in storage back exactly as it is now, without a PC."
		if yes_no "Make a recovery card first?" y; then REC=yes; else REC=no; fi
	fi
fi
[ "$TARGET" = recovery ] && REC=yes
[ "$TARGET" = emmc ] || [ "$REC" = yes ] || REC=no

if [ "$TARGET" = sd ]; then
	say ""
	say "BasedOS goes on the SD card. The built-in storage isn't touched or used while the card runs;"
	say "take the card out to use the device's own system, as now. The card stays in this device."
	if [ -z "$DUAL" ]; then
		say ""
		say "Also put a copy of the stock system on the card? You can start it from BasedOS's maintenance"
		say "menu (hold Select at power-on). It's yours to change; the built-in system isn't touched."
		if yes_no "Copy the stock system to the card?" n; then DUAL=yes; else DUAL=no; fi
	fi
	if [ -z "$BACKUP" ]; then
		say ""
		say "Also save a backup image of the built-in storage on the card, to copy to your PC?"
		if yes_no "Save a backup image?" n; then BACKUP=yes; else BACKUP=no; fi
	fi
	# A frontend from its own upstream release: --frontend <name>, or asked.
	if [ -n "$FE" ] && [ "$FE" != no ]; then
		_l=$(awk -F'|' -v n="$FE" 'tolower($1) == tolower(n) { print NR; exit }' "$T/frontends")
		[ -n "$_l" ] || die "--frontend $FE: no release of it that supports this device"
		fe_pick $_l; FE=yes
	elif [ -z "$FE" ] && [ "$FE_COUNT" -eq 1 ]; then
		fe_pick 1
		say ""
		say "Download $FE_NAME onto the card, so it's ready to use? (about $(gb $FE_DL_MIB) GB to download)"
		say "Otherwise you copy a frontend to the card's BASEOS drive from a PC later."
		if yes_no "Download $FE_NAME?" y; then FE=yes; else FE=no; fi
	elif [ -z "$FE" ] && [ "$FE_COUNT" -gt 1 ]; then
		say ""
		say "Download a frontend onto the card, so it's ready to use?"
		_i=0
		while IFS='|' read -r _n _v _u _s _d _m; do
			_i=$((_i + 1)); say "  $_i) $_n $_v (about $(gb $_d) GB to download)"
		done < "$T/frontends"
		say "  $((_i + 1))) None: I'll copy one from a PC later"
		ask "Choose 1 to $((_i + 1)):" _a
		case "$_a" in ''|*[!0-9]*) die "no choice made" ;; esac
		if [ "$_a" -ge 1 ] && [ "$_a" -le "$_i" ]; then fe_pick "$_a"; FE=yes
		elif [ "$_a" -eq $((_i + 1)) ]; then FE=no
		else die "no choice made"; fi
	fi
	[ "$FE" = yes ] || { FE=no; FE_MIB=0; }
	[ "$FE" = no ] || command -v 7z >/dev/null 2>&1 || die "stock has no 7z, which unpacking $FE_NAME needs"
	NEED_MIB=$(sd_mib $DUAL $BACKUP $FE)
else
	DUAL=no FE=no
	BACKUP=$REC
	NEED_MIB=$REC_MIB
fi
NEED_GB=$(gb $NEED_MIB)

# The card, if there's to be one. Every card this makes is erased first.
CARD=""
if [ "$TARGET" = sd ] || [ "$REC" = yes ]; then
	say ""
	say "This needs an SD card of at least $NEED_GB GB ($(a_card $NEED_MIB) will do). Everything on it is lost."
	while :; do
		CARD=$(disk_of $SDC)
		if [ -z "$CARD" ]; then
			say "Insert the card. (waiting for a card; Ctrl-C to stop)"
			while [ -z "$(disk_of $SDC)" ]; do sleep 1; done
			sleep 2
			CARD=$(disk_of $SDC)
		fi
		CID=$(cat /sys/block/$CARD/device/cid)
		SIZE_MIB=$(( $(cat /sys/block/$CARD/size) / 2048 ))
		SIZE_GB=$(( $(cat /sys/block/$CARD/size) * 512 / 1000000000 ))
		_n=$(ls -d /sys/block/$CARD/${CARD}p* 2>/dev/null | wc -l)
		_l=$(blkid -s LABEL -o value /dev/${CARD}p* 2>/dev/null | tr '\n' ',' | sed 's/,$//; s/,/, /g')
		say ""
		if [ "$_n" -eq 0 ]; then say "Card: $SIZE_GB GB SD card, empty."
		else say "Card: $SIZE_GB GB SD card, with $_n partition$([ "$_n" -gt 1 ] && echo s)${_l:+ ($_l)}: it will be erased."; fi
		problem=""
		[ -n "$CARD_WANT" ] && [ "$CID" != "$CARD_WANT" ] && problem="it isn't the card --card names"
		[ -z "$problem" ] && [ "$(cat /sys/block/$CARD/device/type 2>/dev/null)" != SD ] && problem="it isn't an SD card"
		[ -z "$problem" ] && [ "$SIZE_MIB" -lt "$NEED_MIB" ] && problem="it's $SIZE_GB GB; at least $NEED_GB GB is needed"
		[ -z "$problem" ] && break
		[ -n "$CARD_WANT" ] && die "card not usable: $problem"
		say "This card won't do: $problem."
		say "Take it out and insert another (Ctrl-C to stop)."
		while [ -n "$(disk_of $SDC)" ]; do sleep 1; done
	done
fi

# The summary and the confirmations.
step "About to"
n=0
item() { n=$((n + 1)); say "  $n. $*"; }
if [ "$REC" = yes ]; then
	item "Erase the $SIZE_GB GB card."
	item "Back up the built-in storage onto it (up to $(gb $BK_MIB) GB)."
	item "Make it a recovery card."
	[ -d "$STOCK_P1/basedos" ] && say "     (BasedOS is on the built-in storage now: the card would restore it as it is, with BasedOS.)"
fi
if [ "$TARGET" = sd ]; then
	item "Erase the $SIZE_GB GB card."
	[ "$DUAL" = yes ] && item "Copy the stock system to it."
	[ "$BACKUP" = yes ] && item "Back up the built-in storage onto it (up to $(gb $BK_MIB) GB)."
	item "Put BasedOS $VERSION on it."
	[ "$FE" = yes ] && item "Download $FE_NAME onto it."
	say "  The built-in storage isn't touched."
fi
if [ "$TARGET" = emmc ]; then
	item "Install BasedOS $VERSION on the built-in storage, next to stock."
	[ "$REC" = yes ] && say "     (Only after the recovery card is made and checked.)"
fi
say ""
[ -n "$YES" ] && [ -n "$CARD" ] && [ -z "$CARD_WANT" ] && die "--yes needs --card <ID> when a card is written (--card-id shows it)"
[ -n "$CARD" ] && confirm ERASE "erase this $SIZE_GB GB card"
if [ "$TARGET" = emmc ]; then
	say ""
	say "This modifies the device's built-in storage. If something goes wrong, the device may not start"
	say "until it's restored$([ "$REC" = yes ] && echo " with the recovery card" || echo " from a backup (docs/recovery.md)")."
	confirm INSTALL "confirm that you understand this, know the risks, and have a backup"
fi

# ---------------------------------------------------------------------------------------------
# Phase 2: no more questions.

# The rest of the release, now: the recovery card's files, BasedOS's.
step "Getting BasedOS $VERSION"
[ "$REC" = yes ] && { release_file recovery-initrd.uimg; release_file recovery.scr; }
if [ "$TARGET" != recovery ]; then
	for f in rootfs.squashfs initrd.uimg boot.scr; do release_file $f; done
	mkdir -p "$T/mnt/rootfs" "$T/mnt/stock"
	mount -t squashfs -o ro,loop "$HERE/rootfs.squashfs" "$T/mnt/rootfs" || die "$HERE/rootfs.squashfs does not mount"
	R=$T/mnt/rootfs
	RECIPE=$R/usr/share/basedos/vendor-recipe
	[ "$(cat "$R/usr/share/basedos/needs-vendor" 2>/dev/null)" = "$VENDOR" ] && [ -s "$RECIPE" ] ||
		die "rootfs.squashfs isn't the build release.info describes"
fi
say "ok"

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

# loader: the eMMC's loader (sectors 64 to 32767; the eMMC's p1 starts at 32768) onto the card,
# read back. The card's partitions start at 16 MiB, after it.
loader() {
	dd if=/dev/$EMMC of="$D" bs=512 skip=64 seek=64 count=32704 conv=fsync 2>/dev/null || die "couldn't write the loader"
	echo 3 > /proc/sys/vm/drop_caches
	[ "$(dd if=/dev/$EMMC bs=512 skip=64 count=32704 2>/dev/null | md5sum)" = \
		"$(dd if="$D" bs=512 skip=64 count=32704 2>/dev/null | md5sum)" ] || die "the loader copy doesn't read back"
}

# backup_emmc <drive>: a full backup of the built-in storage in <drive>/backup/, images only:
#   GKD350HUltra-eMMC-<date>.img.zst.001, .002, ...   the main area (mmcblk0) byte for byte, in
#       2000 MiB pieces, each read straight from the eMMC (dd skip/count) and zstd-compressed on
#       its own (zstd decompresses them back to back as one stream; every piece carries zstd's
#       own checksum)
#   GKD350HUltra-eMMC-<date>-boot0.img.zst, -boot1.img.zst   the eMMC's two boot areas
# The main area's MD5 is taken while it's read (one md5sum on a FIFO), and the backup is read back
# and checked against it, the boot areas likewise. Sets BK_DIR, BK_NAME (the name before the
# extensions), BK_MD5, BK_BOOT0_MD5 and BK_BOOT1_MD5.
backup_emmc() {
	step "Backing up the built-in storage"
	BK_DIR=$1/backup
	BK_NAME=GKD350HUltra-eMMC-$(date +%Y%m%d-%H%M)
	mkdir -p "$BK_DIR" || die "can't write $BK_DIR"
	sync
	w0=$(awk '{ print $5 }' /sys/block/$EMMC/${EMMC}p2/stat)
	BK_BOOT0_MD5=$(md5sum < /dev/${EMMC}boot0 | cut -c1-32)
	BK_BOOT1_MD5=$(md5sum < /dev/${EMMC}boot1 | cut -c1-32)
	for b in boot0 boot1; do
		zstd -3 -q -c < /dev/$EMMC$b > "$BK_DIR/$BK_NAME-$b.img.zst" || die "couldn't back up the $b area"
	done
	_bytes=$(( $(cat /sys/block/$EMMC/size) * 512 ))
	_piece=500                              # 4 MiB blocks: 2000 MiB a piece
	_np=$(( (_bytes + _piece * 4194304 - 1) / (_piece * 4194304) ))
	rm -f "$T/fifo"; mkfifo "$T/fifo"
	md5sum < "$T/fifo" | cut -c1-32 > "$T/read.md5" & _m=$!
	exec 3> "$T/fifo"
	_i=0
	while [ $_i -lt $_np ]; do
		_s=$(printf '%03d' $((_i + 1)))
		say "reading and compressing part $((_i + 1)) of $_np..."
		dd if=/dev/$EMMC bs=4M skip=$((_i * _piece)) count=$_piece 2>/dev/null | tee /dev/fd/3 |
			zstd -3 -T0 -q -c > "$BK_DIR/$BK_NAME.img.zst.$_s" || { exec 3>&-; die "the backup didn't complete (is the card full?)"; }
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
	[ ${#BK_MD5} -eq 32 ] && [ "$(cat "$BK_DIR/$BK_NAME.img.zst."* | zstd -dc -q | md5sum | cut -c1-32)" = "$BK_MD5" ] ||
		die "the backup on the card doesn't read back as the built-in storage was read"
	[ "$(zstd -dc -q "$BK_DIR/$BK_NAME-boot0.img.zst" | md5sum | cut -c1-32)" = "$BK_BOOT0_MD5" ] &&
		[ "$(zstd -dc -q "$BK_DIR/$BK_NAME-boot1.img.zst" | md5sum | cut -c1-32)" = "$BK_BOOT1_MD5" ] ||
		die "the boot areas' backup doesn't read back as they were read"
	[ "$w0" = "$w1" ] || say "Note: stock wrote to its data while this copied; the backup is the built-in storage as it was read."
	sync
	say "backup made and checked: $(du -sk "$BK_DIR" | awk '{ printf "%.1f", $1 * 1024 / 1e9 }') GB"
}

# The recovery card: MBR, one FAT32 partition (U-Boot reads FAT, not exFAT), bootable.
if [ "$REC" = yes ]; then
	step "Making the recovery card"
	dd if=/dev/zero of="$D" bs=1M count=8 conv=fsync 2>/dev/null
	parted -s "$D" mklabel msdos mkpart primary fat32 32768s 100% set 1 boot on || die "parted failed"
	new_parts 1
	loader
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
	# What the recovery system checks before it restores: the backup's name, the images' MD5s,
	# and the eMMC it's of (its ID and size).
	cat > "$T/backup.info" <<EOF
NAME=$BK_NAME
IMG_MD5=$BK_MD5
BOOT0_MD5=$BK_BOOT0_MD5
BOOT1_MD5=$BK_BOOT1_MD5
EMMC_CID=$(cat /sys/block/$EMMC/device/cid)
EMMC_SECTORS=$(cat /sys/block/$EMMC/size)
DATE=$(date '+%Y-%m-%d %H:%M')
STOCK=$STOCK_DESC$([ -d "$STOCK_P1/basedos" ] && echo ", with BasedOS")
EOF
	put "$T/backup.info" "$C/recovery/backup.info"
	cat > "$C/RECOVERY.txt" <<EOF
BasedOS recovery card for one GKD 350H Ultra (eMMC ID $(cat /sys/block/$EMMC/device/cid)), made
$(date) by basedos-setup, from $STOCK_DESC.

With this card in, the device starts the restore screen instead of its own system. It checks the
backup, then puts the built-in storage back exactly as it was when this card was made, but only
once you hold A for 5 seconds. B powers off without writing anything. Take the card out to start
normally.

Keep this card as it is. The backup is in backup/: images of the built-in storage, the main area
in numbered pieces (join them in order, then zstd -d, for a plain image a PC can write) and its
two boot areas.
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

# frontend <BASEOS mount>: the chosen frontend's upstream release asset, downloaded onto the
# card's BASEOS drive (not RAM: it's large), checked against GitHub's SHA-256, its unpacked size
# checked against the free space, then unpacked (7z unpacks .7z and .zip alike).
frontend() {
	step "Downloading $FE_NAME"
	_a=$1/.basedos-frontend-download
	fetch "$FE_URL" "$_a" || die "can't download $FE_URL"
	[ "$(sha256sum < "$_a" | cut -c1-64)" = "$FE_SHA" ] || die "the $FE_NAME download doesn't match GitHub's checksum"
	_need=$(7z l -slt "$_a" 2>/dev/null | awk '/^Size = / { s += $3 } END { print int(s / 1048576) + 1 }')
	_free=$(df -m "$1" | awk 'NR == 2 { print $4 }')
	[ "$_need" -gt 1 ] || die "couldn't read the $FE_NAME archive"
	[ "$_need" -lt "$_free" ] || die "$FE_NAME needs $(gb $_need) GB unpacked; the card has $(gb $_free) GB free"
	say "unpacking..."
	7z x -y -bd -o"$1" "$_a" >/dev/null || die "couldn't unpack $FE_NAME"
	rm -f "$_a"
	sync
	say "$FE_NAME is on the card"
}

if [ "$TARGET" = sd ]; then
	step "Partitioning the card"
	dd if=/dev/zero of="$D" bs=1M count=8 conv=fsync 2>/dev/null
	# From 16 MiB (the loader is before it). With a copy of stock: its p1 (FAT) and p2 (ext4), where
	# stock's init mounts them. Then basedos (FAT; the only legacy-bootable partition, so U-Boot never
	# runs a boot script the stock copy's updates write to its p1), data (ext4) and BASEOS (the rest).
	# No-automount on all but BASEOS (bit 63: no drive letter on Windows).
	_at=16
	set --
	if [ "$DUAL" = yes ]; then
		set -- mkpart stock fat32 ${_at}MiB $((_at + CS1_MIB))MiB; _at=$((_at + CS1_MIB))
		set -- "$@" mkpart stock-storage ext4 ${_at}MiB $((_at + CS2_MIB))MiB; _at=$((_at + CS2_MIB))
		BP=3
	else
		BP=1
	fi
	DP=$((BP + 1)) FP=$((BP + 2))
	set -- "$@" mkpart basedos fat32 ${_at}MiB $((_at + BOOT_MIB))MiB; _at=$((_at + BOOT_MIB))
	set -- "$@" mkpart data ext4 ${_at}MiB $((_at + DATA_MIB))MiB; _at=$((_at + DATA_MIB))
	set -- "$@" mkpart BASEOS fat32 ${_at}MiB 100% set $BP legacy_boot on
	_p=1; while [ $_p -lt $FP ]; do set -- "$@" set $_p no_automount on; _p=$((_p + 1)); done
	parted -s "$D" mklabel gpt "$@" || die "parted failed"
	new_parts $FP
	loader
	mkfs.vfat -F 32 -n BASEDOS ${D}p$BP >/dev/null || die "mkfs.vfat p$BP failed"
	mkfs.ext4 -q -F -L basedos-data ${D}p$DP || die "mkfs.ext4 p$DP failed"
	mkfs.vfat -F 32 -n BASEOS ${D}p$FP >/dev/null || die "mkfs.vfat p$FP failed"
	mkdir -p "$T/mnt/boot" "$T/mnt/data" "$T/mnt/card"
	mount -t vfat ${D}p$BP "$T/mnt/boot" && mount -t ext4 ${D}p$DP "$T/mnt/data" && mount -t vfat ${D}p$FP "$T/mnt/card" ||
		die "the new partitions don't mount"
	if [ "$DUAL" = yes ]; then
		mkfs.vfat -F 32 -n STOCK ${D}p1 >/dev/null || die "mkfs.vfat p1 failed"
		mkfs.ext4 -q -F -L stock-storage ${D}p2 || die "mkfs.ext4 p2 failed"
		mkdir -p "$T/mnt/cs1" "$T/mnt/cs2"
		mount -t vfat ${D}p1 "$T/mnt/cs1" && mount -t ext4 ${D}p2 "$T/mnt/cs2" || die "the stock copy's partitions don't mount"
	fi
	say "ok"
	[ "$BACKUP" = yes ] && backup_emmc "$T/mnt/card"
	vendor_set
	step "Writing BasedOS to the card"
	P=$T/mnt/boot
	if [ "$DUAL" = yes ]; then
		say "copying the stock system..."
		for f in "$STOCK_P1"/*; do
			n=${f##*/}
			case "$n" in basedos|boot.scr|boot.scr.*) continue ;; esac
			if [ -d "$f" ]; then cp -a "$f" "$T/mnt/cs1/" || die "couldn't copy $f"
			else put "$f" "$T/mnt/cs1/$n"; fi
		done
		tar -C /storage --exclude=./games-external --exclude=./roms --exclude=./basedos-data -cf - . |
			tar -C "$T/mnt/cs2" -xf - || die "couldn't copy stock's /storage"
		rm -f "$T/mnt/cs2/roms/ports/Return to BasedOS.sh"
		mkdir -p "$T/mnt/cs2/games-external/roms" "$T/mnt/cs2/roms"
		rm -f "$T/mnt/cs2/.please_resize_me" "$T/mnt/cs2/.please_resize_roms_partition"
	fi
	mkdir -p "$P/basedos/vendor-$VENDOR"
	for f in "$VS"/*; do put "$f" "$P/basedos/vendor-$VENDOR/${f##*/}"; done
	put "$HERE/rootfs.squashfs" "$P/basedos/rootfs.squashfs"
	put "$HERE/initrd.uimg" "$P/basedos/initrd.uimg"
	{ echo "basedos_vendor=$VENDOR"; [ "$DUAL" = yes ] && echo "basedos_card_stock=1"; } > "$T/boot.env"
	put "$T/boot.env" "$P/basedos/boot.env"
	mkdir -p "$T/mnt/data/basedos-data"
	seed_data "$T/mnt/data/basedos-data"
	cat > "$T/mnt/card/BasedOS.txt" <<EOF
This card runs BasedOS $VERSION ($BUILD) on the GKD 350H Ultra: with it in, the device starts
BasedOS and the frontend on this drive; without it, the device's own system on its built-in
storage, which BasedOS on this card never uses. The card stays in this device.

$([ "$FE" = yes ] && echo "$FE_NAME is on this BASEOS drive." || echo "Put your frontend here, on this BASEOS drive (for spruce: copy spruce's files to it from your PC).")
BasedOS's own files are on the card's other partitions: don't reformat the card, or it stops
being a BasedOS card.
EOF
	# BasedOS's boot script last: until it's there, the card doesn't boot.
	put "$HERE/boot.scr" "$P/boot.scr"
	sync
	[ "$FE" = yes ] && frontend "$T/mnt/card"
	for m in card data boot cs2 cs1; do
		grep -q " $T/mnt/$m " /proc/mounts || continue
		umount "$T/mnt/$m" || die "can't unmount the card's $m"
	done
	if [ "$FE" = yes ]; then RESULT="BasedOS $VERSION and $FE_NAME are on the card. Restart the device with the card in to start them."
	else RESULT="BasedOS $VERSION is on the card. Power off, copy your frontend (spruce) onto the card's BASEOS drive from a PC, put the card back in and power on."; fi
	[ "$BACKUP" = yes ] && RESULT="$RESULT The backup is in the backup folder on the BASEOS drive: copy it to your PC and keep it."
elif [ "$TARGET" = emmc ]; then
	vendor_set
	step "Installing BasedOS on the built-in storage"
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
	RESULT="The recovery card is ready. Power off and take it out; keep it safe. To restore the built-in storage: power off, put the card in, power on, and follow the screen."
fi

rm -rf "${VS:-$T/none}"
# The card stays out of stock's automounter until the next power-on: released now, it would mount
# the new card's partitions and write to them.
[ -n "${UDEV_HELD:-}" ] && UDEV_HELD=""
cleanup
# setup's own folder in RAM, once nothing is mounted under it.
grep -q " $T/" /proc/mounts || rm -rf "$T"
step "Done"
say "$RESULT"
exit 0
