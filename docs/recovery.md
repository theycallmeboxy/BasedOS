# GKD 350H Ultra: eMMC backup and restore

Take a full backup before anything writes to the eMMC. It is also the only
copy of stock: no official stock image has turned up.

## Taking the backup

The first backup (2026-11-16) was taken step by step with `gkdssh.py dump`.
`backup-emmc.sh` packages those same steps but hasn't been run end to end yet.
From the repo root on the PC, with the device on Wi-Fi running stock:

```sh
export MSYS_NO_PATHCONV=1 GKD_HOST=<device address> GKD_PASS=
sh tools/dev/backup-emmc.sh ../backup/<date>
```

- It finds the eMMC by type (`MMC` on controller `2a330000`) instead of
  assuming `mmcblk0`. On stock it is `mmcblk0`: 30,535,680 sectors (15.6 GB),
  MBR, p1 vfat `/flash` at sector 32768, p2 ext4 `/storage` to the end.
- It saves the whole user area, both hardware boot partitions, and a hash of
  everything as read on the device. It ends with `VERIFIED` when the PC image's
  md5 matches the device's.
- It writes nothing to the device. `/storage` stays mounted read-write, so
  `p2-writes.txt` records p2's write counter before and after. Equal counters
  mean the image is a clean snapshot. On the first run, stock wrote nothing to
  p2 over about 50 minutes.
- Compare hashes of the **whole disk** device (`/dev/mmcblk0`). Don't use
  `/dev/mmcblk0p2` while `/storage` is mounted. Reading the partition device
  returns the kernel's in-memory copy of some ext4 metadata, not what is on
  disk. On the first run, one block differed this way: the bitmap of a
  `BLOCK_UNINIT` group, which ext4 builds in memory and never reads from disk.
- About 2 minutes over Wi-Fi for the empty parts, and about 10 minutes for the
  2.2 GB compressed system image inside p1, which doesn't compress further.

What the regions hold:

| Region | Sectors | Holds |
|---|---|---|
| loader area | 0 to 32767 (16 MiB) | MBR; idbloader (`RKNS`) at 64; U-Boot FIT at 16384 (8 MiB) |
| p1 `/flash` | 32768, +6,144,000 | `Image`, DTBs, `boot.scr`, `SYSTEM` squashfs |
| p2 `/storage` | 6,176,768 to the end | settings, saves, ROMs on the eMMC |
| `boot0`/`boot1` | 4 MiB each | an unused Amlogic BL2 (see recon.md). Read-only in Linux. Never needs restoring. |

## Known stock builds

These fingerprints identify which stock build a backup holds. They are also the
start of the allowlist that the installer's harvest step will check against.
They are hashes only, so no vendor files are redistributed.

**ROCKNIX 20260613 community `dev`, build `c8ed06c`**
(`BUILD_ID=c8ed06c7e9222f739308219f4678010f250100c5`, built Jun 13 2026
12:39:53 HKT), as shipped on the first unit backed up (2026-11-16):

| File / region | sha256 |
|---|---|
| `/flash/Image` | `6fcfbd235c5e921116b7254da77f02c6171b33fe8b174ebac8daa25bd784eab0` |
| `/flash/SYSTEM` | `9581f8f9b5d6e5dd49ec709977a71fc3c3b6ed2d34bd88c4ada8e77c39450cb4` |
| `/flash/boot.scr` | `13e38342ac0b81881afab51bfac4959f4808215ed42bc9407f7b568379b20713` |
| `/flash/rk3576-gkd-atom.dtb` | `602147a55e84a1f0cc81734c6f832b963112c8d546739134f06b88e681e0074a` |
| `/flash/rk3576-gkd-atom-hdmi.dtb` | `82ae35d0a84e9c89d7a180bba4f80af28ca6a91a6703ef11513c9b022503dd91` |
| `/flash/rk3576-gkd-atom-usbdp.dtb` | `f80108a29f45c2a6eaf934d778311f3396c778178b6662d23eb4dde1159a7c28` |
| idbloader, sectors 64 to 16383 | `98d9db607f271ec60bae40de31a2073c07bef7dfff867ef592fd59aa648a51fd` |
| U-Boot FIT area, sectors 16384 to 32767 | `fc621b41351693392b42efc560c40f7ce4143beddafafc1634aa6d4447a1d77a` |

