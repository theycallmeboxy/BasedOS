# BasedOS plan

## Status

**Runs spruce on the device (2026-11-19, build `39ab987`), installed next to stock** with
`tools/install-dev.sh`. Power to spruce's menu takes about 4 s (boot-time.md); spruce starts at
about 1.3 s of the kernel's uptime. Working and checked on the unit:

- The layered root: the vendor layer (stock's files, built on the device's own stock, never
  published) and the system layer (BasedOS's, about 2.4 MB), stacked by the initrd; A/B slots with
  a boot counter that falls back to the other slot, then to stock.
- Updates: a `.bosupd` at the card root, from spruce's BaseOS updater or by hand, installed at the
  next boot into the spare slot and confirmed once it boots (`basedos-update`). The boot script is
  not in a payload (see below).
- spruce: menu, emulators (RetroArch, DSperate, DraStic, PPSSPP, Mupen64Plus, Flycast,
  YabaSanshiro), E-Reader, Gallery, sleep and wake, clean shutdown, Wi-Fi and SSH (spruce's own,
  as on its other devices), screenshots. Details in spruce-on-gkd.md.
- Maintenance mode (Select held at power-on): BasedOS's own Wi-Fi and root SSH, no frontend.
- The boot screen, quiet boot, boot keys, and the Volume Up + Volume Down shutdown watcher.

Not done yet: an installer card for users (the vendor layer is built on a PC from a backup today),
a way for an update to change the boot script and its kernel options, Bluetooth, USB storage mode,
PortMaster and ScummVM on spruce, and a clean-install test of `install-dev.sh` since the layer split.

## Starting point (verified on the device, 2026-11-16)

- **Device:** RK3576S, 2 GB RAM, 16 GB eMMC (`mmcblk0`), one SD slot (`mmcblk1`),
  a 1440×1600 portrait DSI panel shown landscape. The device tree model is
  "GameKiddy GKD ATOM".
- **Stock:** ROCKNIX 20260613 build `c8ed06c`. Its kernel is a Rockchip BSP
  6.1.118 with almost every driver built in (only `bcmdhd` Wi-Fi is a module).
  It has a built-in initramfs (EmuELEC's, 32-bit) and accepts an external
  initrd. overlayfs, squashfs (zstd/lz4/xz), ext4, vfat, exFAT and USB
  configfs gadgets are all built in.
- **Boot chain:** the boot ROM loads the idbloader at sector 64, then the U-Boot
  FIT at 8 MiB. U-Boot runs `boot.scr` from p1 (vfat). The SPL and U-Boot both
  try the SD card first. BasedOS never touches sectors 0 to 32767 except the
  MBR partition table.
- **Recovery is proven on this unit** (see [recovery.md](recovery.md)): a rescue SD card, U-Boot USB disk mode
  (Menu+Home), and maskrom (Volume Down) with a full 15.6 GB restore.

## Conventions

| Topic | BasedOS | Following |
|---|---|---|
| Card mount | `/mnt/SDCARD` is the real mount. `/mnt/sdcard` is a symlink to it. | my355; spruce's own path |
| Card choice | The SD slot (`mmcblk1p1`). vfat, then exFAT. Run `fsck.fat -a` on failure. | h700 |
| Entry points, first match wins | `System/frontend`, `System/launch_frontend.sh`, `spruce/scripts/runtime.sh`, `.tmp_update/updater` (spruce cards carry a Miyoo `.tmp_update` too, so spruce comes first) | h700 (spruce path), my355 (updater) |
| Environment | Every key in `/etc/baseos-release` is exported to the frontend. | h700 |
| `/etc/baseos-release` | `BASEOS=1`, `BASEOS_NAME=BasedOS`, `BASEOS_PLATFORM=rk3576`, `BASEOS_TARGET=gkd350hultra`, `BASEOS_DEVICE=gkd350hultra`, `BASEOS_MODEL="GKD 350H Ultra"`, `BASEOS_MODEL_STRING=GKD350HUltra`, `BASEOS_PANEL_ROTATION_CCW=270` (to verify), `BASEOS_WIFI=true`, `BASEOS_BLUETOOTH=false`, `BASEOS_VERSION`, `BASEOS_BUILD` | union of both |
| `/etc/os-release` | `ID=basedos`, `NAME="BasedOS"` | both |
| Init | BusyBox init: `rcS` sysinit, `frontend-session` respawn, `rcK` shutdown. No udev; devtmpfs only. | both |
| Writable state | `/data` on p2 (ext4): keys, logs, machine-id, update state. tmpfs `/run`, `/tmp`, `/var`. Root is read-only. | my355 |
| Updates | `baseos-gkd350hultra-<ver>.bosupd` at the card root, `format=basedos-update/1`: a tar of `manifest`, the system layer and the initrd (`tools/mkupdate.py`; `basedos-update` installs it at boot into the spare slot) | my355's name and manifest style (spruce looks for `baseos-<target>-*.bosupd`); the format is BasedOS's own, as its slots are files |
| Logs | `/data/basedos.log` (mirroring to the card is not done yet) | both |

## eMMC layout

v0 keeps stock's MBR layout, so installing doesn't touch the loader:

| Region | Contents |
|---|---|
| sectors 0 to 32767 | stock MBR, idbloader, U-Boot FIT. Never written. |
| p1 vfat `BASEDOS`, 3 GB at 16 MiB | `boot.scr`, `Image` and DTBs (harvested), `basedos-initrd.img`, `rootfs.squashfs` |
| p2 ext4 `BASEDOS-DATA`, the rest | `/data` |

A/B is two system-layer files on p1 (`rootfs.squashfs`, `rootfs-b.squashfs`) and a slot file the initrd reads, beside the vendor layer (`vendor-<id>.squashfs`, several may sit side by side). That's simpler than my355's GPT flip, and a vfat p1 allows it.

## Boot flow

1. U-Boot runs BasedOS's `boot.scr` (stock's, rewritten by `mkboot.py bootscr`), which loads `Image`, the panel DTB (BasedOS's 60 Hz one when present) and `basedos/initrd.uimg`, adds BasedOS's kernel options (`rdinit=/basedos/init`, `initcall_blacklist=raid6_select_algo`, `rcupdate.rcu_expedited=1`), then `booti` with the initrd. A missing or rejected initrd boots stock with stock's options.
2. The kernel unpacks its built-in initramfs and then ours over it, so our `/init` replaces stock's. Our `/basedos/init` counts the boot on p2, mounts p1 read-only, loop-mounts the chosen slot's system layer and the vendor layer it names, stacks them with overlayfs (falling back to the other slot, then to stock), then `switch_root`s and execs `/sbin/init`. `rcS` mounts p2 on `/data` and the tmpfs dirs.
3. BusyBox init runs `rcS`: proc/sys/devpts and the `/dev` links, the boot screen, the clock, `/data` (checked, then mounted), the card mount, a pending update (installed, then straight to a reboot), then the Wi-Fi driver and the shutdown-key watcher in the background. Joining Wi-Fi and SSH are the frontend's; BasedOS's own start only in maintenance mode or after a failing frontend.
4. `frontend-session` (respawned) runs the frontend probe. With no card or frontend, it shows a splash and retries.

## Rootfs

The root is two squashfs layers built on the PC (WSL has `mksquashfs`), stacked by the initrd with
overlayfs, the system layer on top:

- **vendor** (`vendor-<id>.squashfs`): the stock harvest (2 below), named by a hash of its
  contents. Built from the device's own firmware, never published.
- **system** (the slot files): everything else (1 and 3, SDL2, librga, `wpa_cli`, BasedOS's
  tools), plus the id of the vendor layer it was built against (`usr/share/basedos/needs-vendor`).
  The build fails if a stock file is in it. This is what a `.bosupd` carries.

The layers come from:

1. **A skeleton and BusyBox:** Alpine's `busybox-static` (aarch64), the same as my355. It needs no compiler.
2. **The stock harvest:** a closed set listed in `manifest/harvest.list`, taken from your own stock image. It includes glibc 2.40, libmali (with its EGL, GLES and GBM links), libdrm, SDL2, ALSA, the `bcmdhd` module, Wi-Fi/BT firmware, wpa_supplicant, openssh `sshd` (no Python: spruce brings its own). A Python closure check (ELF `DT_NEEDED` against `SONAME`s, as my355 does) fails the build if any library is missing.
3. **The BasedOS overlay:** `/init`, inittab, `rcS`, `rcK`, `frontend-session`, `mount-frontend`, `baseos-release`, profile, fstab.

The harvest source is either the backup image (`mmcblk0.img`: FAT p1, then its `SYSTEM` squashfs) or a live stock device. `prepare-stock` checks the stock build against known fingerprints (`c8ed06c` for now) and refuses anything unknown.

## Install paths

- **Developer:** build on the PC (`tools/wsl/build.sh`), then run `tools/install-dev.sh` on the device under stock, over SSH (user-guide.md). Later builds go in with `tools/dev/update-basedos.sh` from BasedOS, or as a `.bosupd`.
- **Users, later:** an installer SD card built on the device from its own files (the rescue card mechanism): back up, harvest, install. Nothing vendor-made is published.

## Versions

- **v0 (done 2026-11-16):** boots to BusyBox init. SSH over Wi-Fi, the card mounted at `/mnt/SDCARD`, frontend probe, splash. No updates, no A/B. Success means BasedOS hands off to a test frontend, then to spruce, whatever spruce does after that.
- **v1 (mostly done):** power key handling, battery and charging, sleep and audio (spruce's, on BasedOS), `.bosupd` with A/B and trial boots. Left: a USB gadget (adb or storage), the boot log on the card.
- **v2:** the installer card for users, boot time work (begun: boot-time.md), NextUI.
- **spruce side (done; spruce-on-gkd.md)** (in the spruce repo, in parallel): a `BASEOS_TARGET=gkd350hultra` platform checked before the CPU-ID case (the 350H Ultra's `0xd03` cores would otherwise match H700), a PyUI rotation like the RG28XX, and RetroArch on KMS/GBM.

## Open questions

Answered on the unit: the panel turns 270 (SDL's RGA path, `SCREEN_ROTATION=270` for PyUI); SDL2
KMSDRM on libmali's GBM drives the panel without sway; `bcmdhd` loads in about 0.5 s and joins in
5 to 9 s with wpa_supplicant and udhcpc; spruce's `baseos_repo` maps `gkd350hultra` to
`theycallmeboxy/BasedOS`.

Still open:

- How an update changes the boot script or its kernel options (a small options file on p1 that
  `boot.scr` reads, or a payload member). Today `tools/dev/update-basedos.sh` and `install-dev.sh`
  write it.
- The installer card for users: building the vendor layer on the device from its own stock.
- A minimal vendor layer (decided 2026-11-19): only the closed GPU drivers, firmware and kernel
  modules from stock, the rest built by BasedOS (Buildroot). Inventory and plan: vendor-minimal.md.
