# BasedOS plan

## Status

**Runs spruce on the device (2026-11-20, build `c9ee8f9`), installed next to stock** with
`tools/install-dev.sh` (clean install from stock, uninstall and reinstall tested twice,
2026-11-20). Power to spruce's menu takes about 4 s (boot-time.md); spruce starts at about 1.3 s of
the kernel's uptime. Working and checked on the unit:

- The layered root: the vendor layer (stock's files, cut from the device's own stock image, never
  published) and the system layer (BasedOS's, about 33 MB with the 32-bit libraries), stacked by
  the initrd; A/B slots with a boot counter that falls back to the other slot, then to stock.
- The vendor layer built on the device (`basedos-vendor`, about 30 s) from stock's `SYSTEM` on p1,
  by the recipe every system layer carries; same files as the PC build's.
- Updates: a `.bosupd` at the card root, from spruce's BaseOS updater or by hand, installed at the
  next boot into the spare slot and confirmed once it boots (`basedos-update`); one that needs a
  vendor layer the device lacks builds it first, before either slot is written. The boot script
  is not in a payload (see below).
- Leaving BasedOS (`basedos-boot`, the maintenance menu, Start held at power-on): stock once,
  switch to stock with "Return to BasedOS" in stock's Ports, uninstall (done by the initrd at the
  restart). Each boot script written is checked and read back.
- spruce: menu, emulators (RetroArch, DSperate, DraStic, PPSSPP, Mupen64Plus, Flycast,
  YabaSanshiro), E-Reader, Gallery, sleep and wake, clean shutdown, Wi-Fi and SSH (spruce's own,
  as on its other devices), screenshots, PortMaster with Weston and 32-bit ports (lib32.md,
  portmaster-libs.md). Details in spruce-on-gkd.md.
- Maintenance mode (Select held at power-on): BasedOS's own Wi-Fi and root SSH, no frontend, and
  the menu above.
- The boot screen, quiet boot, boot keys, and the Volume Up + Volume Down shutdown watcher.

Not done yet: an installer card for users (the pieces are here: a published system layer and the
on-device vendor build), BasedOS on the SD card alone with the eMMC never written, a way for an
update to change the boot script and its kernel options, Bluetooth, USB storage mode, ScummVM on
spruce, and the old-library compat set some ports want (portmaster-libs.md).

## Architecture (decided 2026-11-20; being built, see "Today" below)

Three pieces, the same whether BasedOS runs from the eMMC or from an SD card:

1. **Stock source**: stock's own files, verbatim (`SYSTEM`, `Image`, DTBs, its boot script),
   checked against the known stock builds (`manifest/stock-builds.txt`). Read **only at setup**,
   to harvest the vendor set; BasedOS never boots from it. On the eMMC it's stock's p1, left as
   it is (stock stays bootable). An SD card doesn't need it; it can carry a copy as an option
   (for booting stock from the card later).
2. **Vendor set** (`basedos/vendor-<id>/`): everything BasedOS uses that comes from stock, as one
   unit with one id (a hash of its contents) and one recipe: the kernel `Image` and stock's DTBs
   as plain files (U-Boot loads them: it reads FAT and ext4, not squashfs), and
   `vendor.squashfs` with the kernel's modules, the Wi-Fi and Bluetooth firmware and the closed
   Mali drivers, 64- and 32-bit (Linux needs their links and modes). The kernel and its modules
   always come from the same stock build. Generous on purpose (all modules, all firmware), so it
   needn't change between bases. Never published: harvested on each device, or for each card,
   from its own stock source.
3. **BasedOS's own** (published): its boot script, written by BasedOS (not derived from stock's),
   which reads `basedos/boot.env` (the slot and the vendor id), loads the kernel and DTB from the
   vendor set, applies BasedOS's panel overlay (`fdt apply`: the 60 Hz timing, instead of a
   patched copy of stock's DTB) and boots BasedOS's initrd; the initrd; and the A/B system
   slots. Stock fallback is stock booting itself, from its own saved boot script.

**A base is one vendor set.** Every BasedOS release says which base it's built on (today the one
from ROCKNIX `c8ed06c`); the vendor id is the same on every device with that stock build.

