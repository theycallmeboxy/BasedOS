#!/bin/bash
# Return to BasedOS: in stock's Ports while BasedOS is switched off (basedos-boot switch-to-stock).
# Puts BasedOS's boot script back and restarts into BasedOS. Runs on stock (bash and BusyBox; no
# cmp, so it checks with md5sum and od). Stock runs a Ports script with its output going to a log,
# so what it has to say goes on screen through stock's own text_viewer.
P1=/flash
SAVED=$P1/basedos/boot.scr.basedos
NAME="Return to BasedOS.sh"
show() { /usr/bin/text_viewer "$@" >/dev/null 2>&1; }
fail() {
	echo "Return to BasedOS: $*" >&2
	show -e -w -t "Return to BasedOS" -m "$* Still stock; nothing changed."
	exit 1
}
[ -f "$SAVED" ] || fail "BasedOS's boot script isn't there ($SAVED)."
[ "$(dd if="$SAVED" bs=4 count=1 2>/dev/null | od -An -tx1 | tr -d ' \n')" = 27051956 ] ||
	fail "$SAVED isn't a boot script."
dd if="$SAVED" bs=64 skip=1 2>/dev/null | grep -q "rdinit=/basedos/init" || fail "$SAVED isn't BasedOS's."
[ -f $P1/basedos/initrd.uimg ] || fail "BasedOS's files are gone ($P1/basedos/initrd.uimg)."
ls $P1/basedos/rootfs*.squashfs >/dev/null 2>&1 || fail "BasedOS's system image is gone."
mount -o remount,rw $P1 || fail "Can't write $P1."
rm -f $P1/boot.scr.new
if cp "$SAVED" $P1/boot.scr.new && sync && echo 3 > /proc/sys/vm/drop_caches &&
	[ "$(md5sum < "$SAVED")" = "$(md5sum < $P1/boot.scr.new)" ] &&
	mv $P1/boot.scr.new $P1/boot.scr && sync &&
	[ "$(md5sum < "$SAVED")" = "$(md5sum < $P1/boot.scr)" ]; then
	rm -f "$SAVED"
	mount -o remount,ro $P1
	# Itself, wherever BasedOS has put it (Ports as stock reads it, and older places).
	for d in /storage/games-internal/roms/ports /storage/roms/ports /storage/.config/modules; do rm -f "$d/$NAME"; done
	sync
	echo "Back to BasedOS: restarting."
	reboot
else
	rm -f $P1/boot.scr.new
	sync
	mount -o remount,ro $P1
	fail "Couldn't write $P1/boot.scr."
fi