Whole-image and partition hashes are specific to each unit (`/storage`, the
resize log, the MBR disk ID), so they aren't listed here.

## Rescue SD card (built and boot-tested 2026-11-16)

The rescue card is stock itself, running from the SD card. It's built on the
device from the device's own files, so nothing is downloaded or redistributed.
It boots whenever it's in the slot. Remove it to boot the eMMC again.

**Why stock can't simply be copied to a card:** stock's initramfs (inside
`Image`) mounts `/dev/mmcblk0p1` and `/dev/mmcblk0p2` by name and runs
`fsck -y` on both. It ignores the device it was booted from. The kernel numbers
`mmcblk` devices by the DT aliases, so `mmcblk0` is always the eMMC. Stock's
kernel on a card would therefore boot the eMMC's system.

**The fix:** the card's DTBs swap `/aliases/mmc0` and `mmc1`. The SD slot
becomes `mmcblk0` and the eMMC becomes `mmcblk1`, and that changes 2 bytes per
DTB. Stock's automount then leaves the eMMC alone, because it skips any disk
with `boot0` partitions ("might be Android").

How to build it, on stock with a spare card of 12 GB or more in the slot:

```sh
W=<scratch dir>
python tools/rescue/mkbootscr-card.py <stock boot.scr> $W/boot.scr
for d in rk3576-gkd-atom rk3576-gkd-atom-hdmi rk3576-gkd-atom-usbdp; do
  python tools/rescue/dtb-swap-mmc.py <stock $d.dtb> $W/$d.dtb; done
gkdssh.py push $W /tmp/rescue-files
gkdssh.py script tools/rescue/make-rescue-card.sh probe          # shows the card's CID
gkdssh.py script tools/rescue/make-rescue-card.sh write <CID>    # erases that card
gkdssh.py push <backup>/mmcblk0.img.zst /run/rescue-card/p2/rescue-backup/mmcblk0.img.zst   # optional
gkdssh.py script tools/rescue/make-rescue-card.sh finish         # unmount and reboot into it
```

| Card region | Contents |
|---|---|
| sectors 64 to 32767 | the eMMC's own idbloader and U-Boot FIT, copied byte for byte |
| p1 vfat `GKD-RESCUE` at 32768 (3 GB) | stock `Image` and `SYSTEM`; `boot.scr` loading from `mmc 1:1`; the swapped DTBs |
| p2 ext4 `GKD-RESCUE-ST` to the end | a copy of stock `/storage` (same Wi-Fi, SSH, hostname); `rescue-backup/` with the backup and its README |

Verified on the device on the first boot from the card:

- `/flash` and `/storage` came from the card (`mmcblk0`, on `2a310000.mmc`).
  The eMMC is `mmcblk1` (`2a330000.mmc`, has `boot0`), and none of it is
  mounted, including after automount ran.
- The eMMC's first 16 MiB and p1 hash identically to the backup.
  `e2fsck -fn` on its p2 is clean.
- The eMMC took 0 sectors of writes. The only write request was the cache flush
  from the read-only `e2fsck`.
- The 4 GB backup on the card decompresses to the image's md5.

Not tested yet: booting the card with a damaged eMMC loader, which needs the
BootROM to fall back to the SD card.

## Restoring

**Restore write tested 2026-11-16.** From the rescue card, p1 was restored
from the card's own compressed backup to the eMMC. The bytes were identical,
so the content didn't change.

