# BasedOS's boot script (initrd/boot.cmd; tools/mkboot.py script wraps it for U-Boot as boot.scr).
# BasedOS's own, not derived from stock's: it boots only BasedOS's files, from the partition U-Boot
# found it on. U-Boot's distro boot tries the SD card (mmc 1) before the eMMC (mmc 0) and runs
# the first boot.scr it finds; ${devtype} ${devnum}:${distro_bootpart} is that partition. So the
# same script serves an eMMC install (beside stock's own files, which it leaves alone) and an SD
# card install.
#
#   basedos/boot.env               basedos_vendor=<id>: the base this install is built on
#                                  (docs/plan.md); basedos_card_stock=1 on an SD card that also
#                                  carries a copy of stock (basedos-setup's dual boot)
#   basedos/vendor-<id>/Image      the kernel, from that base's stock firmware
#   basedos/vendor-<id>/*.dtb      stock's device trees, unchanged
#   basedos/initrd.uimg            BasedOS's initrd: picks the A/B system slot, stacks it on the
#                                  vendor set's vendor.squashfs
#
# If BasedOS's files can't be loaded: stock's own boot script, where an eMMC install kept it, so
# stock boots itself; with none (an SD card), this script ends and U-Boot goes on to the next
# disk.
setenv bdev "${devtype} ${devnum}:${distro_bootpart}"
setenv basedos_vendor
setenv basedos_card_stock
# boot.env goes where the kernel will be loaded, not over this script (${scriptaddr}).
if load ${bdev} ${kernel_addr_r} basedos/boot.env; then
	env import -t ${kernel_addr_r} ${filesize}
fi
setenv vset basedos/vendor-${basedos_vendor}

# An SD card carrying a copy of stock (on its p1 and p2, laid out as on the eMMC): stock's init
# mounts mmcblk0p1 and p2 by name, so for stock to start from the card (stock once, or the
# initrd's fallback) the card has to be mmcblk0. The kernel numbers mmcblk disks by the DT's
# aliases, so they are swapped below (the card mmc0, the eMMC mmc1), as the old rescue card's
# DTBs had them (tools/rescue). Every other boot keeps stock's numbering.
setenv swap 0
if test "${devnum}" != "0"; then
	if test "${basedos_card_stock}" = "1"; then
		setenv swap 1
	fi
fi

# Which output U-Boot's display menu chose (GKD's board code sets hdmi_detect): the panel, HDMI
# or the USB-C port. The panel is portrait, hence its console rotation.
setenv rotate 0
setenv panel 0
if test "${hdmi_detect}" = "1"; then
	setenv dtb rk3576-gkd-atom-hdmi.dtb
elif test "${hdmi_detect}" = "2"; then
	setenv dtb rk3576-gkd-atom-usbdp.dtb
else
	setenv dtb rk3576-gkd-atom.dtb
	setenv rotate 3
	setenv panel 1
fi

# loglevel=1: only emergencies on the console, BasedOS's boot screen shows the rest.
# initcall_blacklist=raid6_select_algo: the stock kernel has btrfs built in, whose RAID6 init
# benchmarks for about 0.3 s; nothing here uses RAID6.
# rcupdate.rcu_expedited=1: closing an input device waits for an RCU grace period; expedited,
# the frontend's input reopens don't stall.
# basedos.disk, basedos.vendor: the initrd's disk (U-Boot's mmc N is the kernel's mmcblkN, by
# the DT aliases, unless they were swapped) and the vendor set this boot's kernel came from. Set
# just before booti, once the aliases are known.

# (U-Boot's shell is old: one condition per if.)
setenv loaded 0
if test -n "${basedos_vendor}"; then
	if load ${bdev} ${kernel_addr_r} ${vset}/Image; then
		if load ${bdev} ${fdt_addr_r} ${vset}/${dtb}; then
			if load ${bdev} ${ramdisk_addr_r} basedos/initrd.uimg; then
				setenv loaded 1
			fi
		fi
	fi
fi
if test "${loaded}" = "1"; then
	if test "${panel}" = "1"; then
		# The panel at 60 Hz: its mode asks for 172.26 MHz, which the VOP can't make (it divides
		# GPLL's 1188 MHz by a whole number: 169.714 MHz, so stock runs it at 59.11 Hz). Asking
		# for 169.715 MHz with a shorter front porch gives 60.01 Hz (docs/power.md). If these
		# don't take, the panel just runs at stock's timing.
		fdt addr ${fdt_addr_r}
		fdt resize
		fdt set /dsi@27d80000/panel@0/display-timings/timing0 clock-frequency <169715000>
		fdt set /dsi@27d80000/panel@0/display-timings/timing0 hfront-porch <124>
	fi
	setenv bdisk mmcblk${devnum}
	if test "${swap}" = "1"; then
		fdt addr ${fdt_addr_r}
		fdt resize
		fdt set /aliases mmc0 "/mmc@2a310000"
		fdt set /aliases mmc1 "/mmc@2a330000"
		# Only if it took: otherwise the card stays mmcblk1, and BasedOS still finds it.
		setenv a0
		fdt get value a0 /aliases mmc0
		if test "${a0}" = "/mmc@2a310000"; then
			setenv bdisk mmcblk0
		fi
	fi
	setenv bootargs "fbcon=rotate:${rotate} console=/dev/ttyFIQ0 quiet loglevel=1 consoleblank=0 vt.global_cursor_default=0 rdinit=/basedos/init initcall_blacklist=raid6_select_algo rcupdate.rcu_expedited=1 basedos.disk=${bdisk} basedos.vendor=${basedos_vendor}"
	booti ${kernel_addr_r} ${ramdisk_addr_r} ${fdt_addr_r}
fi

echo "BasedOS: vendor set '${basedos_vendor}' or its initrd missing or rejected"
if load ${bdev} ${pxefile_addr_r} basedos/boot.scr.stock; then
	echo "BasedOS: booting stock"
	source ${pxefile_addr_r}
fi
