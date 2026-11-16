R=$HOME/basedos-work/stock-root
cd $R
grep -rs bcmdhd etc/modprobe.d usr/lib/modprobe.d etc/modules-load.d usr/lib/modules-load.d usr/lib/systemd/system 2>/dev/null | head
grep -rlsE "bcmdhd|insmod|modprobe .*bcm" usr/bin usr/lib/rocknix usr/lib/autostart usr/sbin 2>/dev/null | head
ls usr/lib/libdrm.so* usr/lib/libnss_files* usr/lib/libnss_dns* usr/lib/libresolv* usr/lib/libudev.so* 2>&1 | tr '\n' ' '
