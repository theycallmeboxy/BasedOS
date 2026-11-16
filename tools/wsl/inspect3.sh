R=$HOME/basedos-work/stock-root
cd $R
cat usr/bin/gpudriver | head -80
echo "== overlays"; ls -la usr/lib/kernel-overlays/base usr/lib/kernel-overlays/base/lib; du -sh usr/lib/kernel-overlays/base/lib/firmware; find usr/lib/kernel-overlays/base/lib/firmware -maxdepth 2 | head -40
