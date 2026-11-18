# Mainline experiment

Can BasedOS run on a mainline kernel instead of stock's Rockchip BSP 6.1? ROCKNIX's RK3576
kernel (Linux 7.2 plus ROCKNIX's patches) already runs the Anbernic RG Vita Pro, which shares the
RK3576, the RK806 PMIC, the RTC and the Type-C chip with the 350H Ultra. These tools build that
kernel with a 350H Ultra device tree and boot it from a test SD card, without writing to the eMMC.

| Step | Tool |
|---|---|
| Source: Linux + ROCKNIX's patches, panel driver and config, plus BasedOS's patches, in WSL `~/mainline` | `sh tools/mainline/fetch.sh` |
| Kernel, DTB, modules and the probe's register reader into `out/mainline/` | `sh tools/mainline/build.sh` |
| The Mali GPU driver (ROCKNIX's `mali_kbase`, r54p2) into `out/mainline/` | `sh tools/mainline/build-mali.sh` |
| Test card files into `out/mainline/card/` | `python3 tools/mainline/mkcard.py` |
| Over SSH: deploy a build to the card, switch kernels, pull logs | `sh tools/mainline/remote.sh` |

The device tree is `dts/rk3576-gkd-350h-ultra.dts`, translated from stock's
`rk3576-gkd-atom.dtb` with ROCKNIX's RG Vita Pro tree as the template.

## Working on mainline

Display (DSI panel at 60 Hz), every button and the stick, the RK806 and its regulators, RTC,
charger, Type-C, thermal, cpufreq up to 2208 MHz, eMMC and SD, USB device mode, audio, Wi-Fi
with SSH, and the GPU: BasedOS's own libmali (g24p0, as harvested) on ROCKNIX's `mali_kbase`
r54p2 (UK 11.46), which the probe loads from the card; SDL picks KMSDRM with the `opengles2`
renderer.

## BasedOS's kernel changes (`patches/`, applied by `fetch.sh`)

- `vop2-standby-bootloader.py`: the stock U-Boot leaves its splash screen running through the
  VOP's IOMMU, which then won't attach; the VOP is put in standby and reset first (with the
  `resets` the DT gives it).
- `dsi2-phyclk-overflow.py`: a 32-bit overflow in `dw-mipi-dsi2-rockchip.c` set the DC-PHY to
  57.7 MHz instead of 1131 MHz for this panel. A mainline bug, worth sending upstream.
- `es9018k2m-codec.py`: adds `drivers/es9018k2m.c`, BasedOS's driver for the ES9018K2M DAC
  (none in mainline): the stock driver's volume control name and range, speaker and headphone
  outputs on their GPIOs with headphone detection, and its registers restored after sleep.

## The test card

One FAT32 partition with the contents of `out/mainline/card/`, left in the 350H Ultra. The stock
U-Boot runs its `boot.scr` (as with the rescue card), which boots the mainline kernel with the
probe initrd (`probe-init`), or the eMMC's own `boot.scr` when `mainline/boot-emmc` exists or a
file is missing. The probe mounts the eMMC read-only (p2 with `noload`) and writes only to the
card and RAM:

- `mainline/logs/<n>/`: dmesg, state, regulators, clocks, GPIOs, pinmux, the display
  registers (`regs/`, for `regdump.py diff` against the stock kernel), 90 s of raw input events
  (`decode-events.py`), the kernel log every 5 s.
- Wi-Fi and SSH with BasedOS's own userspace: its rootfs and `/data` from the eMMC under RAM
  overlays, brcmfmac with the stock firmware. `ssh root@<address>` (empty password); the card
  is `/card` in that session.
- USB networking (NCM at `169.254.77.1`, a shell on port 2323) when the port is a gadget.

The second snapshot (after about 3.5 min) only runs when `mainline/later-snapshot` exists: every
run with it hung 10-15 s later, cause not found yet.

## Findings

- The Wi-Fi module is an AP6255 (BCM43455, SDIO `02d0:a9bf`), not the AP6256 the stock DT names.
  brcmfmac wants `brcm/brcmfmac43455-sdio.{bin,txt}` (stock's `fw_bcm43455c0_ag.bin` and
  `nvram_ap6255.txt`). With the firmware supplicant on, the firmware did the WPA handshake and
  wpa_supplicant tore the link down after ~10 s; `feature_disable=0x2000` turns it off.
- ROCKNIX's config has the firmware loader's user-helper fallback on: every missing optional file
  waits 60 s unless `/sys/class/firmware/timeout` is lowered. Its `PANIC_TIMEOUT=1` reboots one
  second after a panic; the card's bootargs say `panic=0`.

## Still to do

- Rotation: BasedOS's SDL turns each frame 270 degrees with the RGA through the BSP's driver
  (librga, `/dev/rga`). Mainline has no RK3576 RGA support (its RGA driver is V4L2 and doesn't
  list the RK3576), and its VOP2 planes on RK3576 only mirror, so SDL has to rotate on the GPU.
- Sleep, DVFS tables, the snapshot hang, and running the whole BasedOS rootfs on this kernel.
