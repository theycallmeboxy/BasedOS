# POSIX syntax check of every BasedOS shell script, with dash (stricter than BusyBox ash).
cd /mnt/e/projects/spruceOS-gkd350hultra/basedos
rc=0
for f in initrd/basedos/init overlay/etc/init.d/* overlay/usr/sbin/mount-frontend overlay/usr/sbin/frontend-session overlay/usr/sbin/basedos-suspend overlay/usr/sbin/basedos-udev overlay/usr/sbin/basedos-boot overlay/usr/sbin/basedos-menu overlay/usr/sbin/basedos-update overlay/usr/lib/basedos/functions overlay/usr/share/udhcpc/default.script tools/install-dev.sh tools/basedos-setup.sh tools/recovery/init tools/dev/update-basedos.sh; do
	dash -n "$f" || { echo "SYNTAX: $f"; rc=1; }
done
exit $rc
