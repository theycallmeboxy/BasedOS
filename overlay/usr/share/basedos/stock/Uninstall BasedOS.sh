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
	echo "$(date) uninstall: $*" >> $LOG
	show -e -w -t "Uninstall BasedOS" -m "$* BasedOS is still installed."
	exit 1
}
is_scr() { [ "$(dd if="$1" bs=4 count=1 2>/dev/null | od -An -tx1 | tr -d ' \n')" = 27051956 ]; }
is_basedos() { dd if="$1" bs=64 skip=1 2>/dev/null | grep -q "rdinit=/basedos/init"; }

[ -d $B ] || { show -w -t "Uninstall BasedOS" -m "BasedOS isn't installed."; exit 0; }
show -y -t "Uninstall BasedOS?" -m "This removes BasedOS and its settings from the device. Stock stays as it is, and the frontend card isn't touched. There's no undo."
rc=$?
echo "$(date) uninstall: text_viewer answered $rc (yes is $YES)" >> $LOG
[ "$rc" -eq $YES ] || exit 0

# Stock's boot script, if BasedOS's is the active one: the saved copy must be stock's.
if is_basedos $P1/boot.scr; then
	SAVED=$B/boot.scr.stock
	is_scr "$SAVED" && ! is_basedos "$SAVED" || fail "BasedOS's saved copy of stock's boot script isn't one."
	mount -o remount,rw $P1 || fail "Can't write $P1."
	rm -f $P1/boot.scr.new
	if ! { cp "$SAVED" $P1/boot.scr.new && sync && echo 3 > /proc/sys/vm/drop_caches &&
		[ "$(md5sum < "$SAVED")" = "$(md5sum < $P1/boot.scr.new)" ] &&
		mv $P1/boot.scr.new $P1/boot.scr && sync &&
		[ "$(md5sum < "$SAVED")" = "$(md5sum < $P1/boot.scr)" ]; }; then
		rm -f $P1/boot.scr.new; sync; mount -o remount,ro $P1
		fail "Couldn't write $P1/boot.scr."
	fi
else
	is_scr $P1/boot.scr || fail "$P1/boot.scr doesn't look like a boot script."
	mount -o remount,rw $P1 || fail "Can't write $P1."
fi
# Then BasedOS's files: nothing boots them any more.
rm -rf $B
sync
mount -o remount,ro $P1
rm -rf $DATA
for d in /storage/games-internal/roms/ports /storage/roms/ports /storage/.config/modules; do
	rm -f "$d/Return to BasedOS.sh" "$d/Uninstall BasedOS.sh"
done
sync
echo "$(date) uninstall: done" >> $LOG
show -t "Uninstall BasedOS" -m "BasedOS is uninstalled. Stock is as it was before BasedOS."
exit 0
