# Mainline experiment: build ROCKNIX's RK3576 kernel (from tools/mainline/fetch.sh) with the
# 350H Ultra device tree. Run in WSL:
#   sh tools/mainline/build.sh
# Output in out/mainline/: Image, rk3576-gkd-350h-ultra.dtb, modules.tar (lib/modules/...).
set -e
R=/mnt/e/projects/spruceOS-gkd350hultra/basedos
K=$(ls -d ~/mainline/linux-*/ | sort -V | tail -1); K=${K%/}
O=$R/out/mainline
DTS=rk3576-gkd-350h-ultra
J=$(nproc)
mk() { make -C "$K" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j"$J" "$@"; }
cd "$K"

# Without the device tree yet (it's being written), build the kernel alone.
[ -f "$R/tools/mainline/dts/$DTS.dts" ] && dtb="rockchip/$DTS.dtb" || dtb=
[ -z "$dtb" ] || cp "$R/tools/mainline/dts/$DTS.dts" arch/arm64/boot/dts/rockchip/
[ -z "$dtb" ] || grep -q "$DTS.dtb" arch/arm64/boot/dts/rockchip/Makefile ||
	echo "dtb-\$(CONFIG_ARCH_ROCKCHIP) += $DTS.dtb" >> arch/arm64/boot/dts/rockchip/Makefile

# ROCKNIX's RK3576 config, plus what the 350H Ultra has that the RG Vita Pro doesn't:
# the BQ25892 charger, the ES9018K2M DAC (BasedOS's driver, tools/mainline/drivers), Broadcom
# SDIO Wi-Fi (a module: it needs its firmware), and an uncompressed-or-gzip initrd (ours is a
# plain cpio), loaded by U-Boot rather than built in (ROCKNIX fills @INITRAMFS_SOURCE@ with
# its own).
cp .rocknix-config .config
scripts/config --file .config \
	--set-str LOCALVERSION "-basedos" \
	--set-str INITRAMFS_SOURCE "" \
	--enable CHARGER_BQ25890 \
	--enable SND_SOC_ES9018K2M \
	--enable WLAN_VENDOR_BROADCOM --module BRCMFMAC --enable BRCMFMAC_SDIO \
	--enable PWRSEQ_SIMPLE \
	--enable RD_GZIP
mk olddefconfig >/dev/null
for s in CHARGER_BQ25890 SND_SOC_ES9018K2M BRCMFMAC PWRSEQ_SIMPLE BLK_DEV_INITRD DEVTMPFS; do
	grep -q "^CONFIG_$s=[ym]" .config || { echo "config: $s didn't stick"; exit 1; }
done

mk Image modules $dtb
mkdir -p "$O"
cp arch/arm64/boot/Image "$O/"
[ -z "$dtb" ] || cp "arch/arm64/boot/dts/rockchip/$DTS.dtb" "$O/"
rm -rf "$HOME/mainline/modroot"
# Staged on ext4: the card-side drive ignores case, and xt_RATEEST.ko / xt_rateest.ko collide.
mk INSTALL_MOD_PATH="$HOME/mainline/modroot" INSTALL_MOD_STRIP=1 modules_install >/dev/null
tar -C "$HOME/mainline/modroot" -cf "$O/modules.tar" lib
# The probe's own module tree: brcmfmac and what it loads (brcmutil, the vendor parts it asks
# for by name), with a modules.dep so the kernel's request_module finds them.
KREL=$(make -s -C "$K" kernelrelease)
W=$HOME/mainline/wifimods
rm -rf "$W"
mkdir -p "$W/lib/modules/$KREL"
(cd "$HOME/mainline/modroot/lib/modules/$KREL" && find kernel -name 'brcm*.ko' | cpio -pdm --quiet "$W/lib/modules/$KREL")
cp "$HOME/mainline/modroot/lib/modules/$KREL/modules.builtin"* "$W/lib/modules/$KREL/"
depmod -b "$W" "$KREL"
tar -C "$W" -cf "$O/wifi-modules.tar" lib
rm -rf "$HOME/mainline/modroot" "$W"
# The probe's register reader (tools/mainline/regdump.c).
aarch64-linux-gnu-gcc -O2 -static -Wall -o "$O/regdump" "$R/tools/mainline/regdump.c"
echo "built $(make -s -C "$K" kernelrelease): $(du -h "$O/Image" | cut -f1) Image, $(du -h "$O/modules.tar" | cut -f1) modules"
