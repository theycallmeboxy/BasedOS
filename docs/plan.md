# BasedOS plan

## Status

**v0 boots on the device (2026-11-16, build `61371a3`), installed next to stock** with
`tools/install-dev.sh`. Verified:
- `rcS` starts at 1.58 s after the kernel, `sshd` at 1.79 s, `wlan0` at 2.17 s, and
  the DHCP lease arrives at 10.1 s (Wi-Fi association dominates). RAM in use: 67 MB.
- Root is the read-only squashfs on p1. `/data` is `basedos-data/` on p2, and
  stock's `/storage` is untouched. `/mnt/SDCARD` exists, with `/mnt/sdcard`
  pointing to it.
- Wi-Fi uses the network copied from stock's connman. SSH uses stock's host
  keys, so the fingerprints are the same.
- `frontend-session` waits for a card quietly and prints one on-screen notice.

Not yet tried: the frontend handoff with a real card, RTC time (`hwclock`),
sleep and power key, audio, and the display from a frontend.

Fixed during bring-up: OpenSSH 9.8 needs `/usr/lib/openssh/sshd-session`
(added to the harvest list), and stock's sshd has no PAM (`UsePAM` removed).

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
- **Recovery is proven on this unit** (see the spruce repo's
  `docs/gkd350h-ultra/backup-restore.md`): a rescue SD card, U-Boot USB disk mode
  (Menu+Home), and maskrom (Volume Down) with a full 15.6 GB restore.

## Conventions

| Topic | BasedOS | Following |
|---|---|---|
| Card mount | `/mnt/SDCARD` is the real mount. `/mnt/sdcard` is a symlink to it. | my355; spruce's own path |
| Card choice | The SD slot (`mmcblk1p1`). vfat, then exFAT. Run `fsck.fat -a` on failure. | h700 |
| Entry points, first match wins | `System/frontend`, `System/launch_frontend.sh`, `.tmp_update/updater`, `spruce/scripts/runtime.sh` | h700 (spruce path), my355 (updater) |
| Environment | Every key in `/etc/baseos-release` is exported to the frontend. | h700 |
| `/etc/baseos-release` | `BASEOS=1`, `BASEOS_NAME=BasedOS`, `BASEOS_PLATFORM=rk3576`, `BASEOS_TARGET=gkd350hultra`, `BASEOS_DEVICE=gkd350hultra`, `BASEOS_MODEL="GKD 350H Ultra"`, `BASEOS_MODEL_STRING=GKD350HUltra`, `BASEOS_PANEL_ROTATION_CCW=270` (to verify), `BASEOS_WIFI=true`, `BASEOS_BLUETOOTH=false`, `BASEOS_VERSION`, `BASEOS_BUILD` | union of both |
| `/etc/os-release` | `ID=basedos`, `NAME="BasedOS"` | both |
| Init | BusyBox init: `rcS` sysinit, `frontend-session` respawn, `rcK` shutdown. No udev; devtmpfs only. | both |
| Writable state | `/data` on p2 (ext4): keys, logs, machine-id, update state. tmpfs `/run`, `/tmp`, `/var`. Root is read-only. | my355 |
| Updates | `baseos-gkd350hultra-<ver>.bosupd` at the card root, `format=baseos-update/2` (tar plus manifest) | my355 (spruce looks for `baseos-<target>-*.bosupd`) |
| Logs | `/data/basedos.log`, mirrored to the card | both |

## eMMC layout

v0 keeps stock's MBR layout, so installing doesn't touch the loader:

| Region | Contents |
|---|---|
| sectors 0 to 32767 | stock MBR, idbloader, U-Boot FIT. Never written. |
| p1 vfat `BASEDOS`, 3 GB at 16 MiB | `boot.scr`, `Image` and DTBs (harvested), `basedos-initrd.img`, `rootfs.squashfs` |
| p2 ext4 `BASEDOS-DATA`, the rest | `/data` |

A/B for updates comes later: two rootfs files on p1 (`rootfs-a`, `rootfs-b`), and `boot.scr` picks one from a slot file. That's simpler than my355's GPT flip, and a vfat p1 allows it.

## Boot flow

1. U-Boot runs BasedOS's `boot.scr`, which loads `Image`, the DTB and `basedos-initrd.img`, then `booti` with the initrd.
2. The kernel unpacks its built-in initramfs and then ours over it, so our `/init` replaces stock's. Our `/init` mounts p1 read-only, loop-mounts `rootfs.squashfs`, mounts p2 on `/data`, mounts tmpfs dirs, then `switch_root`s and execs `/sbin/init`.
3. BusyBox init runs `rcS`: proc/sys/devpts, splash, the Wi-Fi module and firmware, dbus if needed, `/data` setup, the card mount, a pending update, then sshd in the background.
4. `frontend-session` (respawned) runs the frontend probe. With no card or frontend, it shows a splash and retries.

## Rootfs

The rootfs is a squashfs built on the PC (WSL has `mksquashfs`) from:

1. **A skeleton and BusyBox:** Alpine's `busybox-static` (aarch64), the same as my355. It needs no compiler.
2. **The stock harvest:** a closed set listed in `manifest/harvest.list`, taken from your own stock image. It includes glibc 2.40, libmali (with its EGL, GLES and GBM links), libdrm, SDL2, ALSA, the `bcmdhd` module, Wi-Fi/BT firmware, wpa_supplicant, openssh `sshd`, and Python 3 (spruce's PyUI). A Python closure check (ELF `DT_NEEDED` against `SONAME`s, as my355 does) fails the build if any library is missing.
3. **The BasedOS overlay:** `/init`, inittab, `rcS`, `rcK`, `frontend-session`, `mount-frontend`, `baseos-release`, profile, fstab.

The harvest source is either the backup image (`mmcblk0.img`: FAT p1, then its `SYSTEM` squashfs) or a live stock device. `prepare-stock` checks the stock build against known fingerprints (`c8ed06c` for now) and refuses anything unknown.

## Install paths

- **Developer:** build on the PC, copy the files onto p1 and p2 from the rescue card (it boots stock from SD with the eMMC unmounted), then reboot.
- **Users, later:** an installer SD card built on the device from its own files (the rescue card mechanism): back up, harvest, install. Nothing vendor-made is published.

## Versions

- **v0:** boots to BusyBox init. SSH over Wi-Fi, the card mounted at `/mnt/SDCARD`, frontend probe, splash. No updates, no A/B. Success means BasedOS hands off to a test frontend, then to spruce, whatever spruce does after that.
- **v1:** power key handling, battery and charging, sleep, audio routing, a USB gadget (adb or storage), `.bosupd` with A/B and trial boots, boot log on the card.
- **v2:** the installer card for users, boot time work, NextUI.
- **spruce side** (in the spruce repo, in parallel): a `BASEOS_TARGET=gkd350hultra` platform checked before the CPU-ID case (the GKD's `0xd03` cores would otherwise match H700), a PyUI rotation like the RG28XX, and RetroArch on KMS/GBM.

## Open questions

- Is `BASEOS_PANEL_ROTATION_CCW` 90 or 270? Stock sway uses `transform 270` on DSI-1. To be checked on the device.
- Can the display be driven without sway? spruce's RetroArch has no Wayland or KMS backend. We need to check that SDL2 KMSDRM on libmali's GBM can drive the panel.
- How long does `bcmdhd` take to load and associate without connman (wpa_supplicant plus udhcpc)?
- Where does `BASEOS_TARGET` resolve in spruce's `baseos_repo()` (which repo releases BasedOS)?
