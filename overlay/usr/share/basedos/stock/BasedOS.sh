#!/bin/bash
# BasedOS, in stock's Ports: BasedOS's menu on stock. The same file is on the built-in storage (setup
# and BasedOS put it in stock's Ports, and it stays while BasedOS is installed) and on a setup card
# (roms/ports, beside the release in basedos-setup/; tools/wsl/release.sh). One menu, with what
# applies:
#   - a setup card's release (basedos-setup/ at the root of a mounted card): setup,
#     basedos-setup.sh --screen: install or repair, a recovery card, uninstall, and Disable or
#     Enable while BasedOS is installed. The release is copied into memory first and checked
#     against its SHA256SUMS, on the screen (load, with the screens from the card's system
#     layer), so the card can be taken out, or erased as the recovery card.
#   - otherwise the installed BasedOS's menu (/usr/share/basedos/stock/menu): Disable or Enable,
#     Uninstall.
# The screens and actions come from that BasedOS's system layer (/usr/share/basedos/stock/ and
# BasedOS's two screen programs), copied into memory, so they change with BasedOS's updates. They
# run as a service of their own, because they stop stock's frontend while they run (stopping the
# frontend stops what it started, as this script). Stock runs a Ports script with its output going
# to a log, so what goes wrong before that is said through stock's own text_viewer.
UI=/tmp/basedos-ui M=/tmp/basedos-ui.layer
stop() {
	/usr/bin/text_viewer -e -w -t "BasedOS" -m "$1" >/dev/null 2>&1
	umount $M 2>/dev/null; rmdir $M 2>/dev/null
	rm -rf $UI
	exit 1
}
# ui_from <system layer>: its screens and actions into $UI.
ui_from() {
	rm -rf $UI; mkdir -p $UI $M
	mount -t squashfs -o ro,loop "$1" $M 2>/dev/null || return 1
	cp $M/usr/share/basedos/stock/* $M/usr/bin/basedos-splash $M/usr/bin/basedos-keys $M/etc/baseos-release $UI/ 2>/dev/null
	umount $M
	[ -f $UI/screen.sh ] && [ -f $UI/menu ] && [ -x $UI/basedos-splash ] && [ -x $UI/basedos-keys ]
}

src=""
while read -r _dev mp _rest; do
	[ -f "$mp/basedos-setup/basedos-setup.sh" ] && [ -f "$mp/basedos-setup/SHA256SUMS" ] && { src=$mp/basedos-setup; break; }
done < /proc/mounts
if [ -n "$src" ]; then
	# The screens straight from the card's system layer, only to show the copy and the check
	# (load); setup runs with the checked copy's.
	ui_from "$src/rootfs.squashfs" && [ -f $UI/load ] ||
		stop "The setup files on the SD card are damaged, or older than this entry: unpack the setup card zip onto it again."
	set -- /bin/bash $UI/load "$src"
else
	# An installed update waits as rootfs.new: its menu first.
	for s in /flash/basedos/rootfs.new /flash/basedos/rootfs.squashfs; do
		[ -f $s ] && ui_from $s && break
		rm -rf $UI
	done
	[ -f $UI/menu ] || stop "BasedOS's files are missing or damaged: run BasedOS's setup to repair it. Nothing was changed."
	set -- /bin/bash $UI/menu
fi
rmdir $M 2>/dev/null
systemd-run --quiet --collect --unit=basedos-stock --setenv=UI=$UI "$@"
# This waits beside it (stock's frontend shows a running port meanwhile) until stopping the
# frontend ends it.
while systemctl -q is-active basedos-stock; do sleep 1; done
