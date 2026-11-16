# Power

Measured on the unit, 2026-11-16, on battery, with the frontend stopped (maintenance mode) and the
panel on. Tools: `tools/dev/power-probe.sh` and `tools/dev/cluster-probe.py`, which read
`/sys/class/power_supply/battery/current_now` and `voltage_now` once a second.

## Idle

| Configuration | Draw |
|---|---|
| all 8 cores online | 905 to 928 mW |
| A53 cluster only (cpus 4-7 offline) | 904 to 917 mW |

At idle the CPU configuration makes no measurable difference: the panel and the rest of the board
dominate (about 240 mA at 3.8 V).

## Under load: A53 vs A72

One busy thread pinned to one core, both clusters capped at 1416 MHz (spruce's powersave cap):

| Core | Power over idle | Work rate | Energy per unit of work |
|---|---|---|---|
| A53 (cpu0) | +17 mW | 1.64 M loops/s | 10 mJ |
| A72 (cpu4) | +158 mW | 3.03 M loops/s | 52 mJ |

The A72 is about 1.85x faster at the same clock and costs about 9x the extra power: the A53s do
the same work for about a fifth of the energy. (A Python busy loop on one core; real emulators
are memory-heavier, so take the ratio as a direction, not a constant.)

## What spruce does with it (and the Wi-Fi catch)

The A53-only powersave this suggests was tried and **reverted**: with cpus 4-7 offline the unit
dropped off the network, three separate times (spruce running as an H700 with cores "0123", the
power probe's A53-only runs, and the menu in A53-only powersave). The likely cause is the Broadcom
driver: its worker thread or the SDIO interrupt is tied to a big core. Not verified yet. So every
mode keeps all eight cores online for now.

To pick it up again:
1. With the A72s online, record `grep -E "dhd|mmc2" /proc/interrupts` and the CPU affinity of the
   `dhd_dpc` / `dhd_rxf` threads (`/proc/<pid>/status`, `Cpus_allowed_list`).
2. Take one A72 offline at a time and see which one drops Wi-Fi.
3. If it's affinity, pin the IRQ and threads to an A53 at boot (BasedOS `network` script), then
   retry A53-only powersave.

## Sleep

Deep sleep (suspend to RAM) is used; see `recon.md` for the evidence and the RTC wake details.
The deep-sleep draw itself hasn't been measured yet: that needs a long sleep and a before/after
battery reading, or a USB power meter.

## Ideas not tried yet

- The GPU (300 to 900 MHz) and DDR (528 to 2112 MHz) governors in powersave. spruce sets GPU
  limits per mode (`GPU_*` in the cfg); the DMC is left to the kernel's `dmc_ondemand`.
- Panel brightness is the biggest single idle draw; nothing to change there beyond the user's level.
- Wi-Fi power save (`iw`/`wpa_supplicant` `ps`) when idle in the menu.
