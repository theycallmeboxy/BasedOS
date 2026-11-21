# BasedOS user guide (GKD 350H Ultra)

BasedOS is a small operating system that lives on the 350H Ultra's internal storage (eMMC) and starts
**spruce** from your SD card. Your spruce card stays a normal spruce card: you can move it
between the 350H Ultra and your other spruce devices.

> **Status: early, pre-releases only.** BasedOS is installed next to the stock firmware by
> `basedos-setup` (below), on the device itself. Read "Recovery" before you start.

## What you need

- A GKD 350H Ultra on stock firmware **ROCKNIX 20260613, build `c8ed06c`** (other builds are
  refused: BasedOS runs on your device's own stock kernel, drivers and firmware, in place, and
  checks them).
- Wi-Fi on stock, and a PC with SSH to run setup.
- An SD card you can erase, for the recovery card (recommended; setup says what size).
- A spruce card (FAT32 or exFAT) with spruce plus the 350H Ultra kit (see
  [spruce-on-gkd.md](spruce-on-gkd.md)).

## Setup on the device (basedos-setup)

`basedos-setup.sh` runs on the 350H Ultra itself, under stock, and downloads its release from
GitHub. From a PC, in one go (press Enter at the password prompt: stock's root has none; the
release page has the exact line for each release):

    ssh -t root@<device> "curl -fsSL -o /tmp/basedos-setup.sh <release URL>/basedos-setup.sh && sh /tmp/basedos-setup.sh"

It checks stock's build and files first, states its requirements, asks everything, shows a
numbered summary, asks you to type the confirmations (capitals don't matter), and only then
downloads and writes. Two choices:

1. **Install BasedOS on the built-in storage (eMMC)**, next to stock. It recommends making a
   recovery card first and offers to in the same run (the install happens only once the card is
   made and checked). You type `INSTALL` to confirm you understand the built-in storage is
   modified, know the risks and have a backup.
2. **Make a recovery SD card**: see "Recovery" below. You type `ERASE` to confirm the card.

If setup stops part-way (Ctrl-C, the SSH connection drops), run it again. A card is simply made
again. An install is finished: BasedOS's boot script goes in last, so until then stock still
starts, and setup recognises the unfinished install and replaces it.

## Install (developer install, next to stock)

1. Prepare your stock files from a backup of your eMMC (recovery.md):
   `python tools/prepare_stock.py <backup>/mmcblk0.img prepared`. The build makes BasedOS's links
   into stock's files against them; nothing of stock's goes into BasedOS.
2. In WSL: build (`tools/wsl/build.sh`; it unpacks your stock image the first time). It writes
   `out/`: the system layer (`rootfs.squashfs`), the initrd, BasedOS's boot script, the recovery
   card's files and an update payload (`.bosupd`).
3. With the 350H Ultra running stock and reachable over SSH, copy `out/` to `/tmp` on the device and run
   `tools/install-dev.sh /tmp/<dir>` there. It adds BasedOS's files to the boot partition (the
   system layer, the initrd), puts BasedOS's boot script in place of stock's (kept), copies your
   Wi-Fi network and SSH keys, and leaves stock's own files untouched.
4. Reboot. BasedOS starts, then spruce from the card.

From stock, while BasedOS is installed, stock's **Ports** has **Uninstall BasedOS** (it asks
first, then removes BasedOS and its settings and leaves stock as it was), and one of:

- **Disable BasedOS**, while BasedOS is on (in stock after "Start stock once", or after setup):
  stock starts from then on, without a restart; BasedOS's files stay. The same as "Disable
  BasedOS" in BasedOS's maintenance menu.
- **Enable BasedOS**, while it's disabled: BasedOS's boot script goes back and the device restarts
  into BasedOS.

(Stock's Ports shows only what's in it; these entries are what make it appear.)

To go back to stock: the maintenance menu (above), or from SSH `basedos-boot stock-once`,
`disable` or `uninstall` (add `--reboot`); `basedos-boot status` says what boots next.
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
| Power on **holding Select** | **maintenance mode**: no spruce; Wi-Fi and SSH, what's in BasedOS's two copies (slots A and B: which build, which runs, which boots next), and a menu (Up/Down, A): **Start stock once**; **Boot slot A/B from now on** (the other copy, if it's there and would start; it restarts into it); **Disable BasedOS** (stock boots from then on, and an "Enable BasedOS" entry in stock's Ports turns BasedOS back on); **Uninstall BasedOS** (removes its files and settings from the device while it restarts, then starts stock; stock is as before the install); Restart; Power off. Changing slots, disabling and uninstalling want A, B, X, Y tapped in that order (as the recovery card); any other button goes back. The screen shows the address to SSH to once Wi-Fi is up |
| Power on **holding Start** | **stock, for this boot**: BasedOS restarts into stock once; the next power-on is BasedOS again |
| Power on **holding another button** | whatever `/data/boot-keys.conf` maps it to (none by default): maintenance mode, stock once, or a frontend on the card other than the first one found. The format and the button names are in `/usr/share/basedos/boot-keys.conf`; copy it to `/data/` to change it. The boot screen labels the mapped buttons: Select's and Start's beside the buttons themselves ("Maintenance", "Boot Stock OS" by default), any other in a list |
| Hold **Volume Up + Volume Down** together **3 s** | clean shutdown with any frontend, also a hung one: programs get 3 s to save and quit, then the card is synced and unmounted (`basedos-shutdown-keys`). Holding power is the frontend's (spruce: Button Settings > Power button hold time) |
| Tap power (in spruce) | sleep; tap again to wake. spruce's "Shutdown after sleeping" works |
| Pull and reinsert the card | the card is found again; a card that wasn't unmounted cleanly is checked first |

