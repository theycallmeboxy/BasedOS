# What PortMaster's ports need from the system

PortMaster doesn't publish a list of the libraries a system must provide: its packaging guide
asks ports to carry anything unusual in `libs.<arch>` and leaves "usual" undefined (2026-11-19).
So this is measured from the ports themselves.

## Method (2026-11-19)

PortMaster's catalogue of that day: all 1,511 ports (31 GB) and all 67 runtimes (Godot, Mono,
.NET, Java, Python, Weston, ...; 2.3 GB), downloaded to the PC (never to the device), each checked
against the catalogue's MD5.
`tools/pm-libscan.py` reads every ELF file in each port (and each runtime, unpacked): what it
needs (DT_NEEDED), less what the port ships (any `.so` in it) and what the runtimes it names
ship, is what it needs from the system. That is checked against BasedOS (64-bit `/usr/lib`,
32-bit `/usr/lib32`, the build of 2026-11-19) and stock ROCKNIX (`/usr/lib`, its compat folder,
`/usr/lib32`). The full table is [portmaster-libscan.md](portmaster-libscan.md).

Not seen by this: libraries loaded with `dlopen()` (SDL's ALSA and udev, GL through GL4ES),
and the libraries of x86 games run by box64/box86 (the game's binaries come from the buyer). A port whose zip has several binaries counts if any of them needs a missing
library, even one the port might not run on this device. GameMaker's Android libraries (which ask
for bionic's `libc.so`, `liblog.so`; gmloader supplies those) are not counted.

## Results

| | 64-bit ports | 32-bit ports |
|---|---|---|
| With binaries that load system libraries | 1,075 | 252 |
| Needing a library BasedOS lacks | **392** | 18 |
| ... of which stock ROCKNIX has every one | 377 | 3 |

64-bit, ports still needing a missing library if BasedOS adds:

| Added | Ports left |
|---|---|
| nothing (today) | 392 |
| **tier 1**: libvorbisfile, SDL2_mixer, OpenAL, mpg123, libmodplug, SDL2_gfx, SDL2_net, opusfile, speex, libtheora, pixman, GMP, and glib's gobject/gmodule/gio (built already, not installed) | 136 |
| **+ PulseAudio's client libraries** (`libpulse-simple`, `libpulse`; no daemon). Linked by the `libmikmod.so.3` (59 ports) and `libfluidsynth.so.1`/`.2` (59) that ports bundle, built with a PulseAudio output; through SDL_mixer they decode into SDL's buffers and don't use it, but the library must be there for them to load | 73 |
| + cairo, GnuTLS, readline 8, nghttp2, libidn2, libgcrypt, libgpg-error, fribidi, WildMidi | 47 |
| + the X11 client libraries (linked, not used, by Aleph One, Doom Engines and the Java runtimes) | 45 |

The top missing ones: libvorbisfile 180 ports, SDL2_mixer 135, OpenAL 127, libpulse-simple 82,
gobject 48, mpg123 44. All in Buildroot.

What's left after all of that is old ABI versions Buildroot can't build (stock has most of them in
its compat folder): FFmpeg 4 (`libavcodec.so.58` and family, 10 ports), FLAC 1.3
(`libFLAC.so.8`, 13), OpenSSL 1.1 (2), readline 7 (2), and a few single cases (SDL 1.2, librga 2,
sndio, JACK, ICU 66).

32-bit: adding dbus, libgpg-error, LAME and glib's gobject/gmodule takes 18 to 14. The 14 left are
mostly OpenSSL 1.1 (`libcrypto.so.1.1`: Climb, Super Hydorah, Mable and the Wood, Relic Hunters,
Sulka and two more), which stock's `/usr/lib32` lacks too: those ports were made for another
system.

Tools ports call by bare name: `zip` (246 ports, mostly GameMaker setup steps), `unzip` (44),
`python3` (19), `mono`/`java`/`dotnet` (their runtimes provide them). spruce supplies `zip`
(`spruce/bin64`) and `python3` (`spruce/flip/bin`) on the ports' `PATH`; BusyBox has `unzip`.
Only one port calls a system `box64` (Super Hexagon). No port uses ROCKNIX's `clibs`: its compat
folder reaches ports only through ROCKNIX's own `get_controls`.

## Recommendation

Tier 1 and PulseAudio's client libraries for 64-bit, and the four for 32-bit: all Buildroot
packages, a few MB, and they take the 64-bit ports with a missing library from 392 to 73. The
rest (old ABIs) only if particular ports are wanted, as a separate compat folder rather than on
the normal library path.
