# BasedOS's boot script (initrd/boot.cmd; tools/mkboot.py script wraps it for U-Boot as boot.scr).
# BasedOS's own, not derived from stock's: it boots only BasedOS's files, from the partition U-Boot
# found it on. U-Boot's distro boot tries the SD card (mmc 1) before the eMMC (mmc 0) and runs
# the first boot.scr it finds; ${devtype} ${devnum}:${distro_bootpart} is that partition. So the
# same script serves an eMMC install (beside stock's own files, which it leaves alone) and an SD
# card install.
#
#   basedos/boot.env               basedos_vendor=<id>: the base this install is built on
#                                  (docs/plan.md); basedos_card_stock=1 on an SD card that also
#                                  carries a copy of stock (card stock, on the card's p1 and p2)
#   basedos/vendor-<id>/Image      the kernel, from that base's stock firmware
#   basedos/vendor-<id>/*.dtb      stock's device trees, unchanged
#   basedos/initrd.uimg            BasedOS's initrd: picks the A/B system slot, stacks it on the
#                                  vendor set's vendor.squashfs
#   basedos/once.env               SD card only: basedos_once=card-stock starts card stock for one
#                                  boot (basedos-boot stock-once)
#
# From an SD card nothing on the eMMC is used or reachable: the eMMC's node in the device tree is
# disabled before the kernel starts, so Linux never sees it, whatever runs (BasedOS, its frontend,
# card stock), and the card becomes mmc0 (mmcblk0). If the card's files can't be loaded, the
# device powers off: take the card out to start the device's own system. From the eMMC, if
# BasedOS's files can't be loaded, stock's own boot script runs (kept at install).
#
# U-Boot's shell is old: one condition per if, and a value a test depends on is set by an earlier
# top-level line, never inside the same if.
setenv bdev "${devtype} ${devnum}:${distro_bootpart}"
setenv basedos_vendor
setenv basedos_card_stock
setenv basedos_once
# Small files go where the kernel will be loaded, not over this script (${scriptaddr}).
if load ${bdev} ${kernel_addr_r} basedos/boot.env; then
	env import -t ${kernel_addr_r} ${filesize}
fi
setenv vset basedos/vendor-${basedos_vendor}
setenv sd 0
if test "${devnum}" != "0"; then
	setenv sd 1
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

# Card stock, once (an SD card carrying it): the flag is cleared first, written and read back,
# and only then is card stock the target, so the next boot is BasedOS's whatever card stock does.
if test "${sd}${basedos_card_stock}" = "11"; then
	if load ${bdev} ${kernel_addr_r} basedos/once.env; then
		env import -t ${kernel_addr_r} ${filesize}
	fi
fi
setenv wrote 0
if test "${sd}${basedos_card_stock}${basedos_once}" = "11card-stock"; then
	setenv basedos_once done
	env export -t ${kernel_addr_r} basedos_once
	if fatwrite ${devtype} ${devnum}:${distro_bootpart} ${kernel_addr_r} basedos/once.env ${filesize}; then
		setenv wrote 1
	fi
fi
setenv basedos_once
if test "${wrote}" = "1"; then
	if load ${bdev} ${kernel_addr_r} basedos/once.env; then
		env import -t ${kernel_addr_r} ${filesize}
	fi
fi
setenv target basedos
if test "${wrote}${basedos_once}" = "1done"; then
	setenv target cardstock
fi

# Card stock: its own kernel and device tree, from the card's p1 (its own files; its updates
# change them together).
setenv loaded 0
if test "${target}" = "cardstock"; then
	if load ${devtype} ${devnum}:1 ${kernel_addr_r} Image; then
		if load ${devtype} ${devnum}:1 ${fdt_addr_r} ${dtb}; then
			setenv loaded 1
		fi
	fi
fi
if test "${target}${loaded}" = "cardstock0"; then
	echo "BasedOS: card stock's files can't be loaded; starting BasedOS"
	setenv target basedos
fi

# BasedOS: the vendor set's kernel and device tree, and BasedOS's initrd.
if test "${target}" = "basedos"; then
	if test -n "${basedos_vendor}"; then
		if load ${bdev} ${kernel_addr_r} ${vset}/Image; then
			if load ${bdev} ${fdt_addr_r} ${vset}/${dtb}; then
				if load ${bdev} ${ramdisk_addr_r} basedos/initrd.uimg; then
					setenv loaded 1
				fi
			fi
		fi
	fi
