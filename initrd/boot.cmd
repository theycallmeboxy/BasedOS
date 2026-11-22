# BasedOS's boot script (initrd/boot.cmd; tools/mkboot.py script wraps it for U-Boot as boot.scr).
# BasedOS is installed next to stock on the eMMC (docs/plan.md, Architecture): this script takes the
# place of stock's boot.scr on stock's boot partition, and stock's own is kept beside it as
# boot.scr.stock (stock's file under another name: outside BasedOS's folder, so removing that
# folder never takes it). It boots stock's own kernel and device trees, from that same partition,
# with BasedOS's initrd, which mounts stock's SYSTEM read-only under BasedOS's own system layer.
#
#   Image, rk3576-gkd-atom*.dtb    stock's, as stock boots them
#   basedos/initrd.uimg            BasedOS's initrd: puts an installed update in place, checks the
#                                  system layer is made for this stock build, mounts stock's SYSTEM
#                                  at /stock
#
# If its files can't be loaded, stock's own boot script runs, so stock boots itself.
#
# (U-Boot's shell is old: one condition per if, and no ' outside comments: an apostrophe inside
# double quotes, in an echo, hung it on the logo when the fallback below ran (tested 2026-11-21:
# with one, stock's script never ran; without it, stock booted). tools/mkboot.py refuses them.)
setenv bdev "${devtype} ${devnum}:${distro_bootpart}"

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

setenv loaded 0
if load ${bdev} ${kernel_addr_r} Image; then
	if load ${bdev} ${fdt_addr_r} ${dtb}; then
		if load ${bdev} ${ramdisk_addr_r} basedos/initrd.uimg; then
			setenv loaded 1
		fi
	fi
fi
if test "${loaded}${panel}" = "11"; then
	# The panel at 60 Hz: its mode asks for 172.26 MHz, which the VOP can't make (it divides
	# GPLL's 1188 MHz by a whole number: 169.714 MHz, so stock runs it at 59.11 Hz). Asking for
	# 169.715 MHz with a shorter front porch gives 60.01 Hz (docs/power.md). If these don't
	# take, the panel just runs at stock's timing. Stock's DTB file itself is never changed.
	fdt addr ${fdt_addr_r}
	fdt resize
	fdt set /dsi@27d80000/panel@0/display-timings/timing0 clock-frequency <169715000>
	fdt set /dsi@27d80000/panel@0/display-timings/timing0 hfront-porch <124>
fi
if test "${loaded}" = "1"; then
	# loglevel=1: only emergencies on the console, BasedOS's boot screen shows the rest.
	# initcall_blacklist=raid6_select_algo: the stock kernel has btrfs built in, whose RAID6 init
	# benchmarks for about 0.3 s; nothing here uses RAID6.
	# rcupdate.rcu_expedited=1: closing an input device waits for an RCU grace period; expedited,
	# the frontend's input reopens don't stall.
	# basedos.disk: the initrd's disk (U-Boot's mmc N is the kernel's mmcblkN, by the DT aliases).
	# The initrd's own handovers to stock (stock once, uninstall, a refused system layer) run stock
	# on this same command line, the kernel being up already: quieter than stock's own (no
	# systemd.show_status, loglevel 1) and without RAID6, which stock doesn't use either; its SSH
	# is its own setting, not the kernel's "ssh". Only boot.scr.stock, below, boots stock with
	# stock's own.
	setenv bootargs "fbcon=rotate:${rotate} console=/dev/ttyFIQ0 quiet loglevel=1 consoleblank=0 vt.global_cursor_default=0 rdinit=/basedos/init initcall_blacklist=raid6_select_algo rcupdate.rcu_expedited=1 basedos.disk=mmcblk${devnum}"
	booti ${kernel_addr_r} ${ramdisk_addr_r} ${fdt_addr_r}
fi

echo "BasedOS: the stock kernel, its device tree or the BasedOS initrd did not load"
if load ${bdev} ${pxefile_addr_r} boot.scr.stock; then
	echo "BasedOS: booting stock"
	source ${pxefile_addr_r}
fi