- **Setup** (installing on the eMMC, or making an SD card) is the only time the stock source is
  read: it harvests the vendor set (`basedos-vendor`, by the base's recipe), then installs the
  system layer, initrd and boot script.
- **Updates** (`.bosupd`) change BasedOS's own files only, never the vendor set. A release for
  another base is refused ("built for a different stock base; needs a fresh setup").
- **Rebasing** onto a newer stock firmware is a fresh setup from that firmware's image file,
  rare by design. BasedOS keeps little state of its own (the frontend keeps the user's settings
  and games), so a fresh setup costs the user little; a rebase helper can come if a release
  ever needs one.

Why: no drift. A stock update can't change the kernel BasedOS boots or split it from its
modules; BasedOS's build doesn't depend on one exact stock boot script; and the eMMC and SD card
installs are the same files on different partitions.

### Today (2026-11-20), where it differs

- The boot script is stock's, rewritten (`mkboot.py bootscr`), and loads stock's own `Image` and
  (when BasedOS's isn't there) DTB from p1; BasedOS's panel DTB is a patched copy of stock's.
- The vendor layer is the squashfs alone (`vendor-<id>.squashfs`); the kernel and DTBs aren't in
  it.
- Updates can build a missing vendor layer on the device (`basedos-update` with
  `basedos-vendor`, from stock's `SYSTEM` on p1) and prune unused ones: to be removed (updates
  never change the vendor set).
- No SD card install yet.

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
| Init | BusyBox init: `rcS` sysinit, `frontend-session` respawn, `rcK` shutdown. No udev at boot; devtmpfs only (`basedos-udev` runs eudev's udevd for the length of a PortMaster Weston port, whose libinput needs its database). | both |
| Writable state | `/data` on p2 (ext4): keys, logs, machine-id, update state. tmpfs `/run`, `/tmp`, `/var`. Root is read-only. | my355 |
| Updates | `baseos-gkd350hultra-<ver>.bosupd` at the card root, `format=basedos-update/1`: a tar of `manifest`, the system layer and the initrd (`tools/mkupdate.py`; `basedos-update` installs it at boot into the spare slot) | my355's name and manifest style (spruce looks for `baseos-<target>-*.bosupd`); the format is BasedOS's own, as its slots are files |
| Logs | `/data/basedos.log` (mirroring to the card is not done yet) | both |

## eMMC layout

Today (the developer install, `tools/install-dev.sh`): stock's layout and files, untouched, with
BasedOS in one folder on each partition. Stock stays complete and bootable.

| Region | Contents |
|---|---|
| sectors 0 to 32767 | stock's MBR, idbloader and U-Boot FIT. Never written. |
| p1 vfat, 3 GB (`/flash` under stock, `/boot` under BasedOS) | stock's `SYSTEM` (2.3 GB, its root and the vendor layer's source), `Image`, DTBs; `boot.scr` (BasedOS's while BasedOS is on; stock's kept as `basedos/boot.scr.stock`); `basedos/`: the two system slots (`rootfs.squashfs`, `rootfs-b.squashfs`) and the slot file, `vendor-<id>.squashfs`, `initrd.uimg`, BasedOS's panel DTB |
| p2 ext4, 11.6 GB (stock's `/storage`) | stock's data; `basedos-data/`, BasedOS's `/data` (logs, update state, accounts, Wi-Fi, SSH keys) |
| `boot0`, `boot1` | an old Amlogic loader the RK3576 never reads; left alone |

Leaving it: `basedos-boot` (maintenance menu, Start at power-on) boots stock once, switches to
stock with a "Return to BasedOS" in stock's Ports, or uninstalls (stock's `boot.scr` back and both
folders removed).

Later, for the installer: a dedicated layout (p1 `BASEDOS`, p2 `BASEDOS-DATA`), or BasedOS on the
SD card alone with the eMMC never written.

## Boot flow

(Today's; the target is in Architecture above.)

1. U-Boot runs BasedOS's `boot.scr` (stock's, rewritten by `mkboot.py bootscr`), which loads `Image`, the panel DTB (BasedOS's 60 Hz one when present) and `basedos/initrd.uimg`, adds BasedOS's kernel options (`rdinit=/basedos/init`, `initcall_blacklist=raid6_select_algo`, `rcupdate.rcu_expedited=1`), then `booti` with the initrd. A missing or rejected initrd boots stock with stock's options.
2. The kernel unpacks its built-in initramfs and then ours over it, so our `/init` replaces stock's. Our `/basedos/init` counts the boot on p2, mounts p1 read-only, loop-mounts the chosen slot's system layer and the vendor layer it names, stacks them with overlayfs (falling back to the other slot, then to stock), then `switch_root`s and execs `/sbin/init`. `rcS` mounts p2 on `/data` and the tmpfs dirs.
3. BusyBox init runs `rcS`: proc/sys/devpts and the `/dev` links, the boot screen, the clock, `/data` (checked, then mounted), the card mount, a pending update (installed, then straight to a reboot), then the Wi-Fi driver and the shutdown-key watcher in the background. Joining Wi-Fi and SSH are the frontend's; BasedOS's own start only in maintenance mode or after a failing frontend.
4. `frontend-session` (respawned) runs the frontend probe. With no card or frontend, it shows a splash and retries.

## Rootfs

(Today's layout; the target is in Architecture above.) The root is two squashfs layers built on the PC (WSL has `mksquashfs`), stacked by the initrd with
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
- **The vendor layer on the device (2026-11-19; to become setup only, see Architecture):** every system layer carries a recipe for the vendor layer it needs (`usr/share/basedos/vendor-recipe`: each file's place, mode, SHA-256 and where it is in stock's SYSTEM, written by `build-rootfs.sh` from the harvest), and `basedos-vendor` builds that layer from the stock image on p1 (`/boot/SYSTEM`), checking every hash and the id (`usr/lib/basedos/vendor-id`, the one function both sides use). `basedos-update` uses it when a payload needs a vendor layer the device lacks, so a vendor change no longer strands `.bosupd` updates. This is also the core of the user installer: with a published system layer and its recipe, a device needs only its own stock image, not a PC or Buildroot.

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
