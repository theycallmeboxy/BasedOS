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

## What spruce does with it: the A72s in every mode

Every spruce CPU mode runs the A72s and keeps the A53s parked, as the TrimUI Smart Pro S does
(spruce's 8-core big.LITTLE reference: it runs cores 4-7 everywhere, menu included, with the other
unit offline). The A53s would do the light modes for slightly less energy (see the A/B below), not
enough to justify a second cluster in the modes:

| Mode | Cores | Clocks |
|---|---|---|
| Powersave (the menu's screensaver) | A72s (4-7) | conservative, 408-1416 MHz: every A72 step from 408 to 1416 runs at the 712.5 mV floor (the kernel's energy model marks 600, 816 and 1200 inefficient), so 1416 is the fastest clock at the lowest voltage |
| Smart (the menu, most games) | A72s (4-7) | conservative, 408-2016 MHz (Performance's top, as on the Smart Pro S), spruce's Smart tuning |
| Performance | A72s (4-7) | 2016 MHz |
| Overclock | A72s (4-7) | 2208 MHz |

The values are in the 350H Ultra's cfg, and spruce's own mode functions apply them, with no
350H Ultra overrides. `set_smart` sets `conservative` on cpu4's policy (dArkMossCommon's
`CPU_SMART_GOVENOR` only reaches cpu0's), and the cfg points `CONSERVATIVE_POLICY_DIR` at
`policy4/conservative` so spruce's thresholds land on the A72s. cpu0 is parked too: every
interrupt moves to cpu4, and spruce's writes to cpu0's cpufreq fail harmlessly. Checked after a
reboot: boot ends in Smart on 4-7.

**The clock ceiling.** The chip is an RK3576S. Rockchip's cpufreq driver
(`rk3576_cpu_get_soc_info`) gives an RK3576S the S table (A72 2112, A53 1920 MHz) only when its
`test_version` fuse is 0; otherwise it uses the standard RK3576 table and logs `bin=0 (3)`, as
this unit does at boot. So 2208 (A72) and 2016 (A53) are the top of the table the vendor's driver
picks for this chip. There's no fan: the little-core thermal zone trips at 75 and 85 C, and how
long Overclock holds 2208 under a heavy game hasn't been measured yet.

**The shared CCI.** The CPU OPP tables carry `rockchip,opp-shared-cci`: the clusters share the
interconnect, and the driver holds the A53 policy's minimum at the level the A72s last asked for.
Parked while at 2016 MHz, the A72s left the A53s unable to go below 1800 MHz until a reboot
(writes to `scaling_min_freq` return 0 and change nothing; the shown minimum just follows the
maximum); parked from 408 MHz they didn't. With the A72s in every mode they are never parked, so
this no longer comes up. Anything that runs the A53s again would need to drop the A72s to 408
before parking them.

**Wi-Fi.** Parking does not affect Wi-Fi (2026-11-16): A72s off 4 min idle with the A53s at
408 MHz, the A53s (cpu0 too) off 30 s, and 15 min idle in the menu in Smart (266 of 273 pings
answered, no outage over 10 s). Wi-Fi dropped three times in earlier idle tests; the cause is
unknown and hasn't come back.

## The low-power presets: A53s or A72s turned down? (2026-11-17)

`tools/dev/lowpower-ab.sh` runs each configuration in turn, on battery, two rounds in alternating
order, 25 s each, with PyUI's CPU-mode command moved aside so the screensaver can't switch modes
mid-run. Backlight raw 25 (low), BasedOS d4a2a34, DMC as each preset sets it.

| Workload | A53s (ondemand 408-1800) | A72s (ondemand 408-1800) | A72s, Smart Pro S style (conservative 1008-2016) |
|---|---|---|---|
| Menu idle, Smart | 1019 / 1023 mW | 1031 / 1032 mW | 1043 / 1041 mW |
| Menu idle, Powersave (conservative 408-1416) | 1021 / 1012 mW | 1033 / 1022 mW | |
| DS (Castlevania DoS), Smart | 1293 / 1275 mW, 59.1 fps | 1333 / 1333 mW, 59.1 fps | 1328 / 1327 mW, 59.1 fps |
| PSP (Burnout Legends attract mode), Smart | 1332 / 1317 mW | 1355 / 1353 mW | 1339 / 1339 mW |

The A53s save 10-20 mW in the menu (1-2%), about 45 mW on DS (3.5%) and 20-35 mW on PSP (2%): the
panel and the rest of the board dominate, and at a brighter backlight the share is smaller still.
On the 5000 mAh battery (about 18.5 Wh at 3.7 V) that's about 12 minutes of a full charge in the
menu, 18 on PSP and 32 on DS at this backlight; at full brightness (about 1.5 W more for the
panel) DS is about 6.6 h against 6.5. For the same work the A72s used more energy even at lower
clocks: DS's draw above the menu was about 263 mW on the A53s and 301 mW on the A72s (14% more),
PSP's 304 against 322 mW (6%). Decision: the A72s in every mode (above).
The A72s did the same work at lower clocks (DS: about 1.2-1.3 GHz against the A53s' 1.3-1.4). On
PSP the A53s averaged 1.4-1.6 GHz of their 1.8 ceiling in an attract-mode scene; PPSSPP logs no
fps, so their headroom in heavier scenes is not measured.

## Knobs per mode

Each mode sets CPU, GPU and DMC together, through spruce's shared functions:

| Mode | CPU | GPU (Mali-G52, 300-900 MHz) | DMC |
|---|---|---|---|
| Powersave | A72s, conservative 408-1416 | left as it was (spruce's `set_powersave` doesn't touch the GPU; only the Flip overrides it) | powersave (528) |
| Smart | A72s, conservative 408-2016 | simple_ondemand, cap 900 | dmc_ondemand |
| Performance | A72s, performance 2016 | performance (900) | performance (2112) |
| Overclock | A72s, performance 2208 | performance (900; no higher step) | performance (2112) |

The GPU governors come from dArkMossCommon.cfg and match the Flip's and the Smart Pro S's grouping.

## A72 clock steps, 1800 to 2304 MHz (2026-11-17)

**Heat in a real game.** Sega Rally Championship (YabaSanshiro, attract mode, about 1.25 A72 cores
busy) in Overclock at 2208 MHz for 40 minutes: no throttling, temperatures levelled off at about
47 C (peak 48; the little-core zone's passive trips are at 75 and 85 C, the big-core zone has only
the 115 C critical trip), about 2.28 W, 59 fps. In Performance (2016) on the warm device: about
2.22 W and 1-2 C cooler, same fps. `tools/dev/thermal-log.sh` logs it.

**Steps past the table.** `tools/oc/add-a72-steps.py` adds two A72 steps to a decompiled copy of
the handheld DTB (`rk3576-gkd-atom.dtb`): 2112 MHz, the A72 top of Rockchip's own RK3576S table,
with that row's voltages, and 2304 MHz at each level's 2208 voltage plus 37.5 mV (925 mV here,
GammaOS's voltage for 2304 on the RG Vita Pro's RK3576). The firmware (BL31 v1.20) accepts 2112;
for 2304 it keeps reporting 2208 (`scmi_armclkb` in `clk_summary`), but at 925 mV the A72s run
4.4% faster than at 2208, as 2304 would (sha256 timing), presumably the PVTPLL running faster at
the higher voltage. The test DTB was removed again after the sweep: Overclock stays at 2208, the top of the table
Rockchip's driver picks for this chip. BasedOS boots stock's DTB with only the panel timing set (below), so stock's OPP tables stand.

**Panel refresh.** Stock's DTB asks for a 172.26 MHz pixel clock, which the VOP can't make: `dclk_vp0`
comes from GPLL (1188 MHz) through an integer divider and gets 1188/7 = 169.714 MHz (`real_dclk` in
`/sys/kernel/debug/dri/0/summary`), so the panel ran at 59.11 Hz. Anything that paces itself on vsync ran
1.2-1.5% slow: DraStic at 98.1-98.5% with its sound running dry (crackle). BasedOS's boot script asks for
169.715 MHz (the kernel rounds the mode to kHz and the clock framework takes the closest rate at or
below it, so 169.714 MHz would fall to 1188/8 = 148.5) and trims the horizontal front porch from 150
to 124, which keeps each line at the length the panel's own mode gives it: 169.714 MHz / (1714 x 1650)
= 60.01 Hz, DraStic at 100.0%. Same pixel clock as before, so the same power. Since 2026-11-20 the
boot script sets the two values on the loaded DTB (`fdt set`, `initrd/boot.cmd`); before, it booted
a patched copy (`mkboot.py dtb`). Stock's files stay as they were.

**Cost per step.** `tools/dev/clock-sweep.sh`: all four A72s saturated with sha256, on battery,
20 s per step, two rounds in opposite order (averages below). CPU power is the total minus the
1.11 W the device drew unloaded at the end; backlight raw 25.

| A72 MHz | mV | Total draw | Throughput | CPU power | CPU energy per MiB | Big core |
|---|---|---|---|---|---|---|
| 1800 | 762.5 | 2.53 W | 288 MiB/s | 1.41 W | 4.9 mJ | ~47 C |
| 2016 | 825 | 2.94 W | 316 MiB/s | 1.83 W | 5.8 mJ | ~50 C |
| 2112 | 862.5 | 3.30 W | 332 MiB/s | 2.19 W | 6.6 mJ | ~52 C |
| 2208 | 887.5 | 3.50 W | 346 MiB/s | 2.38 W | 6.9 mJ | ~53 C |
| 2304 | 925 | 3.93 W | 359 MiB/s | 2.82 W | 7.9 mJ | ~56 C |

From 1800: speed 100 / 110 / 116 / 120 / 125, CPU power 100 / 130 / 155 / 169 / 200, energy per
unit of work 100 / 118 / 134 / 140 / 160. Step by step: 2016 -> 2112 costs +20% CPU power for +5%
speed (the S table's voltage is conservative), 2112 -> 2208 only +9% for +4%, 2208 -> 2304 +18%
for +4%. At full load on the 18.5 Wh battery that's about 7.3 / 6.3 / 5.6 / 5.3 / 4.7 hours; in a
game that doesn't saturate the CPU the difference shrinks to tens of milliwatts (Sega Rally: about
60 mW between 2016 and 2208).

## Sleep

Deep sleep (suspend to RAM) is used; see `recon.md` for the evidence and the RTC wake details.
The deep-sleep draw itself hasn't been measured yet: that needs a long sleep and a before/after
battery reading, or a USB power meter.

## spruce's CPU modes on this board (2026-11-16)

spruce writes one set of governor and frequency values per mode to both clusters
(`cpu_control_functions.sh`: `cpu0` and `cpu4`). Each cluster clamps a request to its own range:
asked for 2208 MHz, the A53s settle at 2016 and the A72s run at 2208 (checked on the unit).

Measured on battery, backlight raw 25 (level 1 of 10: PyUI's screensaver dim, left on because the
games were started from SSH over the screensaver), Castlevania DoS in DSperate (BasedOS 8d85e0b, Vulkan present),
settings applied live, 24 s averages. Performance first and last, 5 mW apart:

| Setup | Draw | DS speed |
|---|---|---|
| spruce Performance (all at 2016, GPU 900, DDR dmc_ondemand) | 1600 mW | 59.1 fps |
| spruce Smart (A53 ondemand, A72 conservative, GPU simple_ondemand) | 1462 mW | 59.1 fps |
| schedutil on both clusters (energy-aware scheduling active) | 1506 mW | 59.1 fps |
| schedutil, A72s capped at 1416 | 1502 mW | 59.1 fps |
| schedutil, DDR held at 528 | 1442 mW | 59.1 fps |

An earlier Performance reading at full backlight (level 10, raw 255) was 3.1 W: the panel
outweighs every CPU setting by far. DS is a light load (one A53 thread at about a third busy), so this ranks the modes'
overhead, not their headroom; a heavy game (PSP, N64, Dreamcast) is still to measure.

What the kernel offers: energy-aware scheduling is on (`sched_energy_aware` 1; capacities A53 442,
A72 1024) but only works under schedutil, which spruce's modes don't use; per-task uclamp; cpuidle
WFI and cpu-sleep on both clusters; no cgroups mounted. Thermal: the little-core zone trips at 75
and 85 °C, the big core at 115 °C. The DMC offers dmc_ondemand, powersave, performance, userspace
at 528/1068/1560/2112 MHz.

## Levers, and what to use

All of these stay inside the 350H Ultra's own files (its cfg and .sh, and BasedOS); spruce's shared code
is not touched.

| Lever | Where | Verdict |
|---|---|---|
| Smart as spruce does it | spruce | keep: lowest of the tested CPU setups on DS |
| schedutil / energy-aware scheduling | would need a 350H Ultra `set_smart` override (as the Miyoo Mini has) | no: costs more than spruce's Smart on DS; revisit with a heavy game |
| A72 at its 2208 MHz top | Overclock's `CPU_OVERCLOCK_MAX_FREQ` | already: Overclock runs the A72s at 2208, Performance at 2016; to measure: thermals with no fan |
| DDR following the mode | spruce's opt-in `DRAM_*` in the 350H Ultra cfg (as the Flip and Miniloong) | done 2026-11-17: powersave (528 MHz) in Powersave, dmc_ondemand in Smart, performance (2112 MHz) in Performance/Overclock, checked on the unit |
| Parking a cluster | cfg core strings | done (above): the A72s in every mode, as on the Smart Pro S |
| DSperate's threads on the A53s | `DS_PIN` / launch affinity | not needed: 4.7 ms of a 16.7 ms frame |
| Idle sleep (idlemon) input | `set_event_arg_for_idlemon` in the 350H Ultra .sh | done 2026-11-17: the pad's js node (`set_idlemon_to_pad`, as on the H700 BaseOS) |
| Panel brightness | user | the biggest single draw; nothing to change |

## To do

- **Align Smart's ceiling with Performance's clock** once the Performance clock is settled
  (2016, or 2112/2208 from the clock sweep). The Smart Pro S sets no `CPU_SMART_MAX_FREQ`, so
  its Smart scales up to its Performance clock; the 350H Ultra caps Smart at 1800 below
  Performance's 2016 (dArkMossCommon's value). Then drop or match `CPU_SMART_MAX_FREQ`.

## Ideas not tried yet

- A heavy game per mode (PSP, N64, Dreamcast), with and without the DDR at the top.
- Wi-Fi power save (`iw`/`wpa_supplicant` `ps`) when idle in the menu.
- The deep-sleep draw (above).
