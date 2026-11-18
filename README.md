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
| Userland: glibc, Mali GPU (GLES, GBM, Vulkan), ALSA, Python, sshd, wpa_supplicant, Wi-Fi driver and firmware | copied from stock's rootfs: only what [manifest/harvest.list](manifest/harvest.list) names, plus the libraries those need |
| SDL2 and librga | built from source by [tools/sdl2/build.sh](tools/sdl2/build.sh): dArkMoss's rotating SDL2 (SDL 2.32.10, ArkOS's patches, the RGA turns the panel so apps see 1600x1440) and Rockchip's librga 1.10.5 |
| BusyBox (shell and core tools) | Alpine's static aarch64 build |
| Init, boot scripts, card mount, frontend start, power key | BasedOS's own ([initrd/](initrd/), [overlay/](overlay/)) |

On the eMMC (stock's partition layout; the bootloader area is never written):

| Partition | Holds |
|---|---|
| p1 vfat `BASEDOS` | `boot.scr`, kernel, DTBs (stock's, plus BasedOS's 60 Hz panel DTB in `basedos/`), `basedos-initrd.img`, and two read-only root images: slot A `rootfs.squashfs`, slot B `rootfs-b.squashfs` |
| p2 ext4 `BASEDOS-DATA` | `/data`: SSH keys, Wi-Fi config, logs, boot counter |

Boot: U-Boot runs `boot.scr` → kernel plus BasedOS's initrd → the initrd mounts the chosen slot
(falling back to the other after failed boots, then to stock) → BusyBox init → `rcS` (Wi-Fi,
`/data`, card, sshd) → `frontend-session` finds the frontend on the card (spruce's `runtime.sh`)
and starts it, again if it exits.

What it leaves out on purpose: systemd, udev, NetworkManager, Wayland/sway, a desktop. The
frontend draws straight to the display (KMS). Boot to SSH in about 2 s; 67 MB of RAM in use.

## What's here

| Path | What |
|---|---|
| [docs/user-guide.md](docs/user-guide.md) | **start here**: install, everyday use, safeguards, recovery |
| [docs/spruce-on-gkd.md](docs/spruce-on-gkd.md) | spruce support: the kit, status, what's left |
| [docs/plan.md](docs/plan.md) | design, conventions, status |
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
