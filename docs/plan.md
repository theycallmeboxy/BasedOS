# BasedOS plan

## Status

**On the unit (2026-11-22, build `658c2ab`) on the architecture below,** installed next to stock
by `basedos-setup` (power to spruce's menu in about 4 s, boot-time.md). Checked on the unit:

- One system layer and a boot counter that falls back to stock after three failed starts (A/B
  slots were dropped 2026-11-21: their fallback only covered a layer that verified but didn't
  start, which stock now catches, and setup's Repair puts a release back from stock); with
  BasedOS's files unloadable, the boot script hands over to stock's own.
- Updates: a `.bosupd` at the card root, from spruce's BaseOS updater or the maintenance menu,
  written beside the running layer as `rootfs.new` and put in place by the initrd at the restart
  (`basedos-update`). The boot script is not in a payload.
- Leaving BasedOS (`basedos-boot`, the maintenance menu, Start held at power-on): stock once,
  disable BasedOS (stock boots; BasedOS's menu in stock's Ports turns it back on, and has
  Disable and Uninstall too), uninstall (done by the initrd at the restart). Each boot script
  written is checked and read back. BasedOS's menu in stock's Ports: Disable, Enable and
  Uninstall, each used on the unit (2026-11-22).
- spruce: menu, emulators (RetroArch, DSperate, DraStic, PPSSPP, Mupen64Plus, Flycast,
  YabaSanshiro), E-Reader, Gallery, sleep and wake, clean shutdown, Wi-Fi and SSH (spruce's own,
  as on its other devices), screenshots, PortMaster with Weston and 32-bit ports (lib32.md,
  portmaster-libs.md). Details in spruce-on-gkd.md.
- Maintenance mode (Select held at power-on): BasedOS's own Wi-Fi and root SSH, no frontend, and
  the menu above.
- The boot screen, quiet boot, boot keys, and the Volume Up + Volume Down shutdown watcher. The
  waiting screens watch the boot keys too: Start held on "no frontend on the SD card" started
  stock (2026-11-22).
- Setup (`basedos-setup`, run on stock): install, repair (also with BasedOS's folder deleted),
  uninstall, and removing what an unfinished install or uninstall left. From a setup card with no
  PC (2026-11-22): install, repair, uninstall, a recovery card, disable and enable, with the
  checks' progress on the screen.
- The recovery card (setup's "Make a recovery SD card"; recovery.md): made on the device, and two
  real restores of the eMMC: one verified byte for byte (2026-11-20), one after a boot script hung
  (2026-11-21).

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
  file), its initrd, the system layer, its tools. The boot script and the initrd are its
  **boot files**: they put an update in place and count failed boots, so a bad one would stop
  every start, and only setup (or a developer update) installs them. A `.bosupd` carries the system
  layer only, and names the stock build it's made for and the initrd interface it needs (the
  initrd's `ABI`, in its image name; a system layer's `usr/share/basedos/needs-initrd`): a
  device whose initrd is older refuses it, and the initrd itself won't use such a layer.
- **No SD-card install, and no vendor copies.** Both were tried and dropped (2026-11-20): the
  boot ROM only ever starts the bootloader from the eMMC (a card's copy is never used: tested,
  recovery.md), so no install path is independent of the eMMC, and with stock static, copies of
  its files only duplicated what's already beside them. The frontend's card is a normal, portable
  spruce card.

## Starting point (verified on the device, 2026-11-16)

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
| Updates | `baseos-gkd350hultra-<ver>.bosupd` at the card root, `format=basedos-update/1`: a tar of `manifest` and the system layer (`tools/mkupdate.py`; `basedos-update` installs it as `rootfs.new` when asked, at boot after spruce's updater requests it or from the maintenance menu, and the initrd puts it in place at the restart) | my355's name and manifest style (spruce looks for `baseos-<target>-*.bosupd`); the format is BasedOS's own, as its slots are files |
| Logs | `/data/basedos.log` (mirroring to the card is not done yet) | both |

## eMMC layout

Stock's layout and files, untouched, with BasedOS in one folder on each partition. Stock stays
complete and bootable.

| Region | Contents |
|---|---|
| sectors 0 to 32767 | stock's MBR, idbloader and U-Boot FIT. Never written. |
| p1 vfat, 3 GB (`/flash` under stock, `/boot` under BasedOS) | stock's own files, used in place and never changed: `SYSTEM` (2.3 GB, mounted read-only at `/stock`), `Image`, DTBs (booted by BasedOS's boot script); `boot.scr` (BasedOS's own while BasedOS is on; stock's own kept beside it as `boot.scr.stock`, outside BasedOS's folder: stock's file under another name, renamed back at uninstall); `basedos/`: `initrd.uimg`, the system layer (`rootfs.squashfs`; an installed update waits as `rootfs.new` until the restart) |
| p2 ext4, 11.6 GB (stock's `/storage`) | stock's data; `basedos-data/`, BasedOS's `/data` (logs, update state, accounts, Wi-Fi, SSH keys) |
| `boot0`, `boot1` | an old Amlogic loader the RK3576 never reads; left alone |

Leaving it: `basedos-boot` (maintenance menu, Start at power-on) boots stock once, disables
BasedOS (stock boots; Enable BasedOS in BasedOS's menu in stock's Ports turns it back on), or uninstalls (stock's
`boot.scr` back and both folders removed). BasedOS's menu in stock's Ports (`BasedOS.sh`: Disable
or Enable, and Uninstall) goes to both places stock may show Ports from: its
automount binds `games-internal/roms` or the card's `roms` by its setting
`system.merged.device`, and with a spruce card (`Roms`) the latter binds nothing and p2's own
`roms` shows. Both are on p2, never the card. The entry only starts the menu: the menu and its
actions (`/usr/share/basedos/stock/`) come from BasedOS's system layer, so they change with
BasedOS's updates, and show BasedOS's screens (`screen.sh`, `basedos-splash`, `basedos-keys`,
copied into memory). They draw on the framebuffer, which the panel shows once stock's frontend
(sway and EmulationStation) is stopped; the menu runs as its own service (`systemd-run`), since
stopping the frontend stops what it started, and starts the frontend again when it's done. The
seat manager hands the console back in text mode just after the frontend stops, and the text
console clears the screen then: `basedos-splash --console graphics` waits for that and keeps
the console off the screen until the frontend starts again.
A setup card carries the same `BasedOS.sh`: with a release beside it (`basedos-setup/`), it runs
`load` (with the screens from the card's system layer, so the screen is up from the start), which copies
that release into memory, checks it, and runs setup from it (`basedos-setup.sh --screen`) the
same way, with Disable and Enable in its menu too.

## Boot flow

1. U-Boot's distro boot runs the first `boot.scr` it finds. BasedOS's (`initrd/boot.cmd`, its
   own) picks the DTB for the output U-Boot's display menu chose (`hdmi_detect`: panel, HDMI,
   USB-C), loads stock's kernel and that DTB, and `basedos/initrd.uimg`, from stock's boot
   partition, sets the panel's 60 Hz timing (`fdt set`), and boots with BasedOS's kernel options
   (`rdinit=/basedos/init`, `basedos.disk=mmcblkN`, quiet). If those files can't be loaded it runs
   stock's own boot script, kept beside it as `boot.scr.stock`, so stock boots itself (tested
   2026-11-21 with BasedOS's folder deleted).
2. The kernel unpacks its built-in initramfs and then ours over it, so our `/init` runs, not
   stock's. `/basedos/init` mounts p1 read-only, counts the boot on p2 (and does a pending
   uninstall or stock-once there), puts an installed update (`rootfs.new`) in place, loop-mounts the system
   layer as the root and stock's `SYSTEM` at its `/stock`, checks that stock is the build the layer
   was made for (falling back to stock's own `/init`), then `switch_root`s and execs `/sbin/init`.
3. BusyBox init runs `rcS`: proc/sys/devpts and the `/dev` links, the boot screen, the clock, `/data` (checked, then mounted from p2), a first try at the card, then the Wi-Fi driver and the shutdown-key watcher in the background. Joining Wi-Fi and SSH are the frontend's; BasedOS's own start only in maintenance mode or after a failing frontend.
4. `frontend-session` (respawned) mounts the card (retrying until it's probed), installs a requested update once a boot (`basedos-update apply`: installed, then straight to a reboot), then runs the frontend probe. With no card or frontend, it shows a splash and retries. The panel shows the framebuffer again whenever the frontend lets go of the display (spruce clears it after its menu's first exit), so once the frontend's first frame is up, the boot screen behind it is redrawn as "Intermission..." alone in the middle (`basedos-splash --centre`), and what shows through looks meant. What's on the panel is read from the DRM state in debugfs, mounted for the wait only: opening the display device to ask would make BasedOS the display's owner while no program is.

## Rootfs

The root is one squashfs, the system layer, built on the PC (`tools/wsl/build-rootfs.sh`, in WSL or
in the build container on any Linux host, `tools/container/`; both have `mksquashfs`), with stock's `SYSTEM` mounted at its `/stock` on the device:

1. **A skeleton and BusyBox:** Alpine's `busybox-static` (aarch64), the same as my355.
2. **BasedOS's userland:** built from source by Buildroot (`manifest/base.list`; vendor-minimal.md), plus SDL2 with librga, bash and the 32-bit libraries for PortMaster's ports.
3. **The links into `/stock`:** for each file `manifest/harvest.list` takes from stock (and the libraries those need that BasedOS doesn't have: a Python closure check, ELF `DT_NEEDED` against `SONAME`s, as my355 does), a link to its place in stock's `SYSTEM`; stock's own links among them are kept as they are. The build harvests those files only as a build-time view, for its checks; `usr/share/basedos/stock-links` lists them.
4. **The BasedOS overlay:** `/init`, inittab, `rcS`, `rcK`, `frontend-session`, `mount-frontend`, `baseos-release`, profile, fstab.

The build fails if a stock file is in the system layer. `prepare-stock` checks the stock build the PC build reads against known fingerprints (`c8ed06c` for now). `out/release.info` records the stock build (`STOCK_BUILD_ID`) and the SHA-256 of stock's kernel, DTBs and `SYSTEM`, which setup checks on the device.

## Install paths

- **Users:** `tools/basedos-setup.sh`, run on the device under stock over SSH (user-guide.md, "Setup on the device"); it downloads its release from GitHub. What it offers depends on what it finds: install BasedOS on the eMMC, or repair or uninstall it, or remove what an unfinished install or uninstall left (a recovery card first is recommended and offered), and always making a recovery card (recovery.md). Nothing of stock's is published or copied.
- **Developer:** build on the PC (`tools/wsl/build.sh` in WSL, or `tools/container/run.sh tools/wsl/build.sh` on any Linux host), then run `tools/install-dev.sh` on the device under stock, over SSH. Later builds go in with `tools/dev/update-basedos.sh` from BasedOS, or as a `.bosupd`.

## Versions

- **v0 (done 2026-11-16):** boots to BusyBox init. SSH over Wi-Fi, the card mounted at `/mnt/SDCARD`, frontend probe, splash. No updates, no A/B. Success means BasedOS hands off to a test frontend, then to spruce, whatever spruce does after that.
- **v1 (mostly done):** power key handling, battery and charging, sleep and audio (spruce's, on BasedOS), `.bosupd` updates (A/B and trial boots, then one layer with stock as the fallback). Left: a USB gadget (adb or storage), the boot log on the card.
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
