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
GPU driver and Wi-Fi firmware are your own device's stock firmware's, used in
place: BasedOS is installed next to stock and links to them. See
[docs/plan.md](docs/plan.md).

Status: pre-releases, set up on the device itself (`basedos-setup`). Not ready for
general use.

## What it is

Not a fork of any distribution (dArkMoss, ROCKNIX or otherwise). It's three things put together:

| Part | Where it comes from |
|---|---|
| Bootloader | stock's (U-Boot), never written |
| Kernel, DTBs, the kernel's modules, Mali GPU drivers (GLES, GBM, Vulkan; 64- and 32-bit), Wi-Fi and Bluetooth firmware | stock ROCKNIX's own (build `c8ed06c`), the only ones that support this board, **used in place**: U-Boot loads stock's kernel and DTBs, and BasedOS mounts stock's SYSTEM read-only at `/stock` and links to what [manifest/harvest.list](manifest/harvest.list) names. Each BasedOS release is made for one stock build and checks it at every boot. Never copied, never published. The panel runs at 60 Hz instead of 59.11 Hz: the boot script sets it ([docs/power.md](docs/power.md)) |
| SDL2 and librga | built from source by [tools/sdl2/build.sh](tools/sdl2/build.sh): dArkMoss's rotating SDL2 (SDL 2.32.10, ArkOS's patches, the RGA turns the panel so apps see 1600x1440) and Rockchip's librga 1.10.5 |
| BusyBox (shell and core tools) | Alpine's static aarch64 build |
| Boot script, init, card mount, frontend start, updates, boot screen, key tools | BasedOS's own ([initrd/](initrd/), [overlay/](overlay/), [tools/boot-ui/](tools/boot-ui/)): with SDL2, librga, `wpa_cli` and BusyBox, the **system layer**, which `.bosupd` updates carry |

On the eMMC (stock's partition layout; the bootloader area is never written):

| Partition | Holds |
|---|---|
| p1 vfat (stock's) | stock's own files, untouched (BasedOS boots stock's kernel and DTBs and mounts its SYSTEM from here); BasedOS's boot files, `boot.scr` (stock's own kept beside it as `boot.scr.stock`, outside BasedOS's folder) and `basedos/initrd.uimg`, which setup installs and updates don't carry; `basedos/rootfs.squashfs`: the system layer (an installed update waits beside it as `rootfs.new` until the restart) |
| p2 ext4 (stock's) | stock's data; `basedos-data/`, BasedOS's `/data`: SSH keys, Wi-Fi config, logs, boot counter |

Boot: U-Boot runs BasedOS's `boot.scr` → stock's kernel and DTB, the panel at 60 Hz,
BasedOS's initrd → the initrd puts an installed update in place, mounts the system layer as the
root and stock's SYSTEM at its `/stock`, checks stock is the build the layer was made for (falling
back to stock if not, or after three failed boots) → BusyBox init → `rcS` (`/data`,
card, Wi-Fi driver) → `frontend-session` finds the frontend on the card (spruce's `runtime.sh`)
and starts it, again if it exits.

Updates: a `baseos-gkd350hultra-<version>.bosupd` at the card root is installed by
`basedos-update` only when asked for: by spruce's firmware updater (BasedOS's own copy fetches or
finds one, runs `basedos-update request` and reboots; installed at the next boot, once the card
is mounted and before the frontend starts) or from the maintenance menu ("Install update": any payload on the card, older ones too): the
system layer is written beside the running one as `rootfs.new`, verified, and put in place by
the initrd at the restart. One that doesn't start sends the device to stock, where setup's
Repair puts a release back. One it won't install is renamed on the card (`.skipped`, `.refused`,
`.failed`), so it isn't offered again. It carries nothing of stock's; each
release is made for one stock build, and one for another stock build is refused
([docs/plan.md](docs/plan.md), Architecture).

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
| [docs/vendor-minimal.md](docs/vendor-minimal.md) | what BasedOS takes from stock (the closed drivers, firmware and kernel modules, linked in place) and what it builds itself: inventory |
| [docs/lib32.md](docs/lib32.md) | the 32-bit libraries in `/usr/lib32`, for PortMaster's 32-bit ports |
| [docs/portmaster-libs.md](docs/portmaster-libs.md), [docs/portmaster-libscan.md](docs/portmaster-libscan.md) | what PortMaster's ports load from the system: a scan of the whole catalogue, and what BasedOS adds |
| [docs/boot-time.md](docs/boot-time.md), [docs/power.md](docs/power.md) | measurements |
| [docs/recovery.md](docs/recovery.md) | eMMC backup, rescue SD card, USB disk mode, maskrom, full restore (all tested) |
| [docs/recon.md](docs/recon.md) | hardware and stock-firmware notes |
| [docs/spruce-handoff.md](docs/spruce-handoff.md) | what spruce needs to run on BasedOS |
| `overlay/`, `initrd/` | BasedOS's own init, scripts and config |
| `buildroot/` | BasedOS's Buildroot tree: the 64-bit and 32-bit (armhf) configurations |
| `manifest/` | what each layer takes: `base.list` and `base32.list` from BasedOS's Buildroot roots, `harvest.list`, the stock files the system layer links to in `/stock`; known stock-build fingerprints |
| `tools/` | prepare-stock, harvest, rootfs and boot-file builders (`wsl/build.sh` runs them all), dev install, the 32-bit gap report (`lib32-gaps.py`) and the PortMaster library scan (`pm-libscan.py`) |
| `tools/dev/` | SSH helper, rootfs update, recon, power and screenshot probes, eMMC backup, `lib-closure.py` (what a frontend's libraries need from the base) |
| `tools/rescue/` | rescue SD card built on the device from its own files |
| `tools/maskrom/` | builds the RK3576 maskrom USB loader from Rockchip's `rkbin` |

## License

MIT for everything in this repository (see `LICENSE`). Credits, third-party parts and why
built images are never published: [NOTICE.md](NOTICE.md).
