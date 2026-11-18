#!/bin/sh
# Mainline experiment: drive the test card over SSH, from either kernel, so it never has to
# leave the 350H Ultra. Run from Git Bash on the PC (uses tools/dev/gkdssh.py; GKD_HOST
# defaults to 10.0.99.184, root with an empty password, as without a spruce card).
#
#   remote.sh deploy        copy out/mainline/card/ (tools/mainline/mkcard.py) to the card,
#                           check it, clear boot-emmc and reboot into the new mainline build
#   remote.sh stock         set mainline/boot-emmc and reboot: the card boots the eMMC
#   remote.sh mainline      clear mainline/boot-emmc and reboot into mainline
#   remote.sh logs [<n>]    the latest probe log (or run <n>) into out/mainline/logs/<n>/
#   remote.sh run '<cmd>'   a command on the device
#
# On mainline the card is /card (the probe binds it into the SSH session); on the stock
# kernel BasedOS mounts it on /mnt/SDCARD.
set -e
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
VENV=$ROOT/../.venv/Scripts/python
export MSYS_NO_PATHCONV=1 GKD_HOST=${GKD_HOST:-10.0.99.184} GKD_USER=${GKD_USER:-root} GKD_PASS=${GKD_PASS-}
# Each step retried: on a flaky link most failures are the connection, not the command.
gk() {
	_i=0
	while :; do
		_out=$("$VENV" "$(cygpath -w "$ROOT/tools/dev/gkdssh.py")" "$@" 2>&1) && { printf '%s\n' "$_out"; return 0; }
		_i=$((_i + 1))
		case "$_out" in
		*TimeoutError*|*"Unable to connect"*|*"Error reading SSH"*|*EOFError*|*"No existing session"*) ;;
		*) printf '%s\n' "$_out" >&2; return 1 ;;
		esac
		[ $_i -lt 8 ] || { echo "SSH: no connection after $_i tries" >&2; return 1; }
		sleep 3
	done
}
win() { cygpath -w "$1"; }

# The card's mount point and the right reboot for the running kernel.
FIND='for C in /card /mnt/SDCARD; do [ -d $C/mainline ] && break; C=; done; [ -n "$C" ] || { echo "no test card mounted" >&2; exit 1; }'
REBOOT='sync; case $(uname -r) in 7.*) (sleep 1; reboot -f) >/dev/null 2>&1 & ;; *) (sleep 1; reboot) >/dev/null 2>&1 & ;; esac'

case "$1" in
deploy)
	SRC=$ROOT/out/mainline/card
	[ -f "$SRC/boot.scr" ] || { echo "no $SRC: run tools/mainline/mkcard.py first"; exit 1; }
	FILES="boot.scr mainline/Image mainline/rk3576-gkd-350h-ultra.dtb mainline/probe.uimg"
	# Git Bash's md5sum marks binary files with a '*' before the name; drop it.
	sums=$(cd "$SRC" && md5sum $FILES | sed 's/ [*]/  /')
	# Only what differs from the card's copy goes over the air.
	stale=$(gk run "$FIND; cd \$C && echo '$sums' | md5sum -c - 2>/dev/null | sed -n 's/: FAILED.*//p'; \
		echo '$sums' | while read s f; do [ -e \"\$f\" ] || echo \"\$f\"; done; echo CHECKED") ||
		{ echo "couldn't check the card"; exit 1; }
	case "$stale" in *CHECKED*) ;; *) echo "couldn't check the card"; exit 1 ;; esac
	stale=$(printf '%s\n' "$stale" | grep -v '^CHECKED$' | sort -u)
	gk run 'rm -rf /tmp/ml && mkdir -p /tmp/ml' >/dev/null
	for f in $stale; do
		echo "pushing $f"
		gk push "$(win "$SRC/$f")" "/tmp/ml/$(basename "$f")" >/dev/null
		gk run "$FIND; cp /tmp/ml/$(basename "$f") \$C/$f && sync"
	done
	[ -n "$stale" ] || echo "the card already has this build"
	# Reboot only onto a card that matches the build.
	gk run "$FIND
		cd \$C && echo '$sums' | md5sum -c - || exit 1
		rm -f mainline/boot-emmc; rm -rf /tmp/ml
		echo \"deployed to \$C; rebooting into mainline\"; $REBOOT" ||
		{ echo "the card doesn't match the build: not rebooting"; exit 1; }
	;;
stock)
	# Not empty: U-Boot's load of an empty file may count as a failure.
	gk run "$FIND; echo emmc > \$C/mainline/boot-emmc; echo 'boot-emmc set; rebooting into the eMMC'; $REBOOT"
	;;
mainline)
	gk run "$FIND; rm -f \$C/mainline/boot-emmc; echo 'boot-emmc cleared; rebooting into mainline'; $REBOOT"
	;;
logs)
	n=$(gk run "$FIND; ls \$C/mainline/logs | sort -n | tail -1")
	n=${2:-$n}
	gk run "$FIND; tar -C \$C/mainline/logs -cf /tmp/log-$n.tar $n"
	mkdir -p "$ROOT/out/mainline/logs"
	gk pull "/tmp/log-$n.tar" "$(win "$ROOT/out/mainline/logs/$n.tar")" | tail -1
	tar -C "$ROOT/out/mainline/logs" -xf "$ROOT/out/mainline/logs/$n.tar" && rm "$ROOT/out/mainline/logs/$n.tar"
	echo "out/mainline/logs/$n"
	;;
run)
	shift
	gk run "$*"
	;;
*)
	sed -n '2,15p' "$0"
	exit 2
	;;
esac
