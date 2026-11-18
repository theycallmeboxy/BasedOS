# Mainline experiment: the Mali Bifrost kernel driver (mali_kbase.ko) for the mainline kernel,
# as ROCKNIX builds it for RK3576 (packages/linux-drivers/mali-bifrost: rocknix/mali_kbase,
# its RK3576 patches, the devicetree platform). Stock's libmali (g24p0, harvested into BasedOS)
# or ROCKNIX's (g29p1) talks to it through /dev/mali0. Run in WSL after fetch.sh and build.sh:
#   sh tools/mainline/build-mali.sh
# Output: out/mainline/mali_kbase.ko
set -e
R=/mnt/e/projects/spruceOS-gkd350hultra/basedos
W=~/mainline
K=$(ls -d $W/linux-*/ | sort -V | tail -1); K=${K%/}
P=$W/rocknix/projects/ROCKNIX
mk=$P/packages/linux-drivers/mali-bifrost/package.mk
ver=$(sed -n 's/^PKG_VERSION="\(.*\)"/\1/p' "$mk")
sha=$(sed -n 's/^PKG_SHA256="\(.*\)"/\1/p' "$mk")
cd "$W"
tar=mali_kbase-$ver.tar.gz
[ -f "$tar" ] || curl -fsL -o "$tar" "https://github.com/rocknix/mali_kbase/archive/$ver.tar.gz"
echo "$sha  $tar" | sha256sum -c --quiet
rm -rf "mali_kbase-$ver"
tar xf "$tar"
cd "mali_kbase-$ver"
for p in "$P"/devices/RK3576/patches/mali-bifrost/*.patch; do
	patch -s -p1 -N < "$p"
done
D=product/kernel/drivers/gpu/arm/midgard
# Through the driver's own Makefile, as ROCKNIX does (kernel_make KDIR=... -C midgard): it sets
# the DDK's defaults, CONFIG_MALI_DEVFREQ=y among them. Going straight to the kernel's Kbuild
# (make -C $K M=...) skips them, and without devfreq the GPU sat at 131 MHz.
make -C "$D" KDIR="$K" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j"$(nproc)" \
	CONFIG_MALI_MIDGARD=m CONFIG_MALI_PLATFORM_NAME=devicetree CONFIG_MALI_REAL_HW=y >/dev/null
strings "$D/mali_kbase.ko" | grep -q "devfreq" || { echo "mali_kbase built without devfreq"; exit 1; }
aarch64-linux-gnu-strip --strip-debug "$D/mali_kbase.ko"
cp "$D/mali_kbase.ko" "$R/out/mainline/"
find . -name '*.ko' | sed "s|^|built: |"
echo "mali_kbase $ver: $(du -h "$R/out/mainline/mali_kbase.ko" | cut -f1)"
