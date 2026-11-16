# First spruce handoff (2026-11-16, BasedOS 0.0.1 `61371a3`, spruce 4.6.1-20261113)

## BasedOS side (worked)

- The card was hot-inserted while BasedOS was running. `mount-frontend` mounted
  `/dev/mmcblk1p1` (vfat) on `/mnt/SDCARD` at 187.60 s, and `frontend-session`
  exec'd `spruce/scripts/runtime.sh` at 187.87 s.

## spruce side (from `Saves/spruce/spruce.log` on the card)

- Platform detection picked `AnbernicXX640480`, the default of the H700 branch.
  The GKD's A53 cores report part `0xd03`, the case for unknown targets.
- Firstboot ran ("Installing spruce 4.6.1") and completed. It found nothing to
  extract, because PortMaster and the themes were current. "Realtime message
  listener never appeared after 15s."
- Main loop: `principal.sh` restarted about 5 times a second. PyUI never wrote
  a log, so it exits before Python starts or fails to launch at all. Each pass
  logs "Missing post_pyui_exit function".
- Each pass ran H700's `set_performance`: "Setting cores online: 0123", "CPU
  Mode now locked to PERFORMANCE: 0123 @ 1512000". On the GKD that takes the
  four A72 cores (4 to 7) **offline**. ZRAM was enabled (1 GB).
- Result: the screen went black (no PyUI), and the device stopped answering on
  the network (SSH timed out, pings were lost) until a forced power-off.
  (Inferred) A busy loop on the four A53 cores at a fixed frequency starved
  Wi-Fi and sshd. spruce's network scripts weren't checked.

## What the spruce platform needs (input for the spruce repo)

1. Detection before the CPU-ID case: `BASEOS_TARGET=gkd350hultra` in
   `/etc/baseos-release` gives a GKD platform, following the existing
   `SPRUCE_BASEOS` pattern. `baseos_repo()` gets a mapping for it.
2. CPU control for the 4+4 RK3576S (policy0 cpus 0 to 3 up to 2016 MHz,
   policy4 cpus 4 to 7 up to 2208 MHz). It must never take cores 4 to 7 offline.
3. PyUI on this display: 1440×1600 portrait panel shown landscape
   (`BASEOS_PANEL_ROTATION_CCW`), libmali GBM/KMS (no sway in BasedOS),
   SDL2 2.32 GLES-only build. Find out why PyUI exits immediately: missing
   Python modules (sdl2, PIL), its 64-bit launcher path, or the display.
4. Input: `gkd_atom_joypad` (event3), plus gpio-keys for volume and the rk805
   power key. See `docs/recon.md`.
5. A guard against tight `principal.sh` loops would help on any platform.
