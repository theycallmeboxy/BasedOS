# BasedOS user guide (GKD 350H Ultra)

BasedOS is a small operating system that lives on the 350H Ultra's internal storage (eMMC) and starts
**spruce** from your SD card. Your spruce card stays a normal spruce card: you can move it
between the 350H Ultra and your other spruce devices.

> **Status: early.** BasedOS is installed next to the stock firmware, by a developer install
> (below). There is no one-click installer yet. Read "Recovery" before you start.

## What you need

- A GKD 350H Ultra on stock firmware **ROCKNIX 20260613, build `c8ed06c`** (other builds are
  refused: BasedOS is built from your device's own files and checks them).
- A full backup of the eMMC (see [recovery.md](recovery.md)). It is also where BasedOS's
  build takes your device's own files from.
- A spruce card (FAT32 or exFAT) with spruce plus the 350H Ultra kit (see
  [spruce-on-gkd.md](spruce-on-gkd.md)).
- A PC with Python 3 and WSL (Ubuntu) for building. The scripts are in `tools/`.

## Install (developer install, next to stock)

1. Back up the eMMC: `tools/dev/backup-emmc.sh` (see recovery.md). Keep two copies.
2. Prepare your stock files from the backup:
   `python tools/prepare_stock.py <backup>/mmcblk0.img prepared`
3. In WSL: build (`tools/wsl/build.sh`; it unpacks your stock image the first time). It writes
   `out/`: the vendor layer (`vendor-<id>.squashfs`, from your stock, never shared), the system
   layer (`rootfs.squashfs`), the initrd, the boot script and an update payload (`.bosupd`).
4. Make the panel's DTB (60 Hz; see power.md):
   `python tools/mkboot.py dtb prepared/<build>/rk3576-gkd-atom.dtb out/rk3576-gkd-atom.dtb`
5. With the 350H Ultra running stock and reachable over SSH, copy `out/` to `/tmp` on the device and run
   `tools/install-dev.sh /tmp/<dir>` there. It adds BasedOS's files to the boot partition (both
   layers, the initrd, the DTB), keeps stock's boot script, copies your Wi-Fi network and SSH keys,
   and leaves stock untouched.
6. Reboot. BasedOS starts, then spruce from the card.

To go back to stock: the maintenance menu (above), or from SSH `basedos-boot stock-once`,
`switch-to-stock` or `uninstall` (add `--reboot`); `basedos-boot status` says what boots next.
`install-dev.sh revert` (from stock or BasedOS) still puts stock's boot script back and leaves
BasedOS's files.

These are careful with the boot script, the one file that decides whether the device boots: each
script is checked before it's written (a well-formed boot script, BasedOS's or stock's as
expected; stock's against the known stock build) and read back after; everything a switch needs
is in place first, so a failure leaves the device as it was; nothing is removed until stock's
script is back.

## Everyday use

| You do | BasedOS does |
|---|---|
| Power on | boots in about 4 s to spruce's menu |
| Power on **holding Select** | **maintenance mode**: no spruce; Wi-Fi and SSH, and a menu (Up/Down, A): **Start stock once**; **Switch to stock** (stock boots from then on, and a "Return to BasedOS" entry in stock's Ports puts BasedOS back); **Uninstall BasedOS** (removes its files and settings from the device while it restarts, then starts stock; stock is as before the install); Restart; Power off. Switching and uninstalling want A held 3 s; B goes back. The screen shows the address to SSH to once Wi-Fi is up |
| Power on **holding Start** | **stock, for this boot**: BasedOS restarts into stock once; the next power-on is BasedOS again |
| Power on **holding another button** | whatever `/data/boot-keys.conf` maps it to (none by default): maintenance mode, stock once, or a frontend on the card other than the first one found. The format and the button names are in `/usr/share/basedos/boot-keys.conf`; copy it to `/data/` to change it. The boot screen lists the mapped buttons |
| Hold **Volume Up + Volume Down** together **3 s** | clean shutdown with any frontend, also a hung one: programs get 3 s to save and quit, then the card is synced and unmounted (`basedos-shutdown-keys`). Holding power is the frontend's (spruce: Button Settings > Power button hold time) |
| Tap power (in spruce) | sleep; tap again to wake. spruce's "Shutdown after sleeping" works |
| Pull and reinsert the card | the card is found again; a card that wasn't unmounted cleanly is checked first |

Without a card, BasedOS waits for one and says so once on screen.

## Wi-Fi and SSH

- Wi-Fi is spruce's, as on its other devices: join, forget and switch it off from spruce's menu.
  The networks are saved on the card, so they go wherever the card goes. BasedOS only loads the
  Wi-Fi driver at boot.
- BasedOS's own Wi-Fi is for maintenance mode, and for when the frontend keeps failing: then it
  joins the networks in `/data/wpa_supplicant.conf` on the eMMC (the installer fills it from
  stock's saved networks; edit it over SSH).
- SSH: with spruce's "Enable SSH" on, spruce's own SSH answers: user `spruce`, password
  `happygaming`. With it off there is no SSH. In maintenance mode, or when the frontend keeps
  failing, BasedOS's own SSH answers as `root` with **no password**. Use only on a network you
  trust.

## Updates

- Put a `baseos-gkd350hultra-<version>.bosupd` at the root of the card and restart, or use spruce's
  firmware update app, which finds one there (or downloads one) and restarts for you. BasedOS
  installs it while starting: the screen says so, and it restarts once more into the new version.
- It goes into the copy of BasedOS that isn't running, and is checked before it's used. If the new
  copy doesn't start, BasedOS goes back to the old one after a few tries, and won't try that
  update again.
- An update holds only BasedOS's own files. When it needs different parts of your device's stock
  firmware (the vendor layer), BasedOS builds them while installing, from the stock image that
  stays on the device next to it (`basedos-vendor`, about a minute; the screen says so); no PC
  needed. If your stock image isn't the build the update is for, the update fails and the running
  version stays. Vendor layers no longer needed are removed once an update has started. To see what
  an update would do, from SSH: `basedos-update status`; `basedos-vendor status` shows the vendor
  layers.
- An update doesn't carry the boot script either, so a change to BasedOS's kernel options needs a
  developer update (`tools/dev/update-basedos.sh`) for now.

## Safeguards

- **Boot counter**: if BasedOS fails to start three times in a row it boots its other copy (A/B
  slot); after five failures it boots stock. Delete `boot-attempts` in BasedOS's data folder to reset.
- **Bad boot files**: if BasedOS's initrd is missing or damaged, the boot script boots stock.
- **Frontend crash loop**: if spruce exits within 15 s five times in a row, BasedOS stops
  restarting it and shows a message, instead of looping.
- **Card checks**: a card left dirty by a power cut is checked (`fsck`) once before use.

## Recovery

If anything goes wrong, see [recovery.md](recovery.md). In short, from gentlest to strongest:

1. **Rescue SD card**: boots stock from the card; the eMMC is untouched and can be restored.
2. **USB disk mode**: hold **Menu + Home** and power on; the whole eMMC appears on your PC.
3. **Maskrom**: hold **Volume Down** and power on; RKDevTool can rewrite the whole eMMC.

All three have been tested on a unit, including a full restore.

## Logs

- BasedOS: `/data/basedos.log` on the eMMC (`basedos-data/basedos.log` seen from stock), about the
  last 256 KB; the part before is in `basedos.log.1`.
- spruce: `Saves/spruce/spruce.log` and `pyui.log` on the card.