```sh
zstd -dc /storage/rescue-backup/mmcblk0.img.zst |
  dd of=/dev/mmcblk1p1 bs=4M skip=4 count=750 iflag=fullblock conv=fsync
```

- The extracted slice hashed to p1's md5 before writing (a dry run piped to
  `md5sum`).
- `dd` wrote 6,144,000 sectors in 53 s. After dropping caches, p1 read back
  with the same md5, and the loader area was unchanged.
- With the card removed, stock booted from the eMMC as before.

Region offsets in the image, in 4 MiB blocks (`bs=4M`, always with
`iflag=fullblock` when reading from a pipe):

| Region | `skip` | `count` | Write to |
|---|---|---|---|
| loader area (16 MiB) | 0 | 4 | `/dev/mmcblk1` (careful: sector 0 is the MBR) |
| p1 | 4 | 750 | `/dev/mmcblk1p1` |
| p2 | 754 | (rest) | `/dev/mmcblk1p2` |
| whole disk | 0 | (all) | `/dev/mmcblk1` |

1. **Restore only what broke.** The loader area, p1 and p2 are independent.
   A broken base OS usually means restoring p1 and p2 and leaving the loader
   alone.
2. **From the rescue card** (or any Linux booted off an SD card). On the
   rescue card the eMMC is `/dev/mmcblk1`. Check it anyway: type `MMC` on
   `2a330000.mmc`. Then:

   ```sh
   zstd -dc /storage/rescue-backup/mmcblk0.img.zst | dd of=/dev/mmcblk1 bs=4M iflag=fullblock conv=fsync
   ```

   For one region, use `skip`/`count` from the table above. Do a dry run into
   `md5sum` first.
3. **USB disk mode (U-Boot `ums`)**, see below. With admin rights, a raw disk
   writer on the PC (Rufus, Win32 Disk Imager, `dd`) restores the whole image.
   This needs no special drivers.
4. **Maskrom** (see below), with RKDevTool or `rkdeveloptool`: `db <rk3576
   loader>`, then `wl 0 mmcblk0.img`. This is the only path that works if the
   loader at sector 64 is damaged. The RK3568 loaders that ship with RKDevTool
   don't work on this chip. Use the RK3576 USB loader below.

### RK3576 maskrom USB loader

`tools/maskrom/mk-usb-loader.py` builds the loader that `db` / RKDevTool's
"Download Boot" sends, from Rockchip's `rkbin`:

```sh
mk-usb-loader.py 3576 rkbin/bin/rk35/rk3576_ddr_lp4_2112MHz_lp5_2736MHz_v1.13.bin                       rkbin/bin/rk35/rk3576_usbplug_v1.04.bin rk3576_usb_loader.bin
```

- Its 471/472 entries are byte-identical to `boot_merger` 1.38's output for
  `RKBOOT/RK3576MINIALL.ini` (rkbin `3e288fe8`). It also rebuilds the
  `UsbHead` of both RK3568 loaders that ship with RKDevTool exactly.
- It has **no flash entries**, so it can only be loaded into RAM. No tool can
  use it to write a loader to sector 64.
- No vendor binary is committed. The script takes the two rkbin files as
  input.
- Tested 2026-11-16 in RKDevTool v2.96: Advanced Function, Boot = this file,
  then Download, Read Flash ID, Read Flash Info. Read only, nothing written.

SPI clips and a CH341A don't help: the board has no SPI flash.

## Full restore through maskrom (tested 2026-11-16)

This restores the whole eMMC (MBR, loader, U-Boot, p1, p2) from the PC
with nothing on the device working except the boot ROM.

1. Use the USB-A to USB-C cable. Hold **Volume Down** and press power. RKDevTool
   shows "Found One MASKROM Device".
2. **Advanced Function** tab: set Boot to the RK3576 USB loader (below), then
   click **Download**. The status bar keeps saying MASKROM, because the
   usbplug reports the same USB ID. If Read Flash Info works, the usbplug is
   running.
