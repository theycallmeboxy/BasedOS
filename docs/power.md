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

## What spruce does with it: four cores per mode

Every spruce CPU mode runs one cluster and parks the other, as the TrimUI Smart Pro S does (spruce's
8-core big.LITTLE reference: it runs cores 4-7 in every mode, with the other unit offline). Unlike
the Smart Pro S, whose two clusters are the same Cortex-A55, ours differ, so the light modes use
the A53s:

| Mode | Cores | Clocks |
|---|---|---|
| Powersave (the menu's screensaver) | A53s (0-3) | conservative, 408-1416 MHz |
| Smart (the menu, most games) | A53s (0-3) | ondemand, 408-1800 MHz |
| Performance | A72s (4-7) | 2016 MHz |
| Overclock | A72s (4-7) | 2208 MHz |

The values are in the 350H Ultra's cfg, and spruce's own mode functions apply them. The one
override is `cores_online` (below), which also brings the wanted cores up before parking the
others: spruce's single walk over cpu0-7 would reach cpu3 as the last core online when switching
from the A53s to the A72s, and the kernel won't park the last core. Parking either cluster works,
cpu0 included (every interrupt moves to cpu4).

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
maximum). The 350H Ultra's `cores_online` (spruce's plus one step) drops the A72s to 408 MHz before
parking them, and the A53s then scale from 408 again. While the A72s run at 2016, any online A53
sits at 1800 or more for the same reason.

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
The A72s did the same work at lower clocks (DS: about 1.2-1.3 GHz against the A53s' 1.3-1.4). On
PSP the A53s averaged 1.4-1.6 GHz of their 1.8 ceiling in an attract-mode scene; PPSSPP logs no
fps, so their headroom in heavier scenes is not measured.

## Knobs per mode

Each mode sets CPU, GPU and DMC together, through spruce's shared functions:

| Mode | CPU | GPU (Mali-G52, 300-900 MHz) | DMC |
|---|---|---|---|
| Powersave | A53s, conservative 408-1416 | left as it was (spruce's `set_powersave` doesn't touch the GPU; only the Flip overrides it) | powersave (528) |
| Smart | A53s, ondemand 408-1800 (dArkMossCommon's `CPU_SMART_GOVENOR`) | simple_ondemand, cap 900 | dmc_ondemand |
| Performance | A72s, performance 2016 | performance (900) | performance (2112) |
| Overclock | A72s, performance 2208 | performance (900; no higher step) | performance (2112) |

The GPU governors come from dArkMossCommon.cfg and match the Flip's and the Smart Pro S's grouping.

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
| Parking a cluster per mode | cfg core strings and a `cores_online` override | done (above): four cores per mode, as on the Smart Pro S |
| DSperate's threads on the A53s | `DS_PIN` / launch affinity | not needed: 4.7 ms of a 16.7 ms frame |
| Idle sleep (idlemon) input | `set_event_arg_for_idlemon` in the 350H Ultra .sh | done 2026-11-17: the pad's js node (`set_idlemon_to_pad`, as on the H700 BaseOS) |
| Panel brightness | user | the biggest single draw; nothing to change |

## Ideas not tried yet

- A heavy game per mode (PSP, N64, Dreamcast), with and without the DDR at the top.
- Wi-Fi power save (`iw`/`wpa_supplicant` `ps`) when idle in the menu.
- The deep-sleep draw (above).
