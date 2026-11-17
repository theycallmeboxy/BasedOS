# spruce on the GKD 350H Ultra

spruce support for the GKD lives in the spruce fork, https://github.com/theycallmeboxy/spruceOS,
branch `gkd350h-ultra`, until it is merged upstream. It is a normal spruce platform
(`PLATFORM=GKD350HUltra`, family `basedos`), detected from BasedOS's `/etc/baseos-release`.

## Getting it on a card

Build the kit: `python tools/spruce-kit.py <spruce repo> out/spruce-kit`. It makes:

- `spruce-<version>-gkd350hultra-<commit>-overlay.zip`: the changed files. Unzip over a spruce
  nightly at the root of the card.
- `...-patches/`: the same change as `git format-patch` output, for applying to a spruce checkout.
- `...-RELEASE-NOTES.md`: which spruce nightly it is built for, how to install, what changed.

Use the nightly built from the commit named in the notes, or later. Re-apply the overlay after a
spruce update.

## Status (2026-11-16)

| Area | State |
|---|---|
| Detection, platform files | done |
| PyUI menu (1600x1440, rotated) | works |
| Buttons, stick, volume rocker | work (codes measured) |
| Audio (UI sounds, volume) | works (DAC "Digital" control) |
| Sleep / wake / shutdown after sleep | works (deep sleep, RTC wake) |
| Clean shutdown from spruce | strict stage 2 plus session shield, as on the H700 BaseOS |
| SSH (spruce's), Samba user | spruce login added |
| CPU modes | powersave on the A53 cluster only; smart and performance on all 8 cores |
| RetroArch | works: games run upright and full screen through spruce's launcher (NES `fceumm`, PS `pcsx_rearmed`). The pad goes through `linuxraw` (`/dev/input/js0`), since the `udev` driver needs udevd. Every button, the stick and the hotkeys (Select + B/R/L/Left/Right/R2/X/Y) checked in PadTest. L3 bound but not tested |
| Wi-Fi | BasedOS manages it; spruce's switch takes the link up/down; networks added in spruce are saved to the card but not yet joined |
| Bluetooth | not brought up on BasedOS |
| PPSSPP, DraStic, Mupen64Plus, Flycast, YabaSanshiro, ScummVM, DSperate | not set up for this platform yet (see below) |
| Emulator lists (`Emu/*/config.json`) | `BASEDOS` is listed wherever the choice is a RetroArch core (next to `OAKMOSS_A133P`); Dreamcast and N64 now show. On the unit, spruce's launcher resolves each to its RetroArch core; PS played (PadTest), the rest need games on the card. Standalone-default systems (PSP, NDS, NDSI, ScummVM, 3DS, J2ME, CoCo, Ports) and Media left out |
| 32-bit RetroArch and cores | not available (BasedOS has only the aarch64 loader) |

## Still to do for spruce's onboarding checklist (CONTRIBUTING.md)

- `Emu/PSP/default_configs/SYSTEM/ppsspp-GKD350HUltra.ini` and `controls-GKD350HUltra.ini`;
  check the `PPSSPPSDL_dArkMoss3326` build runs on BasedOS.
- DraStic: `run_drastic_GKD350HUltra` (the launcher dispatches by family, and `basedos` has no
  case), `Emu/NDS/config/drastic-GKD350HUltra.cfg` and its `.bak`, and screen rotation.
- Mupen64Plus `MUPEN_PAD_TABLE` and `InputAutoCfg-<table>.ini`; Flycast `FLYCAST_PAD_MAP`;
  YabaSanshiro `SATURN_PAD_TABLE` and keymap; ScummVM target and ini; DSperate wiring.
- Device lists in `Emu/*/config.json` for the standalone emulators, once each runs on BasedOS.
  NDS shows on every device and defaults to DSperate, which has no `basedos` case yet.
- A PyUI system json of its own (the dArkMoss Pixel 2's is borrowed) and
  `App/ButtonReader/devices/GKD350HUltra.json`.
- Apps with per-family cases: FileManagement, Gallery, PixelReader, Netplay.
- Validation: clean install and upgrade, a game per emulator.
- PS games: spruce's own `PCSX-ReARMed.rmp` remap (every device) makes port 1 a digital pad and
  drives the D-pad from the left stick; set a DualShock per game for analog. Not a GKD issue.