Without a card, BasedOS waits for one and says so on screen. While it waits, the buttons the
boot-key map uses work there too, held for a second: Select for maintenance mode, Start for stock
once (or whatever `/data/boot-keys.conf` maps them to), without restarting first.

## Wi-Fi and SSH

- Wi-Fi is spruce's, as on its other devices: join, forget and switch it off from spruce's menu.
  The networks are saved on the card, so they go wherever the card goes. BasedOS only loads the
  Wi-Fi driver at boot.
- BasedOS's own Wi-Fi is for maintenance mode, and for when the frontend keeps failing: then it
  joins the networks in `/data/wpa_supplicant.conf` on the eMMC. Each time it starts, it first
  adds any network stock has saved that it doesn't have yet (stock's own files are only read): to
  add a network, join it once in stock's Wi-Fi menu (start stock once), and maintenance mode
  knows it from then on. The file can also be edited over SSH.
- SSH: with spruce's "Enable SSH" on, spruce's own SSH answers: user `spruce`, password
  `happygaming`. With it off there is no SSH. In maintenance mode, or when the frontend keeps
  failing, BasedOS's own SSH answers as `root` with **no password**. Use only on a network you
  trust.

## Updates

- Each release on GitHub has its `baseos-gkd350hultra-<version>.bosupd`. Put it at the root of the
  card and restart, or use spruce's firmware update app, which finds one there and restarts for
  you. (The app's download only sees GitHub's latest full release, so while BasedOS has only
  pre-releases, download the `.bosupd` from the release page yourself.) BasedOS
  installs it while starting, as soon as the card is mounted and before spruce starts: the screen
  says so, and it restarts once more into the new version.
- It goes into the copy of BasedOS that isn't running, and is checked before it's used. If the new
  copy doesn't start, BasedOS goes back to the old one after a few tries and stays on it, and
  won't try that update again.
- An update it won't install is renamed on the card, so neither BasedOS nor spruce's updater keeps
  offering it: `.bosupd.skipped` (not newer than the running release, or already installed once),
  `.bosupd.refused` (for another device or stock build, or a newer initrd), `.bosupd.failed` (it didn't verify, or the
  new copy didn't start). Rename one back to `.bosupd` to have it looked at again.
- An update holds only BasedOS's own files, never your device's stock firmware (BasedOS uses
  stock's kernel, its modules, the GPU drivers and the firmware in place). Each BasedOS release is
  made for one stock firmware build; an update for another one is refused. To see what an update
  would do, from SSH: `basedos-update status`.
- An update doesn't carry BasedOS's boot files either: the boot script and the initrd, which
  choose the copy and count failed starts, so going back to the other copy couldn't undo a bad
  one. They come with setup; a change needs a developer update (`tools/dev/update-basedos.sh`)
  for now. An update made for a newer initrd than the device has is refused (`.bosupd.refused`).
- From SSH, `basedos-boot status` lists both copies too, and `basedos-boot slot a` (or `b`)
  boots that one from now on, as the maintenance menu does.

## Safeguards

- **Boot counter**: if BasedOS fails to start three times in a row it boots its other copy (A/B
  slot); after five failures it boots stock. Delete `boot-attempts` in BasedOS's data folder to reset.
  A start that gets as far as BasedOS's own start-up counts as a good one, even when its data
  partition needs a check it can't do by itself.
- **Bad boot files**: if BasedOS's initrd is missing or damaged, the boot script boots stock.
  Updates never change the boot files, so a bad update can always be undone by the other copy.
- **Stock changed**: if stock isn't the build BasedOS was made for (reflashed, say), BasedOS
  doesn't start and stock boots. "Enable BasedOS" in stock's Ports checks this first and says
  so, instead of enabling a BasedOS that wouldn't start.
- **Frontend crash loop**: if spruce exits within 15 s five times in a row, BasedOS stops
  restarting it and shows a message, instead of looping.
- **Card checks**: a card left dirty by a power cut is checked (`fsck`) once before use.
- **Clean shutdown**: BasedOS's own power-off and restart (the volume-key combo, SSH) turn off a
  swap file on the card and release anything loop-mounted from it first, as spruce's own power-off
  does, so the card is left clean.

## Recovery

If anything goes wrong, see [recovery.md](recovery.md). In short, from gentlest to strongest:

1. **Recovery card** (basedos-setup, choice 2): power on with it in; it checks its backup, and
   when you tap A, B, X, Y in that order it puts the built-in storage back as it was when the card
   was made, then checks it. Tapping power powers off without writing. No PC needed. A restore
   from a recovery card was verified byte for byte on a unit (2026-11-20, with the earlier
   hold-A screen).
2. **USB disk mode**: hold **Menu + Home** and power on; the whole eMMC appears on your PC.
3. **Maskrom**: hold **Volume Down** and power on; RKDevTool on a PC can rewrite the whole eMMC
   (tested, including a full restore).

Every SD card, the recovery card included, needs the device's own bootloader (at the start of the
built-in storage) to start: the chip never starts one from a card (tested). If the bootloader
itself is gone, only maskrom and a PC bring the device back; the recovery card carries what that
needs (its `maskrom/` folder: Rockchip's USB loader and the steps, and the backup's own copy of
the bootloader).

## Logs

- BasedOS: `/data/basedos.log` on the eMMC (`basedos-data/basedos.log` seen from stock), about the
  last 256 KB; the part before is in `basedos.log.1`.
- spruce: `Saves/spruce/spruce.log` and `pyui.log` on the card.
