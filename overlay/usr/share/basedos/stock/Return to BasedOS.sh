#!/bin/bash
# Return to BasedOS: in stock's Ports while BasedOS is switched off (basedos-boot switch-to-stock).
# Puts BasedOS's boot script back and restarts into BasedOS. Runs on stock (bash and BusyBox; no
# cmp, so it checks with md5sum and od). Stock runs a Ports script with its output going to a log,
# so what it has to say goes on screen through stock's own text_viewer.
#
# Nothing changes unless BasedOS can start on this stock: one of its system layers must be made for
# this stock build (its needs-stock against stock's BUILD_ID), or BasedOS's initrd would refuse it
# and start stock anyway, with this entry gone.
P1=/flash
SAVED=$P1/basedos/boot.scr.basedos
NAME="Return to BasedOS.sh"
show() { /usr/bin/text_viewer "$@" >/dev/null 2>&1; }
fail() {
	echo "Return to BasedOS: $*" >&2
	show -e -w -t "Return to BasedOS" -m "$* Still stock; nothing changed."
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
# layer_fits <squashfs>: 0 if that system layer is made for this stock build.
STOCK_ID=$(sed -n 's/^BUILD_ID="\{0,1\}\([0-9a-f]*\)"\{0,1\}$/\1/p' /etc/os-release)
layer_fits() {
	[ -f "$1" ] && [ -n "$STOCK_ID" ] || return 1
	_m=/tmp/basedos-return.$$
	mkdir -p "$_m" || return 1
	if ! mount -t squashfs -o ro,loop "$1" "$_m" 2>/dev/null; then rmdir "$_m"; return 1; fi
	_want=$(cat "$_m/usr/share/basedos/needs-stock" 2>/dev/null)
	umount "$_m"; rmdir "$_m"
	[ "$_want" = "$STOCK_ID" ]
}

[ -f "$SAVED" ] || fail "BasedOS's boot script isn't there ($SAVED)."
scr_ok "$SAVED" || fail "$SAVED isn't a whole boot script."
dd if="$SAVED" bs=64 skip=1 2>/dev/null | grep -q "rdinit=/basedos/init" || fail "$SAVED isn't BasedOS's."
[ -f $P1/basedos/initrd.uimg ] || fail "BasedOS's files are gone ($P1/basedos/initrd.uimg)."
layer_fits $P1/basedos/rootfs.squashfs || layer_fits $P1/basedos/rootfs-b.squashfs ||
	fail "BasedOS isn't made for this stock build (${STOCK_ID:-unknown}): stock has changed since BasedOS was installed, and BasedOS wouldn't start on it."
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
