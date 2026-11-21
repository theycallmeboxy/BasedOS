# BasedOS plan

## Status

**Being rebuilt (round 3, 2026-11-20 evening) on the simplified architecture below; not yet on
the unit.** Until then, what ran on the unit (2026-11-20, build `c9ee8f9`, installed next to stock
with `tools/install-dev.sh`; power to spruce's menu in about 4 s, boot-time.md) was the earlier
vendor-set design. Checked on the unit, and carried over:

- A/B slots with a boot counter that falls back to the other slot, then to stock; with
  BasedOS's files unloadable, the boot script hands over to stock's own.
- Updates: a `.bosupd` at the card root, from spruce's BaseOS updater or by hand, installed at the
  next boot into the spare slot and confirmed once it boots (`basedos-update`). The boot script
  is not in a payload.
- Leaving BasedOS (`basedos-boot`, the maintenance menu, Start held at power-on): stock once,
  switch to stock with "Return to BasedOS" in stock's Tools, uninstall (done by the initrd at the
  restart). Each boot script written is checked and read back.
- spruce: menu, emulators (RetroArch, DSperate, DraStic, PPSSPP, Mupen64Plus, Flycast,
  YabaSanshiro), E-Reader, Gallery, sleep and wake, clean shutdown, Wi-Fi and SSH (spruce's own,
  as on its other devices), screenshots, PortMaster with Weston and 32-bit ports (lib32.md,
  portmaster-libs.md). Details in spruce-on-gkd.md.
- Maintenance mode (Select held at power-on): BasedOS's own Wi-Fi and root SSH, no frontend, and
  the menu above.
- The boot screen, quiet boot, boot keys, and the Volume Up + Volume Down shutdown watcher.
- The recovery card (setup, choice 2; recovery.md): made on the device, booted, and a real restore
  of the eMMC verified byte for byte (2026-11-20).

Not done yet: a way for an update to change the boot script and its kernel options, Bluetooth,
USB storage mode, ScummVM on spruce, and the old-library compat set some ports want
(portmaster-libs.md).

## Architecture (decided 2026-11-20, evening)

BasedOS is installed **next to stock on the eMMC**, and uses **stock's own files in place**.

- **Stock is static.** GKD's firmware has no update channel of its own: its updater is ROCKNIX's
  generic `rocknix-update`, which asks `update.rocknix.org` as an RK3399 "community" build. Stock
  changes only when it's reflashed (or if that updater pulls something, which is a hazard for
  stock itself).
- **What BasedOS uses of stock, in place:** stock's kernel `Image` and DTBs (U-Boot loads them
  from stock's boot partition, where they are), and stock's `SYSTEM` squashfs, which the initrd
  mounts read-only at `/stock`. BasedOS's system layer has links into `/stock` for exactly the
  stock files it uses (`manifest/harvest.list`: the closed Mali GPU and Vulkan drivers, 64- and
  32-bit, the Wi-Fi and Bluetooth firmware, the kernel's modules), never copies; nothing else of
  stock's userland is visible. The kernel and its modules are always the same stock build's.
- **Pinned to the stock build.** A system layer is made against one stock build
  (`usr/share/basedos/needs-stock`: stock's `BUILD_ID`). The initrd checks it against the stock
  it mounts on every boot; any other stock and BasedOS steps aside to stock. Setup checks stock's
  build and the SHA-256 of its kernel, DTBs and `SYSTEM` before it installs. A new stock build
  takes a BasedOS release made for it.
- **BasedOS's own** (published): its boot script (written by BasedOS, not derived from stock's;
  it sets the panel to 60 Hz with `fdt set` on the loaded device tree, never changing stock's
  file), its initrd, the A/B system slots, its tools. A `.bosupd` carries the system layer and the
  initrd and names the stock build it's made for.
- **No SD-card install, and no vendor copies.** Both were tried and dropped (2026-11-20): the
  boot ROM only ever starts the bootloader from the eMMC (a card's copy is never used: tested,
  recovery.md), so no install path is independent of the eMMC, and with stock static, copies of
  its files only duplicated what's already beside them. The frontend's card is a normal, portable
  spruce card.

## Starting point## Starting point (verified on the device, 2026-11-16)

- **Device:** RK3576S, 2 GB RAM, 16 GB eMMC (`mmcblk0`), one SD slot (`mmcblk1`),
  a 1440×1600 portrait DSI panel shown landscape. The device tree model is
  "GameKiddy GKD ATOM".
- **Stock:** ROCKNIX 20260613 build `c8ed06c`. Its kernel is a Rockchip BSP
  6.1.118 with almost every driver built in (only `bcmdhd` Wi-Fi is a module).
  It has a built-in initramfs (EmuELEC's, 32-bit) and accepts an external
  initrd. overlayfs, squashfs (zstd/lz4/xz), ext4, vfat, exFAT and USB
  configfs gadgets are all built in.
- **Boot chain:** the boot ROM loads the idbloader at sector 64 of the eMMC, then
  the U-Boot FIT at 8 MiB. The boot ROM never starts a bootloader from the SD card
  (tested 2026-11-20 with the eMMC's bootloader zeroed: power LED, black screen;
  only maskrom brings it back). U-Boot then runs the first `boot.scr` it finds, the
  SD card's before the eMMC's p1 (vfat). BasedOS never touches sectors 0 to 32767.
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

Stock's layout and files, untouched, with BasedOS in one folder on each partition. Stock stays
complete and bootable.

| Region | Contents |
|---|---|
| sectors 0 to 32767 | stock's MBR, idbloader and U-Boot FIT. Never written. |
| p1 vfat, 3 GB (`/flash` under stock, `/boot` under BasedOS) | stock's own files, used in place and never changed: `SYSTEM` (2.3 GB, mounted read-only at `/stock`), `Image`, DTBs (booted by BasedOS's boot script); `boot.scr` (BasedOS's own while BasedOS is on; stock's kept as `basedos/boot.scr.stock`); `basedos/`: `initrd.uimg`, the two system slots (`rootfs.squashfs`, `rootfs-b.squashfs`) and the slot file |
| p2 ext4, 11.6 GB (stock's `/storage`) | stock's data; `basedos-data/`, BasedOS's `/data` (logs, update state, accounts, Wi-Fi, SSH keys) |
| `boot0`, `boot1` | an old Amlogic loader the RK3576 never reads; left alone |

Leaving it: `basedos-boot` (maintenance menu, Start at power-on) boots stock once, switches to
stock with a "Return to BasedOS" in stock's Tools, or uninstalls (stock's `boot.scr` back and both
folders removed).

## Boot flow

1. U-Boot's distro boot runs the first `boot.scr` it finds. BasedOS's (`initrd/boot.cmd`, its
   own) picks the DTB for the output U-Boot's display menu chose (`hdmi_detect`: panel, HDMI,
   USB-C), loads stock's kernel and that DTB, and `basedos/initrd.uimg`, from stock's boot
   partition, sets the panel's 60 Hz timing (`fdt set`), and boots with BasedOS's kernel options
   (`rdinit=/basedos/init`, `basedos.disk=mmcblkN`, quiet). If those files can't be loaded it runs
   stock's saved boot script, so stock boots itself.