3. **Download Image** tab: untick every row, **especially Loader**. Add one
   item: Address `0x00000000`, Path `mmcblk0.img` (the raw image). Tick only
   that row, tick **Write by Address**, and click **Run**. RKDevTool accepted
   this from the maskrom state without a Loader row.
4. It takes about 10 to 15 minutes for 15.6 GB, then RKDevTool resets the 350H Ultra.
   Usbplug addresses are absolute: `0x0` is sector 0, with no `0x2000` offset
   (that offset only applies to U-Boot's rockusb mode).

How it was verified: the rescue card was in the slot when RKDevTool reset the
350H Ultra, so it booted from the card and the eMMC stayed unmounted. Then
`dd if=/dev/mmcblk1 bs=4M | md5sum` gave `7212628781e28398546546f4ed634ae8`,
the backup's md5. Then stock booted from the eMMC with the card out.

With USB plugged in, powering off turns into a boot. To swap cards, unplug
USB, shut down, pull the card, then power on.

## Recovery modes (tested 2026-11-16)

Use a **USB-A to USB-C** cable to the PC. With a C-to-C cable, the 350H Ultra showed
"USB mode" but Windows never saw it, because U-Boot doesn't negotiate USB-C
roles. To leave any of these modes, **long-press power**: the 350H Ultra reboots,
and the LEDs flash a pattern.

| Hold at power-on | Mode | What the PC sees | Tested |
|---|---|---|---|
| **Menu + Home** | GKD's U-Boot USB mass storage (`ums 0 mmc 0:0`). The screen says "USB mode, long press power to exit". | `2207:0010` "Linux UMS disk 0", 15,634,268,160 bytes: the whole eMMC user area. Windows mounts p1 (`EMUELEC`). | Read: all six `/flash` files matched the c8ed06c fingerprint, at about 32 MB/s. Raw read and write need an administrator. Not written. |
| **Volume Down** | **Maskrom** (boot ROM download). Black screen. | `2207:350E` "Rockusb Device". RKDevTool reports "Found One MASKROM Device". | **Full restore tested.** The loader was downloaded to RAM, flash info read (Total Sector `0x1d1f000`, the whole eMMC), and the entire 15.6 GB image written from sector 0. Read back from the rescue card, the whole eMMC's md5 matched the backup exactly. Stock then booted. |
| none, rescue card in the slot | the rescue card (see above) | none | Booted, read, restore write. |

Notes:

- Menu + Home is read by U-Boot. It's hard-coded in GKD's board file
  (`evb_rk3576.c`, which prints `MENU_KEY`, `HOME_KEY`, `ums 0 mmc 0:0`), so
  USB disk mode needs a working U-Boot, from the eMMC or from the card's copy
  of the FIT.
- Volume Down went **straight to maskrom**, not to U-Boot's rockusb loader
  mode. (Inferred) it is wired to the RK3576's boot-mode/maskrom input, which
  the boot ROM checks before loading anything, so it should work even with a
  damaged eMMC loader. Untested; that would mean breaking the loader. U-Boot's
  own download key is the ADC key its device tree labels "volume up", which
  should give loader mode (rockusb) instead. Holding Volume Up hasn't been
  tried.
- With the loader at sector 64 erased or invalid, the boot ROM falls back to
  the SD card, and with no bootable card it goes to maskrom by itself. If
  Volume Down is the hardware maskrom input (above), it also covers a loader
  that is valid but hangs.
- U-Boot also has a display menu ("Boot Mode Selection": built-in panel or
  USB-C output), navigated with Up/Down/A. It isn't a recovery mode.
- Windows can write to the FAT p1 while it's mounted in USB disk mode. The
  `System Volume Information` folder in stock's p1, dated 2026-01-06, is from
  the factory image. Eject p1 with "Safely Remove Hardware" before leaving
  USB mode.
