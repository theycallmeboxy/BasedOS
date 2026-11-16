# Boot time

Measured on the unit, 2026-11-16 (BasedOS b8121f5 plus the loglevel change, spruce nightly
4.6.1-20261115 with the GKD platform). The kernel's printk clock starts before Linux, so its
"Booting Linux" line shows how long the boot ROM, SPL, TF-A and U-Boot took.

| Stage | Time | Where it goes |
|---|---|---|
| Power to kernel | about 1.45 s | SPL (DDR init), TF-A, OP-TEE, U-Boot (logo, boot.scr, loading Image, DTB and initrd) |
| Kernel to `/basedos/init` | about 1.57 s | driver probes. The biggest single item is the **RAID6 benchmark (0.46 s)**, then the display pipeline (VOP2 and DSI, about 0.2 s) and SD/SDIO bus setup |
| initrd to `rcS` | under 0.1 s | mounts p1, loop-mounts the squashfs, `switch_root` |
| `rcS` to frontend | about 0.1 s | the card is mounted first, and Wi-Fi and SSH are backgrounded |
| spruce to the PyUI first frame | about 2 s | `runtime.sh`, `device_init`, Python start-up and imports |
| **Power to menu** | **about 5 s** | |
| Wi-Fi lease | 5 to 9 s, in the background | association plus DHCP |

## What was tried

- **`loglevel=4` instead of stock's `loglevel=7`**: `loglevel=7` sends every boot message to the
  serial and framebuffer consoles as it is printed. Kernel time went from 1.590 s to 1.572 s, so
  the console was not the bottleneck. BasedOS keeps `loglevel=4` anyway, because it also keeps
  kernel chatter off the screen. Warnings and worse are still shown.

## What would need a kernel rebuild

The stock kernel is used as it is (no source for GKD's build), so these wait for a BasedOS kernel:

- `CONFIG_RAID6_PQ_BENCHMARK=n` (or no btrfs/RAID6 at all): saves about 0.46 s.
- Making Wi-Fi (`bcmdhd`) probe asynchronously, and trimming drivers the device doesn't have.

## Where else to look

- **PyUI start-up (about 2 s)** is the largest share left, and it is spruce's. A Python and SDL2
  built for this base (see the plan's "optimized frontend runtime") is the lever.
- U-Boot's share is fixed unless BasedOS ships its own U-Boot, which is a red line for now.
