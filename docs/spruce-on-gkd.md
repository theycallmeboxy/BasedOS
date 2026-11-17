# spruce on the GKD 350H Ultra

spruce support for the GKD 350H Ultra lives in the spruce fork, https://github.com/theycallmeboxy/spruceOS,
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

## Status (2026-11-17)

| Area | State |
|---|---|
| Detection, platform files | done |
| Display rotation | as on dArkMoss's rotated panels: BasedOS's SDL2 turns the DSI panel with the RGA (ArkOS's Miniloong patch, ROT_270), so SDL apps see 1600x1440 at 0 and the cfg has `DISPLAY_ROTATION="0"`. Vulkan windows aren't turned (as on the Miniloong). Checked: the menu, spruce's message screens (`display_text.elf`), RetroArch, DSperate, PPSSPP |
| PyUI menu (1600x1440) | works; PyUI has its own SDL2 and turns itself (`SCREEN_ROTATION="270"`, as the H700 cfg sets it) |
| Buttons, stick, volume rocker | work (codes measured) |
| Audio (UI sounds, volume) | works (DAC "Digital" control). Games starting at another volume (reported 2026-11-17) didn't show in the log: the level was 0 from boot to the game, and every change after went through `set_volume` |
| Sleep / wake / shutdown after sleep | works (deep sleep, RTC wake) |
| Clean shutdown from spruce | strict stage 2 plus session shield, as on the H700 BaseOS |
| SSH (spruce's), Samba user | spruce login added |
| CPU modes | the A72s in every mode, the A53s parked, as on the TrimUI Smart Pro S: Powersave 408-1416, Smart 408-1800, Performance 2016, Overclock 2208, all through spruce's shared functions (see power.md) |
| RetroArch | works: games run upright (`video_rotation = "0"`, it draws through the rotating SDL) and full screen through spruce's launcher (NES `fceumm`, PS `pcsx_rearmed`). The pad goes through `linuxraw` (`/dev/input/js0`), since the `udev` driver needs udevd. Every button, the stick and the hotkeys (Select + B/R/L/Left/Right/R2/X/Y) checked in PadTest. L3 bound but not tested |
| Wi-Fi | BasedOS manages it; spruce's switch takes the link up/down; networks added in spruce are saved to the card but not yet joined |
| Bluetooth | not brought up on BasedOS |
| NDS (DSperate, spruce's default) | works: Castlevania DoS at 59 fps in Smart, upright. DSperate's KMS sink needs the window to be a panel mode, which the turned SDL isn't, and its next choice (the window surface) scales 1600x1440 on the CPU: 52-54 fps in Smart. The cfg's `DS_SCANLINE_SCALE=0` (DSperate's own switch) picks its SDL renderer instead (GLES, emu 5.3 ms, GPU 7%). Reported upstream (beebono/DSperate). DSperate pins itself to cores 0-3 (the A53s). Controls checked on the unit; X/Y needed the cfg's `SDL_GAMECONTROLLER_MAP` (SDL had guessed them swapped). Smart mode holds 59 fps too (about 2.7 W against Performance's 3.1 W) |
| PSP (PPSSPP, spruce's default) | works: Burnout Legends upright on OpenGL (`PPSSPPSDL_dArkMoss3326`; the 3566 build needs ARMv8.2), with the E5 Plus's config, the H700 controls layout and the positional pad map (`ppsspp_functions.sh`). Controls checked on the unit. Vulkan would need PPSSPP built with ArkOS's Vulkan rotation patch |
| DraStic, Mupen64Plus, Flycast, YabaSanshiro, ScummVM | not set up for this platform yet (see below) |
| USB Storage Mode's card-less screen (`shutdown_ui.sh`) | not tried; its `display_text.elf` runs with the rootfs's libraries only once the card is unmounted, and BasedOS has no `libSDL2_image`/`libSDL2_ttf`, so it won't start yet (spruce's other message screens use the card's copies and work) |
| Emulator lists (`Emu/*/config.json`) | `BASEDOS` is listed wherever the choice is a RetroArch core (next to `OAKMOSS_A133P`); Dreamcast and N64 now show. On the unit, spruce's launcher resolves each to its RetroArch core; PS played (PadTest), the rest need games on the card. PSP is listed too. Other standalone-default systems (NDSI, ScummVM, 3DS, J2ME, CoCo, Ports) and Media left out |
| 32-bit RetroArch and cores | not available (BasedOS has only the aarch64 loader) |

## Still to do for spruce's onboarding checklist (CONTRIBUTING.md)

- DraStic: `run_drastic_GKD350HUltra` (the launcher dispatches by family, and `basedos` has no
  case), `Emu/NDS/config/drastic-GKD350HUltra.cfg` and its `.bak`, and screen rotation.
- Mupen64Plus `MUPEN_PAD_TABLE` and `InputAutoCfg-<table>.ini`; Flycast `FLYCAST_PAD_MAP`;
  YabaSanshiro `SATURN_PAD_TABLE` and keymap; ScummVM target and ini.
- Device lists in `Emu/*/config.json` for the standalone emulators, once each runs on BasedOS.
- A PyUI system json of its own (the dArkMoss Pixel 2's is borrowed) and
  `App/ButtonReader/devices/GKD350HUltra.json`.
- Apps with per-family cases: FileManagement, Gallery, PixelReader, Netplay.
- Validation: clean install and upgrade, a game per emulator.
- PS games: spruce's own `PCSX-ReARMed.rmp` remap (every device) makes port 1 a digital pad and
  drives the D-pad from the left stick; set a DualShock per game for analog. Not specific to the 350H Ultra.
