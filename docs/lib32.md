# 32-bit (armhf) programs: /usr/lib32

Why (2026-11-19): about 200 of PortMaster's 1,511 ports have only a 32-bit build, most of them
2024 GameMaker ports on the 32-bit gmloader, some on box86. PortMaster offers them only on a
device where it finds `/usr/lib32` or `/usr/lib/ld-linux-armhf.so.3` (its `device_info.txt`,
`DEVICE_HAS_ARMHF`); BasedOS had neither, so they weren't listed. The kernel (stock's 6.1) runs
AArch32 programs, and stock (ROCKNIX) carries a 32-bit userland in `/usr/lib32`.

BasedOS's own programs stay 64-bit. The 32-bit side is only libraries, for programs that bring
their own binaries.

## Layout

The same as stock's, so ports built for ROCKNIX find what they expect:

| What | Where | From |
|---|---|---|
| glibc's 32-bit loader | `/usr/lib32/ld-linux-armhf.so.3`, linked from `/usr/lib/ld-linux-armhf.so.3` (armhf programs' PT_INTERP is `/lib/ld-linux-armhf.so.3`) | system layer |
| glibc, GCC's runtime, SDL2's add-ons, the libraries of `manifest/base.list` that ports use, OpenAL, mpg123, libmodplug | `/usr/lib32` | system layer: BasedOS's 32-bit Buildroot root (`buildroot/configs/basedos_gkd350hultra_armhf_defconfig`), the paths `manifest/base32.list` names plus what they need |
| SDL2 and librga | `/usr/lib32` | system layer: BasedOS's own (`SDL2_ARCH=armhf tools/sdl2/build.sh`), the same patches as the 64-bit one, so 32-bit ports get the turned picture too |
| Mali G52 GLES/EGL driver (32-bit) and its GL API wrappers | `/usr/lib32` | vendor layer: stock's `/usr/lib32` (`manifest/harvest.list`) |

The 32-bit loader looks in `/lib`, `/usr/lib` and then `/usr/lib32` (`buildroot/external.mk`:
glibc's `user-defined-trusted-dirs`). It passes over the 64-bit libraries in the first two as the
wrong class, as glibc does for any library that isn't its own kind, and finds its own in
`/usr/lib32`. BasedOS has no `ld.so.cache` (stock's way, with `/etc/ld.so.conf.d/arm-lib32.conf`).

## Tested (2026-11-19)

The kernel has `CONFIG_COMPAT=y`. After the update PortMaster's `device_info.txt` reports
`DEVICE_HAS_ARMHF="Y"` and the `armhf` capability, once its cached
`device_info_spruce_gkd_350h_ultra.env` (in PortMaster's folder) is removed: it keeps the old
answer until its own version changes. That cache had also kept stock's glibc 2.40.

All 68 of PortMaster's ready-to-run 32-bit-only ports are GameMaker games on the 32-bit
gmloader. Eight were installed with PortMaster's own installer and run from spruce's Ports system:
Sokobrawn, Everpatch, Reverse Bros, Snaklipse, Operius, Maldita Castilla and Bumpers &
Broadswords run upright and full width on BasedOS's 32-bit SDL2 and the 32-bit Mali driver
(Sokobrawn: pad checked, quitting from its menu returns to spruce). Sulka doesn't start:
its gmloader needs `libcrypto.so.1.1` (OpenSSL 1.1), which the other ports carry in their own
`libs/` and Sulka's package doesn't (stock's `/usr/lib32` doesn't have it either; ArkOS's does).

The 32-bit ports that aren't GameMaker (Braid, Super Meat Boy, Shovel Knight, Serious Sam,
SteamWorld Dig and Heist on the Weston pack, ...) need the buyer's own game files and are untested.

## Not there

- **No 32-bit LuaJIT.** Buildroot builds it only with a 32-bit host compiler (`gcc-multilib` in
  WSL). LÖVE ports bring their own.
- **No gconv modules for the 32-bit iconv().** glibc looks for them in `/usr/lib/gconv`, the
  64-bit ones; only its built-in conversions (UTF-8, ASCII, Latin-1, UCS-2/4) work.
- **No 32-bit Vulkan.** Stock's armhf Vulkan is Mesa's PanVK, not Mali's.
- **No 32-bit RetroArch** (spruce's `DEVICE_HAS_32_BIT_RA`): not needed for ports.

## Sizes

First build (2026-11-19): the 32-bit libraries are 21.5 MiB of the system layer (108 paths from
the 32-bit root, `base32-report.txt` in the build's work folder, plus SDL2 and librga); the
system layer went to 28.7 MB compressed. The 32-bit Mali driver adds 38 MB to the vendor layer.
