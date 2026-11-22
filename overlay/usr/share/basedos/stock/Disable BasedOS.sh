#!/bin/bash
# Disable BasedOS: in stock's Ports while BasedOS is on (stock started once from it, or just after
# setup). The same as "Disable BasedOS" in BasedOS's maintenance menu (basedos-boot disable): stock's
# own boot script goes back in place, so stock starts from now on; BasedOS's files stay, and an
# "Enable BasedOS" entry in stock's Ports turns it back on. Stock is running already, so nothing
# restarts. Runs on stock (bash and BusyBox; no cmp, so it checks with md5sum and od). Stock runs a
# Ports script with its output going to a log, so what it has to say goes on screen through stock's
# own text_viewer.
#
# As careful as basedos-boot: both boot scripts are checked first (whole script images, BasedOS's
# and stock's as expected), "Enable BasedOS" is in place and BasedOS's script saved and read back
# before boot.scr changes, and boot.scr is written as boot.scr.new, read back, then renamed.
P1=/flash
B=$P1/basedos
# Stock's Ports: games-internal/roms/ports, or p2's own roms/ports when stock's automount bound
# nothing on /storage/roms (its setting "external" with a spruce card in; basedos-boot, Stock's
# Ports). Never the card's.
PORTS=/storage/games-internal/roms/ports
OWN=""
grep -q " /storage/roms " /proc/mounts || OWN=/storage/roms/ports
NAME="Disable BasedOS.sh"
ENABLE="Enable BasedOS.sh"
show() { /usr/bin/text_viewer "$@" >/dev/null 2>&1; }
fail() {
	echo "Disable BasedOS: ${2:-$1}" >&2
	show -e -w -t "Disable BasedOS" -m "$1 Nothing was changed."
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
# put <src> <dst>: written as <dst>.new, read back, renamed, read back.
put() {
	rm -f "$2.new"
	cp "$1" "$2.new" && sync && echo 3 > /proc/sys/vm/drop_caches &&
		[ "$(md5sum < "$1")" = "$(md5sum < "$2.new")" ] &&
		mv "$2.new" "$2" && sync &&
		[ "$(md5sum < "$1")" = "$(md5sum < "$2")" ] && return 0
	rm -f "$2.new"
	return 1
}

scr_ok $P1/boot.scr && is_basedos $P1/boot.scr ||
	fail "BasedOS is already disabled."
scr_ok $P1/boot.scr.stock && ! is_basedos $P1/boot.scr.stock ||
	fail "BasedOS's files are damaged." "stock's saved boot script ($P1/boot.scr.stock) isn't there or isn't whole"

# 1. "Enable BasedOS" in Ports, from BasedOS's system layer (an installed update's first: it's
# the one that would boot).
m=/tmp/basedos-disable.$$
mkdir -p "$m" "$PORTS" $OWN || fail "Couldn't disable BasedOS." "can't make $m or $PORTS"
got=""
for s in rootfs.new rootfs.squashfs; do
	[ -f "$B/$s" ] || continue
	mount -t squashfs -o ro,loop "$B/$s" "$m" 2>/dev/null || continue
	if [ -f "$m/usr/share/basedos/stock/$ENABLE" ] && put "$m/usr/share/basedos/stock/$ENABLE" "$PORTS/$ENABLE" &&
		{ [ -z "$OWN" ] || put "$m/usr/share/basedos/stock/$ENABLE" "$OWN/$ENABLE"; }; then
		got=1
	fi
	umount "$m"
	[ -n "$got" ] && break
done
rmdir "$m"
[ -n "$got" ] || fail "Couldn't disable BasedOS." "couldn't put 'Enable BasedOS' in stock's Ports"
chmod 755 "$PORTS/$ENABLE" ${OWN:+"$OWN/$ENABLE"}
undo() { rm -f "$PORTS/$ENABLE" ${OWN:+"$OWN/$ENABLE"}; sync; }

# 2. BasedOS's boot script saved, then stock's in its place.
mount -o remount,rw $P1 || { undo; fail "Couldn't disable BasedOS." "can't write $P1"; }
if ! put $P1/boot.scr $B/boot.scr.basedos; then
	rm -f $B/boot.scr.basedos; sync; mount -o remount,ro $P1; undo
	fail "Couldn't disable BasedOS." "couldn't save BasedOS's boot script"
fi
if ! put $P1/boot.scr.stock $P1/boot.scr; then
	# boot.scr is one whole file or the other (put renames only once the copy reads back).
	[ "$(md5sum < $B/boot.scr.basedos)" = "$(md5sum < $P1/boot.scr)" ] || put $B/boot.scr.basedos $P1/boot.scr
	rm -f $B/boot.scr.basedos; sync; mount -o remount,ro $P1; undo
	fail "Couldn't disable BasedOS." "couldn't write stock's boot script"
fi
sync
mount -o remount,ro $P1
# Itself, and the older name of the way back.
for d in $PORTS /storage/roms/ports /storage/.config/modules; do rm -f "$d/$NAME" "$d/Return to BasedOS.sh"; done
sync
echo "$(date) disable: stock's boot script in place" >> /storage/basedos-data/basedos.log 2>/dev/null
show -t "Disable BasedOS" -m "BasedOS is disabled: the device boots stock from now on. BasedOS stays installed. To boot it again, run Enable BasedOS from Ports."
exit 0
