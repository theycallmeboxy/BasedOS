# Boot time

Measured on the unit, 2026-11-16 (BasedOS b8121f5 plus the loglevel change, spruce nightly
4.6.1-20261115 with the 350H Ultra platform). The kernel's printk clock starts before Linux, so its
"Booting Linux" line shows how long the boot ROM, SPL, TF-A and U-Boot took.

| Stage | Time | Where it goes |
|---|---|---|
| Power to kernel | about 1.45 s | SPL (DDR init), TF-A, OP-TEE, U-Boot (logo, boot.scr, loading Image, DTB and initrd) |
| Kernel to `/basedos/init` | about 1.57 s (about 1.0 s since 2026-11-19, below) | driver probes. The biggest single item was the **RAID6 benchmark (0.51 s)**, then the display pipeline (VOP2 and DSI, about 0.2 s) and SD/SDIO bus setup |
| initrd to `rcS` | under 0.1 s | mounts p1, loop-mounts the squashfs, `switch_root` |
| `rcS` to frontend | about 0.1 s (0.6 s by 2026-11-18 with the boot keys, 0.2 s since 2026-11-19) | the card is mounted first, and the Wi-Fi driver loads in the background |
| spruce to the PyUI first frame | about 2 s | `runtime.sh`, `device_init`, Python start-up and imports |
| **Power to menu** | **about 5 s** (about 4 s since 2026-11-19) | |
| Wi-Fi lease | 5 to 9 s, in the background | association plus DHCP, now spruce's (BasedOS only loads the driver) |

## What was tried

- **`loglevel=4` instead of stock's `loglevel=7`**: `loglevel=7` sends every boot message to the
  serial and framebuffer consoles as it is printed. Kernel time went from 1.590 s to 1.572 s, so
  the console was not the bottleneck. BasedOS went to `loglevel=4` to keep kernel chatter off the
  screen, and since 2026-11-18 to `loglevel=1` with `vt.global_cursor_default=0`: the panel shows
  the boot logo, then BasedOS's boot screen (`basedos-splash`, drawn at the start of `rcS`, with
  the text console unbound from the panel), then the frontend. Every message still reaches the
  kernel log and `/data/basedos.log`.

## 2026-11-19: two boot options, and the boot-key read

`frontend` (the mark taken just before spruce starts) went from 2.96 s of uptime to 1.26-1.42 s
over four boots, and the kernel's `Freeing unused kernel memory` from 3.69 s to 2.49-2.54 s.
BasedOS's boot script (`initrd/boot.cmd`; until 2026-11-20 stock's, rewritten by `mkboot.py
bootscr`) has two options stock's command line doesn't; stock's own boot (the fallback, and
`install-dev.sh revert`) has neither:

- **`initcall_blacklist=raid6_select_algo`**: the stock kernel has btrfs built in, and with it the
  RAID6 library, which benchmarked eight parity routines at every boot (0.51 s;
  `CONFIG_RAID6_PQ_BENCHMARK=y`, no module option to skip it). Only btrfs RAID5/6 and md RAID use
  it, and nothing on this device does; a btrfs RAID6 volume must never be mounted under BasedOS.
- **`rcupdate.rcu_expedited=1`**: closing an input device waits for an RCU grace period
  (`input_close_device`), 21-40 ms on this kernel. Anything that looks at every `/dev/input` node
  paid that per node: the boot-key read (`basedos-keys`, five nodes) took 0.15 s, not the few ms
  measured on a desktop, and spruce's key listeners and SDL at every emulator start pay it too.
  Expedited, an open and close takes under 1 ms (`/sys/kernel/rcu_expedited`, tried at runtime
  first). The kernel's own boot got faster with it as well, by about 0.6 s beyond the RAID6 share.
  The cost is an IPI to each core when something waits for a grace period, rare outside device
  setup.

Checked and not worth it: **`mitigations=off`**. The A53 and A72 are not affected by speculative
store bypass, Spectre v2 is handled in hardware (CSV2), and what is left (`__user` pointer
sanitization) costs next to nothing (`/sys/devices/system/cpu/vulnerabilities`).

Also since 2026-11-19:

- **Reboot and power-off are about 2 s faster** (11.3 s against 13.3 s for a reboot back to an
  address on Wi-Fi): BusyBox init, after `rcK`, signals every process again and pauses 2 s in all
  before rebooting. `rcK` already stopped everything and unmounted the card, so it finishes the
  job itself when it knows which was asked for (`/usr/sbin/poweroff`, which `reboot` and `halt`
  link to, notes it). BusyBox's own `reboot` without the note takes the old path.
- **An update restarts at once**: when `rcS` installed updates, the reboot `basedos-update` asks
  for waited for `rcS` to return, so `rcS` returned as soon as one was installed (installed at
  1.52 s, `rcK` at 1.55 s; before, 10 s later). Since 2026-11-21 `frontend-session` installs them,
  once the card is mounted (`rcS`'s single early try usually came before the card was probed, so
  an update waited for a boot where it wasn't); init acts on the reboot at once there too. Not
  measured again.
- The card is polled every 50 ms for the first 2 s (was 0.5 s), and the clock is set from the RTC
  before `e2fsck` checks `/data`.

## Safeguard cost

The boot-attempt counter (the initrd mounts p2, counts and unmounts) and the maintenance-mode key
check (`evtest --query`, 0.04 s; a Python EVIOCGKEY check took 0.18 s and was replaced; since
2026-11-18 the boot keys are read by `basedos-keys`, every key in one call, a few ms) add about
0.2 s before the frontend starts: `frontend` at 1.88 s of uptime, against 1.65 s without them.
The kernel's own time to `/basedos/init` varies by up to about 0.7 s from boot to boot (2.97 to
3.69 s seen), which is more than all of BasedOS's userspace. (The boot keys' real cost turned out to
be the input nodes' close; see 2026-11-19 above.)

## What would need a kernel rebuild

The stock kernel is used as it is (no source for GKD's build), so these wait for a BasedOS kernel:

- No btrfs/RAID6 at all, instead of skipping its init (done by a boot option since 2026-11-19).
- Making Wi-Fi (`bcmdhd`) probe asynchronously, and trimming drivers the device doesn't have.

## Where else to look

- **PyUI start-up (about 2 s)** is the largest share left, and it is spruce's. A Python and SDL2
  built for this base (see the plan's "optimized frontend runtime") is the lever.
- U-Boot's share is fixed unless BasedOS ships its own U-Boot, which is a red line for now.
