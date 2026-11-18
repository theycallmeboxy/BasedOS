# POSIX syntax check of every BasedOS shell script, with dash (stricter than BusyBox ash), and a
# parse of the Python one.
cd /mnt/e/projects/spruceOS-gkd350hultra/basedos
rc=0
for f in initrd/basedos/init overlay/etc/init.d/* overlay/usr/sbin/mount-frontend overlay/usr/sbin/frontend-session overlay/usr/sbin/basedos-suspend overlay/usr/lib/basedos/functions overlay/usr/share/udhcpc/default.script tools/install-dev.sh tools/dev/update-basedos.sh; do
	dash -n "$f" || { echo "SYNTAX: $f"; rc=1; }
done
python3 -c 'import ast, sys; ast.parse(open(sys.argv[1]).read())' overlay/usr/sbin/basedos-shutdown-keys || { echo "SYNTAX: overlay/usr/sbin/basedos-shutdown-keys"; rc=1; }
exit $rc
