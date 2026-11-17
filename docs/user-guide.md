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
3. In WSL: unpack them (`tools/wsl/unpack-stock.sh`) and build the rootfs (`tools/wsl/build.sh`).
4. Make the boot files: `python tools/mkboot.py initrd prepared/alpine/busybox.static out/initrd.uimg`
   and `python tools/mkboot.py bootscr prepared/<build>/boot.scr out/boot.scr`.
5. With the 350H Ultra running stock and reachable over SSH, copy `out/` to `/tmp` on the device and run
   `tools/install-dev.sh /tmp/<dir>` there. It adds BasedOS's files to the boot partition, keeps
   stock's boot script, copies your Wi-Fi network and SSH keys, and leaves stock untouched.
6. Reboot. BasedOS starts, then spruce from the card.

To go back to stock: `install-dev.sh revert` (from stock or BasedOS), then reboot.

## Everyday use

| You do | BasedOS does |
|---|---|
| Power on | boots in about 5 s to spruce's menu |
| Power on **holding Select** | **maintenance mode**: no spruce; Wi-Fi and SSH only, IP on screen |
| Hold power **5 s** | clean shutdown (saves are flushed and the card is unmounted) |
| Tap power (in spruce) | sleep; tap again to wake. spruce's "Shutdown after sleeping" works |
| Pull and reinsert the card | the card is found again; a card that wasn't unmounted cleanly is checked first |

Without a card, BasedOS waits for one and says so once on screen.

## Wi-Fi and SSH

- BasedOS joins the networks in `/data/wpa_supplicant.conf` on the eMMC. The installer fills it
  from stock's saved networks. To change networks, edit that file over SSH (from maintenance mode
  if needed) and reboot.
- SSH: with spruce's "Enable SSH" on, spruce's own SSH answers: user `spruce`, password
  `happygaming`. With it off, spruce turns SSH off. In maintenance mode, or without a card,
  BasedOS's own SSH answers as `root` with **no password**. Use only on a network you trust.

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

- BasedOS: `/data/basedos.log` on the eMMC (`basedos-data/basedos.log` seen from stock).
- spruce: `Saves/spruce/spruce.log` and `pyui.log` on the card.
