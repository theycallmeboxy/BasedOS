# Known port issues

PortMaster ports that misbehave on the 350H Ultra (BasedOS + spruce), what causes it and whose fix it
is. Problems in BasedOS or the spruce fork get fixed there and move to "Fixed on our side"; the
open ones are in the port, its package or PortMaster's runtimes, for their authors.

What ports load from the system in general, and which libraries are still missing: see
[portmaster-libs.md](portmaster-libs.md).

## Open

| Port | On the 350H Ultra | Cause | Fix belongs to | Since |
|---|---|---|---|---|
| Alex the Allegator 4 (Weston pack) | runs, sound and pad fine; the picture tears | The game `stretch_blit`s each frame straight onto Allegro's screen, and Allegro 4's X11 driver sends every line written there to X as it goes: one `XShmPutImage` of 1600x1 per scanline, about 1,200 a frame (gdb, 2026-11-23). Xwayland passes the damage to Weston whenever it gets to it, so Weston composites half-updated frames. Also most of the game's 20% CPU and Weston's 16%. Everything after Weston shows whole frames (Crusty draws Weston's output straight into SDL's surface; BasedOS's rotation waits for the GPU) | the port (`github.com/Cebion/alex4`): stretch into a memory bitmap, then one `blit` to the screen | 2026-11-23 |
| Sulka (32-bit, GameMaker) | doesn't start | its gmloader needs `libcrypto.so.1.1` (OpenSSL 1.1), which the other 32-bit GameMaker ports carry in their own `libs/` and Sulka's package doesn't (PortMaster-New `ports/sulka` has only `libzip.so.5`); no system here has a 32-bit OpenSSL 1.1 ([lib32.md](lib32.md)) | the port's package | 2026-11-19 |
| Meritous | loads every library, then aborts with "buffer overflow detected" | in the game itself; not looked into | not known yet | 2026-11-19 |
| Weston pack ports (Crusty) | run; two traps for whoever changes the setup | (1) Crusty tells its own SDL calls from the program's by only the first memory range of the SDL library; with PortMaster's own libSDL2 that range isn't code, so Crusty faked SDL's display too and recursed until out of files. The spruce fork's `run_basedos_port` sets `CRUSTY_LIBSDL` to BasedOS's SDL2, whose code comes first. (2) Crusty never replaces its `/tmp/CRUSTY_LIBSDL64.so` link once made: a changed `CRUSTY_LIBSDL` takes a reboot | Westonpack's author | 2026-11-19 |

## Fixed on our side

| Port | Was | Fix |
|---|---|---|
| A7Xpg | didn't start, then only black | FLAC 1.3's `libFLAC.so.8` (BasedOS's `flac13` package), and SDL2 patch 0007: the game sets its video mode every frame, and SDL recreated its surfaces each time, discarding the frame (BasedOS 30c1689, 2026-11-23) |
| Apotris | silent, crashed when a game or the title demo started | the `libSDL2.so` development link, which its audio library (SoLoud) loads by name (BasedOS 2e6656d, 2026-11-23) |
| Weston ports | wouldn't start or spun forever | the unversioned `libudev.so`, `CRUSTY_LIBSDL`, and udev's database for libinput while a Weston port runs (`basedos-udev`), 2026-11-19 ([spruce-on-gkd.md](spruce-on-gkd.md)) |
| Weston ports, quitting | the game could be left running after Select+Start | `run_basedos_port` ends what's left of the port's process group 3 s after it and unmounts the pack (spruce fork, 2026-11-19) |
| Meritous, Apricots | missing `libgmodule`, then `libbsd` | added to BasedOS ([portmaster-libs.md](portmaster-libs.md), 2026-11-19) |