fi
if test "${target}${loaded}${panel}" = "basedos11"; then
	# The panel at 60 Hz: its mode asks for 172.26 MHz, which the VOP can't make (it divides
	# GPLL's 1188 MHz by a whole number: 169.714 MHz, so stock runs it at 59.11 Hz). Asking for
	# 169.715 MHz with a shorter front porch gives 60.01 Hz (docs/power.md). If these don't
	# take, the panel just runs at stock's timing.
	fdt addr ${fdt_addr_r}
	fdt resize
	fdt set /dsi@27d80000/panel@0/display-timings/timing0 clock-frequency <169715000>
	fdt set /dsi@27d80000/panel@0/display-timings/timing0 hfront-porch <124>
fi

# From an SD card: the eMMC disabled and the card made mmc0, read back (hidden=1 only if both
# took).
setenv st
setenv a0
if test "${sd}${loaded}" = "11"; then
	fdt addr ${fdt_addr_r}
	fdt resize
	fdt set /mmc@2a330000 status disabled
	fdt set /aliases mmc0 /mmc@2a310000
	fdt set /aliases mmc1 /mmc@2a330000
	fdt get value st /mmc@2a330000 status
	fdt get value a0 /aliases mmc0
fi
setenv hidden 0
if test "${st}" = "disabled"; then
	if test "${a0}" = "/mmc@2a310000"; then
		setenv hidden 1
	fi
fi
setenv bdisk mmcblk${devnum}
if test "${hidden}" = "1"; then
	setenv bdisk mmcblk0
fi

# Card stock with stock's own kernel arguments (its boot script's); only with the eMMC hidden,
# since stock's init mounts mmcblk0p1 and p2 by name. Not hidden: power off (the flag is gone,
# so the next boot is BasedOS's).
if test "${target}${hidden}" = "cardstock1"; then
	setenv bootargs "fbcon=rotate:${rotate} console=/dev/ttyFIQ0 quiet ssh consoleblank=0 systemd.show_status=1 loglevel=7 net.iframes=0"
	echo "BasedOS: starting card stock once"
	booti ${kernel_addr_r} - ${fdt_addr_r}
fi
if test "${target}" = "cardstock"; then
	echo "BasedOS: the eMMC couldn't be hidden, so card stock isn't started; powering off"
	sleep 10
	poweroff
fi

# loglevel=1: only emergencies on the console, BasedOS's boot screen shows the rest.
# initcall_blacklist=raid6_select_algo: the stock kernel has btrfs built in, whose RAID6 init
# benchmarks for about 0.3 s; nothing here uses RAID6.
# rcupdate.rcu_expedited=1: closing an input device waits for an RCU grace period; expedited,
# the frontend's input reopens don't stall.
# basedos.disk, basedos.part, basedos.vendor: the initrd's disk and BasedOS's boot partition on
# it (its data partition is the next one), and the vendor set this boot's kernel came from. If
# the eMMC couldn't be hidden from an SD card, the initrd still finds the card (basedos.disk is
# then mmcblk1) and makes the eMMC read-only.
if test "${loaded}" = "1"; then
	setenv bootargs "fbcon=rotate:${rotate} console=/dev/ttyFIQ0 quiet loglevel=1 consoleblank=0 vt.global_cursor_default=0 rdinit=/basedos/init initcall_blacklist=raid6_select_algo rcupdate.rcu_expedited=1 basedos.disk=${bdisk} basedos.part=${distro_bootpart} basedos.vendor=${basedos_vendor}"
	booti ${kernel_addr_r} ${ramdisk_addr_r} ${fdt_addr_r}
fi

echo "BasedOS: vendor set '${basedos_vendor}' or its initrd missing or rejected"
if test "${sd}" = "1"; then
	# Never on to the eMMC from a BasedOS card: without the card, the device starts its own system.
	echo "BasedOS: this card can't start; powering off. Take the card out to start the device's own system."
	sleep 10
	poweroff
fi
if load ${bdev} ${pxefile_addr_r} basedos/boot.scr.stock; then
	echo "BasedOS: booting stock"
	source ${pxefile_addr_r}
fi
