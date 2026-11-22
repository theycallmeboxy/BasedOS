#!/bin/bash
# Uninstall BasedOS: in stock's Ports while BasedOS is installed (setup puts it there; BasedOS puts
# it back whenever it hands over to stock). Asks first, on screen, with stock's own text_viewer
# (Stock runs a Ports script with its output going to a log). Then, with BasedOS not running and
# none of its files in use: stock's boot script back if BasedOS's is the active one (checked and
# read back), BasedOS's folder on the boot partition and its data on the data partition removed,
# and both Ports entries removed. Stock's own files are never touched; nor is the frontend card.
P1=/flash
B=$P1/basedos
DATA=/storage/basedos-data
LOG=/storage/basedos-uninstall.log
# text_viewer -y: "shows a yes button with different exit code". The code for Yes, as found on the
# device; anything else is no, so a wrong value here only means nothing is removed (the code
# text_viewer gave is logged).
YES=21
show() { /usr/bin/text_viewer "$@" >/dev/null 2>&1; }
fail() {
	echo "$(date) uninstall: ${2:-$1}" >> $LOG
	show -e -w -t "Uninstall BasedOS" -m "$1 BasedOS is still installed."
	exit 1
}
# scr_ok <file>: a whole U-Boot script image: its magic, the type "script", and the size its header
# gives (as basedos-boot checks them).
scr_ok() {
	[ -s "$1" ] || return 1
	[ "$(dd if="$1" bs=4 count=1 2>/dev/null | od -An -tx1 | tr -d ' \n')" = 27051956 ] || return 1
	[ "$(dd if="$1" bs=1 skip=30 count=1 2>/dev/null | od -An -tu1 | tr -d ' \n')" = 6 ] || return 1
	_len=$(dd if="$1" bs=1 skip=12 count=4 2>/dev/null | od -An -tu1 | awk '{print (($1*256+$2)*256+$3)*256+$4}')
	[ "$(wc -c < "$1" | tr -d ' ')" = "$((_len + 64))" ]
}
is_basedos() { dd if="$1" bs=64 skip=1 2>/dev/null | grep -q "rdinit=/basedos/init"; }

[ -d $B ] || { show -w -t "Uninstall BasedOS" -m "BasedOS isn't installed."; exit 0; }
show -y -t "Uninstall BasedOS?" -m "Removes BasedOS and its settings. Stock and your SD card aren't touched. This can't be undone."
rc=$?
echo "$(date) uninstall: text_viewer answered $rc (yes is $YES)" >> $LOG
[ "$rc" -eq $YES ] || exit 0

# Stock's boot script, if BasedOS's is the active one: the saved copy must be a whole stock script.
if is_basedos $P1/boot.scr; then
	SAVED=$P1/boot.scr.stock
	scr_ok "$SAVED" && ! is_basedos "$SAVED" || fail "Couldn't uninstall BasedOS." "BasedOS's saved copy of stock's boot script isn't a whole one"
	mount -o remount,rw $P1 || fail "Couldn't uninstall BasedOS." "can't write $P1"
	rm -f $P1/boot.scr.new
	if ! { cp "$SAVED" $P1/boot.scr.new && sync && echo 3 > /proc/sys/vm/drop_caches &&
		[ "$(md5sum < "$SAVED")" = "$(md5sum < $P1/boot.scr.new)" ] &&
		mv $P1/boot.scr.new $P1/boot.scr && sync &&
		[ "$(md5sum < "$SAVED")" = "$(md5sum < $P1/boot.scr)" ]; }; then
		rm -f $P1/boot.scr.new; sync; mount -o remount,ro $P1
		fail "Couldn't uninstall BasedOS." "couldn't write $P1/boot.scr"
	fi
else
	scr_ok $P1/boot.scr || fail "Couldn't uninstall BasedOS." "$P1/boot.scr doesn't look like a whole boot script"
	mount -o remount,rw $P1 || fail "Couldn't uninstall BasedOS." "can't write $P1"
fi
# Then BasedOS's files: nothing boots them any more. An older developer update's copy of BasedOS's
# boot script beside stock's files goes too (the initrd's uninstall removes it the same way).
rm -rf $B
# Stock's boot script is back under its own name: its copy goes (only if it is that file).
[ "$(md5sum < $P1/boot.scr.stock 2>/dev/null)" = "$(md5sum < $P1/boot.scr)" ] && rm -f $P1/boot.scr.stock
is_basedos $P1/boot.scr.prev 2>/dev/null && rm -f $P1/boot.scr.prev
sync
mount -o remount,ro $P1
rm -rf $DATA
# Stock's Ports entries: both places BasedOS writes them (p2's own roms/ports through a plain bind
# of /storage, which shows p2 without what's mounted over /storage/roms), and older ones.
r=/tmp/basedos-uninstall-p2
mkdir -p $r && mount --bind /storage $r || r=""
for d in /storage/games-internal/roms/ports ${r:+$r/roms/ports} /storage/roms/ports /storage/.config/modules; do
	rm -f "$d/Enable BasedOS.sh" "$d/Disable BasedOS.sh" "$d/Return to BasedOS.sh" "$d/Uninstall BasedOS.sh"
done
[ -n "$r" ] && umount $r; rmdir /tmp/basedos-uninstall-p2 2>/dev/null
sync
echo "$(date) uninstall: done" >> $LOG
show -t "Uninstall BasedOS" -m "BasedOS is uninstalled."
exit 0
