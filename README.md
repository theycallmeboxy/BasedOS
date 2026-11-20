# BasedOS for the GKD 350H Ultra

A small base OS for the eMMC of the GKD 350H Ultra (RK3576). Its only job
is to boot fast and hand the device to a frontend on a portable SD card, such
as spruceOS (NextUI later). That card stays an ordinary spruce card, so it
keeps working in your other spruce devices.

BasedOS follows the conventions of the two BaseOS projects it borrows from:
[apommel/baseos-my355](https://github.com/apommel/baseos-my355) (Miyoo Flip)
and [pvaibhav/BaseOS](https://github.com/pvaibhav/BaseOS) (Anbernic H700).
Frontends detect it the same way they detect BaseOS: `/etc/baseos-release`,
`BASEOS_TARGET=gkd350hultra`.

**Nothing vendor-made is in this repository or its releases.** The kernel,
GPU driver, Wi-Fi firmware and C library come from your own device's stock
firmware, harvested during installation. See [docs/plan.md](docs/plan.md).

Status: runs spruce on the device (installed next to stock, for developers).
Not ready for general use.

## What it is

Not a fork of any distribution (dArkMoss, ROCKNIX or otherwise). It's three things put together:

| Part | Where it comes from |
|---|---|
| Bootloader, kernel, DTBs | stock ROCKNIX (build `c8ed06c`), the only ones that support this board. Unchanged, except a copy of the panel DTB with the panel at 60 Hz instead of 59.11 Hz (`tools/mkboot.py dtb`, [docs/power.md](docs/power.md)) |
| Userland: glibc, Mali GPU (GLES, GBM, Vulkan), ALSA, sshd, wpa_supplicant, Wi-Fi driver and firmware | copied from stock's rootfs into the **vendor layer**: only what [manifest/harvest.list](manifest/harvest.list) names, plus the libraries those need. Built on your own firmware, never published |
| SDL2 and librga | built from source by [tools/sdl2/build.sh](tools/sdl2/build.sh): dArkMoss's rotating SDL2 (SDL 2.32.10, ArkOS's patches, the RGA turns the panel so apps see 1600x1440) and Rockchip's librga 1.10.5 |
| BusyBox (shell and core tools) | Alpine's static aarch64 build |
| Init, boot scripts, card mount, frontend start, updates, boot screen, key tools | BasedOS's own ([initrd/](initrd/), [overlay/](overlay/), [tools/boot-ui/](tools/boot-ui/)): with SDL2, librga, `wpa_cli` and BusyBox, the **system layer**, which `.bosupd` updates carry |

On the eMMC (stock's partition layout; the bootloader area is never written):

| Partition | Holds |
|---|---|
| p1 vfat `BASEDOS` | `boot.scr`, kernel, DTBs (stock's, plus BasedOS's 60 Hz panel DTB in `basedos/`), `basedos/initrd.uimg`, the vendor layer `basedos/vendor-<id>.squashfs`, and two system layers: slot A `rootfs.squashfs`, slot B `rootfs-b.squashfs` |
| p2 ext4 `BASEDOS-DATA` | `/data`: SSH keys, Wi-Fi config, logs, boot counter |

Boot: U-Boot runs `boot.scr` → kernel plus BasedOS's initrd → the initrd stacks the chosen slot's
system layer on the vendor layer it names, with overlayfs (falling back to the other slot after
failed boots, then to stock) → BusyBox init → `rcS` (`/data`,
card, Wi-Fi driver) → `frontend-session` finds the frontend on the card (spruce's `runtime.sh`)
and starts it, again if it exits.

Updates: a `baseos-gkd350hultra-<version>.bosupd` at the card root (spruce's firmware updater
fetches or finds one and reboots) is installed at the next boot by `basedos-update`: the system
layer to the spare slot, verified, then the slot flips. It carries nothing of stock's; it names the
vendor layer it needs and is refused without it.

Sleep: frontends call `basedos-suspend`, which suspends and then runs BasedOS's wake fixes (what a
systemd base's system-sleep hooks do): today, putting the DAC's volume back, which the stock kernel loses.

What it leaves out on purpose: systemd, udev (udevd runs only for the length of a PortMaster Weston
port, `basedos-udev`), NetworkManager, Wayland/sway, a desktop. The frontend draws straight to the
display (KMS). Boot to SSH in about 2 s; 67 MB of RAM in use.

32-bit programs: a 32-bit (armhf) set of libraries in `/usr/lib32`, as stock lays it out, for
PortMaster's 32-bit ports (docs/lib32.md); BasedOS's own programs are all 64-bit.

## What's here

| Path | What |
|---|---|
| [docs/user-guide.md](docs/user-guide.md) | **start here**: install, everyday use, safeguards, recovery |
| [docs/spruce-on-gkd.md](docs/spruce-on-gkd.md) | spruce support: the kit, status, what's left |
| [docs/plan.md](docs/plan.md) | design, conventions, status |
| [docs/vendor-minimal.md](docs/vendor-minimal.md) | shrinking the vendor layer to the closed drivers, firmware and kernel modules: inventory and plan |
| [docs/boot-time.md](docs/boot-time.md), [docs/power.md](docs/power.md) | measurements |
| [docs/recovery.md](docs/recovery.md) | eMMC backup, rescue SD card, USB disk mode, maskrom, full restore (all tested) |
| [docs/recon.md](docs/recon.md) | hardware and stock-firmware notes |
| [docs/spruce-handoff.md](docs/spruce-handoff.md) | what spruce needs to run on BasedOS |
| `overlay/`, `initrd/` | BasedOS's own init, scripts and config |
| `manifest/` | the stock harvest list and known stock-build fingerprints |
| `tools/` | prepare-stock, harvest, rootfs and boot-file builders, dev install |
| `tools/dev/` | SSH helper, rootfs slot update, recon, power and screenshot probes, eMMC backup |
| `tools/rescue/` | rescue SD card built on the device from its own files |
| `tools/maskrom/` | builds the RK3576 maskrom USB loader from Rockchip's `rkbin` |

## License

MIT for everything in this repository (see `LICENSE`). Credits, third-party parts and why
built images are never published: [NOTICE.md](NOTICE.md).
