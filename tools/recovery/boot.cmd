# BasedOS recovery card's boot script (basedos-setup, "Create a recovery SD"; tools/mkboot.py
# script wraps it as the card's boot.scr). U-Boot tries the SD card before the eMMC and runs this.
# It starts this device's own stock kernel, copied to the card when the card was made, with the
# recovery initrd (tools/recovery/init), which asks before it writes anything. If a file is
# missing, the script ends and U-Boot goes on to the eMMC.
#
#   recovery/Image            stock's kernel, from this device
#   recovery/*.dtb            stock's device trees, unchanged
#   recovery/initrd.uimg      the recovery initrd: BusyBox, zstd, the boot screen, the restore
setenv bdev "${devtype} ${devnum}:${distro_bootpart}"

# The output U-Boot's display menu chose (hdmi_detect), as BasedOS's own boot script does.
setenv rotate 0
if test "${hdmi_detect}" = "1"; then
	setenv dtb rk3576-gkd-atom-hdmi.dtb
elif test "${hdmi_detect}" = "2"; then
	setenv dtb rk3576-gkd-atom-usbdp.dtb
else
	setenv dtb rk3576-gkd-atom.dtb
	setenv rotate 3
fi
setenv bootargs "fbcon=rotate:${rotate} console=/dev/ttyFIQ0 quiet loglevel=1 consoleblank=0 vt.global_cursor_default=0 rdinit=/recovery/init"

# (U-Boot's shell is old: one condition per if.)
if load ${bdev} ${kernel_addr_r} recovery/Image; then
	if load ${bdev} ${fdt_addr_r} recovery/${dtb}; then
		if load ${bdev} ${ramdisk_addr_r} recovery/initrd.uimg; then
			booti ${kernel_addr_r} ${ramdisk_addr_r} ${fdt_addr_r}
		fi
	fi
fi
echo "BasedOS recovery card: its files are missing or damaged; starting from the eMMC"