2. The kernel unpacks its built-in initramfs and then ours over it, so our `/init` runs, not
   stock's. `/basedos/init` mounts p1 read-only, counts the boot on p2 (and does a pending
   uninstall or stock-once there), loop-mounts the chosen slot's system layer as the root and
   stock's `SYSTEM` at its `/stock`, checks that stock is the build the slot was made for (falling
   back to the other slot, then to stock's own `/init`), then `switch_root`s and execs `/sbin/init`.
3. BusyBox init runs `rcS`: proc/sys/devpts and the `/dev` links, the boot screen, the clock, `/data` (checked, then mounted from p2), the card mount, a pending update (installed, then straight to a reboot), then the Wi-Fi driver and the shutdown-key watcher in the background. Joining Wi-Fi and SSH are the frontend's; BasedOS's own start only in maintenance mode or after a failing frontend.
4. `frontend-session` (respawned) runs the frontend probe. With no card or frontend, it shows a splash and retries.

## Rootfs

The root is one squashfs, the system layer, built on the PC (`tools/wsl/build-rootfs.sh`; WSL has
`mksquashfs`), with stock's `SYSTEM` mounted at its `/stock` on the device:

1. **A skeleton and BusyBox:** Alpine's `busybox-static` (aarch64), the same as my355.
2. **BasedOS's userland:** built from source by Buildroot (`manifest/base.list`; vendor-minimal.md), plus SDL2 with librga, bash and the 32-bit libraries for PortMaster's ports.
3. **The links into `/stock`:** for each file `manifest/harvest.list` takes from stock (and the libraries those need that BasedOS doesn't have: a Python closure check, ELF `DT_NEEDED` against `SONAME`s, as my355 does), a link to its place in stock's `SYSTEM`; stock's own links among them are kept as they are. The build harvests those files only as a build-time view, for its checks; `usr/share/basedos/stock-links` lists them.
4. **The BasedOS overlay:** `/init`, inittab, `rcS`, `rcK`, `frontend-session`, `mount-frontend`, `baseos-release`, profile, fstab.

The build fails if a stock file is in the system layer. `prepare-stock` checks the stock build the PC build reads against known fingerprints (`c8ed06c` for now). `out/release.info` records the stock build (`STOCK_BUILD_ID`) and the SHA-256 of stock's kernel, DTBs and `SYSTEM`, which setup checks on the device.

## Install paths

- **Users:** `tools/basedos-setup.sh`, run on the device under stock over SSH (user-guide.md, "Setup on the device"); it downloads its release from GitHub. Two choices: install BasedOS on the eMMC (a recovery card first is recommended and offered), or make a recovery card (recovery.md). Nothing of stock's is published or copied.
- **Developer:** build on the PC (`tools/wsl/build.sh`), then run `tools/install-dev.sh` on the device under stock, over SSH. Later builds go in with `tools/dev/update-basedos.sh` from BasedOS, or as a `.bosupd`.

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
- What BasedOS takes from stock is already minimal (decided 2026-11-19): only the closed GPU
  drivers, firmware and kernel modules, the rest built by BasedOS (Buildroot); since 2026-11-20
  linked from stock's own SYSTEM, not copied. Inventory: vendor-minimal.md.
