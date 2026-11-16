R=$HOME/basedos-work/stock-root
cd $R
ls -la usr/lib/modules usr/lib/firmware lib 2>&1
echo "== 003-gpudriver"; cat usr/lib/autostart/common/003-gpudriver
echo "== real module/firmware dirs"; ls -d usr/lib/kernel-overlays* var/lib/kernel-overlays* 2>/dev/null; find . -name "bcmdhd*.ko*" -o -name "modules.dep" 2>/dev/null | head; find . -type d -name brcm 2>/dev/null | head
